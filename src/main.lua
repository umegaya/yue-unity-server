package.path="src/share/?.lua;src/?.lua;"..package.path
-- load modules
_G.ServerMode = true
require 'common.compat_server' -- compatibility layer for server
_G.behavior = require 'common.behavior'
_G.class = require 'common.class'
local url = require 'engine.baseurl'
-- trusted port. should be in firewall
luact.listen(url.sched, { trusted = true })
-- untrusted port. ok to open to internet
luact.listen(url.game)
luact.listen(url.websv) -- for web server emuration
-- game rtserver actor
luact.register('/srv', {
	multi_actor = true,
}, './src/actor/srv.lua')
-- dummy webserver actor
luact.register('/wsv', {
	multi_actor = true,
}, './src/actor/wsv.lua')

-- memory trace 
--[[
local memory = require 'pulpo.memory'
luact.tentacle(function ()
	local cnt = 0
	while true do
		memory.dump_trace(cnt >= 10)
		if cnt >= 10 then
			cnt = 0
		end
		luact.clock.sleep(1.0)
		cnt = cnt + 1
	end
end)
]]

return true

