require 'spec_helper'

describe EventMachine::Hiredis::PubsubClient, '(un)subscribe' do
  describe "subscribing" do

    it "should run the passed block when message received" do
      connect do |redis|
        redis.pubsub.subscribe('channel') { |message|
          message.should == 'hello'
          done
        }

        redis.pubsub.on(:subscribe) {
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
        redis.pubsub.subscribe('channel', proc)

        redis.pubsub.on(:subscribe) {
          redis.publish('channel', 'hello')
        }
      end
    end
  end

  it "should expose raw pubsub events from redis" do
    channel = 'channel'
    callback_count = 0
    connect do |redis|
      redis.pubsub.on(:subscribe) { |channel, subscription_count|
        # 2. Get subscribe callback
        callback_count += 1
        channel.should == channel
        subscription_count.should == 1

        # 3. Publish on channel
        redis.publish(channel, 'foo')
      }

      redis.pubsub.on(:message) { |channel, message|
        # 4. Get message callback
        callback_count += 1
        channel.should == channel
        message.should == 'foo'

        callback_count.should == 2
        done
      }

      # 1. Subscribe to channel
      redis.pubsub.subscribe(channel)
    end
  end

  it "should resubscribe to all channels on reconnect" do
    callback_count = 0
    connect do |redis|
      # 1. Subscribe to channels
      redis.pubsub.callback {
        redis.pubsub.subscribe('channel1') {
          done if (callback_count += 1) == 2
        }
        redis.pubsub.subscribe('channel2') {
          done if (callback_count += 1) == 2
        }

        # 2. Subscriptions complete. Now force disconnect
        redis.pubsub.reconnect

        EM.add_timer(0.1) {
          # 3. After giving time to reconnect publish to both channels
          redis.publish('channel1', 'foo')
          redis.publish('channel2', 'bar')
        }
      }
    end
  end
end

describe EventMachine::Hiredis::PubsubClient, 'p(un)subscribe' do
  describe "psubscribing" do
    it "should run the passed block when message received" do
      connect do |redis|
        redis.pubsub.psubscribe("channel:*") { |channel, message|
          channel.should == 'channel:foo'
          message.should == 'hello'
          done
        }

        redis.pubsub.on(:psubscribe) {
          redis.publish('channel:foo', 'hello')
        }
      end
    end

    it "should run the passed proc when message received on channel" do
      connect do |redis|
        proc = Proc.new { |channel, message|
          channel.should == 'channel:foo'
          message.should == 'hello'
          done
        }
        redis.pubsub.psubscribe("channel:*", proc)
        redis.publish('channel:foo', 'hello')
      end
    end
  end

  describe "punsubscribing" do
    it "should allow punsubscribing a single callback without punsubscribing from redis" do
      connect do |redis|
        proc1 = Proc.new { |channel, message| fail }
        proc2 = Proc.new { |channel, message|
          channel.should == 'channel:foo'
          message.should == 'hello'
          done
        }
        redis.pubsub.psubscribe('channel:*', proc1)
        redis.pubsub.psubscribe('channel:*', proc2)
        redis.pubsub.punsubscribe_proc('channel:*', proc1)
        redis.publish('channel:foo', 'hello')
      end
    end

    it "should allow punsubscribing from redis channel, including all callbacks, and return deferrable for redis punsubscribe" do
      connect do |redis|
        # Raw pubsub event
        redis.pubsub.on('pmessage') { |pattern, channel, message| fail }
        # Block subscription
        redis.pubsub.psubscribe('channel') { |c, m| fail } # block
        # Proc example
        redis.pubsub.psubscribe('channel', Proc.new { |c, m| fail })

        redis.pubsub.punsubscribe('channel')

        redis.publish('channel', 'hello').callback {
          EM.add_timer(0.1) {
            done
          }
        }
      end
    end
  end

  it "should expose raw pattern pubsub events from redis" do
    callback_count = 0
    connect do |redis|
      redis.pubsub.on(:psubscribe) { |pattern, subscription_count|
        # 2. Get subscribe callback
        callback_count += 1
        pattern.should == "channel:*"
        subscription_count.should == 1

        # 3. Publish on channel
        redis.publish('channel:foo', 'foo')
      }

      redis.pubsub.on(:pmessage) { |pattern, channel, message|
        # 4. Get message callback
        callback_count += 1
        pattern.should == 'channel:*'
        channel.should == 'channel:foo'
        message.should == 'foo'

        callback_count.should == 2
        done
      }

      # 1. Subscribe to channel
      redis.pubsub.psubscribe('channel:*')
    end
  end

  it "should resubscribe to all pattern subscriptions on reconnect" do
    callback_count = 0
    connect do |redis|
      redis.pubsub.callback {
        # 1. Subscribe to channels
        redis.pubsub.psubscribe('foo:*') { |channel, message|
          channel.should == 'foo:a'
          message.should == 'hello foo'
          done if (callback_count += 1) == 2
        }
        redis.pubsub.psubscribe('bar:*') { |channel, message|
          channel.should == 'bar:b'
          message.should == 'hello bar'
          done if (callback_count += 1) == 2
        }

        # 2. Subscriptions complete. Now force disconnect
        redis.pubsub.reconnect

        EM.add_timer(0.1) {
          # 3. After giving time to reconnect publish to both channels
          redis.publish('foo:a', 'hello foo')
          redis.publish('bar:b', 'hello bar')
        }
      }
    end
  end
end
