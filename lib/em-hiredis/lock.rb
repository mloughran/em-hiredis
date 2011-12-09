module EM::Hiredis
  # Distributed lock built on redis
  class Lock
    include EM::Deferrable

    def onexpire(&blk); @onexpire = blk; end

    def initialize(redis, key, timeout)
      @redis, @key, @timeout = redis, key, timeout
      @locked = false
      @expiry = nil
    end

    # Aquire the lock
    def aquire
      expiry = new_expiry
      @redis.setnx(@key, expiry) { |setnx|
        if setnx == 1
          lock_aquired(expiry)
        else
          attempt_to_aquire_existing_lock
        end
      }
    end

    # Release the lock
    def unlock
      EM.cancel_timer(@expire_timer) if @expire_timer
      
      if @locked && Time.now.to_i < @expiry
        EM::Hiredis.logger.debug "Lock: released #{@key}"
        @redis.del(@key)
      else
        EM::Hiredis.logger.debug "Lock: could not release #{@key}"
      end
    end

    # This should not be used in normal operation - force clear
    def clear
      @redis.del(@key)
    end

    private

    def attempt_to_aquire_existing_lock
      @redis.get(@key) { |expiry_1|
        expiry_1 = expiry_1.to_i
        if expiry_1 == @expiry || expiry_1 < Time.now.to_i
          # Either the lock was ours or the lock has already expired
          expiry = new_expiry
          @redis.getset(@key, expiry) { |expiry_2|
            expiry_2 = expiry_2.to_i
            if expiry_2 == @expiry || expiry_2 < Time.now.to_i
              lock_aquired(expiry)
            else
              # Another client got there first
              fail(expiry_2)
            end
          }
        else
          fail(expiry_1)
        end
      }
    end

    def new_expiry
      Time.now.to_i + @timeout + 1
    end

    def lock_aquired(expiry)
      EM::Hiredis.logger.debug "Lock: aquired #{@key}"
      @locked = true
      @expiry = expiry
      @expire_timer = EM.add_timer(@timeout) {
        EM::Hiredis.logger.debug "Lock: #{@key} will expire in 1s"
        @onexpire.call if @onexpire
      }
      succeed
    end
  end
end
