module Swarm
  class FeatureFormatter
    def initialize(step_mother, io, options)
      @last_failed_test = []
    end

    def test_result_handler
      Swarm::Drone.pilot
    end

    def step_name(keyword, step_match, status, source_indent, background)
      case status
      when :failed
        if !@last_failed_test.empty?
          # we expected the exception method to clear this out by now!
          report_failures_and_clear()
        end
        step_name = step_match.format_args(lambda{|param| "*#{param}*"})
        @last_failed_test << "#{step_name} FAILED (BUT DIDN'T RAISE AN EXCEPTION??)"
      when :passed
        test_result_handler.test_passed
      when :skipped
        test_result_handler.test_skipped
      when :undefined
        test_result_handler.test_failed "#{step_match.format_args(lambda{|param| "*#{param}*"})} UNDEFINED"
      when :pending
        test_result_handler.test_pending "#{step_match.format_args(lambda{|param| "*#{param}*"})} PENDING"
      else
        step_name = step_match.format_args(lambda{|param| "*#{param}*"})
        raise "Eeek! FeatureFormatter doesn't know how to handle '#{status.inspect}'"
      end
    end

    def after_table_row(table_row)
      if table_row.exception
        test_result_handler.test_failed("#{table_row.exception.message} (#{table_row.exception.class})\n#{table_row.exception.backtrace.join("\n")}")
      end
    end

    def exception(exception, status)
      # replace the last_failed_test (there should be only one) with a more detailed message from this exception
      @last_failed_test.pop
      @last_failed_test << "#{exception.backtrace.last}\n\n#{exception.message}"
      report_failures_and_clear
    end

    def after_features(features)
      if !@last_failed_test.empty?
        report_failures_and_clear
      end
    end

    private

    def report_failures_and_clear
      @last_failed_test.each { |test| test_result_handler.test_failed(test) }
      @last_failed_test.clear
    end
  end
end
