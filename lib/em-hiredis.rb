require 'eventmachine'

module EventMachine
  module Hiredis
    # All em-hiredis errors should descend from EM::Hiredis::Error
    class Error < RuntimeError; end

    # An error reply from Redis. The actual error retuned by ::Hiredis will be
    # wrapped in the redis_error accessor.
    class RedisError < Error
      attr_accessor :redis_error
    end

    class << self
      attr_accessor :reconnect_timeout
    end
    self.reconnect_timeout = 0.5

    def self.setup(uri = nil, activity_timeout = nil, response_timeout = nil)
      uri = uri || ENV["REDIS_URL"] || "redis://127.0.0.1:6379/0"
      Client.new(uri, activity_timeout, response_timeout)
    end

    # Connects to redis and returns a client instance
    #
    # Will connect in preference order to the provided uri, the REDIS_URL
    # environment variable, or localhost:6379
    #
    # TCP connections are supported via redis://:password@host:port/db (only
    # host and port components are required)
    #
    # Unix socket uris are supported, e.g. unix:///tmp/redis.sock, however
    # it's not possible to set the db or password - use initialize instead in
    # this case
    def self.connect(uri = nil, activity_timeout = nil, response_timeout = nil)
      client = setup(uri, activity_timeout, response_timeout)
      client.connect
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

require 'digest/sha1'
require 'hiredis/reader'
require 'em-hiredis/support/event_emitter'
require 'em-hiredis/support/cancellable_deferrable'
require 'em-hiredis/support/inactivity_checker'
require 'em-hiredis/support/state_machine'
require 'em-hiredis/connection_manager'
require 'em-hiredis/redis_connection'
require 'em-hiredis/pubsub_connection'
require 'em-hiredis/redis_client'
require 'em-hiredis/pubsub_client'
