module ConnectionHelper
  def connect(url = nil, &blk)
    em do
      redis = EventMachine::Hiredis.connect(url)
      redis.flushall
      blk.call(redis)
    end
  end
end
