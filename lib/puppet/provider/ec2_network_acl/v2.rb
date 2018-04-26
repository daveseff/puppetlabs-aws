require_relative '../../../puppet_x/puppetlabs/aws'

Puppet::Type.type(:ec2_securitygroup).provide(:v2, :parent => PuppetX::Puppetlabs::Aws) do
  confine feature: :aws

  mk_resource_methods
  remove_method :tags=

  def self.instances
    regions.collect do |region|
      begin
        vpc_names = {}
        vpc_response = ec2_client(region).describe_vpcs()
        vpc_response.data.vpcs.each do |vpc|
          vpc_name = extract_name_from_tag(vpc)
          vpc_names[vpc.vpc_id] = vpc_name if vpc_name
        end

        acl_names = {}
        acls = ec2_client(region).describe_network_acls.collect do |response|
          response.data.network_acls.collect do |acl|
            acl_names[acl.network_acl_id] = extract_name_from_tag(acl)
            acl
          end
        end.flatten
        acls.collect do |acl|
          new(network_acl_to_hash(region, acl, vpc_names))
        end.compact
      rescue Timeout::Error, StandardError => e
        raise PuppetX::Puppetlabs::FetchingAWSDataError.new(region, self.resource_type.name.to_s, e.message)
      end
    end.flatten
  end

  def self.security_group_to_hash(region, acl, vpcs)
    {
      id: acl.network_acl_id,
      ensure: :present,
      #ingress: format_rules(region, :ingress, acl, groups),
      #egress: format_rules(region, :egress, acl, groups),
      vpc: vpcs[acl.vpc_id],
      vpc_id: acl.vpc_id,
      region: region,
      tags: remove_name_from_tags(acl),
    }
  end

  def ec2
    ec2_client(target_region)
  end

  def exists?
    Puppet.info("Checking if Network ACL #{name} exists in region #{target_region}")
    @property_hash[:ensure] == :present
  end

  def create
  end

  def ingress=(value)
    authorize_rules(value, :ingress, @property_hash[:ingress])
  end

  def egress=(value)
    authorize_rules(value, :egress, @property_hash[:egress])
  end

  def destroy
    Puppet.info("Deleting Network ACL #{name} in region #{target_region}")
    ec2.delete_security_group(
      group_id: @property_hash[:id]
    )
    @property_hash[:ensure] = :absent
  end

