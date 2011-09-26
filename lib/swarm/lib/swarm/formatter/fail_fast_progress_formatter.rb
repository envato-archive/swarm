module Swarm
  module Formatter
    class FailFastProgressFormatter < Formatter::Base
      def test_passed
        output(green('.'))
      end

      def test_failed(detail)
        output(red("\n\n#{detail}\n\n"))
      end

      def test_pending(detail)
        output(yellow("\n\n#{detail}\n\n"))
      end

      def test_skipped
        output(cyan('_'))
      end

      def completed
        output("\n\nRuntime: #{runtime}\n")
      end

      protected

      if defined?(Term)
        include Term::ANSIColor
      else
        def yellow(str)
          str
        end

        def red(str)
          str
        end

        def green(str)
          str
        end

        def cyan(str)
          str
        end
      end
    end
  end
end
