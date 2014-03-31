module EventMachine::Hiredis
  module EventEmitter
    def on(event, &listener)
      _listeners.add(event, listener)
    end

    def emit(event, *args)
      _listeners[event].each { |l| l.call(*args) }
    end

    def remove_listener(event, &listener)
      _listeners.remove(event, listener)
    end

    def remove_all_listeners(event)
      _listeners.delete(event)
    end

    def listeners(event)
      _listeners[event]
    end

    private

    def _listeners
      @_listeners ||= ArrayHash.new
    end
  end
end
