module Swarm
  module Formatter
    class YAMLFormatter < Formatter::Base
      def initialize(voice)
        super
        @results = {:stats => {:passed => 0, :failed => 0, :skipped => 0, :pending => 0, :undefined => 0}, :failures => [], :pending => []}
        @mutex = Mutex.new
      end

      def test_passed
        increment(:passed)
      end

      def test_pending(detail)
        increment(:pending)

        @mutex.synchronize do
          @results[:pending] << detail
        end
      end

      def test_failed(detail)
        increment(:failed)

        @mutex.synchronize do
          @results[:failures] << detail
        end
      end

      def test_skipped
        increment(:skipped)
      end

      def completed
        # Don't need to acquire the mutex here.
        @results[:runtime] = runtime
        output(YAML.dump(@results))
      end

      protected

      def increment(counter)
        @mutex.synchronize do
          @results[:stats][counter] += 1
        end
      end
    end
  end
end
