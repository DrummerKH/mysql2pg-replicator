module Replicator

  # Class for set traders IDS for related entities like ORDERS, DEPOSITS etc...
  class SetIds

    BATCH_SIZE = 10000
    PERIOD = 1 #sec

    def do

      # Database connections pool
      connections = {}

      start = Time.new('1970-01-01 00:00:00')
      loop do

        if Time.now - start > PERIOD

          start = Time.now

          Main.init_pools do |broker, platform, server, entity|

            @entity_config = $config[:entity_config][platform.intern][entity.intern]

            # If for given entity need set IDS
            if @entity_config[:set_id]

              # Get config of entity where get IDS for given entity
              @source_entity_config = $config[:entity_config][platform.intern][@entity_config[:set_id][:source_entity].intern]

              # make database connection if not exists in pool
              unless connections.include? broker.intern
                connections[broker.intern] = Helper.pg_connect(broker.intern)
              end

              # Get database connection from pool
              conn = connections[broker.intern]

              result = conn.exec(%[
                UPDATE "#{@entity_config[:dst][:schema]}"."#{@entity_config[:dst][:table]}" as o SET trader_id = x.id FROM
                  (
                    SELECT id, account, platform_pointer
                    FROM "#{@source_entity_config[:dst][:schema]}"."#{@source_entity_config[:dst][:table]}"
                    WHERE "#{@source_entity_config[:dst][:platform_pointer_field]}" = '#{platform.intern}_#{server.intern}'
                  ) as x
                  WHERE x.account = o.internal_trader_id AND x.platform_pointer = o.platform_pointer
                  AND o.id IN (
                                SELECT id FROM "#{@entity_config[:dst][:schema]}"."#{@entity_config[:dst][:table]}"
                                WHERE "#{@entity_config[:dst][:platform_pointer_field]}" = '#{platform.intern}_#{server.intern}' AND trader_id IS NULL
                                LIMIT #{BATCH_SIZE}
                              )
              ])

              $log.debug("#{broker.upcase}:#{platform.upcase}:#{server.upcase}:#{entity.upcase}:SETIDS") {"Handled trader IDs #{result.cmd_tuples}"} if result.cmd_tuples > 0
            end
          end

          # Break the loop of script receives TERM signal
          break if $kill

          sleep 1

        end

      end

    end


  end
end
