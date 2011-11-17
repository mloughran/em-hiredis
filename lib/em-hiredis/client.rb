module EventMachine::Hiredis
  class Client
    PUBSUB_MESSAGES = %w{message pmessage}.freeze

    include EventMachine::Hiredis::EventEmitter
    include EM::Deferrable

    attr_reader :host, :port, :password, :db

    def self.connect(host = 'localhost', port = 6379)
      new(host, port).connect
    end

    def initialize(host, port, password = nil, db = nil)
      @host, @port, @password, @db = host, port, password, db
      @subs, @psubs, @defs = [], [], []
      @closing_connection = false
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
        else
          unless @closing_connection
            EM.add_timer(1) { reconnect }
          end
        end
      end

      @connection.on(:connected) do
        @connected = true

        auth(@password) if @password
        select(@db) if @db

        @subs.each { |s| method_missing(:subscribe, s) }
        @psubs.each { |s| method_missing(:psubscribe, s) }
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
          if reply && PUBSUB_MESSAGES.include?(reply[0]) # reply can be nil
            kind, subscription, d1, d2 = *reply

            case kind.to_sym
            when :message
              emit(:message, subscription, d1)
            when :pmessage
              emit(:pmessage, subscription, d1, d2)
            end
          else
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

    def subscribe(channel)
      @subs << channel
      method_missing(:subscribe, channel)
    end

    def unsubscribe(channel)
      @subs.delete(channel)
      method_missing(:unsubscribe, channel)
    end

    def psubscribe(channel)
      @psubs << channel
      method_missing(:psubscribe, channel)
    end

    def punsubscribe(channel)
      @psubs.delete(channel)
      method_missing(:punsubscribe, channel)
    end

    def select(db, &blk)
      @db = db
      method_missing(:select, db, &blk)
    end

    def auth(password, &blk)
      @password = password
      method_missing(:auth, password, &blk)
    end

    def monitor(&blk)
      @monitoring = true
      method_missing(:monitor, &blk)
    end

    def info(&blk)
      hash_processor = lambda do |response|
        info = {}
        response.each_line do |line|
          key, value = line.split(":", 2)
          info[key.to_sym] = value.chomp
        end
        blk.call(info)
      end
      method_missing(:info, &hash_processor)
    end

    def close_connection
      @closing_connection = true
      @connection.close_connection_after_writing
      @defs.each
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
  end
end
