require 'spec_helper'

describe EventMachine::Hiredis, "connecting" do
  let(:replies) do
    # shove db number into PING reply since redis has no way
    # of exposing the currently selected DB
    replies = {
      :select => lambda { |db| $db = db; "+OK" },
      :ping   => lambda { "+PONG #{$db}" },
      :auth   => lambda { |password| $auth = password; "+OK" },
      :get    => lambda { |key| $auth == "secret" ? "$3\r\nbar" : "$-1" },
    }
  end

  def connect_to_mock(url, &blk)
    redis_mock(replies) do
      connect(url, &blk)
    end
  end

  it "doesn't call select by default" do
    connect_to_mock("redis://localhost:6380/") do |redis|
      redis.ping do |response|
        response.should == "PONG "
        done
      end
    end
  end

  it "selects the right db" do
    connect_to_mock("redis://localhost:6380/9") do |redis|
      redis.ping do |response|
        response.should == "PONG 9"
        done
      end
    end
  end

  it "authenticates with a password" do
    connect_to_mock("redis://:secret@localhost:6380/9") do |redis|
      redis.get("foo") do |response|
        response.should == "bar"
        done
      end
    end
  end

  it "rejects a bad password" do
    connect_to_mock("redis://:failboat@localhost:6380/9") do |redis|
      redis.get("foo") do |response|
        response.should be_nil
        done
      end
    end
  end
end
