module EM::Hiredis
  # A lock that automatically re-acquires a lock before it loses it
  #
  # The lock is configured with the following two parameters
  #
  # :lock_timeout - Specifies how long each lock is acquired for. Setting
  #   this low means that locks need to be re-acquired very often, but a long
  #   timout means that a process that fails without cleaning up after itself
  #   (i.e. without releasing it's underlying lock) will block the anther
  #   process from picking up this lock
  #   replaced for a long while
  # :retry_interval - Specifies how frequently to retry acquiring the lock in
  #   the case that the lock is held by another process, or there's an error
  #   communicating with redis
  #
  class PersistentLock
    def onlocked(&blk); @onlocked = blk; self; end
    def onunlocked(&blk); @onunlocked = blk; self; end

    def initialize(redis, key, options = {})
      @redis, @key = redis, key
      @timeout = options[:lock_timeout] || 100
      @retry_timeout = options[:retry_interval] || 60
      @lock = EM::Hiredis::Lock.new(redis, key, @timeout)
      @lock.onexpire {
        # When the lock is about to expire, extend (called 1s before expiry)
        acquire()
      }
      @locked = false
      EM.next_tick {
        @running = true
        acquire
      }
    end

    # Acquire the lock (called automatically by initialize)
    def acquire
      return unless @running

      @lock.acquire.callback {
        if !@locked
          @onlocked.call if @onlocked
          @locked = true
        end
      }.errback { |e|
        if @locked
          # We were previously locked
          @onunlocked.call if @onunlocked
          @locked = false
        end

        if e.kind_of?(EM::Hiredis::RedisError)
          err = e.redis_error
          EM::Hiredis.logger.warn "Unexpected error acquiring #{@lock} #{err}"
        end

        EM.add_timer(@retry_timeout) {
          acquire() unless @locked
        }
      }
    end

    def stop
      @running = false
      if @locked
        # We were previously locked
        @onunlocked.call if @onunlocked
        @locked = false
      end
      @lock.unlock
    end

    def locked?
      @locked
    end
  end
end
