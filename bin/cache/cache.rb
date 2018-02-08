module Replicator

  require 'digest'
  require 'openssl'
  require_relative File.join('providers', 'redis')

  # Class implements caching system
  # On load it loads destination data to the memory,
  # Worker can check very fast in each time moment - whether exists given row or not in destination tables,
  # Its faster than check form database.
  # It allows separate insert and update statements instead of using "UPSERT" implementation.
  # Faster applying changes to the destination database.
  # Also class saves memory cache to the disk in separate commit thread (main thread time not spend time on it),
  # It allows on each reload get cache from the disk instead of reloading from destination database.
  # It has system for validate cache, and rebuild it when validate was not checked (on crash for example)
  class Cache

    module Keys
      CHECKPOINT_KEY_NAME = 'checkpoint_key'
      CHECKPOINT_KEY_NUM_DEFAULT = '0'
      CHECKPOINT_KEY_TIME_DEFAULT = '00000000T000000.000000'
      CHECKPOINT_KEY_DEFAULT = "#{CHECKPOINT_KEY_NUM_DEFAULT}-#{CHECKPOINT_KEY_TIME_DEFAULT}"
    end

    def initialize(source:, provider:)

      # Saved added keys among commits
      @intermediate_data = []
      @intermediate_checksum = {}

      # Initial checkpoint key value
      @checkpoint_key = Keys::CHECKPOINT_KEY_DEFAULT

      # Check whether cache was changed among commits
      @cache_changed = false

      @destination = source

      # Cache key of the entity
      if Thread.current[:entity_config][:cache_key].nil?
        @key = Thread.current[:original_name].to_s
      else
        @key = "#{Thread.current[:short_name].to_s}:#{Thread.current[:entity_config][:cache_key].upcase}"
      end

      @thread_name = Thread.current[:name].to_s

      # Length of cache of previous commit
      @prev_cache_length = 0

      # Get dynamically class instance from string like "Replicator::Providers::Source::TRADO"
      get_instance = lambda do |path|
        path.split('::').inject(Object) {|o,c| o.const_get c}
      end

      # Load cache provider
      @provider = get_instance.call("Replicator::CacheModule::Providers::#{provider}").new(key: @key)

      # In case of cache invalid, the cache will be build, and this flag set to true
      @first_build = false
    end

    def inspect
      to_s
    end

    def to_s
      @thread_name
    end

    # Check whether loading cache is valid
    def valid?
      destination_key = @destination.get_checksum # Get sum from destination nDB

      $log.debug(self) {"Cache: Cache checkpoint key - #{@checkpoint_key}"}
      $log.debug(self) {"Cache: Destination checkpoint key - #{destination_key}"}

      destination_key == @checkpoint_key
    end

    # Clear the cache
    def clear
      @provider.clear                                # Clear cache provider cache
      @checkpoint_key = Keys::CHECKPOINT_KEY_DEFAULT # Clear checkpoint
    end

    # Prepare cache variables
    def prepare
      checkpoint_key = @provider.get_checkpoint_key
      @checkpoint_key = checkpoint_key unless checkpoint_key.nil?
      @checkpoint_parts = @checkpoint_key.split('-')
      self
    end

    # Load cache to the memory
    def build

      if ! valid? # If cache is invalid rebuild it from destination

        @first_build = true

        #total = @destination.get_count # Get total existing rows in destination
        count = 0

        #$log.info(self) {"Cache: Invalid, rebuilding... #{total} rows gonna add to the cache"}
        $log.info(self) {'Cache: Invalid, rebuilding...'}

        # Clear cache totally
        clear

        total_time = Time.now

        # Gets batches from destination and put to the cache
        @destination.subscribe(
            fields: [::Thread.current[:entity_config][:dst][:pk]],
            batch: $config[:env][:initial_cache_batch_size]
        ) do |rows|

          loop_time = Time.now

          # Adding keys to the cache
          rows.each do |row|
            add(row[::Thread.current[:entity_config][:dst][:pk]], row[::Thread.current[:entity_config][:dst][:updated_at_field]])
          end

          # Save cache to the disk
          commit

          count += rows.length
          #$log.info(self) {"Cache: Progress #{count}/#{total} - #{ ((count.to_f/total)*100).round(2) }% completed. Time #{(Time.now-loop_time).round(3)} sec"}
          $log.info(self) {"Cache: Progress #{count} rows completed. Time #{(Time.now-loop_time).round(3)} sec"}
        end

        #$log.info(self) {"Cache: Building completed. #{total} was added to cache. Time #{(Time.now-total_time).round(3)} sec"}
        $log.info(self) {"Cache: Building completed. #{count} was added to cache. Time #{(Time.now-total_time).round(3)} sec"}

      else

        $log.info(self) {'Cache: Valid'}
      end

      @first_build = false

    end

    # Get multiple values from the cache
    def get_keys(arr)
      @provider.get_specified_values(arr)
    end

    # Add keys to the cache
    def add(key, updated_at)

      pk_type_string = false
      pk_type_string = true unless ::Thread.current[:entity_config][:dst][:pk_type_string].nil?

      if pk_type_string
        key = key.to_s
      else
        key = key.to_i
      end

      update_checksum(updated_at)

      @intermediate_data << key   # Add key to temporary store

      @cache_changed = true       # Set cache - "changed"
    end

    # Update cache
    def update(key, updated_at)
      update_checksum(updated_at)
      @cache_changed = true
    end

    # Update checksum
    def update_checksum(updated_at)

      # Here is the magic
      # If checkpoint time is equal to currently handling row
      # Means we need start calculate checkpoint from data stored in cache
      if !@first_build and @checkpoint_parts[1] != Keys::CHECKPOINT_KEY_TIME_DEFAULT and
          updated_at == Time.parse(@checkpoint_parts[1]).strftime('%Y-%m-%d %H:%M:%S.%6N')

        @intermediate_checksum.clear
        @intermediate_checksum[updated_at] = @checkpoint_parts[0].to_i
        @checkpoint_parts[1] = Keys::CHECKPOINT_KEY_TIME_DEFAULT

      elsif @intermediate_checksum[updated_at].nil?

        # Else checkpoint date is not equal to time of currently updating row
        # Then we start calculating checkpoint from scratch
        @intermediate_checksum.clear
        @intermediate_checksum[updated_at] = 0
      end

      @intermediate_checksum[updated_at] += 1
    end

    # Delete key from the cache
    def delete(key)
      @provider.delete(key)               # Delete key from cache provider
    end

    # Save checkpoint
    def set_checkpoint_key(data)
      updated_at, count = data.first
      @checkpoint_key = "#{count}-#{Time.parse(updated_at).strftime('%Y%m%dT%H%M%S.%6N')}"
      @provider.set_checkpoint_key(@checkpoint_key)
      $log.debug(self) {"Cache: Set checkpoint key to #{@checkpoint_key}"}
    end

    # Save cache and checkpoint to cache provider
    def commit
      @provider.batch_insert(@intermediate_data)

      # Calculate checkpoint
      set_checkpoint_key(@intermediate_checksum) if @cache_changed
      @intermediate_data.clear

      @cache_changed = false
    end

  end

end