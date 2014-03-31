module EM::Hiredis
  class Heartbeat
    attr_reader :every

    def initialize(client, every = 5, logger = EM::Hiredis.logger)
      @client, @every, @logger = client, every, logger
      client.on(:connected, &method(:start))
      client.on(:reconnected, &method(:start))
      client.on(:disconnected, &method(:stop))
      start if client.connected?
    end

    # Allows to change the interval of the heartbeat
    def run_every(every)
      if @every != every
        stop
        @every = every
        start
      end
    end

    def running?
      !!@fd
    end

    protected

    attr_reader :logger

    def start
      return if running?

      @fd = EM.add_periodic_timer(@every) {
        if @waiting
          @waiting.fail("heartbeat-timeout")
          logger.warn("Heartbeat timeout. DEFIBRILATE!")
          stop
          @client.reconnect!
        else
          @waiting = @client.ping
          @waiting.callback{|*a| done_waiting(:success, *a)}
          # Redis responds with an error when subscribed to something
          @waiting.errback{|*a| done_waiting(:error, *a)}
          logger.info("Heartbeat sent ping")
        end
      }
      logger.info("Heartbeat started")
    end

    def stop
      return unless running?

      EM.cancel_timer(@fd)
      @fd = nil
      @waiting = nil

      logger.info("Heartbeat stopped")
    end

    def done_waiting(*a)
      @waiting = nil
      logger.info("Heartbeat got response #{a.inspect}")
    end
  end
end
