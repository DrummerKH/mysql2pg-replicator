require 'thread'

require_relative File.join('..', 'lib', 'gdm_logger')
require_relative File.join('..', 'lib', 'helper')
require_relative File.join('worker', 'worker')
require_relative File.join('plugins')
require_relative File.join('set_ids')

project_root = File.dirname(File.absolute_path(__FILE__))

# Load plugins
Dir.glob(project_root + '/plugins/*', &method(:require))

# Load providers
Dir.glob(File.join(project_root, 'providers', '**', '*.rb'), &method(:require))

module Replicator

  # Class launches broker threads
  class Main

    def self.init_pools
      $config[:brokers].each do |broker, data|

        data[:platforms].each do |platform, servers|

          servers.each do |server|

            # Launch the block
            $config[:entity_config][platform].map do |entity, x|

              yield(broker, platform, server, entity)

              # Delay among threads launches (actually mysql connection dropped without it)
              sleep 0.1

            end

          end

        end

      end
    end

    def self.launch(opts)

      $log.info('Replicator::Main') {'Starting workers...'}

      threads = []

      init_pools do |broker, platform, server, entity|
        # Launch the thread, each thread manage knot - broker, platform, server

          t = Thread.new do

            begin
              worker = Worker.new(broker.to_s, platform.to_s, server.to_s, entity, opts).do
            rescue Exception => msg
              Helper.error(msg, worker)
              raise msg
            end

          end

          t.abort_on_exception = true if $config[:env][:stop_on_thread_ex]

          threads << t
      end

      # Add SETIDS thread
      t = Thread.new do

        begin
          setids = SetIds.new.do
        rescue Exception => msg
          Helper.error(msg, setids)
          raise msg
        end

      end

      t.abort_on_exception = true if $config[:env][:stop_on_thread_ex]

      threads << t

      begin

        threads.map(&:join)
        $log.info('Replicator::Main') {'Replicator normally stopped'}

      rescue Interrupt

        $log.info('Replicator::Main') {'Replicator abnormally stopped'}
      end

    end

  end

end