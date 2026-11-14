class_name FoeFx
extends RefCounted
## DAMAGE ON ENEMIES (wave 113): what a hit, a blast, a status and a death look like on people and machines. An observer: it listens to the hero's hits (Player.hit_confirmed + PlayerWeapon.last_shot),
## to the blasts (Game.exploded + the result of BlastTable) and to the deaths (the `died` signal of every enemy), so no enemy script had to change. Every effect is pooled and capped by tier.
##   hit zones     head: a bright flare, a flying visor chip and a hard head snap; body: armour sparks in the colour of the camp, a flake of plate; legs: a puff of dust, a LIMP (slower for 3.5 s)
##   plates        at 30 % and 62 % of the health lost a big armour plate flies off the body (pooled debris: one draw call), with a ricochet
##   splatter      alien fluid (acid-green ichor of the Vael, amber hydraulic fluid of the gangs, cyan coolant of the drones; none for mercenaries) on the street below, on the wall behind and as a spray
##   statuses      burning (flames on the body, charred), frozen (ice tint, then it shatters), shocked (blue flicker and arcs), dissolving (violet motes, the body shrinks away): the shader `dmg_fx` of hero_body
##   deaths        a death by a blast, a shotgun or a heavy round throws the body: it tumbles, lands and slides (no ragdoll physics, one pooled integrator); a burning body keeps burning for 3 s, an electrocuted
##                 body crackles, a frozen one shatters into ice, a quantum one comes apart into violet dust; a machine breaks into plates and sparks
## No gore: a human (mercenary) leaves armour chips and dust only. Switch: Dmg.enabled (QT_DMG=0).

const TICK := 0.1
const PLATE_AT := [0.3, 0.62]                       ## share of the health lost at which the next big plate flies off
const PLATE_GAP := 0.16                              ## seconds between two plate effects of one enemy (eight pellets are one hit)
const LIMP_TIME := 3.5
const LIMP_K := 0.6
const FLING_MIN_KNOCK := 0.5            ## a round with this much `knock` (or a shotgun, or a heavy hit) throws a body it kills
const MAX_STATE := 160
const ICE := Color(0.7, 0.9, 1.0)
const VIOLET := Color(0.7, 0.35, 1.0)

var world: Node
var _st: Dictionary = {}                             ## instance id -> state (the node, hp seen, plates off, limp, status, hooks)
var _tokens := 4.0
var _plates_live := PackedFloat64Array()             ## expiry times (seconds) of the plates in flight
var _flings: Array[Dictionary] = []                  ## corpses flying: {n, vel, t, spin, axis}
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _shields: Array[Node] = []                       ## shield troopers whose shield is nearly gone: it flickers
var flickers := 0
var shatters := 0
var arcs_made := 0


func _init(w: Node) -> void:
	world = w
	_rng.randomize()


func reset() -> void:
	for id: int in _st.keys():
		_restore(_st[id])
	_st.clear()
	_flings.clear()
	_plates_live.clear()
	_tokens = 4.0


## Game seconds (the ticks add up): gates and statuses follow the game's time (slow motion, a test that advances time by hand), never the wall clock.
func _now() -> float:
	return _clock


# --- state ---------------------------------------------------------------------------------------------------------------------

func _state(en: Node) -> Dictionary:
	var id := en.get_instance_id()
	var s: Dictionary = _st.get(id, {})
	if s.is_empty():
		s = {"n": en, "hp": float(en.get(&"hp")) if en.get(&"hp") != null else 0.0, "plates": 0, "t_plate": -9.0, "limp": 0.0, "limp_speed": 1.0, "kind": &"", "until": 0.0,
				"t_hit": -9.0, "dir": Vector3.ZERO, "zone": &"", "hooked": false, "fx_t": 0.0, "arcs": 0}
		_st[id] = s
		if _st.size() > MAX_STATE:
			_purge()
	return s


func _purge() -> void:
	for id: int in _st.keys():
		var n: Variant = (_st[id] as Dictionary)["n"]
		if not is_instance_valid(n):
			_st.erase(id)
	while _st.size() > MAX_STATE:
		_st.erase(_st.keys()[0])


func state_of(en: Node) -> Dictionary:
	return _st.get(en.get_instance_id(), {})


## The health the enemy lost since this was last asked (and remember the new value).
func _observe(en: Node, s: Dictionary) -> float:
	var hp: Variant = en.get(&"hp")
	if hp == null:
		return 0.0
	var drop := maxf(float(s["hp"]) - float(hp), 0.0)
	s["hp"] = float(hp)
	return drop


func _max_hp(en: Node) -> float:
	var m: Variant = en.get(&"max_hp")
	return maxf(float(m), 1.0) if m != null else 60.0


## The camp of an enemy: gang, drones, vael (hive, the default), merc (a human mercenary: no fluid).
func camp_of(en: Node) -> StringName:
	var c: Variant = en.get(&"camp")
	if c is StringName and (c as StringName) != &"":
		return c
	var f: Variant = en.get(&"faction")
	if f is StringName:
		var fs := String(f)
		if fs.contains("merc"):
			return &"merc"
		if fs.contains("machine") or fs.contains("drone"):
			return &"drones"
	var t: Variant = en.get(&"id")
	if t is StringName and String(t).begins_with("merc"):
		return &"merc"
	return &"vael"


func _glow_of(en: Node) -> Color:
	var spec: Variant = en.get(&"spec")
	if spec is Dictionary and (spec as Dictionary).has("glow"):
		return (spec as Dictionary)["glow"]
	var cfg: Variant = en.get(&"cfg")
	if cfg is Dictionary and (cfg as Dictionary).has("color"):
		return (cfg as Dictionary)["color"]
	return Color(0, 0, 0, 0)


func _plate_color(en: Node) -> Color:
	var base := Color(0.2, 0.225, 0.27)                              # dark steel: a plate must not read as a coloured cube in the street lights
	var g := _glow_of(en)
	if g.a > 0.0:
		return base.lerp(Color(g.r, g.g, g.b), 0.14)
	return base


func _centre(en: Node3D) -> Vector3:
	return en.call(&"center") if en.has_method(&"center") else en.global_position + Vector3(0.0, 1.0, 0.0)


func _near_camera(p: Vector3, d: float) -> bool:
	var cam := Game.get_tree().root.get_camera_3d()
	return cam == null or cam.global_position.distance_to(p) < d


# --- hits ----------------------------------------------------------------------------------------------------------------------

## A bullet of the hero landed on enemy `en` (PlayerWeapon.last_shot `ls`: zone, hit point, direction).
func on_bullet(en: Node3D, ls: Dictionary, crit: bool, kill: bool, wdef: Dictionary) -> void:
	if not Dmg.enabled or not is_instance_valid(en):
		return
	var s := _state(en)
	var drop := _observe(en, s)
	var now := _now()
	var zone: StringName = ls.get("zone", &"")
	var point: Vector3 = ls.get("hit", _centre(en))
	var dir: Vector3 = ls.get("dir", Vector3.FORWARD)
	s["t_hit"] = now
	s["dir"] = dir
	s["zone"] = zone
	if not _near_camera(point, 90.0):
		return
	var human := en is Operative
	var camp := camp_of(en)
	var lost := 1.0 - float(s["hp"]) / _max_hp(en)
	var sparks: Variant = Game.player.get(&"sparks") if is_instance_valid(Game.player) else null
	match zone:
		&"head":
			if sparks != null:
				(sparks as ImpactSparks).spark(point, -dir, Color(1.0, 0.95, 0.75), 1.3)             # a bright flare at the head
			if human and now - float(s["t_plate"]) > PLATE_GAP:
				_chip(en, point, dir, 0.1, 1, 0.9)                                                 # a chip of the visor
			if en.has_method(&"stagger") and not kill:
				en.call(&"stagger", 1.5)                                                           # the head snaps back
		&"legs":
			_limp(en, s)
			_dust_ring(en)
		_:
			if sparks != null and human:
				(sparks as ImpactSparks).spark(point, -dir, _plate_color(en).lerp(Color(1.0, 0.8, 0.45), 0.6), 0.9)
	# plates
	if now - float(s["t_plate"]) > PLATE_GAP:
		var idx := int(s["plates"])
		if idx < PLATE_AT.size() and lost >= float(PLATE_AT[idx]) and _has_plates(en):
			s["plates"] = idx + 1
			s["t_plate"] = now
			_plate_off(en, point, dir)
		elif drop > 0.0 and zone != &"head" and _has_plates(en) and _rng.randf() < 0.28 * (0.5 + float(drop) / _max_hp(en) * 6.0):
			s["t_plate"] = now
			_chip(en, point, dir, 0.08, 1, 0.8)                                                    # a flake off the armour
	# splatter and spray
	if camp != &"merc" and (crit or drop >= 0.12 * _max_hp(en)):
		_splatter(en, point, dir, camp, clampf(drop / _max_hp(en) * 4.0, 0.4, 1.4))
	# weapon statuses
	if kill:
		s["kill_dir"] = dir
		s["kill_def"] = wdef
	else:
		_weapon_status(en, s, wdef)


## `en` is near a blast that just went off (DamageWorld asks one frame later): the damage it took is the health it lost since it was last seen, `entry` = the table entry of the blast.
func on_blast(en: Node3D, pos: Vector3, radius: float, entry: Dictionary) -> void:
	if not Dmg.enabled or not is_instance_valid(en):
		return
	var s := _state(en)
	var amount := _observe(en, s)
	var now := _now()
	var c := _centre(en)
	var away := Vector3(c.x - pos.x, 0.0, c.z - pos.z)
	away = away.normalized() if away.length() > 0.1 else Vector3(0.0, 0.0, 1.0)
	s["t_hit"] = now
	s["dir"] = away
	s["zone"] = &"body"
	if not _near_camera(c, 110.0):
		return
	var frac := amount / _max_hp(en)
	var camp := camp_of(en)
	if frac >= 0.18 and _has_plates(en):
		var n := clampi(int(frac * 5.0) + 1, 1, 3)
		for i in n:
			_plate_off(en, c, away, i > 0)
		s["plates"] = maxi(int(s["plates"]), 1)
	if camp != &"merc" and frac >= 0.1:
		_splatter(en, c, away, camp, clampf(frac * 3.0, 0.6, 1.8))
	var st: Dictionary = entry.get("status", {})
	if not st.is_empty():
		var kind := StringName(st.get("kind", &""))
		match kind:
			&"burn", &"freeze", &"shock":
				set_status(en, kind, float(st.get("time", 2.0)))
	var fire: Variant = entry.get("fire")
	if fire is Dictionary and not (fire as Dictionary).is_empty() and float((fire as Dictionary).get("dps", 0.0)) > 0.0 and radius > 0.0 and c.distance_to(pos) <= float((fire as Dictionary).get("radius", 0.0)) + 1.0:
		set_status(en, &"burn", 2.5)


# --- statuses ------------------------------------------------------------------------------------------------------------------

## A status shows on the body for `secs`: &"burn", &"freeze", &"shock", &"dissolve".
func set_status(en: Node3D, kind: StringName, secs: float) -> void:
	if not Dmg.enabled or not is_instance_valid(en):
		return
	var s := _state(en)
	var n_live := 0
	for id: int in _st.keys():
		if float((_st[id] as Dictionary)["until"]) > _now() and id != en.get_instance_id():
			n_live += 1
	if float(s["until"]) <= _now() and n_live >= Dmg.cap(&"foes_fx"):
		return
	s["kind"] = kind
	s["until"] = maxf(float(s["until"]), _now() + secs)
	s["fx_t"] = 0.0
	_shader(en, kind, 1.0)
	Dmg.bump(StringName("status_" + String(kind)))


func status_of(en: Node) -> StringName:
	var s: Dictionary = _st.get(en.get_instance_id(), {})
	if s.is_empty() or float(s["until"]) <= _now():
		return &""
	return StringName(s["kind"])


func _weapon_status(en: Node3D, s: Dictionary, wdef: Dictionary) -> void:
	if wdef.is_empty():
		return
	if wdef.has("burn") or bool(wdef.get("flame", false)):
		set_status(en, &"burn", 2.5)
	elif wdef.has("zap") or String(wdef.get("blast_element", "")) == "electric":
		set_status(en, &"shock", 1.2)
	elif wdef.has("chill") or wdef.has("freeze_time"):
		var w: Variant = Game.player.get(&"weapon") if is_instance_valid(Game.player) else null
		if w is PlayerWeapon and (w as PlayerWeapon).mech != null and (w as PlayerWeapon).mech.chill_stacks(en) >= 2:
			set_status(en, &"freeze", 2.0)
	elif wdef.has("dissolve"):
		set_status(en, &"dissolve", 2.0)


func _shader(en: Node, kind: StringName, strength: float) -> void:
	var body: Variant = en.get(&"humanoid_body")
	if body is MeshInstance3D:
		var k := 0.0
		match kind:
			&"burn":
				k = 1.0
			&"freeze":
				k = 2.0
			&"shock":
				k = 3.0
			&"dissolve":
				k = 4.0
		(body as MeshInstance3D).set_instance_shader_parameter(&"dmg_fx", Vector4(k, strength, 0.0, 0.0))


func _restore(s: Dictionary) -> void:
	var en: Variant = s["n"]
	if not is_instance_valid(en):
		return
	_shader(en, &"", 0.0)
	var m: Variant = (en as Node).get(&"model")
	if m is Node3D:
		(m as Node3D).scale = Vector3.ONE
		(m as Node3D).visible = true
	if float(s["limp"]) > 0.0 and en.get(&"camp_speed") != null:
		en.set(&"camp_speed", float(s["limp_speed"]))
	s["limp"] = 0.0


# --- the effects ---------------------------------------------------------------------------------------------------------------

func _has_plates(en: Node) -> bool:
	if en is RosterFoe and not (en as RosterFoe).plates.is_empty():
		return false                                                  # the plate brute has its own plates (RosterFoe._through_plates)
	if en is AlienCreature and not (en is RosterFoe):
		return false                                                  # animals and creatures: skin, no plates
	return true


func _plate_budget() -> bool:
	var now := _now()
	var live := 0
	for i in range(_plates_live.size() - 1, -1, -1):
		if _plates_live[i] <= now:
			_plates_live.remove_at(i)
		else:
			live += 1
	return live < Dmg.cap(&"plates")


## One armour plate (or `n` pieces) flies off: pooled debris, a ricochet, sparks.
func _plate_off(en: Node3D, at: Vector3, dir: Vector3, quiet := false) -> void:
	var br := Breakables.current
	if br == null or not _plate_budget():
		return
	var out := Vector3(-dir.x, 0.0, -dir.z)
	out = out.normalized() if out.length() > 0.1 else Vector3.UP
	var col := _plate_color(en)
	var sz := _rng.randf_range(0.2, 0.3) * clampf(float(en.get(&"scale_mult")) if en.get(&"scale_mult") != null else 1.0, 0.8, 1.6)
	var vel := (out * _rng.randf_range(1.5, 3.5) + dir * _rng.randf_range(1.5, 3.5) + Vector3(_rng.randf_range(-1.2, 1.2), _rng.randf_range(2.5, 5.0), _rng.randf_range(-1.2, 1.2)))
	br.fling(at + Vector3(0.0, 0.1, 0.0), vel, col, sz, Vector3(1.0, 0.08, _rng.randf_range(0.55, 0.85)), 2.6)
	_plates_live.append(_now() + 2.6)
	Dmg.bump(&"plate")
	if not quiet:
		Sfx.play_at(&"ricochet", at, -4.0, _rng.randf_range(0.7, 0.9))
		var sp: Variant = Game.player.get(&"sparks") if is_instance_valid(Game.player) else null
		if sp != null:
			(sp as ImpactSparks).spark(at, out, Color(1.0, 0.85, 0.5), 1.2)


## A small chip of plate, visor or flake: `n` pieces of `size` metres.
func _chip(en: Node3D, at: Vector3, dir: Vector3, size: float, n: int, speed: float) -> void:
	var br := Breakables.current
	if br == null or not _plate_budget():
		return
	var col := _plate_color(en)
	for i in n:
		var vel := (-dir * _rng.randf_range(1.0, 2.5) + Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(1.5, 3.2), _rng.randf_range(-1.0, 1.0))) * speed
		br.fling(at, vel, col, size * _rng.randf_range(0.8, 1.3), Vector3(1.0, 0.2, _rng.randf_range(0.6, 1.0)), 1.6)
		_plates_live.append(_now() + 1.6)
	Dmg.bump(&"chip")


func _limp(en: Node3D, s: Dictionary) -> void:
	if float(s["limp"]) > 0.0 or en.get(&"camp_speed") == null:
		return
	var n := 0
	for id: int in _st.keys():
		if float((_st[id] as Dictionary)["limp"]) > 0.0:
			n += 1
	if n >= Dmg.cap(&"limp_foes"):
		return
	s["limp"] = LIMP_TIME
	s["limp_speed"] = float(en.get(&"camp_speed"))
	en.set(&"camp_speed", float(s["limp_speed"]) * LIMP_K)
	if en.has_method(&"stagger"):
		en.call(&"stagger", 1.0)
	Dmg.bump(&"limp")


func _dust_ring(en: Node3D) -> void:
	var bf := BlastFx.instance
	if is_instance_valid(bf):
		bf.puff(en.global_position + Vector3(0.0, 0.15, 0.0), Vector3(0.0, 0.5, 0.0), 0.5, 1.5, 0.7, Color(0.6, 0.57, 0.52, 0.45), BlastFx.K_SMOKE, 0.0, 1.2)


func _token() -> bool:
	if _tokens < 1.0:
		return false
	_tokens -= 1.0
	return true


## Fluid on the street under the enemy, on the wall behind it, and a spray of drops. `k` scales the sizes.
func _splatter(en: Node3D, at: Vector3, dir: Vector3, camp: StringName, k: float) -> void:
	var fl: Variant = Dmg.fluid_of(camp, _glow_of(en))
	if fl == null or FX.marks == null or not _token():
		return
	var col: Color = fl
	var bf := BlastFx.instance
	if is_instance_valid(bf):                                              # the spray: drops thrown along the shot
		var n := 2 if Dmg.tier() == 0 else 3
		for i in n:
			bf.puff(at, dir * _rng.randf_range(1.5, 3.5) + Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(0.5, 2.0), _rng.randf_range(-1.0, 1.0)), 0.07, 0.2, 0.5, col, BlastFx.K_SPRAY, 0.15, 1.6)
	var g: Vector3 = FX.marks.ground_under(at, 3.5)
	if g != Vector3.INF:
		FX.marks.splat(g + Vector3(dir.x, 0.0, dir.z).normalized() * _rng.randf_range(0.3, 1.1), Vector3.UP, _rng.randf_range(0.5, 1.0) * k, col)
		Dmg.bump(&"splat_ground")
	# the wall behind: a ray along the shot
	var vp := Game.get_tree().root
	if vp != null and vp.world_3d != null:
		var q := PhysicsRayQueryParameters3D.create(at, at + dir.normalized() * 3.8)
		q.collision_mask = Game.L_WORLD
		q.collide_with_areas = false
		var h := vp.world_3d.direct_space_state.intersect_ray(q)
		if not h.is_empty() and absf((h["normal"] as Vector3).y) < 0.6 and not (h["collider"] as Node).has_meta(&"bk_index"):
			FX.marks.splat(h["position"], h["normal"], _rng.randf_range(0.7, 1.2) * k, col)
			Dmg.bump(&"splat_wall")


# --- ticking -------------------------------------------------------------------------------------------------------------------

## 10 Hz: statuses, limps, refilling the splat tokens, the enemies that burn.
func tick(dt: float) -> void:
	_clock += dt
	_tokens = minf(_tokens + dt * float(Dmg.cap(&"splat_tokens")), float(Dmg.cap(&"splat_tokens")))
	var now := _now()
	var tree := Game.get_tree()
	var was_shields := _shields.duplicate()
	_shields.clear()
	for n: Node in tree.get_nodes_in_group(&"enemy"):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		_hook(n)
		var sn: Variant = n.get(&"shield_node")
		if sn is MeshInstance3D and float(n.get(&"shield_hp")) > 0.0 and float(n.get(&"shield_hp")) < float(n.get(&"shield_max")) * 0.45:
			_shields.append(n)
			if not was_shields.has(n):
				flickers += 1
				Dmg.bump(&"shield_flicker")
	for n in was_shields:
		if is_instance_valid(n) and not _shields.has(n):
			var sn2: Variant = n.get(&"shield_node")
			if sn2 is MeshInstance3D:
				(sn2 as MeshInstance3D).visible = float(n.get(&"shield_hp")) > 0.0
	for id: int in _st.keys():
		var s: Dictionary = _st[id]
		var en: Variant = s["n"]
		if not is_instance_valid(en):
			_st.erase(id)
			continue
		if float(s["limp"]) > 0.0:
			s["limp"] = float(s["limp"]) - dt
			if float(s["limp"]) <= 0.0 and en.get(&"camp_speed") != null and absf(float(en.get(&"camp_speed")) - float(s["limp_speed"]) * LIMP_K) < 0.001:
				en.set(&"camp_speed", float(s["limp_speed"]))
		if float(s["until"]) > 0.0:
			_tick_status(en as Node3D, s, dt, now)


## The flames, arcs and motes of a status.
func _tick_status(en: Node3D, s: Dictionary, dt: float, now: float) -> void:
	var left := float(s["until"]) - now
	var kind := StringName(s["kind"])
	if left <= 0.0:
		s["until"] = 0.0
		var dead_now: Variant = en.get(&"dead")
		if not (dead_now is bool and dead_now) or kind == &"":
			_shader(en, &"", 0.0)
		return
	if not _near_camera(en.global_position, 70.0):
		return
	s["fx_t"] = float(s["fx_t"]) - dt
	if float(s["fx_t"]) > 0.0:
		return
	var c := _centre(en)
	var bf := BlastFx.instance
	match kind:
		&"burn":
			s["fx_t"] = [0.32, 0.22, 0.14][Dmg.tier()]
			if is_instance_valid(bf):
				bf.puff(c + Vector3(_rng.randf_range(-0.2, 0.2), -0.1 + _rng.randf() * 0.5, _rng.randf_range(-0.2, 0.2)), Vector3(0.0, 1.8, 0.0), 0.5, 1.1, 0.65, Color(1.0, 0.45, 0.1, 0.9), BlastFx.K_FLAME, 0.8, 0.5, 1.7)
				if _rng.randf() < 0.4:
					bf.puff(c + Vector3(0.0, 0.7, 0.0), Vector3(0.0, 1.2, 0.0), 0.4, 1.2, 1.1, Color(0.1, 0.1, 0.11, 0.55), BlastFx.K_SMOKE, 0.0, 0.5)
		&"shock":
			s["fx_t"] = [0.3, 0.2, 0.12][Dmg.tier()]
			var a := c + Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.5, 0.6), _rng.randf_range(-0.4, 0.4))
			var b := c + Vector3(_rng.randf_range(-0.7, 0.7), _rng.randf_range(-0.9, 0.9), _rng.randf_range(-0.7, 0.7))
			if FX.qvfx != null:
				FX.qvfx.bolt(a, b, Color(0.7, 0.9, 1.0))
				arcs_made += 1
				Dmg.bump(&"arc")
		&"freeze":
			s["fx_t"] = 0.5
			if is_instance_valid(bf):
				bf.puff(c + Vector3(0.0, -0.4, 0.0), Vector3(0.0, 0.3, 0.0), 0.3, 0.9, 0.9, Color(0.75, 0.92, 1.0, 0.4), BlastFx.K_SMOKE, 0.2, 1.0)
		&"dissolve":
			s["fx_t"] = 0.25
			if is_instance_valid(bf):
				bf.puff(c + Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.5, 0.7), _rng.randf_range(-0.3, 0.3)), Vector3(0.0, 1.0, 0.0), 0.15, 0.5, 0.8, Color(0.75, 0.4, 1.0, 0.8), BlastFx.K_SPRAY, 0.6, 1.0)


## Connect to the `died` signal of an enemy once.
func _hook(n: Node) -> void:
	var s := _state(n)
	if bool(s.get("died", false)) and n.get(&"dead") != true:
		_restore(s)                                                  # a pooled enemy came back to life: a fresh state (no status, no limp, whole plates)
		_st.erase(n.get_instance_id())
		s = _state(n)
	if bool(s["hooked"]):
		return
	s["hooked"] = true
	if n.has_signal(&"died") and not n.is_connected(&"died", _on_died):
		n.connect(&"died", _on_died)


# --- deaths --------------------------------------------------------------------------------------------------------------------

func _on_died(en: Node) -> void:
	if not Dmg.enabled or not (en is Node3D) or not is_instance_valid(en):
		return
	var s := _state(en)
	s["died"] = true
	var now := _now()
	var node := en as Node3D
	var c := _centre(node)
	var lb: Dictionary = (world as DamageWorld).blast_near(node.global_position) if world is DamageWorld else {}
	var cause := _cause(node, s, now, lb)
	Dmg.bump(StringName("death_" + String(cause)))
	if not _near_camera(c, 120.0):
		return
	var dir: Vector3 = s["dir"] if (s["dir"] as Vector3).length() > 0.1 else Vector3(0.0, 0.0, 1.0)
	if not lb.is_empty():
		var away := Vector3(node.global_position.x - (lb["pos"] as Vector3).x, 0.0, node.global_position.z - (lb["pos"] as Vector3).z)
		if away.length() > 0.2:
			dir = away.normalized()
	var camp := camp_of(en)
	var machine := not (en is Operative) and not (en is AlienCreature)
	# the shell of a machine breaks apart, a person loses plates
	if machine:
		for i in clampi(2 + Dmg.tier() * 2, 2, 6):
			_plate_off(node, c, dir, i > 0)
	elif _has_plates(en) and cause != &"quantum":
		for i in (1 if Dmg.tier() == 0 else 2):
			_plate_off(node, c, dir, i > 0)
	match cause:
		&"burn":
			set_status(node, &"burn", 3.2)
		&"shock":
			set_status(node, &"shock", 0.9)
			if FX.qvfx != null:
				for i in 3:
					FX.qvfx.bolt(c + Vector3(0.0, 0.8, 0.0), c + Vector3(_rng.randf_range(-1.2, 1.2), _rng.randf_range(-0.6, 0.4), _rng.randf_range(-1.2, 1.2)), Color(0.7, 0.9, 1.0))
		&"freeze":
			set_status(node, &"freeze", 0.5)
			_shatter(node, c)
		&"quantum":
			set_status(node, &"dissolve", 1.0)
			if FX.qvfx != null:
				FX.qvfx.death_dust(c, 1.6, 0.5, VIOLET)
			_shrink(node, 0.9)
		&"blast", &"heavy":
			if not machine:
				_fling(node, lb, dir, cause == &"blast")
	if camp != &"merc" and cause != &"quantum":
		_splatter(node, c, dir, camp, 1.6)


## What killed it: a status that was on it, the blast that just went off, the weapon of the last shot, or plain.
func _cause(_en: Node3D, s: Dictionary, now: float, lb: Dictionary) -> StringName:
	if float(s["until"]) > now:
		var k := StringName(s["kind"])
		if k == &"dissolve":
			return &"quantum"
		return k
	if not lb.is_empty():
		var entry := BlastTable.entry(StringName(lb.get("id", &"")))
		if StringName(entry.get("element", &"")) == &"quantum":
			return &"quantum"
		return &"blast"
	var wd: Variant = s.get("kill_def")
	if wd is Dictionary:
		var d: Dictionary = wd
		if d.has("dissolve"):
			return &"quantum"
		if d.has("burn") or bool(d.get("flame", false)):
			return &"burn"
		if d.has("zap"):
			return &"shock"
		if d.has("chill"):
			return &"freeze"
		if float(d.get("knock", 0.0)) >= FLING_MIN_KNOCK or int(d.get("pellets", 1)) >= 6 or float(d.get("damage", 0.0)) >= 55.0:
			return &"heavy"
	return &"plain"


## A frozen body bursts into ice: pieces of ice, a puff of cold, the body is gone.
func _shatter(en: Node3D, c: Vector3) -> void:
	var br := Breakables.current
	if br != null:
		for i in clampi(6 + Dmg.tier() * 4, 6, 14):
			br.fling(c + Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.7, 0.8), _rng.randf_range(-0.3, 0.3)), Vector3(_rng.randf_range(-3.0, 3.0), _rng.randf_range(1.5, 5.0), _rng.randf_range(-3.0, 3.0)), ICE, _rng.randf_range(0.14, 0.32), Vector3(1.0, _rng.randf_range(0.25, 0.6), _rng.randf_range(0.4, 0.9)), 2.4)
	Sfx.impact(&"glass", c, Vector3.UP)
	shatters += 1
	Dmg.bump(&"shatter")
	var m: Variant = en.get(&"model")
	if m is Node3D:
		(m as Node3D).visible = false
	_restore_later(en)


func _shrink(en: Node3D, secs: float) -> void:
	_flings.append({"n": en, "mode": "shrink", "t": 0.0, "dur": secs})


func _restore_later(en: Node3D) -> void:
	_flings.append({"n": en, "mode": "unhide", "t": 0.0, "dur": 4.6})


## The body is thrown by a blast or a heavy round: it flies along `dir`, tumbles, lands and slides. The corpse node moves and spins as a whole (the dying pose lives in its model child).
func _fling(en: Node3D, lb: Dictionary, dir: Vector3, blast: bool) -> void:
	if _flings.size() >= 12:
		return
	var amount := 4.5
	var up := 2.2
	if blast and not lb.is_empty():
		var e := BlastTable.entry(StringName(lb.get("id", &"")))
		amount = clampf(float(e.get("knock", 8.0)) * 0.8, 4.0, 14.0)
		up = clampf(float(e.get("lift", 6.0)) * 0.7, 3.0, 9.0)
	else:
		dir = Vector3(dir.x, 0.0, dir.z).normalized() if Vector2(dir.x, dir.z).length() > 0.05 else Vector3(0.0, 0.0, 1.0)
	var side := Vector3(-dir.z, 0.0, dir.x)
	_flings.append({"n": en, "mode": "fly", "vel": dir * amount + Vector3(0.0, up, 0.0), "t": 0.0, "axis": side, "spin": _rng.randf_range(5.0, 9.0) * (1.0 if _rng.randf() < 0.5 else -1.0), "y0": en.global_position.y})
	Dmg.bump(&"fling")


func shields_live() -> int:
	return _shields.size()


## Every frame while something is in the air or a shield is failing (the world node ticks it).
func step(delta: float) -> void:
	if not _shields.is_empty():
		var phase := int(Time.get_ticks_msec() * 0.014) % 3                  # the failing shield blinks: two frames in three, faster than the eye follows a shot
		for sh in _shields:
			if is_instance_valid(sh):
				var sn: Variant = sh.get(&"shield_node")
				if sn is MeshInstance3D:
					(sn as MeshInstance3D).visible = phase != 0 and float(sh.get(&"shield_hp")) > 0.0
	var i := _flings.size() - 1
	while i >= 0:
		var f: Dictionary = _flings[i]
		if not is_instance_valid(f["n"]):
			_flings.remove_at(i)
			i -= 1
			continue
		var en := f["n"] as Node3D
		f["t"] = float(f["t"]) + delta
		match String(f["mode"]):
			"fly":
				var vel: Vector3 = f["vel"]
				vel.y -= 22.0 * delta
				var p := en.global_position + vel * delta
				var gy := Dmg.ground_y(p)
				var done := false
				if p.y <= gy and vel.y < 0.0 and float(f["t"]) > 0.08:
					p.y = gy
					vel = Vector3(vel.x * 0.45, 0.0, vel.z * 0.45)
					f["mode"] = "slide"
					f["vel"] = vel
					en.rotation.x = 0.0
					en.rotation.z = 0.0
				else:
					f["vel"] = vel
					var ang := float(f["spin"]) * float(f["t"])
					var ax: Vector3 = f["axis"]
					en.rotation = Vector3(ax.x * ang * 0.35, en.rotation.y, ax.z * ang * 0.35)
				en.global_position = p
				if done:
					_flings.remove_at(i)
			"slide":
				var v2: Vector3 = f["vel"]
				v2 *= maxf(0.0, 1.0 - 6.0 * delta)
				f["vel"] = v2
				var p2 := en.global_position + v2 * delta
				p2.y = Dmg.ground_y(p2)
				en.global_position = p2
				f["slide_t"] = float(f.get("slide_t", 0.0)) + delta
				if v2.length() < 0.15 or float(f["slide_t"]) > 1.2:
					_flings.remove_at(i)
			"shrink":
				var m: Variant = en.get(&"model")
				var k := clampf(float(f["t"]) / float(f["dur"]), 0.0, 1.0)
				if m is Node3D:
					(m as Node3D).scale = Vector3.ONE * (1.0 - k * k)
				if k >= 1.0:
					if m is Node3D:
						(m as Node3D).visible = false
					_flings[i]["mode"] = "unhide"
					_flings[i]["t"] = 0.0
					_flings[i]["dur"] = 4.6
			"unhide":
				if float(f["t"]) >= float(f["dur"]) or not (en.get(&"dead") == true):
					var m2: Variant = en.get(&"model")
					if m2 is Node3D:
						(m2 as Node3D).visible = true
						(m2 as Node3D).scale = Vector3.ONE
					_flings.remove_at(i)
		i -= 1


func flings_live() -> int:
	return _flings.size()
