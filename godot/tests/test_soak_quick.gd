extends RefCounted
## The CI-sized soak (about 25 s): the real composed game, a short run of tests/bot_soak.gd (every activity once: walk, combat, drive, interiors, tiers, pause, tour, death,
## sector win or new game, then the leak checkpoints), a short run of tests/bot_monkey.gd (random touch / mouse / keys / chaos with the soft-lock probes), and the regression
## checks of the bugs those bots found (docs/QA.md): the prologue cards that swallowed the taps of the title screen, the interior minimap polygon, the car mesh caches.
## The long versions: tools/soak.sh (10 simulated minutes) and tools/soak.sh --monkey.
## Run: tools/test.sh tests/test_soak_quick.gd

const Lib := preload("res://tests/soak_lib.gd")
const Soak := preload("res://tests/bot_soak.gd")
const Monkey := preload("res://tests/bot_monkey.gd")

var host: Node
var main: Node


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	Game.force_touch = true                                   # the monkey wants the touch controls
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	TestLib.check(is_instance_valid(Game.player) and is_instance_valid(Game.world) and Game.state == &"play", "the composed game is running")
	_minimap_polygon()
	await _car_caches()
	await _soak()
	await _monkey()
	await _prologue_then_menu()
	Game.force_touch = false
	Sfx.muted = false


# --- regression: interior minimap -----------------------------------------------------------------------------------------------

## Clamping the corners of a wall rectangle into the map circle can collapse or fold it; draw_colored_polygon then failed to triangulate ("Invalid polygon data"), hundreds of
## errors a minute indoors. The quad is now drawn only when it is still a proper convex quad.
func _minimap_polygon() -> void:
	var ok := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 4), Vector2(0, 4)])
	var line := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 0), Vector2(0, 0)])
	var point := PackedVector2Array([Vector2(3, 3), Vector2(3, 3), Vector2(3, 3), Vector2(3, 3)])
	var bow := PackedVector2Array([Vector2(0, 0), Vector2(10, 4), Vector2(10, 0), Vector2(0, 4)])
	var sliver := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 0.0005), Vector2(0, 0.0005)])
	TestLib.check(InteriorMinimap._drawable(ok), "a proper rectangle is drawn")
	TestLib.check(not InteriorMinimap._drawable(line) and not InteriorMinimap._drawable(point), "a quad collapsed to a line or a point is skipped")
	TestLib.check(not InteriorMinimap._drawable(bow), "a folded (bow tie) quad is skipped")
	TestLib.check(not InteriorMinimap._drawable(sliver), "a hairline quad is skipped")


# --- regression: the caches of the car meshes -----------------------------------------------------------------------------------

## ShadowProxy, VehicleVisual and DynamicFill cached merged / shadow meshes and albedo lifts under the instance id of the model's source mesh. A model that is instantiated again after
## its PackedScene was dropped has NEW mesh objects (new ids, same resource path), so the key never hit and every car that was built added a mesh to the cache for ever (0.3 MB and
## 3 objects a car: 130 MB in a 10-minute soak). Keyed by resource path now.
func _car_caches() -> void:
	var a := Game.load_model("car_sedan")
	TestLib.check(a != null, "the sedan model loads")
	if a == null:
		return
	host.add_child(a)
	var ma := (a.get_node("Body") as MeshInstance3D).mesh
	var path := ma.resource_path
	var id_a := ma.get_instance_id()
	var s1 := ShadowProxy._shadow_mesh(ma)
	var mat := ma.surface_get_material(0) as BaseMaterial3D
	var l1 := DynamicFill._lift_for(ma, 0, mat)
	var lift_n := DynamicFill._lift_cache.size()
	var tex := mat.albedo_texture
	var tex_n := -1
	if tex != null:
		DynamicFill._texture_lum(tex)
		tex_n = DynamicFill._tex_cache.size()
	ma = null
	mat = null
	tex = null
	a.free()                                                 # what a car going back to the pool for good does: its model (and the PackedScene behind it) is dropped
	await frames(3)
	var b := Game.load_model("car_sedan")
	host.add_child(b)
	var mb := (b.get_node("Body") as MeshInstance3D).mesh
	TestLib.check(mb.resource_path == path and path != "", "the reloaded model has the same mesh resource path (%s)" % path)
	if mb.get_instance_id() == id_a:
		print("note: the model's mesh object was reused this time (resource cache), the id-keyed cache could not show its bug here")
	var s2 := ShadowProxy._shadow_mesh(mb)
	TestLib.check(s1 != null and s1 == s2, "ShadowProxy gives the reloaded model the cached shadow mesh (same object: %s)" % str(s1 == s2))
	var l2 := DynamicFill._lift_for(mb, 0, mb.surface_get_material(0) as BaseMaterial3D)
	TestLib.check(DynamicFill._lift_cache.size() == lift_n and is_equal_approx(l1, l2), "DynamicFill reuses the albedo lift of the first load (%d entries)" % lift_n)
	var tex2 := (mb.surface_get_material(0) as BaseMaterial3D).albedo_texture
	if tex2 != null and tex_n >= 0:
		DynamicFill._texture_lum(tex2)
		TestLib.check(DynamicFill._tex_cache.size() == tex_n, "DynamicFill reads a reloaded texture's luminance only once (%d entries)" % tex_n)
	b.free()
	var path_keys := func() -> int:
		var n := 0
		for k in VehicleVisual._merged:
			if k is String and (k as String).contains("/car_sedan"):
				n += 1
		return n
	var v1 := VehicleVisual.new()
	var n1 := v1.build(&"sedan", Color(0.2, 0.9, 1.0))
	var merged := int(path_keys.call())
	var v2 := VehicleVisual.new()
	var n2 := v2.build(&"sedan", Color(1.0, 0.3, 0.9))
	TestLib.check(merged >= 1 and int(path_keys.call()) == merged, "a second sedan visual adds no lamp mesh to the cache (%d entries for the sedan)" % merged)
	n1.free()
	n2.free()


# --- the soak ---------------------------------------------------------------------------------------------------------------

func _soak() -> void:
	var bot := Soak.new()
	bot.minutes = 1.0
	bot.scale = 0.25
	bot.max_cycles = 1
	bot.speed = 4
	bot.seed_value = 7
	bot.limits["static_mb"]["abs"] = 96.0                      # two checkpoints only: the later lazy loads of a short run are not a trend
	bot.limits["nodes"]["abs"] = 250
	await bot.run(host)
	var r := bot.report
	TestLib.check(str(r.get("verdict")) == "PASS", "the short soak passes (fails: %s)" % str(r.get("fails")))
	TestLib.check(int(r.get("errors", -1)) == 0, "the short soak raised no error")
	TestLib.check(int(r.get("checkpoints", 0)) == 2, "the short soak took the baseline and one cycle checkpoint (%d)" % int(r.get("checkpoints", 0)))
	var c: Dictionary = r.get("counts", {})
	for key: String in ["walks", "fights", "drives", "interiors", "tier_cycles", "pauses", "tours", "death_activity"]:
		TestLib.check(int(c.get(key, 0)) >= 1, "the soak did its %s (%d)" % [key, int(c.get(key, 0))])
	TestLib.check(int(c.get("screen_dead", 0)) >= 1, "the soak died and came back through the RESPAWN button")
	TestLib.check(Game.state == &"play" and is_equal_approx(Engine.time_scale, 1.0) and Engine.physics_ticks_per_second == 60, "the soak leaves the engine at normal speed, in play")
	await frames(10)


func _monkey() -> void:
	var bot := Monkey.new()
	bot.minutes = 0.6
	bot.speed = 4
	bot.seed_value = 11
	await bot.run(host)
	var r := bot.report
	TestLib.check(str(r.get("verdict")) == "PASS", "the short monkey run passes (fails: %s)" % str(r.get("fails")))
	TestLib.check(int(r.get("events", 0)) >= 300, "the monkey sent %d events" % int(r.get("events", 0)))
	TestLib.check(int((r.get("counts", {}) as Dictionary).get("probes", 0)) >= 1, "the monkey ran its soft-lock probes")
	TestLib.check(Game.state == &"play" and is_equal_approx(Engine.time_scale, 1.0), "the monkey leaves the game in play at normal speed")
	await frames(10)


# --- regression: the title screen under prologue cards --------------------------------------------------------------------------

## NEW GAME starts the prologue cards; ABORT TO MENU used to leave them frozen and invisible, and while a card was young it swallowed the tap on DEPLOY for good (story.gd _input).
func _prologue_then_menu() -> void:
	var hud := Lib.find_hud()
	var story := Game.story
	TestLib.check(hud != null and story != null, "the HUD and the story layer exist")
	if hud == null or story == null:
		return
	for round in 2:
		Game.state = &"menu"
		await frames(20)
		Game.start_new_game()                                   # the prologue cards start
		await frames(10)
		TestLib.check(not story.cards.is_empty(), "round %d: the prologue cards are on screen after a new game" % round)
		hud.pause_game()
		await frames(5)
		TestLib.check(hud.press_button(&"menu") and Game.state == &"menu", "round %d: ABORT TO MENU reaches the title screen" % round)
		await frames(10)
		hud.call(&"_ensure_layout")
		var pos := Vector2.ZERO
		for b: Dictionary in hud.buttons:
			if b["id"] == &"deploy":
				pos = (b["rect"] as Rect2).get_center()
		for tap in 4:                                            # a person taps again if nothing happens
			Lib.mouse_event(pos, true)
			await frames(2)
			Lib.mouse_event(pos, false)
			await frames(2)
			if Game.state == &"play":
				break
		TestLib.check(Game.state == &"play", "round %d: a tap on DEPLOY starts the game although the old prologue cards are still queued" % round)
		await frames(5)
	story.skip_cards()
