module EventMachine::Hiredis
  class Client < BaseClient
    def self.connect(host = 'localhost', port = 6379)
      new(host, port).connect
    end
  end
end
