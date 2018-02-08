module Replicator
  module CacheModule
    class ProviderAbstract

      def initialize(key)
        raise NotImplementedError, 'Implement this method in a child class - initialize'
      end

      def get_checkpoint_key
        raise NotImplementedError, 'Implement this method in a child class - get_checkpoint_key'
      end

      def set_checkpoint_key(value)
        raise NotImplementedError, 'Implement this method in a child class - set_checkpoint_key'
      end

      def clear
        raise NotImplementedError, 'Implement this method in a child class - clear'
      end

      def batch_insert(&block)
        raise NotImplementedError, 'Implement this method in a child class - batch_insert'
      end

      def delete(key)
        raise NotImplementedError, 'Implement this method in a child class - delete'
      end

    end
  end
end
