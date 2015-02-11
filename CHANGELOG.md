# Changelog

## 1.0.0 (2015-02-25)

[BUGFIX] Replies becoming out of sync after voluntary reconnect.

[CHANGE] Clients are now configured through the use of URIs only (not individual host, port, db params)

  The previous interface was inconsistently applied, for example clients could be constructed using
  individual params, but only re-configured using a uri.

[CHANGE] Client's public interface simplified considerably wrt connect / reconnect / reconfigure.

  Use `connect` to connect, `reconnect` to force reconnection and `reconnect(uri)` to force reconnection
  to a different server.

[CHANGE] Pubsub interface no longer returns deferrables for subscribe methods.

  Rationale: Redis pubsub subscriptions can only ever be provided on a "best effort" basis where
  reconnection-handling is provided - while reconnection takes place, messages will no be received.
  If it is important to be aware of these periods, binding to a combination of :disconnected and
  :subscribe on the pubsub client will allow one to deduce when the subscription is active.

  The deferrable interface was also awkward in terms of issuing subscribe commands for multiple
  channels at once.

[NEW] Inactivity timeouts:

  Trigger activity on idle connections and force reconnect if no response is found.
  Particularly beneficial for pubsub connections where there may be no activity from the server for
  extended periods and this is otherwise indistinguishable from a hung TCP connection.

## 0.2.1 (2013-04-22)

[NEW] Support for connecting to redis on a unix socket.

[CHANGED] Redis error reply message now used as message for RedisError.

## 0.2.0 (2013-04-05)

[NEW] Richer interface for pubsub (accessible via `client.pubsub`). See example in `examples/pubsub.rb`.

[NEW] Better failure handling:

  * Clients now emit the following events: connected, reconnected, disconnected, reconnect_failed (passes the number of consecutive failures)
  * Client is considered failed after 4 consecutive failures
  * Fails all queued commands when client failed
  * Can now reconfigure and reconnect an exising client
  * Reconnect timeout can be configured (defaults to 0.5s)

[NEW] Added `EM::Hiredis::Lock` and `EM::Hiredis::PersistentLock`

[CHANGE] When a redis command fails, the errback is now always passed an `EM::Hiredis::Error`.

[FIX] Fixed info parsing for Redis 2.6
