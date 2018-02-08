module Replicator
  module Providers
    require_relative File.join('..', '..', 'lib', 'helper')
    require_relative File.join('provider')

    # Class extract data from source or destination tables
    # it retrieve batches of data
    # Clients need subscribe to the data
    class Extractor < Provider

      attr_reader :update_time, :keys

      def to_s
        Thread.current[:name]
      end

      def inspect
        to_s
      end

      def updated_at_field
        @entity_config[:src][:updated_at_field]
      end

      def pk_field
        @entity_config[:src][:pk]
      end

      # Get data from source
      def messages(fields, limit)
        raise NotImplementedError, 'Implement this method in a child class - messages'
      end

      # Get last item from source
      def last_item

        filter = []
        unless @entity_config[:src][:condition].nil?
          filter << @entity_config[:src][:condition]
        end

        key = query([], filter, ["#{updated_at_field} DESC", "#{pk_field} DESC"], 1)[0]

        if key.empty?
          {updated_at_field => '1970-01-01 00:00:00', pk_field => 0}
        else
          key
        end

      end

      # Get last keys from source
      def last_keys

        filter = []
        unless @entity_config[:src][:condition].nil?
          filter << @entity_config[:src][:condition]
        end

        filter << %{ "#{updated_at_field}" = '#{last_item[updated_at_field]}' }

        # Return only private keys values
        query([pk_field], filter).map { |item| item[pk_field] }

      end

      # Common filter depends on entity properties
      def get_filter
        filter = super
        filter << @entity_config[:src][:condition] unless @entity_config[:src][:condition].nil?
        filter
      end

    end
  end
end
