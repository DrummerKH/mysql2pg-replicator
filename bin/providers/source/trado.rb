require 'curb'
require 'digest'
require 'addressable/uri'
require 'openssl'

module Replicator
  module Providers
    module Source

      require_relative File.join('..', 'extractor')

      # Trado source provider
      class TRADO < Replicator::Providers::Extractor

        def initialize(conn, broker, platform, server, entity)
          super

          # Type pf trado API [crm, admin]
          # It needs because of different trado APIs uses different authorization schemas sic!
          @api_type = @entity_config[:src][:api_type]

          # Make trado url
          @url = @env_config[:trado_b2b_url] + @entity_config[:src][:url]
        end

        def messages(fields, limit)

          ###################################################
          ### Limit option for trado API is not supported ###
          ###################################################

          url = prepare_request
          data = request(url)
          prepare_response(data)
        end

        # Prepare response
        def prepare_response(data)

          # Remove elements from response that already was retrieved
          # Because of trado APi is not supported any additional conditions

          if not data.nil?

            data.delete_if do |item|
              @keys.include? item[pk_field] and item[updated_at_field] == DateTime.parse(@update_time).strftime('%Y-%m-%dT%H:%M:%S.%7N')
            end

          else
            []
          end

        end

        # Prepare request
        def prepare_request

          # The first TRADO hack
          # Transform ISO 8601 time to UNIX Timestamp ( TRADO facepalm :( )
          after = DateTime.parse(@update_time).to_time.to_i

          # The second trado hack
          # If after option is 0 (remember type UNIX Timestamp) that API nothing return. FACEPALM :(
          # Note: UNIX Timestamp 0 is 1970-01-01 00:00:00
          after = 1 if after == 0

          # Same as first TRADO hack, transform date to UNIX Timestamp
          before = Time.now.to_i

          # GET parameters for API
          params = {
              accountId: @env_config[:trado_account_id],
              :"#{@entity_config[:src][:after_field]}" => after,
              :"#{@entity_config[:src][:before_field]}" => before
          }

          # Set parameters depends on TRADO API type, facepalm
          case @api_type
            when 'admin'
              key = @env_config[:trado_crm_user_id]
              params[:crmUsername] = @env_config[:trado_crm_username]
            when 'crm'
              key = @env_config[:trado_report_id]
            else
              raise ArgumentError, "#{@api_type} api type is not supported"
          end

          # Generate checksum
          params[:checksum] = generate_checksum(params, key)

          # These manipulations for make query string from hash
          query_params = Addressable::URI.new
          query_params.query_values = params

          @url + '?' + query_params.query

        end

        # Make request to TRADO API
        def request(url)

          # For catch 4xx and 5xx HTTP errors
          has_errors = false

          # Send request to vendor API
          http = Curl.get(url) do |http|

            # On 4xx errors
            http.on_missing do
              has_errors = true
            end

            # On 5xx errors
            http.on_failure do
              has_errors = true
            end

          end

          raise "Error from TRADO API - #{http.body_str}" if has_errors

          JSON.parse(http.body_str)['data']

        end

        def generate_checksum(params, key)
          OpenSSL::Digest::SHA256.hexdigest( params.sort.to_h.values.join + key )
        end

      end
    end
  end
end