extends RefCounted
## w128-anim probe (not a test: it calls VehicleManager.enter directly): the seat of every aircraft / tank kind, the hands' error, the head under the canopy.
##   KINDS=a,b (default all helis, planes, tanks)
const TIMEOUT_SECONDS := 140


func run(h: Node) -> void:
	Sfx.muted = true
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	h.add_child(main)
	await TestLib.frames(h, 20)
	Game.state = &"play"
	var p := Game.player as Player
	var vm := Game.vehicles as VehicleManager
	var kinds: Array = []
	var env := OS.get_environment("KINDS")
	if env != "":
		kinds = Array(env.split(","))
	else:
		kinds = HeliRoster.DEFS.keys() + PlaneRoster.KINDS + TankRoster.DEFS.keys() + [&"heli", &"gunship", &"hauler", &"tank", &"ltank", &"apc", &"quad", &"scooter", &"jetski", &"bike", &"sedan"]
	var at := p.global_position + Vector3(30.0, 0.0, 30.0)
	for k0 in kinds:
		var k := StringName(k0)
		vm._release_farthest(at)
		vm._release_farthest(at)
		var v := vm.spawn_parked(k, at, 0.0)
		if v == null:
			print("W128 %s no spawn" % k)
			continue
		await TestLib.frames(h, 2)
		vm.enter(v)
		await TestLib.frames(h, 24)
		var b := p.body
		var tn := v.visual.model.get_node_or_null("Turret") as MeshInstance3D
		if tn != null:
			print("TUR %s aabb %s pos %s roof %.2f" % [k, tn.mesh.get_aabb(), tn.position, SeatPose._roof(tn.mesh, tn.mesh.get_aabb())])
		var gl := 0
		for si in v.visual.body.mesh.get_surface_count():
			var mm := v.visual.body.get_active_material(si)
			print("SURF %s %d %s %s" % [k, si, mm.resource_name if mm else "-", mm.transparency if mm is BaseMaterial3D else -1])
		var s: Dictionary = b.seat_info
		if s.is_empty():
			print("W128 %-12s NONE visible=%s" % [k, b.visible])
		else:
			var rig := b.rig
			var mx := rig.model.global_transform
			var e0 := (mx * rig.wrist_position(0)).distance_to(mx * rig.seat_hands[0])
			var e1 := (mx * rig.wrist_position(1)).distance_to(mx * rig.seat_hands[1])
			var node: Node3D = v.visual.model if String(s["node"]) == "" else v.visual.model.get_node(String(s["node"]))
			var head_l := node.global_transform.affine_inverse() * (mx * rig.head_now())
			var hip_l := node.global_transform.affine_inverse() * (mx * rig.hips_now())
			var sl := node.global_transform.affine_inverse() * (mx * rig.sole_now(0))
			print("W128 %-12s %s/%s hip %s head %s top %.2f rec %.2f hand err %.3f %.3f hipErr %.3f footErr %.3f vis %s" % [k, s["style"], s["controls"], hip_l, head_l, float(s["top"]), float(s["recline"]), e0, e1, hip_l.distance_to(s["hip"]), sl.distance_to(s["feet"][0]), b.visible])
		vm.exit_vehicle()
		await TestLib.frames(h, 2)
		vm._release(v)
		await TestLib.frames(h, 2)
	main.queue_free()
	await TestLib.frames(h, 2)
