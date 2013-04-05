$:.unshift(File.expand_path('../../lib', __FILE__))
require 'em-hiredis'

EM.run {
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
}
