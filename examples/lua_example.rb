$:.unshift(File.expand_path('../../lib', __FILE__))
require 'em-hiredis'

EM.run do
  scripts_dir = File.expand_path("../lua", __FILE__)
  EM::Hiredis::Client.load_scripts_from(scripts_dir)

  redis = EM::Hiredis.connect

  redis.register_script(:multiply, <<-END)
    return redis.call('get', KEYS[1]) * ARGV[1]
  END

  redis.set('foo', 42).callback {
    redis.set('bar', 8).callback {

      # Multiply is defined above.
      # It is passed one key and one argument.
      redis.multiply(['foo'], [2]).callback { |v|
        puts "Multiply returned: #{v}"
      }.errback { |e|
        puts "Multiply error: #{e}"
      }

      # Sum is a lua script defined in sum.lua.
      # It is passed two keys.
      redis.sum(['foo', 'bar']).callback { |sum|
        puts "Sum returned: #{sum}"
      }.errback { |e|
        puts "Sum error: #{e}"
      }

    }
  }
end
