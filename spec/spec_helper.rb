$:.unshift File.expand_path(File.dirname(__FILE__) + "/../lib")
require 'stringio'
require 'logger'

require 'em-hiredis'
require 'rspec'
require 'em-spec/rspec'

module SpecHelper
  def connect
    em do
      redis = EventMachine::Hiredis::Client.connect
      redis.flushdb
      yield redis
    end
  end
end

RSpec.configure do |config|
  config.include SpecHelper
  config.include EventMachine::SpecHelper
end
