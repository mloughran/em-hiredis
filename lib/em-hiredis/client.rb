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

    def info_commandstats(&blk)
      hash_processor = lambda do |response|
        commands = {}
        response.each_line do |line|
          command, data = line.split(':')
          if data
            c = commands[command.sub('cmdstat_', '').to_sym] = {}
            data.split(',').each do |d|
              k, v = d.split('=')
              c[k.to_sym] = v =~ /\./ ? v.to_f : v.to_i
            end
          end
        end
        blk.call(commands)
      end
      method_missing(:info, 'commandstats', &hash_processor)
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
