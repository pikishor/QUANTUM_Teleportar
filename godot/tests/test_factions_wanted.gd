extends RefCounted
## FACTIONS and WANTED v2 (scripts/enemies/factions.gd, scripts/enemies/wanted.gd) in the REAL scene (main.tscn): territory per district, camps on spawned enemies (rim, speed, sight), allied camps
## stand about unaware until provoked, hostile camps see further, reputation from kills and jobs, prices / job availability / contract offers by standing, the save section (and a save
## without it), the patrol groups' camps, wanted responses by level (cars, roadblocks with guards, hunter drones, elite squad), the hide-and-lose modes (cover, interior, disguise, decoy,
## spotted = no hide), WANTED LOST, the reset, and the HUD plate. Progress writes to a throw-away file; waits are on state and ticks are driven by `Wanted.tick(delta)`.
## Not run: a phone, how the rim reads on the models.
## Run: tools/test.sh tests/test_factions_wanted.gd

const TMP := "user://test_factions_wanted_save.cfg"
const TOWERS := Vector3(120.0, 0.0, 120.0)     ## x >= 0, z >= 0: GLASS TOWERS (vael, drones)
const MARKET := Vector3(-120.0, 0.0, -120.0)   ## NEON MARKET (gang, vael)
const SLUMS := Vector3(-120.0, 0.0, 120.0)     ## RAIN SLUMS (drones, gang)

var host: Node
var main: Node
var prog: Progress
var p: Player
var hud: Hud
var em: EnemyManager
var w: Wanted


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	_pure()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 30)
	p = Game.player as Player
	prog = Game.progress as Progress
	em = Game.enemies as EnemyManager
	w = Wanted.current
	for n in main.find_children("*", "Hud", true, false):
		hud = n as Hud
	TestLib.check(p != null and prog != null and em != null and w != null and hud != null, "main.tscn composes the player, progress, enemies, Wanted and the HUD")
	if p == null or prog == null or em == null or w == null or hud == null:
		return
	prog.path = TMP
	prog.autosave_enabled = false
	prog.new_campaign()
	_camps()
	_patrol_groups()
	_standing()
	_economy()
	_save()
	await _responses()
	await _hiding()
	await _hud()
	Game.heat = 0.0
	em.clear()
	prog.new_campaign()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func _hdist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _at(pos: Vector3) -> void:
	p.global_position = Vector3(pos.x, 1.0, pos.z)


# --- pure rules -------------------------------------------------------------------------------------------------

func _pure() -> void:
	TestLib.check(Factions.IDS.size() == 3, "three factions")
	var primaries := {}
	for d in Factions.Districts.COUNT:
		primaries[Factions.primary(d)] = true
		TestLib.check(Factions.primary(d) != Factions.secondary(d), "district %d has two different camps" % d)
	TestLib.check(primaries.size() == 3, "every faction holds a district")
	for f: StringName in Factions.IDS:
		TestLib.check(Factions.TITLES.has(f) and Factions.COLORS.has(f) and Factions.BEHAVIOUR.has(f) and Factions.ELITES.has(f) and Factions.GUARD.has(f), "%s has title, colour, behaviour, elites and guard" % f)
		for t: StringName in Factions.ELITES[f]:
			TestLib.check(EnemyTypes.TYPES.has(t), "%s elite %s exists" % [f, t])
	TestLib.check(Factions.at(TOWERS) == &"vael" and Factions.at(MARKET) == &"gang" and Factions.at(SLUMS) == &"drones", "ground belongs to the district's primary camp")
	TestLib.check(Factions.camp_for(TOWERS, 0.1) == &"drones" and Factions.camp_for(TOWERS, 0.9) == &"vael", "a low roll takes the secondary camp")
	TestLib.check(Factions.status_of(0.0) == Factions.Status.NEUTRAL and Factions.status_of(-25.0) == Factions.Status.HOSTILE and Factions.status_of(40.0) == Factions.Status.ALLIED, "thresholds make hostile / neutral / allied")
	TestLib.check(Factions.assign(&"sentinel", MARKET) == &"drones" and Factions.assign(&"operative", SLUMS) == &"gang" and Factions.assign(&"operative", TOWERS) == &"vael" and Factions.assign(&"operative", MARKET, &"vael") == &"vael", "types take their camp")
	TestLib.check(Factions.fit_type(&"sentinel", &"vael") == &"operative" and Factions.fit_type(&"operative", &"drones") == &"sentinel" and Factions.fit_type(&"heavy", &"gang") == &"operative", "slots are fitted to the camp that fields them")
	TestLib.check(Factions.job_client(&"courier") == &"gang" and Factions.job_client(&"photo") == &"", "jobs have a client camp or none")
	TestLib.check(Wanted.level_of(0.0) == 0 and Wanted.level_of(0.1) == 1 and Wanted.level_of(2.0) == 2 and Wanted.level_of(2.01) == 3 and Wanted.level_of(5.0) == 5, "wanted level is the star count")
	for lv in range(1, Wanted.LEVELS + 1):
		for k: String in ["cars", "block", "drones", "elite"]:
			TestLib.check(int(Wanted.response(lv)[k]) >= int(Wanted.response(lv - 1)[k]), "response %s never shrinks at level %d" % [k, lv])
	TestLib.check(int(Wanted.response(1)["cars"]) == 0 and int(Wanted.response(2)["cars"]) > 0 and int(Wanted.response(3)["block"]) > 0 and int(Wanted.response(4)["drones"]) > 0 and int(Wanted.response(5)["elite"]) > 0, "each response arrives at its level")
	TestLib.check(Wanted.mode_for(3.0, 1, 9.0, 0.0, 0.0, true) == &"", "seen: nothing hides you")
	TestLib.check(Wanted.mode_for(3.0, 0, 3.5, 0.0, 0.0, false) == &"cover" and Wanted.mode_for(3.0, 0, 1.5, 0.0, 0.0, false) == &"", "cover needs LOS_BREAK seconds out of sight")
	TestLib.check(Wanted.mode_for(3.0, 0, 1.5, 0.0, 5.0, false) == &"disguise" and Wanted.mode_for(3.0, 0, 1.5, 0.0, 5.0, true) == &"decoy" and Wanted.mode_for(3.0, 2, 0.0, 2.0, 0.0, false) == &"interior" and Wanted.mode_for(0.0, 0, 9.0, 0.0, 0.0, false) == &"", "decoy, disguise and interior modes")
	TestLib.check(Wanted.rate_for(&"cover") < Wanted.rate_for(&"interior") and Wanted.rate_for(&"interior") < Wanted.rate_for(&"disguise") and Wanted.rate_for(&"disguise") < Wanted.rate_for(&"decoy"), "better hiding loses the heat faster")


# --- camps on enemies -------------------------------------------------------------------------------------------

func _camps() -> void:
	em.clear()
	Game.heat = 0.0
	_at(TOWERS)
	var a := em.spawn(&"operative", TOWERS + Vector3(20, 0, 0))
	var b := em.spawn(&"sentinel", TOWERS + Vector3(-20, 0, 0))
	var c := em.spawn(&"operative", MARKET + Vector3(20, 0, 0))
	TestLib.check(a != null and b != null and c != null, "enemies spawn")
	TestLib.check(a.camp == &"vael" and b.camp == &"drones" and c.camp == &"gang", "camps follow type and ground")
	TestLib.check(is_equal_approx(c.camp_speed, Factions.speed_mult(&"gang")) and c.camp_speed > a.camp_speed, "gangs run faster than Vael troopers")
	TestLib.check(is_equal_approx(b.aware_dist, Drone.AWARE_DIST * Factions.BEHAVIOUR[&"drones"]["sight"]), "drones sense further")
	TestLib.check(is_equal_approx(c.aware_dist, Drone.AWARE_DIST * Factions.BEHAVIOUR[&"gang"]["sight"]) and c.aware_dist < a.aware_dist, "gangs see less far than the Vael")
	var boss := em.spawn(&"overseer", TOWERS + Vector3(0, 0, 40))
	TestLib.check(boss == null or boss.camp == &"", "a boss belongs to no camp")
	em.clear()
	# an allied camp stands about unaware while the heat burns; a hit provokes it
	prog.faction_rep[&"vael"] = 60.0
	var al := em.spawn(&"operative", TOWERS + Vector3(15, 0, 0))
	TestLib.check(al.friendly and al.aware_dist == 0.0 and not al.aware, "an allied trooper starts unaware and blind")
	Game.heat = 2.0
	al.alert()
	al.friendly = true
	al.damage(1.0)
	TestLib.check(al.aware and not al.friendly, "a hit provokes an allied trooper")
	em.clear()
	# a hostile camp sees further
	prog.faction_rep[&"vael"] = -60.0
	var ho := em.spawn(&"operative", TOWERS + Vector3(15, 0, 0))
	TestLib.check(ho.aware_dist > Drone.AWARE_DIST and not ho.friendly, "a hostile trooper sees 1.4x as far")
	TestLib.check(Factions.extra_slots(prog, TOWERS) == 1 and Factions.extra_slots(prog, MARKET) == 0, "a hostile camp sends one more reinforcement on its own ground")
	em.clear()
	prog.faction_rep.clear()
	TestLib.check(Factions.extra_slots(prog, TOWERS) == 0, "neutral: no extra slot")
	# reinforcements: type fitted to the camp
	var camp_ok := true
	for i in 12:
		var t := Factions.fit_type(&"sentinel", &"vael", 0)
		camp_ok = camp_ok and not Factions.is_drone_type(t)
	TestLib.check(camp_ok, "a Vael slot never fields a drone")


func _patrol_groups() -> void:
	var groups := em.patrol_groups()
	TestLib.check(not groups.is_empty(), "the city has patrol groups")
	var ok := true
	for g: Dictionary in groups:
		var camp: StringName = g.get("camp", &"")
		ok = ok and Factions.is_camp(camp)
		for t: StringName in g["types"]:
			ok = ok and (Factions.is_drone_type(t) == (camp == Factions.DRONES))
	TestLib.check(ok, "every patrol group has a camp and fields only that camp's kind of enemy")


# --- reputation -------------------------------------------------------------------------------------------------

func _standing() -> void:
	prog.faction_rep.clear()
	em.clear()
	_at(MARKET)
	var g1 := em.spawn(&"operative", MARKET + Vector3(15, 0, 0))
	g1.die()
	TestLib.check(is_equal_approx(Factions.rep(prog, &"gang"), -Factions.KILL_PENALTY) and is_equal_approx(Factions.rep(prog, &"vael"), Factions.RIVAL_GAIN), "a kill costs the camp and pays its rival")
	prog.faction_rep[&"gang"] = 50.0
	var g2 := em.spawn(&"operative", MARKET + Vector3(-15, 0, 0))
	g2.die()
	TestLib.check(is_equal_approx(Factions.rep(prog, &"gang"), 50.0 - Factions.KILL_PENALTY_ALLIED), "killing an ally costs far more")
	em.clear()
	Factions.add_rep(prog, &"drones", 500.0)
	TestLib.check(Factions.rep(prog, &"drones") == Factions.REP_MAX, "reputation is clamped")
	Factions.add_rep(prog, &"drones", -500.0)
	TestLib.check(Factions.rep(prog, &"drones") == Factions.REP_MIN and Factions.status(prog, &"drones") == Factions.Status.HOSTILE, "and hostile at the floor")


func _economy() -> void:
	prog.faction_rep.clear()
	_at(TOWERS)
	var base := prog.price(&"damage")
	prog.faction_rep[&"vael"] = 60.0
	var cheap := prog.price(&"damage")
	var cheap_w := prog.weapon_price(&"marksman")
	prog.faction_rep[&"vael"] = -60.0
	var dear := prog.price(&"damage")
	TestLib.check(cheap < base and base < dear, "shop prices: allied cheaper, hostile dearer (%d < %d < %d)" % [cheap, base, dear])
	prog.faction_rep.clear()
	TestLib.check(cheap_w < prog.weapon_price(&"marksman"), "weapons follow the same factor")
	_at(MARKET)
	prog.faction_rep[&"vael"] = -60.0
	TestLib.check(prog.price(&"damage") == base, "another district's camp does not touch the price")
	# jobs
	prog.faction_rep.clear()
	var sm := (Game.missions as Missions).sides
	Game.state = &"play"
	TestLib.check(sm != null and sm.can_start(&"courier"), "a neutral client leaves the job open")
	prog.faction_rep[&"gang"] = -60.0
	TestLib.check(not sm.can_start(&"courier") and sm.can_start(&"photo") == Factions.job_open(prog, &"photo"), "a hostile client closes its jobs, others stay open")
	prog.faction_rep.clear()
	prog.faction_rep[&"gang"] = 60.0
	prog.credits = 0
	var rep0 := Factions.rep(prog, &"gang")
	prog.complete_side(&"courier", 200, 3, 30.0)
	TestLib.check(prog.credits == 230 and Factions.rep(prog, &"gang") > rep0, "an allied client pays 15 % more and a finished job raises its standing")
	prog.faction_rep.clear()
	prog.credits = 0
	prog.complete_side(&"courier", 200, 3, 30.0)
	TestLib.check(prog.credits == 200 and is_equal_approx(Factions.rep(prog, &"gang"), Factions.JOB_REP), "neutral: plain pay, +5 standing")
	# contracts
	TestLib.check(Factions.contracts_open(prog, MARKET), "contracts open on neutral ground")
	prog.faction_rep[&"gang"] = -60.0
	TestLib.check(not Factions.contracts_open(prog, MARKET) and Factions.contracts_open(prog, TOWERS), "no contract offers on hostile ground")
	var ct := (Game.missions as Missions).contracts
	if ct != null:
		_at(MARKET)
		TestLib.check(not ct._can_offer(), "Contracts._can_offer refuses on hostile ground")
		_at(TOWERS)
		prog.faction_rep.clear()
	prog.faction_rep.clear()


func _save() -> void:
	prog.faction_rep.clear()
	prog.faction_rep[&"vael"] = -33.5
	prog.faction_rep[&"drones"] = 71.0
	TestLib.check(prog.save_file(), "the save is written")
	prog.faction_rep.clear()
	TestLib.check(prog.load_file() and is_equal_approx(Factions.rep(prog, &"vael"), -33.5) and is_equal_approx(Factions.rep(prog, &"drones"), 71.0) and Factions.rep(prog, &"gang") == 0.0, "standing round-trips through the [faction] section")
	var cf := ConfigFile.new()
	cf.load(TMP)
	if cf.has_section("faction"):
		cf.erase_section("faction")
	cf.save(TMP)
	prog.faction_rep[&"gang"] = 5.0
	TestLib.check(prog.load_file() and prog.faction_rep.is_empty(), "a save without the section loads all neutral")
	cf.set_value("faction", "rep_vael", 9999.0)
	cf.set_value("faction", "rep_gang", "junk")
	cf.save(TMP)
	TestLib.check(prog.load_file() and Factions.rep(prog, &"vael") == Factions.REP_MAX and Factions.rep(prog, &"gang") == 0.0, "a damaged section is clamped and sanitised")
	prog.new_campaign()
	TestLib.check(prog.faction_rep.is_empty(), "a new campaign resets standing")


# --- wanted responses -------------------------------------------------------------------------------------------

func _drain(max_steps := 30) -> void:
	for i in max_steps:
		if w.dispatch() == &"":
			return


func _responses() -> void:
	em.clear()
	Game.state = &"play"
	w.reset()
	_at(TOWERS)
	await TestLib.frames(host, 3)
	Game.heat = 1.0
	TestLib.check(w.dispatch() == &"", "level 1: no extra response")
	Game.heat = 3.0
	_drain()
	TestLib.check(w.live(&"drone") == 0 and w.live(&"elite") == 0, "level 3 sends no drones or elite squad")
	var blocks := w.live(&"block")
	TestLib.check(blocks >= 1 and blocks <= int(Wanted.response(3)["block"]), "level 3: a roadblock stands (%d)" % blocks)
	var block_node: Node3D = null
	for b in w._blocks:
		if b.visible:
			block_node = b
	TestLib.check(block_node != null and (block_node as StaticBody3D).collision_layer == Game.L_WORLD and _hdist(block_node.global_position, p.global_position) >= Wanted.BLOCK_MIN - 5.0, "the barrier blocks the world layer on a road ahead")
	TestLib.check(w._guards.size() >= 1 and w._guards[0].camp == &"vael" and w._guards[0].reinforce, "its guards are reinforcements of the ground's camp")
	var cars := w.live(&"car")
	TestLib.check(cars <= int(Wanted.response(3)["cars"]), "level 3: at most one patrol car (%d)" % cars)
	Game.heat = 5.0
	_drain()
	var want := Wanted.response(5)
	TestLib.check(w.live(&"drone") >= 1 and w.live(&"drone") <= int(want["drones"]), "level 5: hunter drones fly in (%d)" % w.live(&"drone"))
	TestLib.check(w.live(&"elite") >= 1 and w.live(&"elite") <= int(want["elite"]), "level 5: an elite squad arrives (%d)" % w.live(&"elite"))
	TestLib.check(w.live(&"block") <= int(want["block"]) and w.live(&"car") <= int(want["cars"]), "responses stay within the level's allowance")
	var elite_ok := true
	for e in w._elite:
		elite_ok = elite_ok and e.aware and e.reinforce and (Factions.ELITES[&"vael"].has(e.type) or e.type == &"operative")
	TestLib.check(elite_ok, "the squad is made of the camp's elite types")
	TestLib.check(em.alive_count() <= em.cap(), "the enemy cap holds")
	# slums: drone ground answers with drones
	em.clear()
	w.reset()
	_at(SLUMS)
	Game.heat = 5.0
	_drain()
	var drone_squad := true
	for e in w._elite:
		drone_squad = drone_squad and e.camp == &"drones"
	TestLib.check(drone_squad, "on drone ground the elite squad is rogue drones")
	# stand-down: blocks return to the pool
	Game.heat = 0.0
	w._release_far()
	TestLib.check(w.live(&"block") == 0, "roadblocks return to the pool below level 3")
	# reset on respawn
	Game.heat = 5.0
	w.dispatch()
	Game.respawn.emit()
	TestLib.check(w.last_level == 0 and w.live(&"block") == 0 and w._drones.is_empty(), "a respawn resets the wanted state")
	Game.heat = 0.0
	em.clear()


# --- hide and lose ----------------------------------------------------------------------------------------------

func _hiding() -> void:
	em.clear()
	Game.state = &"play"
	_at(TOWERS)
	await TestLib.frames(host, 3)
	w.reset()
	Game.heat = 3.0
	w._watch_t = 0.0
	var lost0 := w.lost_count
	# seen: no hiding
	var seer := em.spawn(&"operative", p.global_position + Vector3(10, 0, 0), true, true)
	seer.los = true
	w._watch_t = 0.0
	w.tick(0.3)
	TestLib.check(w.watchers == 1 and w.hide_mode == &"" and w.hidden_t == 0.0 and w.state_label().begins_with("SPOTTED"), "an enemy with line of sight: SPOTTED, nothing hides you")
	seer.los = false
	em.clear()
	# break line of sight: cover after LOS_BREAK seconds
	w.reset()
	Game.heat = 3.0
	w._watch_t = 0.0
	w.tick(0.3)
	TestLib.check(w.watchers == 0 and w.hide_mode == &"" and w.state_label() == "SEARCHING", "out of sight at first: SEARCHING")
	w.tick(Wanted.LOS_BREAK)
	TestLib.check(w.hide_mode == &"cover" and w.state_label() == "HIDDEN", "after LOS_BREAK seconds out of sight: HIDDEN")
	var h0 := Game.heat
	w.tick(1.0)
	TestLib.check(h0 - Game.heat >= Wanted.rate_for(&"cover") * 0.99, "cover loses heat (%.3f)" % (h0 - Game.heat))
	var cover_drop := h0 - Game.heat
	# dispatch stops while hidden
	var sent := int(w.dispatched[&"elite"]) + int(w.dispatched[&"drone"]) + int(w.dispatched[&"block"])
	Game.heat = 5.0
	w.hidden_t = Wanted.LOS_BREAK + 1.0
	w._dispatch_t = 0.0
	w.tick(0.1)
	TestLib.check(int(w.dispatched[&"elite"]) + int(w.dispatched[&"drone"]) + int(w.dispatched[&"block"]) == sent, "nothing is dispatched while hidden")
	em.clear()
	# disguise: changed vehicle (a real car when the starter exists, else a vehicle id change)
	w.reset()
	Game.heat = 3.0
	var vm := Game.vehicles as VehicleManager
	var car: Vehicle = vm.starter if vm != null else null
	var entered := false
	if car != null and car.active and not car.dead:
		car.global_position = p.global_position + Vector3(3, 0, 0)
		vm.enter(car)
		entered = p.vehicle != null
	if not entered:
		w._veh_id = 424242
	w._watch_t = 0.0
	w.tick(0.3)
	TestLib.check(w._disguise_t > 0.0, "changing vehicle starts a disguise (%s)" % ("real car" if entered else "id change"))
	w.tick(1.5)
	TestLib.check(w.hide_mode == &"disguise" and w.state_label() == "DISGUISED", "out of sight in the new vehicle: DISGUISED")
	var h1 := Game.heat
	w.tick(1.0)
	var disguise_drop := h1 - Game.heat
	TestLib.check(disguise_drop >= Wanted.rate_for(&"disguise") * 0.99 and disguise_drop > cover_drop, "a disguise loses heat faster than cover")
	if entered:
		vm.exit_vehicle()
		await TestLib.frames(host, 2)
	# interior
	w.reset()
	Game.heat = 3.0
	InteriorGameplay.active = true
	w._watch_t = 0.0
	w.tick(0.6)
	w.tick(0.6)
	var interior_ok := w.hide_mode == &"interior"
	var h2 := Game.heat
	w.tick(1.0)
	var interior_drop := h2 - Game.heat
	InteriorGameplay.active = false
	TestLib.check(interior_ok and interior_drop >= Wanted.rate_for(&"interior") * 0.99, "inside a room: INSIDE, fast loss")
	# decoy
	w.reset()
	em.clear()
	Game.heat = 3.0
	var q := p.quantum
	var have_clone := false
	if q != null:
		p.energy = p.max_energy
		q.cd_super = 0.0
		have_clone = q.clone != null or q.superpose()
	if have_clone:
		await TestLib.frames(host, 2)                            # the manager caches the clone per physics frame
		em.clear()                                               # the live wanted tick may have dispatched sighted reinforcements meanwhile
		var pursuer := em.spawn(&"operative", q.clone.global_position + Vector3(8, 0, 0), true, true)
		pursuer.los = false
		w._watch_t = 0.0
		w.tick(0.3)
		pursuer.los = false
		w._watch_t = 0.0
		w.tick(1.2)
		TestLib.check(w.hide_mode == &"decoy" and w.state_label() == "DECOY" and w.decoys_used >= 1, "aware enemies near a SUPERPOSITION clone: DECOY")
		var h3 := Game.heat
		pursuer.los = false
		w._watch_t = 0.0
		w.tick(1.0)
		TestLib.check(h3 - Game.heat >= Wanted.rate_for(&"decoy") * 0.99, "the decoy loses heat fastest")
		q.collapse()
	else:
		TestLib.check(true, "no clone available in this sandbox (decoy rule covered by mode_for)")
	em.clear()
	# lose it
	w.reset()
	Game.heat = 0.2
	w._was_hot = true
	InteriorGameplay.active = true
	w._watch_t = 0.0
	w.tick(0.6)
	w.tick(2.0)
	InteriorGameplay.active = false
	TestLib.check(Game.heat <= 0.0 and w.lost_count == lost0 + 1 and w.hide_mode == &"", "heat reaching zero from above counts a WANTED LOST")
	em.clear()
	Game.heat = 0.0


# --- HUD ---------------------------------------------------------------------------------------------------------

func _hud() -> void:
	Game.state = &"play"
	_at(TOWERS)
	prog.faction_rep.clear()
	await TestLib.frames(host, 3)
	Game.heat = 0.0
	var t := hud.wanted_tag()
	TestLib.check(not t.is_empty() and String(t["faction"]).begins_with("VAEL") and String(t["faction"]).ends_with("NEUTRAL") and String(t["wanted"]) == "", "the plate names the ground's camp and standing")
	prog.faction_rep[&"vael"] = 60.0
	TestLib.check(String(hud.wanted_tag()["faction"]).ends_with("ALLIED"), "standing shows as ALLIED")
	prog.faction_rep[&"vael"] = -60.0
	TestLib.check(String(hud.wanted_tag()["faction"]).ends_with("HOSTILE"), "standing shows as HOSTILE")
	Game.heat = 2.5
	w.reset()
	w._watch_t = 0.0
	w.tick(0.3)
	TestLib.check(String(hud.wanted_tag()["wanted"]).begins_with("SEARCHING") and String(hud.wanted_tag()["wanted"]).ends_with("L3"), "while the heat burns the plate shows the state and the level")
	for vp in [Vector2(844, 390), Vector2(1280, 720)]:
		var s := UiUtil.ui_scale(vp)
		var top := UiUtil.insets_v(vp).x + 6.0 * s
		var r := hud.wanted_rect(vp, s, top)
		var heat_left: float = vp.x - UiUtil.insets(vp).y - 16.0 * s - 196.0 * s
		TestLib.check(r.position.x >= 0.0 and r.end.x < heat_left and r.size.x > 0.0 and r.end.y <= vp.y, "the plate fits beside the heat plate at %dx%d" % [int(vp.x), int(vp.y)])
		var centre_right: float = vp.x * 0.5 + (UiUtil.insets(vp).y * 0.0 + (Hud.LABEL_W + 8.0 + Hud.VALUE_W + 8.0 + Hud.BAR_W) * 0.5 + 10.0) * s
		TestLib.check(r.position.x >= centre_right - 4.0 * s, "and clears the bars plate at %dx%d" % [int(vp.x), int(vp.y)])
	await TestLib.frames(host, 3)
	Game.heat = 0.0
	prog.faction_rep.clear()
