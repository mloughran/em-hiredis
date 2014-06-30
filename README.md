# em-hiredis

## What

A Redis client for EventMachine designed to be fast and simple.

## Why

I wanted a client which:

* used the C hiredis library to parse redis replies
* had a convenient API for pubsub
* exposed the state of the underlying redis connections so that custom failover logic could be written outside the library

Also, <https://github.com/madsimian/em-redis> is no longer maintained.

## Getting started

Connect to redis:

    require 'em-hiredis'
    redis = EM::Hiredis.connect

Or, connect to redis with a redis URL (for a different host, port, password, DB)

    redis = EM::Hiredis.connect("redis://:secretpassword@example.com:9000/4")

Commands may be sent immediately. Any commands sent while connecting to redis will be queued.

All redis commands are available without any remapping of names, and return a deferrable

    redis.set('foo', 'bar').callback {
      redis.get('foo').callback { |value|
        p [:returned, value]
      }
    }

If redis replies with an error (for example you called a hash operation against a set or the database is full), or if the redis connection disconnects before the command returns, the deferrable will fail.

    redis.sadd('aset', 'member').callback {
      response_deferrable = redis.hget('aset', 'member')
      response_deferrable.errback { |e|
        p e # => #<EventMachine::Hiredis::RedisError: Error reply from redis (wrapped in redis_error)>
        p e.redis_error # => #<RuntimeError: ERR Operation against a key holding the wrong kind of value>
      }
    }

As a shortcut, if you're only interested in binding to the success case you can simply provide a block to any command

    redis.get('foo') { |value|
      p [:returned, value]
    }

## Understanding the state of the connection

When a connection to redis server closes, a `:disconnected` event will be emitted and the connection will be immediately reconnect. If the connection reconnects a `:connected` event will be emitted.

If a reconnect fails to connect, a `:reconnect_failed` event will be emitted (rather than `:disconnected`) with the number of consecutive failures, and the connection will be retried after a timeout (defaults to 0.5s, can be set via `EM::Hiredis.reconnect_timeout=`).

If a client fails to reconnect 4 consecutive times then a `:failed` event will be emitted, and any queued redis commands will be failed (otherwise they would be queued forever waiting for a reconnect).

## Pubsub

The way pubsub works in redis is that once a subscribe has been made on a connection, it's only possible to send (p)subscribe or (p)unsubscribe commands on that connection. The connection will also receive messages which are not replies to commands.

The regular `EM::Hiredis::Client` no longer understands pubsub messages - this logic has been moved to `EM::Hiredis::PubsubClient`. The pubsub client can either be initialized directly (see code) or you can get one connected to the same redis server by calling `#pubsub` on an existing `EM::Hiredis::Client` instance.

Pubsub can either be used in em-hiredis in a close-to-the-metal fashion, or you can use the convenience functionality for binding blocks to subscriptions if you prefer (recommended).

### Close to the metal pubsub interface

Basically just bind to `:message` and `:pmessage` events:

    # Create two connections, one will be used for subscribing
    redis = EM::Hiredis.connect
    pubsub = redis.pubsub

    pubsub.subscribe('bar.0').callback { puts "Subscribed" }
    pubsub.psubscribe('bar.*')

    pubsub.on(:message) { |channel, message|
      p [:message, channel, message]
    }

    pubsub.on(:pmessage) { |key, channel, message|
      p [:pmessage, key, channel, message]
    }

    EM.add_periodic_timer(1) {
      redis.publish("bar.#{rand(2)}", "hello").errback { |e|
        p [:publisherror, e]
      }
    }

### Richer pubsub interface

If you pass a block to `subscribe` or `psubscribe`, the passed block will be called whenever a message arrives on that subscription:

    redis = EM::Hiredis.connect

    puts "Subscribing"
    redis.pubsub.subscribe("foo") { |msg|
      p [:sub1, msg]
    }

    redis.pubsub.psubscribe("f*") { |msg|
      p [:sub2, msg]
    }

    EM.add_periodic_timer(1) {
      redis.publish("foo", "Hello")
    }

    EM.add_timer(5) {
      puts "Unsubscribing sub1"
      redis.pubsub.unsubscribe("foo")
    }

It's possible to subscribe to the same channel multiple time and just unsubscribe a single callback using `unsubscribe_proc` or `punsubscribe_proc`.




## Developing

You need bundler and a local redis server running on port 6379 to run the test suite.

    # WARNING: The tests call flushdb on db 9 - this clears all keys!
    bundle exec rake

Run an individual spec:

    bundle exec rspec spec/redis_commands_spec.rb

Many thanks to the em-redis gem for getting this gem bootstrapped with some tests.
