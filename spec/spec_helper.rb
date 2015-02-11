$:.unshift File.expand_path(File.dirname(__FILE__) + "/../lib")
require 'em-hiredis'
require 'rspec'
require 'em-spec/rspec'

require 'support/mock_connection'
require 'support/connection_helper'
require 'support/networked_redis_mock'
require 'support/time_mock_eventmachine'
require 'stringio'

RSpec.configure do |config|
  config.include ConnectionHelper
  config.include EventMachine::SpecHelper
end

# This speeds the tests up a bit
EM::Hiredis.reconnect_timeout = 0.01

# Keep the tests quiet, decrease the level to investigate failures
EM::Hiredis.logger.level = Logger::FATAL