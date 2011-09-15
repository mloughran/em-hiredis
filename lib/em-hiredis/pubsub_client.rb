module EventMachine::Hiredis
  class PubsubClient < Client
    PUBSUB_MESSAGES = %w{message pmessage}.freeze

    def initialize(host, port, password = nil, db = nil)
      @subs, @psubs = [], []
      super
    end

    def connect
      @sub_callbacks = Hash.new { |h, k| h[k] = [] }
      
      # Resubsubscribe to channels on reconnect
      # TODO: Send all subscriptions using one call to redis
      on(:connected) {
        @subs.each { |s| method_missing(:subscribe, s) }
        @psubs.each { |s| method_missing(:psubscribe, s) }
      }
      
      super
    end
    
    # Subscribe to a pubsub channel
    # 
    # If an optional proc / block is provided then it will be called when a
    # message is received on this channel
    # 
    # @return [Deferrable] Redis subscribe call
    # 
    def subscribe(channel, proc = nil, &block)
      if cb = proc || block
        @sub_callbacks[channel] << cb
      end
      @subs << channel
      method_missing(:subscribe, channel)
    end
    
    # Unsubscribe all callbacks for a given channel
    #
    # @return [Deferrable] Redis unsubscribe call
    #
    def unsubscribe(channel)
      @sub_callbacks.delete(channel)
      @subs.delete(channel)
      method_missing(:unsubscribe, channel)
    end

    # Unsubscribe a given callback from a channel. Will unsubscribe from redis
    # if there are no remaining subscriptions on this channel
    #
    # @return Boolean representing whether or not the given callback existed
    #
    def unsubscribe_proc(channel, proc)
      if @sub_callbacks[channel].delete(proc)
        if @sub_callbacks[channel].empty?
          @sub_callbacks.delete[channel]
          unsubscribe(channel)
        end
        return true
      else
        return false
      end
    end

    def psubscribe(channel)
      @psubs << channel
      method_missing(:punsubscribe, channel)
    end

    def punsubscribe(channel)
      @psubs.delete(channel)
      method_missing(:punsubscribe, channel)
    end
    
    private
    
    def handle_reply(reply)
      if reply && PUBSUB_MESSAGES.include?(reply[0]) # reply can be nil
        kind, subscription, d1, d2 = *reply

        case kind.to_sym
        when :message
          if @sub_callbacks.has_key?(subscription)
            @sub_callbacks[subscription].each { |cb| cb.call(d1) }
          end
          # Arguments are channel, message payload
          emit(:message, subscription, d1)
        when :pmessage
          # Arguments are original pattern, channel, message payload
          emit(:pmessage, subscription, d1, d2)
        end
      else
        super
      end
    end
  end
end
