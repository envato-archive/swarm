module Swarm
  module Formatter
    class Base
      def initialize(voice)
        @voice = voice
      end

      def test_passed
      end

      def test_failed(detail)
      end

      def test_skipped
      end

      def test_pending(detail)
      end

      def test_undefined
      end

      def completed
      end

      def started
        @started_at ||= Time.now
      end

      protected

      def runtime
        Time.now - @started_at
      end

      def output(str)
        @voice.say(str)
      end

      def puts(str)
        raise "Use output() instead"
      end
    end
  end
end
