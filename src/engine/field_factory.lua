local luact = require 'luact.init'
local util = luact.util
local json = require 'engine.json'

local _M = {}
local initialized = false

function _M.new(url, field_data_json)
	local ok, ref = pcall(luact.ref, url)
	if not ok then
		logger.report('error', ref)
		error(ref)
	end
	local field_data, ok, r, field, updater
	if not initialized then
		local ret = ref.GET('/gamedata')
		local status, headers, body, blen = ret:raw_payload()
		local tmp = json.decode(ffi.string(body, blen))
		ok, r = unpack(tmp)
		if not ok then
			ret:fin()
			goto finish
		end
		ok, r = pcall(class.init_fix_data, r)
		if not ok then
			ret:fin()
			goto finish
		end
		ret:fin()
		initialized = true
	else
		-- TODO : if server need to be running longtime, data need to be updated somehow.
		-- but it causes difficult problem when there is the actor which refers old data.
		-- it may better to shutdown server which has old data and restart with new data.
	end
	field_data = json.decode(field_data_json)
	field = class.new("FieldBase", "fields/server_field.lua")
	ok, r = pcall(field.initialize, field, field_data)
	if not ok then
		goto finish
	end
	-- 	100 ms tick
	updater = luact.tentacle(function (f, last_update)
		while not f.Finished do
			local now = luact.clock.get()
			f:update(now - last_update)
			last_update = now
			luact.clock.sleep(0.1)
		end
	end, field, luact.clock.get())
::finish::
	if not ok then
		logger.report(r)
		error(r)
	end
	return field, updater
end

return _M