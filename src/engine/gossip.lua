local luact = require 'luact.init'
local gossip = require 'luact.cluster.gossip'

-- module table
local _M = {}

-- cdef 
ffi.cdef [[
	typedef struct _gossip_delegate {
		int load_score;
		luact_uuid_t actor;
	} gossip_delegate_t;
]]

local gossip_delegate_mt = {}
gossip_delegate_mt.__index = gossip_delegate_mt
function gossip_delegate_mt:initialize(actor)
	self.load_score = 0
	self.actor = actor
end
function gossip_delegate_mt:user_state()
	return ffi.cast('char *', self), ffi.sizeof('gossip_delegate_t')
end
function gossip_delegate_mt:memberlist_event(tp, ...)
	logger.info('mlist event', tp, ...)
end
ffi.metatype('gossip_delegate_t', gossip_delegate_mt)
gossip_delegate_t = ffi.typeof('gossip_delegate_t')


_M.GOSSIP_PORT = 8080
_M.SCORE_PER_THREAD = 1000
function _M.initialize(actor)
	if not _M.gossiper then
		_M.gossiper = luact.root_actor.gossiper(_M.GOSSIP_PORT, {
			delegate = function (a)
				local luact = require 'luact.init'
				local p = luact.memory.alloc_typed('gossip_delegate_t')
				p:initialize(a)
				return p
			end,
			delegate_args = {actor},
		})
		assert(_M.gossiper:wait_bootstrap(5))
	end
end
function _M.modify_self_state(modifier, ...)
	local d = gossip.delegate(_M.GOSSIP_PORT)
	if modifier(d, ...) then
		_M.gossiper:broadcast_user_state()
	end
end
function _M.add_load_score(score)
	_M.modify_self_state(function (st, sc)
		st.load_score = st.load_score + sc
		if st.load_score < 0 then
			st.load_score = 0
		end
		return true
	end, score)
end
function _M.find_best_server()
	local least, least_node = _M.SCORE_PER_THREAD
	local nodelist = gossip.nodelist(_M.GOSSIP_PORT)
	for i=1,#nodelist do
		local n = nodelist[i]:user_state_as(gossip_delegate_t)
		if n.load_score < least then
			least = n.load_score
			least_node = n
		end
	end
	return least_node
end
-- both returns percentile of maximum capacity
function _M.load_percentile()
	local nodelist = gossip.nodelist(_M.GOSSIP_PORT)
	local max = #nodelist * _M.SCORE_PER_THREAD
	local used = 0
	for i=1,#nodelist do
		local n = nodelist[i]:user_state_as(gossip_delegate_t)
		used = used + n.load_score
	end
	return used / max 
end

return _M
