module EventMachine::Hiredis
  module PubsubConnection
    include EventMachine::Hiredis::EventEmitter

    PUBSUB_COMMANDS = %w{subscribe unsubscribe psubscribe punsubscribe}.freeze
    PUBSUB_MESSAGES = (PUBSUB_COMMANDS + %w{message pmessage}).freeze

    PING_CHANNEL = '__em-hiredis-ping'

    def initialize(inactivity_trigger_secs = nil,
                   inactivity_response_timeout = 2,
                   name = 'unnamed connection')

      @name = name
      @reader = ::Hiredis::Reader.new

      @connected = false

      @inactivity_checker = InactivityChecker.new(inactivity_trigger_secs, inactivity_response_timeout)
      @inactivity_checker.on(:activity_timeout) {
        EM::Hiredis.logger.debug("#{@name} - Sending ping")
        send_command('subscribe', PING_CHANNEL)
        send_command('unsubscribe', PING_CHANNEL)
      }
      @inactivity_checker.on(:response_timeout) {
        EM::Hiredis.logger.warn("#{@name} - Closing connection because of inactivity timeout")
        close_connection
      }
    end

    def send_command(command, *channels)
      if PUBSUB_COMMANDS.include?(command.to_s)
        send_data(marshal(command, *channels))
      else
        raise "Cannot send command '#{command}' on Pubsub connection"
      end
    end

    def pending_responses
      # Connection is read only, we only issue subscribes and unsubscribes
      # and we don't count their issue vs completion, so there can be no
      # meaningful responses pending.
      0
    end

    # We special case AUTH, as it is the only req-resp model command which we
    # allow, and it must be issued on an otherwise unused connection
    def auth(password)
      df = @auth_df = EM::DefaultDeferrable.new
      send_data(marshal('auth', password))
      return df
    end

    # EM::Connection callback
    def connection_completed
      @connected = true
      emit(:connected)

      @inactivity_checker.start
    end

    # EM::Connection callback
    def receive_data(data)
      @inactivity_checker.activity

      @reader.feed(data)
      until (reply = @reader.gets) == false
        handle_response(reply)
      end
    end

    # EM::Connection callback
    def unbind
      @inactivity_checker.stop

      if @connected
        emit(:disconnected)
      else
        emit(:connection_failed)
      end
    end

    protected

    COMMAND_DELIMITER = "\r\n"

    def marshal(*args)
      command = []
      command << "*#{args.size}"

      args.each do |arg|
        arg = arg.to_s
        command << "$#{arg.to_s.bytesize}"
        command << arg
      end

      command.join(COMMAND_DELIMITER) + COMMAND_DELIMITER
    end

    def handle_response(reply)
      if @auth_df
        # If we're awaiting a response to auth, we will not have sent any other commands
        if reply.kind_of?(RuntimeError)
          e = EM::Hiredis::RedisError.new(reply.message)
          e.redis_error = reply
          @auth_df.fail(e)
        else
          @auth_df.succeed(reply)
        end
        @auth_df = nil
      else
        type = reply[0]
        if PUBSUB_MESSAGES.include?(type)
          emit(type.to_sym, *reply[1..-1])
        else
          EM::Hireds.logger.error("#{@name} - unrecognised response: #{reply.inspect}")
        end
      end
    end
  end
end