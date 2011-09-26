require 'spec/runner/formatter/base_formatter'

module Swarm
  class SpecFormatter < Spec::Runner::Formatter::BaseFormatter
    def test_result_handler
      Swarm::Drone.pilot
    end

    def example_failed(example_proxy, counter, failure)
      detail = ["#{failure.header}\n#{failure.exception.message}"]
      detail << format_backtrace(failure.exception.backtrace)
      test_result_handler.test_failed(detail.join("\n"))
    end

    def example_passed(example_proxy)
      test_result_handler.test_passed
    end

    def example_pending(example_proxy, message, deprecated_pending_location=nil)
      test_result_handler.test_pending("'#{example_proxy.description}' @ #{example_proxy.location}")
    end

    protected

    def format_backtrace(backtrace)
      return "" if backtrace.nil?
      backtrace.map { |line| backtrace_line(line) }.join("\n")
    end

    def backtrace_line(line)
      line.sub(/\A([^:]+:\d+)$/, '\\1:')
    end
  end
end
