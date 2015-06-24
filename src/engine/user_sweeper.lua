local luact = require 'luact.init'
local actor = require 'luact.actor'
local cache = require 'engine.cacheref'
local _M = {}

local sweeper_mt = {}
sweeper_mt.__index = sweeper_mt
function sweeper_mt:add_user(user, wait)
	local sec = luact.clock.get()
	table.insert(self.exit_users, { 
		user = user, 
		wait_until = sec + wait
	})
end
function sweeper_mt:start(field)
	if not self.destroy_thread then
		-- unregister this field (from scheduler)
		local ref = cache.get(field.UnregistUrl)
		local ok, r = pcall(ref._close, ref, field.Vid, field.Size)
		if not ok then
			logger.error(field.UnregistUrl, r.bt, r.args[1])
		end
		-- kick cleanup fiber
		self.destroy_thread = luact.tentacle(function (f)
			local exit_users = self.exit_users
			local exit_count = 0
			local start_at = luact.clock.get()
			while #exit_users > 0 do 
				local nowsec = luact.clock.get()
				if nowsec - start_at > (15 * 60) then
					logger.warn('field destroy timeout. force close')
					break
				end
				for i=1,#exit_users do
					local eu = exit_users[i]
					if not eu then
						break
					end
					if eu.wait_until < nowsec then
						f:logout(eu.user)
						table.remove(exit_users, i)
						i = i - 1
						exit_count = exit_count + 1
						if exit_count > 50 then
							break
						end
					else
						-- TODO : should send remain time?
					end
				end
				luact.clock.sleep(1.0)
			end
			-- remove this field
			scplog('field destroy', f.Vid)
			luact.unregister(f.Vid)
		end, field)
	end
end

function _M.new()
	return setmetatable({
		exit_users = {},
		destroy_thread = false,
	}, sweeper_mt)
end

return _M
