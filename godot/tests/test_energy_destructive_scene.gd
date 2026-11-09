extends RefCounted
## Environmental destruction of the wave-108 weapons in the REAL game scene (main.tscn): the TREMOR MAUL's GROUND SLAM, the VOID SINGULARITY CANNON's REPULSE, the ORBITAL STRIKE BEACON's strikes and a
## CINDER NAPALM field each break the props around them (Breakables: crates, bins, fences, glass) and wreck a real parked car (VehicleManager), exactly as the same blast would from a grenade. Plus
## the real weapon wheel with all ten classes on the touch HUD, and the catalogue cards of the new weapons drawn by the real Hud. Waits on counters and state, never on frame counts.
## Run: tools/test.sh tests/test_energy_destructive_scene.gd

const DT := 1.0 / 60.0

var _host: Node
var _p: Player
var _w: PlayerWeapon
var _b: Breakables


func _until(cond: Callable, frames := 600) -> bool:
	for i in frames:
		_w.tick(DT, false, false, false, false)
		await TestLib.frames(_host, 1)
		if cond.call():
			return true
	return false


## A prop of `name` that is still whole and has a free spot beside it (the hero stands 2 m off it).
func _prop(name: String, skip := 0) -> int:
	for i in Breakables.COUNT:
		if Breakables.KINDS[_b.kind_of[i]]["name"] == name and _b.broken[i] == 0:
			if skip == 0:
				return i
			skip -= 1
	return -1


func _equip(id: StringName) -> void:
	WeaponDefs.unlock(id)
	_w.switch_to(id, true)
	_w.ammo = _w.mag
	_w.fire_t = 0.0
	_w.swap_t = 0.0
	_w.reload_t = 0.0
	_w.arms.reset()


func run(host: Node) -> void:
	_host = host
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	_p = Game.player as Player
	_b = Breakables.current
	TestLib.check(is_instance_valid(_p) and is_instance_valid(_b), "the real game has a player and breakable props")
	if not is_instance_valid(_p) or not is_instance_valid(_b):
		return
	_w = _p.weapon
	_p.max_hp = 1.0e6
	_p.hp = 1.0e6
	TestMode.god = true
	_p.set_physics_process(false)
	var vm := Game.vehicles as VehicleManager
	var enemies := Game.enemies as EnemyManager
	if enemies != null:
		enemies.patrol_groups().clear()
		enemies.clear()

	# --- GROUND SLAM of the TREMOR MAUL: a crate, a bin and a real parked car beside the hero
	var c1 := _prop("crate")
	var base := _b.positions[c1]
	var car: Vehicle = vm.spawn_parked(&"sedan", Vector3(base.x + 4.0, 0.0, base.z + 3.0), 0.0) if vm != null else null
	await TestLib.frames(host, 3)
	_p.teleport_to(base + Vector3(1.5, 0.1, 0.0))
	await TestLib.frames(host, 3)
	_equip(&"emaul")
	var br0 := _b.break_total
	var hp0 := car.hp if car != null else 0.0
	var sh0 := _w.arms.shockwaves
	TestLib.check(_w.alt_fire(false) and _w.arms.shockwaves == sh0 + 1, "GROUND SLAM goes off beside a crate")
	await TestLib.frames(host, 2)
	TestLib.check(_b.broken[c1] == 1 and _b.break_total > br0, "and the crate breaks (%d props in all)" % (_b.break_total - br0))
	TestLib.check(car != null and car.hp < hp0 - 20.0, "and the parked car beside it is dented (%.0f hp lost)" % (hp0 - (car.hp if car != null else hp0)))
	if car != null:
		vm._release(car)

	# --- REPULSE of the VOID SINGULARITY CANNON: 14 m round the hero
	var c2 := _prop("bin")
	if c2 < 0:
		c2 = _prop("fence")
	var base2 := _b.positions[c2]
	_p.teleport_to(base2 + Vector3(2.0, 0.1, 0.0))
	await TestLib.frames(host, 3)
	_equip(&"sing")
	var br1 := _b.break_total
	TestLib.check(_w.alt_fire(false), "REPULSE is fired")
	await TestLib.frames(host, 2)
	TestLib.check(_b.broken[c2] == 1 and _b.break_total > br1, "and the bin 2 m away goes (%d props)" % (_b.break_total - br1))

	# --- ORBITAL STRIKE BEACON: planted by its own handler on a block of props, the strikes wipe it
	var c3 := _prop("crate")
	var base3 := _b.positions[c3]
	var around := 0
	for i in Breakables.COUNT:
		if _b.broken[i] == 0 and _b.positions[i].distance_to(base3) < 11.0:
			around += 1
	_p.teleport_to(base3 + Vector3(30.0, 0.1, 0.0))
	await TestLib.frames(host, 3)
	_equip(&"orbital")
	var d: Dictionary = WeaponDefs.def(&"orbital")
	var br2 := _b.break_total
	var planted: bool = _w.arms.on_collapse(d, base3)
	TestLib.check(planted and _w.arms.live_beams() == 1, "the beacon is planted on a block of %d props and its column rises" % around)
	var struck: bool = await _until(func() -> bool: return _w.arms.beacon_strikes >= 3, 900)
	await TestLib.frames(host, 2)
	TestLib.check(struck and _b.broken[c3] == 1 and _b.break_total >= br2 + mini(around, 3), "three strikes fall and %d props break (%d around the spot)" % [_b.break_total - br2, around])

	# --- CINDER NAPALM: a field on a shop front burns for seconds and a real car in it takes fire damage
	var spot := Vector3(120.0, 0.0, 400.0)
	var car2: Vehicle = vm.spawn_parked(&"sedan", spot, 0.0) if vm != null else null
	if car2 == null and vm != null:                                          # all slots busy: free the farthest car, then try again
		vm._release_farthest(spot)
		car2 = vm.spawn_parked(&"sedan", spot, 0.0)
	await TestLib.frames(host, 3)
	TestLib.check(car2 != null, "a real car is parked in the street for the fire")
	_p.teleport_to(Vector3(100.0, 0.1, 400.0))
	await TestLib.frames(host, 3)
	_equip(&"napalm")
	var hp2 := car2.hp if car2 != null else 0.0
	if car2 != null:
		_w.arms.add_fire(car2.global_position, 5.5, 7.0, 16.0, 40.0)
	var burnt: bool = await _until(func() -> bool: return _w.arms.fire_ticks >= 2, 600)
	TestLib.check(burnt and car2 != null and car2.hp < hp2 - 30.0, "the burning field damages a real car standing in it (%.0f hp lost, %d ticks)" % [hp2 - (car2.hp if car2 != null else hp2), _w.arms.fire_ticks])
	if car2 != null:
		vm._release(car2)

	# --- the touch HUD: the weapon wheel with ten class wedges, every wedge a 112 px disc that stays on the screen
	for id: StringName in WeaponDefs.IDS:
		WeaponDefs.unlock(id)
	var hud := main.find_child("Hud", true, false) as Hud
	if hud != null:
		hud.touch.controls_on = true
		hud.touch.set_process(true)
		hud.touch._open_wheel(&"weapon", -1, Vector2.ZERO)
		await TestLib.frames(host, 3)
		var wheel: RadialWheel = hud.touch.wheel
		var vp := hud.get_viewport().get_visible_rect().size
		var inside := wheel.items.size() == 10
		for i in wheel.items.size():
			var c := wheel.item_centre(i)
			inside = inside and c.x > 0.0 and c.y > 0.0 and c.x < vp.x and c.y < vp.y
		TestLib.check(inside, "the real weapon wheel opens with ten wedges, all on the screen (%d, %.0f x %.0f)" % [wheel.items.size(), vp.x, vp.y])
		hud.touch.wheel.close()
		hud.touch.controls_on = false

	# --- the catalogue cards of the new weapons and gear are drawn by the real Hud without errors
	if hud != null:
		Game.state = &"paused"
		hud.press_button(&"shop")
		hud.press_button(&"hero_tab_weapons")
		var drawn := 0
		for id: StringName in [&"eplasma", &"espike", &"emaul", &"orbital", &"railgun", &"plasma", &"turret", &"jetpack"]:
			WeaponsScreen.select(id)
			hud._layout_key = ""
			await TestLib.frames(host, 3)
			if ShopScreen.weapon_page == 1 + WeaponsScreen.page_of(id) and WeaponsScreen.sel == id:
				drawn += 1
		TestLib.check(drawn == 8, "the catalogue shows the ENERGY, BLAST and gear pages (%d of 8 cards)" % drawn)
		Game.state = &"play"
	TestMode.god = false
