$:.unshift(File.expand_path('../../lib', __FILE__))
require 'em-hiredis'

EM.run {
  redis = EM::Hiredis.connect
  
  redis.sadd('aset', 'member').callback {
    response_deferrable = redis.hget('aset', 'member')
    response_deferrable.errback { |e|
      p e # => #<RuntimeError: ERR Operation against a key holding the wrong kind of value>
      p e.redis_error
    }
  }
}
