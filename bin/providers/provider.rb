module Replicator
  class Provider

    def initialize(conn, broker, platform, server, entity)

      @broker, @platform, @server, @entity = broker, platform, server, entity
      @pointer   = "#{@platform}_#{@server}".intern

      @connection = conn

      # Entity config
      @entity_config = $config[:entity_config][@platform.intern][@entity.intern]
      @env_config = $config[:env]

      # How often get data from source
      if not @entity_config[:extract_period].nil?
        @cfg_period = @entity_config[:extract_period]
      else
        @cfg_period = $config[:env][:extract_period].to_f
      end

      # How many rows need get for one request
      if not @entity_config[:extract_period].nil?
        @cfg_batch = @entity_config[:grab_count_rows]
      else
        @cfg_batch = $config[:env][:grab_count_rows]
      end

      # Store keys with the same max updated_at field value for each iteration, that these keys can send to select for next iteration
      # because of minimum of update field value is second
      @keys = []

      # Update time
      @update_time = '1970-01-01 00:00:00'
    end

    # Subscribe to gather data
    # +start_from+ - from what time of last modify field need to start gathering
    # +last_keys+ - last updated primary keys of entity with equal modified time value (these keys will excluded from first(on start) query)
    # +infinite+ - the subscribe loop infinite or not.
    #              If the loop is infinite then it can be break when script is end or subscriber send 'break' command
    #              If the loop is not infinite it will break when all data will be gathered, and SELECT request returns empty.
    # +batch+ - number of rows need to get from one iteration
    # +fields+ - fields that must to be gathered
    # +on_kill+ - specify lambda function that must to be called when script receive TERM signal (will be stopped)
    # +block+ - function for processing gathered data
    def subscribe(
        start_from: '1970-01-01 00:00:00',
        last_keys: [],
        infinite: false,
        batch: @cfg_batch,
        fields: @entity_config[:fields_corresponds].keys,
        on_kill: nil,
        &block)

      @keys = last_keys
      @update_time = start_from

      $log.debug(self) { "Last updated time #{@update_time}" }

      start_time = Time.new('1970-01-01 00:00:00')

      loop do

        if Time.now - start_time >  @cfg_period

          start_time = Time.now

          # Proceed subscriber
          handled = proceed(batch, fields, &block)

          # End loop if infinite = false and was not rows handled (end of stream)
          break unless infinite || handled > 0

        end

        if $kill
          # If TERM signal received call +on_kill+ function if it specified and break
          on_kill.call if on_kill
          break
        end

        sleep 0.01

        # Clean threshold log for each iteration
        Thread.current[:threshold_log].clean
      end

    end

    # Proceed subscriber
    def proceed(batch, fields, &block)

      messages_time = Time.now

      # Get data
      rows = messages(fields, batch)

      Thread.current[:threshold_log].add "Getting #{rows.length} rows", (Time.now - messages_time).round(3)

      if rows.length > 0

        # Clear keys if last updated_time is not equal to current updated_time
        # If equal it mean that we need reject from select last keys also
        @keys.clear unless @update_time == rows.last[updated_at_field]

        # Update last updated_at value
        @update_time = rows.last[updated_at_field]

        # Add keys with same max updated_at value from current iteration to the @keys
        rows.each do |item|
          if item[updated_at_field] == @update_time
            @keys << item[pk_field]
          end
        end

        # Call to subscriber block
        block.call(rows)
      end

      #
      # Hack
      #
      # In case of in the database on one any rows for specified entity
      # we need set update time to the current time minus some seconds, if updated time still UNIX 0.
      # Otherwise the updated time will be constantly UNIX timestamp 0
      # and replicator will make requests with very big date range (it can down any databases :)
      if  @update_time == '1970-01-01 00:00:00'
        @update_time = (Time.now - 300).to_s # muns 5 minutes just in case
      end

      rows.length

    end

    # Common filter for all entities
    def get_filter
      filter = []

      filter << %{ #{ updated_at_field } >= '#{@update_time}' }

      unless @keys.empty?

        # If last keys is not empty, add them to the filter
        filter << %{
            (
              #{ pk_field } NOT IN ('#{@keys.join("','")}')
              OR
              #{ updated_at_field } != '#{@update_time}'
            )
          }
      end

      filter

    end

    # Order of response for all entities
    def get_order
      order = []
      order << updated_at_field
      order << pk_field
      order
    end

  end
end