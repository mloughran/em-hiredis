require 'spec_helper'

describe EM::Hiredis::PubsubConnection do

  class TestPubsubConnection
    include EM::Hiredis::PubsubConnection

    attr_accessor :sent, :closed

    def send_data(data)
      @sent ||= []
      @sent << data
    end

    def close_connection
      @closed = true
    end
  end

  it 'should marshall command to send' do
    con = TestPubsubConnection.new
    con.send_command('subscribe', 'test')
    con.sent[0].should == "*2\r\n$9\r\nsubscribe\r\n$4\r\ntest\r\n"
  end

  it 'should emit subscribe responses as they arrive' do
    con = TestPubsubConnection.new
    con.connection_completed

    received = false
    con.on(:subscribe) { |channel|
      channel.should == 'test'
      received = true
    }

    con.receive_data("*2\r\n$9\r\nsubscribe\r\n$4\r\ntest\r\n")
    received.should == true
  end

  it 'should emit unsubscribe responses as they arrive' do
    con = TestPubsubConnection.new
    con.connection_completed

    received = false
    con.on(:unsubscribe) { |channel|
      channel.should == 'test'
      received = true
    }

    con.receive_data("*2\r\n$11\r\nunsubscribe\r\n$4\r\ntest\r\n")
    received.should == true
  end

  it 'should emit psubscribe responses as they arrive' do
    con = TestPubsubConnection.new
    con.connection_completed

    received = false
    con.on(:psubscribe) { |channel|
      channel.should == 'test:*'
      received = true
    }

    con.receive_data("*2\r\n$10\r\npsubscribe\r\n$6\r\ntest:*\r\n")
    received.should == true
  end

  it 'should emit punsubscribe responses as they arrive' do
    con = TestPubsubConnection.new
    con.connection_completed

    received = false
    con.on(:punsubscribe) { |channel|
      channel.should == 'test:*'
      received = true
    }

    con.receive_data("*2\r\n$12\r\npunsubscribe\r\n$6\r\ntest:*\r\n")
    received.should == true
  end

  it 'should emit messages as they arrive' do
    con = TestPubsubConnection.new
    con.connection_completed

    received = false
    con.on(:message) { |channel, message|
      channel.should == 'test'
      message.should == 'my message'
      received = true
    }

    con.receive_data("*3\r\n$7\r\nmessage\r\n$4\r\ntest\r\n$10\r\nmy message\r\n")
    received.should == true
  end

  it 'should emit pmessages as they arrive' do
    con = TestPubsubConnection.new
    con.connection_completed

    received = false
    con.on(:pmessage) { |pattern, channel, message|
      pattern.should == 'test*'
      channel.should == 'test'
      received = true
    }

    con.receive_data("*4\r\n$8\r\npmessage\r\n$5\r\ntest*\r\n$4\r\ntest\r\n$10\r\nmy message\r\n")
    received.should == true
  end

  it 'should emit :disconnected when the connection closes' do
    con = TestPubsubConnection.new
    con.connection_completed

    emitted = false
    con.on(:disconnected) {
      emitted = true
    }

    con.unbind
    emitted.should == true
  end

  context 'inactivity checks' do
    default_timeout 5

    it 'should fire after an initial period of inactivity' do
      em {
        con = TestPubsubConnection.new(1, 1)
        con.connection_completed

        EM.add_timer(3) {
          con.sent.should include("*2\r\n$9\r\nsubscribe\r\n$17\r\n__em-hiredis-ping\r\n")
          done
        }
      }
    end

    it 'should not fire after activity' do
      em {
        con = TestPubsubConnection.new(1, 1)
        con.connection_completed

        EM.add_timer(1.5) {
          con.send_command('subscribe', 'test')
          con.receive_data("*2\r\n$9\r\nsubscribe\r\n$4\r\ntest\r\n")
        }

        EM.add_timer(3) {
          con.sent.should_not include("*2\r\n$9\r\nsubscribe\r\n$17\r\n__em-hiredis-ping\r\n")
          done
        }
      }
    end

    it 'should fire after a later period of inactivity' do
      em {
        con = TestPubsubConnection.new(1, 1)
        con.connection_completed

        EM.add_timer(1.5) {
          con.send_command('subscribe', 'test')
          con.receive_data("*2\r\n$9\r\nsubscribe\r\n$4\r\ntest\r\n")
        }

        EM.add_timer(3) {
          con.sent.should_not include("*2\r\n$9\r\nsubscribe\r\n$17\r\n__em-hiredis-ping\r\n")
        }

        EM.add_timer(4) {
          con.sent.should include("*2\r\n$9\r\nsubscribe\r\n$17\r\n__em-hiredis-ping\r\n")
          done
        }
      }
    end

    it 'should close the connection if inactivity persists' do
      em {
        con = TestPubsubConnection.new(1, 1)
        con.connection_completed

        EM.add_timer(4) {
          con.sent.should include("*2\r\n$9\r\nsubscribe\r\n$17\r\n__em-hiredis-ping\r\n")
          con.closed.should == true
          done
        }
      }
    end

    it 'should not close the connection if there is activity after ping' do
      em {
        con = TestPubsubConnection.new(1, 1)
        con.connection_completed

        EM.add_timer(2.5) {
          con.send_command('subscribe', 'test')
          con.receive_data("*2\r\n$9\r\nsubscribe\r\n$4\r\ntest\r\n")
        }

        EM.add_timer(4) {
          con.sent.should include("*2\r\n$9\r\nsubscribe\r\n$17\r\n__em-hiredis-ping\r\n")
          con.closed.should_not == true
          done
        }
      }
    end
  end
end
