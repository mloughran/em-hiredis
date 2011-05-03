require 'eventmachine'
require 'uri'

module EventMachine
  module Hiredis
    def self.setup(uri = nil)
      url = URI(uri || ENV["REDIS_URL"] || "redis://127.0.0.1:6379/0")
      Client.new(url.host, url.port, url.password, url.path[1..-1])
    end

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
  end
end

require 'em-hiredis/event_emitter'
require 'em-hiredis/connection'
require 'em-hiredis/client'
