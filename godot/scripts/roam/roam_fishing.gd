class_name RoamFishing
extends Node
## FISHING-LITE (wave 111). Six places (`RoamData.fish_spots()`: two lakes, two river banks, the south-west shore and the harbour pier). Stand still on one on foot: the line is cast by itself
## (a bobber floats on the water 7 m out), after 3-7 s something bites, the bobber dips and the line says BITE: tap JUMP (or FIRE) within 3 seconds to reel it in. A miss recasts by itself.
## What bites depends on the water (lake, river, sea) and the time of day (`RoamData.FISH`: a silver eel only at night, a gold koi at dusk, a bluefin tuna by day, a glowfin in the lake at night).
## The first catch of a species is a discovery (the fish log) and pays its price; later catches of it pay a third. EASY: no bait, no tension, nothing to lose but a bite.
## Logic is `poll(dt, hero)`; tests drive it through `cast_now()`, `force_bite()` and `reel()`.

signal caught(species: StringName, first: bool)

const START_R := 6.0
const DWELL := 1.0                          ## seconds standing still before the cast
const STILL := 1.6                          ## m/s: faster than this is not standing still
const BITE_MIN := 3.0
const BITE_MAX := 7.0
const WINDOW := 3.0
const RECAST := 2.0
const LEAVE_R := 11.0
const CAST_DIST := 7.0

var world: RoamWorld
var prompt := ""
var state: StringName = &"idle"            ## idle / dwell / wait / bite / cooldown
var spot: Dictionary = {}
var catches := 0
var misses := 0
var last_species: StringName = &""
var rng := RandomNumberGenerator.new()

var _t := 0.0
var _bite_at := 0.0
var _bobber: MeshInstance3D
var _stem: MeshInstance3D
var _last := Vector3.INF


func _init(w: RoamWorld = null) -> void:
	world = w
	name = "RoamFishing"
	rng.seed = 5150


func reset() -> void:
	_end()
	catches = 0
	misses = 0


func _on_foot() -> bool:
	return WorldSteps.hero_vehicle() == null and not InteriorGameplay.active


## The fishing place the hero is standing in (within START_R), {} when none.
func spot_at(hero: Vector3) -> Dictionary:
	for s in RoamData.fish_spots():
		if RoamWorld.flat(s["pos"], hero) < START_R and absf((s["pos"] as Vector3).y - hero.y) < 4.0:
			return s
	return {}


func poll(dt: float, hero: Vector3) -> void:
	var speed := 0.0
	if _last.is_finite():
		speed = RoamWorld.flat(hero, _last) / maxf(dt, 0.0001)
	_last = hero
	if world != null and world.busy():
		_end()
		return
	if state == &"idle":
		prompt = ""
		if not _on_foot():
			return
		var s := spot_at(hero)
		if s.is_empty():
			_t = 0.0
			return
		if speed > STILL:
			prompt = "FISHING  %s  STAND STILL TO CAST" % String(s["name"])
			_t = 0.0
			return
		spot = s
		prompt = "FISHING  %s  HOLD STILL" % String(s["name"])
		_t += dt
		if _t >= DWELL:
			cast_now(s)
		return
	if not _on_foot() or RoamWorld.flat(spot["pos"], hero) > LEAVE_R:
		_end()
		return
	_t += dt
	match state:
		&"wait":
			prompt = "FISHING  WAITING FOR A BITE"
			_bob(dt, false)
			if _t >= _bite_at:
				force_bite()
		&"bite":
			prompt = "BITE  TAP JUMP TO REEL"
			_bob(dt, true)
			if Input.is_action_just_pressed(&"jump") or Input.is_action_just_pressed(&"fire"):
				reel()
			elif _t >= WINDOW:
				misses += 1
				Game.say("IT GOT AWAY", 1.6)
				state = &"cooldown"
				_t = 0.0
		&"cooldown":
			prompt = "FISHING  RECASTING"
			if _t >= RECAST:
				cast_now(spot)


## Throws the line at `s` (tests and the dwell call this): the bobber floats out over the water.
func cast_now(s: Dictionary) -> void:
	spot = s
	state = &"wait"
	_t = 0.0
	_bite_at = rng.randf_range(BITE_MIN, BITE_MAX)
	Sfx.play(&"pickup")
	_place_bobber()


## A fish takes the bait now (the random wait ended, or a test asks for it).
func force_bite() -> void:
	if state != &"wait" and state != &"cooldown":
		return
	state = &"bite"
	_t = 0.0
	FX.burst(_bobber_pos(), Color(0.7, 0.9, 1.0), 8, 3.0, 0.4, 2.0)
	Sfx.play(&"ui_contract_accept", -4.0)


## Reels in: only during a bite. Returns the species caught, &"" when nothing was on the line.
func reel() -> StringName:
	if state != &"bite":
		return &""
	var water: StringName = spot.get("water", &"sea")
	var list := RoamData.fish_weights(water, RoamData.hour_now())
	var sp := AlienSpecies.pick(list, rng.randf()) if not list.is_empty() else &""
	state = &"cooldown"
	_t = 0.0
	if sp == &"":
		Game.say("NOTHING BITES HERE AT THIS HOUR", 2.0)
		return &""
	return _land(sp)


func _land(sp: StringName) -> StringName:
	catches += 1
	last_species = sp
	var f: Dictionary = RoamData.FISH[sp]
	var first := world != null and not world.fish_log.has(sp)
	var pay := int(f["pay"])
	if world != null:
		world.fish_log[sp] = int(world.fish_log.get(sp, 0)) + 1
	if first and world != null:
		world.note(&"fish", sp, "FISH LOG  %s" % String(f["name"]), pay)
	else:
		var prog := Game.progress as Progress
		if prog != null:
			prog.add_credits(maxi(pay / 3, 5))
		Game.say("CAUGHT  %s  +%d" % [String(f["name"]), maxi(pay / 3, 5)], 2.0)
		if world != null:
			world.save_now()
	FX.burst(_bobber_pos(), Color(0.6, 0.9, 1.0), 12, 4.0, 0.5, 4.0)
	caught.emit(sp, first)
	return sp


func _end() -> void:
	state = &"idle"
	_t = 0.0
	prompt = ""
	if _bobber != null:
		_bobber.visible = false


# --- the bobber -----------------------------------------------------------------------------------------------------------------------

func _bobber_pos() -> Vector3:
	if spot.is_empty():
		return Vector3.ZERO
	var p: Vector3 = spot["pos"]
	var c: Vector3 = spot["cast"]
	var q := p + c * CAST_DIST
	var w := WaterWorld.surface_y(q.x, q.z)                       # the real wave surface (render loop 2: the bobber sat 15 cm under it and was invisible)
	if w == TerrainHeight.NO_WATER:
		w = TerrainHeight.water_level_for(q.x, q.z, TerrainHeight.height_at(q.x, q.z))
	if w == TerrainHeight.NO_WATER:
		w = TerrainHeight.SEA_LEVEL
	return Vector3(q.x, w + 0.16, q.z)


func _place_bobber() -> void:
	if _bobber == null:
		_bobber = MeshInstance3D.new()
		var m := SphereMesh.new()
		m.radius = 0.32
		m.height = 0.64
		m.radial_segments = 10
		m.rings = 5
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.3, 0.25)
		m.material = mat
		_bobber.mesh = m
		_bobber.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bobber.top_level = true
		# a thin column of light over the float: the hero and the pier rail hide a small sphere from the chase camera (render loop 3)
		_stem = MissionVisuals.make_beam(Color(1.0, 0.85, 0.3), 0.09, 7.0, 2.2, 0.5)
		_stem.position.y = 3.5
		_bobber.add_child(_stem)
		add_child(_bobber)
	_bobber.global_position = _bobber_pos()
	_bobber.scale = Vector3.ONE
	_bobber.visible = true


func _bob(_dt: float, biting: bool) -> void:
	if _bobber == null:
		return
	var p := _bobber_pos()
	var k := float(Time.get_ticks_msec()) * 0.001
	p.y += 0.05 * sin(k * 2.2) - (0.18 if biting and int(k * 8.0) % 2 == 0 else 0.0)
	_bobber.global_position = p
	var pulse := 1.0 + (0.5 * absf(sin(k * 9.0)) if biting else 0.0)
	_bobber.scale = Vector3(pulse, pulse, pulse)
	if _stem != null:
		_stem.material_override = RoamMarks._beam_material(Color(1.0, 0.3, 0.25) if biting else Color(1.0, 0.85, 0.3))


## The ring of the nearest fishing place within the show radius (the world calls this while it refreshes its markers).
func show_mark(marks: RoamMarks, slot: int, hero: Vector3) -> void:
	var best := {}
	var bd := RoamWorld.SHOW_R
	for s in RoamData.fish_spots():
		var d := RoamWorld.flat(s["pos"], hero)
		if d < bd:
			bd = d
			best = s
	if not best.is_empty():
		marks.show_at(slot, best["pos"], START_R * 0.55, Color(0.4, 0.8, 1.0), false, false)
