require 'spec_helper'

describe EventMachine::Hiredis, "connected to an empty db" do
  it "sets a string value" do
    connect do |redis|
      redis.set("foo", "bar") do |r|
        r.should == "OK"
        done
      end
    end
  end

  it "increments the value of a string" do
    connect do |redis|
      redis.incr "foo" do |r|
        r.should == 1
        redis.incr "foo" do |r|
          r.should == 2
          done
        end
      end
    end
  end

  it "increments the value of a string by an amount" do
    connect do |redis|
      redis.incrby "foo", 10 do |r|
        r.should == 10
        done
      end
    end
  end

  it "decrements the value of a string" do
    connect do |redis|
      redis.incr "foo" do |r|
        r.should == 1
        redis.decr "foo" do |r|
          r.should == 0
          done
        end
      end
    end
  end

  it "decrement the value of a string by an amount" do
    connect do |redis|
      redis.incrby "foo", 20 do |r|
        r.should == 20
        redis.decrby "foo", 10 do |r|
          r.should == 10
          done
        end
      end
    end
  end

  it "can 'lpush' to a nonexistent list" do
    connect do |redis|
      redis.lpush("foo", "bar") do |r|
        r.should == 1
        done
      end
    end
  end

  it "can 'rpush' to a nonexistent list" do
    connect do |redis|
      redis.rpush("foo", "bar") do |r|
        r.should == 1
        done
      end
    end
  end


  it "gets the size of the database" do
    connect do |redis|
      redis.dbsize do |r|
        r.should == 0
        done
      end
    end
  end

  it "adds a member to a nonexistent set" do
    connect do |redis|
      redis.sadd("set_foo", "bar") do |r|
        r.should == 1
        done
      end
    end
  end

  it "reads info about the db" do
    connect do |redis|
      redis.info do |info|
        info[:redis_version].should_not be_nil
        done
      end
    end
  end

  it "can save the db" do
    connect do |redis|
      redis.save do |r|
        r.should == "OK"
        done
      end
    end
  end

  it "can save the db in the background" do
    connect do |redis|
      redis.bgsave do |r|
        r.should == "Background saving started"
        done
      end
    end
  end
end

describe EventMachine::Hiredis, "connected to a db containing some simple string-valued keys" do
  def set(&blk)
    connect do |redis|
      redis.flushdb
      redis.set "a", "b"
      redis.set "x", "y"
      blk.call(redis)
    end
  end

  it "fetches the values of multiple keys" do
    set do |redis|
      redis.mget "a", "x" do |r|
        r.should == ["b", "y"]
        done
      end
    end
  end

  it "fetches all the keys" do
    set do |redis|
      redis.keys "*" do |r|
        r.sort.should == ["a", "x"]
        done
      end
    end
  end

  it "sets a value if a key doesn't exist" do
    set do |redis|
      redis.setnx "a", "foo" do |r|
        r.should == 0
        redis.setnx "zzz", "foo" do |r|
          r.should == 1
          done
        end
      end
    end
  end

  it "tests for the existence of a key" do
    set do |redis|
      redis.exists "a" do |r|
        r.should == 1
        redis.exists "zzz" do |r|
          r.should == 0
          done
        end
      end
    end
  end

  it "deletes a key" do
    set do |redis|
      redis.del "a" do |r|
        r.should == 1
        redis.exists "a" do |r|
          r.should == 0
          redis.del "a" do |r|
            r.should == 0
            done
          end
        end
      end
    end
  end

  it "detects the type of a key, existing or not" do
    set do |redis|
      redis.type "a" do |r|
        r.should == "string"
        redis.type "zzz" do |r|
          r.should == "none"
          done
        end
      end
    end
  end

  it "renames a key" do
    set do |redis|
      redis.rename "a", "x" do |r|
        redis.get "x" do |r|
          r.should == "b"
          done
        end
      end
    end
  end

  it "renames a key unless it exists" do
    set do |redis|
      redis.renamenx "a", "x" do |r|
        r.should == 0
        redis.renamenx "a", "zzz" do |r|
          r.should == 1
          redis.get "zzz" do |r|
            r.should == "b"
            done
          end
        end
      end
    end
  end
end

describe EventMachine::Hiredis, "connected to a db containing a list" do
  def set(&blk)
    connect do |redis|
      redis.flushdb
      redis.lpush "foo", "c"
      redis.lpush "foo", "b"
      redis.lpush "foo", "a"
      blk.call(redis)
    end
  end

  it "sets a list member and 'lindex' to retrieve it" do
    set do |redis|
      redis.lset("foo",  1, "bar") do |r|
        redis.lindex("foo", 1) do |r|
          r.should == "bar"
          done
        end
      end
    end
  end

  it "pushes onto tail of the list" do
    set do |redis|
      redis.rpush "foo", "d" do |r|
        r.should == 4
        redis.rpop "foo" do |r|
          r.should == "d"
          done
        end
      end
    end
  end

  it "pushes onto the head of the list" do
    set do |redis|
      redis.lpush "foo", "d" do |r|
        r.should == 4
        redis.lpop "foo" do |r|
          r.should == "d"
          done
        end
      end
    end
  end

  it "pops off the tail of the list" do
    set do |redis|
      redis.rpop("foo") do |r|
        r.should == "c"
        done
      end
    end
  end

  it "pops off the tail of the list" do
    set do |redis|
      redis.lpop("foo") do |r|
        r.should == "a"
        done
      end
    end
  end

  it "gets a range of values from a list" do
    set do |redis|
      redis.lrange("foo", 0, 1) do |r|
        r.should == ["a", "b"]
        done
      end
    end
  end

  it "trims a list" do
    set do |redis|
      redis.ltrim("foo", 0, 1) do |r|
        r.should == "OK"
        redis.llen("foo") do |r|
          r.should == 2
          done
        end
      end
    end
  end

  it "removes a list element" do
    set do |redis|
      redis.lrem("foo", 0, "a") do |r|
        r.should == 1
        redis.llen("foo") do |r|
          r.should == 2
          done
        end
      end
    end
  end

  it "detects the type of a list" do
    set do |redis|
      redis.type "foo" do |r|
        r.should == "list"
        done
      end
    end
  end
end

describe EventMachine::Hiredis, "connected to a db containing two sets" do
  def set(&blk)
    connect do |redis|
      redis.flushdb
      redis.sadd "foo", "a"
      redis.sadd "foo", "b"
      redis.sadd "foo", "c"
      redis.sadd "bar", "c"
      redis.sadd "bar", "d"
      redis.sadd "bar", "e"
      blk.call(redis)
    end
  end

  it "finds a set's cardinality" do
    set do |redis|
      redis.scard("foo") do |r|
        r.should == 3
        done
      end
    end
  end

  it "adds a new member to a set unless it is a duplicate" do
    set do |redis|
      redis.sadd("foo", "d") do |r|
        r.should == 1 # success
        redis.sadd("foo", "a") do |r|
          r.should == 0 # failure
          redis.scard("foo") do |r|
            r.should == 4
            done
          end
        end
      end
    end
  end

  it "removes a set member if it exists" do
    set do |redis|
      redis.srem("foo", "a") do |r|
        r.should == 1
        redis.srem("foo", "z") do |r|
          r.should == 0
          redis.scard("foo") do |r|
            r.should == 2
            done
          end
        end
      end
    end
  end

  it "retrieves a set's members" do
    set do |redis|
      redis.smembers("foo") do |r|
        r.sort.should == ["a", "b", "c"]
        done
      end
    end
  end

  it "detects set membership" do
    set do |redis|
      redis.sismember("foo", "a") do |r|
        r.should == 1
        redis.sismember("foo", "z") do |r|
          r.should == 0
          done
        end
      end
    end
  end

  it "finds the sets' intersection" do
    set do |redis|
      redis.sinter("foo", "bar") do |r|
        r.should == ["c"]
        done
      end
    end
  end

  it "finds and stores the sets' intersection" do
    set do |redis|
      redis.sinterstore("baz", "foo", "bar") do |r|
        r.should == 1
        redis.smembers("baz") do |r|
          r.should == ["c"]
          done
        end
      end
    end
  end

  it "finds the sets' union" do
    set do |redis|
      redis.sunion("foo", "bar") do |r|
        r.sort.should == ["a","b","c","d","e"]
        done
      end
    end
  end

  it "finds and stores the sets' union" do
    set do |redis|
      redis.sunionstore("baz", "foo", "bar") do |r|
        r.should == 5
        redis.smembers("baz") do |r|
          r.sort.should == ["a","b","c","d","e"]
          done
        end
      end
    end
  end

  it "detects the type of a set" do
    set do |redis|
      redis.type "foo" do |r|
        r.should == "set"
        done
      end
    end
  end
end

describe EventMachine::Hiredis, "connected to a db containing three linked lists" do
  def set(&blk)
    connect do |redis|
      redis.flushdb
      redis.rpush "foo", "a"
      redis.rpush "foo", "b"
      redis.set "a_sort", "2"
      redis.set "b_sort", "1"
      redis.set "a_data", "foo"
      redis.set "b_data", "bar"
      blk.call(redis)
    end
  end

  it "collates a sorted set of data" do
    set do |redis|
      redis.sort("foo", "BY", "*_sort", "GET", "*_data") do |r|
        r.should == ["bar", "foo"]
        done
      end
    end
  end

  it "gets keys selectively" do
    set do |redis|
      redis.keys "a_*" do |r|
        r.sort.should == ["a_sort", "a_data"].sort
        done
      end
    end
  end
end

describe EventMachine::Hiredis, "when reconnecting" do
  it "select previously selected dataset" do
    connect(3) do |redis|
      #simulate disconnect
      redis.set('foo', 'a') {
        redis.instance_variable_get(:@connection_manager).connection.close_connection_after_writing
      }

      EventMachine.add_timer(2) do
        redis.get('foo') do |r|
          r.should == 'a'
          redis.get('non_existing') do |r|
            r.should == nil
            done
          end
        end
      end
    end
  end
end

describe EventMachine::Hiredis, "when closing_connection" do
  it "should fail deferred commands" do
    errored = false
    connect do |redis|
      redis.callback {
        op = redis.blpop 'empty_list'
        op.callback { fail }
        op.errback { done }

        redis.instance_variable_get(:@connection_manager).connection.close_connection
      }
      EM.add_timer(1) { fail }
    end
  end
end

describe EventMachine::Hiredis, "when redis is blocked by a lua script" do
  it "should select the correct db" do
    script = <<-EOF
      local to_micro = function(t)
        return tonumber(t[1])*1000000 + tonumber(t[2])
      end
      local t0 = to_micro(redis.call("time"))
      local tnow = t0
      repeat
        tnow = to_micro(redis.call("time"))
      until tnow - t0 >= 1000000
    EOF

    # set reconnect timeout to a higher value to avoid too many reconnections
    reconnect_timeout = EM::Hiredis.reconnect_timeout
    EM::Hiredis.reconnect_timeout = 0.5

    connect(9) do |redis1|
      timeout(2)

      redis1.config("get", "lua-time-limit").callback { |original_limit|
        redis1.config("set", "lua-time-limit", 500).callback {
          redis1.eval(script, 0) # run the script, it should take a second
          EM.add_timer(0.1) { # wait for the script to start running
            connect(9) do |redis2|
              redis2.set("test", "545").callback {
                redis2.select(0)
                redis2.get("test").callback { |test_value0|
                  test_value0.should be_nil
                }
                redis2.select(9)
                redis2.get("test").callback { |test_value9|
                  test_value9.should == "545"
                  EM::Hiredis.reconnect_timeout = reconnect_timeout
                  redis1.config("set", "lua-time-limit", original_limit)
                  done
                }
              }.errback { |e|
                fail e
              }
            end
          }
        }
      }
    end
  end
end
