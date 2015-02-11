require 'spec_helper'

describe EventMachine::Hiredis::Lock do

  def start(timeout = 1)
    connect(timeout) do |redis|
      @redis = redis
      yield
    end
  end

  def new_lock
    EventMachine::Hiredis::Lock.new(@redis, "test-lock", 2)
  end

  it "can be acquired" do
    start {
      new_lock.acquire.callback {
        done
      }.errback { |e|
        fail e
      }
    }
  end

  it "is re-entrant" do
    start {
      lock = new_lock
      lock.acquire.callback {
        lock.acquire.callback {
          done
        }.errback { |e|
          fail e
        }
      }.errback { |e|
        fail e
      }
    }
  end

  it "is exclusive" do
    start {
      new_lock.acquire.callback {
        new_lock.acquire.errback {
          done
        }.callback {
          fail "Should not be able to acquire lock from different client"
        }
      }.errback { |e|
        fail e
      }
    }
  end

  it "can be released and taken by another instance" do
    start {
      lock = new_lock
      lock.acquire.callback {
        lock.unlock.callback {
          new_lock.acquire.callback {
            done
          }.errback { |e|
            fail e
          }
        }.errback { |e|
          fail e
        }
      }.errback { |e|
        fail e
      }
    }
  end

  it "times out" do
    start(3) {
      new_lock.acquire.callback {
        EM.add_timer(2) {
          new_lock.acquire.callback {
            done
          }.errback { |e|
            fail e
          }
        }
      }.errback { |e|
        fail e
      }
    }
  end

  it "extends timeout on re-entry" do
    start(4) {
      lock = new_lock
      lock.acquire.callback {
        EM.add_timer(1) {
          lock.acquire.callback {
            EM.add_timer(1.5) {
              # Check it's still locked by initial instance
              new_lock.acquire.errback {
                done
              }.callback { |e|
                fail e
              }
            }
          }.errback { |e|
            fail e
          }
        }
      }.errback { |e|
        fail e
      }
    }
  end

  it "fails to release if it has not been taken" do
    start {
      new_lock.unlock.errback {
        done
      }.callback {
        fail "Released lock which had not been taken"
      }
    }
  end

  it "fails to release if taken by another instance" do
    start {
      new_lock.acquire.callback {
        new_lock.unlock.errback {
          done
        }.callback {
          fail "Released lock belonging to another instance"
        }
      }.errback { |e|
        fail e
      }
    }
  end
end
