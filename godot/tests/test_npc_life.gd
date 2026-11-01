extends RefCounted
## NPC life tests (headless): schedules (shop fronts / bus stops and lingering), promotion of the nearest 12, reactions to gunfire / blasts / heat / fast cars,
## patrol calls raising heat a little, proximity dialogue through Game.say, pause behaviour, no growth. Run: tools/test.sh tests/test_npc_life.gd

const Crowd := preload("res://scripts/ambient/ambient_crowd.gd")
const Npc := preload("res://scripts/npc/npc_life.gd")
const Lines := preload("res://scripts/npc/npc_lines.gd")
const StoryData := preload("res://scripts/story/story_data.gd")
const Fixture := preload("res://tests/ambient_fixture.gd")

var _said: Array[String] = []


func _on_message(text: String, _s: float) -> void:
	_said.append(text)


func run(host: Node) -> void:
	var city := (load("res://scenes/world.tscn") as PackedScene).instantiate() as City
	host.add_child(city)
	await TestLib.frames(host, 3)
	var amb: Node3D = city.ambient
	var player := Fixture.new()
	host.add_child(player)
	player.global_position = Vector3(-30.0, 0.0, 4.0)
	Game.player = player
	var prev_state := Game.state
	var prev_heat: float = Game.heat
	Game.state = &"play"
	Game.message.connect(_on_message)
	amb.simulate = false                       # the test drives the crowd by hand: deterministic
	var c: RefCounted = amb.crowd
	var n: RefCounted = amb.npc
	amb.reset()
	for k in 40:
		c.step(0.1, player.global_position)

	_test_lines()
	_test_schedule(c, n, player)
	_test_promotion(c, n, player)
	_test_gunfire_and_calls(c, n, player)
	_test_blast(c, n, player)
	_test_heat(c, n, player)
	_test_vehicle(c, n, player)
	_test_dialogue(c, n, player)
	await _test_pause(host, amb, n)
	_test_budget(c, n, amb)
	_test_shader_states(c, player)

	Game.message.disconnect(_on_message)
	Game.heat = prev_heat
	Game.state = prev_state
	Game.player = null
	player.queue_free()
	city.queue_free()
	await TestLib.frames(host, 2)


func _test_lines() -> void:
	var longest := 0
	var pools := 0
	for pool: Array in Lines.all_pools():
		pools += 1
		TestLib.check(pool.size() >= 3, "every bark pool has at least 3 lines")
		for l: String in pool:
			longest = maxi(longest, (Lines.PREFIX + l).length())
	TestLib.check(longest <= StoryData.LINE_MAX, "every bark fits the HUD line limit (longest %d of %d)" % [longest, StoryData.LINE_MAX])
	var r := Lines.rumours()
	TestLib.check(r.size() > Lines.RUMOUR.size() and r.has(StoryData.TAGLINE), "rumours are seeded from the story data (%d lines, tagline included)" % r.size())
	for l in r:
		TestLib.check((Lines.PREFIX + l).length() <= StoryData.LINE_MAX, "rumour fits: %s" % l.left(24))


func _test_schedule(c: RefCounted, n: RefCounted, player: Node3D) -> void:
	var kinds := {}
	for k in 40:
		kinds[Crowd.stop_kind(k & 1, -320.0 + 80.0 * float(k % 9) + 11.3, k)] = true
	TestLib.check(kinds.has(Crowd.STOP_SHOP) and kinds.has(Crowd.STOP_BUS) and kinds.has(0), "the street has shop fronts, bus stops and plain pavement")
	TestLib.check(Crowd.stop_kind(1, 68.7, 5) == Crowd.stop_kind(1, 68.7, 5), "a stop keeps its kind (pure hash)")
	var with_goal := 0
	for i in c.count:
		if c.is_alive(i) and c.goal_kind(i) != 0:
			with_goal += 1
	TestLib.check(with_goal >= c.count / 4, "people walk toward a shop or bus stop (%d of %d have a goal)" % [with_goal, c.count])
	# long walk: stops are made, lingerers face a window / the road (not along the walk) and stand still, and everybody walks on afterwards
	var base: int = c.lingers_total()
	var seen_linger := false
	var faced := false
	var still := true
	var resumed := false
	var tracked := -1
	var track_pos := Vector3.ZERO
	for k in 900:
		c.step(0.1, player.global_position)
		for i in c.count:
			if c.state_of(i) == &"linger":
				seen_linger = true
				if c._look[i] in [Crowd.LOOK_LAT_POS, Crowd.LOOK_LAT_NEG]:
					faced = true
				if tracked < 0:
					tracked = i
					track_pos = c.person_position(i)
		if tracked >= 0:
			if c.state_of(tracked) == &"linger":
				still = still and c.person_position(tracked).distance_to(track_pos) < 0.01
			elif c.state_of(tracked) == &"walk":
				resumed = true
				tracked = -2 if resumed else tracked
	TestLib.check(c.lingers_total() > base + 3, "people stop at shops and bus stops (%d stops in 90 s)" % (c.lingers_total() - base))
	TestLib.check(seen_linger and faced, "a lingerer faces the window or the road")
	TestLib.check(still, "a lingerer stands still")
	TestLib.check(resumed, "a lingerer walks on after the stay")
	TestLib.check(c.alive_count() >= c.count - 2, "the street stays populated")


func _test_promotion(c: RefCounted, n: RefCounted, player: Node3D) -> void:
	n._promote(player.global_position)
	TestLib.check(n.actors.size() > 0 and n.actors.size() <= Npc.PROMOTE_MAX, "at most %d people are promoted to actors (%d)" % [Npc.PROMOTE_MAX, n.actors.size()])
	var sorted_ok := true
	for k in range(1, n.actors.size()):
		if n._dist[n.actors[k]] < n._dist[n.actors[k - 1]]:
			sorted_ok = false
	TestLib.check(sorted_ok, "actors are ordered nearest first")
	var nearest_ok := true
	if n.actors.size() == Npc.PROMOTE_MAX:
		var worst: float = n._dist[n.actors[n.actors.size() - 1]]
		for i in c.count:
			if c.is_alive(i) and not n.is_actor(i):
				var p: Vector3 = c.person_position(i)
				var d := (p.x - player.global_position.x) * (p.x - player.global_position.x) + (p.z - player.global_position.z) * (p.z - player.global_position.z)
				if d < worst - 0.01:
					nearest_ok = false
	TestLib.check(nearest_ok, "nobody nearer than the farthest actor is left out")


func _stand_among(c: RefCounted, player: Node3D) -> void:
	var i := 0
	while i < c.count and not c.is_alive(i):
		i += 1
	player.global_position = c.person_position(i) + Vector3(1.5, 0.0, 0.0)


func _test_gunfire_and_calls(c: RefCounted, n: RefCounted, player: Node3D) -> void:
	_stand_among(c, player)
	Game.heat = 0.0
	var heat0: float = Game.heat
	var fled0: int = c.fled_total()
	var react0: int = n.reactions
	var calls0: int = n.calls
	for k in 40:
		n.on_shot(player.global_position, player.global_position)
		n._call_cd = 0.0 if k % 4 == 0 else n._call_cd
		for j in 3:
			c.step(0.1, player.global_position)
			n.step(0.1, player.global_position)
	TestLib.check(c.fled_total() > fled0, "gunfire sends citizens running (%d)" % (c.fled_total() - fled0))
	TestLib.check(n.reactions > react0, "some close citizens cower or point instead (%d)" % (n.reactions - react0))
	var cowering := 0
	for i in c.count:
		if c.is_alive(i) and c.is_cowering(i):
			cowering += 1
	TestLib.check(cowering > 0 or n.reactions > 0, "cowering people exist (%d now)" % cowering)
	TestLib.check(n.calls > calls0, "a citizen calls the patrol (%d calls)" % (n.calls - calls0))
	TestLib.check(Game.heat > heat0 + 0.05, "a patrol call raises heat (%.2f)" % Game.heat)
	TestLib.check(Game.heat <= Npc.CALL_HEAT_CAP + 0.001, "calls never push heat above %.1f (%.2f)" % [Npc.CALL_HEAT_CAP, Game.heat])
	var heat1: float = Game.heat
	n._call_cd = 5.0
	n._try_call(player.global_position)
	TestLib.check(Game.heat == heat1, "calls respect their cooldown")
	Game.heat = 4.0
	n._call_cd = 0.0
	var calls1: int = n.calls
	for k in 60:
		n._call_cd = 0.0
		n._try_call(player.global_position)
	TestLib.check(Game.heat == 4.0 and n.calls > calls1, "a hunted player is not made hotter by calls")
	Game.heat = 0.0
	n._call_cd = 0.0
	# a shot far from everybody scares nobody
	var far := Vector3(5000.0, 0.0, 5000.0)
	for k in 20:
		c.step(0.5, player.global_position)
	var fled1: int = c.fled_total()
	c.on_shot(far)
	TestLib.check(c.fled_total() == fled1, "a shot far away scares nobody")


func _test_blast(c: RefCounted, n: RefCounted, player: Node3D) -> void:
	for k in 60:
		c.step(0.2, player.global_position)
	var fled0: int = c.fled_total()
	var blasts0: int = n.blasts_seen
	var blast_at: Vector3 = player.global_position + Vector3(12.0, 0.0, 0.0)
	n.on_blast(blast_at, 4.0, player.global_position)
	TestLib.check(n.blasts_seen == blasts0 + 1 and c.fled_total() > fled0, "an explosion scatters the street (%d ran)" % (c.fled_total() - fled0))
	# a real explosion from the FX pool is noticed by the poll
	if FX.explosions != null and is_instance_valid(FX.explosions):
		n._sync_serial()
		var b1: int = n.blasts_seen
		FX.explosions.play(player.global_position + Vector3(6.0, 0.0, 0.0), 5.0, Color(1.0, 0.5, 0.2))
		n._poll_blasts(player.global_position)
		TestLib.check(n.blasts_seen == b1 + 1, "a pooled explosion is noticed once")
		n._poll_blasts(player.global_position)
		TestLib.check(n.blasts_seen == b1 + 1, "the same explosion does not scare twice")
		FX.explosions.clear()


func _test_heat(c: RefCounted, n: RefCounted, player: Node3D) -> void:
	for k in 60:
		c.step(0.2, player.global_position)
	Game.heat = 0.0
	n._last_heat = 0.0
	var fled0: int = c.fled_total()
	Game.heat = 1.2
	n._poll_heat(player.global_position)
	TestLib.check(c.fled_total() > fled0, "the street scatters when heat rises a star (%d ran)" % (c.fled_total() - fled0))
	var fled1: int = c.fled_total()
	Game.heat = 1.6
	n._poll_heat(player.global_position)
	TestLib.check(c.fled_total() == fled1, "heat within the same star does not scare again")
	Game.heat = 0.0
	n._last_heat = 0.0


func _test_vehicle(c: RefCounted, n: RefCounted, player: Node3D) -> void:
	for k in 60:
		c.step(0.2, player.global_position)
	_stand_among(c, player)
	for k in 5:
		c.step(0.2, player.global_position)
	n._promote(player.global_position)
	var target := -1
	for i in n.actors:
		if not c.is_fleeing(i):
			target = i
			break
	TestLib.check(target >= 0, "an actor is available for the car test")
	if target < 0:
		return
	var src := GDScript.new()
	src.source_code = "extends Node3D\nvar speed := 0.0\n"
	src.reload()
	var car := Node3D.new()
	car.set_script(src)
	player.add_child(car)
	car.global_position = c.person_position(target) + Vector3(2.0, 0.0, 0.0)
	var vm := Node.new()
	var vs := GDScript.new()
	vs.source_code = "extends Node\nvar list: Array = []\nvar driven = null\n"
	vs.reload()
	vm.set_script(vs)
	vm.set("list", [car])
	var prev_vm: Node = Game.vehicles
	Game.vehicles = vm
	car.set("speed", 3.0)
	n._scan_vehicles()
	TestLib.check(not c.is_fleeing(target), "a slow car scares nobody")
	car.set("speed", 14.0)
	var s0: int = n.car_scares
	n._scan_vehicles()
	TestLib.check(c.is_fleeing(target) and n.car_scares > s0, "a fast car makes the person in its way jump aside")
	car.global_position = Vector3(4000.0, 0.0, 4000.0)
	var s1: int = n.car_scares
	n._scan_vehicles()
	TestLib.check(n.car_scares == s1, "a fast car far away scares nobody")
	Game.vehicles = prev_vm
	vm.free()
	car.queue_free()


func _test_dialogue(c: RefCounted, n: RefCounted, player: Node3D) -> void:
	Game.heat = 0.0
	for k in 80:
		c.step(0.2, player.global_position)
	n.reset()
	n._promote(player.global_position)
	TestLib.check(n.actors.size() > 0, "actors exist near the player")
	var i: int = n.actors[0]
	player.global_position = c.person_position(i) + Vector3(1.2, 0.0, 0.0)
	c.cower_person(i, 0.0)
	c._flee[i] = 0.0
	n._promote(player.global_position)
	_said.clear()
	n._talk_cd = 0.0
	n._talk(player.global_position)
	TestLib.check(_said.size() == 1 and _said[0].begins_with(Lines.PREFIX) and _said[0].length() <= StoryData.LINE_MAX, "standing next to a citizen shows one bark through Game.say: %s" % (_said[0] if _said.size() > 0 else "-"))
	var first := _said.size()
	n._talk(player.global_position)
	TestLib.check(_said.size() == first, "the prompt has a cooldown")
	n._talk_cd = 0.0
	n._talk(player.global_position)
	TestLib.check(_said.size() == first, "the same person does not repeat themselves at once")
	TestLib.check(c.state_of(i) == &"linger", "the person turns to listen")
	# wanted: fear lines
	Game.heat = 3.5
	TestLib.check(Lines.WANTED.has(n.line_for(i).trim_prefix(Lines.PREFIX)), "a wanted player gets fear lines")
	Game.heat = 0.0
	# a cowering person says a scared line
	c.cower_person(i, 5.0)
	TestLib.check(Lines.SCARED.has(n.line_for(i).trim_prefix(Lines.PREFIX)), "a cowering person begs")
	# nobody speaks to a player who is far from everybody, or while driving
	var far_player := Vector3(4000.0, 0.0, 4000.0)
	n._promote(far_player)
	_said.clear()
	n._talk_cd = 0.0
	n._talk(far_player)
	TestLib.check(_said.is_empty() and n.actors.is_empty(), "nobody talks to a player who is out of range")
	# driving: no prompt
	var vm := Node.new()
	var vs := GDScript.new()
	vs.source_code = "extends Node\nvar list: Array = []\nvar driven = 1\n"
	vs.reload()
	vm.set_script(vs)
	var prev_vm: Node = Game.vehicles
	Game.vehicles = vm
	n._promote(player.global_position)
	n._talked.fill(-1000.0)
	n._talk_cd = 0.0
	c._cower[i] = 0.0
	n._talk(player.global_position)
	TestLib.check(_said.is_empty(), "no prompt while driving")
	Game.vehicles = prev_vm
	vm.free()


func _test_pause(host: Node, amb: Node3D, n: RefCounted) -> void:
	amb.simulate = true
	Game.state = &"paused"
	var t0: float = n.clock
	await TestLib.frames(host, 6)
	TestLib.check(n.clock == t0, "paused: nothing in NPC life advances")
	Game.state = &"play"
	await TestLib.frames(host, 15)
	TestLib.check(n.clock > t0, "playing: NPC life runs with the ambient city")
	amb.simulate = false


func _test_budget(c: RefCounted, n: RefCounted, amb: Node3D) -> void:
	TestLib.check(Npc.PROMOTE_MAX <= 12, "no more than 12 actors")
	TestLib.check(c.mm.instance_count == Crowd.BUILT and c.mm_near.instance_count == Crowd.NEAR_CAP, "the crowd is still two MultiMeshes (%d far, %d near slots)" % [c.mm.instance_count, c.mm_near.instance_count])
	var s: Dictionary = amb.stats()
	TestLib.check(s.has("npc") and s["npc"]["actors"] <= 12, "stats report the NPC layer")
	var sizes := [n.actors.size(), c.count]
	for k in 200:
		c.step(0.1, Vector3(-30.0, 0.0, 4.0))
		n.step(0.1, Vector3(-30.0, 0.0, 4.0))
	TestLib.check(n.actors.size() <= 12 and c.mm.instance_count == Crowd.BUILT and c.count == sizes[1], "nothing grows over 20 s")


## The crowd sends the shader its states: cower = negative amplitude, a standing chat group = flag bit 1 (w >= 2), a walker neither.
func _test_shader_states(c: RefCounted, player: Node3D) -> void:
	c._look.fill(0)
	var i := -1
	for j in c.count:
		if c._alive[j] != 0:
			i = j
			break
	TestLib.check(i >= 0, "a live person exists for the shader-state check")
	if i < 0:
		return
	c._flee[i] = 0.0
	c._gkind[i] = 0
	c._idle[i] = 0.0
	c._fill(c._buf, i * c.STRIDE, i, 1.0)
	TestLib.check(c._buf[i * c.STRIDE + 18] >= 0.0 and c._buf[i * c.STRIDE + 19] < 2.0, "a walker sends a positive amplitude and no talk flag")
	c._idle[i] = 10.0
	c._fill(c._buf, i * c.STRIDE, i, 1.0)
	TestLib.check(c._buf[i * c.STRIDE + 18] == 0.0 and c._buf[i * c.STRIDE + 19] >= 2.0, "a standing chat sends amplitude 0 and the talk flag")
	c.cower_person(i, 5.0)
	c._fill(c._buf, i * c.STRIDE, i, 1.0)
	TestLib.check(c._buf[i * c.STRIDE + 18] < 0.0 and c._buf[i * c.STRIDE + 19] < 2.0, "a cowering person sends a negative amplitude and no talk flag")
	c._cower[i] = 0.0
