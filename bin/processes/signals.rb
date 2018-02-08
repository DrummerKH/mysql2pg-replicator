module Replicator

  class Signals

    def self.term
      $term.each(&:call)
    end

    def self.hup
      $hup.each(&:call)
    end

    def self.subscribe(signal, &method)
      if signal == 'term'
        $term << method
      elsif signal == 'hup'
        $hup << method
      end
    end

  end

  $term = []
  $hup = []
  $kill = false

  Signals.subscribe('term') do
    $kill = true
  end

end