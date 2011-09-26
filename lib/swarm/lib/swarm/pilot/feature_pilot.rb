module Swarm
  module Pilot
    class SwarmConfiguration < ::Cucumber::Cli::Configuration
      attr_accessor :disable_support_file_loading

      [:all_files_to_load, :step_defs_to_load, :support_to_load].each do |override_method|
        define_method(override_method) do
          if self.disable_support_file_loading
            []
          else
            super
          end
        end
      end
    end

    class FeaturePilot < Pilot::Base
      def split(files)
        return files
        # debugger
        files.map do |file|
          lines = []
          data = File.read(file)

          if data =~ /Scenario Outline/
            lines << file
          else
            data.split(/\n/).each_with_index do |line, index|
              lines << "#{file}:#{index + 1}" if line =~ /\bScenario: /
            end
          end
          lines
        end.flatten
      end

      def prepare
        # Some features can't handle being parallelised. Run them up front.
        files = Swarm.series_files.grep(/\.feature$/)
        configure_runtime(['--no-profile', '--tags', '@series', '--format', 'Swarm::QueenFeatureFormatter', *files])
        debug("running non concurrent features")
        runtime.run!
        debug("completed non-concurrent features")
      end

      def exec(directive)
        begin
          configure_runtime(['--no-profile', '--tags', '~@series', '--format', 'Swarm::FeatureFormatter', directive.file], :subsequent_run => true)
          runtime.run!
          drone.relay(Directive::Ready)
        rescue SystemExit
          exit 1
        rescue Exception => e
          detail = [e.message]
          detail << e.backtrace.join("\n")
          drone.relay(Directive::TestFailed.new(detail.join("\n"), :encoded => false))
        end
      end

      def runtime
        @runtime ||= Cucumber::Runtime.new
      end

      def configure_runtime(args, options = {})
        output_stream = File.open('/dev/null', 'w')
        @configuration = SwarmConfiguration.new(output_stream, output_stream)
        @configuration.parse!(args)
        @configuration.disable_support_file_loading = true if options[:subsequent_run]
        runtime.configure(@configuration)
      end

    end
  end
end
