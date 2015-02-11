# Collects timers and then invokes their callbacks in order of increasing time
#
# Useful for quickly testing timer based logic AS LONG AS THE CURRENT TIME
# IS NOT USED. i.e. no calls to Time.now or similar
module EventMachine::Hiredis
  class Timer
    attr_reader :due

    def initialize(due, callback)
      @due = due
      @callback = callback
    end

    def fire(now)
      @callback.call
      true
    end
  end

  class PeriodicTimer
    def initialize(period, callback, now)
      @period = period
      @callback = callback
      @last_fired = now
    end

    def fire(now)
      @last_fired = now
      @callback.call
      false
    end

    def due
      @last_fired + @period
    end
  end

  class TimeMockEventMachine
    attr_reader :current_time

    def initialize
      @current_time = 0
      @timers = []
    end

    def add_timer(delay, &blk)
      t = Timer.new(@current_time + delay, blk)
      @timers.push(t)
      return t
    end

    def add_periodic_timer(period, &blk)
      t = PeriodicTimer.new(period, blk, @current_time)
      @timers.push(t)
      return t
    end

    def cancel_timer(t)
      @timers.delete(t)
    end

    def evaluate_ticks
      until @timers.empty?
        sort!

        t = @timers.first
        @current_time = t.due

        remove = t.fire(@current_time)
        @timers.delete(t) if remove
      end
    end

    def remaining_timers
      @timers.length
    end

    private

    def sort!
      @timers.sort_by!(&:due)
    end
  end
end