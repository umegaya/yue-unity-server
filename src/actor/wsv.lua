-- emurate simple web server which communicate with rtserver
local luact = require 'luact.init'
local ffi = require 'ffiex.init'
local json = require 'engine.json'
local url = require 'engine.baseurl'
local cache = require 'engine.cacheref'
local hash = require 'engine.hash'
local thread = require 'pulpo.thread'
local _M = {}

local user_data_hash_t = hash.new('char *', 'char *')
ffi.cdef([[
	typedef struct _shared_game_data {
		$ user_data;
		char *game_data;
	} shared_game_data_t;
]], user_data_hash_t)
thread.shared_memory('game_data', function ()
	local p = luact.memory.alloc_typed('shared_game_data_t')
	p.user_data:_Init(64)
	return 'shared_game_data_t', p
end)

-- share variable in this actor (get from shared memory)
local game_data
local user_datas = {}
local function get_user_data(user_id)
	local user_data = user_datas[user_id]
	if not user_data then
		thread.lock_shared_memory('game_data', function (ptr, datas, id)
			local data = ffi.cast('shared_game_data_t*', ptr)
			local ud = ptr.user_data:Get(ffi.cast('char *', id))
			user_data = ffi.string(ud)
			datas[id] = user_data 
		end, user_datas, user_id)
	end
	logger.info('userdata', user_data)
	return user_data
end
local function get_game_data()
	if not game_data then
		thread.lock_shared_memory('game_data', function (ptr, user_id, user_data_json)
			local data = ffi.cast('shared_game_data_t*', ptr)
			game_data = json.decode(ffi.string(data.game_data))
		end)
	end
	logger.info('gamedata', game_data)
	return game_data
end

-- called from client. debugging purpose
function _M.configure(verb, headers, body) -- (game_data)
	local game_data_json = json.decode(body)[1]
	thread.lock_shared_memory('game_data', function (ptr, gdj)
		local data = ffi.cast('shared_game_data_t*', ptr)
		data.game_data = luact.memory.strdup(json.encode(gdj))
	end, game_data_json)
end
function _M.put_user_data(verb, headers, body) -- (id, user_data)
	local payload = json.decode(body)
	user_datas[payload[1]] = json.encode(payload[2])
	thread.lock_shared_memory('game_data', function (ptr, user_id, user_data_json)
		local data = ffi.cast('shared_game_data_t*', ptr)
		data.user_data:Add(user_id, user_data_json)
	end, ffi.cast('char *', payload[1]), ffi.cast('char *', user_datas[payload[1]]))
end
-- called from rtserver
function _M.gamedata(verb, headers, body) -- ()
	return get_game_data()
end
-- called from client
function _M.open_field(verb, headers, body) -- (size, field_data)
	local payload = json.decode(body)
	local ref = cache.get(url.sched_actor)
	-- emurate calling rtserver REST API
	local resp = ref.POST('/_open', {
		size = payload[1], 
		websv_url = url.websv_actor, 
		field_data_json = json.encode(payload[2]),
	})
	local status, headers, b, blen = resp:raw_payload()
	local tmp = json.decode(ffi.string(b, blen))
	local ok, field_url = unpack(tmp)
	resp:fin()
	if not ok then
		error(field_url)
	end
	return field_url
end
function _M.queue(verb, headers, body) -- (queue_name, queue_settings, user_id)
	local payload = json.decode(body)
	local ref = cache.get(url.queue_actor)
	-- if real web server, it should verify given user_data and id is correct or not here.
	payload[2].websv_url = url.websv_actor
	local resp = ref.POST('/_enter', {
		name = payload[1],
		settings = payload[2],
		user_id = payload[3], 
		user_data_json = get_user_data(payload[3])
	})
	local status, headers, b, blen = resp:raw_payload()
	local tmp = json.decode(ffi.string(b, blen))
	local ok, queue_url = unpack(tmp)
	resp:fin()
	if not ok then
		error(queue_url)
	end
	return queue_url	
end
function _M.otp(verb, headers, body) -- (field_url, user_id)
	local payload = json.decode(body)
	local ref = cache.get(url.sched_actor)
	-- if real web server, it should verify given user_data and id is correct or not here.
	local resp = ref.POST('/_genotp', {
		field_url = payload[1],
		user_id = payload[2], 
		user_data_json = get_user_data(payload[3])
	})
	local status, headers, b, blen = resp:raw_payload()
	local tmp = json.decode(ffi.string(b, blen))
	local ok, otp = unpack(tmp)
	resp:fin()
	if not ok then
		error(otp)
	end
	return otp
end

return _M
