require 'uri'

module EventMachine::Hiredis
  # Emits the following events:
  #
  # - :connected - on successful connection or reconnection
  # - :reconnected - on successful reconnection
  # - :disconnected - no longer connected, when previously in connected state
  # - :reconnect_failed(failure_number) - a reconnect attempt failed
  #     This event is passed number of failures so far (1,2,3...)
  # - :failed - on failing the final reconnect attempt
  class Client
    include EventEmitter
    include EventMachine::Deferrable

    attr_reader :host, :port, :password, :db

    # uri:
    #   the redis server to connect to, redis://[:password@]host[:port][/db]
    # inactivity_trigger_secs:
    #   the number of seconds of inactivity before triggering a ping to the server
    # inactivity_response_timeout:
    #   the number of seconds after a ping at which to terminate the connection
    #   if there is still no activity
    # reconnect_attempts:
    #   the number of how many reconnect attempts it should complete
    #   before declaring a connection as failed.
    def initialize(
        uri,
        inactivity_trigger_secs = nil,
        inactivity_response_timeout = nil,
        em = EventMachine,
        reconnect_attempts = nil)

      @em = em
      configure(uri)

      @inactivity_trigger_secs = inactivity_trigger_secs
      @inactivity_response_timeout = inactivity_response_timeout

      # Commands received while we are not initialized, to be sent once we are
      @command_queue = []

      @connection_manager = ConnectionManager.new(method(:factory_connection), em, reconnect_attempts)

      @connection_manager.on(:connected) {
        EM::Hiredis.logger.info("#{@name} - Connected")
        emit(:connected)
        set_deferred_status(:succeeded)
      }

      @connection_manager.on(:disconnected) {
        EM::Hiredis.logger.info("#{@name} - Disconnected")
        emit(:disconnected)
      }
      @connection_manager.on(:reconnected) {
        EM::Hiredis.logger.info("#{@name} - Reconnected")
        emit(:reconnected)
      }
      @connection_manager.on(:reconnect_failed) { |count|
        EM::Hiredis.logger.warn("#{@name} - Reconnect failed, attempt #{count}")
        emit(:reconnect_failed, count)
      }

      @connection_manager.on(:failed) {
        EM::Hiredis.logger.error("#{@name} - Connection failed")
        @command_queue.each { |df, _, _|
          df.fail(EM::Hiredis::Error.new('Redis connection in failed state'))
        }
        @command_queue.clear

        emit(:failed)
        set_deferred_status(:failed, Error.new('Could not connect after 4 attempts'))
      }
    end

    # Connect to the configured redis server. Returns a deferrable which
    # completes upon successful connections or fails after all reconnect attempts
    # are exhausted.
    #
    # Commands may be issued before or during connection, they will be queued
    # and submitted to the server once the connection is active.
    def connect
      @connection_manager.connect
      return self
    end

    # Reconnect, either:
    #  - because the client has reached a failed state, but you believe the
    #    underlying problem to be resolved
    #  - with an optional different uri, because you wish to tear down the
    #    connection and connect to a different redis server, perhaps as part of
    #    a failover
    def reconnect(uri = nil)
      configure(uri) if uri
      @connection_manager.reconnect
    end

    # Terminate the client permanently
    def close
      @connection_manager.close
    end

    ## Exposed state

    def pending_commands
      @connection_manager.pending_commands
    end

    def pending_commands?
      return pending_commands > 0
    end

    ## Commands which require extra logic or convenience

    def select(db, &blk)
      process_command('select', db, &blk).callback {
        @db = db
      }
    end

    def auth(password, &blk)
      process_command('auth', password, &blk).callback {
        @password = password
      }
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

    # Commands which are not supported

    def monitor
      # If the command were issued it would break the request-response model
      raise 'monitor command not supported'
    end

    def subscribe(*channels)
      raise "Use pubsub client"
    end

    def unsubscribe(*channels)
      raise "Use pubsub client"
    end

    def psubscribe(*pattern)
      raise "Use pubsub client"
    end

    def punsubscribe(*pattern)
      raise "Use pubsub client"
    end

    # Gives access to a richer interface for pubsub subscriptions on a
    # separate redis connection
    def pubsub
      @pubsub ||= begin
        uri = URI("redis://#{@host}:#{@port}/")
        uri.password = @password if @password
        PubsubClient.new(uri).connect
      end
    end

    # Lua script support

    def self.load_scripts_from(dir)
      Dir.glob("#{dir}/*.lua").each do |f|
        name = File.basename(f, '.lua')
        lua = load_script(f)
        EM::Hiredis.logger.debug { "Registering script: #{name}" }
        EM::Hiredis::Client.register_script(name, lua)
      end
    end

    def self.load_script(file)
      script_text = File.open(file, 'r').read

      inc_path = File.dirname(file)
      while (m = /^-- #include (.*)$/.match(script_text))
        inc_file = m[1]
        inc_body = File.read("#{inc_path}/#{inc_file}")
        to_replace = Regexp.new("^-- #include #{inc_file}$")
        script_text = script_text.gsub(to_replace, "#{inc_body}\n")
      end
      script_text
    end

    def self.register_script(name, lua)
      sha = Digest::SHA1.hexdigest(lua)
      self.send(:define_method, name.to_sym) { |keys, args=[]|
        eval_script(lua, sha, keys, args)
      }
      self.send(:define_method, "#{name}_script".to_sym) {
        lua
      }
      self.send(:define_method, "#{name}_sha".to_sym) {
        sha
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

    def ensure_script(script_name)
      df = EM::DefaultDeferrable.new
      method_missing(
        :script,
        'exists',
        self.send("#{script_name}_sha".to_sym)
      ).callback { |ret|
        # ret is an array of 0 or 1s representing existence for each script arg passed
        if ret[0] == 0
          method_missing(
            :script,
            'load',
            self.send("#{script_name}_script".to_sym)
          ).callback {
            df.succeed
          }.errback { |e|
            df.fail(e)
          }
        else
          df.succeed
        end
      }.errback { |e|
        df.fail(e)
      }
      df
    end

    protected

    def configure(uri_string)
      uri = URI(uri_string)

      path = uri.path[1..-1]
      db = path.to_i # Empty path => 0

      @host = uri.host
      @port = uri.port
      @password = uri.password
      @db = db

      if @name
        EM::Hiredis.logger.info("#{@name} - Reconfiguring to #{uri_string}")
      else
        EM::Hiredis.logger.info("#{uri_string} - Configured")
      end
      @name = uri_string
    end

    def factory_connection
      df = EM::DefaultDeferrable.new

      begin
        connection = @em.connect(
          @host,
          @port,
          RedisConnection,
          @inactivity_trigger_secs,
          @inactivity_response_timeout,
          @name
        )

        connection.on(:connected) {
          maybe_auth(connection).callback {
            maybe_select(connection).callback {
              @command_queue.each { |command_df, command, args|
                connection.send_command(command_df, command, args)
              }
              @command_queue.clear

              df.succeed(connection)
            }.errback { |e|
              # Failure to select db counts as a connection failure
              connection.close_connection
              df.fail(e)
            }
          }.errback { |e|
            # Failure to auth counts as a connection failure
            connection.close_connection
            df.fail(e)
          }
        }

        connection.on(:connection_failed) {
          df.fail('Connection failed')
        }
      rescue EventMachine::ConnectionError => e
        df.fail(e)
      end

      return df
    end

    def process_command(command, *args, &blk)
      df = EM::DefaultDeferrable.new
      # Shortcut for defining the callback case with just a block
      df.callback(&blk) if blk

      if @connection_manager.state == :failed
        df.fail(EM::Hiredis::Error.new('Redis connection in failed state'))
      elsif @connection_manager.state == :connected
        @connection_manager.connection.send_command(df, command, args)
      else
        @command_queue << [df, command, args]
      end

      return df
    end

    alias_method :method_missing, :process_command

    def maybe_auth(connection)
      if @password
        connection.send_command(EM::DefaultDeferrable.new, 'auth', @password)
      else
        noop
      end
    end

    def maybe_select(connection)
      if @db != 0
        connection.send_command(EM::DefaultDeferrable.new, 'select', @db)
      else
        noop
      end
    end

    def noop
      df = EM::DefaultDeferrable.new
      df.succeed
      df
    end
  end
end
