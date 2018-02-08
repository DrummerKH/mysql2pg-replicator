require 'curb'

module Replicator
  class BMPPlugin

    #
    # Delete trader accounts from vendor CCFIN database in case of delete from MT4
    #
    Plugins::subscribe(:pre, :delete) do |broker, platform, server, entity, item|

      log_head = Thread.current[:name].to_s+':DELETE:BMPPlugin:'

      # For production only
      if ENV['ENV'] == 'production'

        # For gdm broker and mt4 platform only
        if  entity == :traders and
            broker == 'gdm' and
            platform == 'mt4'

          bmp_platform = ''
          if server == 'live20'
            bmp_platform = 'MT4'
          elsif server == 'live21'
            bmp_platform = 'MT4b'
          else
            $log.error(log_head) {"Platform #{server} not supported in BMPPlugin unlink"}
          end

          if bmp_platform
            data = JSON.parse(item['data'])

            # Get email of BMP account
            sql = %{ SELECT bmp_id FROM public.accounts
                      WHERE email = '#{data['email']}'; }

            result = Thread.current[:pg_connection].exec(sql).to_a[0]

            if result

              has_errors = false

              url_data = "#{result['bmp_id']}/#{bmp_platform}/#{data['login']}"

              # Send request to vendor API
              http = Curl.delete('http://54.254.196.207:9595/unlinkOmsAccount/' + url_data) do |http|
                http.http_auth_types = :basic
                http.username = 'hugo'
                http.password = '123'

                # On 4xx errors
                http.on_missing do
                  has_errors = true
                end

                # On 5xx errors
                http.on_failure do
                  has_errors = true
                end

              end

              raise "BMPPlugin - Url data: #{url_data}; Vendor returns - #{http.body_str}. Further deletion cannot be continued." if has_errors

              $log.info(log_head) {"Data #{url_data} has been deleted from vendor DB"}

            else

              $log.warn(log_head) {"BMP account #{data['email']} not found"}
            end
          end
        end
      end
    end
  end
end