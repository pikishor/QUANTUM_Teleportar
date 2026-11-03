extends RefCounted
## Real actors for the city events (scripts/world/city_events.gd): built with the existing systems, one small record per event in e["a"].
##   ambush  2 Vael patrol cars (VehicleManager) + 3 enemies (EnemyManager), aware; success when every spawned enemy is down
##   race    3 AI cars on the street (traffic lane AI, fast) + 3 checkpoints in order; success when the player passes all, failure when an AI car finishes first
##   rescue  an InteriorCivilian (hostage) with a marker; success when the player reaches it, then it runs off
##   drop    a glowing crate + 2 enemy guards; success when the player reaches the crate
##   rift    a shimmer disc (shader) on the ground over the low-gravity zone
## Draws: one marker mesh per event (rift disc, crate, checkpoint ring, rescue marker is inside the civilian), actors reuse the pooled enemies / cars.

const Civilian := preload("res://scripts/interiors_gameplay/interior_civilian.gd")
const CP_R := 9.0
const SHIMMER := "shader_type spatial;\nrender_mode unshaded, blend_add, cull_disabled, depth_draw_never;\nuniform vec4 tint : source_color = vec4(0.6, 0.35, 1.0, 1.0);\nvoid fragment() {\n\tvec2 p = UV - vec2(0.5);\n\tfloat r = length(p) * 2.0;\n\tfloat ring = smoothstep(0.08, 0.0, abs(r - fract(TIME * 0.35)));\n\tfloat edge = smoothstep(1.0, 0.8, r) * (0.25 + 0.3 * sin(r * 24.0 - TIME * 4.0 + p.x * 9.0));\n\tALBEDO = tint.rgb * (ring + max(edge, 0.0)) * step(r, 1.0);\n}\n"
static var _shader: Shader


static func _nodes() -> Array:
	return [Game.enemies, Game.vehicles]


## Create the actors of event e under `parent`.
static func build(parent: Node, e: Dictionary) -> void:
	var a := {"enemies": [], "cars": [], "ai": [], "node": null, "civ": null, "cp": 0, "pts": [], "reached": false}
	e["a"] = a
	var pos: Vector3 = e["pos"]
	match e["kind"]:
		&"ambush":
			_cars(a, [&"vael_patrol", &"vael_patrol"], pos, 7.0)
			_enemies(a, [&"striker", &"sentinel", &"striker"], pos, 5.0, true)
		&"race":
			var axis: int = e.get("axis", 0)
			var road: int = e.get("road", 0)
			var dir := 1 if pos.x < 0.0 and axis == 0 or pos.z < 0.0 and axis == 1 else -1
			var base := pos.x if axis == 0 else pos.z
			var pts: Array = []
			for k in 3:
				var along := clampf(base + dir * (30.0 + 45.0 * k), -Game.HALF + 10.0, Game.HALF - 10.0)
				pts.append(Vector3(along, 0.0, CityLayout.road_center(road)) if axis == 0 else Vector3(CityLayout.road_center(road), 0.0, along))
			a["pts"] = pts
			if is_instance_valid(Game.vehicles):
				for k in 3:
					var v: Vehicle = Game.vehicles.call(&"spawn_traffic", &"sport", axis, road, dir, base - dir * k * 6.0 + dir * 4.0)
					if v != null:
						v.ai_cruise = 30.0 + 3.0 * k
						a["ai"].append(v)
			_marker(parent, a, Color(1.0, 0.85, 0.3), 3.0, 14.0)
			a["node"].global_position = pts[0]
		&"rescue":
			var c := Civilian.new()
			parent.add_child(c)
			c.setup(int(e["id"]))
			c.activate(&"hostage", pos, randf() * TAU, Color(0.3, 1.0, 0.9))
			a["civ"] = c
		&"drop":
			_marker(parent, a, Color(1.0, 0.7, 0.2), 0.9, 1.0, true)
			a["node"].global_position = pos + Vector3(0, 0.5, 0)
			_enemies(a, [&"striker", &"striker"], pos, 7.0, true)
		&"rift":
			_marker(parent, a, Color(0.6, 0.35, 1.0), float(e.get("radius", 22.0)), 0.05, false, true)
			a["node"].global_position = pos + Vector3(0, 0.15, 0)


## Advance one event. Returns 1 success, 0 failure, -1 still running.
static func step(e: Dictionary, dt: float, player_pos: Vector3) -> int:
	var a: Dictionary = e.get("a", {})
	if a.is_empty():
		return -1
	var node: Node3D = a["node"]
	match e["kind"]:
		&"ambush":
			var total: int = a["enemies"].size()
			if total == 0:
				return -1
			for d: Object in a["enemies"]:
				if is_instance_valid(d) and bool(d.get("active")) and not bool(d.get("dead")):
					return -1
			return 1
		&"race":
			var pts: Array = a["pts"]
			var i: int = a["cp"]
			if i < pts.size() and player_pos != Vector3.INF and Vector2(player_pos.x - pts[i].x, player_pos.z - pts[i].z).length() <= CP_R:
				a["cp"] = i + 1
				i += 1
				if i < pts.size() and node != null:
					node.global_position = pts[i]
			if i >= pts.size():
				return 1
			var last: Vector3 = pts[pts.size() - 1]
			for v: Object in a["ai"]:
				if is_instance_valid(v) and bool(v.get("active")) and Vector2(v.global_position.x - last.x, v.global_position.z - last.z).length() <= CP_R:
					return 0
		&"rescue":
			var civ: Object = a["civ"]
			if is_instance_valid(civ) and player_pos != Vector3.INF and Vector2(player_pos.x - civ.global_position.x, player_pos.z - civ.global_position.z).length() <= 4.0:
				return 1
			if is_instance_valid(civ):
				civ.tick(dt)
		&"drop":
			if node != null:
				node.rotation.y += dt * 1.2
	return -1


## Tidy up when the event ends: success frees the escortee, visuals go, pooled actors stay (they are ordinary enemies / cars now).
static func finish(e: Dictionary, success: bool) -> void:
	var a: Dictionary = e.get("a", {})
	if a.is_empty():
		return
	if is_instance_valid(a["node"]):
		(a["node"] as Node).queue_free()
	var civ: Object = a["civ"]
	if is_instance_valid(civ):
		if success:
			civ.call(&"free_up", civ.global_position + Vector3(24.0, 0.0, 0.0))
			civ.get_tree().create_timer(6.0).timeout.connect(func() -> void:
				if is_instance_valid(civ):
					(civ as Node).queue_free())
		else:
			(civ as Node).queue_free()
	for v: Object in a["ai"]:
		if is_instance_valid(v) and not success:
			v.set("ai_cruise", 12.0)          # the race is over: they go back to ordinary traffic speed
	e.erase("a")


static func _enemies(a: Dictionary, types: Array, pos: Vector3, r: float, aware: bool) -> void:
	if not is_instance_valid(Game.enemies):
		return
	for k in types.size():
		var ang := TAU * float(k) / types.size()
		var d: Object = Game.enemies.call(&"spawn", types[k], pos + Vector3(cos(ang), 0.0, sin(ang)) * r, aware)
		if d != null:
			a["enemies"].append(d)


static func _cars(a: Dictionary, kinds: Array, pos: Vector3, r: float) -> void:
	if not is_instance_valid(Game.vehicles):
		return
	for k in kinds.size():
		var off := Vector3(r * (1.0 if k == 0 else -1.0), 0.0, 0.0)
		var v: Vehicle = Game.vehicles.call(&"spawn_parked", kinds[k], pos + off, randf() * TAU)
		if v != null:
			v.patrol = true
			a["cars"].append(v)


static func _marker(parent: Node, a: Dictionary, col: Color, r: float, h: float, crate := false, shimmer := false) -> void:
	var m := MeshInstance3D.new()
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if shimmer:
		var q := QuadMesh.new()
		q.size = Vector2(r * 2.0, r * 2.0)
		q.orientation = PlaneMesh.FACE_Y
		m.mesh = q
		if _shader == null:
			_shader = Shader.new()
			_shader.code = SHIMMER
		var sm := ShaderMaterial.new()
		sm.shader = _shader
		sm.set_shader_parameter(&"tint", col)
		m.material_override = sm
	else:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(col, 0.55)
		mat.emission_enabled = true
		mat.emission = col
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if crate:
			var b := BoxMesh.new()
			b.size = Vector3(r, r, r)
			m.mesh = b
		else:
			var c := CylinderMesh.new()
			c.top_radius = r
			c.bottom_radius = r
			c.height = h
			m.mesh = c
		m.material_override = mat
	parent.add_child(m)
	a["node"] = m
