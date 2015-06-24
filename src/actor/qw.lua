local name, settings, user_id, user_data_json = ...
local luact = require 'luact.init'
local worker = require 'engine.worker'

local q = luact.memory.alloc_typed('queue_worker_t')
q:_startup(name, settings)
q:_add(user_id, user_data_json)
return q
