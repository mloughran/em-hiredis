require 'hiredis/reader'

module EventMachine::Hiredis
  class Connection < EM::Connection
    include EventMachine::Hiredis::EventEmitter

    def initialize(host, port, args={})
      super
      @host, @port = host, port
      tls = args[:ssl].present?
      @name = "[em-hiredis #{@host}:#{@port} #{tls}]"
      @args = args
    end

    def post_init
      if @args[:ssl]
        start_tls(@args[:ssl_params])
      end
    end

    def reconnect(host, port)
      super
      @host, @port = host, port
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
      command = []
      command << "*#{args.size}"

      args.each do |arg|
        arg = arg.to_s
        command << "$#{string_size arg}"
        command << arg
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
