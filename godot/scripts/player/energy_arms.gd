class_name EnergyArms
extends RefCounted
## The mechanics of the wave-108 weapons (the ENERGY family and the BLAST class of destructive heavies, WeaponDefs keys splash / stick / shock / salvo / cluster_n / fire_* / beacon / guided) kept
## out of PlayerWeapon: one instance per PlayerWeapon (`weapon.arms`), pure game rules, every effect also counts itself (the counters below) so a test waits on a counter, never on a frame count.
##   splash       a blast where a round lands (plasma pistol pop, chaingun explosive round every Nth shot, beam and railgun impact): Game.explode, so cover, props, cars and people all feel it
##   stick        CRYSTAL SPIKER: every hit plants a crystal in the target; `stick` of them within `stick_time` supercombine into a blast, the alt-fire SHATTER pops what is planted
##   shock        melee shockwave (TREMOR MAUL swing, GROUND SLAM, REPULSE): damage, stagger, a shove for people and cars (Vehicle.apply_impulse)
##   salvo / fan  several rockets for one pull (HORNET POD, ALL PODS) and several beacons (ORBITAL BARRAGE)
##   cluster_n    HIVE CLUSTER MISSILE: bomblets rain around the impact one after another
##   fire_*       CINDER NAPALM: a burning field on the ground (people in it burn, cars take fire damage), WALL OF FIRE lays a line of them
##   beacon       ORBITAL STRIKE BEACON: lands, a column of light rises, then `beacon_pulses` strikes fall on it
##   guided       SEEKER: the round turns toward the crosshair (or the locked target) every frame; TOP ATTACK climbs first, then dives; AIRBURST bursts in the air over the target

const MAX_ZONES := 8
const MAX_CRYSTAL_TARGETS := 12
const ZONE_TICK := 0.5
const BEAM_HEIGHT := 140.0
const BEAM_FADE := 0.5
const PALE := Color(0.75, 0.97, 1.0)
const MODE_SHOCK := 0                       ## FX.qvfx ring modes
const MODE_IMPLODE := 1

var w: PlayerWeapon
## counters (tests read them)
var splashes := 0
var shockwaves := 0
var crystals_planted := 0
var crystal_pops := 0
var cluster_blasts := 0
var fire_zones_made := 0
var fire_ticks := 0
var beacons_planted := 0
var beacon_strikes := 0
var guided_steers := 0
var salvo_rockets := 0
var blast_stuns := 0
var oc_bolts := 0

var _crystals: Dictionary = {}              ## enemy instance id -> {node, n, t}
var _zones: Array[Dictionary] = []          ## {pos, left, tick, radius, dps, car}
var _strikes: Array[Dictionary] = []        ## {pos, delay, left, pulse_t, fade, d, node, ring_t}
var _pending: Array[Dictionary] = []        ## delayed blasts {pos, delay, radius, dmg, car, element}
var _beams: Array[MeshInstance3D] = []


func _init(weapon: PlayerWeapon) -> void:
	w = weapon


func reset() -> void:
	_crystals.clear()
	_zones.clear()
	_pending.clear()
	for s in _strikes:
		_hide_beam(s)
	_strikes.clear()


# --- numbers ----------------------------------------------------------------------------------------------------------

func _dmg_mult() -> float:
	return Upgrades.damage_mult() * HeroPower.f("dmg")


## One blast with the hero's damage multipliers; `quiet` skips the boom, shake and slow motion (a fast weapon's small pops).
func blast(pos: Vector3, radius: float, enemy_dmg: float, car_dmg: float, element: StringName, quiet := false) -> void:
	Game.explode(pos, radius, {"enemy_dmg": TestMode.damage(enemy_dmg * _dmg_mult()), "car_dmg": car_dmg, "player_dmg": 0.0, "element": element, "quiet": quiet})


# --- splash (a blast where a round lands) -----------------------------------------------------------------------------------

func splash(at: Vector3, shot_n: int) -> void:
	var d := w.def
	var every := maxi(1, int(d.get("splash_every", 1)))
	if shot_n % every != 0:
		return
	splashes += 1
	var loud := float(d["splash"]) >= 3.0
	blast(at, float(d["splash"]), float(d.get("splash_dmg", 10.0)), float(d.get("splash_car", 20.0)), StringName(d.get("splash_element", &"fire")), not loud)


# --- CRYSTAL SPIKER ---------------------------------------------------------------------------------------------------------

## A hit plants a crystal in `target` (a pink flash on it); the `stick`-th crystal inside `stick_time` supercombines.
func stick(target: Node, hit: Vector3) -> void:
	if not (target is Node3D) or w._is_dead(target):
		return
	var d := w.def
	var key := target.get_instance_id()
	if not _crystals.has(key) and _crystals.size() >= MAX_CRYSTAL_TARGETS:
		return
	var e: Dictionary = _crystals.get(key, {"node": target, "n": 0, "t": 0.0})
	e["n"] = int(e["n"]) + 1
	e["t"] = float(d["stick_time"])
	_crystals[key] = e
	crystals_planted += 1
	FX.burst(hit, d["tracer"], 3, 2.0, 0.35, 0.0, 0.8)
	if int(e["n"]) >= int(d["stick"]):
		_pop(key, 1.0)


## Supercombine: the planted crystals of one target blow in a violet-pink blast; `scale` = how many of the full set were planted (the alt-fire pops a partial set).
func _pop(key: int, scale: float) -> void:
	var e: Dictionary = _crystals.get(key, {})
	_crystals.erase(key)
	if e.is_empty() or not is_instance_valid(e["node"]):
		return
	var d := w.def
	var n := e["node"] as Node3D
	var c: Vector3 = n.call(&"center") if n.has_method(&"center") else n.global_position + Vector3(0.0, 1.0, 0.0)
	crystal_pops += 1
	blast(c, float(d["stick_radius"]), float(d["stick_dmg"]) * scale, float(d.get("stick_car", 100.0)) * scale, StringName(d.get("stick_element", &"quantum")))
	if is_instance_valid(n) and n.has_method(&"stagger"):
		n.call(&"stagger", 1.2)


## SHATTER (alt-fire): every crystal planted so far goes off now, each target for n / stick of the full damage. False when nothing is planted.
func pop_all() -> bool:
	if _crystals.is_empty():
		return false
	var d := w.def
	for key: int in _crystals.keys():
		var e: Dictionary = _crystals[key]
		_pop(key, clampf(float(e["n"]) / float(d["stick"]), 0.2, 1.0))
	return true


func crystals_on(target: Node) -> int:
	var e: Dictionary = _crystals.get(target.get_instance_id(), {})
	return int(e.get("n", 0))


# --- shockwave (TREMOR MAUL, GROUND SLAM, REPULSE) --------------------------------------------------------------------------

## A shockwave around `centre`: Game.explode for the damage and the props, then everything near is shoved away (people stagger, cars are pushed and spun).
func shockwave(centre: Vector3, radius: float, dmg: float, car: float, push: float, element: StringName, quiet := false) -> void:
	shockwaves += 1
	blast(centre, radius, dmg, car, element, quiet)
	for e: Node in w.get_tree().get_nodes_in_group(&"enemy"):
		if not (e is Node3D) or w._is_dead(e):
			continue
		var en := e as Node3D
		var off := en.global_position - centre
		off.y = 0.0
		var dist := off.length()
		if dist > radius:
			continue
		var k := 1.0 - 0.6 * dist / radius
		var dir := off / dist if dist > 0.1 else Vector3.FORWARD
		en.global_position += dir * push * k * 0.5
		if e.has_method(&"stagger"):
			e.call(&"stagger", 1.8 * k)
		if e.has_method(&"disable") and k > 0.55:
			e.call(&"disable", 0.9)
	for v: Node in w.get_tree().get_nodes_in_group(&"vehicle"):
		if not (v is Node3D) or not v.has_method(&"apply_impulse") or v == w._player.vehicle:
			continue
		var vp := (v as Node3D).global_position
		var voff := vp - centre
		voff.y = 0.0
		var vd := voff.length()
		if vd > radius + 2.0:
			continue
		var vk := 1.0 - 0.6 * vd / (radius + 2.0)
		var vdir := voff / vd if vd > 0.1 else Vector3.FORWARD
		v.call(&"apply_impulse", vdir * push * vk * 1400.0, vp - vdir * 0.8)
	FX.qvfx.ring(centre + Vector3(0.0, 0.1, 0.0), Vector3.UP, radius, BlastElements.color(element, "ring"), PALE, MODE_SHOCK, 0.45)


## TREMOR MAUL swing: the wave starts at the head of the hammer, a little in front of the hero (it works on the ground too: it breaks cover, even when nobody is hit).
func melee_shock(origin: Vector3, fwd: Vector3, reach: float) -> void:
	var d := w.def
	var at := origin + fwd * minf(reach * 0.8, 2.6)
	shockwave(at, float(d["shock"]), float(d["shock_dmg"]), float(d.get("shock_car", 80.0)), float(d.get("shock_push", 8.0)), StringName(d.get("shock_element", &"quantum")))


# --- throws: salvo, fans, guided --------------------------------------------------------------------------------------------

## HORNET POD: `salvo` rockets for one pull, fanned a little; each one costs a round.
func salvo() -> void:
	var d := w.def
	var n := int(d.get("salvo", 1))
	Sfx.play(StringName(d.get("snd", &"shot")), float(d.get("vol", -2.0)), randf_range(float(d["pitch_lo"]), float(d["pitch_hi"])))
	var made := 0
	for i in n:
		if w.ammo <= 0:
			break
		var off := 0.0 if i == 0 else (0.035 if i % 2 == 1 else -0.035) * float((i + 1) / 2)
		w._throw(off, true, {})
		made += 1
	salvo_rockets += made


## A fan of `count` throws (ALL PODS, ORBITAL BARRAGE): the round count is paid by the caller.
func fan(count: int, step: float) -> void:
	Sfx.play(StringName(w.def.get("snd", &"shot")), float(w.def.get("vol", -2.0)), 0.9)
	for i in count:
		var off := (float(i) - float(count - 1) * 0.5) * step
		w._throw(off, true, {})
		salvo_rockets += 1


## SEEKER: turn the round toward the crosshair point (or the locked target) at `turn` rad/s; TOP ATTACK first climbs for 0.7 s.
func steer(g: Dictionary, dt: float) -> void:
	var d := w._gdef(g)
	var vel: Vector3 = g["vel"]
	var speed := vel.length()
	if speed < 0.5:
		return
	var pos: Vector3 = g["pos"]
	var aim_pt: Vector3 = (w._player.get_aim() as Dictionary)["hit"]
	if is_instance_valid(w._launch) and is_instance_valid(w._launch.target) and not w._is_dead(w._launch.target):
		aim_pt = (w._launch.target as Node3D).global_position + Vector3(0.0, 1.0, 0.0)
	var want := (aim_pt - pos).normalized()
	var dive := bool(g.get("dive", false))
	if dive and float(g["t"]) < 0.7:
		want = Vector3(0.0, 1.0, 0.0).lerp(vel.normalized(), 0.15).normalized()
	var cur := vel / speed
	var ang := cur.angle_to(want)
	if ang > 0.001:
		var step := minf(ang, float(d.get("turn", 2.5)) * dt * (2.2 if dive else 1.0))
		var axis := cur.cross(want)
		if axis.length() > 0.0001:
			cur = cur.rotated(axis.normalized(), step)
	g["vel"] = cur * speed
	guided_steers += 1


# --- blasts of the projectiles ----------------------------------------------------------------------------------------------

## Before the normal blast of a thrown round: the ORBITAL BEACON does not explode, it plants. True = handled (no blast now).
func on_collapse(d: Dictionary, pos: Vector3) -> bool:
	if not bool(d.get("beacon", false)):
		return false
	beacons_planted += 1
	var node := _take_beam(StringName(d.get("blast_element", &"plasma")))
	node.global_position = pos + Vector3(0.0, BEAM_HEIGHT * 0.5, 0.0)
	node.scale = Vector3(0.12, 1.0, 0.12)
	node.visible = true
	_strikes.append({"pos": pos, "delay": float(d["beacon_delay"]), "left": int(d["beacon_pulses"]), "pulse_t": 0.0, "fade": BEAM_FADE, "d": d, "node": node, "ring_t": 0.0})
	FX.burst(pos + Vector3(0.0, 0.5, 0.0), d["blast_color"], 8, 3.0, 0.5, 0.0, 1.0)
	Sfx.play_at(&"link", pos, -4.0, 0.7)
	return true


## After the normal blast of a thrown round: bomblets, a burning field, the overcharge stun.
func after_blast(d: Dictionary, pos: Vector3) -> void:
	var n := int(d.get("cluster_n", 0))
	if n > 0:
		var ring := float(d.get("cluster_spread", 6.0))
		for i in n:
			var a := TAU * float(i) / float(n) + randf() * 0.5
			var r := ring * (0.45 + 0.55 * float((i * 7) % n) / float(maxi(1, n - 1)))
			_pending.append({"pos": pos + Vector3(cos(a) * r, 0.0, sin(a) * r), "delay": 0.16 * float(i + 1), "radius": float(d["blast_radius"]), "dmg": float(d.get("blast_damage", 40.0)),
					"car": float(d.get("car_dmg", 40.0)), "element": StringName(d.get("blast_element", &"fire"))})
	if float(d.get("fire_radius", 0.0)) > 0.0:
		add_fire(pos, float(d["fire_radius"]), float(d["fire_time"]), float(d["fire_dps"]), float(d.get("fire_car", 8.0)))
	var stun := float(d.get("blast_stun", 0.0))
	if stun > 0.0:
		var radius := float(d["blast_radius"]) + 0.8
		for e: Node in w.get_tree().get_nodes_in_group(&"enemy"):
			if e is Node3D and not w._is_dead(e) and (e as Node3D).global_position.distance_to(pos) < radius and e.has_method(&"disable"):
				var hpmax: Variant = e.get("max_hp")
				e.call(&"disable", stun * (0.3 if hpmax != null and float(hpmax) > 400.0 else 1.0))
				blast_stuns += 1


# --- fire -------------------------------------------------------------------------------------------------------------------

func add_fire(pos: Vector3, radius: float, secs: float, dps: float, car: float) -> void:
	if _zones.size() >= MAX_ZONES:
		_zones.remove_at(0)
	_zones.append({"pos": pos, "left": secs, "tick": 0.0, "radius": radius, "dps": dps, "car": car})
	fire_zones_made += 1
	FX.blast_marks(pos, radius * 0.8, BlastElements.FIRE)


func zones_live() -> int:
	return _zones.size()


## WALL OF FIRE (alt-fire): `count` burning fields in a line from 5 m in front of the hero, away along the view.
func fire_line(count: int) -> void:
	var d := w.def
	var p := w._player
	var fwd := -p.camera_rig.camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	for i in count:
		var at := p.global_position + fwd * (5.0 + 4.5 * float(i))
		add_fire(at, float(d["fire_radius"]) * 0.75, float(d["fire_time"]), float(d["fire_dps"]), float(d.get("fire_car", 8.0)))
		FX.burst(at + Vector3(0.0, 0.5, 0.0), Color(1.0, 0.45, 0.1), 6, 3.0, 0.6, -1.0, 1.4)


# --- alt-fires --------------------------------------------------------------------------------------------------------------

## The alt kinds of the new weapons (PlayerWeapon.alt_fire calls this for the kinds it does not know). False = nothing happened (no cost, no cooldown).
func alt(kind: String, a: Dictionary, _aiming: bool) -> bool:
	var d := w.def
	match kind:
		"oc_bolt":                                         # the plasma pistol's charged ball: slow, big, stuns everybody in its blast
			oc_bolts += 1
			Sfx.play(&"boom", -10.0, 1.9)
			w._throw(0.0, false, {"wid": StringName(a["proj"])})
			return true
		"pop":
			if not pop_all():
				Sfx.dry_fire()
				return false
			return true
		"slam", "repulse":
			var centre := w._player.global_position + Vector3(0.0, 0.2, 0.0)
			shockwave(centre, float(a["radius"]), float(a["dmg"]), float(a["car"]), float(a["push"]), StringName(d.get("shock_element", d.get("blast_element", &"quantum"))))
			w.shots_fired += 1
			return true
		"fan":
			fan(int(a["count"]), float(a["step"]))
			return true
		"airburst":
			w._throw(0.0, false, {"airburst": true})
			return true
		"dive":
			w._throw(0.0, false, {"dive": true})
			return true
		"fire_line":
			fire_line(int(a["count"]))
			Sfx.play(StringName(d.get("snd", &"shot")), float(d.get("vol", -2.0)), 1.15)
			w.shots_fired += 1
			return true
	return false


# --- per frame --------------------------------------------------------------------------------------------------------------

func tick(dt: float) -> void:
	if not _crystals.is_empty():
		for key: int in _crystals.keys():
			var e: Dictionary = _crystals[key]
			e["t"] = float(e["t"]) - dt
			if float(e["t"]) <= 0.0 or not is_instance_valid(e["node"]) or w._is_dead(e["node"]):
				_crystals.erase(key)
	var i := _pending.size() - 1
	while i >= 0:
		var pb: Dictionary = _pending[i]
		pb["delay"] = float(pb["delay"]) - dt
		if float(pb["delay"]) <= 0.0:
			_pending.remove_at(i)
			cluster_blasts += 1
			blast(pb["pos"], float(pb["radius"]), float(pb["dmg"]), float(pb["car"]), StringName(pb["element"]), true)
		i -= 1
	_tick_zones(dt)
	_tick_strikes(dt)


func _tick_zones(dt: float) -> void:
	var i := _zones.size() - 1
	while i >= 0:
		var z: Dictionary = _zones[i]
		z["left"] = float(z["left"]) - dt
		z["tick"] = float(z["tick"]) - dt
		if float(z["left"]) <= 0.0:
			_zones.remove_at(i)
			i -= 1
			continue
		if float(z["tick"]) <= 0.0:
			z["tick"] = ZONE_TICK
			fire_ticks += 1
			var pos: Vector3 = z["pos"]
			var radius := float(z["radius"])
			var puffs := 2 if Game.quality == 0 else 4
			for k in puffs:                                                    # tall orange flames rising from the whole field, and a ring on the ground that shows its edge
				var a := randf() * TAU
				var r := radius * sqrt(randf()) * 0.85
				FX.burst(pos + Vector3(cos(a) * r, 0.3, sin(a) * r), Color(1.0, 0.35 + 0.4 * randf(), 0.06), 5, 2.4, 0.9, -4.0, 2.4)
			FX.qvfx.ring(pos + Vector3(0.0, 0.08, 0.0), Vector3.UP, radius * 0.95, Color(1.0, 0.5, 0.1), Color(1.0, 0.9, 0.5), MODE_SHOCK, 0.6)
			for e: Node in w.get_tree().get_nodes_in_group(&"enemy"):
				if e is Node3D and not w._is_dead(e) and (e as Node3D).global_position.distance_to(pos) < radius:
					w._ignite_ex(e, float(z["dps"]) * _dmg_mult(), 2.0)
			for v: Node in w.get_tree().get_nodes_in_group(&"vehicle"):
				if v is Node3D and v.has_method(&"damage") and (v as Node3D).global_position.distance_to(pos) < radius + 1.5 and v != w._player.vehicle:
					v.call(&"damage", float(z["car"]))
		i -= 1


func _tick_strikes(dt: float) -> void:
	var i := _strikes.size() - 1
	while i >= 0:
		var s: Dictionary = _strikes[i]
		var d: Dictionary = s["d"]
		var pos: Vector3 = s["pos"]
		var node := s["node"] as MeshInstance3D
		var element := StringName(d.get("blast_element", &"plasma"))
		if float(s["delay"]) > 0.0:                         # warning: the column of light thickens, a ring tightens on the ground
			s["delay"] = float(s["delay"]) - dt
			var k := 1.0 - clampf(float(s["delay"]) / float(d["beacon_delay"]), 0.0, 1.0)
			if is_instance_valid(node):
				node.scale = Vector3(0.12 + 0.3 * k, 1.0, 0.12 + 0.3 * k)
			s["ring_t"] = float(s["ring_t"]) - dt
			if float(s["ring_t"]) <= 0.0:
				s["ring_t"] = 0.45
				FX.qvfx.ring(pos + Vector3(0.0, 0.1, 0.0), Vector3.UP, float(d["blast_radius"]) * (1.0 - 0.5 * k), BlastElements.color(element, "ring"), PALE, MODE_IMPLODE, 0.45)
		elif int(s["left"]) > 0:
			s["pulse_t"] = float(s["pulse_t"]) - dt
			if float(s["pulse_t"]) <= 0.0:
				s["left"] = int(s["left"]) - 1
				s["pulse_t"] = float(d["beacon_gap"])
				beacon_strikes += 1
				if is_instance_valid(node):
					node.scale = Vector3(1.1, 1.0, 1.1)
				blast(pos, float(d["blast_radius"]), float(d.get("blast_damage", 200.0)), float(d.get("car_dmg", 300.0)), element)
				w.grenade_collapsed.emit(pos)
		else:                                               # the column fades out
			s["fade"] = float(s["fade"]) - dt
			if is_instance_valid(node):
				var f := clampf(float(s["fade"]) / BEAM_FADE, 0.0, 1.0)
				node.scale = Vector3(1.1 * f, 1.0, 1.1 * f)
			if float(s["fade"]) <= 0.0:
				_hide_beam(s)
				_strikes.remove_at(i)
		i -= 1


func strikes_pending() -> int:
	return _strikes.size()


# --- the column of light ----------------------------------------------------------------------------------------------------

func _take_beam(element: StringName) -> MeshInstance3D:
	for b in _beams:
		if is_instance_valid(b) and not b.visible:
			(b.material_override as StandardMaterial3D).albedo_color = Color(BlastElements.color(element, "mid"), 0.55)
			return b
	var m := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 1.0
	cy.bottom_radius = 1.0
	cy.height = BEAM_HEIGHT
	cy.radial_segments = 10
	cy.rings = 1
	m.mesh = cy
	m.material_override = Gear.fx_material(Color(BlastElements.color(element, "mid"), 0.55), true)
	m.top_level = true
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(m)
	_beams.append(m)
	return m


func _hide_beam(s: Dictionary) -> void:
	var n := s.get("node") as MeshInstance3D
	if n != null and is_instance_valid(n):
		n.visible = false


func live_beams() -> int:
	var n := 0
	for b in _beams:
		if is_instance_valid(b) and b.visible:
			n += 1
	return n
