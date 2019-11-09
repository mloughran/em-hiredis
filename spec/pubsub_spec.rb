require 'spec_helper'

describe EventMachine::Hiredis::PubsubClient, '(un)subscribe' do
  describe "subscribing" do
    it "should return deferrable which succeeds with subscribe call result" do
      connect do |redis|
        df = redis.pubsub_client.subscribe("channel") { }
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
        redis.pubsub_client.subscribe("channel") { |message|
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
        redis.pubsub_client.subscribe("channel", proc).callback {
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
        redis.pubsub_client.subscribe("channel", proc1)
        redis.pubsub_client.subscribe("channel", proc2).callback {
          redis.pubsub_client.unsubscribe_proc("channel", proc1)
          redis.publish("channel", "hello")
        }
      end
    end

    it "should unsubscribe from redis on last proc unsubscription" do
      connect do |redis|
        proc = Proc.new { |message| }
        redis.pubsub_client.subscribe("channel", proc).callback { |subs_count|
          subs_count.should == 1
          redis.pubsub_client.unsubscribe_proc("channel", proc).callback {
            # Slightly awkward way to check that unsubscribe happened:
            redis.pubsub_client.subscribe('channel2').callback { |count|
              # If count is 1 this implies that channel unsubscribed
              count.should == 1
              done
            }
          }
        }
      end
    end

    it "should allow unsubscribing from redis channel, including all callbacks, and return deferrable for redis unsubscribe" do
      connect do |redis|
        # Raw pubsub event
        redis.pubsub_client.on('message') { |channel, message| fail }
        # Block subscription
        redis.pubsub_client.subscribe("channel") { |m| fail } # block
        # Proc example
        df = redis.pubsub_client.subscribe("channel", Proc.new { |m| fail })

        df.callback {
          redis.pubsub_client.unsubscribe("channel").callback { |remaining_subs|
            remaining_subs.should == 0
            redis.publish("channel", "hello") {
              done
            }
          }
        }
      end
    end
  end

  it "should expose raw pubsub events from redis" do
    channel = "channel"
    callback_count = 0
    connect do |redis|
      redis.pubsub_client.on(:subscribe) { |channel, subscription_count|
        # 2. Get subscribe callback
        callback_count += 1
        channel.should == channel
        subscription_count.should == 1

        # 3. Publish on channel
        redis.publish(channel, 'foo')
      }

      redis.pubsub_client.on(:message) { |channel, message|
        # 4. Get message callback
        callback_count += 1
        channel.should == channel
        message.should == 'foo'

        callback_count.should == 2
        done
      }

      # 1. Subscribe to channel
      redis.pubsub_client.subscribe(channel)
    end
  end

  it "should resubscribe to all channels on reconnect" do
    callback_count = 0
    connect do |redis|
      # 1. Subscribe to channels
      redis.pubsub_client.subscribe('channel1') {
        callback_count += 1
      }
      redis.pubsub_client.subscribe('channel2') {
        callback_count += 1
        EM.next_tick {
          # 4. Success if both messages have been received
          callback_count.should == 2
          done
        }
      }.callback { |subscription_count|
        subscription_count.should == 2
        # 2. Subscriptions complete. Now force disconnect
        redis.pubsub_client.instance_variable_get(:@connection).close_connection

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
    it "should return deferrable which succeeds with psubscribe call result" do
      connect do |redis|
        df = redis.pubsub_client.psubscribe("channel") { }
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
        redis.pubsub_client.psubscribe("channel:*") { |channel, message|
          channel.should == 'channel:foo'
          message.should == 'hello'
          done
        }.callback {
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
        redis.pubsub_client.psubscribe("channel:*", proc).callback {
          redis.publish('channel:foo', 'hello')
        }
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
        redis.pubsub_client.psubscribe("channel:*", proc1)
        redis.pubsub_client.psubscribe("channel:*", proc2).callback {
          redis.pubsub_client.punsubscribe_proc("channel:*", proc1)
          redis.publish("channel:foo", "hello")
        }
      end
    end

    it "should punsubscribe from redis on last proc punsubscription" do
      connect do |redis|
        proc = Proc.new { |message| }
        redis.pubsub_client.psubscribe("channel:*", proc).callback { |subs_count|
          subs_count.should == 1
          redis.pubsub_client.punsubscribe_proc("channel:*", proc).callback {
            # Slightly awkward way to check that unsubscribe happened:
            redis.pubsub_client.psubscribe('channel2').callback { |count|
              # If count is 1 this implies that channel unsubscribed
              count.should == 1
              done
            }
          }
        }
      end
    end

    it "should allow punsubscribing from redis channel, including all callbacks, and return deferrable for redis punsubscribe" do
      connect do |redis|
        # Raw pubsub event
        redis.pubsub_client.on('pmessage') { |pattern, channel, message| fail }
        # Block subscription
        redis.pubsub_client.psubscribe("channel") { |c, m| fail } # block
        # Proc example
        df = redis.pubsub_client.psubscribe("channel", Proc.new { |c, m| fail })

        df.callback {
          redis.pubsub_client.punsubscribe("channel").callback { |remaining_subs|
            remaining_subs.should == 0
            redis.publish("channel", "hello") {
              done
            }
          }
        }
      end
    end
  end

  it "should expose raw pattern pubsub events from redis" do
    callback_count = 0
    connect do |redis|
      redis.pubsub_client.on(:psubscribe) { |pattern, subscription_count|
        # 2. Get subscribe callback
        callback_count += 1
        pattern.should == "channel:*"
        subscription_count.should == 1

        # 3. Publish on channel
        redis.publish('channel:foo', 'foo')
      }

      redis.pubsub_client.on(:pmessage) { |pattern, channel, message|
        # 4. Get message callback
        callback_count += 1
        pattern.should == 'channel:*'
        channel.should == 'channel:foo'
        message.should == 'foo'

        callback_count.should == 2
        done
      }

      # 1. Subscribe to channel
      redis.pubsub_client.psubscribe('channel:*')
    end
  end

  it "should resubscribe to all pattern subscriptions on reconnect" do
    callback_count = 0
    connect do |redis|
      # 1. Subscribe to channels
      redis.pubsub_client.psubscribe('foo:*') { |channel, message|
        channel.should == 'foo:a'
        message.should == 'hello foo'
        callback_count += 1
      }
      redis.pubsub_client.psubscribe('bar:*') { |channel, message|
        channel.should == 'bar:b'
        message.should == 'hello bar'
        callback_count += 1
        EM.next_tick {
          # 4. Success if both messages have been received
          callback_count.should == 2
          done
        }
      }.callback { |subscription_count|
        subscription_count.should == 2
        # 2. Subscriptions complete. Now force disconnect
        redis.pubsub_client.instance_variable_get(:@connection).close_connection

        EM.add_timer(0.1) {
          # 3. After giving time to reconnect publish to both channels
          redis.publish('foo:a', 'hello foo')
          redis.publish('bar:b', 'hello bar')
        }
      }
    end
  end
end
