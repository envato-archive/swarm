module Swarm
  class Voice
    class StopMarker; end

    def initialize
      @queue = Queue.new
    end

    def start
      @thread = Thread.start do
        message = @queue.pop
        until message.is_a?(StopMarker)
          $stdout.write(message)
          $stdout.flush
          message = @queue.pop
        end
      end
    end

    def stop
      @queue.push(StopMarker.new)
      @thread.join
    end

    def say(str)
      @queue.push(str)
    end
  end
end
