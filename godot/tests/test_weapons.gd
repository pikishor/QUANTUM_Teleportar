extends RefCounted
## The four alien weapons against the real Player and EnemyManager on a flat floor: WeaponDefs data and per-weapon magazines, the Rift Carbine (damage, ammo, reload, unlimited reserve),
## the Shard Scatter (pellets, per-pellet crit, falloff, reserve reload), the Pulse Lance (charge, minimum charge, scaled damage, pierce, shield break, sniper zoom), the Singularity
## Grenade (arc, gravity well pull and damage, collapse blast, pool), switching (keys, swap button, wheel, animation lock, per-weapon ammo), shop purchase, save / load of the unlocked
## set, weapon pickups and the HUD's weapon text. Time is ticked by hand where exactness matters.
## Run: tools/test.sh tests/test_weapons.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")
const Stubs := preload("res://tests/enemies_stubs.gd")

const DT := 1.0 / 60.0

var e := Env.new()
var p: Player
var w: PlayerWeapon
var root: Node3D
var em: EnemyManager
var stub_missions := Stubs.StubMissions.new()
var collapsed := 0


func run(host: Node) -> void:
	seed(21)
	await e.setup(host)
	p = e.p
	root = e.root
	w = p.weapon
	p.max_hp = 1.0e6
	Fixture.release_inputs()
	Game.world = Stubs.StubWorld.new()
	root.add_child(Game.world)
	root.add_child(stub_missions)
	Game.missions = stub_missions
	em = (load("res://scenes/enemy_manager.tscn") as PackedScene).instantiate() as EnemyManager
	root.add_child(em)
	em.patrol_groups().clear()
	await e.frames(3)
	w.grenade_collapsed.connect(func(_pos: Vector3) -> void: collapsed += 1)

	_defs()
	await _carbine()
	await _scatter()
	await _lance()
	await _grenade()
	await _switching()
	_upgrades_and_shop()
	await _save_and_pickups()
	await _hud_text()

	Game.world = null
	Game.missions = null
	Game.heat = 0.0
	WeaponDefs.reset_unlocked()
	Upgrades.reset()
	await e.teardown()


# --- helpers ---------------------------------------------------------------------------------------------------------

func _fresh() -> void:
	em.clear()
	Game.heat = 0.0
	Game.state = &"play"
	Upgrades.reset()
	WeaponDefs.reset_unlocked()
	WeaponDefs.unlock(&"scatter")
	WeaponDefs.unlock(&"lance")
	WeaponDefs.unlock(&"grenade")
	await e.prep(Vector3(0.0, 0.05, 0.0))
	w.reset()
	w.switch_to(&"carbine", true)
	w.reset()


## A frozen enemy of `type` at the floor position `at`.
func _target(type: StringName, at: Vector3, frozen := true) -> Drone:
	var d := em.spawn(type, at, false)
	d.set_physics_process(not frozen)
	await e.frames(2)                                           # the collider reaches its new place
	return d


func _aim(d: Drone, up := 0.0) -> void:
	p.camera_rig.aim_at(d.center() + Vector3(0.0, up, 0.0))


func _pull(seconds: float, aiming := false) -> void:
	for i in int(ceil(seconds / DT)):
		w.tick(DT, true, false, aiming, false)


func _tick_idle(seconds: float) -> void:
	for i in int(ceil(seconds / DT)):
		w.tick(DT, false, false, false, false)


# --- data ------------------------------------------------------------------------------------------------------------

func _defs() -> void:
	TestLib.check(WeaponDefs.IDS.size() == 4, "four weapons")
	var ok := true
	for id: StringName in WeaponDefs.IDS:
		var d := WeaponDefs.def(id)
		for k: String in ["name", "tag", "kind", "mag", "reserve", "interval", "damage", "crit", "pellets", "spread_hip", "spread_ads", "reload", "range", "tracer", "look", "look_size", "zoom", "price"]:
			ok = ok and d.has(k)
	TestLib.check(ok, "every weapon has the full data row")
	TestLib.check(WeaponDefs.def(&"carbine")["mag"] == PlayerWeapon.MAG_SIZE and is_equal_approx(float(WeaponDefs.def(&"carbine")["damage"]), PlayerWeapon.DAMAGE), "the carbine keeps its old numbers")
	TestLib.check(WeaponDefs.def(&"scatter")["pellets"] == 8 and WeaponDefs.def(&"lance")["kind"] == "charge" and WeaponDefs.def(&"grenade")["kind"] == "throw", "scatter 8 pellets, lance charge, grenade throw")
	var intervals := {}
	for id: StringName in WeaponDefs.IDS:
		intervals[WeaponDefs.def(id)["interval"]] = true
	TestLib.check(intervals.size() == 4, "four distinct fire intervals")
	WeaponDefs.reset_unlocked()
	TestLib.check(WeaponDefs.unlocked == [&"carbine"], "only the carbine is owned at first")
	TestLib.check(WeaponDefs.unlock(&"lance") and not WeaponDefs.unlock(&"lance") and WeaponDefs.is_unlocked(&"lance"), "unlock once")
	WeaponDefs.set_unlocked(["scatter", "bogus"])
	TestLib.check(WeaponDefs.unlocked == [&"carbine", &"scatter"], "set_unlocked drops unknown ids and keeps the carbine")
	TestLib.check(WeaponDefs.mag_size(&"carbine", 0) == 30 and WeaponDefs.mag_size(&"carbine", 5) == 60, "carbine magazine 30..60 as before")
	TestLib.check(WeaponDefs.pick_drop(0.1, 0.0) != &"carbine" and WeaponDefs.pick_drop(0.9, 0.99) != &"carbine", "drops are never the carbine")


# --- carbine ---------------------------------------------------------------------------------------------------------

func _carbine() -> void:
	await _fresh()
	TestLib.check(w.current == &"carbine" and w.ammo == 30 and w.mag == 30 and w.reserve < 0, "default: carbine 30/30, unlimited reserve")
	var d := await _target(&"heavy", Vector3(14.0, 0.0, 0.0))
	_aim(d)
	var hp0 := d.hp
	_pull(0.01)
	TestLib.check(w.ammo == 29 and is_equal_approx(d.hp, hp0 - PlayerWeapon.DAMAGE), "one carbine round: ammo 29, 14 damage")
	TestLib.check(w.fire_t > 0.07 and w.fire_t <= PlayerWeapon.FIRE_INTERVAL, "fire interval ~0.105 s")
	_aim(d, 0.9)
	var hp1 := d.hp
	w.fire_t = 0.0
	_pull(0.01)
	TestLib.check(is_equal_approx(hp1 - d.hp, PlayerWeapon.DAMAGE_CRIT), "a high hit is a 30 damage crit")
	_pull(0.6)
	TestLib.check(w.ammo < 26, "sustained fire spends ammo (%d)" % w.ammo)
	w.ammo = 0
	w.fire_t = 0.0
	w.tick(DT, false, true, false, false)
	TestLib.check(w.is_reloading(), "R starts a reload on an empty magazine")
	_tick_idle(PlayerWeapon.RELOAD_TIME + 0.1)
	TestLib.check(w.ammo == 30 and w.reserve < 0 and not w.is_reloading(), "reload refills to 30 from the unlimited reserve")
	em.clear()


# --- scatter ---------------------------------------------------------------------------------------------------------

func _scatter() -> void:
	await _fresh()
	TestLib.check(w.switch_to(&"scatter", true) and w.current == &"scatter", "switch to the scatter")
	TestLib.check(w.mag == 6 and w.ammo == 6 and w.reserve == 36, "scatter 6 in the magazine, 36 spare")
	w.tick(DT, false, false, false, false)
	TestLib.check(w.spread > 0.06, "scatter spread is wide (%.3f)" % w.spread)
	var d := await _target(&"heavy", Vector3(5.0, 0.0, 0.0))
	_aim(d)
	var hp0 := d.hp
	_pull(0.01)
	var near := hp0 - d.hp
	TestLib.check(w.ammo == 5, "one shell")
	TestLib.check(near > 50.0 and near <= 8.0 * float(WeaponDefs.def(&"scatter")["crit"]), "five metres: most pellets land (%.0f damage)" % near)
	em.clear()
	var d2 := await _target(&"heavy", Vector3(5.0, 0.0, 0.0))
	w.fire_t = 0.0
	_aim(d2, 0.9)
	var hp2 := d2.hp
	_pull(0.01)
	TestLib.check(hp2 - d2.hp > near + 10.0, "high pellets crit one by one (%.0f vs %.0f)" % [hp2 - d2.hp, near])
	em.clear()
	var far := await _target(&"heavy", Vector3(32.0, 0.0, 0.0))
	w.fire_t = 0.0
	_aim(far)
	var hp3 := far.hp
	_pull(0.01)
	TestLib.check(hp3 - far.hp < near * 0.6, "at 32 m the cone and the falloff cost most of it (%.0f)" % (hp3 - far.hp))
	em.clear()
	w.fire_t = 0.0
	w.tick(DT, true, false, false, false)
	var before := w.ammo
	w.reload_t = 0.0
	w.start_reload()
	_tick_idle(2.1)
	TestLib.check(w.ammo == 6 and w.reserve == 36 - (6 - before), "reload takes the rounds from the reserve (%d spare)" % w.reserve)
	w.ammo = 0
	w.reserve = 0
	TestLib.check(not w.start_reload(), "no reserve: no reload")


# --- lance -----------------------------------------------------------------------------------------------------------

func _lance() -> void:
	await _fresh()
	TestLib.check(w.switch_to(&"lance", true), "switch to the lance")
	TestLib.check(w.mag == 5 and w.reserve == 20 and is_equal_approx(p.camera_rig.ads_fov, 24.0), "lance 5 + 20, sniper zoom 24 degrees")
	var d := await _target(&"heavy", Vector3(25.0, 0.0, 0.0))
	_aim(d)
	var hp0 := d.hp
	_pull(0.15)
	TestLib.check(w.charge > 0.0 and w.charge < 0.3 and w.ammo == 5, "holding charges, nothing fires yet (%.2f)" % w.charge)
	w.tick(DT, false, false, false, false)
	TestLib.check(w.charge == 0.0 and w.ammo == 5 and d.hp == hp0, "released below the minimum charge: cancelled, no round spent")
	_pull(0.55)
	var c := w.charge
	TestLib.check(c > 0.45 and c < 0.55, "half charge (%.2f)" % c)
	w.tick(DT, false, false, false, false)
	var half := hp0 - d.hp
	TestLib.check(w.ammo == 4 and half > 35.0 and half < 75.0, "a half charge hits for about half (%.0f)" % half)
	w.fire_t = 0.0
	_pull(1.4)
	TestLib.check(is_equal_approx(w.charge, 1.0), "full charge holds at 1")
	var hp1 := d.hp
	w.tick(DT, false, false, false, false)
	TestLib.check(is_equal_approx(hp1 - d.hp, 120.0), "a full charge deals 120 (%.0f)" % (hp1 - d.hp))
	em.clear()
	# pierce: two in a line, the far one behind the near one
	w.fire_t = 0.0
	var a := await _target(&"heavy", Vector3(15.0, 0.0, 0.0))
	var b := await _target(&"heavy", Vector3(30.0, 0.0, 0.0))
	_aim(a)
	p.camera_rig.aim_at((a.center() + b.center()) * 0.5)
	var ha := a.hp
	var hb := b.hp
	_pull(1.3)
	w.tick(DT, false, false, false, false)
	TestLib.check(a.hp < ha and b.hp < hb, "the lance pierces both targets in line")
	em.clear()
	# shield: breaks, does not block
	w.fire_t = 0.0
	w.ammo = 5
	var s := await _target(&"shield", Vector3(18.0, 0.0, 0.0)) as Specialist
	s.yaw = PI / 2.0                                            # facing +x? forward is (-sin, -cos): yaw -PI/2 faces +x ... set below
	s.yaw = -PI / 2.0
	s.rotation.y = s.yaw
	_aim(s)
	var hs := s.hp
	_pull(1.3)
	w.tick(DT, false, false, false, false)
	TestLib.check(not s.shield_up() and s.hp < hs, "the lance breaks the frontal shield and hurts him")
	em.clear()
	w.reload_t = 0.0


# --- grenade ---------------------------------------------------------------------------------------------------------

func _grenade() -> void:
	await _fresh()
	TestLib.check(w.switch_to(&"grenade", true) and w.mag == 1 and w.reserve == 5, "grenade 1 + 5")
	var victim := await _target(&"sentinel", Vector3(16.0, 0.0, 0.0), false)
	var guard := await _target(&"heavy", Vector3(16.0, 0.0, 6.0), false)
	var floor_pt := Vector3(11.0, 0.0, 0.0)
	p.camera_rig.aim_at(floor_pt + Vector3(0.0, 0.05, 0.0))
	collapsed = 0
	w.tick(DT, true, false, false, false)
	TestLib.check(w.ammo == 0 and w.grenades_active() == 1, "throw: ammo 0, one grenade in the air")
	TestLib.check(w.swap_t == 0.0 and w.fire_t > 0.5, "interval 0.9 s between throws")
	var start_dist := 99.0
	var well_seen := false
	var min_dist := 99.0
	var hp_v := victim.hp
	var hp_g := guard.hp
	for i in 300:
		await e.frames(1)
		var wells := w.well_positions()
		if not wells.is_empty():
			if not well_seen:
				well_seen = true
				start_dist = Vector2(victim.global_position.x - wells[0].x, victim.global_position.z - wells[0].z).length()
			min_dist = minf(min_dist, Vector2(victim.global_position.x - wells[0].x, victim.global_position.z - wells[0].z).length())
		if collapsed > 0:
			break
	TestLib.check(well_seen, "the grenade lands and opens a gravity well")
	TestLib.check(start_dist < 9.0 and min_dist < start_dist - 1.5, "the well pulls enemies in (%.1f m -> %.1f m)" % [start_dist, min_dist])
	TestLib.check(collapsed == 1 and w.grenades_active() == 0, "collapse blast after the well, the slot is free again")
	TestLib.check(victim.dead or victim.hp < hp_v * 0.2, "the sentinel in the well is destroyed (hp %.0f of %.0f)" % [victim.hp, hp_v])
	TestLib.check(guard.hp < hp_g, "the heavy beside it is burnt (%.0f of %.0f)" % [guard.hp, hp_g])
	# shield trooper in the well loses the shield
	em.clear()
	w.ammo = 1
	w.fire_t = 0.0
	var sh := await _target(&"shield", Vector3(14.0, 0.0, 0.0), false) as Specialist
	p.camera_rig.aim_at(Vector3(11.0, 0.05, 0.0))
	collapsed = 0
	w.tick(DT, true, false, false, false)
	for i in 200:
		await e.frames(1)
		if collapsed > 0:
			break
	TestLib.check(not sh.shield_up() or sh.dead, "the well and the blast take the shield away")
	em.clear()


# --- switching -------------------------------------------------------------------------------------------------------

func _switching() -> void:
	await _fresh()
	# per-weapon ammo survives a round trip
	w.ammo = 20
	w.switch_to(&"scatter", true)
	w.ammo = 3
	w.switch_to(&"carbine", true)
	TestLib.check(w.ammo == 20, "the carbine remembers its 20 rounds")
	w.switch_to(&"scatter", true)
	TestLib.check(w.ammo == 3, "the scatter remembers its 3 shells")
	w.switch_to(&"carbine", true)
	# keys 1-4 through the input map
	Input.action_press(&"weapon_3")
	await e.frames(3)
	Input.action_release(&"weapon_3")
	TestLib.check(w.current == &"lance", "key 3 selects the lance")
	Input.action_press(&"swap")
	await e.frames(3)
	Input.action_release(&"swap")
	TestLib.check(w.current == &"grenade", "SWAP cycles to the next weapon")
	Input.action_press(&"weapon_next")
	await e.frames(3)
	Input.action_release(&"weapon_next")
	TestLib.check(w.current == &"carbine", "the wheel wraps round to the carbine")
	Input.action_press(&"weapon_prev")
	await e.frames(3)
	Input.action_release(&"weapon_prev")
	TestLib.check(w.current == &"grenade", "wheel back")
	# the swap animation locks the trigger
	w.switch_to(&"carbine")
	TestLib.check(w.swap_t > 0.2, "a swap takes %.2f s" % w.swap_t)
	var a0 := w.ammo
	w.tick(DT, true, false, false, false)
	TestLib.check(w.ammo == a0, "no shot during the swap")
	_tick_idle(PlayerWeapon.SWAP_TIME + 0.05)
	w.fire_t = 0.0
	w.tick(DT, true, false, false, false)
	TestLib.check(w.ammo == a0 - 1, "firing again after the swap")
	# locked weapons cannot be selected
	WeaponDefs.reset_unlocked()
	TestLib.check(not w.switch_to(&"lance") and w.current == &"carbine", "a locked weapon stays locked")
	Input.action_press(&"weapon_2")
	await e.frames(3)
	Input.action_release(&"weapon_2")
	TestLib.check(w.current == &"carbine", "key 2 does nothing while the scatter is not owned")
	TestLib.check(not w.cycle(1), "cycling with one weapon does nothing")
	# the touch SWAP button exists and drives the action
	var has_swap := false
	for b: Dictionary in TouchControls.BUTTONS:
		has_swap = has_swap or b["action"] == &"swap"
	TestLib.check(has_swap, "the touch controls have a SWAP button")
	TestLib.check(InputMap.has_action(&"swap") and InputMap.has_action(&"weapon_1") and InputMap.has_action(&"weapon_prev"), "input actions exist")
	# the rifle's look follows the weapon
	WeaponDefs.unlock(&"lance")
	w.switch_to(&"lance", true)
	var look := p.body.muzzle.get_node_or_null("WeaponLook") as MeshInstance3D
	TestLib.check(look != null and (look.mesh as BoxMesh).size.z > 0.7, "the lance wears a long rail on the rifle")


# --- upgrades, shop ----------------------------------------------------------------------------------------------------

func _upgrades_and_shop() -> void:
	WeaponDefs.reset_unlocked()
	w.switch_to(&"carbine", true)
	Upgrades.set_levels({&"mag": 2})
	TestLib.check(WeaponDefs.mag_size(&"carbine", 2) == 42 and WeaponDefs.mag_size(&"scatter", 2) == 8 and WeaponDefs.mag_size(&"lance", 2) == 7 and WeaponDefs.mag_size(&"grenade", 2) == 2,
			"the magazine upgrade scales every weapon from its own base")
	Upgrades.reset()
	var prog := Progress.new()
	root.add_child(prog)
	prog.path = "user://test_weapons_shop.cfg"
	prog.new_campaign()
	prog.credits = 600
	TestLib.check(prog.weapon_price(&"scatter") == 500 and prog.can_buy_weapon(&"scatter") and not prog.can_buy_weapon(&"lance"), "the scatter costs 500, the lance is out of reach")
	TestLib.check(prog.buy_weapon(&"scatter") and prog.credits == 100 and WeaponDefs.is_unlocked(&"scatter"), "buying unlocks the scatter and pays")
	TestLib.check(not prog.buy_weapon(&"scatter") and not prog.buy_weapon(&"lance") and not prog.buy_weapon(&"carbine"), "no double purchase, no unaffordable, no carbine")
	prog.set(&"levels", {})
	prog.credits = 5000
	prog.buy(&"damage")
	TestLib.check(Upgrades.damage_mult() > 1.1, "a damage upgrade applies to every weapon's hits")
	prog.credits = 5000
	w.reset()
	prog.buy(&"mag")
	prog.buy(&"mag")
	TestLib.check(w.mag == 42 and w.ammo == 42, "the live carbine got the new magazine at once (%d)" % w.mag)
	prog.free()
	Upgrades.reset()


# --- save and pickups ---------------------------------------------------------------------------------------------------

func _save_and_pickups() -> void:
	await _fresh()
	var prog := Progress.new()
	root.add_child(prog)
	prog.path = "user://test_weapons_save.cfg"
	prog.new_campaign()
	TestLib.check(WeaponDefs.unlocked == [&"carbine"], "a new campaign starts with the carbine only")
	prog.grant_weapon(&"lance")
	TestLib.check(WeaponDefs.is_unlocked(&"lance") and prog.grant_weapon(&"scatter") and not prog.grant_weapon(&"scatter"), "granting unlocks once")
	w.switch_to(&"lance", true)
	TestLib.check(prog.save_file(), "saved")
	WeaponDefs.reset_unlocked()
	TestLib.check(WeaponDefs.unlocked == [&"carbine"], "wiped")
	TestLib.check(prog.load_file(), "loaded")
	TestLib.check(WeaponDefs.unlocked == [&"carbine", &"scatter", &"lance"] and WeaponDefs.last_used == &"lance", "the unlocked set and the weapon in hand come back")
	TestLib.check(w.current == &"lance", "the player's weapon is switched to the saved one")
	prog.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_weapons_save.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_weapons_shop.cfg"))
	# pickups through the real Missions node
	WeaponDefs.reset_unlocked()
	var world := Node3D.new()
	world.set_script(preload("res://tests/weapons_world.gd"))
	root.add_child(world)
	Game.world = world
	var m := (load("res://scenes/missions.tscn") as PackedScene).instantiate() as Missions
	root.add_child(m)
	await e.frames(3)
	TestLib.check(Missions.KINDS.has(&"weapon"), "weapon is a pickup kind")
	w.reset()
	p.teleport_to(Vector3(0.0, 0.05, 0.0))
	m.drop_weapon(&"scatter", Vector3(0.5, 0.0, 0.5))
	await e.frames(6)
	TestLib.check(WeaponDefs.is_unlocked(&"scatter"), "walking into the pickup unlocks the scatter")
	m.drop_weapon(&"scatter", Vector3(0.5, 0.0, 0.5))
	var r0 := w.reserve_of(&"scatter")
	await e.frames(6)
	TestLib.check(w.reserve_of(&"scatter") > r0 or r0 >= 72, "an owned weapon's pickup is an ammo pack (%d -> %d)" % [r0, w.reserve_of(&"scatter")])
	m.free()
	Game.world = null


# --- HUD ---------------------------------------------------------------------------------------------------------------

func _hud_text() -> void:
	await _fresh()
	var hud := (load("res://scenes/hud.tscn") as PackedScene).instantiate() as Hud
	root.add_child(hud)
	await e.frames(3)
	TestLib.check(hud.weapon_text().begins_with("RIFT CARBINE") and hud.weapon_text().contains("CRB") and hud.weapon_text().contains("INF"), "HUD: carbine, tag, unlimited reserve (%s)" % hud.weapon_text())
	TestLib.check(hud.ammo_text() == "30 / 30", "HUD ammo text keeps its format (%s)" % hud.ammo_text())
	w.switch_to(&"scatter", true)
	w.ammo = 4
	await e.frames(2)
	TestLib.check(hud.weapon_text().contains("SHARD SCATTER") and hud.weapon_text().contains("RESERVE 36") and hud.ammo_text() == "4 / 6", "HUD: scatter, its reserve and 4 / 6 (%s | %s)" % [hud.weapon_text(), hud.ammo_text()])
	w.switch_to(&"lance", true)
	w.charge = 0.6
	TestLib.check(is_equal_approx(hud.weapon_charge(), 0.6), "HUD sees the lance charge")
	hud.free()
	await e.frames(2)
