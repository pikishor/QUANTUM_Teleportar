class_name RailWorld
extends Node3D
## The railway in the live world (data: RailNet; meshes: RailKit; rolling stock: Train + TrainKit; timetable: RailSchedule). Child `RailWorld` of the City (RailWorld.attach). `QT_NO_RAIL=1` leaves it out.
##  * CHUNKS: every route is cut into 320 m chunks (one merged mesh, one draw call each, culled beyond 650 m), built lazily when the hero comes within 1 km (one per frame), their colliders
##    (viaduct piers, platforms, stairs, station halls, tunnel tubes) when he is within 480 m.
##  * TRAINS: six trains on the three timetables, pooled cars, solid only near the hero (see Train). `clock` drives the timetable (seconds, runs while the game is playing).
##  * LEVEL CROSSINGS: barriers that come down and flash red lights while a train approaches, a bell, solid arms (a car cannot pass a lowered barrier).
##  * SIGNALS: red while a train stands in the block they guard, green otherwise.
##  * RIDING: the hero boards through the door gaps or from a platform, stands on the floor (carried by the moving car), sits at a seat (control hold), climbs a ladder to the roof.
##    `use_prompt()` / `use_do()` are the contextual USE (see RideUse).
##  * A tunnel light follows the hero inside a tube.
## Tests ask `stats()`, `train(id)`, `ensure_near(pos)`, `set_clock(t)`.

const SHOW_RANGE := 650.0
const BUILD_RANGE := 1000.0
const EVICT_MARGIN := 80.0               ## a built chunk this far beyond BUILD_RANGE (its colliders: beyond COLLIDER_RANGE) is freed again; a small margin keeps the streamed state a function of where the hero stands
const COLLIDER_RANGE := 480.0
const SIGNAL_RANGE := 420.0
const APPROACH := 150.0
const GATE_DOWN_SPEED := 0.55
const BEACON_RANGE := 3200.0

static var instance: RailWorld = null

var clock := 0.0
var chunks: Array[Dictionary] = []                  ## {route, i0, i1, org, node, body, built, tris}
var trains: Array[Train] = []
var schedules := {}                                 ## route id -> RailSchedule
var gates: Array[Dictionary] = []                   ## level crossings: {c, root, arm_a, arm_b, lamps, gate (1 open .. 0 down), body, bell}
var signals: Array[Dictionary] = []                 ## {route, sg, lamps [red, green], state}
var tris := 0
var colliders := 0
var jobs: RailJobs
var seated := false
var _seat_world := Vector3.ZERO
var _build_t := 0.0
var _hero := Vector3.INF
var _tunnel_light: OmniLight3D
var _in_tunnel := false
var _flash := 0.0
var _prompt := ""
var _prompt_kind := &""
var _prompt_data := {}
var _lamp_mats := {}


static func attach(parent: Node) -> RailWorld:
	var w := RailWorld.new()
	w.name = "RailWorld"
	parent.add_child(w)
	return w


func _ready() -> void:
	instance = self
	process_physics_priority = -5                        # the cars move before the hero's own tick
	RailNet.ensure()
	for r in RailNet.routes():
		schedules[r["id"]] = RailSchedule.new(r)
		for rng in RailKit.chunk_ranges(r):
			var org := Vector3.ZERO
			var F := RailKit.frames(r)
			for i in range(rng.x, rng.y + 1):
				org += (F[i]["p"] as Vector3)
			org /= float(rng.y - rng.x + 1)
			org.y = 0.0
			chunks.append({"route": r["id"], "i0": rng.x, "i1": rng.y, "org": org, "node": null, "body": null, "built": false, "tris": 0, "colliders": false, "tubes": []})
		for td: Dictionary in r["trains"]:
			var t := Train.new()
			t.setup(r, td["kind"], float(td["phase"]), schedules[r["id"]])
			add_child(t)
			trains.append(t)
		for c: Dictionary in r["crossings"]:
			if bool(c["level"]):
				_make_gate(r, c)
		for sg: Dictionary in r["signals"]:
			_make_signal(r, sg)
		for st: Dictionary in r["stations"]:
			_make_label(r, st)
	_tunnel_light = OmniLight3D.new()
	_tunnel_light.name = "TunnelLight"
	_tunnel_light.omni_range = 30.0
	_tunnel_light.light_energy = 1.6
	_tunnel_light.shadow_enabled = false
	_tunnel_light.visible = false
	add_child(_tunnel_light)
	jobs = RailJobs.new()
	jobs.name = "RailJobs"
	add_child(jobs)
	var pl := Game.player as CharacterBody3D
	if pl != null:
		pl.platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING     # stepping off a moving train does not throw the hero along the track
	set_process(true)
	set_physics_process(true)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func set_clock(t: float) -> void:
	clock = t
	for tr in trains:
		tr.evaluate(clock)


func route_of(id: StringName) -> Dictionary:
	return RailNet.route(id)


func train(route_id: StringName, kind: StringName = &"") -> Train:
	for t in trains:
		if t.route["id"] == route_id and (kind == &"" or t.kind == kind):
			return t
	return null


# --- chunks -----------------------------------------------------------------------------------------------------------------------------

func _build_chunk(ch: Dictionary) -> void:
	if ch["built"]:
		return
	var r := RailNet.route(ch["route"])
	var res := RailKit.build_chunk(r, int(ch["i0"]), int(ch["i1"]))
	var mi := MeshInstance3D.new()
	mi.name = "Chunk_%s_%d" % [String(ch["route"]), int(ch["i0"])]
	mi.mesh = res["mesh"]
	mi.position = res["origin"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.visibility_range_end = SHOW_RANGE
	mi.visibility_range_end_margin = 30.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	add_child(mi)
	ch["node"] = mi
	ch["built"] = true
	ch["tris"] = int(res["tris"])
	ch["boxes"] = res["boxes"]
	tris += int(res["tris"])


func _evict_chunk(ch: Dictionary) -> void:
	if is_instance_valid(ch.get("node")):
		(ch["node"] as Node).queue_free()
	_evict_colliders(ch)
	tris -= int(ch.get("tris", 0))
	ch["node"] = null
	ch["built"] = false


func _evict_colliders(ch: Dictionary) -> void:
	if is_instance_valid(ch.get("body")):
		colliders -= (ch["body"] as Node).get_child_count()
		(ch["body"] as Node).queue_free()
	for tb: Variant in (ch["tubes"] as Array):
		if is_instance_valid(tb):
			colliders -= 1
			(tb as Node).queue_free()
	(ch["tubes"] as Array).clear()
	ch["body"] = null
	ch["colliders"] = false


func _build_colliders(ch: Dictionary) -> void:
	if ch["colliders"]:
		return
	ch["colliders"] = true
	if not ch["built"]:
		_build_chunk(ch)
	var body := StaticBody3D.new()
	body.name = "Collision_%s_%d" % [String(ch["route"]), int(ch["i0"])]
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	var r := RailNet.route(ch["route"])
	var F := RailKit.frames(r)
	var mode: PackedByteArray = r["mode"]
	# viaduct decks: a box per segment, its top at the bed height; parapets on both sides
	for i in range(int(ch["i0"]), int(ch["i1"])):
		if mode[i] != RailNet.MODE_VIADUCT:
			continue
		var a: Vector3 = F[i]["p"]
		var b: Vector3 = F[i + 1]["p"]
		var d := b - a
		var l := d.length()
		if l < 0.3:
			continue
		var fwd := d / l
		var rt := RailNet.right_of(Vector3(fwd.x, 0.0, fwd.z).normalized())
		var up := rt.cross(fwd).normalized()
		var basis := Basis(rt, up, -fwd)
		var mid := (a + b) * 0.5
		_box(body, Transform3D(basis, mid - up * 0.6), Vector3(RailKit.DECK_HW * 2.0, 1.2, l + 0.3))
		for sx in [-1.0, 1.0]:
			_box(body, Transform3D(basis, mid + rt * float(sx) * (RailKit.DECK_HW - 0.12) + up * 0.55), Vector3(0.3, 1.2, l + 0.3))
	for bx: Dictionary in (ch["boxes"] as Array):
		var bs := Basis(Vector3.UP, float(bx["yaw"]))
		if bx.has("pitch"):
			bs = bs * Basis(Vector3.RIGHT, float(bx["pitch"]))
		_box(body, Transform3D(bs, bx["pos"]), bx["size"])
	add_child(body)
	ch["body"] = body
	# tunnel tubes whose run touches this chunk are built with the first chunk that contains their start
	for run: Dictionary in r["tunnels"]:
		if int(run["i0"]) >= int(ch["i0"]) and int(run["i0"]) < int(ch["i1"]):
			_tunnel_collider(r, run, ch)


func _box(body: StaticBody3D, xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = xf
	body.add_child(cs)
	colliders += 1


func _tunnel_collider(r: Dictionary, run: Dictionary, ch: Dictionary = {}) -> void:
	var res := RailKit.tunnel_collider_mesh(r, run)
	var body := StaticBody3D.new()
	body.name = "Tube_%s_%d" % [String(r["id"]), int(run["i0"])]
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = (res["mesh"] as ArrayMesh).create_trimesh_shape()
	body.add_child(cs)
	body.position = res["origin"]
	add_child(body)
	colliders += 1
	if not ch.is_empty():
		(ch["tubes"] as Array).append(body)


## Build every chunk (and the colliders) within `radius` of `pos` now (tests, teleports).
func ensure_near(pos: Vector3, radius := 700.0, with_colliders := true) -> int:
	var n := 0
	for ch in chunks:
		var d := Vector2((ch["org"] as Vector3).x - pos.x, (ch["org"] as Vector3).z - pos.z).length()
		if d < radius + 200.0:
			if not ch["built"]:
				_build_chunk(ch)
				n += 1
			if with_colliders and d < radius and not ch["colliders"]:
				_build_colliders(ch)
	return n


# --- gates, signals, labels ---------------------------------------------------------------------------------------------------------

func _lamp_material(kind: StringName) -> StandardMaterial3D:
	if _lamp_mats.has(kind):
		return _lamp_mats[kind]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	match kind:
		&"red":
			m.albedo_color = Color(1.0, 0.12, 0.1)
		&"green":
			m.albedo_color = Color(0.2, 1.0, 0.35)
		&"amber":
			m.albedo_color = Color(1.0, 0.7, 0.15)
		_:
			m.albedo_color = Color(0.12, 0.08, 0.08)
	_lamp_mats[kind] = m
	return m


func _lamp(parent: Node3D, pos: Vector3, size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	mi.position = pos
	mi.material_override = _lamp_material(&"off")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = SIGNAL_RANGE
	parent.add_child(mi)
	return mi


func _make_gate(r: Dictionary, c: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Crossing_%s_%d" % [String(r["id"]), int(c["i"])]
	var p: Vector3 = c["pos"]
	root.position = p
	var rd := Vector3((c["road_dir"] as Vector2).x, 0.0, (c["road_dir"] as Vector2).y)
	var rw: float = float(c["road_w"])
	var arms: Array[Node3D] = []
	var lamps: Array[MeshInstance3D] = []
	var bodies: Array[StaticBody3D] = []
	for sd in [-1.0, 1.0]:
		var travel := rd * float(sd)
		var right := RailNet.right_of(travel)
		var pivot := Node3D.new()
		pivot.position = -travel * (RailNet.HALF_SEP + 4.4) + right * (rw * 0.5 + 0.7) + Vector3(0.0, 1.15, 0.0)
		pivot.basis = Basis.looking_at(-right, Vector3.UP)           # the arm extends along local -Z = across the road towards its centre
		root.add_child(pivot)
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.35, 1.3, 0.35)
		post.mesh = pm
		post.position = pivot.position - Vector3(0.0, 0.55, 0.0)
		post.material_override = _flat(Color(0.18, 0.18, 0.2))
		root.add_child(post)
		var arm_len := rw * 0.5 + 0.6
		for k in 6:                                                   # a striped arm: red and white boxes
			var seg := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(0.14, 0.14, arm_len / 6.0)
			seg.mesh = sm
			seg.position = Vector3(0.0, 0.0, -(float(k) + 0.5) * arm_len / 6.0)
			seg.material_override = _flat(Color(0.9, 0.1, 0.08) if k % 2 == 0 else Color(0.95, 0.95, 0.95))
			seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			seg.visibility_range_end = SIGNAL_RANGE
			pivot.add_child(seg)
		var lamp := _lamp(pivot, Vector3(0.0, 0.0, -arm_len + 0.25), 0.34)
		lamp.basis = Basis(Vector3.UP, 0.0)
		lamps.append(lamp)
		var head := _lamp(root, pivot.position + Vector3(0.0, 0.5, 0.0) + travel * 0.2, 0.34)
		head.basis = Basis.looking_at(travel, Vector3.UP)
		lamps.append(head)
		arms.append(pivot)
		var sb := StaticBody3D.new()
		sb.collision_layer = 0
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.3, 0.5, arm_len)
		cs.shape = bs
		cs.position = Vector3(0.0, 0.0, -arm_len * 0.5)
		sb.add_child(cs)
		pivot.add_child(sb)
		bodies.append(sb)
	add_child(root)
	gates.append({"c": c, "route": r["id"], "root": root, "arms": arms, "lamps": lamps, "bodies": bodies, "gate": 1.0, "closed": false, "bell": null})


func _flat(col: Color) -> StandardMaterial3D:
	var key := StringName("flat_%s" % col.to_html())
	if _lamp_mats.has(key):
		return _lamp_mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.7
	_lamp_mats[key] = m
	return m


func _make_signal(r: Dictionary, sg: Dictionary) -> void:
	var hd := RailKit.signal_head(r, sg)
	var root := Node3D.new()
	root.name = "Signal"
	root.position = hd[0]
	root.rotation.y = float(hd[1])
	add_child(root)
	var red := _lamp(root, Vector3(0.0, 0.3, 0.16), 0.3)
	var green := _lamp(root, Vector3(0.0, -0.2, 0.16), 0.3)
	signals.append({"route": r["id"], "sg": sg, "red": red, "green": green, "state": &"", "pos": hd[0]})


func _make_label(r: Dictionary, st: Dictionary) -> void:
	var pa := RailNet.point_at(r, float(st["s"]))
	var t := Vector3((pa[1] as Vector3).x, 0.0, (pa[1] as Vector3).z).normalized()
	var rt := RailNet.right_of(t)
	var lab := Label3D.new()
	lab.name = "Label_%s" % String(st["name"]).replace(" ", "_")
	lab.text = String(st["name"])
	lab.font_size = 96
	lab.pixel_size = 0.016
	lab.outline_size = 14
	lab.modulate = Color(1.0, 0.98, 0.9)
	lab.outline_modulate = Color(0.05, 0.12, 0.28)
	lab.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lab.double_sided = true
	lab.shaded = false
	lab.visibility_range_end = 280.0
	var under: bool = bool(st["underground"])
	lab.position = (pa[0] as Vector3) + rt * (RailNet.HALF_SEP * float(pa[2]) + 5.8) + Vector3(0.0, RailNet.PLATFORM_Y + (3.6 if not under else 4.4), 0.0)
	add_child(lab)


# --- the frame -------------------------------------------------------------------------------------------------------------------------

func _hero_pos() -> Vector3:
	var p := Game.player as Node3D
	return p.global_position if is_instance_valid(p) else Vector3.INF


func _process(delta: float) -> void:
	_hero = _hero_pos()
	_build_t -= delta
	if _build_t <= 0.0 and _hero.is_finite():
		_build_t = 0.05
		for _k in 3:                                                   # up to three chunk jobs per tick: after a teleport the track around the hero is back within a couple of seconds
			if not _stream_chunks():
				break
	_flash += delta
	_tick_gates(delta)
	_tick_signals(delta)
	_tick_tunnel_light()


func _stream_chunks() -> bool:
	var built := 0
	var best: Dictionary = {}
	var bd := 1.0e12
	for ch in chunks:
		var d := Vector2((ch["org"] as Vector3).x - _hero.x, (ch["org"] as Vector3).z - _hero.z).length()
		if d > BUILD_RANGE + EVICT_MARGIN and ch["built"]:
			_evict_chunk(ch)                                           # far behind the hero: the mesh and the colliders go (a chunk is rebuilt when he comes back)
			continue
		if d > COLLIDER_RANGE + EVICT_MARGIN and ch["colliders"]:
			_evict_colliders(ch)
		if d < BUILD_RANGE and not ch["built"] and d < bd:
			bd = d
			best = ch
		if d < COLLIDER_RANGE and ch["built"] and not ch["colliders"]:
			_build_colliders(ch)
			return true
	if not best.is_empty():
		_build_chunk(best)
		return true
	return false


func _physics_process(delta: float) -> void:
	if Game.is_playing():
		clock += delta
	_hero = _hero_pos()
	for t in trains:
		t.step(delta, clock, _hero)
	_hold_seated()
	if Game.is_playing() and Input.is_action_just_pressed(&"interact"):
		use_do()


func _tick_gates(delta: float) -> void:
	var hero := _hero
	for g in gates:
		var c: Dictionary = g["c"]
		var u: float = float(c["u"])
		var want_closed := false
		for t in trains:
			if t.route["id"] != g["route"] or not t.active:
				continue
			var d := t.u() - u
			var gap := maxf(absf(d) - t.length * 0.5, 0.0)
			var heading := float(t.lane_dir()) * -d > 0.0                 # moving towards the crossing
			if gap <= 8.0 or (gap < APPROACH and heading and t.speed() > 0.3):
				want_closed = true
		var near := hero.is_finite() and Vector2(hero.x - (c["pos"] as Vector3).x, hero.z - (c["pos"] as Vector3).z).length() < 260.0
		var target := 0.0 if want_closed else 1.0
		var gv: float = g["gate"]
		gv = move_toward(gv, target, GATE_DOWN_SPEED * delta * (1.0 if target < gv else 0.8))
		g["gate"] = gv
		g["closed"] = gv < 0.05
		for k in (g["arms"] as Array).size():
			((g["arms"] as Array)[k] as Node3D).rotation.x = deg_to_rad(80.0) * gv * (1.0 if true else -1.0)
		var flashing := gv < 0.99
		var phase_on := int(_flash * 1.6) % 2 == 0
		var lamps: Array = g["lamps"]
		for k in lamps.size():
			var on := flashing and ((k % 2 == 0) == phase_on)
			(lamps[k] as MeshInstance3D).material_override = _lamp_material(&"red" if on else &"off")
		for sb in g["bodies"]:
			(sb as StaticBody3D).collision_layer = Game.L_WORLD if gv < 0.35 else 0
		var bell := g["bell"] as AudioStreamPlayer3D
		if flashing and near and not Sfx.muted:
			if bell == null:
				var st := Sfx.variants_of(&"crossing_bell")
				if not st.is_empty():
					bell = AudioStreamPlayer3D.new()
					if st[0] is AudioStreamOggVorbis:
						(st[0] as AudioStreamOggVorbis).loop = true
					bell.stream = st[0]
					bell.unit_size = 14.0
					bell.max_distance = 220.0
					(g["root"] as Node3D).add_child(bell)
					g["bell"] = bell
			if bell != null and not bell.playing:
				bell.play()
		elif bell != null and bell.playing:
			bell.stop()


func _tick_signals(_delta: float) -> void:
	if not _hero.is_finite():
		return
	for sg in signals:
		var pos: Vector3 = sg["pos"]
		if Vector2(pos.x - _hero.x, pos.z - _hero.z).length() > SIGNAL_RANGE:
			continue
		var s: Dictionary = sg["sg"]
		var red := false
		for t in trains:
			if t.route["id"] != sg["route"]:
				continue
			if String(s["kind"]) == "station":
				if int(t.state["stop"]) >= 0 and t.sched.names[int(t.state["stop"])] == String(s["station"]):
					red = true
			elif t.derailed and (t.u() - float(s["u"])) * float(s["dir"]) > 0.0 and absf(t.u() - float(s["u"])) < 900.0:
				red = true
		var st: StringName = &"red" if red else &"green"
		if st != sg["state"]:
			sg["state"] = st
			(sg["red"] as MeshInstance3D).material_override = _lamp_material(&"red" if red else &"off")
			(sg["green"] as MeshInstance3D).material_override = _lamp_material(&"green" if not red else &"off")


func _tick_tunnel_light() -> void:
	if not _hero.is_finite():
		_tunnel_light.visible = false
		return
	var nr := RailNet.nearest(_hero.x, _hero.z)
	var inside := int(nr[1]) >= 0 and int(nr[3]) == RailNet.MODE_TUNNEL and float(nr[0]) < 9.0 and _hero.y < float(nr[2]) + 8.0
	_in_tunnel = inside
	_tunnel_light.visible = inside
	if inside:
		_tunnel_light.global_position = _hero + Vector3(0.0, 3.4, 0.0)


func in_tunnel() -> bool:
	return _in_tunnel


# --- riding -------------------------------------------------------------------------------------------------------------------------

## The car the hero stands in or on (null when none): {train, i, local (hero in car space)}.
func car_under(pos: Vector3) -> Dictionary:
	for t in trains:
		if not t.active:
			continue
		if t.centre().distance_to(pos) > t.length * 0.5 + 12.0:
			continue
		for i in t.cars.size():
			var xf := (t.cars[i]["root"] as Node3D).global_transform
			var lp := xf.affine_inverse() * pos
			var half := float(t.cars[i]["len"]) * 0.5 + 0.5
			if absf(lp.x) < 1.8 and absf(lp.z) < half and lp.y > TrainKit.FLOOR - 0.6 and lp.y < float((t.cars[i]["spec"] as Dictionary)["roof_y"]) + 2.5:
				return {"train": t, "i": i, "local": lp, "xf": xf}
	return {}


func riding(pos: Vector3) -> bool:
	return not car_under(pos).is_empty()


func _hold_seated() -> void:
	var p := Game.player as Node3D
	if not is_instance_valid(p):
		return
	if seated:
		if p.get("control_hold") == null:
			seated = false
			return
		p.set(&"control_hold", true)
		if Input.is_action_just_pressed(&"jump"):
			stand_up()


func stand_up() -> void:
	seated = false
	var p := Game.player as Node3D
	if is_instance_valid(p) and p.get("control_hold") != null:
		p.set(&"control_hold", false)


## The contextual USE: "CLIMB TO ROOF" at a car end, "SIT" at a seat inside a car, "STAND UP" when seated. "" otherwise.
func use_prompt() -> String:
	var p := Game.player as Node3D
	_prompt = ""
	_prompt_kind = &""
	_prompt_data = {}
	if not is_instance_valid(p) or not Game.is_playing():
		return ""
	var pos := p.global_position
	if seated:
		_prompt = "STAND UP"
		_prompt_kind = &"stand"
		return _prompt
	if p.get("vehicle") != null:
		return ""
	var best_d := 2.6
	for t in trains:
		if not t.active or t.centre().distance_to(pos) > t.length * 0.5 + 10.0:
			continue
		for i in t.cars.size():
			var xf := (t.cars[i]["root"] as Node3D).global_transform
			var lp := xf.affine_inverse() * pos
			var spec: Dictionary = t.cars[i]["spec"]
			var half := float(t.cars[i]["len"]) * 0.5
			# seats: inside the car (above the floor, within the walls)
			if bool(spec["hollow"]) and absf(lp.x) < 1.5 and absf(lp.z) < half and lp.y > TrainKit.FLOOR - 0.4 and lp.y < TrainKit.FLOOR + 2.2:
				for sp: Vector3 in spec["seats"]:
					var d := Vector2(lp.x - sp.x, lp.z - sp.z).length()
					if d < 1.15 and d < best_d:
						best_d = d
						_prompt = "SIT"
						_prompt_kind = &"sit"
						_prompt_data = {"world": xf * sp}
			# ladders at the car ends: standing near an end on the ground or the platform, not on the roof
			if lp.y < float(spec["roof_y"]) - 1.6:
				for ld: Vector3 in spec["ladders"]:
					var d2 := Vector2(absf(lp.x) - 1.7, lp.z - signf(ld.z) * (half + 0.1)).length()
					var d3 := Vector2(absf(lp.x) - 1.7, lp.z - signf(ld.z) * (half - 2.4)).length()
					var dd := minf(d2, d3)
					if dd < 3.6 and dd < best_d:
						best_d = dd
						_prompt = "CLIMB TO ROOF"
						_prompt_kind = &"climb"
						var inward := -signf(ld.z) if absf(ld.z) > 0.01 else 1.0
						_prompt_data = {"world": xf * Vector3(0.0, float(spec["roof_y"]) + 0.6, signf(ld.z) * (half - 1.8))}
	return _prompt


func use_do() -> bool:
	var pr := use_prompt()
	if pr == "":
		return false
	var p := Game.player as CharacterBody3D
	match _prompt_kind:
		&"stand":
			stand_up()
		&"sit":
			seated = true
			p.set(&"control_hold", true)
			p.velocity = Vector3.ZERO
			Game.say("SEATED   JUMP TO STAND", 2.0)
		&"climb":
			p.global_position = _prompt_data["world"]
			p.velocity = Vector3.ZERO
			Game.say("ON THE ROOF", 1.5)
	return true


# --- queries for the map, the tests, the missions ---------------------------------------------------------------------------------------

## Minimap markers {pos, color, radius, goal} of the stations.
func markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in RailNet.routes():
		for st: Dictionary in r["stations"]:
			var pa := RailNet.point_at(r, float(st["s"]))
			out.append({"pos": pa[0], "color": Color(0.35, 0.85, 0.95), "radius": 7.0, "goal": false, "label": String(st["name"]), "kind": &"station"})
	return out


func stats() -> Dictionary:
	var built := 0
	var cols := 0
	var active := 0
	for ch in chunks:
		if ch["built"]:
			built += 1
		if ch["colliders"]:
			cols += 1
	for t in trains:
		if t.active:
			active += 1
	return {"chunks": chunks.size(), "built": built, "with_colliders": cols, "tris": tris, "colliders": colliders, "trains": trains.size(), "active": active, "gates": gates.size(), "signals": signals.size(),
		"clock": clock}


func gate_of(route_id: StringName, index := 0) -> Dictionary:
	var k := 0
	for g in gates:
		if g["route"] == route_id:
			if k == index:
				return g
			k += 1
	return {}
