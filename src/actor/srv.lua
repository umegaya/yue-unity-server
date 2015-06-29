local json = require 'engine.json'
local luact = require 'luact.init'
local actor = require 'luact.actor'
local gossip = require 'engine.gossip'
local cache = require 'engine.cacheref'
local url = require 'engine.baseurl'
local refs = {}

local _M = {}

-- helper
local thread = luact.tentacle(function ()
	luact.clock.sleep(1)
	local a = actor.of(_M)
	gossip.initialize(a)
	while true do
		local p = gossip.load_percentile()
		logger.info('load_percentile', p)
		if p > 0.75 then
			logger.warn('load become too high. create new node', p)
			local ok, n = pcall(luact.node.new, luact.opts.env.image_name, {
				["env.role"] = luact.opts.env.role,
			})
			if not ok then
				logger.report('node creation failure', n)
			else
				logger.warn('finish to create new node', n)
			end
		end
		luact.clock.sleep(5)
	end
end)

local function do_register(pfx, file, baseurl, ...)
	local name
	local sec = math.floor(luact.clock.get())
	local ok, r
	while true do
		name = pfx.."/"..tonumber(sec).."_"..math.random(1, 1000000) -- time + random seed

		ok, r = pcall(luact.register, name, file, baseurl..name, ...)
		if ok then
			break
		else
			logger.report('fail to register', name, r)
			luact.clock.sleep(1.0)
		end
	end
	return baseurl..name, r
end

-- debug
function _M:echo(v)
	return v
end
function _M:close_me()
	luact.close_peer()
end
function _M.ping(verb, headers, payload)
	return 'pong+v4'
end
function _M.__actor_destroy__()
	luact.tentacle.cancel(thread)
end
function _M:_close(field_url, size)
	cache.remove(field_url)
	local ok, r = pcall(gossip.add_load_score, -size)
	if not ok then
		logger.report('gossip add score error', r)
	end
end
-- web interface
function _M._open(verb, headers, body)
	local payload = json.decode(body)
	local n = gossip.find_best_server()
	if not n then
		logger.report('all server thread fully loaded: stay tune and then new server launches!!')
		return nil
	end
	logger.info('field open at', n.actor)
	return n.actor:_create(payload.size, payload.websv_url, payload.field_data_json)
end
function _M._genotp(verb, headers, body)
	local payload = json.decode(body)
	local field_url, user_id, user_data_json = payload.field_url, payload.user_id, payload.user_data_json
	local ref = cache.get(field_url)
	return ref:_genotp(user_id, user_data_json)
end
-- tcp interface
function _M:_create(size, caller_websv_url, field_data_json)
	local baseurl = url.game:gsub('0.0.0.0', luact.opts.env.external_address)
	logger.info('create', baseurl)
	local field_name, r = do_register("/gf", "src/actor/gf.lua", baseurl, caller_websv_url, url.sched_actor, field_data_json, size)
	local ok, r = pcall(gossip.add_load_score, size)
	if not ok then
		logger.report('gossip add score error', r)
	end
	return field_name
end
function _M:_createq(name, settings, user_id, user_data_json)
	logger.info('createq', name, user_id)
	local q_name = "/qw/"..name
	local q_url = url.game:gsub('0.0.0.0', luact.opts.env.external_address)..q_name
	local ok, q = pcall(luact.register, q_name, "src/actor/qw.lua", name, settings, user_id, user_data_json)
	if not ok then
		if q:is('vid_registered') then
			logger.info('createq: already created', user_id, q_url)
			q.args[2]:_add(user_id, user_data_json)
			return q_url
		else
			logger.report(q)
			error(q)
		end
	end
	ok, q = pcall(gossip.add_load_score, 1)
	if not ok then
		logger.report('gossip add score error', q)
	end
	return q_url
end

return _M

