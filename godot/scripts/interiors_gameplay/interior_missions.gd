class_name InteriorMissions
extends Node3D
## The four interior missions, one per mission interior (InteriorData.mission_for):
##   safe         OFFICE LOBBY: press USE at the glowing safe, stay beside it while it cracks (5 s, progress decays when you step away), the alarm goes off at the end
##   hostage      APARTMENT:    kill every Vael guard in the flat (the hostage kneels, cyan diamond), then USE beside the hostage to cut the restraints
##   assassinate  CLUB:         a Vael officer (240 hp, bigger than the troopers) hides at the back; the minimap shows only an area until you are within 7 m; kill him
##   hack         CHECKPOINT:   stand at the terminal (16 s fill, decays at half speed outside the ring) while the guards close in: one alerted at 20 %, 50 % and 80 %
## Rewards (credits, score, reputation) scale with the sector and reputation like contracts (InteriorData.reward). A completed mission is remembered per door (InteriorGameplay.done),
## the door glow goes back to the plain colour. Leaving or dying mid-mission resets it (the interior is rebuilt next time). Props are primitive: a marker disc, a safe box, a console.

signal completed(kind: StringName, door_id: int, reward: Dictionary)

const SAFE_TIME := 5.0
const SAFE_REACH := 2.4
const HACK_TIME := 16.0
const HACK_REACH := 2.8
const HACK_DECAY := 0.5
const HOSTAGE_REACH := 2.6
const OFFICER_FOUND := 7.0
const OFFICER_AREA := 18.0
const HACK_AUTO := 2.0                      ## seconds in the ring before the hack starts by itself (USE starts it at once; the waiting time is credited, so nobody loses progress for not pressing)

static var puzzles_on := true                ## false: no quantum gate corridor around the job object (audits, A/B)

var kind: StringName = &""
var state: StringName = &"idle"            ## idle | active | cracking (safe) | complete
var progress := 0.0
var door_id := -1
var last_reward: Dictionary = {}
var target_pos := Vector3.ZERO             ## the safe / terminal / hostage / officer position (world)
var found := false                         ## the officer was spotted
var hacking := false                       ## the hack is running (USE at the terminal, or HACK_AUTO s standing in the ring)

var puzzles: QuantumPuzzles                ## the verb-gated corridor around the mission object (B8)
var _actors: InteriorActors
var _interior: Node3D
var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D
var _pillar: MeshInstance3D
var _prop: MeshInstance3D
var _t := 0.0
var _waves := 0
var _hint := Vector3.ZERO
var _said_clear := false
var _alarm := false
var _ring_t := 0.0


func _ready() -> void:
	name = "InteriorMissions"


func is_active() -> bool:
	return state == &"active" or state == &"cracking"


## Start the mission of `k` in the built interior. `actors` already holds the hostage / officer / guards (InteriorActors.populate).
func begin(room: Node3D, k: StringName, id: int, actors: InteriorActors) -> void:
	reset()
	if k == &"":
		return
	kind = k
	door_id = id
	_interior = room
	_actors = actors
	state = &"active"
	progress = 0.0
	_waves = 0
	found = false
	_said_clear = false
	_alarm = false
	hacking = false
	_ring_t = 0.0
	var seed_value := int(room.get("seed"))
	match k:
		&"safe":
			target_pos = InteriorGameplay.anchor_points(room, &"safe", 1, seed_value)[0]["pos"]
			_make_safe(target_pos)
			_marker_at(target_pos, Color(1.0, 0.72, 0.25))
		&"hostage":
			target_pos = actors.hostage.global_position if actors.hostage != null else InteriorGameplay.anchor_points(room, &"hostage", 1, seed_value)[0]["pos"]
		&"assassinate":
			target_pos = actors.officer.global_position if is_instance_valid(actors.officer) else InteriorGameplay.anchor_points(room, &"officer", 1, seed_value)[0]["pos"]
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			var a := rng.randf() * TAU
			_hint = Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(4.0, 8.0)
		&"hack":
			target_pos = InteriorGameplay.anchor_points(room, &"terminal", 1, seed_value)[0]["pos"]
			_make_console(target_pos)
			_marker_at(target_pos, Color(0.45, 0.95, 1.0))
	var toward: Vector3 = (room.get("door_pos") as Vector3) - target_pos
	puzzles = null
	if puzzles_on and k != &"assassinate":                 # the officer walks: a cage built round where he starts would be empty or trap him (the other three jobs hold still)
		# the gate corridor only where it fits and leaves the job reachable (a null result = no puzzle in this room)
		var must: Array[Vector3] = []
		puzzles = QuantumPuzzles.build_fitted(self, QuantumPuzzles.room_for(k, seed_value), target_pos, toward, room, must)
	_say(&"start")
	Sfx.play(&"mission_start")


func reset() -> void:
	kind = &""
	state = &"idle"
	progress = 0.0
	door_id = -1
	_actors = null
	_interior = null
	found = false
	hacking = false
	_ring_t = 0.0
	if is_instance_valid(puzzles):
		puzzles.queue_free()
	puzzles = null
	if _marker != null:
		_marker.queue_free()
		_marker = null
	if _pillar != null:
		_pillar.queue_free()
		_pillar = null
	if _prop != null:
		_prop.queue_free()
		_prop = null


# --- props ----------------------------------------------------------------------------------------------------------

func _marker_at(p: Vector3, col: Color) -> void:
	if _marker == null:
		_marker = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.55
		cm.bottom_radius = 0.55
		cm.height = 0.03
		cm.radial_segments = 20
		cm.rings = 1
		_marker.mesh = cm
		_marker_mat = StandardMaterial3D.new()
		_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_marker_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_marker.material_override = _marker_mat
		_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_marker)
		_pillar = MeshInstance3D.new()                       # a thin light column: the objective can be seen across a dark room
		var pm := CylinderMesh.new()
		pm.top_radius = 0.05
		pm.bottom_radius = 0.05
		pm.height = 3.2
		pm.radial_segments = 6
		pm.rings = 1
		_pillar.mesh = pm
		_pillar.material_override = _marker_mat
		_pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_pillar)
	_marker_mat.albedo_color = Color(col.r * 1.4, col.g * 1.4, col.b * 1.4, 0.8)
	_marker.global_position = Vector3(p.x, p.y + 0.04, p.z)
	_marker.visible = true
	_pillar.global_position = Vector3(p.x, p.y + 1.6, p.z)
	_pillar.visible = true


func _make_safe(p: Vector3) -> void:
	var b := InteriorCivilian.MB.new()
	b.box(Vector3(0.0, 0.5, 0.0), Vector3(0.9, 1.0, 0.7), Color(0.3, 0.33, 0.38, 1.0))
	b.box(Vector3(0.0, 0.58, 0.37), Vector3(0.55, 0.55, 0.05), Color(0.2, 0.22, 0.25, 1.0))
	b.box(Vector3(0.22, 0.55, 0.41), Vector3(0.1, 0.16, 0.03), Color(1.0, 0.7, 0.2, 1.0))
	_make_prop(b, p)


func _make_console(p: Vector3) -> void:
	var b := InteriorCivilian.MB.new()
	b.box(Vector3(0.0, 0.45, 0.0), Vector3(1.1, 0.9, 0.55), Color(0.1, 0.12, 0.14, 1.0))
	b.box(Vector3(0.0, 1.05, -0.12), Vector3(1.0, 0.5, 0.06), Color(0.3, 0.9, 1.0, 1.0))
	_make_prop(b, p)


func _make_prop(b, p: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.6
	mat.metallic = 0.0
	mat.emission_enabled = true                              # a standard material gets no light from the room's baked pools: the safe was a black block (director review 4, #2)
	mat.emission = Color(0.26, 0.28, 0.32)
	mat.emission_energy_multiplier = 1.0
	_prop = MeshInstance3D.new()
	_prop.mesh = b.build(mat, false, true)
	add_child(_prop)
	_prop.global_position = p
	# face the room centre
	if _interior != null:
		var c := Vector3((_interior.get("bounds") as Rect2).get_center().x, p.y, (_interior.get("bounds") as Rect2).get_center().y)
		var d := c - p
		_prop.rotation.y = atan2(-d.x, -d.z) + PI


# --- interaction ----------------------------------------------------------------------------------------------------

## The USE prompt text near the mission object ("" when nothing to do here).
func prompt_for(pos: Vector3) -> String:
	if not is_active():
		return ""
	match kind:
		&"safe":
			if state == &"active" and _dist(pos, target_pos) < SAFE_REACH:
				return "CRACK THE SAFE"
		&"hostage":
			if _actors != null and _actors.guards_alive() == 0 and _actors.hostage != null and not _actors.hostage.freed and _dist(pos, _actors.hostage.global_position) < HOSTAGE_REACH:
				return "FREE THE HOSTAGE"
		&"hack":
			if state == &"active" and not hacking and _dist(pos, target_pos) < HACK_REACH:
				return "HACK THE TERMINAL"
	return ""


## USE pressed: returns true when the mission consumed the press.
func interact(pos: Vector3) -> bool:
	if prompt_for(pos) == "":
		return false
	match kind:
		&"safe":
			state = &"cracking"
			Sfx.play(&"ui_tap")
			return true
		&"hostage":
			_actors.hostage.free_up(InteriorGameplay.exit_point(_interior))
			_finish()
			return true
		&"hack":
			hacking = true
			Sfx.play(&"ui_tap")
			return true
	return false


func _dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- simulation -----------------------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	if not is_active() or not Game.is_playing() or _actors == null:
		return
	_t += delta
	if is_instance_valid(puzzles):
		puzzles.tick_live(delta)
	var pl := Game.player
	var pp: Vector3 = pl.global_position if is_instance_valid(pl) else Vector3.ZERO
	if _marker != null and _marker.visible:
		_marker_mat.albedo_color.a = 0.55 + 0.25 * sin(_t * 5.0)
	match kind:
		&"safe":
			if state == &"cracking":
				if _dist(pp, target_pos) < SAFE_REACH + 0.6:
					progress = minf(1.0, progress + delta / SAFE_TIME)
				else:
					progress = maxf(0.0, progress - delta * 0.25)
					if progress <= 0.0:
						state = &"active"
				if progress >= 1.0:
					_alarm_and_finish()
		&"hostage":
			if not _said_clear and _actors.guards_alive() == 0:
				_said_clear = true
				_say(&"clear")
				if _actors.hostage != null:
					_marker_at(_actors.hostage.global_position, Color(0.4, 0.95, 1.0))
			progress = 1.0 - float(_actors.guards_alive()) / 3.0 if not _said_clear else 1.0
		&"assassinate":
			var o := _actors.officer
			if not is_instance_valid(o) or not o.active or o.dead:
				_finish()
				return
			target_pos = o.global_position
			if not found and _dist(pp, target_pos) < OFFICER_FOUND:
				found = true
				_say(&"found")
		&"hack":
			var inside := _dist(pp, target_pos) < HACK_REACH
			if inside:
				_ring_t += delta
				if not hacking and _ring_t >= HACK_AUTO:
					hacking = true
					progress = minf(1.0, progress + (_ring_t - delta) / HACK_TIME)     # the waiting time counts
				if hacking:
					progress = minf(1.0, progress + delta / HACK_TIME)
			else:
				_ring_t = 0.0
				progress = maxf(0.0, progress - delta * HACK_DECAY / HACK_TIME)
			while _waves < 3 and progress >= [0.2, 0.5, 0.8][_waves]:
				_waves += 1
				_close_in()
			if progress >= 1.0:
				_finish()


## One more guard turns hostile and rushes the terminal; a dead one is replaced from the guard anchors while the cap allows.
func _close_in() -> void:
	_say(&"wave")
	Game.add_heat(0.3)
	var done := false
	for g in _actors.guards:
		if is_instance_valid(g) and g.active and not g.dead and not g.aware:
			g.alert()
			done = true
			break
	if not done and _actors.total() < InteriorData.ACTOR_CAP:
		var em := Game.enemies as EnemyManager
		var anchors := InteriorGameplay.anchor_points(_interior, &"guard", 2, int(_interior.get("seed")))
		if em != null:
			var g := em.spawn(&"operative", anchors[_waves % anchors.size()]["pos"], true)
			if g != null:
				_actors.guards.append(g)


func _alarm_and_finish() -> void:
	_alarm = true
	_say(&"alarm")
	Game.add_heat(1.0)
	_actors.alert_all()
	_finish()


func _finish() -> void:
	if state == &"complete" or kind == &"":
		return
	state = &"complete"
	progress = 1.0
	var prog := Game.progress as Progress
	var ch := int(Game.story.get("chapter")) if is_instance_valid(Game.story) else 0
	var rep := prog.reputation if prog != null else 0
	var r := InteriorData.reward(kind, ch, rep)
	last_reward = r
	if prog != null:
		prog.add_credits(int(r["credits"]))
		prog.bonus_score(int(r["score"]))
		prog.add_reputation(int(r["rep"]))
		prog.contracts_done += 1
		Crafting.award(&"contract")
	else:
		Game.add_score(int(r["score"]))
	if _marker != null:
		_marker.visible = false
	if _pillar != null:
		_pillar.visible = false
	if not _alarm:
		_say(&"done")
	Game.say("%s COMPLETE  +%d CREDITS" % [str(kind).to_upper(), int(r["credits"])], 3.0)
	Sfx.play(&"ui_contract_complete")
	completed.emit(kind, door_id, r)


func _say(stage: StringName) -> void:
	var lines: Dictionary = InteriorData.MISSION_LINES.get(kind, {})
	if not lines.has(str(stage)) and not lines.has(stage):
		return
	var text := str(lines.get(str(stage), lines.get(stage, "")))
	InteriorGameplay.radio("ORACLE", text, "int_%s_%s" % [str(kind), str(stage)], 0.0, 1)


# --- display ----------------------------------------------------------------------------------------------------------

## The HUD priority line ("" when no mission is running here).
func hud_line() -> String:
	if state == &"complete" or kind == &"":
		return ""
	match kind:
		&"safe":
			return "SAFE  CRACKING  %d%%" % int(progress * 100.0) if state == &"cracking" else "SAFE  REACH THE VAULT"
		&"hostage":
			var n := _actors.guards_alive() if _actors != null else 0
			return "HOSTAGE  CLEAR THE FLAT  %d LEFT" % n if n > 0 else "HOSTAGE  CUT HER FREE"
		&"assassinate":
			return "OFFICER  TARGET SPOTTED" if found else "OFFICER  FIND THE TARGET"
		&"hack":
			return "TERMINAL  HACKING  %d%%" % int(progress * 100.0) if hacking or progress > 0.0 else "TERMINAL  GO TO THE CONSOLE AND HACK IT"
	return ""


## What the job shows in the room right now: [{id, pos, label, height, objective}], the floating text over the safe, the hostage, the terminal, the officer (or the area he hides in).
## `prompt_for` / `interact` are the USE side of the same objects.
func interactables() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_active():
		return out
	match kind:
		&"safe":
			out.append({"id": &"safe", "pos": target_pos, "label": "CRACK THE SAFE" if state == &"active" else "CRACKING  %d%%" % int(progress * 100.0), "height": 1.5, "objective": true})
		&"hostage":
			if _actors != null and _actors.hostage != null and not _actors.hostage.freed:
				var n := _actors.guards_alive()
				out.append({"id": &"hostage", "pos": _actors.hostage.global_position, "label": "FREE THE HOSTAGE" if n == 0 else "CLEAR THE ROOM FIRST  %d LEFT" % n, "height": 2.0, "objective": n == 0})
		&"assassinate":
			if found:
				out.append({"id": &"officer", "pos": target_pos, "label": "TARGET", "height": 2.5, "objective": true})
			else:
				out.append({"id": &"officer_area", "pos": target_pos + _hint, "label": "FIND THE OFFICER", "height": 1.8, "objective": true})
		&"hack":
			out.append({"id": &"terminal", "pos": target_pos, "label": ("HACKING  %d%%" % int(progress * 100.0)) if hacking else "HACK THE TERMINAL", "height": 1.7, "objective": true})
	return out


## Minimap markers: {pos: Vector3, color: Color, kind: StringName ("target" / "area" / "zone"), radius: float}.
func markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_active():
		return out
	match kind:
		&"safe":
			out.append({"pos": target_pos, "color": Color(1.0, 0.72, 0.25), "kind": &"target", "radius": 1.0})
		&"hack":
			out.append({"pos": target_pos, "color": Color(0.45, 0.95, 1.0), "kind": &"zone", "radius": HACK_REACH})
		&"hostage":
			if _actors != null and _actors.hostage != null and not _actors.hostage.freed:
				out.append({"pos": _actors.hostage.global_position, "color": Color(0.4, 0.95, 1.0), "kind": &"target", "radius": 1.0})
		&"assassinate":
			if found:
				out.append({"pos": target_pos, "color": Color(1.0, 0.3, 0.32), "kind": &"target", "radius": 1.0})
			else:
				out.append({"pos": target_pos + _hint, "color": Color(1.0, 0.3, 0.32), "kind": &"area", "radius": OFFICER_AREA})
	return out
