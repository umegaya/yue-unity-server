local vid, url, game_url, field_data_json, size = ...
local luact = require 'luact.init'
local actor = require 'luact.actor'
local otp = require 'engine.otp'
local json = require 'engine.json'
local field_factory = require 'engine.field_factory'

-- import shared script files
local _M = {}

-- called from web server (REST API)
function _M:_genotp(id, user_data_json)
	return otp.gen(id, user_data_json)
end
function _M:login(pass)
	local user = otp.authorize(pass)
	self.field:login(user.id, luact.peer("/"..user.id), user.data)
end
function _M:_startup(vid, url, game_url, field_data_json, size)
	self.field, self.updater = field_factory.new(url, field_data_json)
	self.field.Vid = vid
	self.field.Size = size
	self.field.UnregistUrl = game_url
end
function _M:SendCommand(id, command)
	if type(command) == 'string' then
		command = json.decode(command)
	end
	self.field.LastCommandRecv = luact.clock.get()
	return self.field:invoke(id, command)
end

_M:_startup(vid, url, game_url, field_data_json, size)

return _M
