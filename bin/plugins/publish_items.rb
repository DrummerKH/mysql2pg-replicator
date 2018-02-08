module Replicator

  # Plugin for Risk Management
  class RiskPlugin

    # Send items to rabbitmq queue
    Plugins::subscribe(:pre, :worker) do |broker, platform, server, entity, item|

      payload = {
          action: 'upsert',
          broker: broker,
          platform: platform,
          server: server,
          entity: entity,
          item: item
      }.to_json

      Thread.current[:rmq_exchange].publish(payload, routing_key: "#{broker}.#{platform}.#{server}.#{entity}")

    end

    # Send deletion items to rabbitmq queue
    Plugins::subscribe(:pre, :delete) do |broker, platform, server, entity, item|

      payload = {
          action: 'delete',
          broker: broker,
          platform: platform,
          server: server,
          entity: entity,
          item: item
      }.to_json

      Thread.current[:rmq_exchange].publish(payload, routing_key: "#{broker}.#{platform}.#{server}.#{entity}")

    end

  end
end
