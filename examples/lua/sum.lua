local a = redis.call('get', KEYS[1])
local b = redis.call('get', KEYS[2])

return a + b
