module Replicator

  # Class has common functions
  class Helper

    def inspect
      to_s
    end

    def self.to_s
      Thread.current[:name] || 'Replicator::Helper'
    end

    # Connect to PostgreSQL server
    # +dbname+ - database name
    def self.pg_connect(dbname)
      begin


        # Check if database name exists in env config
        unless $config[:env][:postgresql][:brokers_databases].nil?
          unless $config[:env][:postgresql][:brokers_databases][dbname.intern].nil?
            dbname = $config[:env][:postgresql][:brokers_databases][dbname.intern]
          end
        end

        # Check if database name exists in entity config
        unless Thread.current[:platform].nil? or $config[:entity_config][Thread.current[:platform].intern].nil?
          unless $config[:entity_config][Thread.current[:platform].intern][Thread.current[:entity].intern].nil?
            unless $config[:entity_config][Thread.current[:platform].intern][Thread.current[:entity].intern][:dst][:db].nil?
              dbname = $config[:entity_config][Thread.current[:platform].intern][Thread.current[:entity].intern][:dst][:db]
            end
          end
        end

        conn = PG.connect(
              :host => $config[:env][:postgresql][:hostname],
              :port => $config[:env][:postgresql][:port],
              :user => $config[:env][:postgresql][:username],
              :password => $config[:env][:postgresql][:password],
              :dbname => dbname,
              :application_name => 'GDM-Replicator-'+$config[:env][:environment]
          )

        conn.exec("SET synchronous_commit TO 'off'")

      rescue Exception => msg
        self.error(msg, self)
      end

      conn
    end

    # Connect to MySQL server
    def self.mysql_connect

      begin
        conn = Mysql2::Client.new(
            :host => $config[:env][:mysql][:hostname],
            :username => $config[:env][:mysql][:username],
            :password => $config[:env][:mysql][:password],
            :database => $config[:env][:mysql][:dbname],
            :reconnect => true
        )


      rescue Exception => msg
        self.error(msg, self)
      end

      conn
    end

    # Connect to RabbitMQ server
    def self.rabbitmq_connect

      begin
        conn = Bunny.new(
            host: $config[:env][:rabbitmq][:hostname],
            vhost: $config[:env][:rabbitmq][:vhost],
            user: $config[:env][:rabbitmq][:username],
            pass: $config[:env][:rabbitmq][:password],
            ssl: $config[:env][:rabbitmq][:ssl],
            port: $config[:env][:rabbitmq][:port]
        )
        conn.start
      rescue Exception => msg
        self.error(msg, self)
      end

      conn
    end

    # Error handling, save to log
    # +exception+ - instance of exception class
    # +name+ - name of class that will be stored in log
    def self.error(exception, name)
      name = self unless name
      $log.fatal(name) {"Error: #{exception}\nBacktrace:\n\t#{exception.backtrace.join("\n\t")}"}
    end

  end

end