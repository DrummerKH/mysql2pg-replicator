#!/usr/bin/ruby2.3
require 'rubygems'
require 'bundler/setup'

require 'pg'
require 'json'
require 'daemons'
require 'mysql2'
require 'net/http'
require 'time'
require 'bunny'

require_relative File.join('config', 'config')
require_relative File.join('lib', 'gdm_logger')
require_relative File.join('bin', 'processes', 'signals')

# Load configs
$config = Replicator::Config.new.load.config

$config[:env][:process_name] ||= 'gdm-replicator'

# This is for correct log output to STDOUT with docker
$stdout.sync = true

# Init log variable
$log = Replicator::GdmLogger.new(STDOUT)

require_relative File.join('bin', 'main')


# Text that will be showed on 'ruby replicator.rb' command
# Includes also information for monitoring state of replication
# 1. Command: ruby replicator.rb --get-pools
#  Returns the json with defined pools. It looks like:
#     [["gdm","mt4","live20","traders"],["gdm","mt4","live20","credits"],...]
#     [[BROKER, PLATFORM, SERVER, ENTITY],...]
#  If specify --zabbix option then it returns {"data":[{"{#BROKER}":BROKER,"{#PLATFORM}":PLATFORM,"{#SERVER}":SERVER,"{#ENTITY}":ENTITY},...]}
#
# 2. Command: ruby replicator.rb status --lag broker=gdm server=live20 platform=mt4 entity=credits
#  Shows the current lag in seconds between source database nad destination for specified pool. Returns just integer

# Get lag for specified pool
if ARGV.include? '--lag'

  # Parse command line arguments
  # They are looks like --lag broker=gdm server=live20 platform=mt4 entity=credits
  items = {}
  ARGV.each do |item|
    i = item.split('=')
    i[1] ||= true
    items[i[0].intern] = i[1]
  end

  begin
    worker = ''

    # Some validation
    unless items[:broker]
      raise 'broker argument is not present'
    end

    unless items[:platform]
      raise 'platform argument is not present'
    end

    unless items[:server]
      raise 'server argument is not present'
    end

    unless items[:entity]
      raise 'entity argument is not present'
    end

    worker =  Replicator::Worker.new(items[:broker], items[:platform], items[:server], items[:entity], {})
    puts worker.status[:lag]

  rescue Exception => msg
    Replicator::Helper.error(msg, worker)
    puts 'ERROR: See log for details'
  end
  exit(0)

elsif ARGV.include? '--get-pools'
  # Get list of pools

  pools = []
  if ARGV.include? '--zabbix'
    pools = {data:[]}
  end

  Replicator::Main.init_pools do |broker, platform, server, entity|
    if ARGV.include? '--zabbix'
      pools[:data] << {
          :'{#BROKER}' => broker,
          :'{#PLATFORM}' => platform,
          :'{#SERVER}' => server,
          :'{#ENTITY}' => entity,
      }
    else
      pools << [broker, platform, server, entity]
    end

  end

  puts pools.to_json
  exit(0)
end


Daemons.run_proc($config[:env][:process_name], {force_kill_waittime: 60}) do

  $base_path = __dir__

  # Init log variable
  $log = Replicator::GdmLogger.new(STDOUT)

  # Handle process signals
  trap 'TERM', proc { Replicator::Signals.term }
  trap 'HUP', proc { Replicator::Signals.hup }

  # Recreate log file pointer on reload signal
  Replicator::Signals.subscribe('hup') do
    $log = Replicator::GdmLogger.new(STDOUT)
  end

  # Get command line option
  opts = [].to_set
  opts << :clear if ARGV.include? 'clear'

  $log.info('Replicator::Main') {'Starting workers...'}

  Replicator::Main.launch(opts)

end