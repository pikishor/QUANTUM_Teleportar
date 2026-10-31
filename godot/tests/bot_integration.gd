extends RefCounted
## Integration bot (wave 1): drives the REAL Player through the REAL composed game (scenes/main.tscn = world + atmosphere + player + the
## autoload effects) and lets Dev save a screenshot at the end of every phase. Nothing is stripped or faked: this is what a phone would draw.
##   tools/bot.sh res://tests/bot_integration.gd <out_prefix> 30 20     (every 30 frames, 20 pictures: phases 0-19; writes <out_prefix>_000.png ...)
##   RENDERER=compat tools/bot.sh ...                                      (OpenGL Compatibility renderer)
##   BOT_PHASES=0,9,11 tools/bot.sh ... 30 3                               (run only these phases, in this order; the count must match)
##   BOT_QUALITY=0|1|2                                                      (graphics tier for the whole run; default: the game's own)
## Every phase prints one "BOT" line at its last frame (the screenshot frame; the render counters are those of the frame before): draw calls, primitives and objects of the camera pass and of the whole frame,
## the node count, the player's position and what the world says is under it (is_on_floor, ground_height, is_inside_building).
## Software rendering runs at a few fps, so the game runs in slow motion (Engine.time_scale): every rendered frame then covers about 20-50 ms of
## game time, like a 20-50 fps device. Phases are counted in rendered frames and end exactly on a screenshot frame.
##   0 spawn  1 walk  2 sprint  3 jump  4 ads  5 fire_facade  6 fire_ground  7 wall_slide  8 corner  9 junction  10 roof_low  11 roof_tower
##   12 roof_edge  13 death  14 respawn  15 tier_low  16 tier_high  17 alley  18 plaza  19 street_run  20 explosion  21 wall_holes  22 title  23 victory

const Fixture := preload("res://tests/player_fixture.gd")

const NAMES: Array[String] = ["spawn", "walk", "sprint", "jump", "ads", "fire_facade", "fire_ground", "wall_slide", "corner", "junction",
		"roof_low", "roof_tower", "roof_edge", "death", "respawn", "tier_low", "tier_high", "alley", "plaza", "street_run", "explosion", "wall_holes", "title", "victory"]

var _every := 30
var _count := 20
var _setup_done := false
var _p: Player
var _rig: CameraRig
var _phase := -1
var _order: Array[int] = []
var _quality := -1
var _last_ms := 0
var _fps_sum := 0.0
var _fps_n := 0
var _scale := 0.25
var _tower: CityLayout.Lot
var _low_roof: CityLayout.Lot
var _facade_target := Vector3.ZERO
var _wall_z := 0.0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			if kv[0] == "every":
				_every = maxi(30, int(kv[1]))
			elif kv[0] == "count":
				_count = maxi(1, int(kv[1]))
	for part in OS.get_environment("BOT_PHASES").split(",", false):
		_order.append(int(part))
	if OS.get_environment("BOT_QUALITY") != "":
		_quality = int(OS.get_environment("BOT_QUALITY"))


func _world() -> City:
	return Game.world as City


func _ground(x: float, z: float, from_y := 1.0e9) -> float:
	return _world().ground_height(x, z, from_y)


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	_rig = _p.camera_rig
	Engine.time_scale = _scale
	if _quality >= 0:
		Game.set_quality(_quality)
	# lighting experiments: BOT_NO_CHAR_LIGHT=1 (the hero's key and rim lights off), BOT_NO_MOON=1 (the moon off), BOT_NO_AMBIENT=1 (the ambient off)
	if OS.get_environment("BOT_NO_CHAR_LIGHT") != "":
		_p.body.character_light = false
	if OS.get_environment("BOT_NO_MOON") != "":
		_world().sun.visible = false
	if OS.get_environment("BOT_NO_AMBIENT") != "":
		var we := _world().get_node("Environment") as WorldEnvironment
		we.environment.ambient_light_energy = 0.0
	var w := _world()
	# the tallest building closest to the city centre (the showcase roof) and a low one near the spawn (a walkable street-side roof)
	var best_d := 1.0e9
	var best_low := 1.0e9
	for b in w.building_data:
		var lot: CityLayout.Lot = b.lot
		var d := Vector2(lot.cx, lot.cz).length()
		if lot.h >= 88.0 and d < best_d:
			best_d = d
			_tower = lot
		var dl := Vector2(lot.cx + 30.0, lot.cz - 10.0).length()
		if lot.h <= 28.0 and b.cls == &"block" and dl < best_low:
			best_low = dl
			_low_roof = lot
	# the building face across the avenue from the spawn: lot whose -Z face is nearest to (-30, 12)
	var best_f := 1.0e9
	for lot: CityLayout.Lot in w.layout.lots:
		if lot.contains_xz(Game.SPAWN.x, lot.rect.position.y + 1.0) and lot.rect.position.y > 5.0 and lot.rect.position.y < 20.0 and lot.rect.position.y < best_f:
			best_f = lot.rect.position.y
			_wall_z = lot.rect.position.y
			_facade_target = Vector3(Game.SPAWN.x + 4.0, 3.0, lot.rect.position.y)
	if _wall_z == 0.0:
		_wall_z = 12.0
		_facade_target = Vector3(Game.SPAWN.x + 4.0, 3.0, 12.0)
	print("BOT setup: tower at ", Vector2(_tower.cx, _tower.cz), " h=", _tower.h, " low roof at ", Vector2(_low_roof.cx, _low_roof.cz), " h=", _low_roof.h,
			" facade z=", _wall_z, " quality=", Game.quality, " renderer=", RenderingServer.get_video_adapter_name())


func _reset_player(pos: Vector3, yaw: float, pitch := -0.1) -> void:
	Fixture.release_inputs()
	Game.state = &"play"
	_p.vehicle = null
	_p.invuln = 0.0
	_p.hp = _p.max_hp
	_p.energy = _p.max_energy
	_p.since_hurt = 99.0
	_p.weapon.reset()
	_p.teleport_to(pos)
	_rig.reset_view(yaw, pitch)
	_p.yaw = yaw


func step(_t: float, _delta: float) -> bool:
	if Game.player == null or Game.world == null:
		return false
	if not _setup_done:
		_setup()
	var f: int = Dev.get(&"_frame")
	var slot := (f - 1) / _every
	var phase := _order[slot % _order.size()] if not _order.is_empty() else slot
	var k := ((f - 1) % _every) + 1                  # 1 .. _every, the screenshot is taken at k == _every
	if slot != _phase:
		_phase = slot
		_enter(phase)
		print("BOT phase %d %s (frame %d)" % [phase, NAMES[phase % NAMES.size()], f])
	_run(phase, k)
	var now := Time.get_ticks_msec()
	if _last_ms > 0:
		_fps_sum += 1000.0 / maxf(1.0, float(now - _last_ms))
		_fps_n += 1
	_last_ms = now
	if k == _every:
		_print_stats(phase)
	return f >= _every * _count


func _print_stats(phase: int) -> void:
	var vp := _p.get_viewport().get_viewport_rid()
	var info := RenderingServer
	var pos := _p.global_position
	var w := _world()
	print("BOT stats %2d %-12s visible: draws=%d prims=%d objs=%d | frame total: draws=%d prims=%d | nodes=%d | player (%.1f, %.2f, %.1f) floor=%s ground=%.2f inside_building=%s | shots=%d ammo=%d hp=%d | tex_mem=%.0f MB buf_mem=%.0f MB | sw fps %.1f" % [
			phase, NAMES[phase % NAMES.size()],
			info.viewport_get_render_info(vp, info.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, info.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			info.viewport_get_render_info(vp, info.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, info.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
			info.viewport_get_render_info(vp, info.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, info.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
			info.get_rendering_info(info.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), info.get_rendering_info(info.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			pos.x, pos.y, pos.z, str(_p.is_on_floor()), w.ground_height(pos.x, pos.z, pos.y + 1.0), str(w.is_inside_building(pos + Vector3(0.0, 1.0, 0.0))),
			_p.weapon.shots_fired, _p.ammo, int(_p.hp),
			float(info.get_rendering_info(info.RENDERING_INFO_TEXTURE_MEM_USED)) / 1048576.0, float(info.get_rendering_info(info.RENDERING_INFO_BUFFER_MEM_USED)) / 1048576.0,
			_fps_sum / maxf(1.0, float(_fps_n))])
	_fps_sum = 0.0
	_fps_n = 0


## Called once at the first frame of a phase.
func _enter(phase: int) -> void:
	var yaw := -PI * 0.5
	_scale = 0.25
	match phase:
		0:
			_reset_player(Game.SPAWN, yaw, -0.12)
		1:
			_scale = 1.0
			_reset_player(Game.SPAWN, yaw, -0.12)
			Input.action_press(&"move_forward")
		2:
			_scale = 1.0
			_reset_player(Game.SPAWN + Vector3(-26.0, 0.0, -1.0), yaw, -0.08)
			Input.action_press(&"move_forward")
			Input.action_press(&"sprint")
		3:
			_reset_player(Game.SPAWN + Vector3(-8.0, 0.0, 0.0), yaw, -0.1)
		4:
			_reset_player(Game.SPAWN, yaw, -0.05)
			Input.action_press(&"aim")
		5:
			_reset_player(Game.SPAWN + Vector3(0.0, 0.0, 2.0), yaw, -0.05)
		6:
			_reset_player(Game.SPAWN + Vector3(0.0, 0.0, -1.0), yaw, -0.3)
		7:
			_scale = 0.5
			_reset_player(Vector3(Game.SPAWN.x, 0.0, _wall_z - 3.0), PI, -0.12)        # facing +Z, the wall, 3 m away
			Input.action_press(&"move_forward")
			Input.action_press(&"move_right")
		8:
			_reset_player(_facade_spot(), yaw, -0.08)
		9:
			_reset_player(Vector3(-13.0, 0.0, 6.0), -PI * 0.42, -0.02)
		10:
			var spot := _roof_spot(_low_roof, 0.35)
			_reset_player(spot, yaw, -0.1)
		11:
			var spot := _roof_spot(_tower, 0.0)
			_reset_player(spot, -PI * 0.25, -0.08)
		12:
			var spot := _roof_spot(_tower, 0.9)
			_reset_player(spot, PI * 0.5, -0.45)
		13:
			_reset_player(Game.SPAWN, yaw, -0.1)
			_p.damage(999.0)
		14:
			Game.do_respawn()
		15:
			Game.set_quality(0)
			_reset_player(Game.SPAWN, yaw, -0.12)
		16:
			Game.set_quality(2)
			_reset_player(Game.SPAWN, yaw, -0.12)
		17:
			_reset_player(_gap_spot(), yaw, -0.08)
		18:
			_reset_player(_plaza_spot(), yaw, -0.08)
		19:
			_scale = 1.0
			_reset_player(Vector3(-200.0, 0.0, -5.0), yaw, -0.06)
			Input.action_press(&"move_forward")
			Input.action_press(&"sprint")
		20:
			_reset_player(Game.SPAWN, yaw, -0.08)
		21:
			_reset_player(Vector3(Game.SPAWN.x, 0.0, _wall_z - 7.0), PI, -0.05)
			_p.decals.clear()
			Input.action_press(&"aim")
		22, 23:
			_scale = 2.0                                          # the cinematic camera blends in over a few seconds of game time
			_reset_player(Game.SPAWN, yaw, -0.12)
			Game.state = &"menu" if phase == 22 else &"win"
		_:
			_reset_player(Game.SPAWN, yaw)
	Engine.time_scale = _scale


func _run(phase: int, k: int) -> void:
	var e := _every
	match phase:
		3:
			if k == e - 17:
				Input.action_press(&"jump")
			elif k == e - 14:
				Input.action_release(&"jump")
		4:
			_rig.look_at_point(_facade_target)
		5, 6:
			# the shot leaves in the physics tick right after the press, so the flash, tracer and sparks are all alive in the screenshot frame
			_rig.look_at_point(_facade_target if phase == 5 else _p.global_position + Vector3(14.0, 0.0, 1.0))
			if k == e - 1:
				Input.action_press(&"fire")
			elif k == e:
				Input.action_release(&"fire")
		7:
			_rig.yaw = PI                                       # look at the wall while sliding along it
			_rig.pitch = -0.12
		20:
			if k == e - 3:                                      # a blast 11 m ahead, caught a few frames into its life
				Game.explode(_p.global_position + Vector3(11.0, 0.5, 0.0), 6.0, {"player_dmg": 0.0, "enemy_dmg": 0.0, "car_dmg": 0.0})
		21:
			# a burst of 12 rounds into the facade: the holes stay, the sparks are fresh at the end
			_rig.look_at_point(Vector3(Game.SPAWN.x + 1.0, 2.2, _wall_z))
			if k >= 4 and k < e - 8 and k % 3 == 0:
				Input.action_press(&"fire")
			elif k == e - 1:
				Input.action_press(&"fire")
			else:
				Input.action_release(&"fire")
		10, 11, 12:
			pass
		_:
			pass


## A street spot 0.4 m east of a building face (bot_player's rule), the one nearest the spawn: a player looking east has the facade at the back.
func _facade_spot() -> Vector3:
	var w := _world()
	var best := Game.SPAWN
	var best_d := 1.0e9
	for r in w.building_rects:
		var rect := r as Rect2
		if rect.size.x < 14.0 or rect.size.y < 14.0:
			continue
		var spot := Vector3(rect.end.x + 0.4, 0.0, rect.position.y + rect.size.y * 0.5)
		var d := Vector2(spot.x - Game.SPAWN.x, spot.z - Game.SPAWN.z).length()
		if d < best_d and not w.is_inside_building(spot) and absf(w.ground_height(spot.x, spot.z, 5.0)) < 0.1:
			best_d = d
			best = spot
	return best


## Standing spot on the top part of a building: `edge` 0 = centre of the roof, 1 = right at its +X edge.
func _roof_spot(lot: CityLayout.Lot, edge: float) -> Vector3:
	var p: Array = City.BM.top_part(_world().building_data[lot.index].cls)
	var x0: float = lot.cx + p[0] * lot.w
	var x1: float = lot.cx + p[1] * lot.w
	var z0: float = lot.cz + p[2] * lot.d
	var z1: float = lot.cz + p[3] * lot.d
	var x := lerpf((x0 + x1) * 0.5, x1 - 0.9, edge)
	var z := (z0 + z1) * 0.5
	return Vector3(x, _ground(x, z) + 0.05, z)


## A narrow gap between two lots of the same block, or the street spot next to a building if the layout has none.
func _gap_spot() -> Vector3:
	var w := _world()
	var best := Vector3.INF
	var best_gap := 1.0e9
	for bi in CityLayout.N:
		for bj in CityLayout.N:
			var bx := -CityLayout.HALF + (bi + 0.5) * CityLayout.PITCH
			var bz := -CityLayout.HALF + (bj + 0.5) * CityLayout.PITCH
			if Vector2(bx, bz).length() > 150.0:
				continue
			var lots := w.layout.block_lots(bx, bz)
			for a: CityLayout.Lot in lots:
				for b: CityLayout.Lot in lots:
					if a == b or a.cx >= b.cx or absf(a.cz - b.cz) > 1.0:
						continue
					var gap := b.rect.position.x - a.rect.end.x
					if gap > 3.0 and gap < best_gap:
						best_gap = gap
						best = Vector3((a.rect.end.x + b.rect.position.x) * 0.5, 0.0, a.cz)
	if best == Vector3.INF:
		return Game.SPAWN
	print("BOT gap spot ", best, " gap ", best_gap)
	return best


## The centre of a plaza (an empty lot), nearest the city centre.
func _plaza_spot() -> Vector3:
	var best := Game.SPAWN
	var best_d := 1.0e9
	for pz: Vector2 in _world().layout.plazas:
		var d := pz.length()
		if d < best_d:
			best_d = d
			best = Vector3(pz.x, 0.0, pz.y)
	return best
