class_name DemoMenu
extends RefCounted
## DEMO menu: every launch action of the demo sandbox, headless-testable. The entries are shown as the DEMO tab of the TEST MENU (scripts/ui/test_menu.gd, page DEMO) and
## call the live game: every vehicle kind, every enemy type and boss, every weapon, weather, time of day, heat level and the full hero kit preset.
## Each action returns a short status line ("" = could not do it). Tests: tests/test_demo_menu.gd, tests/bot_full_game.gd (_act_demo).

const HOURS := {"DAWN": 6.0, "NOON": 12.0, "DUSK": 19.0, "MIDNIGHT": 0.0}


static func vehicle_kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: Variant in VehicleSpecs.SPECS:
		out.append(k as StringName)
	return out


static func enemy_types() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: Variant in EnemyTypes.TYPES:
		if not bool((EnemyTypes.TYPES[k] as Dictionary).get("boss", false)):
			out.append(k as StringName)
	return out


static func boss_types() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: Variant in EnemyTypes.TYPES:
		if bool((EnemyTypes.TYPES[k] as Dictionary).get("boss", false)):
			out.append(k as StringName)
	return out


static func _player() -> Player:
	return Game.player as Player if is_instance_valid(Game.player) else null


static func _front(dist: float) -> Vector3:
	var p := _player()
	if p == null:
		return Vector3.ZERO
	var at := p.global_position + Vector3(-sin(p.yaw), 0.0, -cos(p.yaw)) * dist
	at.y = p.global_position.y
	return at


static func spawn_vehicle(kind: StringName) -> String:
	if not is_instance_valid(Game.vehicles) or not VehicleSpecs.SPECS.has(kind):
		return ""
	var vm := Game.vehicles as VehicleManager
	var p := _player()
	if vm.list.size() >= vm.cap():
		for old: Vehicle in vm.list:
			if is_instance_valid(old) and (p == null or old != p.vehicle):
				vm._release(old)
				break
	var v := vm.spawn_parked(kind, _front(8.0), p.yaw if p != null else 0.0)
	return "SPAWNED  %s" % String(kind).to_upper() if v != null else ""


static func spawn_enemy(type: StringName) -> String:
	if not is_instance_valid(Game.enemies) or not EnemyTypes.TYPES.has(type):
		return ""
	var mgr := Game.enemies as EnemyManager
	if mgr.alive_count() >= mgr.cap():
		for e: Drone in mgr.list:
			if is_instance_valid(e):
				mgr.release(e)
				break
	var d := mgr.spawn(type, _front(14.0) + Vector3(0.0, 0.5, 0.0), true)
	return "SPAWNED  %s" % String(type).to_upper() if d != null else ""


static func set_time(hour: float) -> String:
	var city := Game.world as City
	if city == null or city.day_night == null:
		return ""
	city.day_night.set_hour(hour)
	return "TIME  %s" % DayNight.clock_text(hour)


## Every weapon with full ammo, maxed upgrades, credits, every chapter, full health and energy.
static func full_hero_kit() -> String:
	var p := _player()
	if p == null:
		return ""
	TestMode.give_all_weapons()
	TestMode.fill_ammo()
	TestMode.max_upgrades()
	TestMode.add_credits(50000)
	var prog := Game.progress as Progress
	if prog != null:
		prog.unlock(CampaignRunner.chapter_count() - 1)
	p.hp = p.max_hp
	p.energy = p.max_energy
	return "FULL HERO KIT"


## The menu content: {head: true, label} or {label, fn: Callable -> String}.
static func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"head": true, "label": "PRESET"})
	out.append({"label": "FULL HERO KIT", "fn": full_hero_kit})
	out.append({"head": true, "label": "VEHICLES"})
	for k in vehicle_kinds():
		out.append({"label": String(k).to_upper(), "fn": spawn_vehicle.bind(k)})
	out.append({"head": true, "label": "ENEMIES"})
	for t in enemy_types():
		out.append({"label": String(t).to_upper(), "fn": spawn_enemy.bind(t)})
	out.append({"head": true, "label": "BOSSES"})
	for t in boss_types():
		out.append({"label": String(t).to_upper(), "fn": spawn_enemy.bind(t)})
	out.append({"head": true, "label": "WEAPONS"})
	for id: StringName in WeaponDefs.IDS:
		out.append({"label": WeaponDefs.title(id), "fn": TestMode.give_weapon.bind(id)})
	out.append({"head": true, "label": "QUANTUM VERBS"})
	for id: StringName in QuantumVerbs.IDS:
		out.append({"label": QuantumVerbs.TITLES[id], "fn": TestMode.use_verb.bind(id)})
	out.append({"head": true, "label": "THROWABLES AND GADGETS"})
	for id: StringName in Gear.THROW_IDS + Gear.GADGET_IDS:
		out.append({"label": Gear.title(id), "fn": TestMode.give_gear.bind(id)})
	out.append({"head": true, "label": "SKILLS"})
	out.append({"label": "+5000 XP", "fn": TestMode.give_xp.bind(5000)})
	out.append({"label": "MAX ALL SKILLS", "fn": TestMode.max_skills})
	out.append({"head": true, "label": "WEATHER"})
	for w: String in TestMode.WEATHER:
		out.append({"label": w, "fn": TestMode.set_weather.bind(w)})
	out.append({"head": true, "label": "SURFACE LOOK"})
	out.append({"label": "MATERIALS V2", "fn": TestMode.set_materials_v2.bind(true)})
	out.append({"label": "MATERIALS V1", "fn": TestMode.set_materials_v2.bind(false)})
	out.append({"head": true, "label": "VFX SHOWCASE"})
	for id: StringName in FX.QuantumVfx.SHOWCASE:
		out.append({"label": String(FX.QuantumVfx.SHOWCASE_TITLES[id]), "fn": FX.qvfx.play_demo.bind(id)})
	out.append({"head": true, "label": "POST LOOK"})
	out.append({"label": "FILM FX2", "fn": TestMode.set_post_fx2.bind(true)})
	out.append({"label": "BASE", "fn": TestMode.set_post_fx2.bind(false)})
	out.append({"head": true, "label": "TIME OF DAY"})
	for n: String in HOURS:
		out.append({"label": n, "fn": set_time.bind(HOURS[n])})
	out.append({"head": true, "label": "HEAT LEVEL"})
	for h in 6:
		out.append({"label": "HEAT %d" % h, "fn": TestMode.set_heat.bind(float(h))})
	return out
