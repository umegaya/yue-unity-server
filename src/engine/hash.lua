local ffi = require 'engine.ffi'
local util = require 'engine.util'
local refl = require 'engine.reflect'
local memory = require 'engine.memory'
local array = require 'engine.array'
local C = ffi.C
local _M = {}
local hash_ct_map = {}

ffi.cdef [[
	size_t strnlen(const char *s, size_t maxlen);
]]


-- hash calculator for various type
local hasher_map = {}
local seed = 1023 -- TODO : choose good seed
local function murmur3(p, len)
	local c1 = 0xcc9e2d51
	local c2 = 0x1b873593
	local r1 = 15
	local r2 = 13
	local m = 5
	local n = 0xe6546b64
 
	local hash = ffi.new('uint32_t', seed)
 
	local nblocks = bit.rshift(len, 2)
	local blocks = ffi.cast('const uint32_t *', p)
	local i
	for i=0,tonumber(nblocks)-1 do
		local k = blocks[i]
		k = k * c1;
		k = bit.rol(k, r1)
		k = k * c2;
 
		hash = bit.bxor(hash, k)
		hash = bit.rol(hash, r2)
	end
 
	local tail = ffi.cast('const uint8_t *', p) + (nblocks * 4)
	local k1 = 0;
 
 	local tmp = bit.band(len, 3)
 	if tmp >= 3 then
		-- k1 ^= tail[2] << 16;
 		k1 = bit.bxor(k1, bit.lshift(tail[2], 16))
 	end
 	if tmp >= 2 then
 		-- k1 ^= tail[1] << 8;
 		k1 = bit.bxor(k1, bit.lshift(tail[1], 8))
 	end
 	if tmp >= 1 then
 		k1 = bit.bxor(k1, tail[0])
		k1 = k1 * c1 
		k1 = bit.rol(k1, r1)
		k1 = k1 * c2
		hash = bit.bxor(hash, k1)
	end
 
	hash = bit.bxor(hash, len)
	hash = bit.bxor(hash, bit.rshift(hash, 16))
	hash = hash * 0x85ebca6b
	hash = bit.bxor(hash, bit.rshift(hash, 13))
	hash = hash * 0xc2b2ae35
	hash = bit.bxor(hash, bit.rshift(hash, 16))
 
	return hash
end
local hash_func = murmur3
-- numeric, struct/union
local scalar_hasher_tmpl = [[
	union {
		$ key;
		uint8_t p[0];
	}
]]
local scalar_hasher_mt = {}
scalar_hasher_mt.__index = scalar_hasher_mt
function scalar_hasher_mt:hash(k)
	self.key = k
	return hash_func(self.p, ffi.sizeof(self))
end
-- ptr, ref
local ptr_hasher_tmpl = [[
	union {
		$ key;
	}
]]
local ptr_hasher_mt = {}
ptr_hasher_mt.__index = ptr_hasher_mt
function ptr_hasher_mt:hash(k)
	return hash_func(ffi.cast('uint8_t *', k), ffi.sizeof(self))
end
-- string
ffi.cdef [[
	typedef struct {
		char *ptr;
	} __str_hasher;
]]
local str_hasher_mt = {}
str_hasher_mt.__index = str_hasher_mt
function str_hasher_mt:hash(k)
	return hash_func(k, C.strnlen(k, 1024))
end
ffi.metatype('__str_hasher', str_hasher_mt)
local str_hasher = ffi.new('__str_hasher')


-- data pair
local pair_tmpl = [[
	struct {
		$ key;
		$ value;
	}
]]


-- hash container
local hash_tmpl = [[
	struct {
		int _size, _count;
		$ *_data;
	}
]]

local hash_mt = {}
hash_mt.__index = hash_mt
function hash_mt:_Init(size)
	self._size = size
	local bsz = size * ffi.sizeof(self._pair_array_ct)
	self._data = C.malloc(bsz)
	ffi.fill(self._data, bsz)
	assert(self._data ~= nil)
end
function hash_mt:_Iter()
	assert(false)
end



function hash_mt:Add(k, v)
	local idx = tonumber(self._hasher:hash(k) % self._size)
	local bucket = self._data[idx]
	if bucket._cap <= 0 then
		bucket:_Init(4)
	end
	local e = bucket:_EmptySlot()
	e.key, e.value = k, v
	self._count = self._count + 1
end
function hash_mt:Remove(k)
	local idx = tonumber(self._hasher:hash(k) % self._size)
	local bucket = self._data[idx]
	for i=0,bucket._size do
		local e = bucket:Get(i)
		if e.key == k then
			bucket:_RemoveAt(i)
			self._count = self._count - 1
			return true
		end
	end
end
function hash_mt:Get(k)
	local idx = self._hasher:hash(k) % self._size
	local bucket = self._data[idx]
	for i=0,bucket._size do
		local e = bucket:Get(i)
		if e.key == k then
			return e.value
		end
	end
end
function hash_mt:Clear()
	for i=0,self._size do
		self._data[i]:Clear()
	end
end

function hash_mt:Size()
	return self._count
end

hash_mt.__IsDict__ = true


function _M.new_pair(kct, vct)
	if type(kct) == 'string' then
		kct = ffi.typeof(kct)
	end
	if type(vct) == 'string' then
		vct = ffi.typeof(vct)
	end
	local pct = ffi.typeof(pair_tmpl, kct, vct)
	local act = array.new(pct)
	local hash_ct = ffi.typeof(hash_tmpl, act)
	local mt = util.copy_table(hash_mt)
	mt.__index = mt
	mt._ctsize = ffi.sizeof(pct)
	mt._pair_array_ct = act
	local r = refl.typeof(kct)
	local hasher = hasher_map[kct]
	if not hasher then
		if r.what == 'ptr' or r.what == 'ref' then
			if ffi.typeof(kct) == ffi.typeof('const char *') or ffi.typeof(kct) == ffi.typeof('char *') then
				hasher = str_hasher
			else
				local et = r.element_type
				local krefct
				if et.name then -- struct/union
					krefct = ffi.typeof(et.what.." "..et.name)
				else -- primitive type
					krefct = ffi.typeof('char['..et.size..']')
				end
				local hct = ffi.typeof(ptr_hasher_tmpl, krefct)
				ffi.metatype(hct, ptr_hasher_mt)
				hasher = ffi.new(hct)
			end
		elseif r.what == 'int' or r.what == 'float' or r.what == 'struct' or r.what == 'union' then
			local hct = ffi.typeof(scalar_hasher_tmpl, kct)
			ffi.metatype(hct, scalar_hasher_mt)
			hasher = ffi.new(hct)
			if r.what == 'int' or r.what == 'float' then
				-- also can apply to number 
				function mt:Add(k, v)
					if type(k) == 'number' then
						k = ffi.new(self._keyct, k)
					end
					return hash_mt.Add(self, k, v)
				end
			end
		end
		hasher_map[kct] = hasher
	end
	mt._valct = vct
	mt._keyct = kct
	mt._hasher = hasher
	return hash_ct, mt
end	

function _M.new(kct, vct)
	local hash_ct, mt
	local tmp = hash_ct_map[kct]
	if not tmp then
		tmp = {}
		hash_ct_map[kct] = tmp
	end
	hash_ct = tmp[vct]
	if not hash_ct then
		hash_ct, mt = _M.new_pair(kct, vct)
		ffi.metatype(hash_ct, mt)
		tmp[vct] = hash_ct
	end
	return hash_ct
end

return _M
