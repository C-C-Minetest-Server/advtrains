-------------
-- lua sandboxed environment

local S = atlatc.translate

-- function to cross out functions and userdata.
-- modified from dump()
function atlatc.remove_invalid_data(o, nested)
	if o==nil then return nil end
	local valid_dt={["nil"]=true, boolean=true, number=true, string=true}
	if type(o) ~= "table" then
		--check valid data type
		if not valid_dt[type(o)] then
			return nil
		end
		return o
	end
	-- Contains table -> true/nil of currently nested tables
	nested = nested or {}
	if nested[o] then
		return nil
	end
	nested[o] = true
	for k, v in pairs(o) do
		v = atlatc.remove_invalid_data(v, nested)
	end
	nested[o] = nil
	return o
end


local env_proto={
	load = function(self, envname, data)
		self.name=envname
		self.sdata=data.sdata and atlatc.remove_invalid_data(data.sdata) or {}
		self.fdata={}
		self.init_code=data.init_code or ""
		self.subscribers=data.subscribers or {}
	end,
	save = function(self)
		-- throw any function values out of the sdata table
		self.sdata = atlatc.remove_invalid_data(self.sdata)
		return {sdata = self.sdata, init_code=self.init_code, subscribers=self.subscribers}
	end,
}

--Environment
--Code modified from mesecons_luacontroller (credit goes to Jeija and mesecons contributors)

local safe_globals = {
	"assert", "error", "ipairs", "next", "pairs", "select",
	"tonumber", "tostring", "type", "unpack", "_VERSION"
}

local function safe_date(f, t)
	if not f then
		-- fall back to old behavior
		return(os.date("*t",os.time()))
	else
		--pass parameters
		return os.date(f,t)
	end
end

-- string.rep(str, n) with a high value for n can be used to DoS
-- the server. Therefore, limit max. length of generated string.
local function safe_string_rep(str, n)
	if #str * n > 2000 then
		debug.sethook() -- Clear hook
		error("string.rep: string length overflow", 2)
	end

	return string.rep(str, n)
end

-- string.find with a pattern can be used to DoS the server.
-- Therefore, limit string.find to patternless matching.
-- Note: Disabled security since there are enough security leaks and this would be unneccessary anyway to DoS the server
local function safe_string_find(...)
	--if (select(4, ...)) ~= true then
	--	debug.sethook() -- Clear hook
	--	error("string.find: 'plain' (fourth parameter) must always be true for security reasons.")
	--end

	return string.find(...)
end

local mp=minetest.get_modpath("advtrains_luaautomation")

local static_env = {
	--core LUA functions
	string = {
		byte = string.byte,
		char = string.char,
		format = string.format,
		len = string.len,
		lower = string.lower,
		upper = string.upper,
		rep = safe_string_rep,
		reverse = string.reverse,
		sub = string.sub,
		find = safe_string_find,
	},
	math = {
		abs = math.abs,
		acos = math.acos,
		asin = math.asin,
		atan = math.atan,
		atan2 = math.atan2,
		ceil = math.ceil,
		cos = math.cos,
		cosh = math.cosh,
		deg = math.deg,
		exp = math.exp,
		floor = math.floor,
		fmod = math.fmod,
		frexp = math.frexp,
		huge = math.huge,
		ldexp = math.ldexp,
		log = math.log,
		log10 = math.log10,
		max = math.max,
		min = math.min,
		modf = math.modf,
		pi = math.pi,
		pow = math.pow,
		rad = math.rad,
		random = math.random,
		sin = math.sin,
		sinh = math.sinh,
		sqrt = math.sqrt,
		tan = math.tan,
		tanh = math.tanh,
	},
	table = {
		concat = table.concat,
		insert = table.insert,
		maxn = table.maxn,
		remove = table.remove,
		sort = table.sort,
	},
	os = {
		clock = os.clock,
		difftime = os.difftime,
		time = os.time,
		date = safe_date,
	},
	POS = function(x,y,z) return {x=x, y=y, z=z} end,
	getstate = advtrains.getstate,
	setstate = advtrains.setstate,
	is_passive = advtrains.is_passive,
	--interrupts are handled per node, position unknown. (same goes for digilines)
	--however external interrupts can be set here.
	interrupt_pos = function(parpos, imesg)
		local pos=atlatc.pcnaming.resolve_pos(parpos, "interrupt_pos")
		atlatc.interrupt.add(0, pos, {type="ext_int", ext_int=true, message=imesg})
	end,
	train_parts = function(train_id)
		if not train_id then return false end
		local train = advtrains.trains[train_id]
		if not train then return false end
		return table.copy(train.trainparts or {})
	end,
	get_wagon_train_id = function(wagon_id)
		local wagon = advtrains.wagons[wagon_id]
		return wagon and wagon.train_id or false
	end,
	-- sends an atc command to train regardless of where it is in the world
	atc_send_to_train = function(train_id, command)
		assertt(command, "string")
		local train = advtrains.trains[train_id]
		if train then
			advtrains.atc.train_set_command(train, command, true)
			return true
		else
			return false
		end
	end,
	get_slowdown = function()
		return advtrains.global_slowdown
	end
}

-- If interlocking is present, enable route setting functions
if advtrains.interlocking then
	local function gen_checks(signal, route_name, noroutesearch)
		assertt(route_name, "string")
		local pos = atlatc.pcnaming.resolve_pos(signal)
		local sigd = advtrains.interlocking.db.get_sigd_for_signal(pos)
		if not sigd then
			error("There's no signal at "..minetest.pos_to_string(pos))
		end
		local tcbs = advtrains.interlocking.db.get_tcbs(sigd)
		if not tcbs then
			error("Inconsistent configuration, no tcbs for signal at "..minetest.pos_to_string(pos))
		end
		
		local routeid, route
		if not noroutesearch then
			for routeidt, routet in ipairs(tcbs.routes) do
				if routet.name == route_name then
					routeid = routeidt
					route = routet
					break
				end
			end
			if not route then
				error("No route called "..route_name.." at "..minetest.pos_to_string(pos))
			end
		end
		return pos, sigd, tcbs, routeid, route
	end


	static_env.can_set_route = function(signal, route_name)
		local pos, sigd, tcbs, routeid, route = gen_checks(signal, route_name)
		-- if route is already set on signal, return whether it's committed
		if tcbs.routeset == routeid then
			return tcbs.route_committed
		end
		-- actually try setting route (parameter 'true' designates try-run
		local ok = advtrains.interlocking.route.set_route(sigd, route, true)
		return ok
	end
	static_env.set_route = function(signal, route_name)
		local pos, sigd, tcbs, routeid, route = gen_checks(signal, route_name)
		return advtrains.interlocking.route.update_route(sigd, tcbs, routeid, nil, S("LuaATC component"))
	end
	static_env.cancel_route = function(signal)
		local pos, sigd, tcbs, routeid, route = gen_checks(signal, "", true)
		return advtrains.interlocking.route.update_route(sigd, tcbs, nil, true)
	end
	static_env.get_aspect = function(signal)
		local pos = atlatc.pcnaming.resolve_pos(signal)
		return advtrains.interlocking.signal.get_aspect_info(pos)
	end
	static_env.set_aspect = function(signal, main_asp, rem_signal)
		if type(main_asp) == "table" then
			error("set_aspect: Parameters of this method have changed to (signal, main_asp, rem_signal) with introduction of distant signalling: parameter 2 is now the main aspect name (a string)")
		end
		local pos = atlatc.pcnaming.resolve_pos(signal)
		local rem_pos = rem_signal and atlatc.pcnaming.resolve_pos(rem_signal)
		return advtrains.interlocking.signal_set_aspect(pos, main_asp, rem_pos)
	end
	
	--section_occupancy()
	static_env.section_occupancy = function(ts_id)
		if not ts_id then return nil end
		ts_id = tostring(ts_id)
		local response = advtrains.interlocking.db.get_ts(ts_id)
		if not response then return false end
		return (response.trains and table.copy(response.trains)) or {}
	end
end

-- Lines-specific:
if advtrains.lines then
	local atlrwt = advtrains.lines.rwt
	static_env.rwt = {
		now = atlrwt.now,
		new_t = atlrwt.new_t,
		new_i = atlrwt.new_i,
		to_table = atlrwt.to_table,
		t_sec = atlrwt.t_sec,
		i_sec = atlrwt.i_sec,
		to_secs = atlrwt.to_secs, -- deprecated
		t_str = atlrwt.t_str,
		i_str = atlrwt.i_str,
		to_string = atlrwt.to_string, -- deprecated
		add = atlrwt.add,
		diff = atlrwt.diff,
		sub = atlrwt.sub,
		
		is_after = atlrwt.is_after,
		is_before = atlrwt.is_before,
		
		next_rpt = atlrwt.next_rpt,
		last_rpt = atlrwt.last_rpt,
		time_from_last_rpt = atlrwt.time_from_last_rpt,
		time_to_next_rpt = atlrwt.time_to_next_rpt,
	}
end


atlatc.register_function = function (name, f)
	static_env[name] = f
end

for _, name in pairs(safe_globals) do
	static_env[name] = _G[name]
end

local noop = function() end
local err_ZoneBeginS = function()
	error("Call stacks collection is not allowed in LuaATC environment.", 2)
end

--The environment all code calls get is a table that has set static_env as metatable.
--In general, every variable is local to a single code chunk, but kept persistent over code re-runs. Data is also saved, but functions and userdata and circular references are removed
--Init code and step code's environments are not saved
-- S - Table that can contain any save data global to the environment. Will be saved statically. Can't contain functions or userdata or circular references.
-- F - Table global to the environment, can contain volatile data that is deleted when server quits.
--     The init code should populate this table with functions and other definitions.

local proxy_env={}
--proxy_env gets a new metatable in every run, but is the shared environment of all functions ever defined.

-- returns: true, fenv if successful; nil, error if error 
function env_proto:execute_code(localenv, code, evtdata, customfct)
	-- create us a print function specific for this environment
	if not self.safe_print_func then
		local myenv = self
		self.safe_print_func = function(...)
			myenv:log("info", ...)
		end
	end

	-- Prepare Tracy for the code
	local tracy_enabled = atlatc.enable_tracy and _G.tracy
	local tracy_func = {}
	local tracy_zone_count = 0

	-- Do not allow call stacks tracing
	-- Per my understanding to the Tracy API, it seems to allow leaking info
	-- outside of the LuaATC env, and is also costy.
	-- Even if tracy is disabled, still return error for consistency.
	tracy_func.ZoneBeginS = err_ZoneBeginS
	tracy_func.ZoneBeginNS = err_ZoneBeginS

	if tracy_enabled then
		tracy_func.ZoneBegin = function()
			-- For better traceability, we don't allow unnamed zones.
			tracy_zone_count = tracy_zone_count + 1
			return _G.tracy.ZoneBeginN("LuaATC::" .. self.name .. "::unnamed_" .. tracy_zone_count .. "_" .. core.get_us_time())
		end

		tracy_func.ZoneBeginN = function(name)
			assertt(name, "string")
			tracy_zone_count = tracy_zone_count + 1
			return _G.tracy.ZoneBeginN("LuaATC::" .. self.name .. "::" .. name)
		end

		tracy_func.ZoneText = function(text)
			assertt(text, "string")
			if tracy_zone_count == 0 then
				error("Attempt to set Tracy ZoneText without an active zone", 2)
			end
			return _G.tracy.ZoneText("LuaATC::" .. self.name .. "::" .. text)
		end

		tracy_func.Message = function(text)
			assertt(text, "string")
			return _G.tracy.Message("LuaATC::" .. self.name .. "::" .. text)
		end

		tracy_func.ZoneName = function(text)
			assertt(text, "string")
			if tracy_zone_count == 0 then
				error("Attempt to set Tracy ZoneName without an active zone", 2)
			end
			return _G.tracy.ZoneName("LuaATC::" .. self.name .. "::" .. text)
		end

		tracy_func.ZoneEnd = function()
			if tracy_zone_count > 0 then
				tracy_zone_count = tracy_zone_count - 1
				return _G.tracy.ZoneEnd()
			end
			error("Mismatched Tracy ZoneEnd call", 2)
		end
	else
		-- If tracy is not enabled, these functions do nothing.
		-- Note that there are still some overheads; developers should manually 
		-- remove tracy calls before deployment.
		tracy_func.ZoneBegin = noop
		tracy_func.ZoneBeginN = noop
		tracy_func.ZoneText = noop
		tracy_func.Message = noop
		tracy_func.ZoneName = noop
		tracy_func.ZoneEnd = noop
	end

	setmetatable(tracy_func, {
		__newindex = function(t, i, v)
			error("Trying to overwrite tracy environment contents")
		end,
	})
	
	local metatbl ={
		__index = function(t, i)
			if i=="S" then
				return self.sdata
			elseif i=="F" then
				return self.fdata
			elseif i=="event" then
				return evtdata
			elseif customfct and customfct[i] then
				return customfct[i]
			elseif localenv and localenv[i] then
				return localenv[i]
			elseif i=="print" then
				return self.safe_print_func
			elseif i=="tracy" then
				return tracy_func
			end
			return static_env[i]
		end,
		__newindex = function(t, i, v)
			if i=="S" or i=="F" or i=="event" or (customfct and customfct[i]) or static_env[i] then
				debug.sethook()
				error("Trying to overwrite environment contents")
			end
			localenv[i]=v
		end,
	}
	setmetatable(proxy_env, metatbl)
	if type(code) == "string" then
		local fun, err=loadstring(code)
		if not fun then
			return false, err
		end
		code = fun
	elseif type(code) ~= "function" then
		return false, "Code must be a string or a function"
	end
	
	setfenv(code, proxy_env)
	local succ, data = pcall(code)
	if succ then
		data=localenv
	end

	-- Clean up any tracy zones that were not properly ended
	if tracy_zone_count > 0 then
		-- Don't blame the code if we ended due to an error, otherwise warn it
		if succ then
			self:log("warning", "Code ended with "..tracy_zone_count.." unclosed Tracy zones.")
		end

		for i = 1, tracy_zone_count do
			_G.tracy.ZoneEnd()
		end
	end

	return succ, data
end

function env_proto:run_initcode()
	if self.init_code and self.init_code~="" then
		local old_fdata=self.fdata
		self.fdata = {}
		local old_globalsteps = self.globalsteps
		self.globalsteps = {}

		local customfct = {}
		customfct.register_globalstep = function(func)
			assertt(func, "function")
			self.globalsteps[#self.globalsteps+1] = { func = func, dtime = 0 }
		end

		--atprint("[atlatc]Running initialization code for environment '"..self.name.."'")
		local succ, err = self:execute_code(customfct, self.init_code, {type="init", init=true})
		if not succ then
			self:log("error", "Executing InitCode for '"..self.name.."' failed:"..err)
			self.init_err=err
			if old_fdata then
				self.fdata=old_fdata
				self.globalsteps=old_globalsteps
				self:log("warning", "The 'F' table has been restored to the previous state.")
			end
			if old_globalsteps then
				self.globalsteps=old_globalsteps
				self:log("warning", "The list of globalsteps has been restored to the previous state.")
			end
		end
	end
end

-- log to environment subscribers. severity can be "error", "warning" or "info" (used by internal print)
function env_proto:log(severity, ...)
	local text=advtrains.print_concat_table({"[atlatc "..self.name.." "..severity.."]", ...})
	minetest.log("action", text)
	for _, pname in ipairs(self.subscribers) do
		minetest.chat_send_player(pname, text)
	end
end

-- env.subscribers table may be directly altered by callers.


--- class interface

function atlatc.env_new(name)
	local newenv={
		name=name,
		init_code="",
		sdata={},
		subscribers={},
		globalsteps={},
	}
	setmetatable(newenv, {__index=env_proto})
	return newenv
end
function atlatc.env_load(name, data)
	local newenv={}
	setmetatable(newenv, {__index=env_proto})
	newenv:load(name, data)
	return newenv
end

function atlatc.run_initcode()
	for envname, env in pairs(atlatc.envs) do
		env:run_initcode()
	end
end

function atlatc.run_env_globalsteps(dtime)
	local now = core.get_us_time()
	for envname, env in pairs(atlatc.envs) do
		if env.globalsteps then
			for _, func_data in ipairs(env.globalsteps) do
				func_data.dtime = func_data.dtime + dtime
				if not func_data.pause_until or func_data.pause_until <= now then
					func_data.pause_until = nil

					local func_dtime = func_data.dtime
					func_data.dtime = 0

					local func = func_data.func
					local new_func = function()
						return func(func_dtime)
					end

					local customfct = {
						step_pause_until = function(us_time)
							assertt(us_time, "number")
							func_data.pause_until = us_time
						end,
						step_pause_for = function(delay)
							assertt(delay, "number")
							func_data.pause_until = core.get_us_time() + delay * 1000000
						end,
					}

					local evt = {
						type = "globalstep",
						globalstep = true,
						dtime = func_dtime,
						us_time = now,
					}

					local succ, err = env:execute_code(customfct, new_func, evt)
					if not succ then
						env:log("error", "LuaATC globalstep error: LUA Error:", err)

						-- Slow it down so that errors won't overwhelm the server
						-- However, respect the script's pause time if it requested more
						func_data.pause_until = math.max(func_data.pause_until or 0, now + 2000000)
					end
				end
			end
		end
	end
end




