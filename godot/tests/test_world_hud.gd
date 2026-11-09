extends RefCounted
## HUD AND IN-GAME UI FOR THE BIG WORLD (wave 109b), data first, then the real scene (main.tscn, touch layout, 2400x1080 canvas):
##   WorldHud     place names (city, airport, harbour, sites, rivers, biomes), landmarks, the compass strip's data, the route chip (tracker), wanted info
##   WorldRoute   GPS for the three modes: car over the roads (city grid, gates, highways, tracks), air in a straight line, boat over the water mask; ETAs
##   HudFeed      the kill and pickup feeds (merge, cap, expire, the pickup lines leave the toast, enemy deaths are seen by polling)
##   DamageFeedback  the ghost segment, the flash, the hull states
##   VehicleHud   one readout per family (car, boat, tank, heli, plane) on real vehicles; the default frame stays within 12 controls in each of them
##   Map          waypoints outside the city, REGION / WORLD zoom, the GPS mode button, airport / harbour / site badges, biome names, the colour key
##   Minimap      range per vehicle, the landmark pins
## Waits on counters and state, never on frame counts; user:// state is reset.
## Run: tools/test.sh tests/test_world_hud.gd

const SAVE := "user://test_world_hud.cfg"
const SETTINGS := "user://test_world_hud_settings.cfg"
const MAX_CONTROLS := 12

class FakeFoe extends Node3D:
	var dead := false
	var id: StringName = &""
	var type: StringName = &"sentinel"

var host: Node
var main: Node
var hud: Hud
var p: Player
var vm: VehicleManager


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func _cleanup() -> void:
	for f: String in [SAVE, SETTINGS, MapScreen.SAVE_PATH]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	_cleanup()
	TerrainHeight.warm()
	TerrainRoads.ensure()
	WaterLayout.ensure()
	TerrainMap.build_now()
	_place_and_landmarks()
	_compass_data()
	_routes()
	_tracker()
	_feed_logic()
	_damage_logic()
	await _scene()
	_cleanup()


# --- data -----------------------------------------------------------------------------------------------------------------

func _place_and_landmarks() -> void:
	var city := WorldHud.place(Vector3.ZERO)
	TestLib.check(city["name"] == "CITY" and city["kind"] == &"city", "the middle of the map is the CITY")
	var ap := WorldHud.place(Airport.to_world(Vector3(1170.0, 0.0, -560.0)))
	TestLib.check(ap["name"] == Airport.NAME and ap["kind"] == &"airport", "the apron is %s" % Airport.NAME)
	var hb := WorldHud.place(Harbour.center())
	TestLib.check(hb["name"] == "HARBOUR" and hb["kind"] == &"harbour", "the basin is the HARBOUR")
	var site: Dictionary = OutskirtsSites.list[0]
	var sp := WorldHud.place(site["pos"])
	TestLib.check(sp["name"] == String(site["name"]) and sp["kind"] == &"site", "a site's pad carries the site's name (%s)" % sp["name"])
	var sea := WorldHud.place(Vector3(-2800.0, 0.0, 2800.0))
	TestLib.check(sea["kind"] == &"sea" and sea["name"] == "OPEN SEA", "the far south-west is OPEN SEA")
	var river: Dictionary = WaterLayout.paths[0]
	var rp: Vector2 = (river["pos"] as PackedVector2Array)[(river["pos"] as PackedVector2Array).size() / 2]
	var rw := WorldHud.place(Vector3(rp.x, 0.0, rp.y))
	TestLib.check(rw["kind"] == &"water" and rw["name"] == String(river["name"]), "the middle of %s is named by the river (%s)" % [river["name"], rw["name"]])
	var kinds := {}
	for pt in [Vector3(1650, 0, -1700), Vector3(-1600, 0, -1300), Vector3(1650, 0, 900), Vector3(-1750, 0, 700), Vector3(2200, 0, 2200), Vector3(-2200, 0, -2200)]:
		var pl := WorldHud.place(pt)
		TestLib.check(String(pl["name"]) != "" and int(pl["alt"]) >= 0, "every outskirt point has a name and a height (%s %d m)" % [pl["name"], pl["alt"]])
		kinds[pl["kind"]] = true
	TestLib.check(kinds.size() >= 3, "the outskirts name at least three kinds of ground (%s)" % str(kinds.keys()))
	var lm := WorldHud.landmarks()
	var names := []
	for m: Dictionary in lm:
		names.append(m["name"])
	TestLib.check(names.has("CITY") and names.has(Airport.NAME) and names.has("HARBOUR") and lm.size() >= 3 + OutskirtsSites.list.size() - 1, "the compass knows the city, the airport, the harbour and the sites (%d)" % lm.size())
	WorldHud.reset_place()
	TestLib.check(WorldHud.update_place(Vector3.ZERO, 10.0) == "CITY" and WorldHud.place_age(11.0) < WorldHud.PLACE_HOLD, "a new place name is fresh for a few seconds")
	WorldHud.update_place(Airport.to_world(Vector3(1170.0, 0.0, -560.0)), 20.0)
	TestLib.check(WorldHud.current_place() == Airport.NAME and WorldHud.place_age(20.5) < 1.0 and WorldHud.place_age(30.0) > WorldHud.PLACE_HOLD, "entering the airport restarts the clock; later it is old")


func _compass_data() -> void:
	var from := Vector3(1350.0, 0.0, 10.0)
	var north := WorldHud.compass(from, 0.0)
	TestLib.check(int(north["heading"]) == 0, "facing north the heading is 000")
	var has_n := false
	for c: Dictionary in north["cardinals"]:
		if c["l"] == "N":
			has_n = absf(float(c["b"])) < 0.01
	var has_mark := not (north["marks"] as Array).is_empty()
	TestLib.check(has_n or has_mark, "N is dead ahead on the strip (or a landmark took its place)")
	var east := WorldHud.compass(from, -PI * 0.5)
	TestLib.check(int(east["heading"]) == 90, "facing east the heading is 090 (%d)" % int(east["heading"]))
	var seen_clash := false
	for yaw in [0.0, 1.0, 2.0, 3.0, -1.0, -2.0]:
		var d := WorldHud.compass(Vector3(0.0, 0.0, 1300.0), yaw)
		var marks: Array = d["marks"]
		TestLib.check(marks.size() <= WorldHud.MARK_MAX, "at most %d landmarks on the strip" % WorldHud.MARK_MAX)
		for i in marks.size():
			for j in range(i + 1, marks.size()):
				if absf(float(marks[i]["b"]) - float(marks[j]["b"])) < 0.45:
					seen_clash = true
		for m: Dictionary in marks:
			TestLib.check(absf(float(m["b"])) <= WorldHud.WINDOW, "a landmark on the strip is inside the 180 degree window")
		for c: Dictionary in d["cardinals"]:
			for m: Dictionary in marks:
				TestLib.check(absf(float(c["b"]) - float(m["b"])) >= 0.13, "a cardinal letter never sits under a landmark")
	TestLib.check(not seen_clash, "landmark labels on the strip keep their distance")
	var goal := WorldHud.compass(from, 0.0, Vector3(from.x, 0.0, from.z + 500.0))
	TestLib.check(bool((goal["goal"] as Dictionary)["pinned"]) and float((goal["goal"] as Dictionary)["dist"]) > 499.0, "a goal behind the hero is pinned to an end of the strip with its distance")
	var ahead := WorldHud.compass(from, 0.0, Vector3(from.x, 0.0, from.z - 500.0))
	TestLib.check(not bool((ahead["goal"] as Dictionary)["pinned"]) and absf(float((ahead["goal"] as Dictionary)["b"])) < 0.01, "a goal ahead is in the middle of the strip")
	TestLib.check(WorldHud.compass_wanted(Vector3(1350, 0, 10), null) and not WorldHud.compass_wanted(Vector3.ZERO, null), "the strip shows outside the city and stays away inside it")


func _routes() -> void:
	WorldRoute.clear_cache()
	var a := Vector3(-300.0, 0.0, 200.0)
	var b := Vector3(500.0, 0.0, -400.0)
	TestLib.check(WorldRoute.build(a, b, &"car").size() == MapRoute.route(a, b).size(), "inside the city the car route is the street staircase")
	var obs: Vector3 = OutskirtsSites.by_id(&"observatory")["pos"]
	var car := WorldRoute.build(Vector3.ZERO, obs, &"car")
	var straight := Vector2(obs.x, obs.z).length()
	TestLib.check(car.size() >= 6 and not bool(WorldRoute.info["direct"]), "the car route to the observatory is a real route (%d points)" % car.size())
	TestLib.check(WorldRoute.length(car) >= straight - 1.0 and WorldRoute.length(car) < straight * 4.0, "it is longer than the crow flies but not absurd (%.0f m for %.0f m)" % [WorldRoute.length(car), straight])
	TestLib.check(Vector2(car[car.size() - 1].x - obs.x, car[car.size() - 1].z - obs.z).length() < 1.0 and car[0].distance_to(Vector3.ZERO) < 1.0, "it starts at the start and ends at the goal")
	var near_road := 0
	var out_n := 0
	for i in range(2, car.size() - 2):
		if not WorldRoute.in_city(car[i]):
			out_n += 1
			if float(TerrainRoads.nearest(car[i].x, car[i].z)[0]) < 45.0:
				near_road += 1
	TestLib.check(out_n >= 10 and float(near_road) / maxf(out_n, 1.0) >= 0.8, "outside the city the route follows the roads (%d of %d points)" % [near_road, out_n])
	var close_a := Vector3(1500.0, 0.0, 1500.0)
	var close_b := Vector3(1600.0, 0.0, 1560.0)
	TestLib.check(WorldRoute.build(close_a, close_b, &"car").size() == 2 and bool(WorldRoute.info["direct"]), "two points close together in the open are one straight line")
	var air := WorldRoute.build(Vector3.ZERO, obs, &"air")
	TestLib.check(air.size() == 2 and absf(WorldRoute.length(air) - straight) < 1.0, "the air route is one straight line")
	TestLib.check(WorldRoute.eta(5000.0, &"air") < WorldRoute.eta(5000.0, &"car") and WorldRoute.eta(5000.0, &"car") < WorldRoute.eta(5000.0, &"foot"), "an aircraft is faster than a car, a car faster than walking")
	TestLib.check(WorldRoute.clock(65.0) == "1:05" and WorldRoute.dist_text(840.0) == "840 M" and WorldRoute.dist_text(1250.0) == "1.2 KM", "the clock and the distance read plainly")
	# the boat: over the water mask
	var wm := TerrainMap.water_mask
	TestLib.check(wm.size() == TerrainMap.WATER_N * TerrainMap.WATER_N and wm.count(1) > 500 and wm.count(0) > 500, "the world map left a water mask with sea and land (%d wet cells)" % wm.count(1))
	var start := Vector3(30.0, 0.0, 1570.0)
	var sea_goal := Vector3(-2500.0, 0.0, 2500.0)
	var boat := WorldRoute.build(start, sea_goal, &"boat")
	TestLib.check(boat.size() >= 2 and WorldRoute.length(boat) >= Vector2(start.x - sea_goal.x, start.z - sea_goal.z).length() - 1.0, "a boat route from the harbour to the open sea exists")
	var far_land: Vector3 = Vector3.INF                                # a wet cell whose straight line to the harbour crosses land
	var best := 0.0
	for cy in range(0, TerrainMap.WATER_N, 4):
		for cx in range(0, TerrainMap.WATER_N, 4):
			var q := WorldRoute._centre(Vector2i(cx, cy))
			var d := Vector2(q.x - start.x, q.z - start.z).length()
			if d > 2500.0 and d > best and WorldRoute._wet(Vector2i(cx, cy)) and not WorldRoute._clear(start, q):
				best = d
				far_land = q
	if far_land.is_finite():
		var around := WorldRoute.build(start, far_land, &"boat")
		var st := Vector2(far_land.x - start.x, far_land.z - start.z).length()
		if not bool(WorldRoute.info["direct"]):
			TestLib.check(WorldRoute.length(around) > st * 1.01, "a boat route round a headland is longer than the line (%.0f m for %.0f m)" % [WorldRoute.length(around), st])
			var dry := 0
			var n := 0
			for i in range(1, around.size() - 1):
				var seg := Vector2(around[i + 1].x - around[i].x, around[i + 1].z - around[i].z).length() if i + 1 < around.size() else 0.0
				for k in range(0, int(seg / 25.0) + 1):
					var pt := around[i].lerp(around[mini(i + 1, around.size() - 1)], float(k) / maxf(seg / 25.0, 1.0))
					n += 1
					if not WorldRoute._wet(WorldRoute._cell(pt)):
						dry += 1
			TestLib.check(dry <= maxi(2, n / 20), "the boat route stays on the water (%d of %d samples dry)" % [dry, n])
		else:
			TestLib.check(true, "no water link to the far cell: a straight line is returned and marked direct")
	var dry_goal := Vector3(1000.0, 0.0, -500.0)                         # a goal on land: the lane ends at the nearest water, the last leg is straight
	var to_land := WorldRoute.build(start, dry_goal, &"boat")
	TestLib.check(to_land.size() >= 2 and Vector2(to_land[to_land.size() - 1].x - dry_goal.x, to_land[to_land.size() - 1].z - dry_goal.z).length() < 1.0, "a boat route to a goal on land still ends at the goal")


func _tracker() -> void:
	var from := Vector3.ZERO
	var obs: Vector3 = OutskirtsSites.by_id(&"observatory")["pos"]
	var t := WorldHud.tracker(from, obs, &"foot")
	TestLib.check(not t.is_empty() and String(t["text"]).contains("KM") and String(t["text"]).contains("ETA") and String(t["text"]).ends_with("ON FOOT"), "the route chip reads distance, ETA and mode (%s)" % t.get("text", ""))
	var tc := WorldHud.tracker(from, obs, &"car")
	var ta := WorldHud.tracker(from, obs, &"air")
	TestLib.check(float(ta["eta"]) < float(tc["eta"]) and float(tc["eta"]) < float(t["eta"]), "the same goal is quickest by air, then by car, then on foot")
	TestLib.check(WorldHud.tracker(from, Vector3(60, 0, 40), &"foot").is_empty() and WorldHud.tracker(from, Vector3.INF, &"foot").is_empty(), "a goal under 150 m away or no goal gives no chip")


func _feed_logic() -> void:
	TestLib.check(HudFeed.classify("+30 INTEGRITY") == HudFeed.PICKUP and HudFeed.classify("+6 CARBINE") == HudFeed.PICKUP and HudFeed.classify("NEW WEAPON  RAILGUN") == HudFeed.PICKUP, "pickup lines are recognised")
	TestLib.check(HudFeed.classify("COURIER RUN COMPLETE  +200 CREDITS") == &"" and HudFeed.classify("CHECKPOINT") == &"", "mission lines are not pickups")
	var f := HudFeed.new()
	f.push(HudFeed.KILL, "DOWN  GRUNT", 0.0)
	f.push(HudFeed.KILL, "DOWN  GRUNT", 0.5)
	var v := f.visible_lines(0.6)
	TestLib.check(v.size() == 1 and int(v[0]["n"]) == 2 and String(v[0]["label"]).ends_with("x2"), "the same kill twice in a moment is one line with x2")
	for i in 6:
		f.push(HudFeed.PICKUP, "+%d AMMO" % (i + 1), 1.0 + i * 0.1)
	TestLib.check(f.visible_lines(2.0).size() == HudFeed.MAX_LINES, "the feed holds at most %d lines" % HudFeed.MAX_LINES)
	var fade := f.visible_lines(1.0 + 5 * 0.1 + HudFeed.LIFE - 0.3)
	TestLib.check(not fade.is_empty() and float(fade[fade.size() - 1]["alpha"]) < 1.0, "a line fades before it goes")
	TestLib.check(f.visible_lines(60.0).is_empty() and not f.active(60.0), "and after LIFE seconds the feed is empty")
	var g := HudFeed.new()
	TestLib.check(g.take_message("+30 INTEGRITY", 0.0) and g.pickups == 1, "'+30 INTEGRITY' goes to the feed and leaves the toast")
	TestLib.check(not g.take_message("COURIER RUN COMPLETE  +200 CREDITS", 0.0) and g.pickups == 1, "a mission line stays a toast")
	TestLib.check(not g.take_message("NEW WEAPON  RAILGUN", 0.0) and g.pickups == 2, "weapon news shows in the feed and as a toast")


func _damage_logic() -> void:
	var d := DamageFeedback.new()
	var r0 := d.track(&"hero", 1.0, 0.0)
	TestLib.check(float(r0["ghost"]) == 1.0 and float(r0["flash"]) == 0.0, "a full bar has no ghost and no flash")
	var r1 := d.track(&"hero", 0.5, 0.1)
	TestLib.check(float(r1["ghost"]) >= 0.99 and float(r1["flash"]) > 0.4, "a hit leaves the lost half as a ghost and flashes the bar")
	var r2 := d.track(&"hero", 0.5, 0.3)
	TestLib.check(float(r2["ghost"]) > 0.9 and float(r2["flash"]) < 0.2, "the ghost holds for a moment, the flash is brief")
	var r3 := d.track(&"hero", 0.5, 0.45)
	var r4 := d.track(&"hero", 0.5, 0.9)
	TestLib.check(float(r4["ghost"]) < float(r3["ghost"]), "then the ghost drains")
	var t := 0.9
	var last := {}
	while t < 3.0:
		t += 0.1
		last = d.track(&"hero", 0.5, t)
	TestLib.check(absf(float(last["ghost"]) - 0.5) < 0.001, "and is gone after a second or two")
	var h := d.track(&"hero", 0.9, t + 5.0)
	TestLib.check(float(h["ghost"]) == 0.9, "healing never leaves a ghost above the bar")
	TestLib.check(bool(d.track(&"hull", 0.2, 0.0)["low"]), "a bar under 30 % is low")
	TestLib.check(DamageFeedback.hull_state(1.0)["word"] == "SOUND" and DamageFeedback.hull_state(0.6)["word"] == "DAMAGED" and DamageFeedback.hull_state(0.3)["word"] == "SMOKING" and bool(DamageFeedback.hull_state(0.1)["critical"]), "hull states: SOUND, DAMAGED, SMOKING, BURNING (critical)")


# --- the real scene -----------------------------------------------------------------------------------------------------

func _scan() -> Array[Dictionary]:
	hud.scan_log.clear()
	hud.scan_text = true
	hud.scan_hud = true
	hud._hud.queue_redraw()
	await frames(3)
	hud.scan_text = false
	return hud.scan_log.duplicate()


func _texts(log: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in log:
		out.append(String(e["text"]))
	return out


func _scene() -> void:
	TestMode.reset_toggles()
	var was_touch := Game.force_touch
	Game.force_touch = true
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	p = Game.player as Player
	hud = main.find_child("Hud", true, false) as Hud
	vm = Game.vehicles as VehicleManager
	var prog := Game.progress as Progress
	TestLib.check(p != null and hud != null and prog != null and vm != null and hud.touch != null, "main.tscn composes the player, the HUD, the vehicles and the touch controls")
	if p == null or hud == null or prog == null or vm == null or hud.touch == null:
		Game.force_touch = was_touch
		return
	prog.autosave_enabled = false
	prog.path = SAVE
	prog.new_campaign()
	hud.settings = UiSettings.new(SETTINGS)
	hud.settings.publish(false)
	(Game.enemies as EnemyManager).clear()
	Game.heat = 0.0
	Game.state = &"play"
	hud.touch.controls_on = true
	hud.touch.more_open = false
	hud.touch.release_all()
	hud.message_left = 0.0
	hud.toast.clear()
	hud.feed.clear()
	await frames(10)
	await _foot_outskirts()
	await _feeds_live()
	await _wanted_live()
	await _vehicles_live()
	await _minimap_live()
	await _map_live()
	Game.heat = 0.0
	hud.feed.clear()
	main.queue_free()
	await frames(5)
	Game.force_touch = was_touch
	Game.state = &"menu"


func _foot_outskirts() -> void:
	var city_ids := _frame_ids()
	TestLib.check(city_ids.size() <= MAX_CONTROLS, "in the city a default frame shows at most %d controls (%d)" % [MAX_CONTROLS, city_ids.size()])
	var at := Vector3(1350.0, 0.0, 10.0)
	p.teleport_to(Vector3(at.x, TerrainHeight.height_at(at.x, at.z) + 1.0, at.z))
	await frames(6)
	TestLib.check(WorldHud.compass_wanted(p.global_position, p.get("vehicle")), "the hero stands outside the city: the landmark strip is on")
	var ids := _frame_ids()
	TestLib.check(ids.size() <= MAX_CONTROLS, "with the strip and the place name the default frame still shows at most %d controls (%d: %s)" % [MAX_CONTROLS, ids.size(), str(ids)])
	var log := await _scan()
	var texts := _texts(log)
	var place := String(WorldHud.place(p.global_position)["name"])
	var found_place := false
	for t in texts:
		if t.ends_with(place):
			found_place = true
	TestLib.check(found_place, "the strip prints the place name (%s)" % place)
	var vp := hud._hud.size
	var all_in := true
	for e: Dictionary in log:
		var r: Rect2 = e["rect"]
		if r.position.x < -2.0 or r.end.x > vp.x + 2.0 or r.position.y < -2.0 or r.end.y > vp.y + 2.0:
			all_in = false
	TestLib.check(all_in, "every HUD text lies inside the screen (%dx%d)" % [int(vp.x), int(vp.y)])
	var d := WorldHud.compass(p.global_position, Game.camera.global_rotation.y)
	var rects: Array[Rect2] = []
	for m: Dictionary in d["marks"]:
		for e: Dictionary in log:                                                  # (the scan holds several redraws: the first match of each label)
			if String(e["text"]) == String(m["short"]):
				rects.append(e["rect"])
				break
	var clash := false
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				clash = true
	TestLib.check(not clash, "the landmark labels on the strip do not touch (%d labels)" % rects.size())
	WorldHud.reset_place()
	await frames(3)


func _feeds_live() -> void:
	hud.feed.clear()
	hud.toast.clear()
	hud.message_left = 0.0
	Game.say("+30 INTEGRITY", 2.0)
	TestLib.check(hud.feed.lines.size() == 1 and hud.message_left <= 0.0, "a pickup line lands in the feed, not in the toast")
	Game.say("COURIER RUN COMPLETE  +200 CREDITS", 2.0)
	TestLib.check(hud.message_left > 0.0, "a mission line is still a toast")
	var foe := FakeFoe.new()
	foe.type = &"hive_sentinel"
	host.add_child(foe)
	foe.add_to_group(&"enemy")
	foe.global_position = p.global_position + Vector3(20.0, 0.0, 0.0)
	hud.feed.poll(host.get_tree(), p.global_position, PlayerUtil.now(), 1.0)
	var before := hud.feed.kills
	foe.dead = true
	hud.feed.poll(host.get_tree(), p.global_position, PlayerUtil.now(), 1.0)
	TestLib.check(hud.feed.kills == before + 1, "a tracked enemy that dies is one DOWN line (%s)" % str(hud.feed.lines.back()["text"]))
	hud.feed.poll(host.get_tree(), p.global_position, PlayerUtil.now(), 1.0)
	TestLib.check(hud.feed.kills == before + 1, "and is counted once")
	foe.queue_free()
	var texts := _texts(await _scan())
	var seen_kill := false
	var seen_pick := false
	for t in texts:
		seen_kill = seen_kill or t.begins_with("DOWN")
		seen_pick = seen_pick or t.begins_with("+30")
	TestLib.check(seen_kill and seen_pick, "both feeds are drawn (small lines under the stars' corner)")
	TestLib.check(hud.visible_controls().size() <= MAX_CONTROLS + 1, "the feeds add no control to the frame")
	hud.feed.clear()


func _wanted_live() -> void:
	Game.heat = 2.6
	await frames(4)
	var info := WorldHud.wanted_info()
	TestLib.check(not info.is_empty() and int(info["level"]) == 3 and String(info["response"]) == "ROADBLOCKS" and String(info["state"]) != "", "wanted level 3 reads ROADBLOCKS with a pursuit state (%s)" % str(info))
	var texts := _texts(await _scan())
	var seen := false
	for t in texts:
		seen = seen or (t.contains("ROADBLOCKS") and t.contains(String(info["state"])))
	TestLib.check(seen, "the pursuit line under the stars is drawn")
	Game.heat = 0.0
	TestLib.check(WorldHud.wanted_info().is_empty(), "no heat, no line")
	p.set(&"hp", 100.0)
	await _scan()
	TestLib.check(hud.damage._s.has(&"hero"), "the hero's health bar reports to the damage feedback")


## Frees the pool slots the traffic took (a test needs a roster vehicle now) and stops new traffic from spawning.
func _free_slots() -> void:
	for v in vm.list.duplicate():
		if v != vm.starter and not v.driver_is_player:
			vm._release(v)
	vm._spawn_t = 1.0e9


## The controls the default frame counts: the transient overlays (a toast, a subtitle line) come and go over it.
func _frame_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in hud.visible_controls():
		if id != &"toast" and id != &"subtitle":
			out.append(id)
	return out


func _vehicles_live() -> void:
	var at := p.global_position
	var cases := [[&"sport", &"car"], [&"boat", &"boat"], [&"tank", &"tank"], [&"heli", &"heli"], [&"plane", &"plane"]]
	for c in cases:
		_free_slots()
		var v := vm.spawn_parked(c[0], at + Vector3(0.0, 0.6, 0.0), 0.0)
		TestLib.check(v != null, "%s: a vehicle of the kind could be placed" % c[0])
		if v == null:
			continue
		await frames(2)
		vm.enter(v)
		await frames(4)
		var pn := VehicleHud.panel(v)
		TestLib.check(pn["family"] == c[1] and int(pn["kmh"]) >= 0 and float(pn["hull"]) > 0.9 and String((pn["state"] as Dictionary)["word"]) == "SOUND", "%s: the %s readout has speed and a sound hull" % [c[0], c[1]])
		match c[1]:
			&"car":
				TestLib.check(int(pn["gear"]) >= 1 and float(pn["nitro"]) > 0.0, "car: gear and nitro")
			&"boat":
				var words := " ".join(hud.vehicle_rows(v).map(func(r: Dictionary) -> String: return String(r["text"])))
				TestLib.check(words.contains("HDG"), "boat: the readout plate gives the heading (%s)" % words)
			&"tank":
				TestLib.check(float(pn["reload"]) >= 0.0 and float(pn["reload"]) <= 1.0 and int(pn["ammo"]) > 0 and absf(float(pn["turret"])) <= PI + 0.001, "tank: the turret dial has a bearing, a reload and rounds")
				var w: VehicleWeapons = v.weapons
				if w != null:
					TestLib.check(w.ready_fraction() > 0.99, "a fresh main gun is ready (%.2f)" % w.ready_fraction())
			&"heli":
				var words2 := " ".join(hud.vehicle_rows(v).map(func(r: Dictionary) -> String: return String(r["text"])))
				TestLib.check(words2.contains("ROTOR"), "heli: the rotor speed is on the plate")
			&"plane":
				TestLib.check(float(pn["stall"]) > 10.0, "plane: the stall speed is known")
		var ids := _frame_ids()
		TestLib.check(ids.size() <= MAX_CONTROLS, "driving the %s the frame shows at most %d controls (%d: %s)" % [c[0], MAX_CONTROLS, ids.size(), str(ids)])
		var log := await _scan()
		var all_in := true
		for e: Dictionary in log:
			var r: Rect2 = e["rect"]
			if r.position.x < -2.0 or r.end.x > hud._hud.size.x + 2.0 or r.position.y < -2.0 or r.end.y > hud._hud.size.y + 2.0:
				all_in = false
		TestLib.check(all_in and _texts(log).has("SOUND"), "%s: every HUD text lies inside the screen and the hull row says SOUND" % c[0])
		TestLib.check(Minimap.range_for_vehicle(v) >= Minimap.RANGE_M, "%s: the minimap range grows with the vehicle (%.0f m)" % [c[0], Minimap.range_for_vehicle(v)])
		vm.exit_vehicle()
		await frames(3)
		v.hp = 0.0 if false else v.hp
	TestLib.check(Minimap.range_for_vehicle(null) == Minimap.RANGE_M and Minimap.RANGE_PLANE > Minimap.RANGE_HELI and Minimap.RANGE_HELI > Minimap.RANGE_BOAT, "minimap ranges: foot < boat < helicopter < plane")
	# a damaged car: the hull row turns to a warning
	_free_slots()
	var car := vm.spawn_parked(&"sport", at + Vector3(0.0, 0.6, 0.0), 0.0)
	TestLib.check(car != null, "a car for the damage readout")
	if car == null:
		return
	await frames(2)
	vm.enter(car)
	car.hp = car.max_hp * 0.2
	await frames(3)
	var pnl := VehicleHud.panel(car)
	TestLib.check(bool((pnl["state"] as Dictionary)["critical"]) and (pnl["state"] as Dictionary)["word"] == "BURNING", "a car at 20 % hull reads BURNING (critical)")
	TestLib.check(_texts(await _scan()).has("BURNING"), "and the hull row says so")
	vm.exit_vehicle()
	await frames(3)


func _minimap_live() -> void:
	var ap := Airport.to_world(Vector3(1150.0, 0.0, -560.0))
	p.teleport_to(Vector3(ap.x, TerrainHeight.height_at(ap.x, ap.z) + 1.0, ap.z))
	await frames(6)
	hud.minimap.queue_redraw()
	await frames(3)
	TestLib.check(hud.minimap.pins_drawn >= 1, "at the airport the minimap pins landmarks (%d)" % hud.minimap.pins_drawn)
	TestLib.check(TerrainMap.ready and TerrainMap.texture != null, "the minimap has the terrain picture to show outside the city")


func _map_live() -> void:
	Game.state = &"play"
	hud.touch.open_map()
	await frames(4)
	var ms := hud.touch.get_node_or_null("MapScreen") as MapScreen
	TestLib.check(ms != null and ms.is_open(), "the map opens")
	if ms == null:
		return
	var obs: Vector3 = OutskirtsSites.by_id(&"observatory")["pos"]
	ms.set_waypoint(obs)
	TestLib.check(ms.has_waypoint() and absf(ms.waypoint.z) > MapScreen.HALF, "a waypoint can be placed in the outskirts (z %.0f)" % ms.waypoint.z)
	TestLib.check(ms.route_points().size() >= 6 and ms._route_style == &"car", "the GPS follows the roads on foot")
	var m0 := ms._route_m
	ms.cycle_route_mode()
	TestLib.check(ms.route_mode == &"car", "the GPS button goes AUTO -> CAR")
	ms.cycle_route_mode()
	TestLib.check(ms.route_mode == &"air" and ms.route_points().size() == 2 and ms._route_eta < WorldRoute.eta(float(m0), &"car"), "AIR is one straight, quicker line")
	ms.cycle_route_mode()
	TestLib.check(ms.route_mode == &"boat" and ms.route_points().size() >= 2, "BOAT gives a sea lane")
	ms.cycle_route_mode()
	TestLib.check(ms.route_mode == &"auto", "and the button comes round to AUTO")
	ms.set_zoom(4)
	ms._on_zoom_button()
	TestLib.check(ms.world_mode and ms.region_view() and ms._zoom_btn.text == "REGION", "after 4x the zoom button opens the REGION level")
	ms._on_zoom_button()
	TestLib.check(ms.world_mode and not ms.region_view() and ms._zoom_btn.text == "WORLD", "then WORLD")
	ms._on_zoom_button()
	TestLib.check(not ms.world_mode and ms.zoom == 1, "and back to the city")
	ms.set_world_mode(true)
	var mk := ms.collect_markers()
	var glyphs := {}
	var sites := 0
	for m: Dictionary in mk:
		if m.has("glyph"):
			glyphs[m["glyph"]] = true
		if m["kind"] == &"site":
			sites += 1
	TestLib.check(glyphs.has(&"airport") and glyphs.has(&"harbour") and sites >= 11, "the world map has the airport, the harbour and %d sites as markers" % sites)
	var lod := ms.lod_markers(ms.visible_markers())
	var lod_glyph := 0
	var lod_city := 0
	for m: Dictionary in lod:
		if m.has("glyph"):
			lod_glyph += 1
		if m["kind"] in [&"interior", &"shop", &"weapon", &"items", &"job"]:
			lod_city += 1
	TestLib.check(lod_glyph >= 2 and lod_city == 0, "in the world view the airport and the harbour stay and the city's doors and shops go (%d, %d)" % [lod_glyph, lod_city])
	ms.scan_on = true
	ms._map.queue_redraw()
	await frames(3)
	var names := []
	for e: Dictionary in ms.scan_log:
		names.append(String(e["text"]))
	TestLib.check(names.has("HARBOUR") and names.has(Airport.NAME), "the world map names the airport and the harbour (%d labels)" % names.size())
	var regions := 0
	for e in TerrainMap.LABELS:
		if names.has(String(e[0])) and e[0] != "CITY":
			regions += 1
	TestLib.check(regions >= 3, "and prints biome names (%d of %d)" % [regions, TerrainMap.LABELS.size() - 1])
	var all_in := true
	for e: Dictionary in ms.scan_log:
		var r: Rect2 = e["rect"]
		if r.end.x > ms._map.size.x + 2.0 or r.end.y > ms._map.size.y + 2.0 or r.position.x < -2.0 or r.position.y < -8.0:
			all_in = false
	TestLib.check(all_in, "no map label leaves the screen")
	ms.scan_on = false
	TestLib.check(TerrainMap.BIOME_KEY.size() >= 6, "the colour key lists the biomes")
	ms.close_screen()
	await frames(3)
	TestLib.check(not ms.is_open() and Game.state == &"play", "the map closes and the game resumes")
	ms.clear_waypoint()
