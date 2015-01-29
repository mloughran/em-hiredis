require 'digest/sha1'

module EventMachine::Hiredis
  class Client < BaseClient
    def self.connect(host = 'localhost', port = 6379)
      new(host, port).connect
    end

    def self.load_scripts_from(dir)
      Dir.glob("#{dir}/*.lua").each do |f|
        name = Regexp.new(/([^\/]*)\.lua$/).match(f)[1]
        lua = File.open(f, 'r').read
        EM::Hiredis.logger.debug { "Registering script: #{name}" }
        EM::Hiredis::Client.register_script(name, lua)
      end
    end

    def self.register_script(name, lua)
      sha = Digest::SHA1.hexdigest(lua)
      self.send(:define_method, name.to_sym) { |keys, args=[]|
        eval_script(lua, sha, keys, args)
      }
    end

    def register_script(name, lua)
      sha = Digest::SHA1.hexdigest(lua)
      singleton = class << self; self end
      singleton.send(:define_method, name.to_sym) { |keys, args=[]|
        eval_script(lua, sha, keys, args)
      }
    end

    def eval_script(lua, lua_sha, keys, args)
      df = EM::DefaultDeferrable.new
      method_missing(:evalsha, lua_sha, keys.size, *keys, *args).callback(
        &df.method(:succeed)
      ).errback { |e|
        if e.kind_of?(RedisError) && e.redis_error.message.start_with?("NOSCRIPT")
          self.eval(lua, keys.size, *keys, *args)
            .callback(&df.method(:succeed)).errback(&df.method(:fail))
        else
          df.fail(e)
        end
      }
      df
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
    def pubsub_client
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
