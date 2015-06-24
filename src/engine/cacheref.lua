local luact = require 'luact.init'
local _M = {}
function _M.get(url)
	assert(url:match('://'))
	local ref = _M[url]
	if not ref then
		ref = luact.ref(url)
		_M[url] = ref
	end
	return ref
end
function _M.remove(url)
	assert(url:match('://'))
	_M[url] = nil
end
return _M
