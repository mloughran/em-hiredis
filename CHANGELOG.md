# Changelog

## 0.3.0 (2014-06-30)

[NEW] Lua script support (see README for details).

[NEW] `Client#reconnect!` method which disconnects, reconfigures, and reconnects.

[CHANGED] Locking abstraction re-implemented using lua (safer and simpler) [mdpye].

[CHANGED] Hiredis dependency updated to 0.5.x

## 0.2.1 (2013-04-22)

[NEW] Support for connecting to redis on a unix socket.

[CHANGED] Redis error reply message now used as message for RedisError.

## 0.2.0 (2013-04-05)

[NEW] Richer interface for pubsub (accessible via `client.pubsub`). See example in `examples/pubsub.rb`.

[NEW] Better failure handling:

  * Clients now emit the following events: connected, reconnected, disconnected, reconnect_failed (passes the number of consecutive failures)
  * Client is considered failed after 4 consecutive failures
  * Fails all queued commands when client failed
  * Can now reconfiure and reconnect an exising client
  * Reconnect timeout can be configured (defaults to 0.5s)

[NEW] Added `EM::Hiredis::Lock` and `EM::Hiredis::PersistentLock`

[CHANGE] When a redis command fails, the errback is now always passed an `EM::Hiredis::Error`.

[FIX] Fixed info parsing for Redis 2.6
