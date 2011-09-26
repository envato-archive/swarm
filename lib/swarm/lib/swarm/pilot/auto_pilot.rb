module Swarm
  module Pilot
    class AutoPilot < Pilot::Base
      attr_reader :spec_pilot, :feature_pilot

      def prepare
        @spec_pilot = SpecPilot.new(drone)
        @feature_pilot = FeaturePilot.new(drone)

        spec_pilot.prepare
        feature_pilot.prepare
      end

      def exec(directive)
        if directive.file =~ /\.feature\b/
          feature_pilot.exec(directive)
        else
          spec_pilot.exec(directive)
        end
      end
    end
  end
end
