module EventMachine::Hiredis
  module RedisConnection
    include EventMachine::Hiredis::EventEmitter

    def initialize(inactivity_trigger_secs = nil,
                   inactivity_response_timeout = 2,
                   name = 'unnamed connection')

      @name = name
      # Parser for incoming replies
      @reader = ::Hiredis::Reader.new
      # Queue of deferrables awaiting replies
      @response_queue = []

      @connected = false

      @inactivity_checker = InactivityChecker.new(inactivity_trigger_secs, inactivity_response_timeout)
      @inactivity_checker.on(:activity_timeout) {
        EM::Hiredis.logger.debug("#{@name} - Sending ping")
        send_command(EM::DefaultDeferrable.new, 'ping', [])
      }
      @inactivity_checker.on(:response_timeout) {
        EM::Hiredis.logger.warn("#{@name} - Closing connection because of inactivity timeout")
        close_connection
      }
    end

    def send_command(df, command, args)
      @response_queue.push(df)
      send_data(marshal(command, *args))
      return df
    end

    def pending_responses
      @response_queue.length
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

      @response_queue.each { |df| df.fail(EM::Hiredis::Error.new('Redis connection lost')) }
      @response_queue.clear

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
      df = @response_queue.shift
      if df
        if reply.kind_of?(RuntimeError)
          e = EM::Hiredis::RedisError.new(reply.message)
          e.redis_error = reply
          df.fail(e)
        else
          df.succeed(reply)
        end
      else
        emit(:replies_out_of_sync)
        close_connection
      end
    end
  end
end
