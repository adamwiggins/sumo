
module Sumo
  module Config
    extend self

    def instance_defaults
      { :key_name => key_name,
      :instance_type => instance_type,
      :ami32 => ami32,
      :ami64 => ami64,
      :user => user,
      :security_group => security_group,
      :availability_zone => availability_zone,
      :state => "offline" }
    end

    def cookbooks_url
      config["cookbooks_url"] || "git://github.com/adamwiggins/chef-cookbooks.git"
    end

    def security_group
      config["security_group"] || "sumo"
    end

    def user
      config["user"] || "ubuntu"
    end

    def ia32?
      ["m1.small", "c1.medium"].include?(instance_type)
    end

    def ia64?
      not ia32?
    end

    def ami32
      config["ami32"] || "ami-1515f67c" ## default to ubuntu 9.10 server
    end

    def ami64
      config["ami64"] || "ami-ab15f6c2" ## default to ubuntu 9.10 server
    end

    def availability_zone
      config['availability_zone'] || 'us-east-1d'
    end

    def instance_type
      config['instance_type'] || 'm1.small'
    end

    def access_id
      config["access_id"] || ENV["AWS_ACCESS_KEY_ID"] || (raise "please define access_id in #{sumo_config_file} or in the env as AWS_ACCESS_KEY_ID")
    end
  
    def access_secret
      config["access_secret"] || ENV["AWS_SECRET_ACCESS_KEY"] || (raise "please define access_secet in #{sumo_config_file} or in the env as AWS_SECRET_ACCESS_KEY")
    end

    def ec2
      @ec2 ||= Aws::Ec2.new(access_id, access_secret, :logger => Logger.new(nil))
    end

    def key_name
      config["key_name"] || "sumo"
    end

    def keypair_file
      config["keypair_file"] || "#{sumo_dir}/keypair.pem"
    end

    def validate
      create_security_group

      k = ec2.describe_key_pairs.detect { |kp| kp[:aws_key_name] == key_name }

      if k.nil? 
        if key_name == "sumo"
          create_keypair
        else
          raise "cannot use key_pair #{key_name} b/c it does not exist"
        end
      end
    end

    def connect
      @@con = Aws::ActiveSdb.establish_connection(Config.access_id, Config.access_secret, :logger => Logger.new(nil))
      one_time_setup unless setup?
    end

    def one_time_setup
      puts "ONE TIME SETUP"
      Sumo::Instance.create_domain
    end

    def purge
      puts "PURGE"
      Sumo::Instance.delete_domain
    end

    def setup?
      Sumo::Instance.connection.list_domains[:domains].include? Sumo::Instance.domain
    end

    private

    def config
      @config ||= read_config
    end

    def sumo_config_file
      "#{sumo_dir}/config.yml"
    end

    def sumo_dir
      "#{ENV['HOME']}/.sumo"
    end

    def read_config
      YAML.load File.read(sumo_config_file)
    rescue Errno::ENOENT
      {}
    end

    def create_keypair
      material = ec2.create_key_pair("sumo")[:aws_material]
      File.open(keypair_file, 'w') { |f| f.write material }
      File.chmod 0600, keypair_file
    end

    def create_security_group
      ec2.create_security_group('sumo', 'Sumo')
      ec2.authorize_security_group_IP_ingress("sumo", 22, 22,'tcp','0.0.0.0/0')
    rescue Aws::AwsError
    end
  end
end
