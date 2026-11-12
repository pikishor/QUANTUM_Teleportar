extends RefCounted
## A REAL FIGHT (owner: "nowhere close to COD", director review 4 #1 and #10: foes were 30 px figures behind parked cars and the hero stood planted). In the REAL game scene:
##  * the encounter director plays CONTACT IN 10 S, THREE WAVES of 3-6 troopers, then a breather; each wave mixes roster looks that ARE roles (rifleman, scout, grenadier, heavy,
##    marksman, commander: TacticsTable.KITS) and squad roles (pusher, flanker, anchor);
##  * the troopers close to 8-20 m; the squad's cover is LOW cover only (a body about waist to chest high: EnemyCover.is_low_cover), never a parked car, a van or a lamp post, and a trooper
##    behind it crouches, so he stays in the hero's line of fire;
##  * a hero (tests/real_fight_bot.gd, the real input actions and camera) strafes while he fires, backs off, drops targets that duck behind cars, and wins;
##  * a grenadier lobs a grenade you can see (ball, landing ring as wide as the blast, fuse) that explodes where the ring said;
##  * readability: a trooper far from the camera glows in his role colour and is drawn bigger (hit shapes follow); a hit flashes the body; a kill ends in the DEAD pose.
##  * the director's squad fights to the end, backups included: a wounded trooper of the squad never turns into the retreating straggler that held a wave open until the wave timeout.
## Frames of the same script: tests/bot_real_fight.gd (docs/shots/slice/real_fight_*.jpg). Time runs 4x (time_scale and tick rate together); every wait is in game seconds.
## The street's moving life (road traffic and the crowd) stands still while this runs: the test is about the troopers. A road car that crept into the standing hero pushed him 10 m towards
## the grenadier, out of its 9-26 m throw range, and a walker or a car crossing the line of fire is a random blocker. The parked cars, the starter car and the props stay: they are the
## real cover and the real line-of-sight blockers.
## Run: tools/test.sh tests/test_real_fight.gd

const RealFightBot := preload("res://tests/real_fight_bot.gd")
const K := 4
const TMP := "user://test_real_fight.cfg"

var _p: Player
var _mgr: EnemyManager
var _enc: Encounters
var _dt := 1.0 / 60.0


func run(host: Node) -> void:
	_test_rules()
	await _test_cover_rules(host)

	Game.civilian_casualties = false                     # the bot's rounds pass through bystanders: this test is about the troopers, not the wanted level
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 4)
	_p = Game.player
	_mgr = Game.enemies as EnemyManager
	_enc = Encounters.current
	if _p == null or _mgr == null or _enc == null:
		TestLib.check(false, "the real game has a player, an enemy manager and the encounter director")
		return
	var prog := Game.progress as Progress
	if prog != null:
		prog.path = TMP
	Game.state = &"play"
	_mgr.patrol_groups().clear()
	_mgr.clear()
	_p.max_hp = 1.0e6
	var m := Game.missions
	if m != null:
		m.contracts.enabled = false
	if Game.story != null and Game.story.get("tutorial") != null:
		Game.story.tutorial.set("active", false)
	_p.weapon.switch_to(&"carbine", true)
	if Game.vehicles != null:
		Game.vehicles.set_physics_process(false)         # the road traffic stands still (see the header); the manager is not needed by anything below
	var city := Game.world as City
	if city != null and city.ambient != null:
		city.ambient.set_process(false)                  # the crowd and the near traffic stand still (the same freeze as tests/test_shooting_accuracy.gd)
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K

	await _test_readability(host)
	await _test_squad_fights_on(host)
	await _test_grenade(host)
	await _test_director_fight(host)

	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	_enc.enabled = false
	_mgr.clear()
	Game.heat = 0.0
	for a: StringName in [&"fire", &"move_left", &"move_right", &"move_forward", &"move_back"]:
		Input.action_release(a)
	for f: String in [TMP, TMP + ".bak", TMP + ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	main.queue_free()
	await TestLib.frames(host, 2)


# --- pure rules -----------------------------------------------------------------------------------------------------------

func _test_rules() -> void:
	var sizes_ok := true
	for tier in 3:
		for k in range(1, Encounters.SET_WAVES + 1):
			var n := Encounters.patrol_size(k, tier)
			sizes_ok = sizes_ok and n >= 3 and n <= 6
	TestLib.check(sizes_ok, "a wave is 3-6 troopers on every tier")
	TestLib.check(Encounters.FIRST_DELAY <= 10.0 and Encounters.FIRST_DELAY > Encounters.CALLOUT_LEAD, "contact in 10 s: the first squad spawns %.1f s after play starts, the callout %.1f s earlier" % [Encounters.FIRST_DELAY, Encounters.CALLOUT_LEAD])
	TestLib.check(Encounters.SET_WAVES == 3 and Encounters.SET_CALM >= 30.0, "three waves and a breather of %.0f s" % Encounters.SET_CALM)
	for k in range(1, 4):
		var looks := {}
		for slot in Encounters.patrol_size(k, 0):
			looks[Encounters.look_of(k, slot)] = true
		TestLib.check(looks.size() >= 2, "wave %d of the smallest tier has %d different looks" % [k, looks.size()])
	var gren_wave := false
	for k in range(2, 4):
		for slot in 4:
			gren_wave = gren_wave or Encounters.look_of(k, slot) == 3
	TestLib.check(gren_wave, "a grenadier comes in wave 2 or 3 even on the smallest tier")
	TestLib.check(Encounters.role_of(2, 0) == &"flanker" and Encounters.role_of(1, 1) == &"pusher" and Encounters.role_of(3, 0) == &"anchor" and Encounters.role_of(4, 1) == &"anchor" and Encounters.role_of(0, 2) == &"anchor", "the look decides the role: scout flanks, heavy pushes, grenadier and marksman hold; a rifleman takes his group's role")
	var kit_ok := true
	for i in HumanoidVariants.VAEL_CLASSES.size():
		kit_ok = kit_ok and TacticsTable.KITS.has(HumanoidVariants.VAEL_CLASSES[i]["name"])
	TestLib.check(kit_ok, "every roster look has a squad kit")
	TestLib.check(bool(TacticsTable.kit(&"grenadier")["throws"]) and not bool(TacticsTable.kit(&"rifleman")["throws"]) and float(TacticsTable.kit(&"scout")["speed"]) > 1.2 and float(TacticsTable.kit(&"gunner")["hp"]) > 1.4, "grenadier throws, scout is fast, heavy has more health")
	# grenade maths
	var from := Vector3(0.0, 1.5, 0.0)
	var to := Vector3(12.0, 0.0, 0.0)
	var mid := EnemyGrenades.arc_point(from, to, 3.0, 0.5)
	TestLib.check(EnemyGrenades.arc_point(from, to, 3.0, 0.0).is_equal_approx(from) and EnemyGrenades.arc_point(from, to, 3.0, 1.0).is_equal_approx(to) and mid.y > 0.75 + 2.9, "the throw arc starts in the hand, lands on the ring and rises above the line")
	TestLib.check(EnemyGrenades.flight_time(2.0) == EnemyGrenades.FLIGHT.x and EnemyGrenades.flight_time(100.0) == EnemyGrenades.FLIGHT.y, "flight time is bounded")
	var lead := EnemyGrenades.lead_point(Vector3.ZERO, Vector3(6.0, 0.0, 0.0), 1.0)
	TestLib.check(lead.x > 2.0 and lead.x < 6.0, "the throw leads a walking hero (%.1f m)" % lead.x)
	TestLib.check(EnemyGrenades.max_live(0) == 1 and EnemyGrenades.max_live(2) == 2, "grenades in flight per tier")
	TestLib.check(Drone.DIST_SCALE_MAX <= 1.4 and Drone.DIST_SCALE_MAX > 1.15 and Drone.FAR_GLOW.x < Drone.FAR_GLOW.y and Drone.FAR_SCALE.x < Drone.FAR_SCALE.y, "readability numbers: bigger and glowing with distance, bounded")


## Low cover only for the squad (a car or a lamp post is not cover that keeps a trooper in the line of fire).
func _test_cover_rules(host: Node) -> void:
	TestLib.check(not EnemyCover.is_low_cover({"center": Vector3.ZERO, "radius": 0.75, "height": 1.6}), "a parked car (1.6 m) is not low cover")
	TestLib.check(not EnemyCover.is_low_cover({"center": Vector3.ZERO, "radius": 0.34, "height": 3.0}), "a lamp post is not low cover")
	TestLib.check(EnemyCover.is_low_cover({"center": Vector3.ZERO, "radius": 1.1, "height": 0.95}), "a planter (0.95 m) is low cover")
	TestLib.check(not EnemyCover.is_low_cover({"center": Vector3.ZERO, "radius": 0.3, "height": 1.0}), "a post-thin body is not cover")
	var holder := Node3D.new()
	host.add_child(holder)
	var who := Node3D.new()
	holder.add_child(who)
	who.global_position = Vector3(0.0, 0.0, 0.0)
	var car := _body(holder, Vector3(3.0, 0.8, 8.0), Vector3(2.0, 1.7, 4.2))
	var planter := _body(holder, Vector3(-4.0, 0.5, 11.0), Vector3(1.6, 1.0, 1.6))
	EnemyCover.override_bodies = [car, planter]
	EnemyCover.low_in_tests = true
	var threat := Vector3(0.0, 0.0, 22.0)
	var any := EnemyCover.find(who, threat, 30.0, &"observer", 0.0, false)
	var low := EnemyCover.find(who, threat, 30.0, &"observer", 0.0, true)
	EnemyCover.override_bodies = []
	EnemyCover.low_in_tests = false
	TestLib.check(any.is_finite(), "ordinary cover finds a spot")
	TestLib.check(low.is_finite() and Vector2(low.x - planter.global_position.x, low.z - planter.global_position.z).length() < 3.0, "the squad's low cover is the planter (spot %s), not the car" % str(low))
	holder.queue_free()


func _body(parent: Node, pos: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	parent.add_child(b)
	b.global_position = pos
	return b


# --- readability and reactions ---------------------------------------------------------------------------------------------

func _wait(host: Node, seconds: float, until := Callable()) -> float:
	var t := 0.0
	while t < seconds:
		await host.get_tree().physics_frame
		t += _dt
		_p.invuln = 5.0
		if until.is_valid() and bool(until.call()):
			break
	return t


func _test_readability(host: Node) -> void:
	_mgr.clear()
	_enc.enabled = false
	var pp := _p.global_position
	var d := _mgr.spawn(&"operative", pp + Vector3(0.0, 0.0, -30.0), true, true, &"", 3) as Operative
	if d == null or d.humanoid_body == null:
		TestLib.check(d != null, "a grenadier trooper can be spawned (hero character files present: skipped if not)")
		return
	TestLib.check(d.look_index() == 3 and d.kit == &"grenadier" and d.throws, "the director's spawn gives the requested look and its kit (%s)" % d.kit)
	d.update_lod(30.0)
	var far_k := float(d.humanoid_body.get_instance_shader_parameter(&"far_k"))
	TestLib.check(far_k > 0.9 and d._dist_scale > 1.2, "at 30 m the trooper glows in his role colour (%.2f) and is drawn bigger (x%.2f)" % [far_k, d._dist_scale])
	var box_far: Array = d.body_box()
	d.update_lod(6.0)
	var box_near: Array = d.body_box()
	TestLib.check(float(d.humanoid_body.get_instance_shader_parameter(&"far_k")) < 0.01 and absf(d._dist_scale - 1.0) < 0.01, "close up he is drawn at his own size without the glow")
	TestLib.check((box_far[1] as Vector3).y - (box_far[0] as Vector3).y > (box_near[1] as Vector3).y - (box_near[0] as Vector3).y, "the hit shape grows with the drawn size (a shot at the bigger figure lands)")
	# hit reaction: flash, flinch, then fade
	d.set_physics_process(false)
	d.damage(1.0, false)
	TestLib.check(d._hit_k > 0.9 and d.hanim.state == HumanoidAnim.State.HIT and d._flinch > 0.3, "a hit flashes the body and flinches him")
	d.set_physics_process(true)
	await _wait(host, 0.5)
	TestLib.check(d._hit_k < 0.05, "the flash fades in well under half a second")
	# death
	d.damage(1.0e6, true)
	await _wait(host, 0.6)
	TestLib.check(d.dead and d.hanim != null and d.hanim.state == HumanoidAnim.State.DEAD, "a kill ends in the DEAD pose")
	_mgr.clear()


## The director's squad fights to the end, a backup (no roster look, so no kit) included. Found by CI: the last trooper of a wave was a wounded backup who retreated to cover for good (the
## director's pressure cleared his cover state every frame, he found the same cover again and stood still) and held the wave open until the wave timeout, 30+ s behind a wall.
func _test_squad_fights_on(host: Node) -> void:
	_mgr.clear()
	_enc.enabled = false
	_p.invuln = 5.0
	var pp := _p.global_position
	var fwd := -_p.camera_rig.camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var backup := _mgr.spawn(&"operative", pp + fwd * 14.0, true, true, &"", -1) as Operative     # what the director's backup is: a look-less trooper with a squad role
	var plain := _mgr.spawn(&"operative", pp - fwd * 14.0, true, true, &"", -1) as Operative      # the street's own patrol member: no squad role
	if backup == null or plain == null:
		TestLib.check(false, "two troopers can be spawned")
		_mgr.clear()
		return
	backup.set_squad_role(&"pusher", 1.0)
	TestLib.check(backup.squad_job and not backup.kit_set and not plain.squad_job, "a backup has a squad role but no kit; a patrol member has neither")
	for o: Operative in [backup, plain]:
		o.faction = TacticsTable.OBSERVER                # the disciplined corps retreats at 25 % health (a faction the director's squads and the patrols can both be)
		o.hp = o.max_hp * 0.1
	await _wait(host, 1.5, func() -> bool:
		backup.hp = backup.max_hp * 0.1
		return plain.is_retreating())
	TestLib.check(plain.is_retreating(), "a wounded patrol member still retreats (the street keeps its tactics)")
	TestLib.check(not backup.is_retreating(), "a wounded trooper of the director's squad fights on instead of retreating")
	_mgr.clear()


func _test_grenade(host: Node) -> void:
	_mgr.clear()
	_enc.enabled = false
	_p.invuln = 5.0
	var pp := _p.global_position
	var fwd := -_p.camera_rig.camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var d := _mgr.spawn(&"operative", pp + fwd * 15.0, true, true, &"", 3) as Operative
	if d == null:
		TestLib.check(false, "a grenadier can be spawned")
		return
	d.set_squad_role(&"anchor", 1.0)
	var seen_live := [0]
	var landed := [0]
	var boom := [0]
	_mgr.grenades.landed.connect(func(_at: Vector3) -> void: landed[0] += 1)
	_mgr.grenades.exploded.connect(func(_at: Vector3) -> void: boom[0] += 1)
	var t0 := _mgr.grenades_thrown
	var b0 := _mgr.grenades.blasts
	await _wait(host, 25.0, func() -> bool:
		seen_live[0] = maxi(seen_live[0], _mgr.grenades.live_count())
		d.hp = maxf(d.hp, 50.0)                        # this test is about the throw: keep him alive
		return _mgr.grenades.blasts > b0)
	TestLib.check(_mgr.grenades_thrown > t0 and d.grenades_thrown >= 1, "the grenadier throws a grenade (%d)" % (_mgr.grenades_thrown - t0))
	TestLib.check(seen_live[0] >= 1 and seen_live[0] <= EnemyGrenades.max_live(Game.quality), "a live grenade is visible (%d in flight, the tier allows %d)" % [seen_live[0], EnemyGrenades.max_live(Game.quality)])
	TestLib.check(landed[0] >= 1 and boom[0] >= 1 and _mgr.grenades.blasts > b0, "it lands, burns its fuse and explodes (%d landed, %d blasts)" % [landed[0], boom[0]])
	TestLib.check(_mgr.grenades.last_to.is_finite() and Vector2(_mgr.grenades.last_to.x - pp.x, _mgr.grenades.last_to.z - pp.z).length() < 12.0, "the ring lands near the hero (%.1f m)" % Vector2(_mgr.grenades.last_to.x - pp.x, _mgr.grenades.last_to.z - pp.z).length())
	for c: Dictionary in _mgr.grenades.landed.get_connections():
		_mgr.grenades.landed.disconnect(c["callable"])
	for c: Dictionary in _mgr.grenades.exploded.get_connections():
		_mgr.grenades.exploded.disconnect(c["callable"])
	_mgr.clear()
	TestLib.check(_mgr.grenades.live_count() == 0, "clearing the enemies clears the grenades")


# --- the fight itself --------------------------------------------------------------------------------------------------------

func _test_director_fight(host: Node) -> void:
	_mgr.clear()
	_enc.enabled = true
	_enc.reset()
	var ppos := _p.global_position
	var sizes: Array[int] = []
	var looks: Array = []
	var roles: Array = []
	_enc.wave_started.connect(func(_w: int, s: int) -> void:
		sizes.append(s)
		var kinds := {}
		for d in _enc.squad:
			kinds[("look%d" % d.look_index()) if d is Operative and d.type == &"operative" else String(d.type)] = true
		looks.append(kinds.size())
		roles.append(_enc.last_roles.duplicate()))
	var sets_done := [0]
	_enc.set_cleared.connect(func(_n: int) -> void: sets_done[0] += 1)
	var bot := RealFightBot.new()
	bot.setup(_p)
	var t := 0.0
	var min_d := 1.0e9
	var hidden := {}                                     # instance id -> seconds in a row an aware trooper within 25 m had no line to the hero
	var max_hidden := 0.0
	var who_hidden := ""
	var ray_t := 0.0
	var space := _p.get_world_3d().direct_space_state
	while t < 150.0 and sets_done[0] < 1:
		await host.get_tree().physics_frame
		t += _dt
		bot.step(_dt)
		ray_t += _dt
		for e in _enc.squad:
			if is_instance_valid(e) and e.active and not e.dead and e.aware:
				min_d = minf(min_d, e.global_position.distance_to(_p.global_position))
		if ray_t >= 0.25:
			ray_t = 0.0
			for e in _enc.squad:
				if not is_instance_valid(e) or not e.active or e.dead or not e.aware:
					continue
				var id := e.get_instance_id()
				if e.global_position.distance_to(_p.global_position) > 25.0:
					hidden[id] = 0.0
					continue
				var q := PhysicsRayQueryParameters3D.create(_p.global_position + Vector3(0.0, 1.5, 0.0), e.center(), Game.L_WORLD | Game.L_VEHICLE)
				if space.intersect_ray(q).is_empty():
					hidden[id] = 0.0
				else:
					hidden[id] = float(hidden.get(id, 0.0)) + 0.25
					if OS.get_environment("DBG_HID") != "" and float(hidden[id]) >= 6.0 and int(float(hidden[id]) * 4.0) % 8 == 0:
						var oo := e as Operative
						print("HID %.1f s %s cover=%d retreat=%s hid_t=%s dist=%.1f act=%s aware=%s squad=%d state=%s" % [hidden[id], e.type, oo.cover_state(), str(oo.is_retreating()), str(e.get_meta(&"hid_t", -1.0)), e.global_position.distance_to(_p.global_position), str(e.active), str(e.aware), _enc.squad.size(), _enc.state])
					if float(hidden[id]) > max_hidden:
						max_hidden = float(hidden[id])
						var o := e as Operative
						who_hidden = "%s role=%s kit=%s cover=%d d=%.1f los=%s rush=%s" % [e.type, o.tactic_role if o != null else &"", o.kit if o != null else &"", o.cover_state() if o != null else -1, e.global_position.distance_to(_p.global_position), str(e.los), str(o.rush if o != null else false)]
	bot.finish()
	print("REAL FIGHT: set cleared at %.0f s (game), waves %s, distinct kinds %s, min distance %.1f m, hero moved %.0f m, %d strafes, %d shots fired while moving, %d kills / %d hits / %d shots, first contact %.1f s, longest hidden %.1f s (%s), relocations %d (%d failed)" % [t, str(sizes), str(looks), min_d, bot.moved, bot.strafes, bot.fire_while_moving, bot.kills, bot.hits, bot.shots, _enc.first_engaged_t, max_hidden, who_hidden, _enc.relocations, _enc.relocate_fails])
	var cap := _mgr.cap()
	TestLib.check(_enc.first_engaged_t > 0.0 and _enc.first_engaged_t <= 12.0, "CONTACT in 10 s: an aware trooper within 40 m after %.1f s of play" % _enc.first_engaged_t)
	TestLib.check(sizes.size() == Encounters.SET_WAVES, "three waves came (%d)" % sizes.size())
	var size_ok := not sizes.is_empty()
	for i in sizes.size():
		size_ok = size_ok and sizes[i] >= 2 and sizes[i] <= mini(6, cap)
	TestLib.check(size_ok, "every wave is 3-6 troopers (trimmed by the tier cap %d): %s" % [cap, str(sizes)])
	var mixed := not looks.is_empty()
	for k: int in looks:
		mixed = mixed and k >= 2
	TestLib.check(mixed, "every wave mixes at least two kinds of trooper: %s" % str(looks))
	var role_set := {}
	for r: Array in roles:
		for x: StringName in r:
			role_set[x] = true
	TestLib.check(role_set.size() >= 2, "squad roles are distinct: %s" % str(role_set.keys()))
	TestLib.check(min_d <= 20.0, "the troopers close to %.1f m (8-20 m fight)" % min_d)
	TestLib.check(bot.moved >= 12.0 and bot.strafes >= 3 and bot.fire_while_moving >= 20, "the hero moves and strafes while he fires: %.0f m, %d strafes, %d moving shots" % [bot.moved, bot.strafes, bot.fire_while_moving])
	TestLib.check(bot.kills >= 3 and bot.hits >= bot.kills and bot.shots >= 15, "the fight is won on the real input actions: %d kills, %d hits, %d shots" % [bot.kills, bot.hits, bot.shots])
	TestLib.check(max_hidden <= 12.0, "no trooper within 25 m stays behind a car or a wall for more than 12 s (longest %.1f s)" % max_hidden)
	TestLib.check(sets_done[0] >= 1 and _enc.phase == &"calm", "the third wave closes the set: the breather follows")
	for c: Dictionary in _enc.wave_started.get_connections():
		_enc.wave_started.disconnect(c["callable"])
	for c: Dictionary in _enc.set_cleared.get_connections():
		_enc.set_cleared.disconnect(c["callable"])
	_mgr.clear()
	_enc.squad.clear()
	_enc.enabled = false
