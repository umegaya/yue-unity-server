local luact = require 'luact.init'
local exception = luact.exception
local json = require 'engine.json'
local mod = require 'luact.module'
local sha2 = require 'lua-aws.deps.sha2'
local _M = {}
-- server side only methods (auth/creation)
local OTP_VALID_SPAN = 180
local otpmap = {} -- TODO : make it cdata by using hash.lua
function _M.gen(id, user_data_json)
	local otp = sha2.hash256("hoge"..tostring(os.clock())..tostring(math.random()))
	local sec = luact.clock.get()
	otpmap[otp] = {
		valid_until = sec + OTP_VALID_SPAN, 
		data = json.decode(user_data_json),
		id = id,
	}
	scplog('otp', 'generated', id, otp)
	return otp, OTP_VALID_SPAN
end

function _M.authorize(otp)
	local user = otpmap[otp]
	if not user then
		exception.raise('invalid', 'otp is invalid or expired', otp)
	end
	otpmap[otp] = nil
	return user
end

luact.tentacle(function ()
	while true do 
		local nowsec = luact.clock.get()
		for k,v in pairs(otpmap) do
			if nowsec > v.valid_until then
				logger.info('otp invalidate', k, nowsec, v.valid_until)
				otpmap[k] = nil
			end
		end
		luact.clock.sleep(10.0)
	end
end)

return _M
