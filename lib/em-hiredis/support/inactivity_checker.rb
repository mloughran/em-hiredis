module EventMachine::Hiredis
  # Time inactivity and trigger ping action, triggering disconnect
  # action if this does not prompt activity.
  #
  # If initialized with inactivity_timeout_secs = nil, does nothing
  #
  # Emits:
  #   activity_timeout: when inactive for > inactivity_timeout_secs
  #   response_timeout: when inactive for > response_timeout_secs after
  #     activity_timeout emitted
  #
  # Both events are emitted with the number of seconds inactive as argument
  class InactivityChecker
    include EventMachine::Hiredis::EventEmitter

    def initialize(inactivity_timeout_secs, response_timeout_secs, em = EM)
      @em = em
      if inactivity_timeout_secs
        raise ArgumentError('inactivity_timeout_secs must be > 0') unless inactivity_timeout_secs > 0
        raise ArgumentError('response_timeout_secs must be > 0') unless response_timeout_secs > 0
        @inactivity_timeout_secs = inactivity_timeout_secs
        @response_timeout_secs = response_timeout_secs
      end
    end

    def activity
      @inactive_seconds = 0
    end

    def start
      return unless @inactivity_timeout_secs

      @inactive_seconds = 0
      @inactivity_timer = @em.add_periodic_timer(1) {
        @inactive_seconds += 1
        if @inactive_seconds > @inactivity_timeout_secs + @response_timeout_secs
          emit(:response_timeout, @inactive_seconds)
          @inactive_seconds = 0 # or we'll continue to fire each second
        elsif @inactive_seconds > @inactivity_timeout_secs
          emit(:activity_timeout, @inactive_seconds)
        end
      }
    end

    def stop
      if @inactivity_timer
        @em.cancel_timer(@inactivity_timer)
        @inactivity_timer = nil
      end
    end
  end
end
