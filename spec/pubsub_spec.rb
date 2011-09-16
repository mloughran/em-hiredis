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
    it "should allow unsubscribing a single callback without unsubscribing from redis" do
      connect do |redis|
        proc1 = Proc.new { |message| fail }
        proc2 = Proc.new { |message|
          message.should == 'hello'
          done
        }
        redis.pubsub.subscribe("channel", proc1)
        redis.pubsub.subscribe("channel", proc2).callback {
          redis.pubsub.unsubscribe_proc("channel", proc1)
          redis.publish("channel", "hello")
        }
      end
    end

    it "should allow unsubscribing from redis channel, including all callbacks, and return deferrable for redis unsubscribe" do
      connect do |redis|
        # Raw pubsub event
        redis.pubsub.on('message') { |channel, message| fail }
        # Block subscription
        redis.pubsub.subscribe("channel") { |m| fail } # block
        # Proc example
        df = redis.pubsub.subscribe("channel", Proc.new { |m| fail })

        df.callback {
          redis.pubsub.unsubscribe("channel").callback { |remaining_subs|
            remaining_subs.should == 0
            redis.publish("channel", "hello") {
              done
            }
          }
        }
      end
    end
  end

  it "should expose raw pubsub events from redis"

  it "should resubscribe to all channels on reconnect"
end
