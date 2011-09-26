module Swarm
  module OutputHelper
    def self.included(base)
      base.class_eval do
        include InstanceMethods
        extend ClassMethods
      end
    end

    module InstanceMethods
      def debug(msg)
        self.class.debug(msg)
      end
    end

    module ClassMethods
      def debug(msg)
        puts "DEBUG: #{msg}" if Swarm.debug?
        msg
      end
    end
  end
end
