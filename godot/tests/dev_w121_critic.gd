extends RefCounted
## w121-critic probe: 5 different walk-in towers, real fingers only (setup teleports to the sidewalk only). Prints findings, no checks.
##   tools/test.sh tests/dev_w121_critic.gd
const TIMEOUT_SECONDS := 600
const Lib := preload("res://tests/w120_reach_lib.gd")

var L: Lib
var tw: Dictionary


func run(h: Node) -> void:
	L = Lib.new()
	await L.start(h)
	L.fast(true)
	var tf := TowerFloors.instance
	tf.nearest(Game.SPAWN)
	var picked: Array = []
	var kinds := {}
	var all := tf.towers.duplicate()
	all.sort_custom(func(a, b): return TowerFloors.door_pos(a).distance_to(Game.SPAWN) < TowerFloors.door_pos(b).distance_to(Game.SPAWN))
	for t in all:
		if picked.size() >= 5:
			break
		var k: StringName = t["kind"]
		if int(kinds.get(k, 0)) < 2:
			kinds[k] = int(kinds.get(k, 0)) + 1
			picked.append(t)
	for t in picked:
		if OS.get_environment("ONLY") != "" and str((t["lot"] as CityLayout.Lot).index) != OS.get_environment("ONLY"):
			continue
		tw = t
		await _tower()
	await L.finish()


func _say(s: String) -> void:
	var lot: CityLayout.Lot = tw["lot"]
	print("CRIT lot%d %s: %s" % [lot.index, tw["kind"], s])


func _cam() -> String:
	var cam := L.p.get_viewport().get_camera_3d()
	var c := cam.global_position
	var head := L.p.global_position + Vector3(0, 1.5, 0)
	var q := PhysicsRayQueryParameters3D.create(head, c, Game.L_WORLD)
	var hit := L.p.get_world_3d().direct_space_state.intersect_ray(q)
	var ins := TowerFloors.inside(c)
	return "cam %s d%.1f in=%s blocked=%s" % [c.snapped(Vector3(0.1, 0.1, 0.1)), c.distance_to(head), ins, not hit.is_empty()]


func _step(q: Vector3, limit: float) -> bool:
	var t := 0.0
	var pushing := false
	var still := 0.0
	var last := L.p.global_position
	while t < limit:
		var gp := L.p.global_position
		if Lib.flat(gp, q) < 0.45:
			L.fg.stick(Vector2.ZERO)
			return true
		var err := wrapf(Lib.yaw_to(gp, q) - L.p.camera_rig.yaw, -PI, PI)
		if absf(err) > 0.42 or (not pushing and absf(err) > 0.15):
			if pushing:
				L.fg.stick(Vector2.ZERO)
				pushing = false
			L.fg.look(-err * 160.0, 0.0, 4)
			await L.f(3)
			t += 0.1
			continue
		if not pushing:
			L.fg.stick(Vector2(0.0, -0.6))
			pushing = true
		await L.secs(0.1)
		t += 0.1
		var mv := Lib.flat(L.p.global_position, last)
		last = L.p.global_position
		still = still + 0.1 if mv < 0.03 else 0.0
		if still > 1.5:
			break
	L.fg.stick(Vector2.ZERO)
	return false


func _follow(pts: Array, what: String) -> bool:
	var cams := 0
	for i in pts.size():
		if not await _step(pts[i], 9.0):
			var col := L.p.get_last_slide_collision()
			if col and col.get_collider_shape() is Node:
				_say("  blocker %s at %s" % [(col.get_collider_shape() as Node).get_path(), (col.get_collider_shape() as Node3D).global_position])
			_say("%s STUCK at point %d %s hero %s (%s)" % [what, i, pts[i], L.p.global_position, (col.get_collider_shape() as Node).name if col and col.get_collider_shape() is Node else "-"])
			return false
		var c := _cam()
		if c.contains("in=false") or c.contains("blocked=true"):
			cams += 1
			if cams < 4:
				_say("%s cam issue at %d: %s" % [what, i, c])
	return true


func _tower() -> void:
	var tf := TowerFloors.instance
	var door := TowerFloors.door_pos(tw, 4.0)
	await L.tp(door, Lib.yaw_to(door, TowerFloors.door_pos(tw, -3.0)))
	await L.secs(0.8)
	if tf._cur != tw:
		_say("not open at door (open %d)" % TowerFloors.open_lot)
		return
	var lot: CityLayout.Lot = tw["lot"]
	_say("%.0fx%.0fx%.0f levels %s style %d" % [lot.w, lot.d, lot.h, tf._levels, tw["b"].style])
	var r0 := tf.route(0)
	if not await _follow([r0[0]], "in"):
		return
	_say("in: %s" % _cam())
	# stairs to floor 2
	var r2 := tf.route(2)
	if not await _follow(r2.slice(1), "up2"):
		return
	_say("floor2 y %.2f floor_of %d" % [L.p.global_position.y, tf.floor_of(L.p.global_position.y)])
	# walk into the floor
	var iu := TowerFloors.inner_u(tw)
	var iv := TowerFloors.inner_v(tw)
	var lv := tf._levels
	for target in [TowerFloors.at(tw, iu * 0.5, iv * 0.5, lv[2]), TowerFloors.at(tw, iu - 2.0, iv - 2.0, lv[2]), TowerFloors.at(tw, 2.0, iv - 2.0, lv[2])]:
		var w := await L.walk(target, 8.0, 0.8, 0.7)
		var qq := PhysicsRayQueryParameters3D.create(L.p.global_position + Vector3(0, 0.3, 0), L.p.global_position - Vector3(0, 2, 0), Game.L_WORLD)
		var hh := L.p.get_world_3d().direct_space_state.intersect_ray(qq)
		if not hh.is_empty():
			var sh = (hh["collider"] as CollisionObject3D).shape_owner_get_owner((hh["collider"] as CollisionObject3D).shape_find_owner(hh["shape"]))
			_say("  stands on %s / %s at %s y %.2f" % [(hh["collider"] as Node).get_path(), sh.name if sh else "-", (sh as Node3D).global_position if sh else Vector3.ZERO, hh["position"].y])
		_say("  floor %s vel %s trav %s last %s" % [L.p.is_on_floor(), L.p.velocity, L.p.traversal.kind if &"traversal" in L.p else -1, L.p.traversal.last_kind if &"traversal" in L.p else -1])
		if not L.p.is_on_floor():
			var sq := PhysicsShapeQueryParameters3D.new()
			var cap := CapsuleShape3D.new()
			cap.radius = 0.36
			cap.height = 1.75
			sq.shape = cap
			sq.collision_mask = Game.L_WORLD
			sq.transform = Transform3D(Basis(), L.p.global_position + Vector3(0, 0.85, 0))
			for rr in L.p.get_world_3d().direct_space_state.intersect_shape(sq, 16):
				var co := rr["collider"] as CollisionObject3D
				var ow := co.shape_owner_get_owner(co.shape_find_owner(rr["shape"])) as CollisionShape3D
				_say("  touching %s %s size %s" % [co.name, ow.global_position, (ow.shape as BoxShape3D).size if ow.shape is BoxShape3D else Vector3.ZERO])
			for zz in 4:
				await L.secs(0.5)
				_say("  wait y %.2f floor %s ceil %s wall %s vel %s verbs %s snake %s" % [L.p.global_position.y, L.p.is_on_floor(), L.p.is_on_ceiling(), L.p.is_on_wall(), L.p.velocity, L.p.verbs.active(), L.p.snake.active() if L.p.snake.has_method("active") else "?"])
			var lt := L.p.traversal
			_say("  trav from %s to %s" % [lt._from, lt._to])
		for ci in L.p.get_slide_collision_count():
			var cc := L.p.get_slide_collision(ci)
			_say("  slide %s %s n %s at %s" % [(cc.get_collider() as Node).name if cc.get_collider() is Node else "?", (cc.get_collider_shape() as Node3D).global_position if cc.get_collider_shape() is Node3D else Vector3.ZERO, cc.get_normal(), cc.get_position()])
		_say("floor2 walk to %s reached=%s dist %.1f y %.2f %s" % [target.snapped(Vector3.ONE * 0.1), w["reached"], w["dist"], L.p.global_position.y, _cam()])
	# fight on floor 2 (setup: back to the floor-2 landing)
	await L.tp(TowerFloors.at(tw, TowerFloors.LAND * 0.5, TowerFloors.SHAFT_W + 1.2, lv[2]), 0.0)
	var mgr := Game.enemies as EnemyManager
	var ep := TowerFloors.at(tw, TowerFloors.SHAFT_L + 4.0, TowerFloors.SHAFT_W + 3.0, lv[2] + 0.1)
	var e := mgr.spawn(&"operative", ep, true)
	await L.secs(1.5)
	if e != null and is_instance_valid(e):
		_say("enemy spawned at y %.2f now %s" % [lv[2], e.global_position.snapped(Vector3.ONE * 0.1)])
	mgr.clear()
	await L.tp(TowerFloors.at(tw, TowerFloors.LAND * 0.5, TowerFloors.SHAFT_W + 1.2, lv[2]), 0.0)
	# lift to top floor
	var tl := TowerLift.instance
	if tl == null or tl.mode != &"in" or tl.lot_idx != lot.index:
		_say("NO inside lift (mode %s lot %d)" % [tl.mode if tl else &"-", tl.lot_idx if tl else -1])
	else:
		_say("lift stops %s base %s" % [tl.stops, tl.base.origin])
		var cp := tl.call_point(2)
		_say("  walk to cp %s from %s" % [cp, L.p.global_position])
		var mon := func():
			var yy := L.p.global_position.y
			for zz in 60:
				await L.secs(0.1)
				if absf(L.p.global_position.y - yy) > 0.05:
					yy = L.p.global_position.y
					_say("    t%d y %.2f pos %s trav %d/%d verbs %s wallrun %s floor %s" % [zz, yy, L.p.global_position.snapped(Vector3.ONE*0.01), L.p.traversal.kind, L.p.traversal.last_kind, L.p.verbs.active(), L.p.wall_running, L.p.is_on_floor()])
		await _follow([TowerFloors.at(tw, TowerFloors.LAND * 0.5, TowerFloors.SHAFT_W + 1.6, lv[2]), TowerFloors.at(tw, TowerFloors.SHAFT_L, TowerFloors.SHAFT_W + 1.6, lv[2])], "tolift")
		mon.call()
		var w := await L.walk(cp, 10.0, 0.5, 0.5)
		_say("lift call on floor2: label %s dist %.1f" % [L.fg.button_label(&"interact"), w["dist"]])
		_say("  before press: at_stop %d state %s cab_y %.2f hero y %.2f call_stop %d" % [tl.at_stop, tl.state, tl.cab_y, L.p.global_position.y, tl.call_stop(L.p.global_position)])
		await L.press(&"interact", 4)
		for zz in 6:
			await L.secs(0.5)
			_say("  after press: at_stop %d target %d state %s cab_y %.2f" % [tl.at_stop, tl.target, tl.state, tl.cab_y])
		var cab := tl.base.origin + Vector3(0.0, tl.stops[2], 0.0)
		await L.walk(cab, 5.0, 0.3, 0.45)
		_say("in cabin %s door_k %.2f at_stop %d" % [tl.in_cabin(L.p.global_position), tl.door_k, tl.at_stop])
		await L.press(&"interact", 4)
		await L.secs(0.4)
		var top := tl.stops.size() - 1
		var b: Button = null
		for x in tl.panel_buttons():
			if x.name == "Floor_%d" % top or (x.name.begins_with("Floor_R")):
				b = x
		if b == null:
			_say("panel buttons: %s" % [tl.panel_buttons().map(func(x): return x.name)])
			for x in tl.panel_buttons():
				if x.name != "LiftClose":
					b = x
		if b != null:
			L.fg.down(7, b.get_global_rect().get_center())
			await L.f(3)
			L.fg.up(7)
			await L.secs(4.0)
			_say("rode via %s: at_stop %d y %.2f stop y %.2f %s" % [b.name, tl.at_stop, L.p.global_position.y, tl.stops[tl.at_stop], _cam()])
			# walk out
			var out := tl.call_point(tl.at_stop) + (tl.base.basis * Vector3.BACK) * 1.0
			var w2 := await L.walk(out, 5.0, 0.6, 0.5)
			_say("out of lift at stop %d reached %s y %.2f" % [tl.at_stop, w2["reached"], L.p.global_position.y])
			await L.secs(1.0)
			_say("1s later y %.2f" % L.p.global_position.y)
	if L.p.global_position.y < lv[lv.size() - 2] - 1.0:
		await L.tp(TowerFloors.at(tw, TowerFloors.LAND * 0.5, TowerFloors.SHAFT_W + 1.2, lv[lv.size() - 2]), 0.0)
	# roof by stairs from wherever he is: teleport-free, walk to landing of current floor
	var k := tf.floor_of(L.p.global_position.y)
	var topk := lv.size() - 1
	if k < topk:
		var rr := tf.route(topk)
		var pts: Array = [rr[rr.size() - 1] - Vector3(0, rr[rr.size() - 1].y - lv[k], 0)]
		pts.append_array(rr.slice(2 + 5 * k))
		if await _follow(pts, "roof"):
			var outp := TowerFloors.at(tw, TowerFloors.LAND * 0.5 + 3.0, TowerFloors.SHAFT_W + 4.0, lv[topk])
			var w3 := await L.walk(outp, 6.0, 0.6, 0.8)
			_say("roof: reached %s y %.2f h %.1f %s" % [w3["reached"], L.p.global_position.y, lot.h, _cam()])
			# roof edges
			for tgt in [TowerFloors.at(tw, iu - 1.0, iv - 1.0, lot.h), TowerFloors.at(tw, iu - 1.0, 1.0, lot.h), TowerFloors.at(tw, 9.0, 1.2, lot.h)]:
				var w4 := await L.walk(tgt, 8.0, 0.8, 0.7)
				_say("roof walk reached %s y %.2f" % [w4["reached"], L.p.global_position.y])
	# back down by the lift to ground
	if tl != null and tl.mode == &"in":
		var ks := tf.floor_of(L.p.global_position.y) if L.p.global_position.y < lot.h - 1.0 else tl.stops.size() - 1
		var w5 := await L.walk(tl.call_point(ks), 12.0, 0.8, 0.5)
		_say("lift call at stop %d: label %s dist %.1f y %.2f" % [ks, L.fg.button_label(&"interact"), w5["dist"], L.p.global_position.y])
		await L.press(&"interact", 4)
		await L.secs(3.5)
		await L.walk(tl.base.origin + Vector3(0.0, tl.stops[ks], 0.0), 5.0, 0.3, 0.45)
		await L.press(&"interact", 4)
		await L.secs(0.4)
		for x in tl.panel_buttons():
			if x.name == "Floor_G":
				L.fg.down(7, x.get_global_rect().get_center())
				await L.f(3)
				L.fg.up(7)
		await L.secs(4.0)
		_say("down: at_stop %d y %.2f" % [tl.at_stop, L.p.global_position.y])
		await L.walk(tl.call_point(0) + (tl.base.basis * Vector3.BACK) * 1.0, 5.0, 0.6, 0.5)
	var w6 := await L.walk(TowerFloors.door_pos(tw, 3.0), 15.0, 0.8, 0.8)
	_say("leave: reached %s pos %s inside %s" % [w6["reached"], L.p.global_position.snapped(Vector3.ONE * 0.1), TowerFloors.inside(L.p.global_position)])
