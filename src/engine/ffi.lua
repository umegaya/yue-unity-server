local ok, ffi = pcall(require, 'ffiex.init')
if not ok then
	ok, ffi = pcall(require, 'ffi')
	if not ok then
		error('cannot load ffi module')
	end
end
return ffi
