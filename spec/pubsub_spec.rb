require 'spec_helper'

describe EventMachine::Hiredis::PubsubClient do
  describe "subscribing" do
    it "should return deferrable which succeeds with subscribe call result" do
      connect do |redis|
        df = redis.pubsub.subscribe("channel") { }
        df.should be_kind_of(EventMachine::DefaultDeferrable)
        df.callback { |subscription_count|
          # Subscribe response from redis - indicates that subscription has
          # succeeded and that the current connection has a single
          # subscription
          subscription_count.should == 1
          done
        }
      end
    end

    it "should run the passed block when message received" do
      connect do |redis|
        redis.pubsub.subscribe("channel") { |message|
          message.should == 'hello'
          done
        }.callback {
          redis.publish('channel', 'hello')
        }
      end
    end

    it "should run the passed proc when message received on channel" do
      connect do |redis|
        proc = Proc.new { |message|
          message.should == 'hello'
          done
        }
        redis.pubsub.subscribe("channel", proc).callback {
          redis.publish('channel', 'hello')
        }
      end
    end
  end

  describe "unsubscribing" do
    it "should allow unsubscribing a single callback without unsubscribing from redis"

    it "should allow unsubscribing all callbacks"
  end

  it "should expose raw pubsub events from redis"

  it "should resubscribe to all channels on reconnect"
end
