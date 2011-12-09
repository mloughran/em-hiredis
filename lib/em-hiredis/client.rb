module EventMachine::Hiredis
  class Client < BaseClient
    def self.connect(host = 'localhost', port = 6379)
      new(host, port).connect
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
  end
end
