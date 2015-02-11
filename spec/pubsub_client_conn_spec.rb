require 'spec_helper'

describe EM::Hiredis::PubsubClient do

  class PubsubTestConnection
    include EM::Hiredis::PubsubConnection
    include EM::Hiredis::MockConnection
  end

  # Create expected_connections connections, inject them in order in to the
  # client as it creates new ones
  def mock_connections(expected_connections, uri = 'redis://localhost:6379')
    em = EM::Hiredis::MockConnectionEM.new(expected_connections, PubsubTestConnection)

    yield EM::Hiredis::PubsubClient.new(uri, nil, nil, em), em.connections

    em.connections.each { |c| c._expectations_met! }
  end

  context '(un)subscribing' do
    it "should unsubscribe all callbacks for a channel on unsubscribe" do
      mock_connections(1) do |client, (connection)|
        client.connect
        connection.connection_completed

        connection._expect_pubsub('subscribe channel')
        connection._expect_pubsub('unsubscribe channel')

        # Block subscription
        client.subscribe('channel') { |m| fail }
        # Proc example
        client.subscribe('channel', Proc.new { |m| fail })

        client.unsubscribe('channel')
        connection.emit(:message, 'channel', 'hello')
      end
    end

    it "should allow selective unsubscription" do
      mock_connections(1) do |client, (connection)|
        client.connect
        connection.connection_completed

        connection._expect_pubsub('subscribe channel')

        received_messages = 0

        # Block subscription
        client.subscribe('channel') { |m| received_messages += 1 } # block
        # Proc example (will be unsubscribed again before message is sent)
        proc = Proc.new { |m| fail }
        client.subscribe('channel', proc)

        client.unsubscribe_proc('channel', proc)
        connection.emit(:message, 'channel', 'hello')

        received_messages.should == 1
      end
    end

    it "should unsubscribe from redis when all subscriptions for a channel are unsubscribed" do
      mock_connections(1) do |client, (connection)|
        client.connect
        connection.connection_completed

        connection._expect_pubsub('subscribe channel')

        proc_a = Proc.new { |m| fail }
        client.subscribe('channel', proc_a)
        proc_b = Proc.new { |m| fail }
        client.subscribe('channel', proc_b)

        # Unsubscribe first
        client.unsubscribe_proc('channel', proc_a)

        # Unsubscribe second, should unsubscribe in redis
        connection._expect_pubsub('unsubscribe channel')
        client.unsubscribe_proc('channel', proc_b)

        # Check callbacks were removed
        connection.emit(:message, 'channel', 'hello')
      end
    end

    it "should punsubscribe all callbacks for a pattern on punsubscribe" do
      mock_connections(1) do |client, (connection)|
        client.connect
        connection.connection_completed

        connection._expect_pubsub('psubscribe channel:*')

        # Block subscription
        client.psubscribe('channel:*') { |m| fail }
        # Proc example
        client.psubscribe('channel:*', Proc.new { |m| fail })

        connection._expect_pubsub('punsubscribe channel:*')
        client.punsubscribe('channel:*')

        connection.emit(:pmessage, 'channel:*', 'channel:hello', 'hello')
      end
    end

    it "should allow selective punsubscription" do
      mock_connections(1) do |client, (connection)|
        client.connect
        connection.connection_completed

        connection._expect_pubsub('psubscribe channel:*')

        received_messages = 0

        # Block subscription
        client.psubscribe('channel:*') { |m| received_messages += 1 }
        # Proc example
        proc = Proc.new { |m| fail }
        client.psubscribe('channel:*', proc)

        client.punsubscribe_proc('channel:*', proc)
        connection.emit(:pmessage, 'channel:*', 'channel:hello', 'hello')

        received_messages.should == 1
      end
    end

    it "should punsubscribe from redis when all psubscriptions for a pattern are punsubscribed" do
      mock_connections(1) do |client, (connection)|
        client.connect
        connection.connection_completed

        connection._expect_pubsub('psubscribe channel:*')

        proc_a = Proc.new { |m| fail }
        client.psubscribe('channel:*', proc_a)
        proc_b = Proc.new { |m| fail }
        client.psubscribe('channel:*', proc_b)

        # Unsubscribe first
        client.punsubscribe_proc('channel:*', proc_a)

        # Unsubscribe second, should unsubscribe in redis
        connection._expect_pubsub('punsubscribe channel:*')
        client.punsubscribe_proc('channel:*', proc_b)

        # Check callbacks were removed
        connection.emit(:pmessage, 'channel:*', 'channel:hello', 'hello')
      end
    end
  end

  context 'reconnection' do
    it 'should resubscribe all existing on reconnection' do
      mock_connections(2) do |client, (conn_a, conn_b)|
        client.connect
        conn_a.connection_completed

        channels = %w{foo bar baz}
        patterns = %w{foo:* bar:*:baz}

        received_subs = []

        # Make some subscriptions to various channels and patterns
        channels.each do |c|
          conn_a._expect_pubsub("subscribe #{c}")
          client.subscribe(c) { |message|
            received_subs << c
          }
        end

        patterns.each do |p|
          conn_a._expect_pubsub("psubscribe #{p}")
          client.psubscribe(p) { |channel, message|
            received_subs << p
          }
        end

        # Check that those subscriptions receive messages
        channels.each do |c|
          conn_a.emit(:message, c, 'message content')
          received_subs.select { |e| e == c }.length.should == 1
        end

        patterns.each do |p|
          channel = p.gsub('*', 'test')
          conn_a.emit(:pmessage, p, channel, 'message content')
          received_subs.select { |e| e == p }.length.should == 1
        end

        # Trigger a reconnection
        conn_a.unbind

        # All subs previously made should be re-made
        conn_b._expect_pubsub("subscribe #{channels.join(' ')}")
        conn_b._expect_pubsub("psubscribe #{patterns.join(' ')}")

        conn_b.connection_completed

        # Check the callbacks are still attached correctly
        channels.each do |c|
          conn_b.emit(:message, c, 'message content')
          received_subs.select { |e| e == c }.length.should == 2
        end

        patterns.each do |p|
          channel = p.gsub('*', 'test')
          conn_b.emit(:pmessage, p, channel, 'message content')
          received_subs.select { |e| e == p }.length.should == 2
        end

      end
    end
  end

  context 'auth' do
    it 'should auth if password provided' do
      mock_connections(1, 'redis://:mypass@localhost:6379') do |client, (connection)|
        connection._expect('auth mypass')

        connected = false
        client.connect.callback {
          connected = true
        }
        connection.connection_completed

        connected.should == true
      end
    end

    it 'should issue pubsub commands as usual after authentication' do
      mock_connections(1, 'redis://:mypass@localhost:6379') do |client, (connection)|
        connection._expect('auth mypass')

        connected = false
        client.connect.callback {
          connected = true
        }
        connection.connection_completed
        connected.should == true

        connection._expect_pubsub('subscribe channel')

        message_received = nil
        # Block subscription
        client.subscribe('channel') { |m|
           message_received = m
        }

        connection.emit(:message, 'channel', 'hello')

        message_received.should == 'hello'
      end
    end

    it 'should issue pubsub commands issued before connection completion after authentication' do
      mock_connections(1, 'redis://:mypass@localhost:6379') do |client, (connection)|
        connection._expect('auth mypass')

        connected = false
        client.connect.callback {
          connected = true
        }

        connection._expect_pubsub('subscribe channel')

        message_received = nil
        # Block subscription
        client.subscribe('channel') { |m|
           message_received = m
        }

        connection.connection_completed
        connected.should == true

        connection.emit(:message, 'channel', 'hello')

        message_received.should == 'hello'
      end
    end

    it 'should reconnect if auth command fails' do
      mock_connections(2, 'redis://:mypass@localhost:6379') do |client, (conn_a, conn_b)|
        conn_a._expect('auth mypass', RuntimeError.new('OOPS'))
        conn_b._expect('auth mypass')

        connected = false
        client.connect.callback {
          connected = true
        }
        conn_a.connection_completed
        connected.should == false

        conn_b.connection_completed
        connected.should == true
      end
    end
  end
end
