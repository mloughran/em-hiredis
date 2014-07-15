module IRedisMock
  def self.start(replies = {})
    @sig = EventMachine::start_server("127.0.0.1", 6381, Connection)
    @received = []
    @replies = replies
    @paused = false
  end

  def self.stop
    EventMachine::stop_server(@sig)
  end

  def self.received
    @received ||= []
  end

  def self.pause
    @paused = true
  end
  def self.unpause
    @paused = false
  end

  def self.paused
    @paused
  end

  def self.replies
    @replies
  end

  class Connection < EventMachine::Connection
    def initialize
      @data = ""
      @parts = []
    end

    def unbind
      IRedisMock.received << 'disconnect'
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

        if IRedisMock.replies.member?(command_line)
          reply = IRedisMock.replies[command_line]
        else
          reply = "+OK"
        end

        # p "[#{command_line}] => [#{reply}]"

        IRedisMock.received << command_line

        if IRedisMock.paused
          # puts "Paused, therefore not sending [#{reply}]"
        else
          send_data "#{reply}\r\n"
        end
      end
    end
  end
end
