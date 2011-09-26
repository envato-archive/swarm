module Swarm
  module Pilot
    class Base
      include OutputHelper
      def initialize(drone)
        @drone = drone
      end

      def drone
        @drone
      end

      def test_failed(detail)
        @drone.relay(Directive::TestFailed.new(detail, :encoded => false))
      end

      def test_pending(detail)
        @drone.relay(Directive::TestPending.new(detail, :encoded => false))
      end

      def test_passed
        @drone.relay(Directive::TestPassed)
      end

      def test_skipped
        @drone.relay(Directive::TestSkipped)
      end

      def prepare
      end
    end
  end
end
