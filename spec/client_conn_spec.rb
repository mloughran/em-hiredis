require 'spec_helper'

describe EM::Hiredis::Client do
  default_timeout 4

  class ClientTestConnection
    include EM::Hiredis::RedisConnection
    include EM::Hiredis::MockConnection
  end

  # Create expected_connections connections, inject them in order in to the
  # client as it creates new ones
  def mock_connections(expected_connections)
    em = EM::Hiredis::MockConnectionEM.new(expected_connections, ClientTestConnection)

    yield EM::Hiredis::Client.new('redis://localhost:6379/9', nil, nil, em), em.connections

    em.connections.each { |c| c._expectations_met! }
  end

  it 'should queue commands issued while reconnecting' do
    mock_connections(2) { |client, (conn_a, conn_b)|
      # Both connections expect to receive 'select' first
      # But pings 3 and 4 and issued between conn_a being disconnected
      # and conn_b completing its connection
      conn_a._expect('select 9')
      conn_a._expect('ping 1')
      conn_a._expect('ping 2')

      conn_b._expect('select 9')
      conn_b._expect('ping 3')
      conn_b._expect('ping 4')

      client.connect
      conn_a.connection_completed

      client.ping(1)
      client.ping(2)

      conn_a.unbind

      client.ping(3)
      client.ping(4)

      conn_b.connection_completed
    }
  end

  context 'failed state' do
    default_timeout 2

    it 'should be fail queued commands when entering the state' do
      mock_connections(5) { |client, connections|
        client.connect

        # Queue command that will later fail
        got_errback = false
        client.ping.errback { |e|
          e.message.should == 'Redis connection in failed state'
          got_errback = true
        }

        # THEN fail all connection attempts
        connections.each { |c| c.unbind }

        got_errback.should == true
      }
    end

    it 'should be possible to recover' do
      mock_connections(6) { |client, connections|
        failing_connections = connections[0..4]
        good_connection = connections[5]

        # Connect and fail 5 times
        client.connect
        failing_connections.each { |c| c.unbind }

        # We should now be in the failed state
        got_errback = false
        client.ping.errback { |e|
          e.message.should == 'Redis connection in failed state'
          got_errback = true
        }

        good_connection._expect('select 9')
        good_connection._expect('ping')

        # But after calling connect and completing the connection, we are functional again
        client.connect
        good_connection.connection_completed

        got_callback = false
        client.ping.callback {
          got_callback = true
        }

        got_errback.should == true
        got_callback.should == true
      }
    end

    it 'should queue commands once attempting to recover' do
      mock_connections(6) { |client, connections|
        failing_connections = connections[0..4]
        good_connection = connections[5]

        # Connect and fail 5 times
        client.connect
        failing_connections.each { |c| c.unbind }

        # We sohuld now be in the failed state
        got_errback = false
        client.ping.errback { |e|
          e.message.should == 'Redis connection in failed state'
          got_errback = true
        }

        good_connection._expect('select 9')
        good_connection._expect('ping')

        # But after calling connect, we queue commands even though the connection
        # is not yet complete
        client.connect

        got_callback = false
        client.ping.callback {
          got_callback = true
        }

        good_connection.connection_completed

        got_errback.should == true
        got_callback.should == true
      }
    end
  end

  context 'disconnects from em' do
    it 'should retry when connecting' do
      mock_connections(2) { |client, (conn_a, conn_b)|
        connected = false
        client.connect.callback {
          connected = true
        }.errback {
          fail('Connection failed')
        }

        # not connected yet
        conn_a.unbind

        conn_b._expect('select 9')
        conn_b.connection_completed

        connected.should == true
      }
    end

    it 'should retry when partially set up' do
      mock_connections(2) { |client, (conn_a, conn_b)|
        conn_a._expect_no_response('select 9')

        connected = false
        client.connect.callback {
          connected = true
        }

        conn_a.connection_completed
        # awaiting response to 'select'
        conn_a.unbind

        conn_b._expect('select 9')
        conn_b.connection_completed

        connected.should == true
      }
    end

    it 'should reconnect once connected' do
      mock_connections(2) { |client, (conn_a, conn_b)|
        conn_a._expect('select 9')

        client.connect.errback {
          fail('Connection failed')
        }

        reconnected = false
        client.on(:reconnected) {
          reconnected = true
        }

        conn_a.connection_completed
        # awaiting response to 'select'
        conn_a.unbind

        conn_b._expect('select 9')
        conn_b.connection_completed

        reconnected.should == true
      }
    end
  end
end
