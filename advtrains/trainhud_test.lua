local S = advtrains.translate
local function FS(...)
	return core.formspec_escape(S(...))
end

local default_hud = { -- dummy train object to demonstrate the train hud
	max_speed = 15, speed_restriction = 15, velocity = 15, tarvelocity = 12,
	active_control = true, lever = 3, ctrl = {lzb = true}, is_shunt = true,
	door_open = 1, lzb = {checkpoints = {{speed=6, index=125.7}}}, index = 100,
	id = "012345",
}
local default_wagon = { id = "987654" }
local _, texture = advtrains.hud_train_format(default_hud, default_wagon)

local hud_test_cache = {}

local speed_scrollbaroptions = "scrollbaroptions[min=0;max=100;smallstep=1]"
local function hudtest_speed_scrollbar(fs, y, id, label, val)
	table.insert(fs, ("label[0.5,%f;%s]"):format(y, core.formspec_escape(label)))
	table.insert(fs, speed_scrollbaroptions)
	table.insert(fs, ("scrollbar[4,%f;6.5,0.4;horizontal;%s;%d]"):format(y-0.2, core.formspec_escape(id), val))
end

local function show_hud_test(pname)
	local fs = {"formspec_version[2]", "size[11,6.5]"}
	local hud = hud_test_cache[pname] or default_hud

	table.insert(fs, ("checkbox[0.5,0.75;noars;%s;%s]"):format(FS("Disable ARS"), hud.ars_disable or "false"))
	table.insert(fs, ("checkbox[4,0.75;shunt;%s;%s]"):format(FS("Shunt mode"), hud.is_shunt or "false"))
	table.insert(fs, ("checkbox[7.5,0.75;ac;%s;%s]"):format(FS("Autocouple mode"), hud.autocuople or "false"))

	hudtest_speed_scrollbar(fs, 1.25, "velocity", S("Speed: @1", tostring(hud.velocity)), hud.velocity)
	hudtest_speed_scrollbar(fs, 1.75, "vmax", S("Maximum speed: @1", tostring(hud.max_speed)), hud.max_speed)
	hudtest_speed_scrollbar(fs, 2.25, "res", hud.speed_restriction and S("Speed restriction: @1", tostring(hud.speed_restriction)) or S("No speed restriction"), hud.speed_restriction or 0)

	local _, tx = advtrains.hud_train_format(hud, default_wagon)
	table.insert(fs, ("image[0.5,4;10,2;%s]"):format(core.formspec_escape(tx)))

	core.show_formspec(pname, "advtrains:hud_dev", table.concat(fs))
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "advtrains:hud_dev" then
		return
	end
	if core.is_yes(fields.quit) or core.is_yes(fields.key_enter) then
		return true
	end

	local pname = player:get_player_name()
	local hud = hud_test_cache[pname]
	if not hud then
		hud = table.copy(default_hud)
		hud_test_cache[pname] = hud
	end

	for fk, tk in pairs {noars = "ars_disable", shunt = "is_shunt", ac = "autocouple"} do
		if fields[fk] then
			hud[tk] = core.is_yes(fields[fk])
		end
	end
	
	for fk, tk in pairs {velocity = "velocity", vmax = "max_speed", res = "speed_restriction"} do
		local event = core.explode_scrollbar_event(fields[fk] or "")
		if event and event.type == "CHG" then
			hud[tk] = event.value
		end
	end
	hud.velocity = math.min(hud.velocity, hud.max_speed)
	if hud.speed_restriction and hud.speed_restriction <= 0 then
		hud.speed_restriction = nil
	end

	show_hud_test(pname)
	return true
end)

core.register_node("advtrains:hud_demo",{
	description = "Train HUD demonstration",
	tiles = {texture},
	groups = {cracky = 3, not_in_creative_inventory = 1},
	on_rightclick = function(_, _, clicker)
		if clicker:is_player() then
			show_hud_test(clicker:get_player_name())
		end
	end,
})

core.register_craft {
	output = "advtrains:hud_demo",
	recipe = {
		{"default:paper", "default:paper", "default:paper"},
		{"default:paper", "advtrains:trackworker", "default:paper"},
		{"default:paper", "default:paper", "default:paper"},
	}
}
