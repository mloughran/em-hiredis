require 'spec_helper'

describe EM::Hiredis::Client do

  def recording_server(replies = {})
    em {
      yield NetworkedRedisMock::RedisMock.new(replies)
    }
  end

  context 'initial connections' do
    default_timeout 1

    it 'should not connect on construction' do
      recording_server { |server|
        client = EM::Hiredis::Client.new('redis://localhost:6381/9')
        server.connection_count.should == 0
        done
      }
    end

    it 'should be connected when connect is called' do
      recording_server { |server|
        client = EM::Hiredis::Client.new('redis://localhost:6381/9')
        client.connect.callback {
          server.connection_count.should == 1
          done
        }.errback { |e|
          fail(e)
        }
      }
    end

    it 'should issue select command before succeeding connection' do
      recording_server { |server|
        client = EM::Hiredis::Client.new('redis://localhost:6381/9')
        client.connect.callback {
          server.connection_count.should == 1
          server.received[0].should == 'select 9'
          done
        }.errback { |e|
          fail(e)
        }
      }
    end

    it 'should issue select command before emitting :connected' do
      recording_server { |server|
        client = EM::Hiredis::Client.new('redis://localhost:6381/9')
        client.on(:connected) {
          server.connection_count.should == 1
          server.received[0].should == 'select 9'
          done
        }
        client.connect
      }
    end
  end

  context 'disconnection' do
    default_timeout 1

    it 'should emit :disconnected when the connection disconnects' do
      recording_server { |server|
        client = EM::Hiredis::Client.new('redis://localhost:6381/9')
        client.on(:disconnected) {
          done
        }
        client.connect.callback {
          server.kill_connections
        }
      }
    end
  end

  context 'reconnection' do
    default_timeout 1

    it 'should create a new connection if the existing one reports it has failed' do
      recording_server { |server|
        client = EM::Hiredis::Client.new('redis://localhost:6381/9')
        client.connect.callback {
          server.kill_connections
        }
        EM.add_timer(0.1) {
          server.connection_count.should == 2
          done
        }
      }
    end

    it 'should emit both connected and reconnected' do
      recording_server { |server|
        client = EM::Hiredis::Client.new('redis://localhost:6381/9')
        client.connect.callback {
          callbacks = []
          client.on(:connected) {
            callbacks.push(:connected)
            if callbacks.sort == [:connected, :reconnected]
              done
            end
          }
          client.on(:reconnected) {
            callbacks.push(:reconnected)
            if callbacks.sort == [:connected, :reconnected]
              done
            end
          }

          server.kill_connections
        }
      }
    end

    context 'failing from initial connect attempt' do
      default_timeout 1

      it 'should make 4 attempts, emitting :reconnect_failed with a count' do
        em {
          client = EM::Hiredis::Client.new('redis://localhost:9999') # assumes nothing listening on 9999

          expected = 1
          client.on(:reconnect_failed) { |count|
            count.should == expected
            expected += 1
            done if count == 4
          }

          client.connect
        }
      end

      it 'after 4 unsuccessful attempts should emit :failed' do
        em {
          client = EM::Hiredis::Client.new('redis://localhost:9999') # assumes nothing listening on 9999

          reconnect_count = 0
          client.on(:reconnect_failed) { |count|
            reconnect_count += 1
          }
          client.on(:failed) {
            reconnect_count.should == 4
            done
          }

          client.connect
        }
      end

      it 'should attempt reconnect on DNS resolution failure' do
        em {
          client = EM::Hiredis::Client.new('redis://not-a-host:6381') # assumes not-a-host is... well, you get the idea

          reconnect_count = 0
          client.on(:reconnect_failed) { |count|
            reconnect_count += 1
          }
          client.on(:failed) {
            reconnect_count.should == 4
            done
          }

          client.connect
        }
      end

      it 'should recover from DNS resolution failure' do
        recording_server { |server|
          EM.stub(:connect).and_raise(EventMachine::ConnectionError.new)
          client = EM::Hiredis::Client.new('redis://localhost:6381/9')

          client.on(:reconnect_failed) {
            EM.rspec_reset
          }

          client.connect
          client.ping.callback {
            done
          }
        }
      end
    end

    context 'failing after initially being connected' do
      default_timeout 1

      it 'should make 4 attempts, emitting :reconnect_failed with a count' do
        recording_server { |server|
          client = EM::Hiredis::Client.new('redis://localhost:6381/9')
          client.connect.callback {
            server.stop
            server.kill_connections

            expected = 1
            client.on(:reconnect_failed) { |count|
              count.should == expected
              expected += 1
              done if count == 4
            }
          }
        }
      end

      it 'after 4 unsuccessful attempts should emit :failed' do
        recording_server { |server|
          client = EM::Hiredis::Client.new('redis://localhost:6381/9')
          client.connect.callback {
            server.stop
            server.kill_connections

            reconnect_count = 0
            client.on(:reconnect_failed) { |count|
              reconnect_count += 1
            }
            client.on(:failed) {
              reconnect_count.should == 4
              done
            }
          }
        }
      end
    end

    it 'should fail commands immediately when in a failed state' do
      recording_server { |server|
        client = EM::Hiredis::Client.new('redis://localhost:6381/9')
        client.connect.callback {
          client.on(:failed) {
            client.get('foo').errback { |e|
              e.message.should == 'Redis connection in failed state'
              done
            }
          }

          server.stop
          server.kill_connections
        }
      }
    end

    it 'should be possible to trigger reconnect on request' do
      recording_server { |server|
        client = EM::Hiredis::Client.new('redis://localhost:6381/9')
        client.connect.callback {
          client.on(:reconnected) {
            server.connection_count.should == 2
            done
          }

          client.reconnect
        }
      }
    end

    it 'should do something sensible???' do
      recording_server { |server|
        client = EM::Hiredis::Client.new('redis://localhost:6381/9')
        client.reconnect
        client.ping.callback {
          done
        }
      }
    end

    it 'should keep responses matched when connection is lost' do
      recording_server('get f' => '+hello') { |server|
        client = EM::Hiredis::Client.new('redis://localhost:6381/9')
        client.connect.callback {
          client.get('a')
          client.get('b').callback {
            client.get('c')
            server.kill_connections
            client.get('d')
            client.get('e')
            client.on(:reconnected) {
              client.get('f').callback { |v|
                v.should == 'hello'
                done
              }
            }
          }
        }
      }
    end
  end

  context 'commands' do
    default_timeout 1

    it 'should be able to send commands' do
      recording_server { |server|
        client = EM::Hiredis::Client.new('redis://localhost:6381/9')
        client.connect.callback {
          client.set('test', 'value').callback {
            done
          }
        }
      }
    end

    it 'should queue commands called before connect is called' do
      recording_server { |server|
        client = EM::Hiredis::Client.new('redis://localhost:6381/9')
        client.set('test', 'value').callback {
          client.ping.callback {
            done
          }
        }

        client.connect
      }
    end
  end

  context 'db selection' do
    default_timeout 1

    it 'should support alternative dbs' do
      recording_server { |server|
        client = EM::Hiredis::Client.new('redis://localhost:6381/4')
        client.connect.callback {
          server.received.should == ['select 4']
          done
        }
      }
    end

    it 'should execute db selection first' do
      recording_server { |server|
        client = EM::Hiredis::Client.new('redis://localhost:6381/9')
        client.set('test', 'value').callback {
          client.ping.callback {
            server.received.should == [
              'select 9',
              'set test value',
              'ping']
            done
          }
        }

        client.connect
      }
    end

    it 'should class db selection failure as a connection failure' do
      recording_server('select 9' => '-ERR no such db') { |server|
        client = EM::Hiredis::Client.new('redis://localhost:6381/9')
        client.connect.errback { |e|
          done
        }
      }
    end

    it 'should re-select db on reconnection' do
      recording_server { |server|
        client = EM::Hiredis::Client.new('redis://localhost:6381/4')
        client.connect.callback {
          client.ping.callback {
            client.on(:reconnected) {
              client.ping.callback {
                server.connection_count.should == 2
                server.received.should == [
                  'select 4',
                  'ping',
                  'disconnect',
                  'select 4',
                  'ping'
                ]
                done
              }
            }
            server.kill_connections
          }
        }
      }
    end

    it 'should remember a change in the selected db' do
      recording_server { |server|
        client = EM::Hiredis::Client.new('redis://localhost:6381/9')
        client.connect.callback {
          client.select(4).callback {
            client.on(:reconnected) {
              client.ping.callback {
                server.connection_count.should == 2
                server.received.should == [
                  'select 9',
                  'select 4',
                  'disconnect',
                  'select 4',
                  'ping'
                ]
                done
              }
            }
            server.kill_connections
          }
        }
      }
    end
  end
end
