require_relative '../../puppet_x/puppetlabs/property/tag.rb'
require_relative '../../puppet_x/puppetlabs/property/region.rb'
require 'puppet/property/boolean'

Puppet::Type.newtype(:ec2_vpc_network_acl) do
  @doc = 'type representing an EC2 Network ACL'

  ensurable

  newparam(:name, namevar: true) do
    desc 'The name of the network ACL'
    validate do |value|
      fail 'Volume must have a name' if value == ''
      fail 'name should be a String' unless value.is_a?(String)
    end
  end

  newproperty(:vpc) do
    desc 'A VPC to which the group should be associated'
    validate do |value|
      fail 'vpc should be a String' unless value.is_a?(String)
    end
  end

  newproperty(:id) do
    desc 'The unique identifier for the security group'
  end

  newproperty(:region, :parent => PuppetX::Property::AwsRegion) do
    desc 'the region in which to launch the security group'
  end

  newproperty(:tags, :parent => PuppetX::Property::AwsTag) do
    desc 'the tags for the volume'
  end

  newproperty(:associations, :array_matching => :all) do
    desc 'Network ACL subnet associations'
    validate do |value|
      fail 'rule should be a Hash' unless value.is_a?(Hash)
    end
  end

  newproperty(:entries, :array_matching => :all) do
    desc 'ACL rule'
    validate do |value|
      fail 'rule should be a Hash' unless value.is_a?(Hash)
    end
  end
end
