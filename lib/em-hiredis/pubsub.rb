module EventMachine::Hiredis
  class Pubsub
    attr_reader :client

    def initialize(client)
      @client = client
      @client.on(:message) { |channel, message|
        if @sub_callbacks.has_key?(channel)
          @sub_callbacks[channel].each { |cb| cb.call(message) }
        end
      }
      @sub_callbacks = Hash.new { |h, k| h[k] = [] }
    end

    def subscribe(channel, proc = nil, &block)
      cb = proc || block
      raise "Proc or block required when subscribing" unless cb
      @sub_callbacks[channel] << cb
      @client.subscribe(channel)
    end

    # Unsubscribe a given callback from a channel. Will unsubscribe from redis
    # if there are no remaining subscriptions on this channel
    #
    # @return Boolean representing whether or not the given callback was
    # removed
    #
    def unsubscribe_proc(channel, proc)
      if @sub_callbacks[channel].delete(proc)
        if @sub_callbacks[channel].empty?
          @sub_callbacks.delete[channel]
          @client.unsubscribe(channel)
        end
        return true
      else
        return false
      end
    end

    # Unsubscribe all callbacks for a given channel
    #
    # @return [Deferrable] Deferrable for redis unsubscribe call
    #
    def unsubscribe(channel)
      @sub_callbacks.delete(channel)
      return @client.unsubscribe(channel)
    end
  end
end
