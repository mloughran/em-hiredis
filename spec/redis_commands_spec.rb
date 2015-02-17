require 'spec_helper'

describe EventMachine::Hiredis, "commands" do
  it "pings" do
    connect do |redis|
      redis.ping.callback { |r| r.should == 'PONG'; done }
    end
  end

  it "SETs and GETs a key" do
    connect do |redis|
      redis.set('foo', 'nik').errback { fail }
      redis.get('foo').callback { |r| r.should == 'nik'; done }
    end
  end

  it "handles trailing newline characters" do
    connect do |redis|
      redis.set('foo', "bar\n").errback { fail }
      redis.get('foo').callback { |r| r.should == "bar\n"; done }
    end
  end

  it "stores and retrieves all possible characters at the beginning and the end of a string" do
    connect do |redis|
      (0..255).each do |char_idx|
        string = "#{char_idx.chr}---#{char_idx.chr}"
        if RUBY_VERSION > "1.9"
          string.force_encoding("UTF-8")
        end
        redis.set('foo', string).errback { fail }
        redis.get('foo').callback { |r| r.should == string }.errback { fail }
      end
      redis.ping.callback { done }
    end
  end

  it "SETs a key with an expiry" do
    connect do |redis|
      timeout(3)

      redis.setex('foo', 1, 'bar').errback { fail }
      redis.get('foo').callback { |r| r.should == 'bar' }.errback { fail }
      EventMachine.add_timer(2) do
        redis.get('foo').callback { |r| r.should == nil }.errback { fail }
        redis.ping.callback { done }
      end
    end
  end

  it "gets TTL for a key" do
    connect do |redis|
      redis.setex('foo', 1, 'bar').errback { fail }
      redis.ttl('foo').callback { |r| r.should == 1; done }
    end
  end

  it "can SETNX" do
    connect do |redis|
      redis.set('foo', 'nik').errback { fail }
      redis.get('foo').callback { |r| r.should == 'nik' }.errback { fail }
      redis.setnx('foo', 'bar').errback { fail }
      redis.get('foo').callback { |r| r.should == 'nik' }.errback { fail }

      redis.ping.callback { done }
    end
  end

  it "can GETSET" do
    connect do |redis|
      redis.set('foo', 'bar').errback { fail }
      redis.getset('foo', 'baz').callback { |r| r.should == 'bar' }.errback { fail }
      redis.get('foo').callback { |r| r.should == 'baz'; done }
    end
  end

  it "can INCR a key" do
    connect do |redis|
      redis.del('counter').errback { fail }
      redis.incr('counter').callback { |r| r.should == 1 }.errback { fail }
      redis.incr('counter').callback { |r| r.should == 2 }.errback { fail }
      redis.incr('counter').callback { |r| r.should == 3 }.errback { fail }

      redis.ping.callback { done }
    end
  end

  it "can INCRBY a key" do
    connect do |redis|
      redis.del('counter').errback { fail }
      redis.incrby('counter', 1).callback { |r| r.should == 1 }.errback { fail }
      redis.incrby('counter', 2).callback { |r| r.should == 3 }.errback { fail }
      redis.incrby('counter', 3).callback { |r| r.should == 6 }.errback { fail }

      redis.ping.callback { done }
    end
  end

  it "can DECR a key" do
    connect do |redis|
      redis.del('counter').errback { fail }
      redis.incr('counter').callback { |r| r.should == 1 }.errback { fail }
      redis.incr('counter').callback { |r| r.should == 2 }.errback { fail }
      redis.incr('counter').callback { |r| r.should == 3 }.errback { fail }
      redis.decr('counter').callback { |r| r.should == 2 }.errback { fail }
      redis.decrby('counter', 2).callback { |r| r.should == 0; done }
    end
  end

  it "can RANDOMKEY" do
    connect do |redis|
      redis.set('foo', 'bar').errback { fail }
      redis.randomkey.callback { |r| r.should_not == nil; done }
    end
  end

  it "can RENAME a key" do
    connect do |redis|
      redis.del('foo').errback { fail }
      redis.del('bar').errback { fail }
      redis.set('foo', 'hi').errback { fail }
      redis.rename('foo', 'bar').errback { fail }
      redis.get('bar').callback { |r| r.should == 'hi' ; done }
    end
  end

  it "can RENAMENX a key" do
    connect do |redis|
      redis.del('foo').errback { fail }
      redis.del('bar').errback { fail }
      redis.set('foo', 'hi').errback { fail }
      redis.set('bar', 'ohai').errback { fail }
      redis.renamenx('foo', 'bar').errback { fail }
      redis.get('bar').callback { |r| r.should == 'ohai' ; done }
    end
  end

  it "can get DBSIZE of the database" do
    connect do |redis|
      redis.set('foo1', 'bar').errback { fail }
      redis.set('foo2', 'baz').errback { fail }
      redis.set('foo3', 'bat').errback { fail }
      redis.dbsize.callback { |r|
        r.should == 3
        done
      }
    end
  end

  it "can EXPIRE a key" do
    connect do |redis|
      timeout(3)

      redis.set('foo', 'bar').errback { fail }
      redis.expire('foo', 1).errback { fail }
      redis.get('foo').callback { |r| r.should == "bar" }.errback { fail }
      EventMachine.add_timer(2) do
        redis.get('foo').callback { |r| r.should == nil }.errback { fail }
        redis.ping.callback { done }
      end
    end
  end


  it "can check if a key EXISTS" do
    connect do |redis|
      redis.set('foo', 'nik').errback { fail }
      redis.exists('foo').callback { |r| r.should == 1 }.errback { fail }
      redis.del('foo').errback { fail }
      redis.exists('foo').callback { |r| r.should == 0 ; done }
    end
  end

  it "can list KEYS" do
    connect do |redis|
      redis.keys("f*") { |keys| keys.each { |key| @r.del key } }.errback { fail }
      redis.set('f', 'nik').errback { fail }
      redis.set('fo', 'nak').errback { fail }
      redis.set('foo', 'qux').errback { fail }
      redis.keys("f*").callback { |r| r.sort.should == ['f', 'fo', 'foo'].sort }.errback { fail }

      redis.ping.callback { done }
    end
  end

  it "returns a random key (RANDOMKEY)" do
    connect do |redis|
      redis.set("foo", "bar").errback { fail }
      redis.randomkey { |r|
        redis.exists(r) { |e|
          e.should == 1
          done
        }
      }.errback { fail }
    end
  end

  it "should be able to check the TYPE of a key" do
    connect do |redis|
      redis.set('foo', 'nik').errback { fail }
      redis.type('foo').callback { |r| r.should == "string" }.errback { fail }
      redis.del('foo').errback { fail }
      redis.type('foo').callback { |r| r.should == "none" ; done }
    end
  end

  it "pushes to the head of a list (LPUSH)" do
    connect do |redis|
      redis.lpush("list", 'hello').errback { fail }
      redis.lpush("list", 42).errback { fail }
      redis.type('list').callback { |r| r.should == "list" }.errback { fail }
      redis.llen('list').callback { |r| r.should == 2 }.errback { fail }
      redis.lpop('list').callback { |r| r.should == '42'; done }
    end
  end

  it "pushes to the tail of a list (RPUSH)" do
    connect do |redis|
      redis.rpush("list", 'hello').errback { fail }
      redis.type('list').callback { |r| r.should == "list" }.errback { fail }
      redis.llen('list').callback { |r| r.should == 1 ; done }
    end
  end

  it "pops the tail of a list (RPOP)" do
    connect do |redis|
      redis.rpush("list", 'hello').errback { fail }
      redis.rpush("list", 'goodbye').errback { fail }
      redis.type('list').callback { |r| r.should == "list" }.errback { fail }
      redis.llen('list').callback { |r| r.should == 2 }.errback { fail }
      redis.rpop('list').callback { |r| r.should == 'goodbye'; done }
    end
  end

  it "pop the head of a list (LPOP)" do
    connect do |redis|
      redis.rpush("list", 'hello').errback { fail }
      redis.rpush("list", 'goodbye').errback { fail }
      redis.type('list').callback { |r| r.should == "list" }.errback { fail }
      redis.llen('list').callback { |r| r.should == 2 }.errback { fail }
      redis.lpop('list').callback { |r| r.should == 'hello'; done }
    end
  end

  it "gets the length of a list (LLEN)" do
    connect do |redis|
      redis.rpush("list", 'hello').errback { fail }
      redis.rpush("list", 'goodbye').errback { fail }
      redis.type('list').callback { |r| r.should == "list" }.errback { fail }
      redis.llen('list').callback { |r| r.should == 2 ; done }
    end
  end

  it "gets a range of values from a list (LRANGE)" do
    connect do |redis|
      redis.rpush("list", 'hello').errback { fail }
      redis.rpush("list", 'goodbye').errback { fail }
      redis.rpush("list", '1').errback { fail }
      redis.rpush("list", '2').errback { fail }
      redis.rpush("list", '3').errback { fail }
      redis.type('list').callback { |r| r.should == "list" }.errback { fail }
      redis.llen('list').callback { |r| r.should == 5 }.errback { fail }
      redis.lrange('list', 2, -1).callback { |r| r.should == ['1', '2', '3']; done }
    end
  end

  it "trims a list (LTRIM)" do
    connect do |redis|
      redis.rpush("list", 'hello').errback { fail }
      redis.rpush("list", 'goodbye').errback { fail }
      redis.rpush("list", '1').errback { fail }
      redis.rpush("list", '2').errback { fail }
      redis.rpush("list", '3').errback { fail }
      redis.type('list').callback { |r| r.should == "list" }.errback { fail }
      redis.llen('list').callback { |r| r.should == 5 }.errback { fail }
      redis.ltrim('list', 0, 1).errback { fail }
      redis.llen('list').callback { |r| r.should == 2 }.errback { fail }
      redis.lrange('list', 0, -1).callback { |r| r.should == ['hello', 'goodbye']; done }
    end
  end

  it "gets a value by indexing into a list (LINDEX)" do
    connect do |redis|
      redis.rpush("list", 'hello').errback { fail }
      redis.rpush("list", 'goodbye').errback { fail }
      redis.type('list').callback { |r| r.should == "list" }.errback { fail }
      redis.llen('list').callback { |r| r.should == 2 }.errback { fail }
      redis.lindex('list', 1).callback { |r| r.should == 'goodbye'; done }
    end
  end

  it "sets a value by indexing into a list (LSET)" do
    connect do |redis|
      redis.rpush("list", 'hello').errback { fail }
      redis.rpush("list", 'hello').errback { fail }
      redis.type('list').callback { |r| r.should == "list" }.errback { fail }
      redis.llen('list').callback { |r| r.should == 2 }.errback { fail }
      redis.lset('list', 1, 'goodbye').callback { |r| r.should == 'OK' }.errback { fail }
      redis.lindex('list', 1).callback { |r| r.should == 'goodbye'; done }
    end
  end

  it "removes values from a list (LREM)" do
    connect do |redis|
      redis.rpush("list", 'hello').errback { fail }
      redis.rpush("list", 'goodbye').errback { fail }
      redis.type('list').callback { |r| r.should == "list" }.errback { fail }
      redis.llen('list').callback { |r| r.should == 2 }.errback { fail }
      redis.lrem('list', 1, 'hello').callback { |r| r.should == 1 }.errback { fail }
      redis.lrange('list', 0, -1).callback { |r| r.should == ['goodbye']; done }
    end
  end

  it "pops values from a list and push them onto a temp list(RPOPLPUSH)" do
    connect do |redis|
      redis.rpush("list", 'one').errback { fail }
      redis.rpush("list", 'two').errback { fail }
      redis.rpush("list", 'three').errback { fail }
      redis.type('list').callback { |r| r.should == "list" }.errback { fail }
      redis.llen('list').callback { |r| r.should == 3 }.errback { fail }
      redis.lrange('list', 0, -1).callback { |r| r.should == ['one', 'two', 'three'] }.errback { fail }
      redis.lrange('tmp', 0, -1).callback { |r| r.should == [] }.errback { fail }
      redis.rpoplpush('list', 'tmp').callback { |r| r.should == 'three' }.errback { fail }
      redis.lrange('tmp', 0, -1).callback { |r| r.should == ['three'] }.errback { fail }
      redis.rpoplpush('list', 'tmp').callback { |r| r.should == 'two' }.errback { fail }
      redis.lrange('tmp', 0, -1).callback { |r| r.should == ['two', 'three'] }.errback { fail }
      redis.rpoplpush('list', 'tmp').callback { |r| r.should == 'one' }.errback { fail }
      redis.lrange('tmp', 0, -1).callback { |r| r.should == ['one', 'two', 'three']; done }
    end
  end

  it "adds members to a set (SADD)" do
    connect do |redis|
      redis.sadd("set", 'key1').errback { fail }
      redis.sadd("set", 'key2').errback { fail }
      redis.type('set').callback { |r| r.should == "set" }.errback { fail }
      redis.scard('set').callback { |r| r.should == 2 }.errback { fail }
      redis.smembers('set').callback { |r| r.sort.should == ['key1', 'key2'].sort; done }
    end
  end

  it "deletes members to a set (SREM)" do
    connect do |redis|
      redis.sadd("set", 'key1').errback { fail }
      redis.sadd("set", 'key2').errback { fail }
      redis.type('set').callback { |r| r.should == "set" }.errback { fail }
      redis.scard('set').callback { |r| r.should == 2 }.errback { fail }
      redis.smembers('set').callback { |r| r.sort.should == ['key1', 'key2'].sort }.errback { fail }
      redis.srem('set', 'key1').errback { fail }
      redis.scard('set').callback { |r| r.should == 1 }.errback { fail }
      redis.smembers('set').callback { |r| r.should == ['key2']; done }
    end
  end

  it "returns and remove random key from set (SPOP)" do
    connect do |redis|
      redis.sadd("set_pop", "key1").errback { fail }
      redis.sadd("set_pop", "key2").errback { fail }
      redis.spop("set_pop").callback { |r| r.should_not == nil }.errback { fail }
      redis.scard("set_pop").callback { |r| r.should == 1; done }
    end
  end

  it "returns random key without delete the key from a set (SRANDMEMBER)" do
    connect do |redis|
      redis.sadd("set_srandmember", "key1").errback { fail }
      redis.sadd("set_srandmember", "key2").errback { fail }
      redis.srandmember("set_srandmember").callback { |r| r.should_not == nil }.errback { fail }
      redis.scard("set_srandmember").callback { |r| r.should == 2; done }
    end
  end

  it "counts the members of a set (SCARD)" do
    connect do |redis|
      redis.sadd("set", 'key1').errback { fail }
      redis.sadd("set", 'key2').errback { fail }
      redis.type('set').callback { |r| r.should == "set" }.errback { fail }
      redis.scard('set').callback { |r| r.should == 2; done }
    end
  end

  it "tests for set membership (SISMEMBER)" do
    connect do |redis|
      redis.sadd("set", 'key1').errback { fail }
      redis.sadd("set", 'key2').errback { fail }
      redis.type('set').callback { |r| r.should == "set" }.errback { fail }
      redis.scard('set').callback { |r| r.should == 2 }.errback { fail }
      redis.sismember('set', 'key1').callback { |r| r.should == 1 }.errback { fail }
      redis.sismember('set', 'key2').callback { |r| r.should == 1 }.errback { fail }
      redis.sismember('set', 'notthere').callback { |r| r.should == 0; done }
    end
  end

  it "intersects sets (SINTER)" do
    connect do |redis|
      redis.sadd("set", 'key1').errback { fail }
      redis.sadd("set", 'key2').errback { fail }
      redis.sadd("set2", 'key2').errback { fail }
      redis.sinter('set', 'set2').callback { |r| r.should == ['key2']; done }
    end
  end

  it "intersects set and stores the results in a key (SINTERSTORE)" do
    connect do |redis|
      redis.sadd("set", 'key1').errback { fail }
      redis.sadd("set", 'key2').errback { fail }
      redis.sadd("set2", 'key2').errback { fail }
      redis.sinterstore('newone', 'set', 'set2').callback { |r| r.should == 1 }.errback { fail }
      redis.smembers('newone').callback { |r| r.should == ['key2']; done }
    end
  end

  it "performs set unions (SUNION)" do
    connect do |redis|
      redis.sadd("set", 'key1').errback { fail }
      redis.sadd("set", 'key2').errback { fail }
      redis.sadd("set2", 'key2').errback { fail }
      redis.sadd("set2", 'key3').errback { fail }
      redis.sunion('set', 'set2').callback { |r| r.sort.should == ['key1','key2','key3'].sort; done }
    end
  end

  it "performs a set union and store the results in a key (SUNIONSTORE)" do
    connect do |redis|
      redis.sadd("set", 'key1').errback { fail }
      redis.sadd("set", 'key2').errback { fail }
      redis.sadd("set2", 'key2').errback { fail }
      redis.sadd("set2", 'key3').errback { fail }
      redis.sunionstore('newone', 'set', 'set2').callback { |r| r.should == 3 }.errback { fail }
      redis.smembers('newone').callback { |r| r.sort.should == ['key1','key2','key3'].sort; done }
    end
  end

  it "takes a set difference (SDIFF)" do
    connect do |redis|
      redis.sadd("set", 'a').errback { fail }
      redis.sadd("set", 'b').errback { fail }
      redis.sadd("set2", 'b').errback { fail }
      redis.sadd("set2", 'c').errback { fail }
      redis.sdiff('set', 'set2').callback { |r| r.should == ['a']; done }
    end
  end

  it "takes set difference and store the results in a key (SDIFFSTORE)" do
    connect do |redis|
      redis.sadd("set", 'a').errback { fail }
      redis.sadd("set", 'b').errback { fail }
      redis.sadd("set2", 'b').errback { fail }
      redis.sadd("set2", 'c').errback { fail }
      redis.sdiffstore('newone', 'set', 'set2').errback { fail }
      redis.smembers('newone').callback { |r| r.should == ['a']; done }
    end
  end

  it "moves elements from one set to another (SMOVE)" do
    connect do |redis|
      redis.sadd('set1', 'a').errback { fail }
      redis.sadd('set1', 'b').errback { fail }
      redis.sadd('set2', 'x').errback { fail }
      redis.smove('set1', 'set2', 'a').callback { |r| r.should == 1 }.errback { fail }
      redis.sismember('set2', 'a').callback { |r| r.should == 1 }.errback { fail }
      redis.del('set1') { done }
    end
  end

  it "counts the members of a zset" do
    connect do |redis|
      redis.sadd("set", 'key1').errback { fail }
      redis.sadd("set", 'key2').errback { fail }
      redis.zadd('zset', 1, 'set').errback { fail }
      redis.zcount('zset', '-inf', '+inf').callback { |r| r.should == 1 }.errback { fail }
      redis.del('set').errback { fail }
      redis.del('zset') { done }
    end
  end

  it "adds members to a zset" do
    connect do |redis|
      redis.sadd("set", 'key1').errback { fail }
      redis.sadd("set", 'key2').errback { fail }
      redis.zadd('zset', 1, 'set').errback { fail }
      redis.zrange('zset', 0, 1).callback { |r| r.should == ['set'] }.errback { fail }
      redis.zcount('zset', '-inf', '+inf').callback { |r| r.should == 1 }.errback { fail }
      redis.del('set').errback { fail }
      redis.del('zset') { done }
    end
  end

  it "deletes members from a zset" do
    connect do |redis|
      redis.sadd("set", 'key1').errback { fail }
      redis.sadd("set", 'key2').errback { fail }
      redis.type('set').callback { |r| r.should == "set" }.errback { fail }
      redis.sadd("set2", 'key3').errback { fail }
      redis.sadd("set2", 'key4').errback { fail }
      redis.type('set2').callback { |r| r.should == "set" }.errback { fail }
      redis.zadd('zset', 1, 'set').errback { fail }
      redis.zcount('zset', '-inf', '+inf').callback { |r| r.should == 1 }.errback { fail }
      redis.zadd('zset', 2, 'set2').errback { fail }
      redis.zcount('zset', '-inf', '+inf').callback { |r| r.should == 2 }.errback { fail }
      redis.zrem('zset', 'set').errback { fail }
      redis.zcount('zset', '-inf', '+inf').callback { |r| r.should == 1 }.errback { fail }
      redis.del('set').errback { fail }
      redis.del('set2').errback { fail }
      redis.del('zset') { done }
    end
  end

  it "gets a range of values from a zset" do
    connect do |redis|
      redis.sadd("set", 'key1').errback { fail }
      redis.sadd("set", 'key2').errback { fail }
      redis.sadd("set2", 'key3').errback { fail }
      redis.sadd("set2", 'key4').errback { fail }
      redis.sadd("set3", 'key1').errback { fail }
      redis.type('set').callback { |r| r.should == 'set' }.errback { fail }
      redis.type('set2').callback { |r| r.should == 'set' }.errback { fail }
      redis.type('set3').callback { |r| r.should == 'set' }.errback { fail }
      redis.zadd('zset', 1, 'set').errback { fail }
      redis.zadd('zset', 2, 'set2').errback { fail }
      redis.zadd('zset', 3, 'set3').errback { fail }
      redis.zcount('zset', '-inf', '+inf').callback { |r| r.should == 3 }.errback { fail }
      redis.zrange('zset', 0, 3).callback { |r| r.should == ['set', 'set2', 'set3'] }.errback { fail }
      redis.del('set').errback { fail }
      redis.del('set2').errback { fail }
      redis.del('set3').errback { fail }
      redis.del('zset') { done }
    end
  end

  it "gets a reverse range of values from a zset" do
    connect do |redis|
      redis.sadd("set", 'key1').errback { fail }
      redis.sadd("set", 'key2').errback { fail }
      redis.sadd("set2", 'key3').errback { fail }
      redis.sadd("set2", 'key4').errback { fail }
      redis.sadd("set3", 'key1').errback { fail }
      redis.type('set').callback { |r| r.should == 'set' }.errback { fail }
      redis.type('set2').callback { |r| r.should == 'set' }.errback { fail }
      redis.type('set3').callback { |r| r.should == 'set' }.errback { fail }
      redis.zadd('zset', 1, 'set').errback { fail }
      redis.zadd('zset', 2, 'set2').errback { fail }
      redis.zadd('zset', 3, 'set3').errback { fail }
      redis.zcount('zset', '-inf', '+inf').callback { |r| r.should == 3 }.errback { fail }
      redis.zrevrange('zset', 0, 3).callback { |r| r.should == ['set3', 'set2', 'set'] }.errback { fail }
      redis.del('set').errback { fail }
      redis.del('set2').errback { fail }
      redis.del('set3').errback { fail }
      redis.del('zset') { done }
    end
  end

  it "gets a range by score of values from a zset" do
    connect do |redis|
      redis.sadd("set", 'key1').errback { fail }
      redis.sadd("set", 'key2').errback { fail }
      redis.sadd("set2", 'key3').errback { fail }
      redis.sadd("set2", 'key4').errback { fail }
      redis.sadd("set3", 'key1').errback { fail }
      redis.sadd("set4", 'key4').errback { fail }
      redis.zadd('zset', 1, 'set').errback { fail }
      redis.zadd('zset', 2, 'set2').errback { fail }
      redis.zadd('zset', 3, 'set3').errback { fail }
      redis.zadd('zset', 4, 'set4').errback { fail }
      redis.zcount('zset', '-inf', '+inf').callback { |r| r.should == 4 }.errback { fail }
      redis.zrangebyscore('zset', 2, 3).callback { |r| r.should == ['set2', 'set3'] }.errback { fail }
      redis.del('set').errback { fail }
      redis.del('set2').errback { fail }
      redis.del('set3').errback { fail }
      redis.del('set4').errback { fail }
      redis.del('zset') { done }
    end
  end

  it "gets a score for a specific value in a zset (ZSCORE)" do
    connect do |redis|
      redis.zadd("zset", 23, "value").errback { fail }
      redis.zscore("zset", "value").callback { |r| r.should == "23" }.errback { fail }

      redis.zscore("zset", "value2").callback { |r| r.should == nil }.errback { fail }
      redis.zscore("unknown_zset", "value").callback { |r| r.should == nil }.errback { fail }

      redis.del("zset").callback { done }
    end
  end

  it "increments a range score of a zset (ZINCRBY)" do
    connect do |redis|
      # create a new zset
      redis.zincrby("hackers", 1965, "Yukihiro Matsumoto").errback { fail }
      redis.zscore("hackers", "Yukihiro Matsumoto").callback { |r| r.should == "1965" }.errback { fail }

      # add a new element
      redis.zincrby("hackers", 1912, "Alan Turing").errback { fail }
      redis.zscore("hackers", "Alan Turing").callback { |r| r.should == "1912" }.errback { fail }

      # update the score
      redis.zincrby("hackers", 100, "Alan Turing").errback { fail } # yeah, we are making Turing a bit younger
      redis.zscore("hackers", "Alan Turing").callback { |r| r.should == "2012" }.errback { fail }

      # attempt to update a key that's not a zset
      redis.set("i_am_not_a_zet", "value").errback { fail }
      # shouldn't raise error anymore
      redis.zincrby("i_am_not_a_zet", 23, "element").errback { |e| e.message.should =~ /WRONGTYPE/ }.callback { fail }

      redis.del("hackers").errback { fail }
      redis.del("i_am_not_a_zet") { done }
    end
  end

  it "provides info (INFO)" do
    connect do |redis|
      redis.info.callback { |r|
        [:redis_version, :total_connections_received, :connected_clients, :total_commands_processed, :connected_slaves, :uptime_in_seconds, :used_memory, :uptime_in_days].each do |x|
          r.keys.include?(x).should == true
        end
        done
      }
    end
  end

  it "provides commandstats (INFO COMMANDSTATS)" do
    connect do |redis|
      redis.info_commandstats { |r|
        r[:get][:calls].should be_a_kind_of(Integer)
        r[:get][:usec].should be_a_kind_of(Integer)
        r[:get][:usec_per_call].should be_a_kind_of(Float)
        done
      }
    end
  end

  it "flushes the database (FLUSHDB)" do
    connect do |redis|
      redis.set('key1', 'keyone').errback { fail }
      redis.set('key2', 'keytwo').errback { fail }
      redis.keys('*').callback { |r| r.sort.should == ['key1', 'key2'].sort }.errback { fail }
      redis.flushdb.errback { fail }
      redis.keys('*').callback { |r| r.should == []; done }
    end
  end

  it "SELECTs database" do
    connect do |redis|
      redis.set("foo", "bar").callback { |set_response|
        redis.select("10").callback { |select_response|
          redis.get("foo").callback { |get_response|
            get_response.should == nil; done
          }
        }
      }
    end
  end

  it "SELECTs database without a callback" do
    connect do |redis|
      redis.select("9").errback { fail }
      redis.incr("foo").callback { |response|
        response.should == 1
        done
      }
    end
  end

  it "provides the last save time (LASTSAVE)" do
    connect do |redis|
      redis.lastsave.callback { |savetime|
        Time.at(savetime).class.should == Time
        Time.at(savetime).should <= Time.now
        done
      }.errback { fail }
    end
  end

  it "can MGET keys" do
    connect do |redis|
      redis.set('foo', 1000).errback { fail }
      redis.set('bar', 2000).errback { fail }
      redis.mget('foo', 'bar').callback { |r| r.should == ['1000', '2000'] }.errback { fail }
      redis.mget('foo', 'bar', 'baz').callback { |r| r.should == ['1000', '2000', nil] }.errback { fail }
      redis.ping.callback { done }
    end
  end

  it "can MSET values" do
    connect do |redis|
      redis.mset("key1", "value1", "key2", "value2").errback { fail }
      redis.get('key1').callback { |r| r.should == "value1" }.errback { fail }
      redis.get('key2').callback { |r| r.should == "value2"; done }
    end
  end

  it "can MSETNX values" do
    connect do |redis|
      redis.msetnx("keynx1", "valuenx1", "keynx2", "valuenx2").errback { fail }
      redis.mget('keynx1', 'keynx2').callback { |r| r.should == ["valuenx1", "valuenx2"] }.errback { fail }

      redis.set("keynx1", "value1").errback { fail }
      redis.set("keynx2", "value2").errback { fail }
      redis.msetnx("keynx1", "valuenx1", "keynx2", "valuenx2").errback { fail }
      redis.mget('keynx1', 'keynx2').callback { |r| r.should == ["value1", "value2"]; done }
    end
  end

  it "can BGSAVE" do
    connect do |redis|
      redis.bgsave.callback { |r|
        ['OK', 'Background saving started'].include?(r).should == true
        done
      }.errback { fail }
    end
  end

  it "can ECHO" do
    connect do |redis|
      redis.echo("message in a bottle\n").callback { |r| r.should == "message in a bottle\n"; done }
    end
  end

  it "runs MULTI without a block" do
    connect do |redis|
      redis.multi
      redis.get("key1").callback { |r| r.should == "QUEUED" }.errback { fail }
      redis.discard { done }
    end
  end

  it "runs MULTI/EXEC" do
    connect do |redis|
      redis.multi.errback { fail }
      redis.set("key1", "value1").errback { fail }
      redis.exec.errback { fail }

      redis.get("key1").callback { |r| r.should == "value1" }.errback { fail }

      begin
        redis.multi.errback { fail }
        redis.set("key2", "value2").errback { fail }
        raise "Some error"
        redis.set("key3", "value3")
        redis.exec
      rescue
        redis.discard.errback { fail }
      end

      redis.get("key2").callback { |r| r.should == nil }.errback { fail }
      redis.get("key3").callback { |r| r.should == nil; done }
    end
  end

  it "sets and get hash values" do
    connect do |redis|
      redis.hset("rush", "signals", "1982").callback { |r| r.should == 1 }.errback { fail }
      redis.hexists("rush", "signals").callback { |r| r.should == 1 }.errback { fail }
      redis.hget("rush", "signals").callback { |r| r.should == "1982"; done }
    end
  end

  it "deletes hash values" do
    connect do |redis|
      redis.hset("rush", "YYZ", "1981").errback { fail }
      redis.hdel("rush", "YYZ").callback { |r| r.should == 1 }.errback { fail }
      redis.hexists("rush", "YYZ").callback { |r| r.should == 0; done }
    end
  end
end

describe EventMachine::Hiredis, "with hash values" do
  def set(&blk)
    connect do |redis|
      redis.hset("rush", "permanent waves", "1980").errback { fail }
      redis.hset("rush", "moving pictures", "1981").errback { fail }
      redis.hset("rush", "signals", "1982").errback { fail }
      blk.call(redis)
    end
  end

  it "gets the length of the hash" do
    set do |redis|
      redis.hlen("rush").callback { |r| r.should == 3 }.errback { fail }
      redis.hlen("yyz").callback { |r| r.should == 0; done }
    end
  end

  it "gets the keys and values of the hash" do
    set do |redis|
      redis.hkeys("rush").callback { |r| r.should == ["permanent waves", "moving pictures", "signals"] }.errback { fail }
      redis.hvals("rush").callback { |r| r.should == %w[1980 1981 1982] }.errback { fail }
      redis.hvals("yyz").callback { |r| r.should == []; done }
    end
  end

  it "returns all hash values" do
    set do |redis|
      redis.hgetall("rush").callback { |r|
        r.should == [
          "permanent waves", "1980",
          "moving pictures", "1981",
          "signals"        , "1982"
        ]
      }.errback { fail }
      redis.hgetall("yyz").callback { |r| r.should == []; done }
    end
  end
end

describe EventMachine::Hiredis, "with nested multi-bulk response" do
  def set(&blk)
    connect do |redis|
      redis.set('user:one:id', 'id-one').errback { fail }
      redis.set('user:two:id', 'id-two').errback { fail }
      redis.sadd("user:one:interests", "first-interest").errback { fail }
      redis.sadd("user:one:interests", "second-interest").errback { fail }
      redis.sadd("user:two:interests", "third-interest").errback { fail }
      blk.call(redis)
    end
  end

  it "returns array of arrays" do
    set do |redis|
      redis.multi.errback { fail }
      redis.smembers("user:one:interests")
      redis.smembers("user:two:interests")
      redis.exec.callback { |interests_one, interests_two|
        interests_one.sort.should == ["first-interest", "second-interest"]
        interests_two.should == ['third-interest']
      }.errback { fail }
      redis.mget("user:one:id", "user:two:id").callback { |user_ids|
        user_ids.should == ['id-one', 'id-two']
        done
      }
    end
  end
end

describe EventMachine::Hiredis, "monitor" do
  it "returns monitored commands" do
    connect do |redis|
      # 1. Create 2nd connection to send traffic to monitor
      redis2 = EventMachine::Hiredis.connect("redis://localhost:6379/")
      redis2.callback {
        # 2. Monitor after command has connected
        redis.monitor do |reply|
          reply.should == "OK"

          # 3. Command which should show up in monitor output
          redis2.get('foo')
        end
      }

      redis.on(:monitor) do |line|
        line.should =~ /foo/
        done
      end
    end
  end
end

describe EventMachine::Hiredis, "sorting" do
  context "with some simple sorting data" do
    def set(&blk)
      connect do |redis|
        redis.set('dog_1', 'louie').errback { fail }
        redis.rpush('Dogs', 1).errback { fail }
        redis.set('dog_2', 'lucy').errback { fail }
        redis.rpush('Dogs', 2).errback { fail }
        redis.set('dog_3', 'max').errback { fail }
        redis.rpush('Dogs', 3).errback { fail }
        redis.set('dog_4', 'taj').errback { fail }
        redis.rpush('Dogs', 4).errback { fail }
        blk.call(redis)
      end
    end

    it "sorts with a limit" do
      set do |redis|
        redis.sort('Dogs', "GET", 'dog_*', "LIMIT", "0", "1").callback { |r|
          r.should == ['louie']
          done
        }
      end
    end

    it "sorts with a limit and order" do
      set do |redis|
        redis.sort('Dogs', "GET", 'dog_*', "LIMIT", "0", "1", "desc", "alpha").callback { |r|
          r.should == ['taj']
          done
        }
      end
    end
  end

  context "with more complex sorting data" do
    def set(&blk)
      connect do |redis|
        redis.set('dog:1:name', 'louie').errback { fail }
        redis.set('dog:1:breed', 'mutt').errback { fail }
        redis.rpush('dogs', 1).errback { fail }
        redis.set('dog:2:name', 'lucy').errback { fail }
        redis.set('dog:2:breed', 'poodle').errback { fail }
        redis.rpush('dogs', 2).errback { fail }
        redis.set('dog:3:name', 'max').errback { fail }
        redis.set('dog:3:breed', 'hound').errback { fail }
        redis.rpush('dogs', 3).errback { fail }
        redis.set('dog:4:name', 'taj').errback { fail }
        redis.set('dog:4:breed', 'terrier').errback { fail }
        redis.rpush('dogs', 4).errback { fail }
        blk.call(redis)
      end
    end

    it "handles multiple GETs" do
      set do |redis|
        redis.sort('dogs', 'GET', 'dog:*:name', 'GET', 'dog:*:breed', 'LIMIT', '0', '1').callback { |r|
          r.should == ['louie', 'mutt']
          done
        }
      end
    end

    it "handles multiple GETs with an order" do
      set do |redis|
        redis.sort('dogs', 'GET', 'dog:*:name', 'GET', 'dog:*:breed', 'LIMIT', '0', '1', 'desc', 'alpha').callback { |r|
          r.should == ['taj', 'terrier']
          done
        }
      end
    end
  end
end
