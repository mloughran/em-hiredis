module EventMachine::Hiredis
  class Client < BaseClient
    def self.connect(host = 'localhost', port = 6379)
      new(host, port).connect
    end

    def monitor(&blk)
      @monitoring = true
      method_missing(:monitor, &blk)
    end

    def info
      df = method_missing(:info)
      df.callback { |response|
        info = {}
        response.each_line do |line|
          key, value = line.split(":", 2)
          info[key.to_sym] = value.chomp if value
        end
        df.succeed(info)
      }
      df.callback { |info| yield info } if block_given?
      df
    end

    # Gives access to a richer interface for pubsub subscriptions on a
    # separate redis connection
    #
    def pubsub
      @pubsub ||= begin
        PubsubClient.new(@host, @port, @password, @db).connect
      end
    end

    def subscribe(*channels)
      raise "Use pubsub client"
    end

    def unsubscribe(*channels)
      raise "Use pubsub client"
    end

    def psubscribe(channel)
      raise "Use pubsub client"
    end

    def punsubscribe(channel)
      raise "Use pubsub client"
    end
  end
end
