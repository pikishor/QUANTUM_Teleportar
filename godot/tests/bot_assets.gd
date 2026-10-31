extends RefCounted
## ASSETS bot: drops every model into the REAL night city (the main scene: world, atmosphere, player) and cycles through look-dev views,
## so the models are judged where they will be seen: readability in the dark, the emission colour code, wear, wheels and rotors. It also
## prints the draw calls and primitives of the world alone vs the world plus a firefight of 17 models at each graphics tier.
##   tools/bot.sh res://tests/bot_assets.gd /tmp/assets_city 40 12      (12 screenshots, one every 40 frames; look at the PNGs)
##   RENDERER=compat tools/bot.sh res://tests/bot_assets.gd /tmp/assets_city_compat 40 12
## The ASSETS_BOT lines in the output carry the numbers (compare with BUDGETS.md: MED 150 draw calls / 300k triangles).

const CYCLE := 40                    ## frames per view once the stats are printed
const STATS_DONE := 80               ## the first views start here

var tree: SceneTree
var frame := 0
var built := false
var cam: Camera3D
var root: Node3D
## [camera position, look-at target, label]
var views := [
	[Vector3(-35.5, 1.7, 5.5), Vector3(-12.0, 1.4, 1.5), "road_wide"],
	[Vector3(-31.0, 1.05, 7.0), Vector3(-27.0, 0.25, 2.6), "pickups_close"],
	[Vector3(-26.0, 1.5, 9.0), Vector3(-19.0, 0.8, 5.2), "sport_car_close"],
	[Vector3(-12.0, 1.8, 7.0), Vector3(-2.0, 1.8, 0.0), "drone_sentinel_10m"],
	[Vector3(-16.0, 1.7, 3.0), Vector3(-4.0, 2.0, -1.0), "operative_drone_14m"],
	[Vector3(-4.0, 1.6, -2.0), Vector3(8.0, 1.0, -5.5), "sedan_rear_quarter"],
	[Vector3(-8.0, 2.2, -4.0), Vector3(10.0, 2.8, 2.0), "heavy_16m"],
	[Vector3(-28.0, 1.4, -1.0), Vector3(-24.0, 1.0, -3.6), "core_gem"],
	[Vector3(-21.0, 1.6, 4.4), Vector3(-18.0, 1.3, 2.2), "operative_close"],
]


func _put(model_name: String, pos: Vector3, yaw_deg: float) -> Node3D:
	var m := Game.load_model(model_name)
	if m == null:
		push_error("ASSETS_BOT missing model " + model_name)
		return null
	m.position = pos
	m.rotation_degrees.y = yaw_deg
	root.add_child(m)
	return m


func _info(tag: String) -> void:
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var pr := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	print("ASSETS_BOT %-36s frame=%d draw_calls=%d primitives=%d quality=%d" % [tag, frame, dc, pr, Game.quality])


func _build() -> void:
	root = Node3D.new()
	root.name = "AssetsBot"
	tree.current_scene.add_child(root)
	_put("operative", Vector3(-18.0, 0.0, 2.2), 90.0)
	_put("car_sport", Vector3(-20.0, 0.0, 7.0), 80.0)
	_put("car_sedan", Vector3(6.0, 0.0, -5.0), -90.0)
	_put("car_suv", Vector3(-4.0, 0.0, 6.5), -95.0)
	_put("drone_sentinel", Vector3(-5.0, 2.3, 0.5), 80.0)
	_put("drone_striker", Vector3(-9.0, 2.0, -3.0), 70.0)
	_put("drone_heavy", Vector3(11.0, 3.0, 2.0), 100.0)
	_put("pickup_health", Vector3(-28.0, 0.0, 2.0), 0.0)
	_put("pickup_energy", Vector3(-26.6, 0.0, 3.4), 0.0)
	_put("core_gem", Vector3(-24.0, 0.0, -3.5), 0.0)
	cam = Camera3D.new()
	cam.far = 2000.0
	cam.fov = 62.0
	root.add_child(cam)
	cam.make_current()


## The rest of a firefight: 6 operatives, 3 sentinels, 1 striker, 1 heavy and 6 cars in total.
func _crowd() -> void:
	for i in 5:
		_put("operative", Vector3(-24.0 + i * 3.0, 0.0, 1.5 + (i % 2) * 3.0), 90.0)
	for i in 2:
		_put("drone_sentinel", Vector3(-14.0 + i * 4.0, 2.2, -2.0 + i), 90.0)
	for i in 3:
		_put("car_sedan" if i == 0 else ("car_sport" if i == 1 else "car_suv"), Vector3(-18.0 + i * 6.5, 0.0, -6.5), -90.0)


func step(_t: float, _delta: float) -> bool:
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	frame += 1
	if not built:
		if tree.current_scene == null or not is_instance_valid(Game.world):
			return false
		built = true
		_build()
		print("ASSETS_BOT built the display set; %d views" % views.size())
		return false
	var wide: Array = views[0]
	if frame < STATS_DONE:
		cam.global_position = wide[0]
		cam.look_at(wide[1], Vector3.UP)
	cam.make_current()
	if frame == 20:
		_info("world + player + display set (10 models)")
	if frame == 21:
		_crowd()
	if frame == 30:
		_info("+ crowd: 17 models in view")
	if frame == 34:
		Game.set_quality(0)
	if frame == 44:
		_info("17 models, quality LOW")
	if frame == 46:
		Game.set_quality(2)
	if frame == 56:
		_info("17 models, quality HIGH")
	if frame == 58:
		Game.set_quality(1)
	if frame == 68:
		_info("17 models, quality MED")
	if frame >= STATS_DONE:
		var idx := int((frame - STATS_DONE) / CYCLE) % views.size()
		var v: Array = views[idx]
		cam.global_position = v[0]
		cam.look_at(v[1], Vector3.UP)
	return false
