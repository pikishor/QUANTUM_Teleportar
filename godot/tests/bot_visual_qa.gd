extends RefCounted
## Visual QA bot: ~12 fixed spots, one PNG each plus numeric checks (tests/visual_qa_lib.gd). Use tools/visual_qa.sh.
##   VQA_OUT=<dir> (PNG folder)  VQA_SPOTS=a,b (subset)   prints VQA <spot> PASS|FAIL mean= contrast= black= [sep=] [why]
const SPOTS: Array[StringName] = [&"street_nw", &"street_ne", &"street_sw", &"street_se", &"interior", &"car", &"chase", &"boss", &"title", &"hero", &"rain", &"storm", &"sky_dawn", &"sky_noon", &"sky_dusk", &"sky_night", &"district_market", &"district_foundry", &"district_slums", &"district_towers", &"roofs_market", &"roofs_foundry", &"roofs_slums", &"roofs_towers"]
const Kit := preload("res://scripts/world/city_kit.gd")
const KitWorld := preload("res://scripts/world/city_kit_world.gd")
const Districts := preload("res://scripts/world/city_districts.gd")
const Dress := preload("res://scripts/world/city_kit_dress.gd")
const SETTLE := 16
const CAR_KIND := &"sedan"
const CAR_PAINT := 4          ## VehicleSpecs.COLORS: dusk violet
var _i := 0
var _wait := 0
var _phase := 0
var _spots: Array[StringName] = []
var _out := ""
var _p: Player
var _shown: Image
var _hidden_nodes: Array[MeshInstance3D] = []
var _fails := 0
var _hero_tries := 0


func _init() -> void:
	_out = OS.get_environment("VQA_OUT")
	var s := OS.get_environment("VQA_SPOTS")
	for n in (s.split(",", false) if s != "" else PackedStringArray()):
		_spots.append(StringName(n))
	if _spots.is_empty():
		_spots.assign(SPOTS)


func step(_t: float, _dt: float) -> bool:
	if _p == null:
		_p = Game.player as Player
		if _p == null:
			return false
		for n in _p.get_tree().root.find_children("*", "AutoQuality", true, false):
			(n as AutoQuality).enabled = false
		for n in _p.get_tree().root.find_children("*", "Stability", true, false):
			n.set_process(false)
		_p.max_hp = 1.0e6
		DirAccess.make_dir_recursive_absolute(_out)
		_begin()
	if _wait > 0:
		_wait -= 1
		_hold()
		return false
	var spot := _spots[_i]
	var vp := _p.get_viewport()
	if spot == &"hero" and _phase == 0:
		_shown = vp.get_texture().get_image()
		_set_hero(false)
		_phase = 1
		_wait = 4
		return false
	var img: Image = _shown if _phase == 1 else vp.get_texture().get_image()
	var sep := -1.0
	if _phase == 1:
		var hidden := vp.get_texture().get_image()
		_set_hero(true)
		sep = float(VisualQaLib.separation(_shown, hidden)["sep"])
	if spot == &"hero" and sep >= 0.0 and sep < VisualQaLib.MIN_SEP and _hero_tries < 2:
		_hero_tries += 1              # the separation is measured on two frames and is state-dependent (the hero may face away): look again before failing
		_phase = 0
		_wait = 8
		return false
	var st := VisualQaLib.stats(img)
	var people := -1
	if String(spot).begins_with("street_"):
		for n in _p.get_tree().root.find_children("*", "Node3D", true, false):
			var cr = n.get("crowd")
			if cr != null and cr.has_method(&"count_near"):
				people = cr.count_near(_p.global_position, VisualQaLib.PEOPLE_RADIUS)
				break
	var extra := ""
	if spot == &"title":
		extra = _badge_overlap()
	var fr := VisualQaLib.flat_rects(img, _is_open_sky)
	var why := VisualQaLib.verdict(st, sep, people, float(fr["frac"]), extra)
	if why.contains("rectangle"):
		why += " [flat frac=%.3f rect=%s open_rays=%d]" % [fr["frac"], fr["rect"], _last_open]
	img.save_png("%s/%s.png" % [_out, spot])
	if why != "":
		_fails += 1
	print("VQA %s %s mean=%.3f contrast=%.3f black=%.3f%s %s" % [spot, "PASS" if why == "" else "FAIL", st["mean"], st["contrast"], st["black"], ((" sep=%.3f" % sep) if sep >= 0.0 else "") + ((" people=%d" % people) if people >= 0 else ""), why])
	_i += 1
	if _i >= _spots.size():
		print("VQA_DONE fails=%d" % _fails)
		if OS.get_environment("BOT_FASTEXIT") != "":
			OS.kill(OS.get_process_id())
		return true
	_begin()
	return false


## True when the view rays through the corners and the middle of `r` (viewport px) nearly all leave the city without hitting anything: that flat bright rectangle is the sky between
## two towers. A quad drawn over the street, a car or a facade hits geometry on its rays and is NOT exempt.
func _is_open_sky(r: Rect2i) -> bool:
	var cam := _p.get_viewport().get_camera_3d()
	if cam == null:
		return false
	var space := _p.get_world_3d().direct_space_state
	_last_open = 0
	var open_n := 0
	var total := 0
	for iy in 3:
		for ix in 3:
			var pt := Vector2(r.position) + Vector2(r.size) * Vector2((ix + 0.5) / 3.0, (iy + 0.5) / 3.0)
			var from := cam.project_ray_origin(pt)
			var q := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(pt) * 1500.0)
			total += 1
			var hit := space.intersect_ray(q)
			if hit.is_empty() or from.distance_to(hit["position"]) > SKY_FOG_DIST:
				open_n += 1
	_last_open = open_n
	return open_n >= 7      # a sky gap's bounding rect may clip a tower edge or a cable, so most (not all) rays must leave the city


const SKY_FOG_DIST := 300.0     ## geometry this far away is fog-washed to sky colour (a far tower in a sky gap): it counts as open sky
var _last_open := -1
var _look := Vector3.INF
var _cine: Transform3D
var _use_cine := false


func _hold() -> void:
	if _spots[_i] == &"hero":
		for n in _p.get_tree().root.find_children("*", "Hud", true, false):
			(n as Hud).message_left = 0.0       # a leftover mission toast must not sit over the hero (it now lives under the top stack, but the shot is about the hero)
	if _use_cine:
		_p.camera_rig.cine_set(_cine, 80.0)
	elif _look.is_finite():
		_p.camera_rig.look_at_point(_look)


func _begin() -> void:
	_phase = 0
	_wait = SETTLE
	_look = Vector3.INF
	_use_cine = false
	Game.state = &"play"
	if is_instance_valid(Game.enemies):
		TestMode.kill_all_enemies()
	TestMode.set_weather("CLEAR")
	var spot := _spots[_i]
	var corner := ""
	match spot:
		&"street_nw", &"street_ne", &"street_sw", &"street_se":
			corner = String(spot).trim_prefix("street_")
			TestMode.teleport(corner)
			_p.camera_rig.reset_view(-PI * 0.5 if corner.ends_with("e") else PI * 0.5, -0.08)
		&"district_market", &"district_foundry", &"district_slums", &"district_towers":
			_district_view(String(spot).trim_prefix("district_"))
		&"roofs_market", &"roofs_foundry", &"roofs_slums", &"roofs_towers":
			_roof_view(String(spot).trim_prefix("roofs_"))
		&"interior":
			var ig := InteriorGameplay.instance
			if ig != null:
				ig.leave(true)
				_p.teleport_to(Game.SPAWN)
				ig.enter(ig.doors_of(&"weapons", Game.SPAWN)[0], true)
		&"car":
			_p.teleport_to(Game.SPAWN)
			_p.camera_rig.reset_view(-PI * 0.5, -0.1)
			## The car shot is the sedan in dusk violet (the paint that read as flat purple); VQA_CAR / VQA_PAINT override the kind and the COLORS index.
			var kind := StringName(OS.get_environment("VQA_CAR") if OS.get_environment("VQA_CAR") != "" else CAR_KIND)
			TestMode.spawn_vehicle(kind)
			var veh := _nearest_vehicle(kind)
			if veh != null:
				var pi := int(OS.get_environment("VQA_PAINT")) if OS.get_environment("VQA_PAINT") != "" else CAR_PAINT
				veh.visual.set_paint(VehicleSpecs.COLORS[pi])
				veh.paint_i = pi
				_cine = Transform3D(Basis.looking_at(Vector3(-1, -0.15, 0.6)), veh.global_position + Vector3(4.3, 1.4, -2.5))
				_cine = _cine.looking_at(veh.global_position + Vector3(0, 0.6, 0), Vector3.UP)
				_use_cine = true
		&"chase", &"boss":
			TestMode.teleport("spawn")
			TestMode.start_contract(&"chase" if spot == &"chase" else &"boss")
			var k = Game.missions.get(&"contracts") if is_instance_valid(Game.missions) else null
			if k != null and is_instance_valid(k.get(&"target")):
				_look = (k.get(&"target") as Node3D).global_position + Vector3(0, 1.0, 0)
		&"title":
			Game.state = &"menu"
		&"hero":
			var ig2 := InteriorGameplay.instance
			if ig2 != null:
				ig2.leave(true)
			_p.teleport_to(Game.SPAWN)
			var o := _p.global_position
			_cine = Transform3D(Basis.IDENTITY, o + Vector3(1.6, 1.5, 1.4)).looking_at(o + Vector3(0, 1.2, 0), Vector3.UP)
			_use_cine = true
		&"sky_dawn", &"sky_noon", &"sky_dusk", &"sky_night":
			_p.teleport_to(Game.SPAWN)
			_p.camera_rig.reset_view(-PI * 0.5, 0.45)
			var dn: DayNight = (Game.world as City).day_night
			dn.frozen = true
			dn.set_hour({&"sky_dawn": 6.0, &"sky_noon": 12.0, &"sky_dusk": 18.5, &"sky_night": 1.0}[spot])
		&"rain", &"storm":
			_p.teleport_to(Game.SPAWN)
			_p.camera_rig.reset_view(-PI * 0.5, -0.1)
			TestMode.set_weather("RAIN" if spot == &"rain" else "STORM")


## City dressing close-up: a sidewalk-level view of a storefront of the district (nearest dressed ground floor to the district's target point), looking up the facade.
func _district_view(id: String) -> void:
	var ig := InteriorGameplay.instance
	if ig != null:
		ig.leave(true)
	var d: int = Districts.IDS.find(StringName(id))
	var kit = (Game.world as City).street_kit()
	var target: Vector2 = Districts.LANDMARK_TARGETS[d] * 0.7
	var best := Vector3.INF
	var best_yaw := 0.0
	var bd := 1.0e9
	var first: int = Kit.KC_FIRST + KitWorld.DRESS_FIRST
	for pl in kit.placements:
		var k := int(pl["kind"])
		if k < first or int(pl["district"]) != d:
			continue
		var local := k - first
		if local != Dress.AWNING and local != Dress.SHUTTER and local != Dress.COLONNADE and local != Dress.STOOP:
			continue
		var pos: Vector3 = pl["pos"]
		var dist := Vector2(pos.x, pos.z).distance_to(target)
		if dist < bd:
			bd = dist
			best = pos
			best_yaw = float(pl["yaw"])
	if not best.is_finite():
		return
	var n := Vector3(sin(best_yaw), 0.0, cos(best_yaw))
	var t := Vector3(n.z, 0.0, -n.x)
	var cam := Vector3(best.x, 0.0, best.z) + n * 11.0 + t * 7.0
	cam.y = 2.1
	_p.teleport_to(Vector3(cam.x, 0.2, cam.z))
	_cine = Transform3D(Basis.IDENTITY, cam).looking_at(Vector3(best.x, 6.0, best.z) - t * 3.0, Vector3.UP)
	_use_cine = true


## City dressing from above: a rooftop structure of the district seen from a point over the street, at roof height.
func _roof_view(id: String) -> void:
	var ig := InteriorGameplay.instance
	if ig != null:
		ig.leave(true)
	var d: int = Districts.IDS.find(StringName(id))
	var kit = (Game.world as City).street_kit()
	var target: Vector2 = Districts.LANDMARK_TARGETS[d] * 0.6
	var best := Vector3.INF
	var best_yaw := 0.0
	var bd := 1.0e9
	for pl in kit.placements:
		if int(pl["kind"]) != Kit.KC_FIRST + KitWorld.DRESS_FIRST + Dress.ROOFTOP or int(pl["district"]) != d or float((pl["pos"] as Vector3).y) < 28.0:
			continue
		var pos: Vector3 = pl["pos"]
		var dist := Vector2(pos.x, pos.z).distance_to(target)
		if dist < bd:
			bd = dist
			best = pos
			best_yaw = float(pl["yaw"])
	if not best.is_finite():
		return
	var n := Vector3(sin(best_yaw), 0.0, cos(best_yaw))
	var cam := best + n * 30.0 + Vector3(0.0, 5.0, 0.0)
	_p.teleport_to(Vector3(cam.x, 0.2, cam.z))
	_cine = Transform3D(Basis.IDENTITY, cam).looking_at(best + Vector3(0.0, 2.0, 0.0), Vector3.UP)
	_use_cine = true


## Title screen: the HUD buttons (DEMO, OPTIONS, ...) and the TEST badge must not overlap each other.
func _badge_overlap() -> String:
	var rects := {}
	for n in _p.get_tree().root.find_children("*", "Hud", true, false):
		for b: Dictionary in (n as Hud).buttons:
			if String(b["id"]) in ["demo", "options"]:
				rects[String(b["id"]).to_upper()] = b["rect"]
	for n in _p.get_tree().root.find_children("*", "TestMenu", true, false):
		rects["TEST"] = (n as TestMenu).entry_rect()
	return VisualQaLib.overlap(rects)


func _nearest_vehicle(kind: StringName) -> Vehicle:
	var best: Vehicle
	var bd := 1.0e9
	for v: Vehicle in (Game.vehicles as VehicleManager).list:
		if is_instance_valid(v) and v.kind == kind:
			var d := v.global_position.distance_to(_p.global_position)
			if d < bd:
				bd = d
				best = v
	return best


func _set_hero(on: bool) -> void:
	if not on:
		_hidden_nodes.clear()
		for n in _p.body.find_children("*", "MeshInstance3D", true, false):
			var m := n as MeshInstance3D
			if m.visible and m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				m.visible = false
				_hidden_nodes.append(m)
	else:
		for m in _hidden_nodes:
			if is_instance_valid(m):
				m.visible = true
		_hidden_nodes.clear()
