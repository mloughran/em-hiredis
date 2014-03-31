require 'spec_helper'

describe EM::Hiredis::Heartbeat do
  let(:connected) { false }
  let(:client) { EM::Hiredis::Client.new }
  let(:every) { 0.1 }

  subject{ EM::Hiredis::Heartbeat.new(client, every) }

  context 'client is not running' do
    it 'should not be running' do
      client.should_not_receive(:ping)
      subject.should_not be_running
      em(every * 3) {
        EM.add_timer(every) {
          subject.should_not be_running
          done
        }
      }
    end

    it 'also after disconnection' do
      client.on(:connected) {
        EM.next_tick {
          subject.should be_running
          client.close_connection
        }
      }
      client.on(:disconnected) {
        EM.next_tick {
          subject.should_not be_running
          done
        }
      }
      em(1) {
        client.connect
      }
    end
  end

  it 'reconnects the client if no reponse is received after "every"' do
    subject.should_not be_running
    client.on(:connected) {
      subject.should be_running
      client.should_receive(:ping).and_return(EM::DefaultDeferrable.new)
      client.should_receive(:reconnect!)
      EM.add_timer(every * 2.5) {
        subject.should_not be_running
        done 
      }
    }
    em(every * 3) {
      client.connect
    }
  end

end
