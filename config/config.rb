require 'yaml'
require 'fileutils'
require_relative 'env.rb'

class ::Hash
  def deep_merge(second)
      merger = proc { |key, v1, v2| Hash === v1 && Hash === v2 ? v1.merge(v2, &merger) : v2 }
      self.merge(second, &merger)
  end
end

module Replicator

  # Class for load configs
  class Config

    def load

      @config = {
          env: ::Config.config
      }

      load_yml 'entity_config'
      load_yml 'brokers'

      self
    end

    # Load configs depends on environment
    def load_yml(filename)

      @config[filename.intern] = YAML.load_file(File.join(__dir__, filename+'.yml'))
      if File.exist? File.join(__dir__, 'environments', @config[:env][:environment], filename+'.yml')

        # If file exists in environment then load it, if not then load production file
        @config[filename.intern] = YAML.load_file(File.join(__dir__, 'environments', @config[:env][:environment], filename+'.yml'))
      end
    end

    # Returns configs
    def config
      @config
    end

    # Replace config option by environment values
    def set_env_defaults

      env_vars = {}
      ENV.select do |key, value|
          if key.to_s.match(/^GDM_.*/)
            k =(key.split '_')[1..-1].map {|i| i.to_sym.downcase}
            env_vars = env_vars.deep_merge k.reverse.inject(value) { |a, n| { n => a } }
          end
      end

      @config[:env] = @config[:env].deep_merge(env_vars)

    end

  end
end