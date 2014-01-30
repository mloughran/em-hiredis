-- Deletes a key only if it has the value supplied as token
local key = KEYS[1]
local token = ARGV[1]

if redis.call('get', key) == token then
    return redis.call('del', key)
else
    return 0
end
