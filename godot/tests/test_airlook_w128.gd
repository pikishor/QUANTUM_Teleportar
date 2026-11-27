extends RefCounted
## WAVE 128 AIRCRAFT LOOK (w128-airlook): the helicopters and aeroplanes look like real aircraft of their class.
## MODELS (every procedural helicopter and aeroplane kind, built as the game builds them):
##   - drawn right side out: Godot's front faces are CLOCKWISE; the craft models were wound the other way, so the near skin was culled and the inner far wall drawn (flat, see-through
##     canopies, a fin seen through the body: "fins in the middle of helicopters")
##   - helicopters: framed windscreen (no glass shell under the nose), the tail rotor BEHIND the mast and outside the main rotor disc, on the side of the fin, nothing of the body in
##     the main rotor's sweep, the gear on the ground, a far body (LOD1) lighter than the near one
##   - aeroplanes: the fin behind the wing, the glass on top (no shell under the nose), propeller hubs ahead of their engine, the gear on the ground, LOD1 lighter
## THE FIELD (the real main scene; the hero placed by code: no control is checked here):
##   - every parked aircraft of the HELI LINE, the PLANE LINE and the hangars stands on the ground (not under the field, not floating)
##   - the hangars are lit inside while the hero is near
##   - the air traffic flies the new helicopter kinds from the pads too, and six crossers
## W128_OLD=1 is the old code: every check marked [old fails] fails.
## Run: tools/test.sh tests/test_airlook_w128.gd
const TIMEOUT_SECONDS := 300

var host: Node


func _f(n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame
		await host.get_tree().process_frame


## Every triangle of the mesh: [a, b, c, normal of a].
static func _tris(m: Mesh) -> Array:
	var out: Array = []
	if m == null:
		return out
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var name := String(m.surface_get_material(s).resource_name) if m.surface_get_material(s) != null else ""
		for t in range(0, v.size() - 2, 3):
			out.append([v[t], v[t + 1], v[t + 2], nn[t], name])
	return out


## Share of the triangles whose CLOCKWISE (Godot front) face looks the way their normal points.
static func front_share(m: Mesh) -> float:
	var tr := _tris(m)
	if tr.is_empty():
		return 0.0
	var ok := 0
	for t: Array in tr:
		var a: Vector3 = t[0]
		var g := ((t[2] as Vector3) - a).cross((t[1] as Vector3) - a)
		if g.dot(t[3] as Vector3) > 0.0:
			ok += 1
	return float(ok) / float(tr.size())


static func _min_y(root: Node3D) -> float:
	var y := 1.0e9
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		if g.name == "Body_LOD1" or g.name == "Glow" or g.mesh == null:
			continue
		for t: Array in _tris(g.mesh):
			for i in 3:
				y = minf(y, (t[i] as Vector3).y + g.position.y)
	return y


static func _tri_n(root: Node3D, nm: String) -> int:
	var g := root.get_node_or_null(nm) as MeshInstance3D
	return _tris(g.mesh).size() if g != null else 0


## Glass under the nose: triangles of the Glass surface that face straight down below the fuselage's centre line `yc` (a glass ring round the belly; the hidden bottom of a
## canopy box above the centre line does not count).
static func _glass_down(m: Mesh, yc: float) -> int:
	var n := 0
	for t: Array in _tris(m):
		var cy := ((t[0] as Vector3).y + (t[1] as Vector3).y + (t[2] as Vector3).y) / 3.0
		if t[4] == "Glass" and (t[3] as Vector3).y < -0.9 and cy < yc:
			n += 1
	return n


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	_helis()
	_planes()
	await _field()


func _helis() -> void:
	var bad: Array[String] = []
	for k: StringName in HeliRoster.NEW:
		var sp: Dictionary = VehicleSpecs.SPECS[k]
		var m := VehicleCraftModels.build(String(sp["procedural"]), sp)
		var body := m.get_node("Body") as MeshInstance3D
		var rot := m.get_node("Rotor") as Node3D
		var rr := float(sp["rotor_r"])
		var why: Array[String] = []
		var fs := front_share(body.mesh)
		if fs < 0.97:
			why.append("front faces %.0f%%" % (fs * 100.0))
		var P: Dictionary = HeliModels.params(k)
		var gd := _glass_down(body.mesh, float(P["cab"][4]))
		if gd > 0:
			why.append("%d glass faces under the nose" % gd)
		var tail := m.get_node_or_null("TailRotor") as Node3D
		if String(P.get("tail", "rotor")) == "rotor" and not (P.get("x", []) as Array).has("ring"):
			if tail == null:
				why.append("no tail rotor")
			else:
				var d := Vector2(tail.position.x - rot.position.x, tail.position.z - rot.position.z).length()
				var tr := float(HeliModels._cache[k]["parts"].filter(func(p: Dictionary) -> bool: return p["name"] == "TailRotor").size())
				if tail.position.z <= rot.position.z + rr * 0.8:
					why.append("tail rotor not behind the mast (z %.1f vs mast %.1f, disc %.1f)" % [tail.position.z, rot.position.z, rr])
				if d < rr + 0.2 or tr == 0.0:
					why.append("tail rotor inside the main disc (%.1f < %.1f)" % [d, rr])
				if absf(tail.position.x) < 0.15:
					why.append("tail rotor in the fin plane")
		# nothing of the body (fin, cowling, mast fairing) reaches into the main rotor's sweep: within the disc, the body stays 0.15 m under the hub
		var hubs: Array[Vector3] = [rot.position]
		if m.get_node_or_null("Rotor2") != null:
			hubs.append((m.get_node("Rotor2") as Node3D).position)
		var hit := 0
		for t: Array in _tris(body.mesh):
			for i in 3:
				var v: Vector3 = t[i]
				for hb: Vector3 in hubs:
					var dh := Vector2(v.x - hb.x, v.z - hb.z).length()
					if dh > 0.6 and dh < rr and v.y > hb.y - 0.15:
						hit += 1
		if hit > 0:
			why.append("%d body points in the rotor sweep" % hit)
		var gy := _min_y(m)
		if absf(gy) > 0.1:
			why.append("gear bottom at %.2f m" % gy)
		var n0 := _tri_n(m, "Body")
		var n1 := _tri_n(m, "Body_LOD1")
		if n1 <= 0 or float(n1) > float(n0) * 0.75:
			why.append("LOD1 %d tris vs %d" % [n1, n0])
		if not why.is_empty():
			bad.append("%s: %s" % [k, ", ".join(why)])
		TestLib.check(why.is_empty(), "[old fails] %s %s: right side out, framed windscreen, tail rotor behind the mast and clear of the disc, rotor sweep clear, gear on the ground, LOD1 (%d / %d tris) %s" % [k, VehicleSpecs.name_of(k), n0, n1, ", ".join(why)])
		m.free()
	print("HELI LOOK faults: ", bad)


func _planes() -> void:
	for k: StringName in PlaneRoster.NEW:
		var sp: Dictionary = VehicleSpecs.SPECS[k]
		var m := VehicleCraftModels.build(String(sp["procedural"]), sp)
		var body := m.get_node("Body") as MeshInstance3D
		var P := PlaneModels.params(k)
		var why: Array[String] = []
		var fs := front_share(body.mesh)
		if fs < 0.97:
			why.append("front faces %.0f%%" % (fs * 100.0))
		var gd := _glass_down(body.mesh, float(P["f"][4]))
		if gd > 0:
			why.append("%d glass faces under the nose" % gd)
		var w: Array = P["w"]
		var f: Array = P["f"]
		var tail := String(P.get("t", "conv"))
		if tail != "none":
			var tp: Array = P.get("tp", [0.0, 1.0, 0.0, 1.0])
			var fin_mid := float(f[1]) - float(tp[1]) * 0.5
			var wing_mid := float(w[0]) + float(w[4]) * 0.5 + (float(w[2]) + float(w[3])) * 0.25
			if fin_mid <= wing_mid:
				why.append("fin (z %.1f) not behind the wing (z %.1f)" % [fin_mid, wing_mid])
		for pn: String in PlaneModels.PROP_NAMES:
			var pr := m.get_node_or_null(pn) as Node3D
			if pr != null and String((P.get("e", {}) as Dictionary).get("type", "")) == "nose" and pr.position.z > float(f[0]) + 0.05:
				why.append("%s hub behind the nose" % pn)
		var gy := _min_y(m)
		if absf(gy) > 0.1:
			why.append("gear bottom at %.2f m" % gy)
		var n0 := _tri_n(m, "Body")
		var n1 := _tri_n(m, "Body_LOD1")
		if n1 <= 0 or float(n1) > float(n0) * 0.85:
			why.append("LOD1 %d tris vs %d" % [n1, n0])
		TestLib.check(why.is_empty(), "[old fails] %s %s: right side out, glass on top, fin behind the wing, props ahead, gear on the ground, LOD1 (%d / %d tris) %s" % [k, VehicleSpecs.name_of(k), n0, n1, ", ".join(why)])
		m.free()


func _field() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await _f(20)
	Game.state = &"play"
	Game.force_touch = true
	CrateReveal._quiet = 0
	var p := Game.player as Player
	var vm := Game.vehicles as VehicleManager
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	TestMode.god = true
	# --- the parked aircraft stand on the ground: walk the lines (placed by code) and measure every fixed aircraft that appears against a ray down to the field
	var seen := {}
	var faults: Array[String] = []
	var space := p.get_world_3d().direct_space_state
	for at: Vector3 in [Vector3(1320.0, 0.0, -900.0), Vector3(1320.0, 0.0, -760.0), Vector3(1320.0, 0.0, -620.0), Vector3(1320.0, 0.0, -480.0), Vector3(1320.0, 0.0, -340.0),
			Vector3(1320.0, 0.0, -230.0), Vector3(1170.0, 0.0, -910.0), Vector3(1360.0, 0.0, -680.0)]:
		var w := Airport.to_world(at)
		p.teleport_to(w + Vector3(0.0, 0.5, 0.0))
		vm._spawn_t = 0.0
		await _f(420)
		for v: Vehicle in vm.list:
			if not (HeliRoster.NEW.has(v.kind) or PlaneRoster.NEW.has(v.kind)) or seen.has(v.get_instance_id()) or v == vm.driven:
				continue
			if v.global_position.distance_to(w) > 140.0:
				continue
			seen[v.get_instance_id()] = true
			var gp := v.global_position
			var q := PhysicsRayQueryParameters3D.create(gp + Vector3(0.0, 6.0, 0.0), gp - Vector3(0.0, 30.0, 0.0), Game.L_WORLD)
			q.exclude = [v.get_rid()]
			var hit := space.intersect_ray(q)
			var gy := float(hit["position"].y) if not hit.is_empty() else -999.0
			if absf(gp.y - gy) > 0.35:
				faults.append("%s at %.1f, ground %.1f" % [v.kind, gp.y, gy])
	TestLib.check(seen.size() >= 30 and faults.is_empty(), "%d parked aircraft of the lines and hangars stand on the field (%s)" % [seen.size(), ", ".join(faults)])
	# --- the hangars are lit inside while the hero is near
	p.teleport_to(Airport.to_world(Vector3(1140.0, 0.0, -940.0)) + Vector3(0.0, 0.5, 0.0))
	await _f(20)
	var lit := 0
	var dn := Hangars.Doors.instance
	if dn != null:
		for e: Array in dn._lamps:
			if (e[0] as OmniLight3D).visible:
				lit += 1
	TestLib.check(lit >= 2, "[old fails] HANGAR A is lit inside while the hero stands in it (%d lamps on)" % lit)
	# --- the air traffic flies the new helicopter kinds (pads and crossers) and six crossers
	var traf := AirportWorld.instance.traffic if AirportWorld.instance != null else null
	var heli_kinds := {}
	var crossers := 0
	var pad_new := 0
	if traf != null:
		for fl in traf.flights:
			if fl.cross:
				crossers += 1
			if fl.heli:
				for kk: StringName in fl.kinds:
					heli_kinds[kk] = true
				heli_kinds[fl.kind] = true
				if not fl.cross:
					for kk: StringName in fl.kinds:
						if HeliRoster.NEW.has(kk):
							pad_new += 1
	var news := 0
	for kk: StringName in HeliRoster.NEW:
		if heli_kinds.has(kk):
			news += 1
	TestLib.check(crossers >= 6 and pad_new >= 12 and news >= 20, "[old fails] the air traffic: %d crossers, the pad helicopters take %d new kinds in turn, %d of the 20 new kinds fly" % [crossers, pad_new, news])
	# --- a cargo crate falls under a parachute: the canopy opens over it, upright, once the chute is out
	var shooter: Vehicle = null
	for v: Vehicle in vm.list:
		shooter = v
		break
	var chute_ok := false
	var note := "no vehicle to drop from"
	if shooter != null:
		var top := p.global_position + Vector3(0.0, 150.0, 0.0)
		var ok := AirRockets.launch(shooter, {"look": &"crate", "speed": 4.0, "life": 40.0, "grav": 9.8, "chute": 5.0, "inherit": 0.0}, top, Vector3(0.0, -1.0, 0.2))
		await _f(90)
		note = "launched %s" % ok
		var ar := AirRockets.instance
		if ar != null:
			for r: Dictionary in ar._live:
				var mi := r["mi"] as MeshInstance3D
				var ch := mi.get_node_or_null(^"Chute") as Node3D
				note = "crate at %.0f m, chute %s" % [mi.global_position.y - p.global_position.y, "none" if ch == null else ("open %.1f m over it" % (ch.global_position.y - mi.global_position.y) if ch.is_visible_in_tree() else "shut")]
				if ch != null and ch.is_visible_in_tree() and ch.global_position.y >= mi.global_position.y - 0.01 and ch.global_basis.y.dot(Vector3.UP) > 0.99:
					chute_ok = true
	TestLib.check(chute_ok, "[old fails] a cargo crate falls under an open parachute (%s)" % note)
	Game.state = &"menu"
	Game.force_touch = false
	CrateReveal._quiet = -1
	TestMode.god = false
	main.queue_free()
	await _f(2)
