class Sumo
	def launch
		ami = config['ami']
		raise "No AMI selected" unless ami

		create_keypair unless File.exists? keypair_file

		result = ec2.run_instances(
			:image_id => ami,
			:instance_type => config['instance_size'] || 'm1.small',
			:key_name => 'sumo'
		)
		result.instancesSet.item[0].instanceId
	end

	def list
		result = ec2.describe_instances
		return [] unless result.reservationSet

		instances = []
		result.reservationSet.item.each do |r|
			r.instancesSet.item.each do |item|
				instances << {
					:instance_id => item.instanceId,
					:status => item.instanceState.name,
					:hostname => item.dnsName
				}
			end
		end
		instances
	end

	def terminate(instance_id)
		ec2.terminate_instances(:instance_id => [ instance_id ])
	end

	def config
		@config ||= read_config
	end

	def sumo_dir
		"#{ENV['HOME']}/.sumo"
	end

	def read_config
		YAML.load File.read("#{sumo_dir}/config.yml")
	rescue Errno::ENOENT
		raise "Sumo is not configured, please fill in ~/.sumo/config.yml"
	end

	def keypair_file
		"#{sumo_dir}/keypair.pem"
	end

	def create_keypair
		keypair = ec2.create_keypair(:key_name => "sumo").keyMaterial
		File.open(keypair_file, 'w') { |f| f.write keypair }
		File.chmod 0600, keypair_file
	end

	def ec2
		@ec2 ||= EC2::Base.new(:access_key_id => config['access_id'], :secret_access_key => config['access_secret'])
	end
end
