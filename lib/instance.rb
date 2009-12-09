
module Sumo
  class Instance < Aws::ActiveSdb::Base
    set_domain_name :sumo_instance

    @@ec2_list = Config.ec2.describe_instances

    def self.search(*names)
      query = names.map { |name| name =~ /(^%)|(%$)/ ? "name like ?" : "name = ?" }.join(" or ")
      self.select(:all, :conditions => names.unshift(query))
    end

    def method_missing(method, *args)
      if all_attrs.include?(method)
        if self[method]
          self[method].first
        else
          nil
        end
      else
        super(method, @args)
      end
    end

    def update_attributes!(args)
      args.each do |key,value|
        self[key] = value
      end
      save
    end

    def all_attrs
      [:name, :ami32, :ami64, :instance_type, :instance_id, :state, :availability_zone, :key_name, :role_list, :security_group, :user, :volumes_json, :elastic_ip]
    end

    def initialize(attrs={})
      super(defaults.merge(uniq_values(attrs)))
    end

    def defaults
      uniq_values(Config.instance_defaults)
    end

    def self.all
      @@all ||= Instance.find(:all)
    end

    def self.untracked
      ids = all.map { |a| a.instance_id }
      @@ec2_list.reject { |e| e[:aws_state] == "terminated" or ids.include?(e[:aws_instance_id]) } 
    end

    def has_ip?
      elastic_ip
    end

    def has_volumes?
      not volumes.empty?
    end

    def volumes
      ## FIXME - just use the darn simpledb array - use put/delete do avoid race conditions
      @volumes ||= JSON.load(volumes_json) rescue {}
    end

    def destroy
      delete
      volumes.each { |mount,v| Sumo::Config.ec2.delete_volume(v) }
      Sumo::Config.ec2.release_address(elastic_ip) if has_ip?
    end

    def before_save
      self["volumes_json"] = volumes.to_json
    end

    def ec2_state
      ec2_instance[:aws_state] rescue "offline"
    end

    def ec2_instance
      @ec2 ||= Config.ec2.describe_instances([instance_id]).first rescue {}
#      @@ec2_list.detect { |i| i[:aws_instance_id] == instance_id }
    end

    def running?
      ## other options are "terminated" and "nil"
      ["pending", "running", "shutting_down", "degraded"].include?(ec2_state)
    end

    def start
      Config.validate ## FIXME

      result = Config.ec2.launch_instances(ami, 
        :instance_type => instance_type, 
        :availability_zone => availability_zone,
        :key_name => key_name,
        :group_ids => [security_group],
        :user_data => '').first

      update_attributes! :instance_id => result[:aws_instance_id]
    end

    def launch
      start
      wait_for_hostname
      wait_for_ssh
      attach_ip
      attach_volumes
      setup_roles
    end

    def terminate
      Config.ec2.terminate_instances([ instance_id ])
      wait_for_termination if volumes.size > 0
      update_attributes! :instance_id => nil
      "#{instance_id} scheduled for termination"
    end

    def console_output
      Config.ec2.get_console_output(instance_id)[:aws_output]
    end

    def ami
      ia32? ? ami32 : ami64
    end

    def ia32?
      ["m1.small", "c1.medium"].include?(instance_type)
    end

    def ia64?
      not ia32?
    end

    def hostname
      ec2_instance[:dns_name] == "" ? nil : ec2_instance[:dns_name]
    end

    def wait_for_hostname
      loop do
        refresh
        return hostname if hostname
        sleep 1
      end
    end

    def wait_for_termination
      loop do
        ec2 = Config.ec2.describe_instances.detect { |i| i[:aws_instance_id] == instance_id }
        break if ec2[:aws_state] == "terminated"
        sleep 1
      end
    end

    def wait_for_ssh
      loop do
        begin
          Timeout::timeout(4) do
            TCPSocket.new(hostname, 22)
            return
          end
        rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH
        end
      end
    end

    def bootstrap_chef
      commands = [
        'sudo apt-get update',
        'sudo apt-get autoremove -y',
        'sudo apt-get install -y ruby ruby-dev rubygems git-core',
        'sudo gem sources -a http://gems.opscode.com',
        'sudo gem install chef ohai --no-rdoc --no-ri',
        "git clone #{Config.cookbooks_url}",
      ]
      ssh(commands)
    end

    def roles
      @roles ||= role_list.split(",") rescue []
    end

    def has_roles?
      not roles.empty?
    end
 
    def setup_roles
      return [] unless has_roles?
      bootstrap_chef 
      roles.each { |r| setup_role(r) }
      fetch_resources
    end

    def setup_role(r)
      commands = [
        "cd chef-cookbooks",
        "sudo /var/lib/gems/1.8/bin/chef-solo -c config.json -j roles/#{r}.json"
      ]
      ssh(commands)
    end

    def ssh(cmds)
      IO.popen("ssh -i #{Config.keypair_file} #{user}@#{hostname} > ~/.sumo/ssh.log 2>&1", "w") do |pipe|
        pipe.puts cmds.join(' && ')
      end
      unless $?.success?
        abort "failed\nCheck ~/.sumo/ssh.log for the output"
      end
    end

    def fetch_resources
      cmd = "ssh -i #{Config.keypair_file} #{user}@#{hostname} 'sudo cat /root/resources' 2>&1"
      out = IO.popen(cmd, 'r') { |pipe| pipe.read }
      abort "failed to read resources, output:\n#{out}" unless $?.success?
      parse_resources(out)
    end

    def add_ip(public_ip)
      ## TODO - make sure its not in use
      update_attributes! :elastic_ip => public_ip
      attach_ip
    end

    def attach_ip
      return unless running? and elastic_ip
      Config.ec2.associate_address(instance_id, elastic_ip)
      refresh
    end

    def attach_volumes
      return unless running?
      volumes.each do |device,volume_id|
        Config.ec2.attach_volume(volume_id, instance_id, device)
      end
    end

    def add_volume(volume_id, device)
      abort("Instance already has a volume on that device") if volumes[device]
      ## TODO make sure its not attached to someone else
      volumes[device] = volume_id
      self[:volumes_json] = volumes.to_json
      save
      Config.ec2.attach_volume(volume_id, instance_id, device) if running?
    end
 
    def parse_resources(raw)
      raw.split("\n").map do |line|
        line.gsub(/localhost/, hostname)
      end
    end

		def connect_ssh
			system "ssh -i #{Sumo::Config.keypair_file} #{user}@#{hostname}"
			if $?.success?
				puts "\nType 'sumo terminate' if you're done with this instance."
			end
		end
    
    def self.attrs
      [:ami32, :ami64, :instance_type, :availability_zone, :key_name, :role_list, :security_group, :user]
    end

    def refresh
      @ec2 = nil
      @volumes = nil
      @roles = nil
      reload
    end

    def to_hash
      hash = {}
      Instance.attrs.each { |key| hash[key] = self.send(key) }
      hash
    end

  end
end

