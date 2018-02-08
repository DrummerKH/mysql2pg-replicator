require 'logger'

module Replicator

  # Custom logger class
  # inherits native Logger class and set custom configs
  class GdmLogger < Logger

    def initialize(file)
      super

      # Severity (dont remove this line)
      level = $config[:env][:logger_severity]

      @formatter = proc do |severity, datetime, progname, msg|
        "[#{datetime}] #{severity} -- #{progname}: #{msg}\n"
      end

    end
  end
end