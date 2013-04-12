require 'eventmachine'

module EventMachine
  module Hiredis
    # All em-hiredis errors should descend from EM::Hiredis::Error
    class Error < RuntimeError; end

    # In the case of error responses from Redis, the RuntimeError returned
    # by ::Hiredis will be wrapped
    class RedisError < Error
      attr_accessor :redis_error
    end

    class << self
      attr_accessor :reconnect_timeout
    end
    self.reconnect_timeout = 0.5

    def self.setup(uri = nil)
      uri = uri || ENV["REDIS_URL"] || "redis://127.0.0.1:6379/0"
      client = Client.new
      client.configure(uri)
      client
    end

    # Connects to redis and returns a client instance
    #
    # Will connect in preference order to the provided uri, the REDIS_URL
    # environment variable, or localhost:6379
    #
    # TCP connections are supported via redis://:password@host:port/db (only
    # host and port components are required)
    def self.connect(uri = nil)
      client = setup(uri)
      client.connect
      client
    end

    def self.logger=(logger)
      @@logger = logger
    end

    def self.logger
      @@logger ||= begin
        require 'logger'
        log = Logger.new(STDOUT)
        log.level = Logger::WARN
        log
      end
    end

    autoload :Lock, 'em-hiredis/lock'
    autoload :PersistentLock, 'em-hiredis/persistent_lock'
  end
end

require 'em-hiredis/event_emitter'
require 'em-hiredis/connection'
require 'em-hiredis/base_client'
require 'em-hiredis/client'
require 'em-hiredis/pubsub_client'
