#!/usr/bin/env ruby
# Author: Courtney Cotton <cotton@cottoncourtney.com> 5-26-2015
# Desc: This script takes a list of IPs from a .txt file and grabs the 
# correct subnet/cidr from a provided FTP networks file.

# Libraries/Gems
require 'optparse'
require 'net/ftp'
require 'fileutils'
require 'ipaddr'

# Represents a Example Network, consisting of the subnet name, the cidr and a description
class ExampleNetwork
  attr_accessor :name, :cidr, :description

  def initialize name, cidr, description
    @name = name
    @cidr = IPAddr.new cidr
    @description = description
  end

  # Returns true if a sample ip is present in the range of ipaddresses of this Network
  def includes_ip? ip
    begin
      testip = IPAddr.new ip
      return @cidr.include? ip
    rescue IPAddr::InvalidAddressError
      return false
    end
  end

  # Returns the subnet mask prefix for this particular network.
  def subnet_mask
    @cidr.instance_variable_get("@mask_addr").to_s(2).count('1')
  end
end

# Represents a collection of Example Networks
class ExampleNetworks
  attr_accessor :list

  # Reads a networks.local file and constructs a Berkley Networks object
  def read_from_file filename
    @list = []
    File.readlines(filename).each do |line|
      line = line.split(/\t/)
      unless is_comment? line
        name         = line[0].strip
        cidr         = line[1].strip
        description  = line[2].strip
        @list.push ExampleNetwork.new name, cidr, description
      end
    end
    File.delete(filename)
    self
  end

  # Returns a list of all the subnets defined in ExampleNetworks which the ipaddress is a member of
  def all_subnets_for_ipaddress ipaddress
    subnets = []

    @list.each do |example_network|
      subnets.push example_network.name if example_network.includes_ip? ipaddress
    end

    subnets
  end

  # Returns the most specifc subnet match for an ipaddress
  def subnet_for_ipaddress ipaddress
    # Start with something to compare the next match to
    most_specific_subnet = ExampleNetwork.new nil, '0.0.0.0/0', 'All ips'

    @list.each do |example_network|
      # The most specific subnet match is the one with the greatest subnet mask prefix (i.e. /25 is less specifc thatn /28 )
      if example_network.includes_ip? ipaddress and example_network.subnet_mask > most_specific_subnet.subnet_mask
        most_specific_subnet = example_network
      end
    end

    most_specific_subnet
  end

  private
  def is_comment? line
    line[0].start_with? "#"
  end
end

class ExampleNetworksIpaddressMatcher
  attr_accessor :options

  def initialize
    @options = {}
    OptionParser.new do |opts|
      opts.banner = "Usage: looks up subnet/cidr for ip address"
      opts.on("-f", "--file path/filename", "Example: /path/to/filname.txt") do |f|
          @options[:ipfile] = f
      end
    end.parse!    
  end

  def match_ipaddresses_from_net
    # Get most recent copy of networks.local file.
    unless File.exists? 'networks.local'
      # Change the URL to be the FTP download location of your subnet lists
      ftp = Net::FTP.new('ftp.net.example.edu')
      ftp.login
      files = ftp.chdir('pub')
      files = ftp.list('n*')
      remotefile = 'networks.local'
      ftp.gettextfile(remotefile, localfile = File.basename(remotefile))
      ftp.close
    end

  # Verify required inputs
  abort("ABORTING: ip file not provided, please use ./cidrmagic -f path/to/filename.txt") if options[:ipfile].nil?

    networks = ExampleNetworks.new.read_from_file 'networks.local'

    ip_lines = File.readlines(options[:ipfile]).map do |line|
      line = line.split(/ /)[0]
    end

    infos = []
    subnets_so_far = []

    ip_lines.each do |ip|
      address = ip.strip
      subnets = networks.subnet_for_ipaddress address
      # If subnet has already been printed, no printsies again.
      unless subnets_so_far.include? subnets
        if subnets.name.nil?
          infos.push "#{ip.strip} NO MATCHES"
        else
          infos.push "- '#{subnets.cidr.to_s}/#{subnets.subnet_mask}'      ##{subnets.name} "
          subnets_so_far.push(subnets)
        end
      end
    end
    infos
  end
end

bnim = ExampleNetworksIpaddressMatcher.new
puts bnim.match_ipaddresses_from_net
