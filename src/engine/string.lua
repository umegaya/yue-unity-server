local ffi = require 'engine.ffi'
local util = require 'engine.util'
local memory = require 'engine.memory'
local C = ffi.C
local _str = _G.string

ffi.cdef [[
	typedef struct _pulpo_string {
		char p[0];
	} pulpo_string_t;
]]

local function new_string(len)
	local p = memory.alloc(len+1)
	ffi.cast('char *', p)[len] = 0
	return ffi.cast('pulpo_string_t *', p)
end
local function to_string(str)
	local s = new_string(#str)
	ffi.copy(s.p, str)
	return s
end

local string_mt = {}
string_mt.__index = string_mt
function string_mt.new(str)
	return to_string(str)
end
function string_mt:__concat(str)
	local l1, l2 = #self, #str
	local p = new_string(self, l1 + l2)
	if not p then
		assert(false, "memory allocation")
	end
	if type(str) == 'cdata' then
		ffi.copy(p.p + l1, str.p, l2)
		p.p[l1 + l2] = 0
	elseif type(str) == 'string' then
		ffi.copy(p.p + l1, str)
	end		
	return p
end
function string_mt:__tostring()
	return ffi.string(self.p)
end
function string_mt:__len()
	return self:len()
end
function string_mt:byte(i)
	return self.p[i-1]
end
function string_mt.char(...)
	local len = select('#', ...)
	local buf = {...}
	local s = new_string(len)
	for i=0,len-1 do
		s.p[i] = buf[i+1]
	end
	return s
end
function string_mt:find(pattern, init, plain)
	return _str.find(self.p, pattern, init, plain)
end
function string_mt:format(...)
	return _str.format(self.p, ...)
end
function string_mt:gmatch(pattern)
	return _str.gmatch(self.p, pattern)
end
function string_mt:match(pattern, init)
	return _str.gmatch(self.p, pattern, init)
end
function string_mt:gsub(pattern, repl, n)
	return _str.gsub(self.p, pattern, repl, n)
end
function string_mt:len()
	return _str.len(self.p)
end
function string_mt:lower()
	return _str.lower(self.p)
end
function string_mt:upper()
	return _str.upper(self.p)
end
function string_mt:rep(n)
	return _str.rep(self.p, n)
end
function string_mt:reverse()
	return _str.reverse(self.p)
end
function string_mt:sub(i, j)
	return _str.sub(self.p, i, j)
end
ffi.metatype('pulpo_string_t', string_mt)

return string_mt




