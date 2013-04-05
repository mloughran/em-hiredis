$:.unshift(File.expand_path('../../lib', __FILE__))
require 'em-hiredis'

EM.run {
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
}
