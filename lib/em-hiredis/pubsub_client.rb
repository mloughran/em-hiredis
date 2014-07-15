module EventMachine::Hiredis
  class PubsubClient < BaseClient
    PUBSUB_MESSAGES = %w{message pmessage subscribe unsubscribe psubscribe punsubscribe}.freeze

    PING_CHANNEL = '__em-hiredis-ping'

    def initialize(host='localhost', port='6379', password=nil, db=nil)
      @subs, @psubs = [], []
      @pubsub_defs = Hash.new { |h,k| h[k] = [] }
      super
    end

    def connect
      @sub_callbacks = Hash.new { |h, k| h[k] = [] }
      @psub_callbacks = Hash.new { |h, k| h[k] = [] }
      
      # Resubsubscribe to channels on reconnect
      on(:reconnected) {
        raw_send_command(:subscribe, @subs) if @subs.any?
        raw_send_command(:psubscribe, @psubs) if @psubs.any?
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
      raw_send_command(:subscribe, [channel])
      return pubsub_deferrable(channel)
    end
    
    # Unsubscribe all callbacks for a given channel
    #
    # @return [Deferrable] Redis unsubscribe call
    #
    def unsubscribe(channel)
      @sub_callbacks.delete(channel)
      @subs.delete(channel)
      raw_send_command(:unsubscribe, [channel])
      return pubsub_deferrable(channel)
    end

    # Unsubscribe a given callback from a channel. Will unsubscribe from redis
    # if there are no remaining subscriptions on this channel
    #
    # @return [Deferrable] Succeeds when the unsubscribe has completed or
    #   fails if callback could not be found. Note that success may happen
    #   immediately in the case that there are other callbacks for the same
    #   channel (and therefore no unsubscription from redis is necessary)
    #
    def unsubscribe_proc(channel, proc)
      df = EM::DefaultDeferrable.new
      if @sub_callbacks[channel].delete(proc)
        if @sub_callbacks[channel].any?
          # Succeed deferrable immediately - no need to unsubscribe
          df.succeed
        else
          unsubscribe(channel).callback { |_|
            df.succeed
          }
        end
      else
        df.fail
      end
      return df
    end

    # Pattern subscribe to a pubsub channel
    #
    # If an optional proc / block is provided then it will be called (with the
    # channel name and message) when a message is received on a matching
    # channel
    #
    # @return [Deferrable] Redis psubscribe call
    #
    def psubscribe(pattern, proc = nil, &block)
      if cb = proc || block
        @psub_callbacks[pattern] << cb
      end
      @psubs << pattern
      raw_send_command(:psubscribe, [pattern])
      return pubsub_deferrable(pattern)
    end

    # Pattern unsubscribe all callbacks for a given pattern
    #
    # @return [Deferrable] Redis punsubscribe call
    #
    def punsubscribe(pattern)
      @psub_callbacks.delete(pattern)
      @psubs.delete(pattern)
      raw_send_command(:punsubscribe, [pattern])
      return pubsub_deferrable(pattern)
    end

    # Unsubscribe a given callback from a pattern. Will unsubscribe from redis
    # if there are no remaining subscriptions on this pattern
    #
    # @return [Deferrable] Succeeds when the punsubscribe has completed or
    #   fails if callback could not be found. Note that success may happen
    #   immediately in the case that there are other callbacks for the same
    #   pattern (and therefore no punsubscription from redis is necessary)
    #
    def punsubscribe_proc(pattern, proc)
      df = EM::DefaultDeferrable.new
      if @psub_callbacks[pattern].delete(proc)
        if @psub_callbacks[pattern].any?
          # Succeed deferrable immediately - no need to punsubscribe
          df.succeed
        else
          punsubscribe(pattern).callback { |_|
            df.succeed
          }
        end
      else
        df.fail
      end
      return df
    end

    # Pubsub connections to not support even the PING command, but it is useful,
    # especially with read-only connections like pubsub, to be able to check that
    # the TCP connection is still usefully alive.
    #
    # This is not particularly elegant, but it's probably the best we can do
    # for now. Ping support for pubsub connections is being considerred:
    # https://github.com/antirez/redis/issues/420
    def ping
      subscribe(PING_CHANNEL).callback {
        unsubscribe(PING_CHANNEL)
      }
    end

    private
    
    # Send a command to redis without adding a deferrable for it. This is
    # useful for commands for which replies work or need to be treated
    # differently
    def raw_send_command(sym, args)
      if @connected
        @connection.send_command(sym, args)
      else
        callback do
          @connection.send_command(sym, args)
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
        # Note: pmessage is the only message with 4 arguments
        kind, subscription, d1, d2 = *reply

        case kind.to_sym
        when :message
          if @sub_callbacks.has_key?(subscription)
            @sub_callbacks[subscription].each { |cb| cb.call(d1) }
          end
          # Arguments are channel, message payload
          emit(:message, subscription, d1)
        when :pmessage
          if @psub_callbacks.has_key?(subscription)
            @psub_callbacks[subscription].each { |cb| cb.call(d1, d2) }
          end
          # Arguments are original pattern, channel, message payload
          emit(:pmessage, subscription, d1, d2)
        else
          if @pubsub_defs[subscription].any?
            df = @pubsub_defs[subscription].shift
            df.succeed(d1)
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
