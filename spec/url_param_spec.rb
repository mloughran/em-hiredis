# adapted from redis-rb
require 'spec_helper'

describe EventMachine::Hiredis, "URL parsing" do
  it "defaults URL defaults to 127.0.0.1:6379" do
    redis = EventMachine::Hiredis.setup

    redis.host.should == "127.0.0.1"
    redis.port.should == 6379
    redis.db.should == "0"
    redis.password.should == nil
  end

  it "allows to pass in a URL" do
    redis = EventMachine::Hiredis.setup "redis://:secr3t@foo.com:999/2"

    redis.host.should == "foo.com"
    redis.port.should == 999
    redis.db.should == "2"
    redis.password.should == "secr3t"
  end

  it "does not modify the passed options" do
    options = "redis://:secr3t@foo.com:999/2"

    redis = EventMachine::Hiredis.setup(options)

    options.should == "redis://:secr3t@foo.com:999/2"
  end

  it "uses REDIS_URL over default if available" do
    ENV["REDIS_URL"] = "redis://:secr3t@foo.com:999/2"

    redis = EventMachine::Hiredis.setup

    redis.host.should == "foo.com"
    redis.port.should == 999
    redis.db.should == "2"
    redis.password.should == "secr3t"

    ENV.delete("REDIS_URL")
  end
end
