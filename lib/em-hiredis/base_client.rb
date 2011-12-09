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

    def initialize(host, port, password = nil, db = nil)
      @host, @port, @password, @db = host, port, password, db
      @defs = []
      @closing_connection = false
      @reconnect_failed_count = 0
      @failed = false

      self.errback {
        @failed = true
      }
    end

    def connect
      @connection = EM.connect(@host, @port, Connection, @host, @port)

      @connection.on(:closed) do
        if @connected
          @defs.each { |d| d.fail("Redis disconnected") }
          @defs = []
          @deferred_status = nil
          @connected = false
          unless @closing_connection
            @reconnecting = true
            reconnect
          end
          emit(:disconnected)
        else
          unless @closing_connection
            @reconnect_failed_count += 1
            EM.add_timer(1) { reconnect }
            emit(:reconnect_failed, @reconnect_failed_count)

            if @reconnect_failed_count >= 4
              self.fail("Could not connect after 4 attempts")
            end
          end
        end
      end

      @connection.on(:connected) do
        @connected = true
        @reconnect_failed_count = 0
        @failed = false

        select(@db) if @db
        auth(@password) if @password

        emit(:connected)
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
          deferred.fail(reply) if deferred
        else
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

    def select(db, &blk)
      @db = db
      method_missing(:select, db, &blk)
    end

    def auth(password, &blk)
      @password = password
      method_missing(:auth, password, &blk)
    end

    def close_connection
      @closing_connection = true
      @connection.close_connection_after_writing
    end

    private

    def method_missing(sym, *args)
      deferred = EM::DefaultDeferrable.new
      # Shortcut for defining the callback case with just a block
      deferred.callback { |result| yield(result) } if block_given?

      if @connected
        @connection.send_command(sym, *args)
        @defs.push(deferred)
      else
        callback do
          @connection.send_command(sym, *args)
          @defs.push(deferred)
        end
      end

      deferred
    end

    def reconnect
      EventMachine::Hiredis.logger.debug("Trying to reconnect to Redis")
      @connection.reconnect @host, @port
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
