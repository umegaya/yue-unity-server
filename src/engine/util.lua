local ok, _M = pcall(require, 'pulpo.util')
if not ok then
	_M = {}
	function _M.copy_table(t, deep)
		local r = {}
		for k,v in pairs(t) do
			r[k] = (deep and type(v) == 'table') and _M.copy_table(v) or v
		end
		return r
	end
end

return _M
