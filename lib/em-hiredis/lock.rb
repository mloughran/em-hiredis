module EM::Hiredis
  # Distributed lock built on redis
  class Lock
    def onexpire(&blk); @onexpire = blk; end

    def initialize(redis, key, timeout)
      @redis, @key, @timeout = redis, key, timeout
      @locked = false
      @expiry = nil
    end

    # Acquire the lock
    #
    # It is ok to call acquire again before the lock expires, which will attempt to extend the existing lock.
    #
    # Returns a deferrable which either succeeds if the lock can be acquired, or fails if it cannot. In both cases the expiry timestamp is returned (for the new lock or for the expired one respectively)
    def acquire
      df = EM::DefaultDeferrable.new
      expiry = new_expiry
      @redis.setnx(@key, expiry).callback { |setnx|
        if setnx == 1
          lock_acquired(expiry)
          df.succeed(expiry)
        else
          attempt_to_acquire_existing_lock(df)
        end
      }.errback { |e|
        df.fail(e)
      }
      return df
    end

    # Release the lock
    #
    # Returns a deferrable
    def unlock
      EM.cancel_timer(@expire_timer) if @expire_timer
      
      unless active
        df = EM::DefaultDeferrable.new
        df.fail Error.new("Cannot unlock, lock not active")
        return df
      end

      @redis.del(@key)
    end

    # Lock has been acquired and we're within it's expiry time
    def active
      @locked && Time.now.to_i < @expiry
    end

    # This should not be used in normal operation - force clear
    def clear
      @redis.del(@key)
    end

    private

    def attempt_to_acquire_existing_lock(df)
      @redis.get(@key) { |expiry_1|
        expiry_1 = expiry_1.to_i
        if expiry_1 == @expiry || expiry_1 < Time.now.to_i
          # Either the lock was ours or the lock has already expired
          expiry = new_expiry
          @redis.getset(@key, expiry) { |expiry_2|
            expiry_2 = expiry_2.to_i
            if expiry_2 == @expiry || expiry_2 < Time.now.to_i
              lock_acquired(expiry)
              df.succeed(expiry)
            else
              # Another client got there first
              EM::Hiredis.logger.debug "Lock: failed to acquire #{@key}"
              df.fail(expiry_2)
            end
          }
        else
          EM::Hiredis.logger.debug "Lock: failed to acquire #{@key}"
          df.fail(expiry_1)
        end
      }
    end

    def new_expiry
      Time.now.to_i + @timeout + 1
    end

    def lock_acquired(expiry)
      EM::Hiredis.logger.debug "Lock: acquired #{@key}"
      @locked = true
      @expiry = expiry
      EM.cancel_timer(@expire_timer) if @expire_timer
      @expire_timer = EM.add_timer(@timeout) {
        EM::Hiredis.logger.debug "Lock: #{@key} will expire in 1s"
        @onexpire.call if @onexpire
      }
    end
  end
end
