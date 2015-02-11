# Wraps a deferrable and allows the switching of callbacks and errbacks
# depending on whether #cancel is called before the completion of the deferrable.
#
# Allows one to conveniently start an async operation which creates a resource
# rather than just returning a value and attach callbacks for 4 cases:
#
# callback           - receive the desired resource.
# callback_cancelled - clean up if the resource was successfully created, but we
#                      have decided we no longer want it.
# errback            - deal with failure to create the resource (retry perhaps).
# errback_cancelled  - deal with failure to create the resource when we no longer
#                      wanted it anyway, probably do nothing.

module EM::Hiredis
  class CancellableDeferrable
    def initialize(df)
      @df = df
      @cancelled = false
    end

    def cancel
      @cancelled = true
    end

    def callback(&blk)
      @df.callback { |*args|
        unless @cancelled
          blk.call(*args)
        end
      }
      self
    end

    def callback_cancelled(&blk)
      @df.callback { |*args|
        if @cancelled
          blk.call(*args)
        end
      }
      self
    end

    def errback(&blk)
      @df.errback { |*args|
        unless @cancelled
          blk.call(*args)
        end
      }
      self
    end

    def errback_cancelled(&blk)
      @df.errback { |*args|
        if @cancelled
          blk.call(*args)
        end
      }
      self
    end
  end
end
