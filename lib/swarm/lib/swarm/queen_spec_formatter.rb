module Swarm
  class QueenSpecFormatter < SpecFormatter

    def test_result_handler
      Swarm::Queen.instance.formatter
    end

  end
end

