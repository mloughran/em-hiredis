require 'spec_helper'

describe EventMachine::Hiredis, "commands" do
  it "pings" do
    connect do |redis|
      redis.ping { |r| r.should == 'PONG'; done }
    end
  end

  it "SETs and GETs a key" do
    connect do |redis|
      redis.set('foo', 'nik')
      redis.get('foo') { |r| r.should == 'nik'; done }
    end
  end

  it "handles trailing newline characters" do
    connect do |redis|
      redis.set('foo', "bar\n")
      redis.get('foo') { |r| r.should == "bar\n"; done }
    end
  end

  it "stores and retrieves all possible characters at the beginning and the end of a string" do
    connect do |redis|
      (0..255).each do |char_idx|
        string = "#{char_idx.chr}---#{char_idx.chr}"
        if RUBY_VERSION > "1.9"
          string.force_encoding("UTF-8")
        end
        redis.set('foo', string)
        redis.get('foo') { |r| r.should == string }
      end
      redis.ping { done }
    end
  end

  it "SETs a key with an expiry" do
    connect do |redis|
      timeout(3)

      redis.setex('foo', 1, 'bar')
      redis.get('foo') { |r| r.should == 'bar' }
      EventMachine.add_timer(2) do
        redis.get('foo') { |r| r.should == nil }
        redis.ping { done }
      end
    end
  end

  it "gets TTL for a key" do
    connect do |redis|
      redis.setex('foo', 1, 'bar')
      redis.ttl('foo') { |r| r.should == 1; done }
    end
  end

  it "can SETNX" do
    connect do |redis|
      redis.set('foo', 'nik')
      redis.get('foo') { |r| r.should == 'nik' }
      redis.setnx 'foo', 'bar'
      redis.get('foo') { |r| r.should == 'nik' }

      redis.ping { done }
    end
  end

  it "can GETSET" do
    connect do |redis|
      redis.set('foo', 'bar')
      redis.getset('foo', 'baz') { |r| r.should == 'bar' }
      redis.get('foo') { |r| r.should == 'baz'; done }
    end
  end

  it "can INCR a key" do
    connect do |redis|
      redis.del('counter')
      redis.incr('counter') { |r| r.should == 1 }
      redis.incr('counter') { |r| r.should == 2 }
      redis.incr('counter') { |r| r.should == 3 }

      redis.ping { done }
    end
  end

  it "can INCRBY a key" do
    connect do |redis|
      redis.del('counter')
      redis.incrby('counter', 1) { |r| r.should == 1 }
      redis.incrby('counter', 2) { |r| r.should == 3 }
      redis.incrby('counter', 3) { |r| r.should == 6 }

      redis.ping { done }
    end
  end

  it "can DECR a key" do
    connect do |redis|
      redis.del('counter')
      redis.incr('counter') { |r| r.should == 1 }
      redis.incr('counter') { |r| r.should == 2 }
      redis.incr('counter') { |r| r.should == 3 }
      redis.decr('counter') { |r| r.should == 2 }
      redis.decrby('counter', 2) { |r| r.should == 0; done }
    end
  end

  it "can RANDOMKEY" do
    connect do |redis|
      redis.set('foo', 'bar')
      redis.randomkey { |r| r.should_not == nil; done }
    end
  end

  it "can RENAME a key" do
    connect do |redis|
      redis.del 'foo'
      redis.del 'bar'
      redis.set('foo', 'hi')
      redis.rename 'foo', 'bar'
      redis.get('bar') { |r| r.should == 'hi' ; done }
    end
  end

  it "can RENAMENX a key" do
    connect do |redis|
      redis.del 'foo'
      redis.del 'bar'
      redis.set('foo', 'hi')
      redis.set('bar', 'ohai')
      redis.renamenx 'foo', 'bar'
      redis.get('bar') { |r| r.should == 'ohai' ; done }
    end
  end

  it "can get DBSIZE of the database" do
    connect do |redis|
      redis.set('foo1', 'bar')
      redis.set('foo2', 'baz')
      redis.set('foo3', 'bat')
      redis.dbsize do |r|
        r.should == 3
        done
      end
    end
  end

  it "can EXPIRE a key" do
    connect do |redis|
      timeout(3)

      redis.set('foo', 'bar')
      redis.expire 'foo', 1
      redis.get('foo') { |r| r.should == "bar" }
      EventMachine.add_timer(2) do
        redis.get('foo') { |r| r.should == nil }
        redis.ping { done }
      end
    end
  end


  it "can check if a key EXISTS" do
    connect do |redis|
      redis.set 'foo', 'nik'
      redis.exists('foo') { |r| r.should == 1 }
      redis.del 'foo'
      redis.exists('foo') { |r| r.should == 0 ; done }
    end
  end

  it "can list KEYS" do
    connect do |redis|
      redis.keys("f*") { |keys| keys.each { |key| @r.del key } }
      redis.set('f', 'nik')
      redis.set('fo', 'nak')
      redis.set('foo', 'qux')
      redis.keys("f*") { |r| r.sort.should == ['f', 'fo', 'foo'].sort }

      redis.ping { done }
    end
  end

  it "returns a random key (RANDOMKEY)" do
    connect do |redis|
      redis.set("foo", "bar")
      redis.randomkey do |r|
        redis.exists(r) do |e|
          e.should == 1
          done
        end
      end
    end
  end

  it "should be able to check the TYPE of a key" do
    connect do |redis|
      redis.set('foo', 'nik')
      redis.type('foo') { |r| r.should == "string" }
      redis.del 'foo'
      redis.type('foo') { |r| r.should == "none" ; done }
    end
  end

  it "pushes to the head of a list (LPUSH)" do
    connect do |redis|
      redis.lpush "list", 'hello'
      redis.lpush "list", 42
      redis.type('list') { |r| r.should == "list" }
      redis.llen('list') { |r| r.should == 2 }
      redis.lpop('list') { |r| r.should == '42'; done }
    end
  end

  it "pushes to the tail of a list (RPUSH)" do
    connect do |redis|
      redis.rpush "list", 'hello'
      redis.type('list') { |r| r.should == "list" }
      redis.llen('list') { |r| r.should == 1 ; done }
    end
  end

  it "pops the tail of a list (RPOP)" do
    connect do |redis|
      redis.rpush "list", 'hello'
      redis.rpush"list", 'goodbye'
      redis.type('list') { |r| r.should == "list" }
      redis.llen('list') { |r| r.should == 2 }
      redis.rpop('list') { |r| r.should == 'goodbye'; done }
    end
  end

  it "pop the head of a list (LPOP)" do
    connect do |redis|
      redis.rpush "list", 'hello'
      redis.rpush "list", 'goodbye'
      redis.type('list') { |r| r.should == "list" }
      redis.llen('list') { |r| r.should == 2 }
      redis.lpop('list') { |r| r.should == 'hello'; done }
    end
  end

  it "gets the length of a list (LLEN)" do
    connect do |redis|
      redis.rpush "list", 'hello'
      redis.rpush "list", 'goodbye'
      redis.type('list') { |r| r.should == "list" }
      redis.llen('list') { |r| r.should == 2 ; done }
    end
  end

  it "gets a range of values from a list (LRANGE)" do
    connect do |redis|
      redis.rpush "list", 'hello'
      redis.rpush "list", 'goodbye'
      redis.rpush "list", '1'
      redis.rpush "list", '2'
      redis.rpush "list", '3'
      redis.type('list') { |r| r.should == "list" }
      redis.llen('list') { |r| r.should == 5 }
      redis.lrange('list', 2, -1) { |r| r.should == ['1', '2', '3']; done }
    end
  end

  it "trims a list (LTRIM)" do
    connect do |redis|
      redis.rpush "list", 'hello'
      redis.rpush "list", 'goodbye'
      redis.rpush "list", '1'
      redis.rpush "list", '2'
      redis.rpush "list", '3'
      redis.type('list') { |r| r.should == "list" }
      redis.llen('list') { |r| r.should == 5 }
      redis.ltrim 'list', 0, 1
      redis.llen('list') { |r| r.should == 2 }
      redis.lrange('list', 0, -1) { |r| r.should == ['hello', 'goodbye']; done }
    end
  end

  it "gets a value by indexing into a list (LINDEX)" do
    connect do |redis|
      redis.rpush "list", 'hello'
      redis.rpush "list", 'goodbye'
      redis.type('list') { |r| r.should == "list" }
      redis.llen('list') { |r| r.should == 2 }
      redis.lindex('list', 1) { |r| r.should == 'goodbye'; done }
    end
  end

  it "sets a value by indexing into a list (LSET)" do
    connect do |redis|
      redis.rpush "list", 'hello'
      redis.rpush "list", 'hello'
      redis.type('list') { |r| r.should == "list" }
      redis.llen('list') { |r| r.should == 2 }
      redis.lset('list', 1, 'goodbye') { |r| r.should == 'OK' }
      redis.lindex('list', 1) { |r| r.should == 'goodbye'; done }
    end
  end

  it "removes values from a list (LREM)" do
    connect do |redis|
      redis.rpush "list", 'hello'
      redis.rpush "list", 'goodbye'
      redis.type('list') { |r| r.should == "list" }
      redis.llen('list') { |r| r.should == 2 }
      redis.lrem('list', 1, 'hello') { |r| r.should == 1 }
      redis.lrange('list', 0, -1) { |r| r.should == ['goodbye']; done }
    end
  end

  it "pops values from a list and push them onto a temp list(RPOPLPUSH)" do
    connect do |redis|
      redis.rpush "list", 'one'
      redis.rpush "list", 'two'
      redis.rpush "list", 'three'
      redis.type('list') { |r| r.should == "list" }
      redis.llen('list') { |r| r.should == 3 }
      redis.lrange('list', 0, -1) { |r| r.should == ['one', 'two', 'three'] }
      redis.lrange('tmp', 0, -1) { |r| r.should == [] }
      redis.rpoplpush('list', 'tmp') { |r| r.should == 'three' }
      redis.lrange('tmp', 0, -1) { |r| r.should == ['three'] }
      redis.rpoplpush('list', 'tmp') { |r| r.should == 'two' }
      redis.lrange('tmp', 0, -1) { |r| r.should == ['two', 'three'] }
      redis.rpoplpush('list', 'tmp') { |r| r.should == 'one' }
      redis.lrange('tmp', 0, -1) { |r| r.should == ['one', 'two', 'three']; done }
    end
  end

  it "adds members to a set (SADD)" do
    connect do |redis|
      redis.sadd "set", 'key1'
      redis.sadd "set", 'key2'
      redis.type('set') { |r| r.should == "set" }
      redis.scard('set') { |r| r.should == 2 }
      redis.smembers('set') { |r| r.sort.should == ['key1', 'key2'].sort; done }
    end
  end

  it "deletes members to a set (SREM)" do
    connect do |redis|
      redis.sadd "set", 'key1'
      redis.sadd "set", 'key2'
      redis.type('set') { |r| r.should == "set" }
      redis.scard('set') { |r| r.should == 2 }
      redis.smembers('set') { |r| r.sort.should == ['key1', 'key2'].sort }
      redis.srem('set', 'key1')
      redis.scard('set') { |r| r.should == 1 }
      redis.smembers('set') { |r| r.should == ['key2']; done }
    end
  end

  it "returns and remove random key from set (SPOP)" do
    connect do |redis|
      redis.sadd "set_pop", "key1"
      redis.sadd "set_pop", "key2"
      redis.spop("set_pop") { |r| r.should_not == nil }
      redis.scard("set_pop") { |r| r.should == 1; done }
    end
  end

  it "returns random key without delete the key from a set (SRANDMEMBER)" do
    connect do |redis|
      redis.sadd "set_srandmember", "key1"
      redis.sadd "set_srandmember", "key2"
      redis.srandmember("set_srandmember") { |r| r.should_not == nil }
      redis.scard("set_srandmember") { |r| r.should == 2; done }
    end
  end

  it "counts the members of a set (SCARD)" do
    connect do |redis|
      redis.sadd "set", 'key1'
      redis.sadd "set", 'key2'
      redis.type('set') { |r| r.should == "set" }
      redis.scard('set') { |r| r.should == 2; done }
    end
  end

  it "tests for set membership (SISMEMBER)" do
    connect do |redis|
      redis.sadd "set", 'key1'
      redis.sadd "set", 'key2'
      redis.type('set') { |r| r.should == "set" }
      redis.scard('set') { |r| r.should == 2 }
      redis.sismember('set', 'key1') { |r| r.should == 1 }
      redis.sismember('set', 'key2') { |r| r.should == 1 }
      redis.sismember('set', 'notthere') { |r| r.should == 0; done }
    end
  end

  it "intersects sets (SINTER)" do
    connect do |redis|
      redis.sadd "set", 'key1'
      redis.sadd "set", 'key2'
      redis.sadd "set2", 'key2'
      redis.sinter('set', 'set2') { |r| r.should == ['key2']; done }
    end
  end

  it "intersects set and stores the results in a key (SINTERSTORE)" do
    connect do |redis|
      redis.sadd "set", 'key1'
      redis.sadd "set", 'key2'
      redis.sadd "set2", 'key2'
      redis.sinterstore('newone', 'set', 'set2') { |r| r.should == 1 }
      redis.smembers('newone') { |r| r.should == ['key2']; done }
    end
  end

  it "performs set unions (SUNION)" do
    connect do |redis|
      redis.sadd "set", 'key1'
      redis.sadd "set", 'key2'
      redis.sadd "set2", 'key2'
      redis.sadd "set2", 'key3'
      redis.sunion('set', 'set2') { |r| r.sort.should == ['key1','key2','key3'].sort; done }
    end
  end

  it "performs a set union and store the results in a key (SUNIONSTORE)" do
    connect do |redis|
      redis.sadd "set", 'key1'
      redis.sadd "set", 'key2'
      redis.sadd "set2", 'key2'
      redis.sadd "set2", 'key3'
      redis.sunionstore('newone', 'set', 'set2') { |r| r.should == 3 }
      redis.smembers('newone') { |r| r.sort.should == ['key1','key2','key3'].sort; done }
    end
  end

  it "takes a set difference (SDIFF)" do
    connect do |redis|
      redis.sadd "set", 'a'
      redis.sadd "set", 'b'
      redis.sadd "set2", 'b'
      redis.sadd "set2", 'c'
      redis.sdiff('set', 'set2') { |r| r.should == ['a']; done }
    end
  end

  it "takes set difference and store the results in a key (SDIFFSTORE)" do
    connect do |redis|
      redis.sadd "set", 'a'
      redis.sadd "set", 'b'
      redis.sadd "set2", 'b'
      redis.sadd "set2", 'c'
      redis.sdiffstore('newone', 'set', 'set2')
      redis.smembers('newone') { |r| r.should == ['a']; done }
    end
  end

  it "moves elements from one set to another (SMOVE)" do
    connect do |redis|
      redis.sadd 'set1', 'a'
      redis.sadd 'set1', 'b'
      redis.sadd 'set2', 'x'
      redis.smove('set1', 'set2', 'a') { |r| r.should == 1 }
      redis.sismember('set2', 'a') { |r| r.should == 1 }
      redis.del('set1') { done }
    end
  end

  it "counts the members of a zset" do
    connect do |redis|
      redis.sadd "set", 'key1'
      redis.sadd "set", 'key2'
      redis.zadd 'zset', 1, 'set'
      redis.zcount('zset') { |r| r.should == 1 }
      redis.del('set')
      redis.del('zset') { done }
    end
  end

  it "adds members to a zset" do
    connect do |redis|
      redis.sadd "set", 'key1'
      redis.sadd "set", 'key2'
      redis.zadd 'zset', 1, 'set'
      redis.zrange('zset', 0, 1) { |r| r.should == ['set'] }
      redis.zcount('zset') { |r| r.should == 1 }
      redis.del('set')
      redis.del('zset') { done }
    end
  end

  it "deletes members to a zset" do
    connect do |redis|
      redis.sadd "set", 'key1'
      redis.sadd "set", 'key2'
      redis.type?('set') { |r| r.should == "set" }
      redis.sadd "set2", 'key3'
      redis.sadd "set2", 'key4'
      redis.type?('set2') { |r| r.should == "set" }
      redis.zadd 'zset', 1, 'set'
      redis.zcount('zset') { |r| r.should == 1 }
      redis.zadd 'zset', 2, 'set2'
      redis.zcount('zset') { |r| r.should == 2 }
      redis.zset_delete 'zset', 'set'
      redis.zcount('zset') { |r| r.should == 1 }
      redis.del('set')
      redis.del('set2')
      redis.del('zset') { done }
    end
  end

  it "gets a range of values from a zset" do
    connect do |redis|
      redis.sadd "set", 'key1'
      redis.sadd "set", 'key2'
      redis.sadd "set2", 'key3'
      redis.sadd "set2", 'key4'
      redis.sadd "set3", 'key1'
      redis.type?('set') { |r| r.should == 'set' }
      redis.type?('set2') { |r| r.should == 'set' }
      redis.type?('set3') { |r| r.should == 'set' }
      redis.zadd 'zset', 1, 'set'
      redis.zadd 'zset', 2, 'set2'
      redis.zadd 'zset', 3, 'set3'
      redis.zcount('zset') { |r| r.should == 3 }
      redis.zrange('zset', 0, 3) { |r| r.should == ['set', 'set2', 'set3'] }
      redis.del('set')
      redis.del('set2')
      redis.del('set3')
      redis.del('zset') { done }
    end
  end

  it "gets a reverse range of values from a zset" do
    connect do |redis|
      redis.sadd "set", 'key1'
      redis.sadd "set", 'key2'
      redis.sadd "set2", 'key3'
      redis.sadd "set2", 'key4'
      redis.sadd "set3", 'key1'
      redis.type?('set') { |r| r.should == 'set' }
      redis.type?('set2') { |r| r.should == 'set' }
      redis.type?('set3') { |r| r.should == 'set' }
      redis.zadd 'zset', 1, 'set'
      redis.zadd 'zset', 2, 'set2'
      redis.zadd 'zset', 3, 'set3'
      redis.zcount('zset') { |r| r.should == 3 }
      redis.zrevrange('zset', 0, 3) { |r| r.should == ['set3', 'set2', 'set'] }
      redis.del('set')
      redis.del('set2')
      redis.del('set3')
      redis.del('zset') { done }
    end
  end

  it "gets a range by score of values from a zset" do
    connect do |redis|
      redis.sadd "set", 'key1'
      redis.sadd "set", 'key2'
      redis.sadd "set2", 'key3'
      redis.sadd "set2", 'key4'
      redis.sadd "set3", 'key1'
      redis.sadd "set4", 'key4'
      redis.zadd 'zset', 1, 'set'
      redis.zadd 'zset', 2, 'set2'
      redis.zadd 'zset', 3, 'set3'
      redis.zadd 'zset', 4, 'set4'
      redis.zcount('zset') { |r| r.should == 4 }
      redis.zrangebyscore('zset', 2, 3) { |r| r.should == ['set2', 'set3'] }
      redis.del('set')
      redis.del('set2')
      redis.del('set3')
      redis.del('set4')
      redis.del('zset') { done }
    end
  end

  it "gets a score for a specific value in a zset (ZSCORE)" do
    connect do |redis|
      redis.zadd "zset", 23, "value"
      redis.zscore("zset", "value") { |r| r.should == "23" }

      redis.zscore("zset", "value2") { |r| r.should == nil }
      redis.zscore("unknown_zset", "value") { |r| r.should == nil }

      redis.del("zset") { done }
    end
  end

  it "increments a range score of a zset (ZINCRBY)" do
    connect do |redis|
      # create a new zset
      redis.zincrby "hackers", 1965, "Yukihiro Matsumoto"
      redis.zscore("hackers", "Yukihiro Matsumoto") { |r| r.should == "1965" }

      # add a new element
      redis.zincrby "hackers", 1912, "Alan Turing"
      redis.zscore("hackers", "Alan Turing") { |r| r.should == "1912" }

      # update the score
      redis.zincrby "hackers", 100, "Alan Turing" # yeah, we are making Turing a bit younger
      redis.zscore("hackers", "Alan Turing") { |r| r.should == "2012" }

      # attempt to update a key that's not a zset
      redis.set("i_am_not_a_zet", "value")
      # shouldn't raise error anymore
      redis.zincrby("i_am_not_a_zet", 23, "element") { |r| r.should == nil }

      redis.del("hackers")
      redis.del("i_am_not_a_zet") { done }
    end
  end

  it "provides info (INFO)" do
    connect do |redis|
      redis.info do |r|
        [:last_save_time, :redis_version, :total_connections_received, :connected_clients, :total_commands_processed, :connected_slaves, :uptime_in_seconds, :used_memory, :uptime_in_days, :changes_since_last_save].each do |x|
          r.keys.include?(x).should == true
        end
        done
      end
    end
  end

  it "flushes the database (FLUSHDB)" do
    connect do |redis|
      redis.set('key1', 'keyone')
      redis.set('key2', 'keytwo')
      redis.keys('*') { |r| r.sort.should == ['key1', 'key2'].sort }
      redis.flushdb
      redis.keys('*') { |r| r.should == []; done }
    end
  end

  it "SELECTs database" do
    connect do |redis|
      redis.set("foo", "bar") do |set_response|
        redis.select("9") do |select_response|
          redis.get("foo") do |get_response|
            get_response.should == nil; done
          end
        end
      end
    end
  end

  it "SELECTs database without a callback" do
    connect do |redis|
      redis.select("9")
      redis.incr("foo") do |response|
        response.should == 1
        done
      end
    end
  end

  it "provides the last save time (LASTSAVE)" do
    connect do |redis|
      redis.lastsave do |savetime|
        Time.at(savetime).class.should == Time
        Time.at(savetime).should <= Time.now
        done
      end
    end
  end

  it "can MGET keys" do
    connect do |redis|
      redis.set('foo', 1000)
      redis.set('bar', 2000)
      redis.mget('foo', 'bar') { |r| r.should == ['1000', '2000'] }
      redis.mget('foo', 'bar', 'baz') { |r| r.should == ['1000', '2000', nil] }
      redis.ping { done }
    end
  end

  it "can MSET values" do
    connect do |redis|
      redis.mset "key1", "value1", "key2", "value2"
      redis.get('key1') { |r| r.should == "value1" }
      redis.get('key2') { |r| r.should == "value2"; done }
    end
  end

  it "can MSETNX values" do
    connect do |redis|
      redis.msetnx "keynx1", "valuenx1", "keynx2", "valuenx2"
      redis.mget('keynx1', 'keynx2') { |r| r.should == ["valuenx1", "valuenx2"] }

      redis.set("keynx1", "value1")
      redis.set("keynx2", "value2")
      redis.msetnx "keynx1", "valuenx1", "keynx2", "valuenx2"
      redis.mget('keynx1', 'keynx2') { |r| r.should == ["value1", "value2"]; done }
    end
  end

  it "can BGSAVE" do
    connect do |redis|
      redis.bgsave do |r|
        ['OK', 'Background saving started'].include?(r).should == true
        done
      end
    end
  end

  it "can ECHO" do
    connect do |redis|
      redis.echo("message in a bottle\n") { |r| r.should == "message in a bottle\n"; done }
    end
  end

  it "runs MULTI without a block" do
    connect do |redis|
      redis.multi
      redis.get("key1") { |r| r.should == "QUEUED" }
      redis.discard { done }
    end
  end

  it "runs MULTI/EXEC" do
    connect do |redis|
      redis.multi
      redis.set "key1", "value1"
      redis.exec

      redis.get("key1") { |r| r.should == "value1" }

      begin
        redis.multi
        redis.set "key2", "value2"
        raise "Some error"
        redis.set "key3", "value3"
        redis.exec
      rescue
        redis.discard
      end

      redis.get("key2") { |r| r.should == nil }
      redis.get("key3") { |r| r.should == nil; done}
    end
  end

  it "sets and get hash values" do
    connect do |redis|
      redis.hset("rush", "signals", "1982") { |r| r.should == 1 }
      redis.hexists("rush", "signals") { |r| r.should == 1 }
      redis.hget("rush", "signals") { |r| r.should == "1982"; done }
    end
  end

  it "deletes hash values" do
    connect do |redis|
      redis.hset("rush", "YYZ", "1981")
      redis.hdel("rush", "YYZ") { |r| r.should == 1 }
      redis.hexists("rush", "YYZ") { |r| r.should == 0; done }
    end
  end
end

describe EventMachine::Hiredis, "with hash values" do
  def set(&blk)
    connect do |redis|
      redis.hset("rush", "permanent waves", "1980")
      redis.hset("rush", "moving pictures", "1981")
      redis.hset("rush", "signals", "1982")
      blk.call(redis)
    end
  end

  it "gets the length of the hash" do
    set do |redis|
      redis.hlen("rush") { |r| r.should == 3 }
      redis.hlen("yyz") { |r| r.should == 0; done }
    end
  end

  it "gets the keys and values of the hash" do
    set do |redis|
      redis.hkeys("rush") { |r| r.should == ["permanent waves", "moving pictures", "signals"] }
      redis.hvals("rush") { |r| r.should == %w[1980 1981 1982] }
      redis.hvals("yyz") { |r| r.should == []; done }
    end
  end

  it "returns all hash values" do
    set do |redis|
      redis.hgetall("rush") do |r|
        r.should == [
          "permanent waves", "1980",
          "moving pictures", "1981",
          "signals"        , "1982"
        ]
      end
      redis.hgetall("yyz") { |r| r.should == []; done }
    end
  end
end

describe EventMachine::Hiredis, "with nested multi-bulk response" do
  def set(&blk)
    connect do |redis|
      redis.set 'user:one:id', 'id-one'
      redis.set 'user:two:id', 'id-two'
      redis.sadd "user:one:interests", "first-interest"
      redis.sadd "user:one:interests", "second-interest"
      redis.sadd "user:two:interests", "third-interest"
      blk.call(redis)
    end
  end

  it "returns array of arrays" do
    set do |redis|
      redis.multi
      redis.smembers "user:one:interests"
      redis.smembers "user:two:interests"
      redis.exec do |user_interests|
        user_interests.should == [["second-interest", "first-interest"], ['third-interest']]
      end
      redis.mget("user:one:id", "user:two:id") do |user_ids|
        user_ids.should == ['id-one', 'id-two']
        done
      end
    end
  end
end

describe EventMachine::Hiredis, "monitor" do
  it "returns monitored commands" do
    connect do |redis|
      redis.monitor do |reply|
        reply.should == "OK"
      end
      redis.on(:monitor) do |line|
        line.should =~ /monitor/
        done
      end
    end
  end
end

describe EventMachine::Hiredis, "sorting" do
  context "with some simple sorting data" do
    def set(&blk)
      connect do |redis|
        redis.set('dog_1', 'louie')
        redis.rpush 'Dogs', 1
        redis.set('dog_2', 'lucy')
        redis.rpush 'Dogs', 2
        redis.set('dog_3', 'max')
        redis.rpush 'Dogs', 3
        redis.set('dog_4', 'taj')
        redis.rpush 'Dogs', 4
        blk.call(redis)
      end
    end

    it "sorts with a limit" do
      set do |redis|
        redis.sort('Dogs', "GET", 'dog_*', "LIMIT", "0", "1") do |r|
          r.should == ['louie']
          done
        end
      end
    end

    it "sorts with a limit and order" do
      set do |redis|
        redis.sort('Dogs', "GET", 'dog_*', "LIMIT", "0", "1", "desc", "alpha") do |r|
          r.should == ['taj']
          done
        end
      end
    end
  end

  context "with more complex sorting data" do
    def set(&blk)
      connect do |redis|
        redis.set('dog:1:name', 'louie')
        redis.set('dog:1:breed', 'mutt')
        redis.rpush 'dogs', 1
        redis.set('dog:2:name', 'lucy')
        redis.set('dog:2:breed', 'poodle')
        redis.rpush 'dogs', 2
        redis.set('dog:3:name', 'max')
        redis.set('dog:3:breed', 'hound')
        redis.rpush 'dogs', 3
        redis.set('dog:4:name', 'taj')
        redis.set('dog:4:breed', 'terrier')
        redis.rpush 'dogs', 4
        blk.call(redis)
      end
    end

    it "handles multiple GETs" do
      set do |redis|
        redis.sort('dogs', 'GET', 'dog:*:name', 'GET', 'dog:*:breed', 'LIMIT', '0', '1') do |r|
          r.should == ['louie', 'mutt']
          done
        end
      end
    end

    it "handles multiple GETs with an order" do
      set do |redis|
        redis.sort('dogs', 'GET', 'dog:*:name', 'GET', 'dog:*:breed', 'LIMIT', '0', '1', 'desc', 'alpha') do |r|
          r.should == ['taj', 'terrier']
          done
        end
      end
    end
  end
end
