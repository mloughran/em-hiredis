require 'hiredis/reader'

module EventMachine::Hiredis
  class Connection < EM::Connection
    include EventMachine::Hiredis::EventEmitter

    def initialize(host, port, tls = false)
      super
      @host, @port, @tls = host, port, tls
      @name = "[em-hiredis #{@host}:#{@port} tls:#{@tls}]"
    end

    def reconnect(host, port, tls = false)
      super(host, port)
      @host, @port, @tls = host, port, tls
    end

    def connection_completed
      @reader = ::Hiredis::Reader.new
      tls_options = @tls == true ? { ssl_version: :tlsv1_2 } : @tls 
      start_tls(tls_options) if tls_options
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
