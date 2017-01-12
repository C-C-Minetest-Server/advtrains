--advtrains

--create the base table structure.
advtrains={atc={controllers={}}, detector={}, trackplacer={}, trains={}, trackdb={}, wagon_save={}}

advtrains.modpath = minetest.get_modpath("advtrains")

local function print_concat_table(a)
	local str=""
	local stra=""
	for i=1,50 do
		t=a[i]
		if t==nil then
			stra=stra.."nil "
		else
			str=str..stra
			stra=""
			if type(t)=="table" then
				if t.x and t.y and t.z then
					str=str..minetest.pos_to_string(t)
				else
					str=str..dump(t)
				end
			elseif type(t)=="boolean" then
				if t then
					str=str.."true"
				else
					str=str.."false"
				end
			else
				str=str..t
			end
			str=str.." "
		end
	end
	return str
end
--atprint=function() end
atprint=function(t, ...) minetest.log("action", "[advtrains]"..print_concat_table({t, ...})) minetest.chat_send_all("[advtrains]"..print_concat_table({t, ...})) end
sid=function(id) return string.sub(id, -4) end

dofile(advtrains.modpath.."/helpers.lua");
dofile(advtrains.modpath.."/debugitems.lua");

advtrains.meseconrules = 
{{x=0,  y=0,  z=-1},
 {x=1,  y=0,  z=0},
 {x=-1, y=0,  z=0},
 {x=0,  y=0,  z=1},
 {x=1,  y=1,  z=0},
 {x=1,  y=-1, z=0},
 {x=-1, y=1,  z=0},
 {x=-1, y=-1, z=0},
 {x=0,  y=1,  z=1},
 {x=0,  y=-1, z=1},
 {x=0,  y=1,  z=-1},
 {x=0,  y=-1, z=-1},
 {x=0, y=-2, z=0}}
 


--load/save

advtrains.fpath=minetest.get_worldpath().."/advtrains"
local file, err = io.open(advtrains.fpath, "r")
if not file then
	minetest.log("error", " Failed to read advtrains save data from file "..advtrains.fpath..": "..(err or "Unknown Error"))
else
	local tbl = minetest.deserialize(file:read("*a"))
	if type(tbl) == "table" then
		if tbl.version then
			--congrats, we have the new save format.
			advtrains.atc.controllers = tbl.atc_controllers
			advtrains.trains = tbl.trains
			advtrains.wagon_save = tbl.wagon_save
		else
			--oh no, its the old one...
			advtrains.trains=tbl
			--load ATC
			advtrains.fpath_atc=minetest.get_worldpath().."/advtrains_atc"
			local file, err = io.open(advtrains.fpath_atc, "r")
			if not file then
				local er=err or "Unknown Error"
				atprint("Failed loading advtrains atc save file "..er)
			else
				local tbl = minetest.deserialize(file:read("*a"))
				if type(tbl) == "table" then
					advtrains.atc.controllers=tbl.controllers
				end
				file:close()
			end
			--load wagon saves
			advtrains.fpath_ws=minetest.get_worldpath().."/advtrains_wagon_save"
			local file, err = io.open(advtrains.fpath_ws, "r")
			if not file then
				local er=err or "Unknown Error"
				atprint("Failed loading advtrains save file "..er)
			else
				local tbl = minetest.deserialize(file:read("*a"))
				if type(tbl) == "table" then
					advtrains.wagon_save=tbl
				end
				file:close()
			end
		end
	else
		minetest.log("error", " Failed to deserialize advtrains save data: Not a table!")
	end
	file:close()
end

advtrains.save = function()
	atprint("saving")
	advtrains.invalidate_all_paths()
	
	-- update wagon saves
	for _,wagon in pairs(minetest.luaentities) do
		if wagon.is_wagon and wagon.initialized then
			wagon:get_staticdata()
		end
	end
	--cross out userdata
	for w_id, data in pairs(advtrains.wagon_save) do
		data.name=nil
		data.object=nil
		if data.driver then
			data.driver_name=data.driver:get_player_name()
			data.driver=nil
		else
			data.driver_name=nil
		end
		if data.discouple then
			data.discouple.object:remove()
			data.discouple=nil
		end
	end
	--atprint(dump(advtrains.wagon_save))
	
	--versions:
	-- 1 - Initial new save format.
	local save_tbl={
		trains = advtrains.trains,
		wagon_save = advtrains.wagon_save,
		atc_controllers = advtrains.atc.controllers,
		version = 1,
	}
	local datastr = minetest.serialize(save_tbl)
	if not datastr then
		minetest.log("error", " Failed to serialize advtrains save data!")
		return
	end
	local file, err = io.open(advtrains.fpath, "w")
	if err then
		minetest.log("error", " Failed to write advtrains save data to file "..advtrains.fpath..": "..(err or "Unknown Error"))
		return
	end
	file:write(datastr)
	file:close()
end
minetest.register_on_shutdown(advtrains.save)


dofile(advtrains.modpath.."/trainlogic.lua")
dofile(advtrains.modpath.."/trainhud.lua")
dofile(advtrains.modpath.."/trackplacer.lua")
dofile(advtrains.modpath.."/tracks.lua")
dofile(advtrains.modpath.."/atc.lua")
dofile(advtrains.modpath.."/wagons.lua")

dofile(advtrains.modpath.."/pseudoload.lua")
dofile(advtrains.modpath.."/couple.lua")
dofile(advtrains.modpath.."/damage.lua")

dofile(advtrains.modpath.."/signals.lua")
dofile(advtrains.modpath.."/misc_nodes.lua")
dofile(advtrains.modpath.."/crafting.lua")
