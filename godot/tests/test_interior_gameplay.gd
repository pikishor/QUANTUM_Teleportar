extends RefCounted
## Interior gameplay, core flows on the REAL composed game (scenes/main.tscn): data limits, the doors of the city, the door markers, the USE prompt, enter and exit with fades,
## player state through the door (hp, energy, weapons, ammo, HEAT), hunters following in, the street's enemies stored and restored, the walls the enemies obey, civilians and
## guards within the actor cap, interior radio, the minimap layout, the HUD / touch hooks, saving inside an interior and the safe respawn at the door.
## Vendors: tests/test_interior_gameplay_vendors.gd. Missions and the TEST menu page: tests/test_interior_gameplay_missions.gd.
## Run: tools/test.sh tests/test_interior_gameplay.gd

const SPEED_UP := 4
const TICK_RATE := 60 * SPEED_UP
const TMP := "user://test_interiors_save.cfg"

var host: Node
var main: Node
var p: Player
var city: City
var ig: InteriorGameplay
var em: EnemyManager


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func press_use() -> void:
	Input.action_press(&"interact")
	await frames(2)
	Input.action_release(&"interact")
	await frames(1)


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	Engine.physics_ticks_per_second = TICK_RATE
	Engine.time_scale = float(SPEED_UP)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	_data()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	p = Game.player as Player
	city = Game.world as City
	em = Game.enemies as EnemyManager
	ig = InteriorGameplay.instance
	TestLib.check(ig != null and ig.is_inside_tree(), "main.tscn composes the InteriorGameplay node")
	if ig == null or city == null or p == null:
		_end()
		return
	_doors()
	await _prompt_and_enter()
	await _state_through_the_door()
	await _inside_world()
	await _actors_per_type()
	await _contract_blocks_doors()
	await _followers_and_street()
	await _hud_and_minimap()
	await _save_and_respawn()
	await _stub_room()
	await _teardown()
	_end()


func _end() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Sfx.muted = false


# --- pure data ----------------------------------------------------------------------------------------------------------

func _data() -> void:
	var longest := 0
	var bad_speaker := 0
	for pair: Array in InteriorData.all_lines():
		longest = maxi(longest, str(pair[1]).length())
		if not StoryData.SPEAKERS.has(str(pair[0])):
			bad_speaker += 1
	TestLib.check(longest <= StoryData.LINE_MAX, "every interior radio line fits a phone screen (longest %d of %d)" % [longest, StoryData.LINE_MAX])
	TestLib.check(bad_speaker == 0, "every interior radio line has a known speaker")
	var ok := true
	for t: StringName in InteriorData.TYPES:
		for f in 3:
			var n := InteriorData.actor_total(InteriorData.plan(t, f))
			if n > InteriorData.ACTOR_CAP or n < InteriorData.ACTOR_MIN:
				ok = false
				printerr("plan out of range: ", t, " followers ", f, " -> ", n)
	TestLib.check(ok, "every interior plan keeps 3..5 actors, with 0, 1 or 2 followers")
	for t: StringName in InteriorData.VENDOR_TYPES:
		TestLib.check((InteriorData.STOCK[t] as Array).size() >= 2, "vendor %s has stock" % t)
	TestLib.check(InteriorData.TYPES.size() == 16 and InteriorData.WEIGHTS.size() == 16 and InteriorData.TYPES.size() == InteriorKinds.TYPES.size(), "sixteen interior types (ten classic + six kit) with weights")
	var wsum := 0.0
	for w in InteriorData.WEIGHTS:
		wsum += w
	TestLib.check(absf(wsum - 1.0) < 0.001, "door weights sum to 1")
	var names := {}
	for i in 40:
		names[InteriorData.door_name(&"bar", i)] = true
	TestLib.check(names.size() > 8, "door names vary (%d different in 40)" % names.size())
	var r := InteriorData.reward(&"hostage", 0, 0)
	var r2 := InteriorData.reward(&"hostage", 4, 50)
	TestLib.check(int(r["credits"]) > 0 and int(r2["credits"]) > int(r["credits"]), "rewards grow with the sector and reputation")


# --- doors -------------------------------------------------------------------------------------------------------------

func _doors() -> void:
	var doors := city.doors
	var lots := city.layout.lots.size()
	TestLib.check(doors.size() == lots, "every lot has a door (%d of %d)" % [doors.size(), lots])
	var types := {}
	var near_spawn := false
	var on_walk := 0
	var unique := {}
	for d in doors:
		types[d["type"]] = true
		unique[d["id"]] = true
		var pos: Vector3 = d["pos"]
		if Vector2(pos.x, pos.z).distance_to(Vector2(Game.SPAWN.x, Game.SPAWN.z)) < 100.0:
			near_spawn = true
		if not city.is_inside_building(Vector3(pos.x, 1.0, pos.z)) and not CityLayout.on_road(pos.x, pos.z, 0.0) and absf(pos.x) < 330.0 and absf(pos.z) < 330.0:
			on_walk += 1
	TestLib.check(types.size() == InteriorData.TYPES.size(), "every interior type has a door (%d types)" % types.size())
	TestLib.check(near_spawn, "a door within 100 m of the spawn")
	TestLib.check(on_walk == doors.size(), "every door front is on the sidewalk, not inside a building (%d of %d)" % [on_walk, doors.size()])
	TestLib.check(unique.size() == doors.size(), "door ids are unique")
	var again := CityDoorsProbe.compute(city)
	var same := again.size() == doors.size()
	for i in mini(again.size(), doors.size()):
		same = same and again[i]["id"] == doors[i]["id"] and again[i]["type"] == doors[i]["type"] and (again[i]["pos"] as Vector3).is_equal_approx(doors[i]["pos"])
	TestLib.check(same, "door placement is deterministic")
	TestLib.check(ig.markers.mmi != null and ig.markers.count == doors.size() and ig.markers.mmi.multimesh.instance_count == doors.size(), "ONE MultiMesh holds every door marker")
	var n_mmi := 0
	for c in ig.markers.get_children():
		if c is MultiMeshInstance3D:
			n_mmi += 1
	TestLib.check(n_mmi == 1, "the door markers are one draw call")


# --- prompt, enter, exit --------------------------------------------------------------------------------------------------

func _prompt_and_enter() -> void:
	p.teleport_to(Game.SPAWN)
	await frames(8)
	TestLib.check(InteriorGameplay.prompt == "", "no prompt away from every door")
	var d := ig.doors_of(&"weapons", p.global_position)[0]
	var front: Vector3 = d["pos"]
	p.teleport_to(front + Vector3(0.0, 0.1, 0.0))
	await frames(20)
	TestLib.check(InteriorGameplay.prompt.begins_with("ENTER"), "standing at a door shows the ENTER prompt ('%s')" % InteriorGameplay.prompt)
	var hud := _find_hud()
	if hud != null:
		TestLib.check(hud.hint_text().find("ENTER") >= 0, "the HUD shows the door prompt ('%s')" % hud.hint_text())
	p.teleport_to(front + Vector3(0.0, 0.1, 0.0) + (d["normal"] as Vector3) * 6.0)
	await frames(20)
	TestLib.check(InteriorGameplay.prompt == "", "six metres from the door the prompt is gone")
	p.teleport_to(front + Vector3(0.0, 0.1, 0.0))
	await frames(20)
	var fades := ig.enter_count
	await press_use()
	TestLib.check(ig.is_fading(), "USE starts the fade")
	var guard := 0
	while ig.busy and guard < 200:
		await frames(2)
		guard += 1
	TestLib.check(InteriorGameplay.active and ig.interior != null and ig.enter_count == fades + 1, "the fade ends inside the interior")
	TestLib.check(not ig.is_fading() and not ig.busy, "the transition is over")
	TestLib.check(ig.interior.get("type") == &"weapons", "the door's type decides the interior")


func _state_through_the_door() -> void:
	# leave, set a state, go in again: hp, energy, ammo, weapon and heat must all come through
	ig.leave(true)
	await frames(3)
	TestLib.check(not InteriorGameplay.active and is_instance_valid(city) and city.visible, "leaving shows the city again")
	(Game.progress as Progress).grant_weapon(&"scatter")
	p.weapon.switch_to(&"scatter", true)
	await frames(3)
	p.hp = 61.0
	p.energy = 47.0
	p.weapon.ammo = 4
	Game.heat = 2.0
	Game.quiet = 100.0
	var d := ig.doors_of(&"clinic", p.global_position)[0]
	p.teleport_to((d["pos"] as Vector3) + Vector3(0.0, 0.1, 0.0))
	await frames(5)
	TestLib.check(ig.enter(d, true), "enter a clinic")
	await frames(60)
	TestLib.check(is_equal_approx(p.hp, 61.0) or p.hp >= 61.0, "hp carries through the door (%.1f)" % p.hp)
	TestLib.check(p.weapon.current == &"scatter" and p.weapon.ammo == 4, "weapon and ammo carry through the door (%s, %d)" % [p.weapon.current, p.weapon.ammo])
	TestLib.check(Game.heat >= 1.5, "heat carries inside, only the wanted v2 interior hide rate bleeds it (%.3f after 1 s with quiet = 100)" % Game.heat)
	TestLib.check(p.energy >= 47.0, "energy carries through the door (%.1f)" % p.energy)
	var room: Node3D = ig.interior
	var b: Rect2 = room.get("bounds")
	TestLib.check(b.has_point(Vector2(p.global_position.x, p.global_position.z)) and absf(p.global_position.y) < 0.6, "the player stands inside the room (%s)" % p.global_position)
	var fwd := -Vector3(sin(p.yaw), 0.0, cos(p.yaw))
	var into: Vector3 = (room.get("bounds") as Rect2).get_center().x * Vector3.RIGHT + Vector3(0.0, 0.0, (room.get("bounds") as Rect2).get_center().y) - p.global_position
	TestLib.check(fwd.dot(into.normalized()) > 0.3, "the player faces into the room")
	ig.leave(true)
	await frames(5)
	TestLib.check((p.global_position - (d["pos"] as Vector3)).length() < 3.0, "exit puts the player at the street door (%s)" % p.global_position)
	TestLib.check(Game.heat >= 1.4 and p.hp >= 61.0, "heat and hp survive the way out too")
	Game.heat = 0.0


func _inside_world() -> void:
	var d := ig.doors_of(&"bar", p.global_position)[0]
	var rain_before: float = Game.atmosphere.get("rain_target")
	TestLib.check(ig.enter(d, true), "enter a bar")
	await frames(10)
	TestLib.check(not city.visible, "the city is hidden inside (no draw calls for it)")
	TestLib.check(float(Game.atmosphere.get("rain_target")) == 0.0, "rain is off inside")
	var vm := Game.vehicles
	var hid := 0
	for v in vm.list:
		if not v.visible:
			hid += 1
	TestLib.check(hid == vm.list.size() and not vm.is_physics_processing(), "cars are hidden and frozen inside (%d of %d)" % [hid, vm.list.size()])
	TestLib.check(InteriorGameplay.blocks(Vector3(p.global_position.x, 1.0, p.global_position.z)) == false, "the arrival point is free")
	var wall: Rect2 = (ig.interior.get("wall_rects") as Array)[0]
	TestLib.check(InteriorGameplay.blocks(Vector3(wall.get_center().x, 1.0, wall.get_center().y)) and InteriorSpace.active, "a wall rect blocks civilian steps and the generator's InteriorSpace is registered")
	TestLib.check(InteriorGameplay.blocks(Vector3(ig.interior.get("bounds").position.x - 3.0, 1.0, 0.0)), "outside the interior bounds is blocked")
	var room: Node3D = ig.interior
	var meshes := 0
	var lights := 0
	for n in room.find_children("*", "", true, false):
		if n is MeshInstance3D:
			meshes += 1
		if n is Light3D:
			lights += 1
	TestLib.check(meshes <= 60 and lights <= 6, "the interior stays within its draw budget (%d meshes, %d lights)" % [meshes, lights])
	ig.leave(true)
	await frames(5)
	TestLib.check(city.visible and is_equal_approx(float(Game.atmosphere.get("rain_target")), rain_before), "city, cars and rain come back on exit")
	var shown := 0
	for v in vm.list:
		if v.visible:
			shown += 1
	TestLib.check(vm.is_physics_processing(), "the vehicle manager runs again (%d visible cars)" % shown)
	TestLib.check(not InteriorGameplay.blocks(Vector3(wall.get_center().x, 1.0, wall.get_center().y)) and not city.is_inside_building(Vector3(wall.get_center().x, 1.0, wall.get_center().y)) and not InteriorSpace.active, "no phantom walls outside")


func _contract_blocks_doors() -> void:
	var k: Contracts = (Game.missions as Missions).contracts
	var d := ig.doors_of(&"bar", p.global_position)[0]
	p.teleport_to((d["pos"] as Vector3) + Vector3(0.0, 0.1, 0.0))
	await frames(3)
	k.offer(&"drones", p.global_position + Vector3(3.0, 0.0, 3.0))
	k.accept()
	await frames(10)
	var why := ig.block_reason()
	TestLib.check(k.foes_alive() == 0 or why == "FINISH THE CONTRACT FIRST", "doors stay shut while a contract's enemies are alive ('%s', %d foes)" % [why, k.foes_alive()])
	k.abandon()
	em.clear()
	await frames(10)
	TestLib.check(ig.block_reason() == "", "doors open again when the contract ends")


func _actors_per_type() -> void:
	var all_ok := true
	Game.heat = 0.0
	for t: StringName in InteriorData.TYPES:
		em.clear()
		Game.heat = 0.0
		var dl := ig.doors_of(t, p.global_position)
		var d: Dictionary = dl[0]
		p.teleport_to((d["pos"] as Vector3) + Vector3(0.0, 0.1, 0.0))
		await frames(3)
		if not ig.enter(d, true):
			TestLib.check(false, "enter %s" % t)
			continue
		var fresh := ig.actors
		var stealth_ok := true
		for g in fresh.guards:
			stealth_ok = stealth_ok and g.aware_dist < Drone.AWARE_DIST and not g.aware
		TestLib.check(stealth_ok, "interior guards start stealthy in %s (sight %.1f m instead of %.0f)" % [t, InteriorActors.STEALTH_DIST, Drone.AWARE_DIST])
		await frames(30)
		var a := ig.actors
		var n := a.total()
		var plan := InteriorData.plan(t)
		var vend := a.vendor != null and a.vendor.active
		var fine := n >= InteriorData.ACTOR_MIN and n <= InteriorData.ACTOR_CAP and vend == InteriorData.has_vendor(t)
		var guards_ok := a.guards.size() == int(plan["guards"])
		var civ_ok := a.civilians.size() == int(plan["civilians"])
		var inside_ok := true
		var b: Rect2 = ig.interior.get("bounds")
		for g in a.guards:
			if g.type != &"operative" or not b.has_point(Vector2(g.global_position.x, g.global_position.z)) or absf(g.global_position.y) > 1.0:
				inside_ok = false
		for c in a.civilians:
			if not b.has_point(Vector2(c.global_position.x, c.global_position.z)):
				inside_ok = false
		if not (fine and guards_ok and civ_ok and inside_ok):
			all_ok = false
			printerr("actors wrong in ", t, ": total ", n, " vendor ", vend, " guards ", a.guards.size(), "/", plan["guards"], " civ ", a.civilians.size(), "/", plan["civilians"], " inside ", inside_ok)
		TestLib.check(ig.last_radio != "", "an interior radio line for %s" % t)
		ig.leave(true)
		await frames(3)
	TestLib.check(all_ok, "every interior type holds 3..5 actors in the planned mix, inside its walls")
	TestLib.check(em.alive_count() <= em.cap(), "the enemy cap holds")


func _followers_and_street() -> void:
	# street enemies are stored while inside and put back after; an aware hunter at the door follows in
	Game.heat = 0.0
	em.clear()
	var d := ig.doors_of(&"weapons", p.global_position)[0]
	var front: Vector3 = d["pos"]
	p.teleport_to(front + Vector3(0.0, 0.1, 0.0))
	await frames(5)
	var far_at: Vector3 = front + (Vector3(0.0, 0.0, 0.0) - front).normalized() * 60.0          # towards the city centre: always inside the walls
	var far := em.spawn(&"operative", far_at, false)
	var near := em.spawn(&"operative", front + (d["normal"] as Vector3) * 9.0, true)
	TestLib.check(far != null and near != null, "two street enemies")
	var before := em.alive_count()
	Game.heat = 1.5
	await frames(3)
	TestLib.check(ig.enter(d, true), "enter with hunters about")
	await frames(2)
	TestLib.check(em.alive_count() <= 3, "the street's enemies are stored: only the interior's actors are alive (%d)" % em.alive_count())
	await frames(130)
	TestLib.check(ig.actors.followers.size() == 1 and ig.actors.followers[0].aware, "the aware hunter followed through the door")
	TestLib.check(ig.actors.total() <= InteriorData.ACTOR_CAP + 2, "followers keep the actor cap (%d)" % ig.actors.total())
	var heat_lines: Array[String] = []
	for pair: Array in InteriorData.RADIO[&"heat"]:
		heat_lines.append(str(pair[1]))
	TestLib.check(heat_lines.has(ig.last_radio), "the heat radio line plays when hunters follow ('%s')" % ig.last_radio)
	ig.leave(true)
	await frames(4)
	var restored := 0
	for e in em.list:
		if e.active and not e.dead and e.global_position.distance_to(far_at) < 3.0:
			restored += 1
	TestLib.check(restored == 1, "the far street enemy is put back where it stood")
	TestLib.check(em.alive_count() >= 1 and before == 2, "the street is repopulated after the exit (%d alive: the stored one, survivors that followed out, new reinforcements)" % em.alive_count())
	Game.heat = 0.0
	em.clear()


func _find_hud() -> Hud:
	for n in main.find_children("*", "Hud", true, false):
		return n as Hud
	return null


func _hud_and_minimap() -> void:
	var d := ig.doors_of(&"club", p.global_position)[0]
	p.teleport_to((d["pos"] as Vector3) + Vector3(0.0, 0.1, 0.0))
	await frames(3)
	ig.enter(d, true)
	await frames(40)
	TestLib.check(InteriorGameplay.hud_line != "", "the HUD priority line shows the interior mission ('%s')" % InteriorGameplay.hud_line)
	var hud := _find_hud()
	if hud != null:
		TestLib.check(hud.layers_consistent(), "HUD layers consistent inside")
		await frames(20)
		var mm: Minimap = hud.minimap
		if mm != null:
			mm.queue_redraw()
			await frames(6)
			TestLib.check(InteriorMinimap.floors_drawn >= 1 and InteriorMinimap.walls_drawn >= 3, "the minimap draws the interior layout (%d floors, %d walls)" % [InteriorMinimap.floors_drawn, InteriorMinimap.walls_drawn])
			TestLib.check(InteriorMinimap.markers_drawn >= 2, "the minimap draws the exit, actors and mission markers (%d)" % InteriorMinimap.markers_drawn)
	var mk := ig.minimap_markers()
	TestLib.check(mk.size() >= 3, "minimap markers exist (%d)" % mk.size())
	TestLib.check(Game.quiet == 0.0, "the observers' quiet clock is held at zero inside")
	ig.leave(true)
	await frames(3)
	TestLib.check(InteriorGameplay.hud_line == "" and not InteriorGameplay.prompt.begins_with("LEAVE"), "mission line and inside prompts clear on exit ('%s')" % InteriorGameplay.prompt)
	if hud != null:
		TestLib.check(hud.layers_consistent(), "HUD layers consistent after leaving")


func _save_and_respawn() -> void:
	ig.autosave = true
	ig.save_path = TMP
	var d := ig.doors_of(&"tech", p.global_position)[0]
	p.teleport_to((d["pos"] as Vector3) + Vector3(0.0, 0.1, 0.0))
	await frames(3)
	ig.done[777] = true
	ig.hinted[778] = true
	ig.enter(d, true)
	await frames(5)
	TestLib.check(FileAccess.file_exists(TMP), "entering an interior writes the interior save")
	var ig2 := InteriorGameplay.new()
	ig2.save_path = TMP
	TestLib.check(ig2.load_state() and ig2.saved_inside() and ig2.done.has(777) and ig2.hinted.has(778), "the save remembers 'inside', finished missions and hints")
	ig2.free()
	# quit to title: the city comes back, the save still says 'inside', and a resume goes back to the same room
	Game.state = &"menu"
	await frames(3)
	TestLib.check(not InteriorGameplay.active and city.visible, "the title screen shows the city (the interior is closed)")
	TestLib.check(ig.saved_inside(), "the last save still says inside")
	Game.state = &"play"
	await frames(3)
	TestLib.check(ig.resume_saved() and InteriorGameplay.active and int(ig.door["id"]) == int(d["id"]), "CONTINUE resumes in the saved interior")
	# the title's CONTINUE (Progress.continue_game) takes the player back into the saved interior
	ig.leave(true)
	await frames(3)
	ig.enter(d, true)
	await frames(5)
	var prog := Game.progress as Progress
	prog.path = "user://test_interiors_progress.cfg"
	prog.autosave_enabled = false
	prog.save_file()
	Game.state = &"menu"
	await frames(3)
	TestLib.check(not InteriorGameplay.active and ig.saved_inside(), "at the title the interior is closed but the save says inside")
	TestLib.check(prog.continue_game(), "CONTINUE starts the run")
	await frames(2)
	TestLib.check(prog.continued and not InteriorGameplay.active, "the run starts on the street")
	await frames(60)
	TestLib.check(InteriorGameplay.active and int(ig.door["id"]) == int(d["id"]), "CONTINUE resumes inside the saved interior")
	ig.leave(true)
	await frames(3)
	# a NEW game (not a continue) forgets it
	ig.enter(d, true)
	await frames(5)
	Game.state = &"menu"
	await frames(3)
	Game.start_new_game()
	await frames(80)
	TestLib.check(not InteriorGameplay.active and not prog.continued, "a new game from the title starts on the street")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_interiors_progress.cfg"))
	ig.enter(d, true)
	await frames(5)
	# death inside: the respawn puts the player at the street door, safe
	await frames(5)
	Game.die()
	await frames(3)
	TestLib.check(InteriorGameplay.active, "the interior stays up on the death screen")
	Game.do_respawn()
	await frames(4)
	TestLib.check(not InteriorGameplay.active and city.visible and (p.global_position - (d["pos"] as Vector3)).length() < 3.0, "respawn after dying inside puts the player at the street door (%s)" % p.global_position)
	TestLib.check(Game.is_playing() and Game.heat == 0.0, "playing again with heat 0")
	ig.autosave = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	# new game inside an interior drops the interior and the finished missions
	ig.done[5] = true
	ig.enter(d, true)
	await frames(3)
	Game.start_new_game()
	await frames(4)
	TestLib.check(not InteriorGameplay.active and city.visible and ig.done.is_empty(), "a new game closes the interior and forgets finished interior missions")


## The fallback room (used when the generator is missing or returns something invalid) honours the same interface.
func _stub_room() -> void:
	ig.use_generator = false
	var d := ig.doors_of(&"bar", p.global_position)[0]
	p.teleport_to((d["pos"] as Vector3) + Vector3(0.0, 0.1, 0.0))
	await frames(3)
	TestLib.check(ig.enter(d, true) and ig.interior is InteriorStub, "the stub room stands in when the generator is off")
	await frames(20)
	TestLib.check(ig.actors.total() >= 3 and ig.actors.vendor != null, "the stub room is populated like a real one")
	ig.leave(true)
	await frames(3)
	ig.use_generator = true
	TestLib.check(ig.enter(d, true) and not (ig.interior is InteriorStub), "the generator's room is used by default")
	ig.leave(true)
	await frames(3)


func _teardown() -> void:
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var d := ig.doors_of(&"bar", p.global_position)[0]
	for i in 6:
		ig.enter(d, true)
		await frames(4)
		ig.leave(true)
		await frames(4)
	await frames(10)
	var after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	TestLib.check(after - nodes_before <= 12, "repeated enter / exit does not leak nodes (%d -> %d)" % [nodes_before, after])
	main.queue_free()
	await frames(5)
	TestLib.check(not InteriorGameplay.active and InteriorGameplay.instance == null, "freeing the game clears the interior statics")


## Runs the world module's door placement again from its own data, to prove it is deterministic.
class CityDoorsProbe extends RefCounted:
	static func compute(c: City) -> Array[Dictionary]:
		return (load("res://scripts/world/city_doors.gd") as GDScript).compute(c.layout, c.building_data)
