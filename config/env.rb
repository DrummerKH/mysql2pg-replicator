module Config

  def self.config
    {
      process_name: ENV['PROCESS_NAME'],

      environment: ENV['ENV'],

      stop_on_thread_ex: ENV['STOP_ON_THREAD_EX'] == 'true',

      use_cache: ENV['USE_CACHE'] == 'true',

      # Size of batches for fill cache in case it invalid
      initial_cache_batch_size: ENV['INITIAL_CACHE_BATCH_SIZE'],

      # Severity of logging. Possible values [DEBUG, INFO, WARN, ERROR, FATAL]
      logger_severity: ENV['LOG_SEVERITY'],

      # PostgreSQL connect credentials
      postgresql: {
          hostname: ENV['PG_HOSTNAME'],
          port: ENV['PG_PORT'],
          username: ENV['PG_USERNAME'],
          password: ENV['PG_PASSWORD'],
          gtr_dbname: ENV['PG_DBNAME'],
          brokers_databases: {
              gdm: ENV['DB_GDM']
          },
      },

      # MySQl connect credentials
      mysql: {
          hostname: ENV['MYSQL_HOSTNAME'],
          port: ENV['MYSQL_PORT'],
          username: ENV['MYSQL_USERNAME'],
          password: ENV['MYSQL_PASSWORD'],
          dbname: ENV['MYSQL_DATABASE'],

          # Table where storing outcoming to RabbitMQ messages
          trx_table: ENV['TRX_TABLE']
      },

      rabbitmq: {
          hostname: ENV['RABBITMQ_HOSTNAME'],
          username: ENV['RABBITMQ_USERNAME'],
          password: ENV['RABBITMQ_PASSWORD'],
          vhost: ENV['RABBITMQ_VHOST'],
          ssl: ENV['RABBITMQ_SSL'] == 'true',
          port: ENV['RABBITMQ_PORT'],
      },

      redis: {
          host: ENV['REDIS_HOST'],
          timeout: ENV['REDIS_TIMEOUT']
      },

      # How much rows get from queue table per thread
      grab_count_rows: ENV['GRAB_COUNT_ROWS'],
      extract_period: ENV['EXTRACT_PERIOD'],

      # Time when threshold will be stored on log file
      time_to_log_threshold: ENV['TIME_TO_LOG'],

      trado_b2b_url: ENV['TRADO_B2B_URL'],
      trado_crm_user_id: ENV['TRADO_CRM_USER_ID'],
      trado_report_id: ENV['TRADO_REPORT_ID'],
      trado_crm_username: ENV['TRADO_CRM_USERNAME'],
      trado_account_id: ENV['TRADO_ACCOUNT_ID']
    }
  end

end