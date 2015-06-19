package.path="./src/?.lua;"..package.path
local ffi = require 'engine.ffi'
local hash = require 'engine.hash'
local memory = require 'engine.memory'
local C = ffi.C

ffi.cdef [[
typedef struct hoge {
	int a, b, c;
} hoge_t;
typedef struct fuga {
	int x;
} fuga_t;
]]

local hoge_mt = {}
hoge_mt.__index = hoge_mt
function hoge_mt:__eq(h)
	return h.a == self.a and h.b == self.b and h.c == self.c
end
ffi.metatype('hoge_t', hoge_mt)

local fuga_mt = {}
fuga_mt.__index = fuga_mt
function fuga_mt:__eq(h)
	return h.x == self.x
end
ffi.metatype('fuga_t', fuga_mt)


local ITER = 100
local fixture = {}
for i=1,ITER do
	local h = ffi.new('hoge_t', i * 10, i * 10 + 1, i * 10 + 2)
	table.insert(fixture, h)
end


local hcts = {
	{ 
		hct = hash.new('char *', 'hoge_t'), 
		keygen = function ()  
			local len = math.random(1, 63)
			local p = ffi.new('char[?]', len + 1)
			local texts = "abcdefghijklmnopqrstuvwxyz"
			for i=0,len do
				p[i] = texts:byte(math.random(1, #texts))
			end
			p[len] = 0
			return p
		end, 
	},
	{ 
		hct = hash.new('uint32_t', 'hoge_t'), 
		keygen = function () return math.random(1, 1000000) end, 
	},
	{ 
		hct = hash.new('int *', 'hoge_t'), 
		keygen = function ()
			local p = ffi.new('int[1]') 
			p[0] = math.random(1, 1000000)
			return p
		end, 
	},
	{ 
		hct = hash.new('fuga_t', 'hoge_t'), 
		keygen = function () 
			local p = ffi.new('fuga_t')
			p.x = math.random(1, 10000000)
			return p
		end, 
	},
}

local function test_hct(hs, kgen)
	print('test start with', hs)
	local keys = {}
	for i=1,ITER do
		local k = kgen()
		table.insert(keys, k)
		hs:Add(k, fixture[i])
	end
	assert(hs:Size() == ITER)
	for i=1,ITER do
		local e = hs:Get(keys[i])
		assert(e)
		assert(e == fixture[i])
	end
	for i=1,ITER do
		assert(hs:Remove(keys[i]))
		assert(hs:Size() == ITER - i)
	end
	print('test end with', hs)
end

for _, set in ipairs(hcts) do
	local hs = ffi.new(set.hct)
	hs:_Init(64)
	test_hct(hs, set.keygen)
end

return true
