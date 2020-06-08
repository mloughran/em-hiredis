require 'securerandom'

module EM::Hiredis
  # Cross-process re-entrant lock, backed by redis
  class Lock

    EM::Hiredis::Client.load_scripts_from(File.expand_path("../lock_lua", __FILE__))

    # Register a callback which will be called 1s before the lock expires
    # This is an informational callback, there is no hard guarantee on the timing
    # of its invocation because the callback firing and lock key expiry are handled
    # by different clocks (the client process and redis server respectively)
    def onexpire(&blk); @onexpire = blk; end

    def initialize(redis, key, timeout)
      unless timeout.kind_of?(Integer) && timeout >= 1
        raise "Timeout must be an integer and >= 1s"
      end
      @redis, @key, @timeout = redis, key, timeout
      @token = SecureRandom.hex
    end

    # Acquire the lock
    #
    # This is a re-entrant lock, re-acquiring will succeed and extend the timeout
    #
    # Returns a deferrable which either succeeds if the lock can be acquired, or fails if it cannot.
    def acquire
      df = EM::DefaultDeferrable.new
      @redis.lock_acquire([@key], [@token, @timeout]).callback { |success|
        if (success)
          EM::Hiredis.logger.debug "#{to_s} acquired"

          EM.cancel_timer(@expire_timer) if @expire_timer
          @expire_timer = EM.add_timer(@timeout - 1) {
            EM::Hiredis.logger.debug "#{to_s} Expires in 1s"
            @onexpire.call if @onexpire
          }

          df.succeed
        else
          EM::Hiredis.logger.debug "#{to_s} failed to acquire"
          df.fail("Lock is not available")
        end
      }.errback { |e|
        EM::Hiredis.logger.error "#{to_s} Error acquiring lock #{e}"
        df.fail(e)
      }
      df
    end

    # Release the lock
    #
    # Returns a deferrable
    def unlock
      EM.cancel_timer(@expire_timer) if @expire_timer

      df = EM::DefaultDeferrable.new
      @redis.lock_release([@key], [@token]).callback { |keys_removed|
        # DEBUGGING WTF
        if !keys_removed.is_a?(Integer)
          EM::Hiredis.logger.error "#{to_s}: Received String where expected int [#{keys_removed.inspect}]"
          df.fail("WTF")
        elsif keys_removed > 0
          EM::Hiredis.logger.debug "#{to_s} released"
          df.succeed
        else
          EM::Hiredis.logger.debug "#{to_s} could not release, not held"
          df.fail("Cannot release a lock we do not hold")
        end
      }.errback { |e|
        EM::Hiredis.logger.error "#{to_s} Error releasing lock #{e}"
        df.fail(e)
      }
      df
    end

    # This should not be used in normal operation.
    # Force clear without regard to who owns the lock.
    def clear
      EM::Hiredis.logger.warn "#{to_s} Force clearing lock (unsafe)"
      EM.cancel_timer(@expire_timer) if @expire_timer

      @redis.del(@key)
    end

    def to_s
      "[lock #{@key}]"
    end

  end
end
