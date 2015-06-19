local ffi = require 'engine.ffi'
local util = require 'engine.util'
local memory = require 'engine.memory'
local _M = {}
local C = ffi.C

local array_ct_map = {}

local array_tmpl = [[
struct {
	int 	_size, _cap;
	$		*_data;
}
]]

local array_mt = {}
array_mt.__index = array_mt
-- private
function array_mt:_Init(size)
	self._cap = size
	self._size = 0
	self._data = C.malloc(self._cap * self._ctsize)
	assert(self._data ~= nil)
end
function array_mt:_EmptySlot()
	self:_Reserve(1)
	self._size = self._size + 1
	return self._data[tonumber(self._size) - 1]
end
function array_mt:_RemoveAt(i)
	C.memmove(self._data + i, self._data + i + 1, self._ctsize * (self._size - i - 1))
	self._size = self._size - 1
end
function array_mt:_Reserve(sz)
	if self._size >= self._cap then
		self._cap = self._cap * 2
		local tmp = C.realloc(self._data, self._cap * self._ctsize)
		if tmp == nil then
			assert(false, "memory allocation error")
		end
		self._data = tmp
	end
end
function array_mt:_Iter()
	return function (d, p)
		p = ffi.cast(ffi.typeof(d._data), p)
		return (d._data + d._size - 1) > p and (p + 1)[0] or nil
	end, self, self._data - 1
end



-- public
function array_mt:Add(e)
	self:_Reserve(1)
	self._data[self._size] = e
	self._size = self._size + 1
end
function array_mt:Remove(e)
	for i=0,self._size - 2 do
		if e == self._data[i] then -- TODO : can use binary search?
			self:_RemoveAt(i)
			return
		end
	end
	if e == self:Last() then
		self._size = self._size - 1
	end
end
function array_mt:Get(i)
	return self._data[tonumber(i)]
end
function array_mt:Size()
	return self._size
end
function array_mt:Clear()
	self._size = 0
end
function array_mt:Last()
	return self._data[tonumber(self._size) - 1]
end
function array_mt:Random()
	local idx = math.random(0, self._size - 1)
	return self._data[idx]
end
array_mt.__IsList__ = true



-- exported methods
function _M.new_pair(ct)
	if type(ct) == 'string' then
		ct = ffi.typeof(ct)
	end
	local array_ct = ffi.typeof(array_tmpl, ct)
	local mt = util.copy_table(array_mt)
	mt.__index = mt
	mt._ctsize = ffi.sizeof(ct)
	return array_ct, mt
end

function _M.new(ct)
	local array_ct, mt
	array_ct = array_ct_map[ct]
	if not array_ct then
		array_ct, mt = _M.new_pair(ct)
		ffi.metatype(array_ct, mt)
	end
	return array_ct
end

return _M
