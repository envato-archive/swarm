require 'swarm/queen_spec_formatter'
require 'ruby-debug'
module Swarm
  module Pilot
    class SpecPilot < Pilot::Base
      def split(files)
        return files
        options = Spec::Runner::Options.new($stderr, $stdout)
        options.parse_format('Swarm::SpecFormatter')
        options.files.replace(files)
        options.add_dir_from_project_root_to_load_path('spec')
        options.add_dir_from_project_root_to_load_path('lib')
        Spec::Runner.use options

        runner = Spec::Runner::ExampleGroupRunner.new(options)

        runner.load_files(options.files_to_load)

        debugger
        options.example_groups.select do |g|
          true
        end.map(&:examples).flatten.map(&:location).compact.uniq.tap do |f|
          pp f
        end
      end

      def prepare
        # Load some constants before we fork to take advantage of Copy On Write.
        Spec::Runner::Options

        # Some specs can't handle being parallelised. Run them up front.
        options = Spec::Runner::Options.new($stderr, $stdout)
        options.parse_format('Swarm::QueenSpecFormatter')
        options.files.replace(Swarm.series_files.grep(/_spec.rb/) || [])
        Spec::Runner.use options
        debug("running non-concurrent specs")
        options.run_examples
        debug("completed non-concurrent specs")
      end

      def exec(directive)
        begin
          options = Spec::Runner::Options.new($stderr, $stdout)
          options.parse_format('Swarm::SpecFormatter')

          file, line = directive.file.split(/:/, 2)
          options.files << file
          options.line_number = line.to_i

          Spec::Runner.use options
          options.run_examples

          @drone.relay(Directive::Ready)
        rescue SystemExit
          exit 1
        rescue Exception => e
          detail = [e.message]
          detail << "On file: #{directive.file}"
          detail << e.backtrace.join("\n")
          @drone.relay(Directive::TestFailed.new(detail.join("\n"), :encoded => false))
        end
      end
    end
  end
end
