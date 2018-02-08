#------------------------------------------------------------
# The class for modify Broker tables corresponds specified rules
#
# @author Dmitry Hvorostyuk
# @date   16.02.2016
# @copyright GDMFX ltd
#------------------------------------------------------------

module Replicator
  module Providers

    require_relative File.join('provider')

    # Class for modifying destination tables according to config
    class Modifier < Provider

      attr_reader :sql, :last_handled

      # identify modify instance with ID of item (broker:platform:server:entity)
      def initialize(conn, broker, platform, server, entity)

        super

        # Array to store needed SQL commands for applying
        @sql = []

        # Store last added data to @sql
        @last_handled = []

      end

      def to_s
        ::Thread.current[:name]
      end

      def inspect
        to_s
      end

      # Get fields and values for update statement
      def get_update_data(data)

        update_data = []

        to_sql = lambda do |field, src_value|
          update_data << @connection.quote_ident(field.to_s) + "='#{ @connection.escape_string(src_value.to_s) }'"
        end

        data.each do |item|

          src_field = item[0]
          src_value = item[1]

          # Getting destination field
          dst_field = @entity_config[:fields_corresponds][src_field.intern]

          if dst_field

            # If not array make it them
            unless dst_field.kind_of?(Array)
              dst_field = [dst_field]
            end

            # Add to sql
            dst_field.each do |field|
              to_sql.call(field, src_value)
            end

          end

        end

        # Adding custom fields to sql
        unless @entity_config[:dst][:custom_fields].nil?

          @entity_config[:dst][:custom_fields].each do |item|
            to_sql.call(item[0], item[1])
          end

        end

        update_data

      end


      # Get fields and values for insert statement
      def get_insert_data(data)

        @fields, @values = [], []

        found = false

        to_sql = lambda do |dst_field, src_value|
          @fields << @connection.quote_ident(dst_field.to_s)
          @values << "'#{@connection.escape_string(src_value.to_s)}'"
        end

        data.each do |item|

          src_field = item[0] # Field name
          src_value = item[1] # Value

          # Get destination field based on source field
          dst_field = @entity_config[:fields_corresponds][src_field.intern]

          if dst_field

            # If not array make it them
            unless dst_field.kind_of?(Array)
              dst_field = [dst_field]
            end

            # Add to sql each element
            dst_field.each do |field|
              to_sql.call(field, src_value)
            end

            found = true
          end

        end

        # Adding custom fields to sql
        unless @entity_config[:dst][:custom_fields].nil?

          @entity_config[:dst][:custom_fields].each do |item|
            to_sql.call(item[0], item[1])
          end

        end

        if found and not @entity_config[:dst][:platform_pointer_field].nil?

          # Required fields
          to_sql.call(@entity_config[:dst][:platform_pointer_field], @pointer)

        end

        return @fields, @values

      end


      # Add insert statement to @sql
      def insert(data)

        insert_fields, insert_values = get_insert_data(data)

        unless insert_values.empty?
          @sql << %[ INSERT INTO "#{@entity_config[:dst][:schema]}"."#{@entity_config[:dst][:table]}" (#{insert_fields.join(',')}) VALUES (#{insert_values.join(',')});]
          @last_handled = data
        end

      end


      # Add update statement to @sql
      def update(data)

        update_data = get_update_data(data)
        pk = data[@entity_config[:src][:pk]]

        unless  update_data.empty?

          where = []
          where << %["#{pk_field}" = '#{pk}']
          where << %["#{@entity_config[:dst][:platform_pointer_field]}" = '#{@pointer}] unless @entity_config[:dst][:platform_pointer_field].nil?

          @sql << %[
                    UPDATE "#{@entity_config[:dst][:schema]}"."#{@entity_config[:dst][:table]}"
                    SET #{update_data.join(',')}
                    WHERE #{where.join(' AND ')}';
                    ]
          @last_handled = data
        end
      end


      # Add upsert statement to @sql
      def upsert(data)

        # Get data for update statement
        update_data = get_update_data(data)

        unless update_data.empty?

          # Get data for insert statement
          insert_fields, insert_values = get_insert_data(data)

          on_conflict = []
          on_conflict << %["#{pk_field}"]

          where = []
          where  << %[t."#{pk_field}" = EXCLUDED."#{pk_field}"]


          unless @entity_config[:dst][:platform_pointer_field].nil?
            on_conflict << %["#{@entity_config[:dst][:platform_pointer_field]}"]
            where  << %[t."#{@entity_config[:dst][:platform_pointer_field]}" = EXCLUDED."#{@entity_config[:dst][:platform_pointer_field]}"]
          end

          @sql << %[
                    INSERT INTO "#{@entity_config[:dst][:schema]}"."#{@entity_config[:dst][:table]}" as t (#{insert_fields.join(',')}) VALUES (#{insert_values.join(',')})
                      ON CONFLICT (#{on_conflict.join(',')}) DO UPDATE
                    SET #{update_data.join(',')} WHERE #{where.join(' AND ')} ;
                    ]

          @last_handled = data
        end

      end

      # Add delete statement to @sql
      def delete(pk)
        @sql << %[ DELETE FROM "#{@entity_config[:dst][:schema]}"."#{@entity_config[:dst][:table]}"
                    WHERE
                      "#{pk_field}" = '#{pk}' AND
                      "#{@entity_config[:dst][:platform_pointer_field]}" = '#{@pointer}'
                  ]
      end


      # Execute statements from @sql array and clear it
      def commit
        @connection.exec(@sql.join(';')) if @sql.size > 0
        @sql.clear
      end

      def updated_at_field
        @entity_config[:dst][:updated_at_field]
      end

      def pk_field
        @entity_config[:dst][:pk]
      end

      # Common filter depends on entity properties
      def get_filter
        filter = super
        filter << %{ "#{@entity_config[:dst][:platform_pointer_field]}"='#{@pointer}'} unless @entity_config[:dst][:platform_pointer_field].nil?
        filter << @entity_config[:dst][:condition] unless @entity_config[:dst][:condition].nil?
        filter
      end

      # Get last keys from destination
      def last_keys
        filter = []
        unless @entity_config[:dst][:platform_pointer_field].nil?
          filter << %{"#{@entity_config[:dst][:platform_pointer_field]}"='#{@pointer}'}
        end

        filter << @entity_config[:dst][:condition] unless @entity_config[:dst][:condition].nil?
        filter << %{ "#{updated_at_field}" = '#{last_item[updated_at_field]}' }

        # Return only private keys values
        pk_type_string = false
        pk_type_string = true unless ::Thread.current[:entity_config][:dst][:pk_type_string].nil?
        query([pk_field], filter).map do |item|
          if not pk_type_string
            item[pk_field].to_i
          else
            item[pk_field].to_s
          end
        end

      end

      # Get last item from destination
      def last_item

        filter = []
        unless @entity_config[:dst][:platform_pointer_field].nil?
          filter << %{"#{@entity_config[:dst][:platform_pointer_field]}"='#{@pointer}'}
        end

        filter << @entity_config[:dst][:condition] unless @entity_config[:dst][:condition].nil?

        key = query([pk_field], filter, ["#{updated_at_field} DESC NULLS LAST", "#{pk_field} DESC"], 1)[0]

        # If row was not found
        if key.nil?
          {updated_at_field => '1970-01-01 00:00:00', pk_field => 0}
        else

          # If updated at field is NULL then set UNIXTIMESTAMP = 0
          if key[updated_at_field].nil?
            key[updated_at_field] = '1970-01-01 00:00:00'
          end

          key
        end
      end

      # Get count form destination
      def get_count

        result = @connection.exec(
            %[
                SELECT count(#{pk_field})
                FROM "#{@entity_config[:dst][:schema]}"."#{@entity_config[:dst][:table]}"
                WHERE #{get_filter.join(' AND ')}
            ]
        ).to_a[0]

        if result.nil?
          0
        else
          result['count'].to_i
        end

      end

      # Get checksum form destination
      def get_checksum

        result = @connection.exec(
            %[
                SELECT count(*)||'-'||to_char("#{@entity_config[:dst][:updated_at_field]}"::timestamp at time zone 'UTC', 'YYYYMMDD"T"HH24MISS.US') as checksum
                FROM "#{@entity_config[:dst][:schema]}"."#{@entity_config[:dst][:table]}"
                WHERE #{get_filter.join(' AND ')}
                GROUP BY "#{@entity_config[:dst][:updated_at_field]}"
                ORDER BY "#{@entity_config[:dst][:updated_at_field]}" DESC LIMIT 1
            ]
        ).to_a[0]

        if result.nil?
          Cache::Keys::CHECKPOINT_KEY_DEFAULT
        else
          result['checksum']
        end

      end

    end
  end
end