module Replicator

  # Class for get delete messages from source and delete according rows from destination
  class Delete

    # How often gather delete messages
    DELETE_PERIOD = 5 #sec

    def initialize(broker, platform, server, entity, opts)

      Thread.current[:broker_id] = @broker = broker
      Thread.current[:platform]  = @platform  = platform
      Thread.current[:server]    = @server    = server
      Thread.current[:entity]    = @entity    = entity

      Thread.current[:entity_config] = @entity_config = $config[:entity_config][@platform.intern][@entity.intern]

      # Init threshold log
      Thread.current[:threshold_log] = ThresholdLog.new(self, $config[:env][:time_to_log_threshold])
      @source_connection = Helper.mysql_connect

      # Make modifier instance
      @destination = opts[:destination]

      # Get cache instance
      @cache = opts[:cache]

    end

    def to_s
      Thread.current[:name].to_s+':DELETE'
    end

    def inspect
      to_s
    end

    def launch

      $log.info(self) {'Delete worker launched'}

      start = Time.new('1970-01-01 00:00:00')
      loop do

        if Time.now - start > DELETE_PERIOD

          start = Time.now

          records = @source_connection.query("SELECT * FROM `#{$config[:env][:mysql][:dbname]}`.`#{$config[:env][:mysql][:trx_table]}`
                                    WHERE broker_id='#{@broker}' AND platform='#{@platform}' AND server='#{@server}' AND entity='#{@entity}'").to_a

          if records.length > 0

            ids = []
            pks = []

            # Add items to the delete queue
            records.each do |item|
              Plugins::fire(Plugins::PRE_ACTION, Plugins::ON_DELETE, @broker, @platform, @server, @entity, item, @entity_config)

              @destination.delete(item['pk'])
              @cache.delete item['pk'] unless @cache.nil?

              ids << item['id'] # For delete rows from transaction table
              pks << item['pk'] # For show in logs primary keys of entities that have been deleted
            end

            # launch queue
            @destination.commit

            # Delete messages from source (ACK)
            @source_connection.query("DELETE FROM `#{$config[:env][:mysql][:dbname]}`.`#{$config[:env][:mysql][:trx_table]}` WHERE id IN (#{ids.join(',')})")

            records.each do |item|
              Plugins::fire(Plugins::POST_ACTION, Plugins::ON_DELETE, @broker, @platform, @server, @entity, item, @entity_config)
            end

            $log.info(self) {"#{records.length} row have been deleted: #{pks.join(',')}"}
          end

        end

        # Break the loop of script receives TERM signal
        break if $kill

        sleep 1
      end

    end

  end

end