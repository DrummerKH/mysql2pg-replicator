module Replicator

  Plugins::subscribe(:pre, :worker) do |broker, platform, server, entity, item|

    if platform == 'mt4'

      # Fields must be 0 and 1 but it's not, need convert for Postgres
      if entity == :traders
        unless item['ENABLE'].nil?
          item['ENABLE'] = item['ENABLE'] > 0
        end

        unless item['ENABLE_READONLY'].nil?
          item['ENABLE_READONLY'] = item['ENABLE_READONLY'] > 0
        end

        unless item['ENABLE_CHANGE_PASS'].nil?
          item['ENABLE_CHANGE_PASS'] = item['ENABLE_CHANGE_PASS'] > 0
        end

      end

      # Withdrawal amount to positive number, because of in MT4 db withdrawals number are negative
      if entity == :withdrawals
        unless item['PROFIT'].nil?
          item['PROFIT'] = item['PROFIT'].abs
        end

      end

      if entity == :orders

        # Modify MT4 cmd notation to human language :)
        unless item['CMD'].nil?
          item['CMD'] =
              (   case item['CMD']
                    when 0
                      'buy'
                    when 1
                      'sell'
                    when 2
                      'buy_limit'
                    when 3
                      'sell_limit'
                    when 4
                      'buy_stop'
                    when 5
                      'sell_stop'
                    else
                      nil
                  end
              )
        end

        # Convert VOLUME to lots units
        unless item['VOLUME'].nil?
          item['VOLUME'] = item['VOLUME'].to_f/100
        end

      end

    elsif platform == 'special'

      # Quotes replication, like up or down bar (in mysql is 1 and 0)
      if entity == :quotes
        unless item['DIRECTION'].nil?
          item['DIRECTION'] = item['DIRECTION'] == 1 ? 'up' : 'down'
        end

      end

    elsif platform == 'trado'

      # Down case of trado bonus state
      if entity == :bonuses
        item['bonusState'].downcase!
      end

    end

  end

end