# Plugin for handle data before or after any actions
module Replicator
  class Plugins


      # Entities
      ON_DELETE = :delete
      ON_WORKER = :worker

      # Moments
      PRE_ACTION = :pre
      POST_ACTION = :post

      class << self

      @@subscribes = {
          PRE_ACTION => [],
          POST_ACTION => []
      }

      def subscribe(moment, entity, &block)
        @@subscribes[moment] << [entity, block] if block_given?
      end


      def fire(moment, entity, broker, platform, server, data_entity, data, config)

        @@subscribes[moment].each do |i|
          if i[0] == entity

            begin
              i[1].call(broker, platform, server, data_entity, data, config)
            rescue Exception => msg
              Helper.error(msg, 'MainPluginClass')
            end

          end
        end
      end
    end
  end
end