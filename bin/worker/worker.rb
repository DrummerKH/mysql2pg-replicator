require 'digest'

require_relative File.join('delete')
require_relative File.join('..', '..', 'lib', 'threshold_log')
require_relative File.join('..', 'cache', 'cache')

module Replicator

  # Worker class, starts as separate thread
  # handles each {broker_id:platform:server:entity} item
  class Worker

    def initialize(broker_id, platform, server, entity, opts)

      Thread.current[:broker_id] = @broker_id = broker_id
      Thread.current[:platform]  = @platform  = platform
      Thread.current[:server]    = @server    = server
      Thread.current[:entity]    = @entity    = entity
      Thread.current[:pointer]   = @pointer   = platform+'_'+server

      # Config of selected entity
      Thread.current[:entity_config] = @entity_config = $config[:entity_config][@platform.intern][@entity.intern]

      # Put put name of class for write in logs of other classes in same thread

      # Short name - name without entity
      Thread.current[:short_name]    = @thread_short_name = %{#{@broker_id.upcase}:#{@platform.upcase}:#{@server.upcase}}
      Thread.current[:name]          = self.to_s
      Thread.current[:original_name] = self.original_name

      Thread.current[:pg_connection] = @pg_connection    = Helper.pg_connect(@broker_id)
      Thread.current[:my_connection] = @mysql_connection = Helper.mysql_connect

      Thread.current[:rmq_exchange]  = rmq_exchange

      # Get destination and sources handler classes if specified
      dst_provider = @entity_config[:dst][:provider] ||= 'GTR'
      src_provider = @entity_config[:src][:provider] ||= @platform.upcase

      # Get dynamically class instance from string like "Replicator::Providers::Source::TRADO"
      get_instance = lambda do |path|
        path.split('::').inject(Object) {|o,c| o.const_get c}
      end

      # Make source handler instance instance
      @src_class = get_instance.call("Replicator::Providers::Source::#{src_provider}")
      @source = @src_class.new(@mysql_connection, @broker_id, @platform, @server, @entity)

      # Make destination handler instance
      @dst_class = get_instance.call("Replicator::Providers::Destination::#{dst_provider}")
      @destination = @dst_class.new(@pg_connection, @broker_id, @platform, @server, @entity)

      # Use caching or not
      @use_cache = (@entity_config[:use_cache] and $config[:env][:use_cache])

      # Set default actions if not specified for entity
      @entity_config[:actions] ||= %w'insert delete update'

    end

    def to_s
      display_name = @entity_config[:display_name] ||= @entity
      %{#{@thread_short_name}:#{display_name.upcase}}
    end

    def original_name
      %{#{@thread_short_name}:#{@entity.upcase}}
    end

    def inspect
      to_s
    end

    def cache_init

      @cache = Cache.new(source: @destination, provider: 'Redis').prepare

      if @entity_config[:actions].include? 'insert'
        # Store data into the cache in case of entity has INSERT action
        @cache.build
      end

    end

    # Get the status of entity replication - difference in seconds between source and destination rows
    def status

      # Get times
      src_time = @source.last_item[@entity_config[:src][:updated_at_field]]
      dst_time = @destination.last_item[@entity_config[:dst][:updated_at_field]]

      unless src_time.instance_of? Time
        src_time = Time.parse(src_time)
      end

      unless dst_time.instance_of? Time
        dst_time = Time.parse(dst_time)
      end

      # Calculate lag
      lag = (src_time - dst_time).to_i

      {
          pool: self.to_s,
          src_time: src_time,
          dst_time: dst_time,
          lag: lag
      }

    end

    # Process the thread
    def do

      $log.debug(self) {'Worker created'}

      # Init threshold log
      Thread.current[:threshold_log] = ThresholdLog.new(self, $config[:env][:time_to_log_threshold])

      # If constant is set then use cache
      cache_init if @use_cache

      # Initialize delete worker if entity has DELETE action
      @thr_del_worker = delete_worker if @entity_config[:actions].include? 'delete'

      listen
    end

    # Launch delete worker as separate thread
    def delete_worker

      rmq = Thread.current[:rmq_exchange]
      t = Thread.new(self) do |name|

        Thread.current[:name] = name
        Thread.current[:rmq_exchange] = rmq
        deleter = Delete.new(@broker_id, @platform, @server, @entity,
                             {
                                 destination: @dst_class.new(@pg_connection, @broker_id, @platform, @server, @entity),
                                 cache: @cache
                             })

        begin
          deleter.launch
        rescue Exception => msg
          Helper.error(msg, deleter)
          raise msg
        end
      end

      # Abort main thread in case child exceptions
      t.abort_on_exception = true if $config[:env][:stop_on_thread_ex]
      t

    end

    # Listen the extractor
    def listen

      # Subscribe callback function
      @source.subscribe(
          start_from: @destination.last_item[@destination.updated_at_field], # Set start from updated time
          last_keys: @destination.last_keys, # Set last updated primary keys
          infinite: true, # Subscribe on infinite loop (actually break on TERM signal)
          on_kill: lambda{on_kill}            # Set callback function that call on kill command (TERM signal)
      ) do |rows|

        # Times for measure
        time = mod_time = Time.now

        updated = 0
        inserted = 0

        keys = []

        rows.each do |row|

          Plugins::fire(Plugins::PRE_ACTION, Plugins::ON_WORKER, @broker_id, @platform, @server, @entity, row, Thread.current[:entity_config])

          if @use_cache

            # If use cache then save batch
            keys << row[@source.pk_field]

          else

            # If cache not uses then upsert (INSERT on DUPLICATE UPDATE)
            if @entity_config[:actions].include? 'insert' or @entity_config[:actions].include? 'update'
              @destination.upsert(row)
            end

          end

        end

        # If cache using
        if @use_cache

          values = @cache.get_keys(keys)

          index = 0
          keys.each do |key|

            if not values[key].nil?

              # If exists then update
              if @entity_config[:actions].include? 'update'
                @destination.update(rows[index])

                # Update cache
                @cache.update(key, rows[index][@entity_config[:src][:updated_at_field]])

                updated += 1

              end

            else

              # If not exists then upsert (INSERT on DUPLICATE UPDATE)
              if @entity_config[:actions].include? 'insert'
                @destination.upsert(rows[index])

                # Add to the cache
                @cache.add(key, rows[index][@entity_config[:src][:updated_at_field]])

                inserted += 1
              end

            end

            index += 1
          end

        end

        ::Thread.current[:threshold_log].add 'Modifier time', (Time.now - mod_time).round(3)

        sql = @destination.sql.dup

        # Commit made changes
        commit

        rows.each do |row|
          Plugins::fire(Plugins::POST_ACTION, Plugins::ON_WORKER, @broker_id, @platform, @server, @entity, row, Thread.current[:entity_config])
        end

        round_time = (Time.now - time).round(3)
        ::Thread.current[:threshold_log].thread_log 'Total time', round_time

        if @use_cache
          $log.info(self) {"#{inserted > 0 ? "Inserted #{inserted} rows. " : ''}#{updated > 0 ? "Updated #{updated} rows. " : ''}#{round_time} sec"}
        else
          $log.info(self) {"Handled #{sql.length}/#{rows.length} rows: #{round_time} sec"}
        end

        # Store threshold log to the log file if round time was exceeded
        ::Thread.current[:threshold_log].store

      end

    end

    # Commit changes (persistent store to the disk)
    def commit(on_kill = false)

      unless @destination.sql.empty?

        $log.debug(self) {'Launch last commit'} if on_kill

        if @use_cache
          cache_time = Time.now

          # And add to the cache
          @cache.commit

          Thread.current[:threshold_log].add 'Cache time', (Time.now - cache_time).round(3)
        end

        pg_time = Time.now
        # Launch SQL commands
        @destination.commit
        Thread.current[:threshold_log].add 'Replicate time', (Time.now - pg_time).round(3)

      end

    end

    # Callback function, what need to do on TERM signal
    def on_kill

      # Commit last changes
      commit(true)

      # Join to the delete worker and wait wile it is done
      @thr_del_worker.join unless @thr_del_worker.nil?

      $log.info(self) {'Shutting down...'}

      # Here the thread is almost shut down
    end

    # Connect to rabbitmq and return exchange
    def rmq_exchange
      rabbitmq_conn = Helper.rabbitmq_connect
      rabbitmq_conn.create_channel.direct('amq.topic')
    end

  end
end