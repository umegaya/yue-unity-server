local json = require 'common.dkjson'
local class = require 'common.class'

local _M = {}

_M.encode = json.encode
function _M.decode(jsonstr)
	-- scplog('decode_json start', jsonstr)
	return json.decode(jsonstr, 1, nil, class.dict_mt, class.list_mt)
end

return _M
