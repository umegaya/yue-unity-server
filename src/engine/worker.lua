local luact = require 'luact.init'
local memory = luact.memory
local util = luact.util
local ffi = require 'ffiex.init'
local url = require 'engine.baseurl'
local json = require 'engine.json'
local cache = require 'engine.cacheref'

-- TODO : this storage will be shift to dht after implementation done.
local user_list_mt = {}
user_list_mt.__index = user_list_mt
function user_list_mt:register(id, queue)
	self[id] = {
		start_at = luact.clock.get(),
		queue = queue,
	}
end
function user_list_mt:unregister(id)
	self[id] = nil
end
function user_list_mt:prepare_login(id, field_url, otp)
	local u = self[id]
	if u then
		u.url = field_url
		u.otp = otp
	end
end
function user_list_mt:error(id, err)
	local u = self[id]
	if u then
		u.err = err
	end
end
local users = setmetatable({}, user_list_mt)
local QUEUE_REGISTER_TIMEOUT = 30 -- 30 sec
luact.tentacle(function ()
	while true do
		local now = luact.clock.get()
		local ids = {}
		for id, data in pairs(users) do
			if now > (data.start_at + QUEUE_REGISTER_TIMEOUT) then
				table.insert(ids, id)
			end
		end
		for i=1,#ids do
			local id = ids[i]
			local u = users[id]
			u.queue:_remove(id)
			users:unregister(id)
		end
		luact.clock.sleep(5.0)
	end
end)

ffi.cdef [[
	typedef struct _queue_worker {
		char *name;
		char *current_field_url;
		int current_field_remain;
		struct queue_setting {
			int n_group_size;
			char *websv_url;
			char *field_data;
		} settings;
		int n_qsize, n_qused;
		struct queue_worker_elem {
			char *user_id;
			char *user_data;
		} *queue;
	} queue_worker_t;
]]

local worker_mt = {}
worker_mt.__threads = {}
worker_mt.__index = worker_mt
-- public methods
function worker_mt:stat(user_id)
	user_id = tostring(user_id)
	local v = users[user_id]
	if not v then 
		-- logger.info('stat nil', user_id)
		return nil
	end
	v.start_at = luact.clock.get()
	if v.otp then
		-- logger.info('stat otp', user_id, v.otp)
		return v.otp, v.url
	elseif v.err then
		-- logger.info('stat err', user_id, v.err)
		error(v.err)
	else
		local idx = self:_user_order(user_id)
		-- logger.info('stat count', user_id, idx, self.settings.n_group_size)
		if idx < self.settings.n_group_size then
			return 0
		else
			return math.floor(idx / self.settings.n_group_size) * self.settings.n_group_size
		end
	end
end

-- internal methods
function worker_mt:_startup(name, settings)
	self.name = memory.strdup(name)
	self.current_field_url = nil
	self.current_field_remain = 0
	self.n_qsize = 1024
	self.n_qused = 0
	self.queue = memory.alloc_typed('struct queue_worker_elem', self.n_qsize)
	if self.queue == nil then
		luact.exception.raise('fatal', 'fail to malloc', self.n_qused * ffi.sizeof('struct queue_worker_elem'))
	end
	self.settings.n_group_size = settings.group_size
	self.settings.websv_url = memory.strdup(settings.websv_url)
	self.settings.field_data = memory.strdup(json.encode(settings.field_data))
	self.__threads[name] = luact.tentacle(function (qw)
		while true do
			qw:_poll()
			luact.clock.sleep(3.0)
		end
	end, self)
end
function worker_mt:_add(id, data)
	id = tostring(id)
	local u = users[id]
	if u then
		exception.raise('invalid', 'already registered in queue', id, ffi.string(u.queue.name))
	end
	if self.current_field_url ~= nil then
		local fref = cache.get(ffi.string(self.current_field_url))
		local ok, r = self:_enter_field(id, data, fref)
		if ok then
			self.current_field_remain = self.current_field_remain - 1
			if self.current_field_remain <= 0 then
				memory.free(self.current_field_url)
				self.current_field_url = nil
			end
		else
			error(r)
		end
		return
	end
	local e = self:_new_elem()
	e.user_id = memory.strdup(id)
	e.user_data = memory.strdup(data)
	users:register(id, self)
	logger.info('user added to queue', ffi.string(self.name), id)
end
function worker_mt:_remove(id)
	local idx = self:_user_order()
	if idx then
		memory.free(self.queue[idx].user_id)
		memory.free(self.queue[idx].user_data)
		memory.move(self.queue + idx, self.queue + idx + 1, self.n_qused - idx - 1)
		self.n_qused = self.n_qused - 1
	end
	logger.info('user removed from queue', ffi.string(self.name), id, idx)
end
function worker_mt:_destroy()
	if self.name ~= nil then
		memory.free(self.name)
	end
	if self.settings.websv_url ~= nil then
		memory.free(self.settings.websv_url)
	end
	if self.settings.field_data ~= nil then
		memory.free(self.settings.field_data)
	end
	if self.queue ~= nil then
		for i=0,self.n_qused-1 do
			memory.free(self.queue[i].user_id)
			memory.free(self.queue[i].user_data)
		end
		memory.free(self.queue)
	end
	memory.free(self)
end
function worker_mt:__actor_destroy__()
	local name = ffi.string(self.name)
	local t = self.__threads[name]
	if t then
		self.__threads[name] = nil
		luact.tentacle.cancel(t)
	end
	self:_destroy()
end
function worker_mt:_new_elem()
	if self.n_qsize <= self.n_qused then
		local tmp = memory.realloc_typed('struct queue_worker_elem', self.queue, self.n_qsize * 2)
		if not tmp then
			exception.raise('fatal', 'fail to realloc', self.n_qsize * 2 * ffi.sizeof('struct queue_worker_elem'))
		end
		self.queue = tmp
	end
	local ret = self.queue[self.n_qused]
	self.n_qused = self.n_qused + 1
	return ret
end
function worker_mt:_poll()
	while self.n_qused >= self.settings.n_group_size do
		self:_start_session()
	end
end
function worker_mt:_start_session()
	local ref = cache.get(url.sched_actor)
	local field_url = ref:_create(self.settings.n_group_size, ffi.string(self.settings.websv_url), ffi.string(self.settings.field_data))
	local enter = 0
	for i=0,self.n_qused-1 do
		local elem = self.queue[i]
		local user_id = ffi.string(elem.user_id)
		if self:_enter_field(user_id, elem.user_data, field_url) then
			enter = enter + 1
			if enter >= self.settings.n_group_size then
				for j=0,i do
					memory.free(self.queue[j].user_id)
					memory.free(self.queue[j].user_data)
				end
				-- i is index, so real shift count should be i + 1
				memory.move(self.queue, self.queue + i + 1, self.n_qused - i - 1)
				self.n_qused = self.n_qused - i - 1
				return
			end
		end
	end
	-- here, it means there is enough candidate to enter, 
	-- but actually enough members are not available because of some of candidate dropped with error, 
	-- then worker turn to immediate enter mode, which immediately enter player which called worker_mt:add
	self.n_qused = 0
	self.current_field_url = memory.strdup(field_url)
	self.current_field_remain = self.settings.n_group_size - enter
end
function worker_mt:_enter_field(user_id, user_data, field_url)
	local fref = cache.get(field_url)
	local ok, otp = pcall(fref._genotp, fref, user_id, ffi.string(user_data))
	if ok then
		-- we assume that its ok if some of enter user actually not start game play.
		-- bot will play for such a player. 
		users:prepare_login(user_id, field_url, otp)
	else
		users:error(user_id, otp)
	end
	return ok, otp
end
function worker_mt:_user_order(user_id)
	for i = 0,self.n_qused - 1 do
		if util.strcmp(self.queue[i].user_id, user_id, #user_id) then
			return i
		end
	end
end

ffi.metatype('queue_worker_t', worker_mt)

