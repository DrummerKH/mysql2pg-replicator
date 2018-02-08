require_relative File.join('..', 'extractor')

module Replicator
  module Providers
    module Source

      class MT4 < Replicator::Providers::Extractor

        # Get data
        def messages(fields, limit)
          query(fields, get_filter, get_order, limit)
        end

        def prepare_request(fields, filter, order, limit)

          # Add updated_at field if its not exists in +field+
          unless fields.include? updated_at_field
            fields << updated_at_field
          end

          "SELECT `#{ fields.join('`,`') }` FROM #{table}
          #{ (not filter.empty?) ? " WHERE #{filter.join(' AND ')} " : ''}
          #{ (not order.empty?) ? " ORDER BY #{order.join(' , ')} " : ''}
          #{ (not limit.nil?) ? %{ LIMIT #{limit} } : ''}
            ;
           "
        end

        def prepare_response(result)
          # Convert Time to string with milliseconds
          result.map do |item|
            item[updated_at_field] = item[updated_at_field].strftime('%Y-%m-%d %H:%M:%S.%6N')
            item
          end
        end

        def query(fields, filter, order = [], limit = nil)

          sql = prepare_request(fields, filter, order, limit)

          result = @connection.query(sql).to_a

          prepare_response(result)
        end

        # Get source table name with database name
        def table
          dbname = "`#{@broker}_#{@platform}_#{@server}`"

          # Check if database name exists in entity config
          unless @entity_config[:src][:db].nil?
            dbname = @entity_config[:src][:db]
          end

          "#{dbname}.`#{@entity_config[:src][:table]}`"
        end

      end

    end
  end
end