package.path="./src/?.lua;"..package.path
local ffi = require 'engine.ffi'
local array = require 'engine.array'

ffi.cdef [[
typedef struct hoge {
	int a, b, c;
} hoge_t;
]]

local hoge_mt = {}
hoge_mt.__index = hoge_mt
function hoge_mt:__eq(h)
	return h.a == self.a and h.b == self.b and h.c == self.c
end
ffi.metatype('hoge_t', hoge_mt)

local act = array.new('hoge_t')
local a = ffi.new(act)

a:_Init(4)

local h1 = ffi.new('hoge_t', { 1, 2, 3 })
local h2 = ffi.new('hoge_t', { 4, 5, 6 })
local h3 = ffi.new('hoge_t', { 7, 8, 9 })

a:Add(h1)
a:Add(h2)
a:Add(h3)

assert(a:Size() == 3)

assert(a:Get(0) == h1)
assert(a:Get(1) == h2)
assert(a:Get(2) == h3)

local seen = 0
assert(a:Last() == h3)
while seen < 7 do
	local h = a:Random()
	if h == h1 then
		seen = bit.bor(seen, 1)
	elseif h == h2 then
		seen = bit.bor(seen, 2)
	elseif h == h3 then
		seen = bit.bor(seen, 4)
	end
end

local cnt = 1
for h in a:_Iter() do
	if cnt == 1 then
		assert(h == h1)
	elseif cnt == 2 then
		assert(h == h2)
	elseif cnt == 3 then
		assert(h == h3)
	else
		assert(false)
	end
	cnt = cnt + 1
end

a:Remove(h1)
assert(a:Size() == 2)
a:Remove(h3)
assert(a:Size() == 1)
a:Remove(h2)
assert(a:Size() == 0)

return true
