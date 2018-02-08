module Replicator

  #
  # Class for put threshold log to the main log file
  # On creation instance need put Logger instance and threshold time, if it exceed write log to the file
  #
  # For add string:
  #
  # instance.add('String log', 4.34) do
  #   'Here is optional block'
  # end
  #
  # If block given, the result will put to the string after time string
  #
  # Before put log to the file need call thread_log('Thread time', 5.34)
  #
  # When log is complete call put method without argument,
  # if thread time in the method above is greater than threshold time,
  # the strings will added to the log file
  #
  class ThresholdLog

    # +name+ - name of class that will be stored to the log file
    # +threshold_time+ - time if round time exceeded that time then log will be stored
    def initialize(name, threshold_time)
      @name, @threshold_time = name, threshold_time
      @log,  @thread_time    = [],     {}
    end

    # Add string to the log
    # +string+ - log string
    # +time+ - processed time
    # +block+ - If threshold log will be stored and time of this item is max of existed,
    # then this block will be called, and concat to the +string+
    def add(string, time, &block)

      if block_given?
        block = block.call
      end

      @log << {
          string: string,
          time: time,
          block: block
      }
    end

    # Set the last item of the log and set time of the round
    def thread_log(string, time)
      @thread_time = {
          string: string,
          time: time
      }
    end

    # Try store log to the log file
    def store

      if @thread_time.empty?
        raise Exception, 'You need call thread_log method first'
      end

      if store?

        max = 0

        # Check max time index
        @log.each_with_index do |item, index|

          # Get max time of current log
          if item[:time] > @log[max][:time]
            max = index
          end
        end

        # Add thread time to main log
        @log << @thread_time

        to_log = []
        @log.each_with_index do |item, index|
          to_log << "#{item[:string]}: #{item[:time]} sec #{ (index == max and item[:block]) ? "\n\t#{item[:block]}" : ''}"
        end

        $log.debug(@name) {("\n###########################################\n"+
                              to_log.join("\n") +
                            "\n###########################################")}
      end

      self
    end

    def clean
      @log.clear
    end

    # Check need store the log or not
    def store?
      (@thread_time[:time] > @threshold_time.to_f and @log.length > 0)
    end

    def to_s
      'Threshold Log'
    end

    def inspect
      to_s
    end

  end
end