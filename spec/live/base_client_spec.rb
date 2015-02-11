require 'spec_helper'

describe EM::Hiredis::Client do
  it "should be able to connect to redis (required for all tests!)" do
    em {
      redis = EM::Hiredis.connect
      redis.callback {
        done
      }
      redis.errback {
        puts "CHECK THAT THE REDIS SERVER IS RUNNING ON PORT 6379"
        fail
      }
    }
  end

  it "should emit an event on reconnect failure, with the retry count" do
    # Assumes there is no redis server on 9999
    connect(1, "redis://localhost:9999/") do |redis|
      expected = 1
      redis.on(:reconnect_failed) { |count|
        count.should == expected
        expected += 1
        done if expected == 3
      }
    end
  end

  it "should emit an event on reconnect failure, with the retry count (DNS resolution)" do
    # Assumes there is no host for 'not-a-host'
    connect(1, "redis://localhost:6379/") do |redis|
      expected = 1
      redis.on(:reconnect_failed) { |count|
        count.should == expected
        expected += 1
        done if expected == 5
      }

      redis.callback {
        redis.reconnect("redis://not-a-host:9999/")
      }
    end
  end

  it "should fail the client deferrable after 4 unsuccessful attempts" do
    connect(1, "redis://localhost:9999/") do |redis|
      events = []
      redis.on(:reconnect_failed) { |count|
        events << count
      }
      redis.errback { |error|
        error.class.should == EM::Hiredis::Error
        error.message.should == 'Could not connect after 4 attempts'
        events.should == [1,2,3,4]
        done
      }
    end
  end

  it "should allow reconfiguring the client at runtime" do
    connect(1, "redis://localhost:9999/") do |redis|
      redis.on(:reconnect_failed) {
        redis.reconnect("redis://localhost:6379/9")
        redis.info {
          done
        }
      }
    end
  end

  it "should allow connection to be reconnected" do
    connect do |redis|
      redis.on(:reconnected) {
        done
      }
      # Wait for first connection to complete
      redis.callback {
        redis.reconnect
      }
    end
  end

  it "should wrap error responses returned by redis" do
    connect do |redis|
      redis.sadd('foo', 'bar') {
        df = redis.get('foo')
        df.callback {
          fail "Should have received error response from redis"
        }
        df.errback { |e|
          e.class.should == EM::Hiredis::RedisError
          e.should be_kind_of(EM::Hiredis::Error)
          msg = /Operation against a key holding the wrong kind of value/
          e.message.should =~ msg
          # This is the wrapped error from redis:
          e.redis_error.class.should == RuntimeError
          e.redis_error.message.should =~ msg
          done
        }
      }
    end
  end
end
