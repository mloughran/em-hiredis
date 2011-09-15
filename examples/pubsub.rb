require 'rubygems'
$:.unshift(File.expand_path('../../lib', __FILE__))
require 'em-hiredis'

EM.run {
  redis = EM::Hiredis.connect
  
  # If you pass a block to subscribe it will be called whenever a message
  # is received on this channel
  redis.pubsub.subscribe('foo') { |message|
    puts "Block received #{message}"
  }
  
  # You can also pass any other object which responds to call if you wish
  callback = Proc.new { |message|
    "Proc received #{message}"
  }
  df = redis.pubsub.subscribe('foo', callback)
  
  # All calls return a deferrable
  df.callback { |reply|
    p [:subscription_succeeded, reply]
  }
  
  # Passing such an object is useful if you want to unsubscribe
  p [:unsubscribed?, redis.pubsub.unsubscribe_proc('foo', callback)]
  
  # Or if you want to call a method on a certain object
  class Thing
    def receive_message(message)
      puts "Thing received #{message}"
    end
  end
  redis.pubsub.subscribe('bar', Thing.new.method(:receive_message))
  
  # You can also get all the following raw events:
  # message pmessage subscribe unsubscribe psubscribe punsubscribe
  redis.pubsub.on(:message) { |channel, message|
    p [:message_received, channel, message]
  }
  redis.pubsub.on(:unsubscribe) { |channel, remaining_subscriptions|
    p [:unsubscribe_happened, channel, remaining_subscriptions]
  }
  
  EM.add_timer(1) {
    # You can also unsubscribe completely from a channel
    redis.pubsub.unsubscribe('foo')
    
    # Publishing events
    redis.publish('bar', 'Hello')
  }
}
