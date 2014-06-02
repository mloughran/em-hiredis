require 'spec_helper'
require 'support/inprocess_redis_mock'

def connect_mock(timeout = 10, url = "redis://localhost:6381", server = nil, &blk)
  em(timeout) do
    IRedisMock.start
    redis = EventMachine::Hiredis.connect(url)
    blk.call(redis)
    IRedisMock.stop
  end
end

describe EM::Hiredis::BaseClient do
  it "should ping after activity timeout reached" do
    connect_mock do |redis|
      redis.configure_inactivity_check(2, 1)
      EM.add_timer(4) {
        IRedisMock.received.should include("ping")
        done
      }
    end
  end

  it "should not ping before activity timeout reached" do
    connect_mock do |redis|
      redis.configure_inactivity_check(3, 1)
      EM.add_timer(2) {
        IRedisMock.received.should_not include("ping")
        done
      }
    end
  end

  it "should ping after timeout reached even though command has been sent (no response)" do
    connect_mock do |redis|
      redis.configure_inactivity_check(2, 1)
      IRedisMock.pause # no responses from now on

      EM.add_timer(1.5) {
        redis.get "test"
      }

      EM.add_timer(4) {
        IRedisMock.received.should include("ping")
        done
      }
    end
  end

  it "should trigger a reconnect when there's no response to ping" do
    connect_mock do |redis|
      redis.configure_inactivity_check(2, 1)
      IRedisMock.pause # no responses from now on

      EM.add_timer(1.5) {
        redis.get "test"
      }

      EM.add_timer(5) {
        IRedisMock.received.should include("disconnect")
        done
      }
    end
  end

end
