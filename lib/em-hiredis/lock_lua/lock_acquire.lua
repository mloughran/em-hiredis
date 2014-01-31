-- Set key to token with expiry of timeout, if:
--  - It doesn't exist
--  - It exists and already has value of token (further set extends timeout)
-- Used to implement a re-entrant lock.
local key = KEYS[1]
local token = ARGV[1]
local timeout = ARGV[2]

local value = redis.call('get', key)

if value == token or not value then
    -- Great, either we hold the lock or it's free for us to take
    return redis.call('setex', key, timeout, token)
else
    -- Someone else has it
    return false
end
