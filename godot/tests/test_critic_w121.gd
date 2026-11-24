extends RefCounted
## w121-critic: the independent review of wave 121 (walk-in towers, lifts). The real main scene, the phone HUD, REAL FINGERS (tests/w116_fingers.gd), the phone-only layers on
## (CrateReveal._quiet = 0 in tests/w120_reach_lib.gd). Start points are set up by teleport; every move is a finger.
##   fight   an enemy on floor 2 of an open tower stands on floor 2 (not on the street under it) and a finger on FIRE hits it              [old fails: it drops to y 0]
##   doors   no street prop stands in front of any walk-in door; the stick walks in at lot 77 (a planter stood in front of it)                    [old fails]
##   cam     climbing the stairwell by the stick, a lens close to his head never shows an opaque hero mesh (head, hands, gun) filling the screen    [old fails]
##   buttons on a tower floor ZIP / SWING / FLY are not on screen (they did nothing there); on the roof and the street ZIP is back                [old fails]
##   ceiling stick into a room wall on floor 2 + JUMP: the wall run stops at the ceiling, he is back on the floor within 1.5 s               [old fails: hangs under it]
##   walls   an enemy outside chasing the hero in the lobby does not walk through the tower's outer wall                                  [old fails: walks through]
## W121_CRITIC_OLD=1 = the builders' code (TowerFloors.critic_on false). Run: tools/test.sh tests/test_critic_w121.gd
const TIMEOUT_SECONDS := 150
const Lib := preload("res://tests/w120_reach_lib.gd")

var L: Lib
var tw: Dictionary


func run(h: Node) -> void:
	TowerFloors.critic_on = OS.get_environment("W121_CRITIC_OLD") != "1"
	PlayerBody.fade_all_on = TowerFloors.critic_on
	HeroVerbs.ceiling_stop = TowerFloors.critic_on
	L = Lib.new()
	await L.start(h)
	L.fast(true)
	var tf := TowerFloors.instance
	tf.nearest(Game.SPAWN)
	for t in tf.towers:
		if (t["lot"] as CityLayout.Lot).index == 44:
			tw = t
	if tw.is_empty():
		tw = tf.nearest(Game.SPAWN)
	await _doors()
	await _enter()
	await _fight()
	await _walls()
	await _stair_cam()
	await _dead_buttons()
	await _ceiling()
	TowerFloors.critic_on = true
	PlayerBody.fade_all_on = true
	HeroVerbs.ceiling_stop = true
	await L.finish()


func _doors() -> void:
	var tf := TowerFloors.instance
	var pc = Game.world.prop_colliders()
	var blocked: Array = []
	for t in tf.towers:
		var hit := false
		for out in [0.6, 1.6, 2.6]:
			var q := TowerFloors.at(t, TowerFloors.door_u(t), TowerFloors.inner_v(t) + TowerFloors.IN + out)
			for x: Transform3D in pc._xf:
				if absf(x.origin.y) < 1.5 and Vector2(x.origin.x - q.x, x.origin.z - q.z).length() < 1.2:
					hit = true
		if hit:
			blocked.append((t["lot"] as CityLayout.Lot).index)
	TestLib.check(blocked.is_empty(), "no street prop stands in front of a walk-in door (%d towers, blocked: %s) [old fails: lot 77]" % [tf.towers.size(), blocked])
	var t77: Dictionary = {}
	for t in tf.towers:
		if (t["lot"] as CityLayout.Lot).index == 77:
			t77 = t
	if t77.is_empty():
		return
	var door := TowerFloors.door_pos(t77, 4.0)
	var inside := TowerFloors.door_pos(t77, -2.5)
	await L.tp(door, Lib.yaw_to(door, inside))
	await L.secs(0.6)
	var r := await L.walk(inside, 8.0, 0.8, 0.6)
	TestLib.check(r["reached"] and TowerFloors.inside(L.p.global_position), "the stick walks in through the street door of lot 77 (%.1f m short, %s) [old fails: a planter]" % [r["dist"], r["block"]])


func _enter() -> void:
	var door := TowerFloors.door_pos(tw, 4.0)
	var inside := TowerFloors.door_pos(tw, -2.5)
	await L.tp(door, Lib.yaw_to(door, inside))
	await L.secs(0.6)
	var r := await L.walk(inside, 8.0, 0.8, 0.6)
	TestLib.check(r["reached"] and TowerFloors.inside(L.p.global_position), "the stick walks the hero in through the street door (lot %d)" % (tw["lot"] as CityLayout.Lot).index)


## Turn the view to `q` with the right thumb (short swipes).
func _face(q: Vector3) -> void:
	for i in 12:
		var err := wrapf(Lib.yaw_to(L.p.camera_rig.camera.global_position, q) - L.p.camera_rig.yaw, -PI, PI)      # from the camera: the view sits over the shoulder
		if absf(err) < 0.02:
			return
		L.fg.look(-err * 160.0, 0.0, 4)
		await L.f(3)


func _fight() -> void:
	var tf := TowerFloors.instance
	var lv := tf._levels
	var iu := TowerFloors.inner_u(tw)
	var iv := TowerFloors.inner_v(tw)
	var st := TowerFloors.at(tw, TowerFloors.SHAFT_L + 3.5, TowerFloors.SHAFT_W + 1.5, lv[2] + 0.05)
	var ep := TowerFloors.at(tw, iu - 1.0, TowerFloors.SHAFT_W + 1.5, lv[2] + 0.1)
	if OS.get_environment("STREET") == "1":
		st = Game.SPAWN
		ep = Game.SPAWN + Vector3(5.5, 0.1, 0.4)
	await L.tp(st, Lib.yaw_to(st, ep))
	var mgr := Game.enemies as EnemyManager
	var e := mgr.spawn(&"operative", ep, true)
	TestLib.check(e != null, "an enemy can be put on floor 2")
	if e == null:
		return
	e.max_hp = 4000.0
	e.hp = 4000.0
	await L.secs(1.5)
	var ey := e.global_position.y
	TestLib.check(absf(ey - lv[2]) < 0.5, "the enemy on floor 2 stands on floor 2 (y %.2f, floor %.2f) [old fails: it drops to the street under the floor]" % [ey, lv[2]])
	e.process_mode = Node.PROCESS_MODE_DISABLED          # setup: the target holds still for the shots (it stood 1.5 s on its own first)
	await _face(e.global_position)
	var hp0 := e.hp
	var am0: int = L.p.weapon.ammo if &"ammo" in L.p.weapon else -1
	print("fight: hero %s enemy %s cam pitch %.2f" % [L.p.global_position, e.global_position, L.p.camera_rig.pitch if &"pitch" in L.p.camera_rig else 0.0])
	for i in 10:                                      # short bursts by taps, the right thumb re-aims between them (yaw and pitch: recoil climbs)
		if not is_instance_valid(e):
			break
		var to := e.global_position + Vector3(0.0, 1.2, 0.0) - L.p.camera_rig.camera.global_position
		var err := wrapf(Lib.yaw_to(L.p.global_position, e.global_position) - L.p.camera_rig.yaw, -PI, PI)
		var perr := atan2(to.y, Vector2(to.x, to.z).length()) - L.p.camera_rig.pitch
		var pb: float = L.p.camera_rig.pitch
		L.fg.look(0.0, -perr * 160.0, 3)
		await _face(e.global_position)
		print("tap %d: yaw err %.2f pitch %.2f -> %.2f want %.2f enemy %s hp %.0f" % [i, err, pb, L.p.camera_rig.pitch, pb + perr, e.global_position, e.hp])
		L.fg.press(5, &"fire")
		await L.secs(0.15)
		L.fg.up(5)
		await L.secs(0.2)
	await L.f(3)
	var cpos: Vector3 = L.p.camera_rig.camera.global_position
	var rq := PhysicsRayQueryParameters3D.create(cpos, e.global_position + Vector3(0, 1.2, 0), Game.L_WORLD)
	var rh := L.p.get_world_3d().direct_space_state.intersect_ray(rq)
	if not rh.is_empty():
		var co := rh["collider"] as CollisionObject3D
		var ow := co.shape_owner_get_owner(co.shape_find_owner(rh["shape"])) as CollisionShape3D
		print("fight: ray cam %s hits %s at %s shape at %s size %s basis %s" % [cpos, co.name, rh["position"], ow.global_position, (ow.shape as BoxShape3D).size if ow.shape is BoxShape3D else Vector3.ZERO, ow.global_basis])
	var lc = L.p.weapon._last_collider
	print("fight: last collider %s" % [(lc as Node).get_path() if lc is Node else lc])
	print("fight: ammo %d -> %d, enemy %s" % [am0, L.p.weapon.ammo if &"ammo" in L.p.weapon else -1, e.global_position])
	TestLib.check(is_instance_valid(e) and e.hp < hp0, "a finger on FIRE hits the enemy on the same floor (hp %.0f -> %.0f) [old fails]" % [hp0, e.hp if is_instance_valid(e) else -1.0])
	e.process_mode = Node.PROCESS_MODE_INHERIT
	mgr.clear()


func _walls() -> void:
	var tf := TowerFloors.instance
	var iu := TowerFloors.inner_u(tw)
	var iv := TowerFloors.inner_v(tw)
	var st := TowerFloors.at(tw, iu * 0.5, iv - 1.5, 0.05)
	await L.tp(st, 0.0)
	await L.secs(0.5)
	var mgr := Game.enemies as EnemyManager
	var es: Array = []
	for f in [0.25, 0.5, 0.75]:
		var e := mgr.spawn(&"operative", TowerFloors.at(tw, iu * f, -9.0, 0.0), true)       # on the sidewalk behind the back wall
		if e != null:
			e.max_hp = 4000.0
			e.hp = 4000.0
			es.append(e)
	TestLib.check(es.size() == 3, "3 enemies behind the tower")
	var worst := -99.0
	var walls := 0
	var entered := false
	for i in 100:
		await L.secs(0.1)
		for e in es:
			if not is_instance_valid(e):
				continue
			var uv := TowerFloors.uv_of(tw, e.global_position)
			var g := TowerFloors.IN - 0.15                    # deeper than 0.15 m into the facade (a body brushing the facade is not in the wall)
			var in_foot := uv.x > -g and uv.x < iu + g and uv.y > -g and uv.y < iv + g
			var in_room := uv.x > 0.0 and uv.x < iu and uv.y > 0.0 and uv.y < iv
			var at_door := uv.y > iv - 0.5 and absf(uv.x - iu * 0.5) < TowerFloors.DOOR_W * 0.5
			if in_foot and not in_room and not at_door:
				walls += 1
			if in_room and uv.y < 0.6 and not entered:
				worst = maxf(worst, uv.y)                       # inside, by the back wall, before any came in by the door: through the wall
			if at_door:
				entered = true
	TestLib.check(walls <= 2 and worst < -0.2 and tf._cur == tw, "enemies behind the tower chasing the hero in the lobby never walk through its walls (%d frames in a wall, %.2f) [old fails: walk through]" % [walls, worst])
	mgr.clear()


## The opaque hero meshes the camera sees (not hidden, transparency under 0.5).
func _opaque_parts() -> Array:
	var out: Array = []
	for n in L.p.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g.is_visible_in_tree() and g.transparency < 0.5 and g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and g is MeshInstance3D:
			out.append(str(g.name))
	return out


func _stair_cam() -> void:
	var tf := TowerFloors.instance
	var lv := tf._levels
	var st := TowerFloors.at(tw, 0.7, TowerFloors.SHAFT_W - TowerFloors.LANE * 0.5, lv[1] + 0.05)
	var r := tf.route(3)
	await L.tp(st, Lib.yaw_to(st, r[2 + 5 + 1]))
	await L.secs(0.5)
	var bad := 0
	var close := 0
	var total := 0
	var seen := {}
	var pts: Array = r.slice(2 + 5, 2 + 5 * 3)
	print("stair: start %s target0 %s" % [L.p.global_position, pts[0]])
	for q in pts:
		print("stair: at %s -> %s" % [L.p.global_position, q])
		L.fg.stick(Vector2.ZERO)
		var err := wrapf(Lib.yaw_to(L.p.global_position, q) - L.p.camera_rig.yaw, -PI, PI)
		L.fg.look(-err * 160.0, 0.0, 4)
		await L.f(3)
		L.fg.stick(Vector2(0.0, -0.6))
		for i in 12:
			await L.secs(0.1)
			await L.host.get_tree().process_frame             # the camera and the fade move on the rendered frame
			var head := L.p.global_position + Vector3(0.0, 1.6, 0.0)
			var d := L.p.camera_rig.camera.global_position.distance_to(head)
			total += 1
			if d < 1.0:
				close += 1
				var op := _opaque_parts()
				if not op.is_empty():
					bad += 1
					for nm in op:
						seen[nm] = true
			if Lib.flat(L.p.global_position, q) < 0.5:
				break
	L.fg.stick(Vector2.ZERO)
	TestLib.check(total >= 10 and bad == 0 and L.p.global_position.y > lv[2] - 0.5, "up the stairwell by the stick (%d samples, y %.1f): %d samples with the lens under 1 m from his head, %d of them show an opaque hero mesh %s [old fails]" % [total, L.p.global_position.y, close, bad, seen.keys()])


func _dead_buttons() -> void:
	var tf := TowerFloors.instance
	var lv := tf._levels
	var iu := TowerFloors.inner_u(tw)
	var iv := TowerFloors.inner_v(tw)
	var st := TowerFloors.at(tw, iu * 0.5, iv * 0.5, lv[3] + 0.05)
	await L.tp(st, Lib.yaw_to(st, TowerFloors.at(tw, iu * 0.5, iv + 5.0)))
	await L.secs(0.5)
	var shown := []
	for a in [&"snake_zip", &"snake", &"fly"]:
		if L.fg.button(a) != Vector2.INF:
			shown.append(a)
	var p0 := L.p.global_position
	if L.fg.press(6, &"snake_zip"):
		await L.f(4)
		L.fg.up(6)
		await L.secs(1.5)
	var moved := L.p.global_position.distance_to(p0)
	TestLib.check(shown.is_empty() or moved > 1.0, "on floor 3 no dead snake buttons: shown %s, a finger on ZIP moved him %.1f m [old fails: ZIP shown, nothing happens]" % [shown, moved])
	var roof := TowerFloors.at(tw, iu * 0.5, iv * 0.5, (tw["lot"] as CityLayout.Lot).h + 0.05)
	await L.tp(roof, 0.0)
	await L.secs(0.5)
	TestLib.check(L.fg.button(&"snake_zip") != Vector2.INF, "on the roof ZIP is on screen again")


func _ceiling() -> void:
	var tf := TowerFloors.instance
	var lv := tf._levels
	var iu := TowerFloors.inner_u(tw)
	var iv := TowerFloors.inner_v(tw)
	var sep_u := iu / clampi(int(iu / 6.5), 2, 5)                        # the first room separator wall (tower_floors.gd _room_boxes)
	var st := TowerFloors.at(tw, sep_u + 1.2, iv - 1.0, lv[2] + 0.05)
	var wall := TowerFloors.at(tw, sep_u, iv - 1.0, lv[2] + 0.05)
	await L.tp(st, Lib.yaw_to(st, wall))
	await L.secs(0.5)
	L.fg.stick(Vector2(0.0, -1.0))
	await L.secs(0.3)
	await L.press(&"jump", 4)
	var top := 0.0
	var hung := 0.0
	for i in 30:
		await L.secs(0.1)
		var y := L.p.global_position.y - lv[2]
		top = maxf(top, y)
		if L.p.is_on_ceiling() or y > lv[3] - lv[2] - 2.2:
			hung += 0.1
	L.fg.stick(Vector2.ZERO)
	var y_end := L.p.global_position.y - lv[2]
	TestLib.check(hung <= 0.5 and y_end < 1.0, "stick into a room wall + JUMP on floor 2: %.1f s pressed under the ceiling (top %.2f m), %.2f m over the floor after 3 s [old fails: hangs under it]" % [hung, top, y_end])
