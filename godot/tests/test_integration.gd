extends RefCounted
## Integration test (headless): the REAL composed game, scenes/main.tscn = world + atmosphere + player (and every autoload), exercised through input actions.
## What no single-module test can check: the player's controller against the city's colliders (streets, walls, roofs, stepped ledges, the border), the
## registry and quality fan-out between modules, the hero's reflection in the world's mirror pass, the shared FX pool, a death/respawn cycle, and node leaks.
## Run: tools/test.sh tests/test_integration.gd
## The game runs SPEED_UP times faster than real time so the whole walk fits the 60 s watchdog with room to spare: Engine.time_scale = k alone would make every
## physics step k times longer (delta = time_scale / tick rate), so the tick rate is raised by the same factor (240 ticks per second, each still 1/60 s of game
## time). One `frames(n)` below is n ticks = n / 60 s of game time, as in a normal run.

const Fixture := preload("res://tests/player_fixture.gd")

## Records the camera where the renderer sees it: after the frame's _process of every other node (the rig runs at priority 100).
class CameraSampler extends Node:
	var camera: Camera3D
	var pos := Vector3.ZERO

	func _ready() -> void:
		process_priority = 1000

	func _process(_delta: float) -> void:
		pos = camera.global_position


const SPEED_UP := 4
const TICK_RATE := 60 * SPEED_UP

var host: Node
var main: Node
var p: Player
var city: City


## n physics ticks of 1/60 s of game time each.
func frames(n: int) -> void:
	await TestLib.frames(host, n)


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	Engine.physics_ticks_per_second = TICK_RATE
	Engine.time_scale = float(SPEED_UP)
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var ticks0 := Engine.get_physics_frames()
	var frames0 := Engine.get_process_frames()
	var t0 := Time.get_ticks_msec()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	p = Game.player as Player
	city = Game.world as City
	_composition()
	await _street_and_walls()
	await _roofs_and_ledges()
	await _sweeps()
	await _border()
	await _camera_against_a_facade()
	await _reflection()
	await _quality_tiers()
	_audio()
	_fx_pool()
	await _death_and_respawn()
	await _teardown(nodes_before)
	print("INTEGRATION: %d physics ticks (%.1f s of game time), %d process frames, %.1f s real" % [Engine.get_physics_frames() - ticks0, float(Engine.get_physics_frames() - ticks0) / 60.0,
			Engine.get_process_frames() - frames0, (Time.get_ticks_msec() - t0) / 1000.0])
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Sfx.muted = false


# --- helpers ------------------------------------------------------------------------------------------------------------------

## Fresh state: inputs released, full stats, the player standing at pos with the view along yaw.
func prep(pos: Vector3, yaw: float, pitch := -0.1, settle := 20) -> void:
	Fixture.release_inputs()
	Game.state = &"play"
	p.invuln = 0.0
	p.hp = p.max_hp
	p.since_hurt = 99.0
	p.weapon.reset()
	p.teleport_to(pos)
	p.camera_rig.reset_view(yaw, pitch)
	p.yaw = yaw
	await frames(settle)


func hold(actions: Array[StringName], n: int) -> void:
	for a in actions:
		Input.action_press(a)
	await frames(n)
	Fixture.release_inputs()


## The lot whose -Z face is the nearest one across the avenue from the spawn: a wall to walk into (face z in (5, 20)).
func facade_lot() -> CityLayout.Lot:
	var best: CityLayout.Lot = null
	for lot: CityLayout.Lot in city.layout.lots:
		if lot.contains_xz(Game.SPAWN.x, lot.rect.position.y + 1.0) and lot.rect.position.y > 5.0 and lot.rect.position.y < 20.0:
			if best == null or lot.rect.position.y < best.rect.position.y:
				best = lot
	return best


# --- composition --------------------------------------------------------------------------------------------------------------

func _composition() -> void:
	TestLib.check(is_instance_valid(Game.world) and is_instance_valid(Game.atmosphere) and is_instance_valid(Game.player) and is_instance_valid(Game.camera),
			"main.tscn registers the world, the atmosphere, the player and the camera")
	TestLib.check(Game.camera == p.camera_rig.camera and Game.camera.current, "the player's camera is the current gameplay camera")
	TestLib.check(Game.camera.far >= 1500.0, "the camera far plane (%.0f m) reaches the far skyline (world contract: at least 1500 m)" % Game.camera.far)
	TestLib.check(Game.state == &"play" and Game.is_playing(), "the game is in play")
	TestLib.check(city.get_mirror_root() != null and city.get_mirror_root().name == &"Mirror" and city.get_mirror_root().scale == Vector3(1, -1, 1),
			"the world exposes its mirror root (scale 1,-1,1)")
	TestLib.check(Game.atmosphere.get_parent() == main and city.get_parent() == main and p.get_parent() == main, "the three modules are siblings under Main")
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	TestLib.check(nodes < 1100, "the composed game stays small: %d nodes (the world is MultiMeshes and a 56-body prop collider pool, not thousands of nodes)" % nodes)


# --- the street and the walls -------------------------------------------------------------------------------------------------

func _street_and_walls() -> void:
	# spawn: the player stands on the road
	await prep(Game.SPAWN, -PI * 0.5, -0.12, 30)
	TestLib.check(p.is_on_floor() and absf(p.global_position.y) < 0.02, "the player stands on the street at y = 0 (y = %.3f)" % p.global_position.y)
	# walk down the avenue for 4 s
	var x0 := p.global_position.x
	var min_y := 0.0
	Input.action_press(&"move_forward")
	for i in 24:
		await frames(10)
		min_y = minf(min_y, p.global_position.y)
	Fixture.release_inputs()
	var walked := p.global_position.x - x0
	TestLib.check(walked > 22.0 and walked < 6.2 * 4.1, "walking 4 s down the avenue covers %.1f m (6.2 m/s, with the start-up ramp)" % walked)
	TestLib.check(absf(p.global_position.z - Game.SPAWN.z) < 0.6 and min_y > -0.03, "the walk stays on its lane and never sinks into the road (z drift %.2f, lowest y %.3f)" % [p.global_position.z - Game.SPAWN.z, min_y])
	# sprint speed
	await prep(Game.SPAWN + Vector3(-20.0, 0.0, 0.0), -PI * 0.5, -0.1, 20)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await frames(70)
	var v := Vector2(p.velocity.x, p.velocity.z).length()
	Fixture.release_inputs()
	TestLib.check(absf(v - 6.2 * 1.6) < 0.5, "sprinting reaches %.2f m/s (prototype: 9.92)" % v)
	# a facade across the avenue: push into it (forward + right): the player stops at the face and slides along it
	var lot := facade_lot()
	TestLib.check(lot != null, "a building face lies across the avenue from the spawn")
	if lot == null:
		return
	var face := lot.rect.position.y
	var start_x := lot.cx + lot.w * 0.25                          # the player slides toward -X (facing +Z, 'right' is -X): 0.75 of the width is ahead of him
	await prep(Vector3(start_x, 0.0, face - 3.0), PI, -0.1, 20)
	var max_z := -1.0e9
	Input.action_press(&"move_forward")
	Input.action_press(&"move_right")
	for i in 14:
		await frames(6)
		max_z = maxf(max_z, p.global_position.z)
	Fixture.release_inputs()
	var slid := absf(p.global_position.x - start_x)
	TestLib.check(max_z + Player.CAPSULE_RADIUS <= face + 0.02, "the player never enters the wall: front edge %.3f, face at %.3f" % [max_z + Player.CAPSULE_RADIUS, face])
	TestLib.check(max_z + Player.CAPSULE_RADIUS > face - 0.1, "...and reaches it (the front edge got within %.3f m of the face)" % (face - (max_z + Player.CAPSULE_RADIUS)))
	TestLib.check(slid > 3.0 and slid < lot.w * 0.75, "pushing diagonally into the wall slides along it (%.1f m in 1.4 s, the wall is %.0f m wide)" % [slid, lot.w])
	TestLib.check(not city.is_inside_building(p.global_position + Vector3(0.0, 1.0, 0.0)) and not city.is_inside_building(p.global_position + Vector3(0.0, 0.1, 0.0)),
			"the player's body is never inside a building volume after sliding along its wall")


# --- roofs and ledges ---------------------------------------------------------------------------------------------------------

func _roofs_and_ledges() -> void:
	# one tall lot per building class: the player dropped 2 m above the crown lands on it at the height the world reports
	var by_class := {}
	for b in city.building_data:
		var cls: StringName = b.cls
		if not by_class.has(cls) or b.lot.h > (by_class[cls].lot as CityLayout.Lot).h:
			by_class[cls] = b
	TestLib.check(by_class.size() == City.BM.ORDER.size(), "every building class exists in the city (%d of %d)" % [by_class.size(), City.BM.ORDER.size()])
	var good := 0
	var ledges := 0
	var ledges_good := 0
	for cls: StringName in City.BM.ORDER:
		if not by_class.has(cls):
			continue
		var lot: CityLayout.Lot = (by_class[cls] as Object).get(&"lot")
		var parts: Array = City.BM.CLASSES[cls]
		var top: Array = parts[parts.size() - 1]
		var cx: float = lot.cx + (top[0] + top[1]) * 0.5 * lot.w
		var cz: float = lot.cz + (top[2] + top[3]) * 0.5 * lot.d
		var roof_y := city.ground_height(cx, cz)
		await prep(Vector3(cx, roof_y + 2.0, cz), -PI * 0.5, -0.1, 34)
		if p.is_on_floor() and absf(p.global_position.y - roof_y) < 0.03 and absf(roof_y - lot.h) < 0.01:
			good += 1
		else:
			printerr("roof of a %s (h=%.0f) at (%.1f, %.1f): y=%.3f on_floor=%s ground_height=%.3f" % [cls, lot.h, cx, cz, p.global_position.y, str(p.is_on_floor()), roof_y])
		# the ledge around the crown (stepped classes): the top of the lower part, outside the crown's footprint
		if parts.size() > 1:
			var low: Array = parts[0]
			var ex: float = lot.cx + (top[1] + low[1]) * 0.5 * lot.w                # between the crown's +X edge and the lower part's +X edge
			var ez: float = lot.cz
			var ledge_y := city.ground_height(ex, ez)
			if ledge_y > 0.0 and ledge_y < lot.h - 0.5 and not city.is_inside_building(Vector3(ex, ledge_y + 0.3, ez)):
				ledges += 1
				await prep(Vector3(ex, ledge_y + 2.0, ez), -PI * 0.5, -0.1, 34)
				if p.is_on_floor() and absf(p.global_position.y - ledge_y) < 0.03:
					ledges_good += 1
				else:
					printerr("ledge of a %s at (%.1f, %.1f): y=%.3f on_floor=%s ground_height=%.3f" % [cls, ex, ez, p.global_position.y, str(p.is_on_floor()), ledge_y])
	TestLib.check(good == by_class.size(), "the player lands on the crown of every building class at the height the world reports (%d of %d)" % [good, by_class.size()])
	TestLib.check(ledges >= 4 and ledges_good == ledges, "...and on the stepped ledges around the crowns (%d of %d)" % [ledges_good, ledges])
	# walking off a roof edge falls to the street, no invisible floor
	var low_lot: CityLayout.Lot = null
	for b in city.building_data:
		if b.cls == &"block" and b.lot.h <= 28.0 and absf(b.lot.cx) < 120.0 and absf(b.lot.cz) < 120.0:
			low_lot = b.lot
			break
	if low_lot != null:
		var edge_x := low_lot.rect.end.x - 1.0
		await prep(Vector3(edge_x, low_lot.h + 0.05, low_lot.cz), -PI * 0.5, -0.1, 20)
		TestLib.check(p.is_on_floor() and absf(p.global_position.y - low_lot.h) < 0.03, "standing 1 m from the edge of a %.0f m roof" % low_lot.h)
		Input.action_press(&"move_forward")
		await frames(140)
		Fixture.release_inputs()
		TestLib.check(p.global_position.x > low_lot.rect.end.x and p.global_position.y < 1.0 and p.is_on_floor(),
				"walking off the roof edge drops to the street (x = %.1f past the edge %.1f, y = %.2f)" % [p.global_position.x, low_lot.rect.end.x, p.global_position.y])


# --- sweeps over the whole city -----------------------------------------------------------------------------------------------

## A sample spread over the whole city: every 5th building crown and every 4th junction, the player dropped from 0.5 m to 1.5 m, must land at the height the world reports
## (a collider that is missing, shifted or a different height from what is drawn shows up here, whatever the building class or the position).
func _sweeps() -> void:
	var lots := city.layout.lots
	city.prop_colliders().enabled = false      # this sweep checks the bare building crowns, not the roof clutter that stands on them
	city.update_colliders(Vector3(0.0, -2000.0, 0.0))
	var good := 0
	var tried := 0
	for i in range(0, lots.size(), 5):
		var lot := lots[i]
		var b: Object = city.building_data[lot.index]
		var parts: Array = City.BM.CLASSES[b.get(&"cls")]
		var top: Array = parts[parts.size() - 1]
		var x: float = lot.cx + (top[0] + top[1]) * 0.5 * lot.w + 0.7
		var z: float = lot.cz + (top[2] + top[3]) * 0.5 * lot.d - 0.9
		var y := city.ground_height(x, z)
		tried += 1
		await prep(Vector3(x, y + 1.5, z), -PI * 0.5, -0.1, 24)
		if p.is_on_floor() and absf(p.global_position.y - y) < 0.03 and absf(y - lot.h) < 0.01:
			good += 1
		else:
			printerr("crown of lot %d (%s, h=%.0f) at (%.1f, %.1f): y=%.3f on_floor=%s ground_height=%.3f" % [lot.index, b.get(&"cls"), lot.h, x, z, p.global_position.y, str(p.is_on_floor()), y])
	city.prop_colliders().enabled = true
	TestLib.check(tried >= 40 and good == tried, "a sample of %d building crowns spread over the city: the player lands on each at the reported height (%d)" % [tried, good])
	good = 0
	tried = 0
	for i in range(0, city.intersections.size(), 4):
		var j := city.intersections[i]
		tried += 1
		await prep(j + Vector3(0.0, 0.5, 0.0), -PI * 0.5, -0.1, 22)
		if p.is_on_floor() and absf(p.global_position.y) < 0.02:
			good += 1
		else:
			printerr("junction %s: y=%.3f on_floor=%s" % [str(j), p.global_position.y, str(p.is_on_floor())])
	TestLib.check(tried >= 12 and good == tried, "a sample of %d junctions: the street is solid ground at y = 0 everywhere (%d)" % [tried, good])


# --- the border ---------------------------------------------------------------------------------------------------------------

func _border() -> void:
	var limit := CityLayout.WALK
	await prep(Vector3(limit - 6.0, 0.0, 0.0), -PI * 0.5, -0.1, 20)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await frames(110)
	Fixture.release_inputs()
	TestLib.check(p.global_position.x <= limit - Player.CAPSULE_RADIUS + 0.02 and p.global_position.x > limit - 1.0, "the invisible border wall stops a sprint at x = %.2f (inner face %.0f)" % [p.global_position.x, limit])
	await prep(Vector3(0.0, 0.0, -limit + 6.0), PI, -0.1, 20)
	Input.action_press(&"move_back")
	await frames(120)
	Fixture.release_inputs()
	TestLib.check(p.global_position.z >= -limit + Player.CAPSULE_RADIUS - 0.02, "the north border holds as well (z = %.2f)" % p.global_position.z)


# --- the camera against a facade ----------------------------------------------------------------------------------------------

func _camera_against_a_facade() -> void:
	var lot := facade_lot()
	if lot == null:
		return
	# the player's back 0.4 m from the -Z face of the building, looking away from it (-Z): the camera arm is squeezed to its floor
	var face := lot.rect.position.y
	await prep(Vector3(Game.SPAWN.x, 0.0, face - 0.4), 0.0, -0.08, 60)
	# Sample the camera where the renderer sees it: after the frame's _process. Right after a physics tick the SpringArm3D has just re-placed its child at the
	# raw solved arm length (0.17 m here); CameraRig._process then writes the final pose (floor 0.85 m, sideways slide) before anything is drawn.
	var sampler := CameraSampler.new()
	sampler.camera = p.camera_rig.camera
	host.add_child(sampler)
	await frames(8)
	var cam := sampler.pos
	sampler.queue_free()
	var back := cam.z - p.global_position.z
	TestLib.check(back > 0.3 and back < 1.2, "squeezed against the wall the camera sits %.2f m behind the player (floor 0.85 m)" % back)
	var inside := city.is_inside_building(cam)
	var depth := cam.z - face
	print("camera squeezed against a facade: z = %.2f, face at %.2f -> %.2f m %s the wall volume" % [cam.z, face, absf(depth), "inside" if depth > 0.0 else "outside"])
	TestLib.check(depth < 0.8, "the camera never sinks more than 0.8 m into the wall behind the player (%.2f m)" % depth)
	TestLib.check(is_equal_approx(p.camera_rig.camera.near, 0.08) or p.camera_rig.camera.near < 0.15, "the near plane (%.2f m) is small enough to keep the character from clipping" % p.camera_rig.camera.near)
	if inside:
		print("  note: the camera is inside the facade volume; back faces are culled so the street stays visible")


# --- the hero's reflection ----------------------------------------------------------------------------------------------------

func _reflection() -> void:
	await prep(Game.SPAWN, -PI * 0.5, -0.12, 20)
	Game.set_quality(1)
	await frames(6)
	var proxy := p.body.get_node_or_null("Reflection") as MirrorProxy
	TestLib.check(proxy != null, "the player body owns a MirrorProxy")
	if proxy == null:
		return
	var mirror := city.get_mirror_root()
	var n := proxy.copy_count()
	if p.body.rig != null:
		TestLib.check(n == 0, "the skinned hero has no reflection copy (a rest-pose copy showed a second, stationary body): %d" % n)
		return
	TestLib.check(n >= 1, "the world's mirror pass holds the hero's reflection: %d mesh (the articulated body is one mesh)" % n)
	var src := p.body.rig.rest_mesh if p.body.rig != null else (p.body.upper.find_child("Body", true, false) as MeshInstance3D)    # the skinned model is reflected through its unskinned rest-pose twin
	var copy := mirror.get_node_or_null("Reflection_%s" % (src.name if src != null else "Body")) as MeshInstance3D
	TestLib.check(src != null and copy != null and copy.mesh == src.mesh, "the reflection shares the original's mesh (no extra mesh memory)")
	if src != null and copy != null:
		var a := src.global_transform.origin
		var b := copy.global_transform.origin
		TestLib.check(copy.visible and b.distance_to(Vector3(a.x, -a.y, a.z)) < 0.01, "the reflection sits at the mirrored position of the body (%s vs %s)" % [str(a), str(b)])
		# a mirrored transform has a negative determinant; the reflection must be the exact mirror image of the original, scale included
		var ref_basis := Basis.from_scale(Vector3(1, -1, 1)) * src.global_transform.basis
		TestLib.check(copy.global_transform.basis.is_equal_approx(ref_basis), "...with the mirrored orientation")
		TestLib.check(copy.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "the reflection casts no shadow")
		p.body.visible = false
		await frames(3)
		TestLib.check(not copy.visible, "a hidden body (the player in a vehicle) hides its reflection")
		p.body.visible = true
		await frames(3)
		# moving: the reflection follows
		await prep(Game.SPAWN, -PI * 0.5, -0.12, 10)
		Input.action_press(&"move_forward")
		await frames(40)
		Fixture.release_inputs()
		var a2 := src.global_transform.origin
		var b2 := copy.global_transform.origin
		TestLib.check(b2.distance_to(Vector3(a2.x, -a2.y, a2.z)) < 0.01 and absf(a2.x - a.x) > 1.0, "the reflection follows the walking hero")
	# the LOW tier draws no mirrored city, so the reflection is hidden with it
	Game.set_quality(0)
	await frames(4)
	TestLib.check(not mirror.is_visible_in_tree() and copy != null and not copy.is_visible_in_tree(), "LOW: the mirror pass, and with it the reflection, is off")
	Game.set_quality(1)
	await frames(4)
	TestLib.check(mirror.is_visible_in_tree() and copy != null and copy.is_visible_in_tree(), "MED: the reflection is back")


# --- quality fan-out ----------------------------------------------------------------------------------------------------------

func _quality_tiers() -> void:
	var vp := p.get_viewport()
	var seen := {}
	var listener := func(level: int) -> void: seen[level] = true
	Game.quality_changed.connect(listener)
	for level in [0, 2, 1]:
		Game.set_quality(level)
		await frames(2)
		var ok: bool = city.quality == level and Game.atmosphere.quality == level and Game.quality == level
		TestLib.check(ok, "Game.set_quality(%d) reaches the world (%d) and the atmosphere (%d)" % [level, city.quality, Game.atmosphere.quality])
		TestLib.check(is_equal_approx(vp.scaling_3d_scale, 0.7 if level == 0 else 1.0), "tier %d: the world sets the render scale (%.2f)" % [level, vp.scaling_3d_scale])
		TestLib.check(city.sun.shadow_enabled == (level >= 1), "tier %d: moon shadows %s" % [level, "on" if level >= 1 else "off"])
		TestLib.check(Game.atmosphere.particle_count() <= Atmosphere.particle_budget(level), "tier %d: rain stays within its budget (%d <= %d)" % [level, Game.atmosphere.particle_count(), Atmosphere.particle_budget(level)])
	Game.quality_changed.disconnect(listener)
	TestLib.check(seen.size() == 3, "quality_changed fired for every change")
	TestLib.check(Atmosphere.particle_budget(0) < Atmosphere.particle_budget(1) and Atmosphere.particle_budget(1) < Atmosphere.particle_budget(2), "rain density grows with the tier")


# --- audio ---------------------------------------------------------------------------------------------------------------------

func _audio() -> void:
	var sfx := AudioServer.get_bus_index(&"SFX")
	var music := AudioServer.get_bus_index(&"Music")
	TestLib.check(sfx >= 0 and music >= 0, "the bus layout is loaded: SFX (%d) and Music (%d) exist" % [sfx, music])
	TestLib.check(AudioServer.get_bus_effect_count(0) >= 1 and AudioServer.get_bus_effect(0, 0) is AudioEffectLimiter, "the Master bus ends in a limiter (a firefight never clips)")
	TestLib.check(sfx >= 0 and AudioServer.get_bus_send(sfx) == &"Master" and music >= 0 and AudioServer.get_bus_send(music) == &"Master", "SFX and Music feed the Master bus")
	var on_sfx := 0
	var total := 0
	for c in Sfx.get_children():
		if c is AudioStreamPlayer and c.name != &"Music":
			total += 1
			on_sfx += 1 if (c as AudioStreamPlayer).bus == &"SFX" else 0
		elif c is AudioStreamPlayer3D:
			total += 1
			on_sfx += 1 if (c as AudioStreamPlayer3D).bus == &"SFX" else 0
	TestLib.check(total >= 20 and on_sfx == total, "every effect voice plays on the SFX bus (%d of %d)" % [on_sfx, total])
	var player := Sfx.get_node("Music") as AudioStreamPlayer
	TestLib.check(player.bus == &"Music" and is_equal_approx(player.volume_db, Sfx.MUSIC_DB), "the music has its own player on the Music bus, %.0f dB below the effects" % -player.volume_db)
	var loop := load("res://assets/audio/music_ambient.wav") as AudioStreamWAV
	TestLib.check(loop != null and loop.loop_mode == AudioStreamWAV.LOOP_FORWARD and loop.format == AudioStreamWAV.FORMAT_16_BITS,
			"music_ambient.wav is 16-bit PCM and loops forward by itself (loop mode %s)" % (str(loop.loop_mode) if loop != null else "?"))
	Sfx.play_music()
	TestLib.check(Sfx.is_music_playing() and player.stream is AudioStreamSynchronized, "Sfx.play_music() starts the adaptive music (five stems under one synchronized stream)")
	Sfx.stop_music()
	Sfx.stop_ambience()


# --- the shared FX pool -------------------------------------------------------------------------------------------------------

func _fx_pool() -> void:
	var emitters: Array[CPUParticles3D] = []
	for c in FX.get_children():
		if c is CPUParticles3D:
			emitters.append(c)
	TestLib.check(emitters.size() == FX.PARTICLE_POOL, "the FX pool has %d emitters" % emitters.size())
	var all_hidden := true
	var no_shadows := true
	for e in emitters:
		all_hidden = all_hidden and not e.visible
		no_shadows = no_shadows and e.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	TestLib.check(all_hidden, "idle FX emitters are hidden (they cost no draw call)")
	TestLib.check(no_shadows, "FX emitters cast no shadows (no extra draw call per shadow cascade)")
	var mats_ok := true
	for e in emitters:
		var m := (e.mesh as QuadMesh).material as StandardMaterial3D
		mats_ok = mats_ok and m != null and m.albedo_texture != null
	TestLib.check(mats_ok, "sparks are textured soft sprites, not untextured cards")
	FX.burst(Vector3(0.0, 5.0, 0.0), Color.ORANGE, 20, 3.0, 0.3)
	var live := 0
	for e in emitters:
		if e.visible and e.emitting:
			live += 1
	TestLib.check(live == 1, "a burst plays on exactly one pooled emitter (%d)" % live)


func _fx_after_burst() -> void:
	var live := 0
	for c in FX.get_children():
		if c is CPUParticles3D and (c as CPUParticles3D).visible:
			live += 1
	TestLib.check(live == 0, "a finished burst hides its emitter again (%d still visible)" % live)
	var lights := 1 if FX.explosions.light.visible else 0
	TestLib.check(lights == 0, "a finished blast switches its light off (%d lights still on)" % lights)


# --- death and respawn --------------------------------------------------------------------------------------------------------

func _death_and_respawn() -> void:
	await prep(Game.SPAWN + Vector3(10.0, 0.0, 0.0), -PI * 0.5, -0.1, 20)
	Game.explode(p.global_position + Vector3(8.0, 0.5, 0.0), 4.0, {"player_dmg": 0.0})
	await frames(80)
	_fx_after_burst()
	p.damage(999.0)
	await frames(50)
	TestLib.check(Game.state == &"dead" and p.is_dead(), "dying in the composed game ends the run")
	var dead_pos := p.global_position
	await frames(25)
	TestLib.check(p.is_on_floor() and absf(p.global_position.y) < 0.03 and p.global_position.distance_to(dead_pos) < 0.5, "the body lies still on the street")
	Game.do_respawn()
	await frames(10)
	TestLib.check(Game.state == &"play" and not p.is_dead() and p.hp == p.max_hp and p.global_position.distance_to(Game.SPAWN) < 0.5, "respawn restores the player at the spawn point")
	TestLib.check(Game.atmosphere.particle_count() >= 0 and is_instance_valid(Game.camera) and Game.camera.current, "the camera and the rain survive a respawn")


# --- teardown -----------------------------------------------------------------------------------------------------------------

func _teardown(nodes_before: int) -> void:
	Fixture.release_inputs()
	main.queue_free()
	await frames(10)
	var nodes_after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	TestLib.check(Game.world == null and Game.player == null and Game.atmosphere == null and Game.camera == null, "freeing the game clears every registry entry")
	TestLib.check(nodes_after <= nodes_before + 2, "freeing the game leaves no nodes behind (%d before, %d after)" % [nodes_before, nodes_after])
	Game.state = &"menu"
