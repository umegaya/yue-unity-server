local json = require 'engine.json'
local luact = require 'luact.init'
local url = require 'engine.baseurl'
local field_list = {}
local refs = {}
return {
	-- debug
	echo = function (self, v)
		return v
	end,
	close_me = function (self)
		luact.close_peer()
	end,
	ping = function (verb, headers, payload)
		return 'pong+v4'
	end,
	-- belows are protected from external access
	_close = function (self, field_url)
		for i=1,#field_list do
			if field_list[i] == field_url then
				table.remove(field_list, i)
				refs[field_url] = nil
				break
			end
		end
	end,
	-- this will be called from web server.
	_open = function (verb, headers, body)
		if #field_list > 0 then
			return field_list[1]
		end
		local field_name
		local sec = math.floor(luact.clock.get())
		local ok, r
		while true do
			field_name = "/gf/"..tonumber(sec).."_"..math.random(1, 1000000) -- time + random seed
			ok, r = pcall(luact.register, field_name, 'src/actor/gf.lua')
			if ok then
				break
			end
		end
		local payload = json.decode(body)
		local caller_websv_url, field_data_json = payload.websv_url, payload.field_data_json
		local field_url = url.game:gsub('0.0.0.0', luact.opts.env.external_address)..field_name
		r:_startup(field_url, caller_websv_url, url.sched..'/srv', field_data_json)
		table.insert(field_list, field_url)
		return field_url
	end,
	_genotp = function (verb, headers, body)
		local payload = json.decode(body)
		local field_url, user_id, user_data_json = payload.field_url, payload.user_id, payload.user_data_json
		local ref = refs[field_url]
		if not ref then
			ref = luact.ref(field_url)
			refs[field_url] = ref
		end
		return ref:_genotp(user_id, user_data_json)
	end,
}
