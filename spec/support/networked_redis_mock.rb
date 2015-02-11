module NetworkedRedisMock

  class RedisMock
    attr_reader :replies, :paused

    def initialize(replies = {})
      @sig = EventMachine::start_server("127.0.0.1", 6381, Connection, self) { |con|
        @connections.push(con)
      }
      @connections = []
      @received = []
      @connection_count = 0
      @replies = replies
      @paused = false
    end

    def stop
      EventMachine::stop_server(@sig)
    end

    def received
      @received ||= []
    end

    def connection_received
      @connection_count += 1
    end

    def connection_count
      @connection_count
    end

    def pause
      @paused = true
    end

    def unpause
      @paused = false
    end

    def kill_connections
      @connections.each { |c| c.close_connection }
      @connections.clear
    end
  end

  class Connection < EventMachine::Connection
    def initialize(redis_mock)
      @redis_mock = redis_mock
      @data = ""
      @parts = []
    end

    def post_init
      @redis_mock.connection_received
    end

    def unbind
      @redis_mock.received << 'disconnect'
    end

    def receive_data(data)
      @data << data

      while (idx = @data.index("\r\n"))
        @parts << @data[0..idx-1]
        @data = @data[idx+2..-1]
      end

      while @parts.length > 0
        throw "commands out of sync" unless @parts[0][0] == '*'

        num_parts = @parts[0][1..-1].to_i * 2 + 1
        return if @parts.length < num_parts

        command_parts = @parts[0..num_parts]
        @parts = @parts[num_parts..-1]

        # Discard length declarations
        command_line =
            command_parts
              .reject { |p| p[0] == '*' || p[0] == '$' }
              .join ' '

        if @redis_mock.replies.member?(command_line)
          reply = @redis_mock.replies[command_line]
        elsif command_line == '_DISCONNECT'
          close_connection
        else
          reply = "+OK"
        end

        @redis_mock.received << command_line

        unless @redis_mock.paused
          send_data "#{reply}\r\n"
        end
      end
    end
  end
end
