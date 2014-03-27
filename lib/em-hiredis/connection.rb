require 'hiredis/reader'

module EventMachine::Hiredis
  class Connection < EM::Connection
    include EventMachine::Hiredis::EventEmitter

    def initialize(host, port)
      super
      @host, @port = host, port
      @name = "[em-hiredis #{@host}:#{@port}]"
    end

    def reconnect(host, port)
      super
      @host, @port = host, port
      @name = "[em-hiredis #{@host}:#{@port}]"
    end

    def connection_completed
      @reader = ::Hiredis::Reader.new
      emit(:connected)
    end

    def receive_data(data)
      @reader.feed(data)
      until (reply = @reader.gets) == false
        emit(:message, reply)
      end
    end

    def unbind
      emit(:closed)
    end

    def send_command(command, args)
      send_data(command(command, *args))
    end

    def to_s
      @name
    end

    protected

    COMMAND_DELIMITER = "\r\n"

    def command(*args)
      command = Array.new(args.size * 2 + 1)
      command[0] = "*#{args.size}"

      args.each_with_index do |arg, i|
        arg = arg.to_s
        command[i*2+1] = "$#{string_size arg}"
        command[i*2+2] = arg
      end

      command.join(COMMAND_DELIMITER) + COMMAND_DELIMITER
    end

    if "".respond_to?(:bytesize)
      def string_size(string)
        string.to_s.bytesize
      end
    else
      def string_size(string)
        string.to_s.size
      end
    end
  end
end
