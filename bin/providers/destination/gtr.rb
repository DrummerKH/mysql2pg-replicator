require_relative File.join('..', 'modifier')
require_relative File.join('..', 'extractor')

module Replicator
  module Providers
    module Destination

      # GTR destination provider
      class GTR < Replicator::Providers::Modifier

        # Gather data from destination
        def messages(fields, limit)
          query(fields, get_filter, get_order, limit)
        end

        # Prepare the request
        def prepare_request(fields, filter, order, limit)

          %{
            SELECT "#{ fields.join('","') }", to_char("#{updated_at_field}"::timestamp at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS.US') as #{updated_at_field} FROM (
              SELECT "#{ fields.join('","') }", "#{updated_at_field}" FROM

          "#{@entity_config[:dst][:schema]}"."#{@entity_config[:dst][:table]}"

          #{ (not filter.empty?) ? %{ WHERE #{filter.join(' AND ')} } : ''}
            #{ (not order.empty?) ? %{ ORDER BY #{order.join(' , ')} } : ''}
            #{ (not limit.nil?) ? %{ LIMIT #{limit} } : ''}
            ) as x;
           }
        end

        # Make a request
        def query(fields, filter, order = [], limit = nil)
          sql = prepare_request(fields, filter, order, limit)
          @connection.exec(sql).to_a
        end

      end

    end
  end
end
