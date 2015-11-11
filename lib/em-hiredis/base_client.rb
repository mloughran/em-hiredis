require 'uri'

module EventMachine::Hiredis
  # Emits the following events
  #
  # * :connected - on successful connection or reconnection
  # * :reconnected - on successful reconnection
  # * :disconnected - no longer connected, when previously in connected state
  # * :reconnect_failed(failure_number) - a reconnect attempt failed
  #     This event is passed number of failures so far (1,2,3...)
  # * :monitor
  #
  class BaseClient
    include EventEmitter
    include EM::Deferrable

    attr_reader :host, :port, :password, :db

    def initialize(host = 'localhost', port = 6379, password = nil, db = nil)
      @host, @port, @password, @db = host, port, password, db
      @defs = []
      @command_queue = []

      @reconnect_failed_count = 0
      @reconnect_timer = nil
      @failed = false

      @inactive_seconds = 0

      self.on(:failed) {
        @failed = true
        @command_queue.each do |df, _, _|
          df.fail(Error.new("Redis connection in failed state"))
        end
        @command_queue = []
      }
    end

    # Configure the redis connection to use
    #
    # In usual operation, the uri should be passed to initialize. This method
    # is useful for example when failing over to a slave connection at runtime
    #
    def configure(uri_string)
      uri = URI(uri_string)

      if uri.scheme == "unix"
        @host = uri.path
        @port = nil
      else
        @host = uri.host
        @port = uri.port
        @password = uri.password
        path = uri.path[1..-1]
        @db = path.to_i # Empty path => 0
      end
    end

    # Disconnect then reconnect the redis connection.
    #
    # Pass optional uri - e.g. to connect to a different redis server.
    # Any pending redis commands will be failed, but during the reconnection
    # new commands will be queued and sent after connected.
    #
    def reconnect!(new_uri = nil)
      @connection.close_connection
      configure(new_uri) if new_uri
      @auto_reconnect = true
      EM.next_tick { reconnect_connection }
    end

    def connect
      @auto_reconnect = true
      @connection = EM.connect(@host, @port, Connection, @host, @port)

      @connection.on(:closed) do
        cancel_inactivity_checks
        if @connected
          @defs.each { |d| d.fail(Error.new("Redis disconnected")) }
          @defs = []
          @deferred_status = nil
          @connected = false
          if @auto_reconnect
            # Next tick avoids reconnecting after for example EM.stop
            EM.next_tick { reconnect }
          end
          emit(:disconnected)
          EM::Hiredis.logger.info("#{@connection} Disconnected")
        else
          if @auto_reconnect
            @reconnect_failed_count += 1
            @reconnect_timer = EM.add_timer(EM::Hiredis.reconnect_timeout) {
              @reconnect_timer = nil
              reconnect
            }
            emit(:reconnect_failed, @reconnect_failed_count)
            EM::Hiredis.logger.info("#{@connection} Reconnect failed")

            if @reconnect_failed_count >= 4
              emit(:failed)
              self.fail(Error.new("Could not connect after 4 attempts"))
            end
          end
        end
      end

      @connection.on(:connected) do
        @connected = true
        @reconnect_failed_count = 0
        @failed = false

        auth(@password) if @password
        select(@db) unless @db == 0

        @command_queue.each do |df, command, args|
          @connection.send_command(command, args)
          @defs.push(df)
        end
        @command_queue = []

        schedule_inactivity_checks

        emit(:connected)
        EM::Hiredis.logger.info("#{@connection} Connected")
        succeed

        if @reconnecting
          @reconnecting = false
          emit(:reconnected)
        end
      end

      @connection.on(:message) do |reply|
        if RuntimeError === reply
          raise "Replies out of sync: #{reply.inspect}" if @defs.empty?
          deferred = @defs.shift
          error = RedisError.new(reply.message)
          error.redis_error = reply
          deferred.fail(error) if deferred
        else
          @inactive_seconds = 0
          handle_reply(reply)
        end
      end

      @connected = false
      @reconnecting = false

      return self
    end

    # Indicates that commands have been sent to redis but a reply has not yet
    # been received
    #
    # This can be useful for example to avoid stopping the
    # eventmachine reactor while there are outstanding commands
    #
    def pending_commands?
      @connected && @defs.size > 0
    end

    def connected?
      @connected
    end

    def select(db, &blk)
      @db = db
      method_missing(:select, db, &blk)
    end

    def auth(password, &blk)
      @password = password
      method_missing(:auth, password, &blk)
    end

    def close_connection
      EM.cancel_timer(@reconnect_timer) if @reconnect_timer
      @auto_reconnect = false
      @connection.close_connection_after_writing
    end

    # Note: This method doesn't disconnect if already connected. You probably
    # want to use `reconnect!`
    def reconnect_connection
      @auto_reconnect = true
      EM.cancel_timer(@reconnect_timer) if @reconnect_timer
      reconnect
    end

    # Starts an inactivity checker which will ping redis if nothing has been
    # heard on the connection for `trigger_secs` seconds and forces a reconnect
    # after a further `response_timeout` seconds if we still don't hear anything.
    def configure_inactivity_check(trigger_secs, response_timeout)
      raise ArgumentError('trigger_secs must be > 0') unless trigger_secs.to_i > 0
      raise ArgumentError('response_timeout must be > 0') unless response_timeout.to_i > 0

      @inactivity_trigger_secs = trigger_secs.to_i
      @inactivity_response_timeout = response_timeout.to_i

      # Start the inactivity check now only if we're already conected, otherwise
      # the connected event will schedule it.
      schedule_inactivity_checks if @connected
    end

    private

    def method_missing(sym, *args)
      deferred = EM::DefaultDeferrable.new
      # Shortcut for defining the callback case with just a block
      deferred.callback { |result| yield(result) } if block_given?

      if @connected
        @connection.send_command(sym, args)
        @defs.push(deferred)
      elsif @failed
        deferred.fail(Error.new("Redis connection in failed state"))
      else
        @command_queue << [deferred, sym, args]
      end

      deferred
    end

    def reconnect
      @reconnecting = true
      @connection.reconnect @host, @port
      EM::Hiredis.logger.info("#{@connection} Reconnecting")
    end

    def cancel_inactivity_checks
      EM.cancel_timer(@inactivity_timer) if @inactivity_timer
      @inactivity_timer = nil
    end

    def schedule_inactivity_checks
      if @inactivity_trigger_secs
        @inactive_seconds = 0
        @inactivity_timer = EM.add_periodic_timer(1) {
          @inactive_seconds += 1
          if @inactive_seconds > @inactivity_trigger_secs + @inactivity_response_timeout
            EM::Hiredis.logger.error "#{@connection} No response to ping, triggering reconnect"
            reconnect!
          elsif @inactive_seconds > @inactivity_trigger_secs
            EM::Hiredis.logger.debug "#{@connection} Connection inactive, triggering ping"
            ping
          end
        }
      end
    end

    def handle_reply(reply)
      if @defs.empty?
        if @monitoring
          emit(:monitor, reply)
        else
          raise "Replies out of sync: #{reply.inspect}"
        end
      else
        deferred = @defs.shift
        deferred.succeed(reply) if deferred
      end
    end
  end
end
