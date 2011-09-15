module EventMachine::Hiredis
  class PubsubClient < Client
    PUBSUB_MESSAGES = %w{message pmessage subscribe unsubscribe psubscribe punsubscribe}.freeze

    def initialize(host, port, password = nil, db = nil)
      @subs, @psubs = [], []
      @pubsub_defs = Hash.new { |h,k| h[k] = [] }
      super
    end

    def connect
      @sub_callbacks = Hash.new { |h, k| h[k] = [] }
      
      # Resubsubscribe to channels on reconnect
      on(:reconnected) {
        raw_send_command(:subscribe, *@subs) if @subs.any?
        raw_send_command(:psubscribe, *@psubs) if @psubs.any?
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
      raw_send_command(:subscribe, channel)
      return pubsub_deferrable(channel)
    end
    
    # Unsubscribe all callbacks for a given channel
    #
    # @return [Deferrable] Redis unsubscribe call
    #
    def unsubscribe(channel)
      @sub_callbacks.delete(channel)
      @subs.delete(channel)
      raw_send_command(:unsubscribe, channel)
      return pubsub_deferrable(channel)
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
      raw_send_command(:punsubscribe, channel)
      return pubsub_deferrable(channel)
    end

    def punsubscribe(channel)
      @psubs.delete(channel)
      raw_send_command(:punsubscribe, channel)
      return pubsub_deferrable(channel)
    end
    
    private
    
    # Send a command to redis without adding a deferrable for it. This is
    # useful for commands for which replies work or need to be treated
    # differently
    def raw_send_command(sym, *args)
      if @connected
        @connection.send_command(sym, *args)
      else
        callback do
          @connection.send_command(sym, *args)
        end
      end
      return nil
    end

    def pubsub_deferrable(channel)
      df = EM::DefaultDeferrable.new
      @pubsub_defs[channel].push(df)
      df
    end

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
        else
          if @pubsub_defs[subscription].any?
            df = @pubsub_defs[subscription].shift
            df.succeed(reply)
            # Cleanup empty arrays
            if @pubsub_defs[subscription].empty?
              @pubsub_defs.delete(subscription)
            end
          end

          # Also emit the event, as an alternative to using the deferrables
          emit(kind.to_sym, subscription, d1)
        end
      else
        super
      end
    end
  end
end
