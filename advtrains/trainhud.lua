--trainhud.lua: holds all the code for train controlling

-- Get current translator
local S = advtrains.translate

local T = advtrains.texture

advtrains.hud = {}
advtrains.hhud = {}

minetest.register_on_leaveplayer(function(player)
advtrains.hud[player:get_player_name()] = nil
advtrains.hhud[player:get_player_name()] = nil
end)

local hud_type_key = minetest.features.hud_def_type_field and "type" or "hud_elem_type"

local mletter={[1]="F", [-1]="R", [0]="N"}

function advtrains.on_control_change(pc, train, flip)
   	local maxspeed = train.max_speed or 10
	if pc.sneak then
		if pc.up then
			train.tarvelocity = maxspeed
		end
		if pc.down then
			train.tarvelocity = 0
		end
		if pc.left then
			train.tarvelocity = 4
		end
		if pc.right then
			train.tarvelocity = 8
		end
		--[[if pc.jump then
			train.brake = true
			--0: released, 1: brake and pressed, 2: released and brake, 3: pressed and brake
			if not train.brake_hold_state or train.brake_hold_state==0 then
				train.brake_hold_state = 1
			elseif train.brake_hold_state==2 then
				train.brake_hold_state = 3
			end
		elseif train.brake_hold_state==1 then
			train.brake_hold_state = 2
		elseif train.brake_hold_state==3 then
			train.brake = false
			train.brake_hold_state = 0
		end]]
		--shift+use:see wagons.lua
	else
		local act=false
		if pc.jump then
			train.ctrl_user = 1
			act=true
		end
		if train.ars_disable and pc.up then
			-- up clears ars disable flag in any situation
			train.ars_disable = nil
		end
		-- If atc command set, only "Jump" key can clear command. To prevent accidental control.
		if train.tarvelocity or train.atc_command then
			return
		end
		if pc.up then
		   train.ctrl_user=4
		   act=true
		end
		if pc.down then
			if train.velocity>0 then
				if pc.jump then
					train.ctrl_user = 0
				else
					train.ctrl_user = 2
				end
				act=true
			else
				advtrains.invert_train(train.id)
				advtrains.atc.train_reset_command(train)
			end
		end
		if pc.left then
			if train.door_open ~= 0 then
				train.door_open = 0
			else
				train.door_open = -1
			end
		end
		if pc.right then
			if train.door_open ~= 0 then
				train.door_open = 0
			else
				train.door_open = 1
			end
		end
		if not act then
			train.ctrl_user = nil
		end
	end
end
function advtrains.update_driver_hud(pname, train, wdata)
	local inside=train.text_inside or ""
	local ft, ht = advtrains.hud_train_format(train, wdata)
	advtrains.set_trainhud(pname, inside.."\n"..ft, ht)
end
function advtrains.clear_driver_hud(pname)
	advtrains.set_trainhud(pname, "")
end

function advtrains.set_trainhud(name, text, driver)
	local hud = advtrains.hud[name]
	local player=minetest.get_player_by_name(name)
	if not player then
	   return
	end
	local drivertext = driver or ""
	local driverhud = {
		[hud_type_key] = "image",
		name = "ADVTRAINS_DRIVER",
		position = {x=0.5, y=1},
		offset = {x=0,y=-170},
		text = drivertext,
		alignment = {x=0,y=-1},
		scale = {x=1,y=1},
	}
	if not hud then
		hud = {}
		advtrains.hud[name] = hud
		hud.id = player:hud_add({
			[hud_type_key] = "text",
			name = "ADVTRAINS",
			number = 0xFFFFFF,
			position = {x=0.5, y=1},
			offset = {x=0, y=-300},
			text = text,
			scale = {x=200, y=60},
			alignment = {x=0, y=-1},
		})
		hud.driver = player:hud_add(driverhud)
		hud.oldText = text
		hud.oldDriver = drivertext
	else
		if hud.oldText ~= text then
			player:hud_change(hud.id, "text", text)
			hud.oldText=text
		end
		if hud.driver then
			if hud.oldDriver ~= drivertext then
				player:hud_change(hud.driver, "text", drivertext)
				hud.oldDriver = drivertext
			end
		elseif driver then
			hud.driver = player:hud_add(driverhud)
			hud.oldDriver = drivertext
		end
	end
end

function advtrains.set_help_hud(name, text)
	local hud = advtrains.hhud[name]
	local player=minetest.get_player_by_name(name)
	if not player then
	   return
	end
	if not hud then
		hud = {}
		advtrains.hhud[name] = hud
		hud.id = player:hud_add({
			[hud_type_key] = "text",
			name = "ADVTRAINS_HELP",
			number = 0xFFFFFF,
			position = {x=1, y=0.3},
			offset = {x=0, y=0},
			text = text,
			scale = {x=200, y=60},
			alignment = {x=1, y=0},
		})
		hud.oldText=text
		return
	elseif hud.oldText ~= text then
		player:hud_change(hud.id, "text", text)
		hud.oldText=text
	end
end

--train.lever:
--Speed control lever in train, for new train control system.
--[[
Value	Disp	Control	Meaning
0		BB		S+Space	Emergency Brake
1		B		Space	Normal Brake
2		-		S		Roll
3		o		<none>	Stay at speed
4		+		W		Accelerate
]]

function advtrains.hud_train_format(train, wdata)
	if not train then return "","" end
	local sformat = string.format -- this appears to be faster than (...):format
	
	local flip = wdata.wagon_flipped
	local max = train.max_speed or 10
	local res = train.speed_restriction
	local vel = math.abs(train.velocity)
	
	local tlev=train.lever or 3
	if train.velocity==0 and not train.active_control then tlev=1 end
	if train.hud_lzb_effect_tmr then
		tlev=1
	end
	
	local hud = T.combine(500, 100, "black")
	local st = {}
	if train.debug then st = {train.debug} end
	
	---[[ lever
	hud:add_multicolor_fill_topdown(375, 10, 5, 80, 1, "cyan", 1, "white", 2, "orange", 1, "red")
	hud:add_lever_topdown(345, 10, 30, 80, 16, 6, (4-tlev)/4, "gray", "darkslategray")
	--]]
	---[[ reverser
	hud:add(320, 10, T"advtrains_hud_arrow.png":multiply(flip and "gray" or "cyan"))
	hud:add(320, 80, T"advtrains_hud_arrow.png":transform"FY":multiply(flip and "orange" or "gray"))
	hud:add_lever_topdown(320, 25, 15, 50, 15, 5, flip and 1 or 0, "gray", "darkslategray")
	--]]
	---[[ train/wagon ID
	hud:add(10, 10, T"advtrains_hud_twid.png":verticalframe(2, 0):multiply"gray":resize(10, 10))
	hud:add_smallnum(22, 10, 2, tonumber(train.id) or 0, 6, "gray")
	hud:add(10, 30, T"advtrains_hud_twid.png":verticalframe(2, 1):multiply"gray":resize(10, 10))
	hud:add_smallnum(22, 30, 2, tonumber(wdata.id) or 0, 6, "gray")
	--]]
	---[[ train control/safety indication
	hud:add(73, 10, T"advtrains_hud_shunt.png":multiply(train.is_shunt and "orange" or "darkslategray"))
	hud:add(108, 10, T"advtrains_hud_cpl.png":multiply((train.autocouple or train.atc_wait_autocouple) and "cyan" or "darkslategray"))
	hud:add(143, 10, T"advtrains_hud_ars.png":multiply(train.ars_disable and "darkslategray" or "cyan"))
	hud:add(178, 10, T"advtrains_hud_atc.png":multiply((train.tarvelocity or train.atc_command) and "cyan" or "darkslategray"))
	hud:add(213, 10, T"advtrains_hud_lzb.png":multiply(train.hud_lzb_effect_tmr and "red" or "darkslategray"))
	--]]
	---[[ door
	hud:add(283, 10, T"advtrains_hud_door.png":multiply(train.door_open==-1 and "white" or "darkslategray"))
	hud:add(298, 10, T"advtrains_hud_door.png":multiply(train.door_open==1 and "white" or "darkslategray"):transform"FX")
	--]]
	-- speed indicators
	local lzbdisp = {c = "darkslategray", d = 8888}
	local lzb = train.lzb
	local lzbspd
	if lzb and lzb.checkpoints and lzb.checkpoints[1] then
		local cp = lzb.checkpoints[1]
		if advtrains.interlocking and cp.udata and cp.udata.signal_pos then
			local sigd = advtrains.interlocking.db.get_sigd_for_signal(cp.udata.signal_pos)
			if sigd then
				local tcbs = advtrains.interlocking.db.get_tcbs(sigd) or {}
				if tcbs.route_rsn then
					table.insert(st, ("%s: %s"):format(minetest.pos_to_string(sigd.p), tcbs.route_rsn))
				end
			end
		end
		local spd = cp.speed
		local c
		if not spd or spd == -1 then
			c = "lime"
		elseif spd == 0 then
			c = "red"
		elseif not res or spd <= res then
			c = "orange"
		elseif spd <= max then
			c = "yellow"
		else
			c = "cyan"
		end
		if c then
			if spd and spd > 0 then
				lzbspd = spd
			end
			local dist = math.floor(((cp.index or train.index)-train.index))
			dist = math.max(0, math.min(9999, dist))
			lzbdisp = {c = c, d = dist}
		end
	end
	hud:add_fill(248, 10, 30, 5, lzbdisp.c)
	hud:add_fill(248, 35, 30, 5, lzbdisp.c)
	hud:add_smallnum(248, 20, 2, lzbdisp.d, 4, lzbdisp.c)

	hud:add_n7seg(390, 10, 100, 80, math.round(vel), 2, "red")

	---[[ new speed indication bar
	local dispmax = 100
	local vmax = train.max_speed or 20
	for _, n in ipairs {10, 15, 20, 30, 50, 60, 75} do
		if vmax and train.max_speed <= n then
			dispmax = n
			break
		end
	end
	local vsize = 300/dispmax
	hud:add_fill(10, 50, vel*vsize, 25, "white")

	local vmaxmark = 10+math.floor(vmax*vsize)
	hud:add_fill(vmaxmark, 50, 310-vmaxmark, 25, "darkslategray")

	local largestep = dispmax > 30 and 10 or 5
	local smallstep = dispmax > 30 and 2 or 1
	for i = 0, vmax, smallstep do
		local markpos = math.min(9 + math.max(1, i*vsize), vmaxmark, 308)
		local marksize = 15
		if i % largestep == 0 then
			marksize = 25

			local numlen = math.floor(math.log10(math.max(i, 1))) + 1
			local numpos = markpos + 2 - 4*numlen
			if i/10^numlen < 0.2 then
				numpos = numpos - 2
			end
			numpos = math.min(math.max(numpos, 10), 308 + 4 - 8*numlen)
			hud:add_smallnum(numpos, 80, 2, i, numlen, "gray")
		end
		hud:add_fill(markpos, 50, 2, marksize, "gray")
	end

	if res and res > 0 then
		hud:add_fill(math.min(9 + res*vsize, vmaxmark, 308), 50, 2, 25, "red")
	end

	-- [lowpart:...^[transform... does not seem to work well so we do not use it for now
	-- Otherwise we could "crop" the arrows at the edges of the bar.
	for _, arr in pairs {
		{v = train.tarvelocity, y = 50, fill = "cyan", transform = "I"},
		{v = lzbspd, y = 65, fill = "orange", transform = "FY"},
	} do
		if arr.v then
			local x = math.max(math.min(5+math.floor(arr.v*vsize), vmaxmark-5, 304), 6)
			hud:add(x, arr.y, T"advtrains_hud_speed_arrow.png":colorize(arr.fill, "alpha"):transform(arr.transform))
		end
	end
	--]]
	
	if res and res == 0 then
		table.insert(st, S("OVERRUN RED SIGNAL! Examine situation and reverse train to move again."))
	end
	
	if train.atc_command then
		local delay_str = ""
		if train.atc_delay and train.atc_delay >= 0 then
			delay_str = advtrains.abs_ceil(train.atc_delay).."s "
		end
		if train.atc_wait_finish then
			delay_str = delay_str.."[W] "
		end
		if train.atc_wait_autocouple then
			delay_str = delay_str.."[Cpl] "
		end
		if train.atc_wait_signal then
			delay_str = delay_str.."[G] "
		end
		table.insert(st, ("ATC: %s%s"):format(delay_str, train.atc_command or ""))
	end
	
	return table.concat(st,"\n"), tostring(hud)
end
