extends RefCounted
## w119-blasts probe: today's snake bombs by real fingers (ability wheel SNAKE BOMB disc; weapon wheel BOMBS wedge then FIRE).
const TIMEOUT_SECONDS := 140
const Audit := preload("res://tests/touch_audit_lib.gd")
const STREET := Vector3(-30.0, 0.0, 4.0)
var a: Audit
var p: Player

func _foes(n: int, d: float) -> Array:
	var out := []
	var dir := -p.global_basis.z
	dir.y = 0; dir = dir.normalized()
	for k in n:
		var pos := p.global_position + dir * d + dir.cross(Vector3.UP) * (k - 1) * 2.0
		var f := (Game.enemies as EnemyManager).spawn(&"operative", pos, false)
		if f: f.set_physics_process(false); f.global_position = pos; f.max_hp = 400; f.hp = 400; out.append(f)
	return out

func run(h: Node) -> void:
	a = Audit.new(); a.quiet = true
	if not await a.boot(h, "w119p"): print("PROBE boot fail"); return
	(Game.progress as Progress).new_campaign()
	Game.state = &"play"
	await a.frames(30)
	p = Game.player as Player
	p.max_hp = 1e6; p.hp = 1e6
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null: Encounters.current.enabled = false
	p.teleport_to(STREET); p.camera_rig.reset_view(-PI * 0.5, 0.05); p.yaw = -PI * 0.5
	await a.pframes(30)
	var war := SnakeWar.of(p)
	print("PROBE war=", war != null, " bomb_sel=", war.bomb_sel if war else "-", " unlocked=", SnakeRows.unlocked(war.bomb_sel) if war else false, " energy=", war.energy() if war else 0)
	var fs := _foes(3, 14.0)
	await a.pframes(4)
	# 1 ability wheel
	var ab := a.hud_button("ability")
	print("PROBE ability button: ", ab)
	a.fast_tap(a.centre_of(ab)); await a.frames(4)
	var list := a.touch_controls()
	var ids := []
	for c in list: ids.append(str(c.get("id")) + ":" + str(c.get("label")))
	print("PROBE wheel open=", a.tc.wheel.is_open, " discs=", ids)
	var d := a.find(list, "snake_bomb")
	var t0 := war.bombs.thrown
	war.bombs.connect_ops(); BlastOps.shared(p.get_tree()).detonated.connect(func(id, at): print("PROBE det ", id, " at ", at, " foes at ", fs.map(func(f): return f.global_position), " hero ", p.global_position, " aimpt ", SnakeAim.point(p, 30.0)))
	if not d.is_empty():
		await a.tap(d["centre"]); await a.pframes(150)
	print("PROBE after SNAKE BOMB disc: thrown ", t0, "->", war.bombs.thrown, " by_id=", war.bombs.by_id, " hp=", fs.map(func(f): return f.hp if is_instance_valid(f) else -1), " preview_radius=", war.preview_radius)
	a.tc.wheel.close()
	# 2 weapon wheel BOMBS
	war.cd.clear(); p.snake.energy = SnakePower.max_energy()
	var sw := a.hud_button("swap")
	print("PROBE swap button: ", sw.get("label"))
	a.finger_down(a.centre_of(sw)); await a.frames(40); a.finger_up(); await a.frames(2)
	a.finger_down(a.centre_of(sw)); await a.frames(40)
	list = a.touch_controls(); ids = []
	for c in list: ids.append(str(c.get("id")))
	print("PROBE weapon wheel open=", a.tc.wheel.is_open, " ", ids)
	var bw := a.find(list, "snake_bombs")
	if not bw.is_empty():
		a.finger_move(bw["centre"]); await a.frames(3); a.finger_up(); await a.frames(4)
		list = a.touch_controls(); ids = []
		for c in list: ids.append(str(c.get("id")))
		print("PROBE ring ", ids)
		var fr := a.find(list, "sb_freeze")
		if not fr.is_empty(): await a.tap(fr["centre"]); await a.frames(6)
	print("PROBE armed=", war.armed, " wheel open=", a.tc.wheel.is_open, " preview_radius=", war.preview_radius, " fire btn label=", a.hud_button("fire").get("label"))
	t0 = war.bombs.thrown
	await a.tap(a.centre_of(a.hud_button("fire"))); await a.pframes(150)
	print("PROBE after FIRE: thrown ", t0, "->", war.bombs.thrown, " by_id=", war.bombs.by_id, " hp=", fs.map(func(f): return f.hp if is_instance_valid(f) else -1))
	await a.shutdown()
