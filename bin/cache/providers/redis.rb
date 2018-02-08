require 'readthis'

module Replicator
  module CacheModule
    module Providers

      require_relative File.join('..', 'provider_abstract')

      require 'readthis'
      require 'readthis/passthrough'

      class Redis < Replicator::CacheModule::ProviderAbstract

        def initialize(key:)
          @key = key

          Readthis.fault_tolerant = true
          @redis = Readthis::Cache.new(
              redis: {
                  host: $config[:env][:redis][:host],
                  timeout: $config[:env][:redis][:timeout].to_i,
                  driver: :hiredis
              },
              namespace: @key,
              marshal: Readthis::Passthrough,
              compress: true)


          @checkpoint_key = Cache::Keys::CHECKPOINT_KEY_NAME
        end

        # Get value from checkpoint set
        def get_checkpoint_key
          @redis.read(@checkpoint_key)
        end

        # Add values to checkpoint set
        def set_checkpoint_key(value)
          @redis.write(@checkpoint_key, value)
        end

        # Delete cache and checkpoint key totally
        def clear
          @redis.delete_matched("#{@key}:*")
        end

        # Inserting a lot of rows using redis pipeline
        def batch_insert(data)
          hash = Hash[data.collect { |v| [v, '1'] }]
          @redis.write_multi(hash)
        end

        # Get array of values
        def get_specified_values(arr)
          @redis.read_multi(*arr, retain_nils: true)
        end

        # Delete key from set
        def delete(key)
          @redis.delete(key)
        end

        # Returns instance of cache class
        def get_instance
          @redis
        end

      end

    end
  end
end