class_name Minimap
extends Control
## Circular minimap, rotated so the view direction is up. The static layer (roads and building footprints from Game.world.building_rects) is rendered
## once into a texture and drawn as ONE textured polygon; only the markers (enemies, cars, pickups, beacon, clone, cores clamped to the rim) are drawn live,
## and the whole thing redraws at about 15 Hz.

const CityEventsScript := preload("res://scripts/world/city_events.gd")
const RANGE_M := 130.0              ## metres from the centre to the rim on foot
const RANGE_DRIVE := 280.0          ## ... at full driving speed (the big city: the map zooms out with the speed of the driven vehicle, smoothly)
const DRIVE_FULL := 24.0            ## speed (m/s) at which the map has zoomed out completely
const REFRESH := 1.0 / 15.0
const EXTENT := CityLayout.HALF + 40.0   ## the texture covers |x|, |z| <= EXTENT (the whole 26 x 26 block map)
const TEX_PX := 900                 ## 2.4 m per pixel (the whole 2160 m of the 26 x 26 block city)
const SEGMENTS := 44
const DIAMOND := [Vector2(0, -1), Vector2(0.8, 0), Vector2(0, 1), Vector2(-0.8, 0)]
const ARROW := [Vector2(0, -1.3), Vector2(0.85, 0.9), Vector2(0, 0.4), Vector2(-0.85, 0.9)]

var tex: ImageTexture
var markers_drawn := 0              ## markers inside the rim in the last redraw (for tests)
var shard_markers := 0              ## collectible shards drawn (in range, plus the nearest pinned to the rim) in the last redraw
var core_markers := 0               ## cores drawn (clamped to the rim when far) in the last redraw
var contract_markers := 0           ## contract markers drawn (offer, target, zone, destination, officer area) in the last redraw
var route_drawn := false            ## a courier route line was drawn in the last redraw
var campaign_markers := 0           ## scripted campaign step markers drawn (waypoint, zone, target, escort, destination; also counted in contract_markers) in the last redraw

var city_event_markers := 0         ## city event markers drawn in the last redraw (tests)
var gps_drawn := 0                  ## road-following objective line segments drawn in the last redraw (tests)
var _gps := PackedVector3Array()    ## the cached road route to the objective (MapRoute), rebuilt when the goal or the player moved REFRESH_M
var _gps_goal := Vector3.INF
var _gps_from := Vector3.INF
var _gps_custom := false
var _map_screen: MapScreen
var _key := 0
var _t := 0.0
var _t_clock := 0.0
var _pts := PackedVector2Array()
var _uvs := PackedVector2Array()
var _diamond := PackedVector2Array(DIAMOND)
var _arrow := PackedVector2Array(ARROW)
var _fwd := Vector2(0, -1)
var _right := Vector2(1, 0)
var _pos := Vector2.ZERO
var _k := 1.0
var _range := RANGE_M               ## current metres from the centre to the rim (zoom: RANGE_M on foot .. RANGE_DRIVE in a fast vehicle)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pts.resize(SEGMENTS)
	_uvs.resize(SEGMENTS)


## The rim distance the map wants now: on foot RANGE_M, in a vehicle it opens up with the speed.
static func range_for_speed(speed: float) -> float:
	return lerpf(RANGE_M, RANGE_DRIVE, clampf(absf(speed) / DRIVE_FULL, 0.0, 1.0))


func _process(delta: float) -> void:
	var want := RANGE_M
	if is_instance_valid(Game.vehicles):
		var dv: Variant = Game.vehicles.get("driven")
		if dv != null and is_instance_valid(dv):
			want = range_for_speed(float((dv as Object).get("speed")))
	_range = lerpf(_range, want, 1.0 - exp(-2.5 * delta))
	_t_clock += delta
	_t -= delta
	if _t <= 0.0:
		_t = LowPlus.minimap_interval()       # LOW 10 redraws a second, LOW+ 7.5 (a map dot moves a few px between them)
		queue_redraw()


## (Re)builds the cached static layer when the world changed. Returns true when a texture exists.
func ensure_static() -> bool:
	var w: Object = Game.world if is_instance_valid(Game.world) else null
	if w == null:
		return tex != null
	var rects: Variant = w.get("building_rects")
	if not (rects is Array):
		return tex != null
	var key := hash([w.get_instance_id(), (rects as Array).size()])
	if tex != null and key == _key:
		return true
	_key = key
	var img := Image.create(TEX_PX, TEX_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.025, 0.07, 0.09))
	var ppm := float(TEX_PX) / (2.0 * EXTENT)
	var road := Color(0.07, 0.19, 0.24)
	var half_road := Game.ROAD * 0.5
	for i in Game.N + 1:
		var c := -Game.HALF + i * Game.PITCH
		_fill(img, Rect2(c - half_road, -EXTENT, Game.ROAD, 2.0 * EXTENT), ppm, road)
		_fill(img, Rect2(-EXTENT, c - half_road, 2.0 * EXTENT, Game.ROAD), ppm, road)
	var roof := Color(0.2, 0.5, 0.62)
	for r in rects as Array:
		if r is Rect2:
			_fill(img, (r as Rect2).grow(-0.5), ppm, roof)
	tex = ImageTexture.create_from_image(img)
	return true


func _fill(img: Image, r: Rect2, ppm: float, col: Color) -> void:
	var x0 := clampi(floori((r.position.x + EXTENT) * ppm), 0, TEX_PX)
	var y0 := clampi(floori((r.position.y + EXTENT) * ppm), 0, TEX_PX)
	var x1 := clampi(ceili((r.end.x + EXTENT) * ppm), 0, TEX_PX)
	var y1 := clampi(ceili((r.end.y + EXTENT) * ppm), 0, TEX_PX)
	if x1 > x0 and y1 > y0:
		img.fill_rect(Rect2i(x0, y0, x1 - x0, y1 - y0), col)


## World (x, z) to minimap pixels relative to the centre, for the current view heading.
func to_map(wx: float, wz: float) -> Vector2:
	var d := Vector2(wx, wz) - _pos
	return Vector2(d.dot(_right), -d.dot(_fwd)) * _k


func _update_view(radius: float) -> void:
	var p := Game.player if is_instance_valid(Game.player) else null
	if p != null:
		_pos = Vector2(p.global_position.x, p.global_position.z)
	var f := Vector2(0, -1)
	if is_instance_valid(Game.camera):
		var cf := -Game.camera.global_transform.basis.z
		f = Vector2(cf.x, cf.z)
	elif p != null:
		f = Vector2(-sin(p.rotation.y), -cos(p.rotation.y))
	if f.length() > 0.001:
		_fwd = f.normalized()
	_right = Vector2(-_fwd.y, _fwd.x)
	_k = radius / _range


func _draw() -> void:
	var t0 := PerfTimers.start()
	_draw_body()
	PerfTimers.stop(PerfTimers.MINIMAP, t0)


func _draw_body() -> void:
	var s := UiUtil.ui_scale(get_viewport_rect().size)
	var c := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 2.0
	_update_view(radius)
	markers_drawn = 0
	core_markers = 0
	contract_markers = 0
	campaign_markers = 0
	city_event_markers = 0
	route_drawn = false
	draw_circle(c, radius, Color(0.02, 0.06, 0.08, 0.82))
	if InteriorGameplay.active:                  # inside an interior: its floor plan, vendors, guards and mission markers instead of the city
		InteriorMinimap.draw(self, c, radius, s)
		return
	if ensure_static():
		var inv := 1.0 / (2.0 * EXTENT)
		for i in SEGMENTS:
			var a := TAU * float(i) / SEGMENTS
			var l := Vector2(cos(a), sin(a)) * radius
			_pts[i] = c + l
			var w := _pos + _right * (l.x / _k) - _fwd * (l.y / _k)
			_uvs[i] = Vector2((w.x + EXTENT) * inv, (w.y + EXTENT) * inv)
		draw_colored_polygon(_pts, Color(1, 1, 1, 0.9), _uvs, tex)
	var inner := radius - 3.0 * s
	_draw_gps(c, inner, s)
	var cars: Array = []        # markers are collected and drawn per kind at the end: sprites of one texture batch, circles / polygons / arcs cost a draw call each
	var discs: Array = []
	var diamonds: Array = []
	var rings: Array = []
	var own: Object = Game.player.get("vehicle") if is_instance_valid(Game.player) else null
	# cars (faint), enemies, pickups
	for v: Node in get_tree().get_nodes_in_group(&"vehicle"):
		var vn := v as Node3D
		if vn != null and vn.visible and vn != own:
			var m := to_map(vn.global_position.x, vn.global_position.z)
			if m.length() < inner:
				cars.append(Rect2(c + m - Vector2(1.5, 1.5) * s, Vector2(3, 3) * s))
	for e: Node in get_tree().get_nodes_in_group(&"enemy"):
		var en := e as Node3D
		if en != null and en.visible and en.get("dead") != true:
			var m := to_map(en.global_position.x, en.global_position.z)
			if m.length() < inner:
				discs.append([c + m, 2.8 * s, UiUtil.hostile_col()])
				markers_drawn += 1
	var mis: Object = Game.missions if is_instance_valid(Game.missions) else null
	if mis != null:
		var picks: Variant = mis.get("pickups")
		if picks is Array:
			for pk in picks as Array:
				var pd: Dictionary = pk
				var pp: Vector3 = pd.get("pos", Vector3.ZERO)
				var m := to_map(pp.x, pp.z)
				if m.length() < inner:
					diamonds.append([c + m, 3.6 * s, UiUtil.friend_col() if pd.get("kind", &"health") == &"health" else UiUtil.CYAN])
					markers_drawn += 1
	var q: Object = Game.player.get("quantum") if is_instance_valid(Game.player) else null
	if q != null:
		if q.get("has_beacon") == true:
			var bp: Variant = q.get("beacon_pos")
			if bp is Vector3:
				var m := to_map((bp as Vector3).x, (bp as Vector3).z)
				if m.length() < inner:
					rings.append([c + m, 4.0 * s, UiUtil.CYAN])
		var cl := q.get("clone") as Node3D
		if is_instance_valid(cl):
			var m := to_map(cl.global_position.x, cl.global_position.z)
			if m.length() < inner:
				discs.append([c + m, 3.0 * s, UiUtil.CYAN])
	# quantum cores: magenta diamonds, pinned to the rim and pointing outward when far
	if mis != null:
		var cores: Variant = mis.get("cores")
		if cores is Array:
			for cd in cores as Array:
				var cp: Vector3 = (cd as Dictionary).get("pos", Vector3.ZERO)
				var m := to_map(cp.x, cp.z)
				var far := m.length() > inner - 4.0 * s
				if far:
					m = (m.normalized() if m.length() > 0.001 else Vector2(0, -1)) * (inner - 4.0 * s)
				diamonds.append([c + m, 4.8 * s, UiUtil.objective_col()])
				if not far:
					rings.append([c + m, 7.5 * s, Color(UiUtil.objective_col(), 0.7)])
				core_markers += 1
	# collectible shards: violet diamonds in range, and the nearest one pinned to the rim as a hint
	shard_markers = 0
	var col: Object = (Game.progress.get(&"collectibles") if is_instance_valid(Game.progress) else null)
	if col is Collectibles and is_instance_valid(Game.player):
		var cl2 := col as Collectibles
		var sp := Collectibles.spots()
		var near := cl2.nearest_uncollected(Game.player.global_position)
		for i in Collectibles.COUNT:
			if cl2.is_collected(i):
				continue
			var m := to_map(sp[i].x, sp[i].z)
			if m.length() < inner:
				diamonds.append([c + m, 3.2 * s, Color(0.7, 0.5, 1.0)])
				shard_markers += 1
			elif i == near:
				diamonds.append([c + m.normalized() * (inner - 3.0 * s), 3.2 * s, Color(0.7, 0.5, 1.0, 0.8)])
				shard_markers += 1
	var con: Object = mis.get("contracts") if mis != null else null
	if con != null:
		_contract_layer(con, c, inner, s, diamonds, rings)
	var camp: Object = mis.get("campaign") if mis != null else null
	if camp != null:                                      # the scripted step's markers have the same shape as a contract's (CampaignRunner.markers / route_points)
		var before := contract_markers
		_contract_layer(camp, c, inner, s, diamonds, rings)
		campaign_markers = contract_markers - before
	var cev: Object = CityEventsScript.current
	if is_instance_valid(cev):                            # city events: a pulsing diamond and a ring (clamped to the rim when far)
		for mk: Dictionary in cev.markers():
			var ep: Vector3 = mk["pos"]
			var em := to_map(ep.x, ep.z)
			var far := em.length() > inner
			if far:
				em = em.normalized() * (inner - 3.0 * s)
			var ecol := Color(0.85, 0.5, 1.0) if mk["kind"] == &"rift" else (UiUtil.hostile_col() if mk["kind"] == &"ambush" else UiUtil.objective_col())
			diamonds.append([c + em, 4.4 * s, ecol])
			if not far:
				rings.append([c + em, maxf(float(mk["radius"]) * _k, 6.0 * s), Color(ecol, 0.55)])
			city_event_markers += 1
	for fm: Dictionary in Freedom.markers():               # open world jobs: a coloured diamond per marker, the live goal clamped to the rim with a ring
		var fp: Vector3 = fm["pos"]
		var fmm := to_map(fp.x, fp.z)
		var ffar := fmm.length() > inner
		var is_goal := bool(fm["goal"])
		if ffar and not is_goal:
			continue
		if ffar:
			fmm = fmm.normalized() * (inner - 3.0 * s)
		var fcol: Color = fm["color"]
		diamonds.append([c + fmm, (4.8 if is_goal else 3.6) * s, Color(fcol, 1.0 if is_goal else 0.8)])
		if is_goal and not ffar:
			rings.append([c + fmm, maxf(float(fm["radius"]) * _k, 6.0 * s), Color(fcol, 0.55)])
	for r: Rect2 in cars:
		draw_rect(r, Color(0.7, 0.75, 0.8, 0.6))
	for kind: Array in [[&"disc", discs], [&"diamond", diamonds], [&"ring", rings]]:
		for d: Array in kind[1]:
			var hs := float(d[1])
			draw_texture_rect(UiUtil.sprite(kind[0]), Rect2((d[0] as Vector2) - Vector2(hs, hs), Vector2(hs, hs) * 2.0), false, d[2])
	# the player: fixed arrow in the middle
	draw_set_transform(c, 0.0, Vector2(5.0, 5.0) * s)
	draw_colored_polygon(_arrow, Color(1, 1, 1, 0.95))
	draw_set_transform(Vector2.ZERO)
	# north tick and the rim
	var nl := Vector2(Vector2(0, -1).dot(_right), -Vector2(0, -1).dot(_fwd))
	draw_string(UiUtil.font(), c + nl * (radius - 9.0 * s) + Vector2(-5.0, 6.0) * s, "N", HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(18.0 * s), Color(UiUtil.CYAN, 0.9))
	draw_arc(c, radius, 0.0, TAU, 56, Color(UiUtil.CYAN, 0.55), 1.6 * s, false)


## The objective as a line along the ROADS (MapRoute: your map waypoint, else the scripted step, else the side contract), cut at the rim. Cached; rebuilt every REFRESH_M metres.
func _draw_gps(c: Vector2, inner: float, s: float) -> void:
	gps_drawn = 0
	if not is_instance_valid(Game.player):
		return
	if _map_screen == null or not is_instance_valid(_map_screen):
		_map_screen = get_tree().root.find_child("MapScreen", true, false) as MapScreen
	var custom := _map_screen.waypoint if _map_screen != null else Vector3.INF
	var goal := MapRoute.goal(custom)
	if not goal.is_finite():
		_gps = PackedVector3Array()
		_gps_goal = Vector3.INF
		return
	var from := Game.player.global_position
	if goal != _gps_goal or _gps.is_empty() or Vector2(from.x - _gps_from.x, from.z - _gps_from.z).length() > MapRoute.REFRESH_M:
		_gps = MapRoute.route(from, goal)
		_gps_goal = goal
		_gps_from = from
		_gps_custom = custom.is_finite()
	var pl := PackedVector2Array()
	for rp: Vector3 in _gps:
		pl.append(c + to_map(rp.x, rp.z))
	var col := Color(UiUtil.CYAN, 0.95) if _gps_custom else Color(1.0, 0.78, 0.2, 0.95)
	for seg: PackedVector2Array in MapRoute.clip_to_circle(pl, c, inner):
		draw_polyline(seg, Color(0.0, 0.02, 0.04, 0.9), 5.2 * s)
		draw_polyline(seg, col, 3.0 * s)
		gps_drawn += 1


## Contract markers and the courier route (see Contracts.markers / route_points): a cyan diamond for an offer, a pulsing diamond with a ring for a target, a big ring for a
## hack node / anchor zone, a ring over a clamped diamond for the officer's approximate area, an amber flag diamond for a delivery. The route is ONE polyline clamped to the rim.
func _contract_layer(con: Object, c: Vector2, inner: float, s: float, diamonds: Array, rings: Array) -> void:
	var route: PackedVector3Array = con.call(&"route_points")
	if route.size() >= 2:
		var pl := PackedVector2Array()
		for rp: Vector3 in route:
			var rm := to_map(rp.x, rp.z)
			if rm.length() > inner:
				rm = rm.normalized() * inner
			pl.append(c + rm)
		draw_polyline(pl, Color(UiUtil.AMBER, 0.9), 2.4 * s)
		route_drawn = true
	var list: Array = con.call(&"markers")
	var n := int(con.call(&"marker_count"))
	var pulse := 0.75 + 0.25 * sin(_t_clock * 6.0)
	for i in n:
		var mk: Dictionary = list[i]
		var wp: Vector3 = mk["pos"]
		var col: Color = mk["color"]
		var m := to_map(wp.x, wp.z)
		var far := m.length() > inner - 4.0 * s
		var kind: StringName = mk["kind"]
		if far:
			m = (m.normalized() if m.length() > 0.001 else Vector2(0, -1)) * (inner - 4.0 * s)
		if (kind == &"zone" or kind == &"area") and not far:
			var rr := float(mk["radius"]) * _k
			rings.append([c + m, maxf(rr, 7.0 * s), Color(col, 0.6 * pulse)])
		else:
			diamonds.append([c + m, (5.4 if kind != &"offer" else 4.6) * s, Color(col, pulse if kind == &"target" else 1.0)])
			if kind != &"offer" and not far:
				rings.append([c + m, 8.0 * s, Color(col, 0.75 * pulse)])
		contract_markers += 1
