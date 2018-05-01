require_relative '../../../puppet_x/puppetlabs/aws'

Puppet::Type.type(:ec2_vpc_network_acl).provide(:v2, :parent => PuppetX::Puppetlabs::Aws) do
  confine feature: :aws
  confine feature: :retries

  mk_resource_methods
  remove_method :tags=

  def self.instances
    regions.collect do |region|
      begin
        network_acls = []
        acl_response = ec2_client(region).describe_network_acls()
        acl_response.data.network_acls.collect do |acl|
          hash = network_acl_to_hash(region, acl)
          network_acls << new(hash) if has_name?(hash)
        end
        network_acls
      rescue Timeout::Error, StandardError => e
        raise PuppetX::Puppetlabs::FetchingAWSDataError.new(region, self.resource_type.name.to_s, e.message)
      end
    end.flatten
  end

  def self.prefetch(resources)
    instances.each do |prov|
      if resource = resources[prov.name] # rubocop:disable Lint/AssignmentInCondition
        resource.provider = prov if resource[:region] == prov.region
      end
    end
  end

  def self.network_acl_to_hash(region, acl)
    name = extract_name_from_tag(acl)
    config = {
      name: name,
      id: acl.network_acl_id,
      ensure: :present,
      vpc: vpc_name_from_id(region, acl.vpc_id),
      region: region,
      tags: remove_name_from_tags(acl),
    }

    associations = acl.associations.collect do |assc|
      {
        network_acl_association_id: assc.network_acl_association_id,
        network_acl_id: assc.network_acl_id,
        subnet_id: assc.subnet_id,
      }
    end

    entries = acl.entries.reject{|entry| entry.port_range.to_a[0].nil?}.collect do |entry|
      {
        cidr_block: entry.cidr_block,
        egress: entry.egress,
        protocol: entry.protocol,
        from_port: entry.port_range.to_a[0],
        to_port: entry.port_range.to_a[1],
        rule_action: entry.rule_action,
        rule_number: entry.rule_number,
      }
    end

    config[:associations] = associations unless associations.empty?
    config[:entries] = entries unless entries.empty?

    config
  end

  def ec2
    ec2_client(target_region)
  end

  def exists?
    Puppet.info("Checking if Network ACL #{name} exists in region #{target_region}")
    @property_hash[:ensure] == :present
  end

  def create
    Puppet.info("Creating Network ACL #{name} in region #{target_region}")
    vpc = self.class.vpc_id_from_name(target_region, resource[:vpc])
    network_acl = ec2.create_network_acl({vpc_id: vpc})
    acl_id = network_acl[0].network_acl_id

    # Assign tags
    with_retries(:max_tries => 5) do
      ec2.create_tags(
        resources: [acl_id],
        tags: extract_resource_name_from_tag
      ) if resource[:tags]
    end

#    config[:is_default] = 'false' unless resource[:is_default].is_empty?
    associations = resource[:associations]
    associations = [associations] unless associations.is_a?(Array)
    assc_maping = associations.collect do |assc_map|
      {
        network_acl_id: acl_id,
        subnet_id: assc_map['subnet_id'],
      }
    end

    config = {}
    entries = resource[:entries]
    entries = [entries] unless entries.is_a?(Array)
    entry_maping = entries.collect do |entry_map|
      config[:network_acl_id] = acl_id
      config[:cidr_block] = entry_map['cidr_block']
      config[:egress] = entry_map['egress']
      if entry_map['protocol'] == '1' or entry_map['protocol'] == 'icmp'
        config[:port_range] = { from: 1, to: 1, }
        config[:icmp_type_code] = { code: 1, type: 1, }
      else
        config[:port_range] = { from: entry_map['from_port'], to: entry_map['to_port'], }
      end
      config[:protocol] = entry_map['protocol']
      config[:rule_action] = entry_map['rule_action']
      config[:rule_number] = entry_map['rule_number']
      ec2.create_network_acl_entry(config)
    end

    @property_hash[:id] = network_acl[0].network_acl_id
    @property_hash[:ensure] = :present
  end

  def destroy
    Puppet.info("Deleting Network ACL #{name} in region #{target_region}")
    ec2.delete_security_group( network_acl_id: @property_hash[:network_acl_id])
    @property_hash[:ensure] = :absent
  end
end
