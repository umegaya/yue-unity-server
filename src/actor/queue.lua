local json = require 'engine.json'
local luact = require 'luact.init'
local actor = require 'luact.actor'
local gossip = require 'engine.gossip'
local cache = require 'engine.cacheref'
local url = require 'engine.baseurl'
local _M = {}

function _M._enter(verb, headers, body)
	local n = gossip.find_best_server()
	if not n then
		logger.report('all server thread fully loaded: stay tune and then new server launches!!')
		return nil
	end
	local payload = json.decode(body)
	return n.actor:_createq(payload.name, payload.settings, payload.user_id, payload.user_data_json)
end

return _M
