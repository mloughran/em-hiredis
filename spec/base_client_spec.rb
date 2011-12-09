require 'spec_helper'

describe EM::Hiredis::BaseClient do
  it "should emit an event on reconnect failure, with the retry count" do
    # Assumes there is no redis server on 9999
    connect("redis://localhost:9999/") do |redis|
      expected = 1
      redis.on(:reconnect_failed) { |count|
        count.should == expected
        expected += 1
        done if expected == 3
      }
    end
  end
  
  it "should emit disconnected when the connection closes" do
    connect do |redis|
      redis.on(:disconnected) {
        done
      }
      redis.close_connection
    end
  end

  it "should fail the client deferrable after 4 unsuccessful attempts" do
    connect("redis://localhost:9999/") do |redis|
      events = []
      redis.on(:reconnect_failed) { |count|
        events << count
      }
      redis.errback { |reason|
        reason.should == 'Could not connect after 4 attempts'
        events.should == [1,2,3,4]
        done
      }
    end
  end
end
