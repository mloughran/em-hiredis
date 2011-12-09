module ConnectionHelper
  # Use db 9 for tests to avoid flushing the main db
  # It would be nice if there was a standard db number for testing...
  def connect(url = "redis://localhost:6379/9", &blk)
    em do
      redis = EventMachine::Hiredis.connect(url)
      redis.flushall
      blk.call(redis)
    end
  end
end
