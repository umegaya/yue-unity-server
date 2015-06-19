-- emurate simple web server which communicate with rtserver
local ffi = require 'ffiex.init'
local json = require 'engine.json'
local url = require 'engine.baseurl'

-- share variable in this actor
local game_data
local user_datas = {}
local refs = {}

-- helper
local function sched_ref()
	local sched_url = url.sched.."/srv"
	local ref = refs[sched_url]
	if not ref then
		ref = luact.ref(sched_url)
		refs[sched_url] = ref
	end
	return ref
end

-- interfaces
return {
	-- called from client. debugging purpose
	configure = function (verb, headers, body) -- (game_data)
		game_data = json.decode(body)[1]
	end,
	put_user_data = function (verb, headers, body) -- (id, user_data)
		local payload = json.decode(body)
		user_datas[payload[1]] = payload[2]
	end,
	-- called from rtserver
	gamedata = function (verb, headers, body) -- ()
		return game_data
	end,
	-- called from client
	open_field = function (verb, headers, body) -- (data)
		local payload = json.decode(body)
		local sched_url = url.sched.."/srv"
		local ref = sched_ref()
		-- emurate calling rtserver REST API
		local resp = ref.POST('/_open', {
			websv_url = url.websv.."/wsv",
			field_data_json = json.encode(payload[1]),
		})
		local status, headers, b, blen = resp:raw_payload()
		local tmp = json.decode(ffi.string(b, blen))
		local ok, field_url = unpack(tmp)
		resp:fin()
		if not ok then
			error(field_url)
		end
		return field_url
	end,
	otp = function (verb, headers, body) -- (field_url, id)
		local payload = json.decode(body)
		local ref = sched_ref()
		-- if real web server, it should verify given user_data and id is correct or not here.
		local resp = ref.POST('/_genotp', {
			field_url = payload[1],
			user_id = payload[2], 
			user_data_json = json.encode(user_datas[payload[2]])
		})
		local status, headers, b, blen = resp:raw_payload()
		local tmp = json.decode(ffi.string(b, blen))
		local ok, otp = unpack(tmp)
		resp:fin()
		if not ok then
			error(otp)
		end
		return otp
	end,
}
