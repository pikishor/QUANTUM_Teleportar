extends "res://tests/citizen_lineup.gd"
## Render check of the citizen animation states and silhouettes (needs a GPU / software Vulkan: tools/citizen_check.sh runs it under xvfb).
## One row of the 13 archetypes with the real crowd shader; for every state a frame is captured and every archetype's column is compared:
##   - walk, talk, flee and cower look different from each other for every archetype (mean luminance difference of the column),
##   - the walk cycle moves (two phases differ), a talking person keeps moving over time,
##   - silhouettes: the sylph is the tallest, the child under 70 % of the commuter, the stocky porter has the widest width / height ratio,
##   - the far mesh draws the same row (it is not empty).
## Prints "RESULT: PASS" or "RESULT: FAIL" and exits with 0 / 1.

const WAIT := 10
const MIN_DIFF := 0.8                    ## mean absolute luminance difference (0..255) over a column's pixels

var _cam: Camera3D
var _mm: MultiMesh
var _mi: MultiMeshInstance3D
var _fails := 0
var _checks := 0


func _check(c: bool, msg: String) -> void:
	_checks += 1
	if c:
		print("ok: ", msg)
	else:
		_fails += 1
		printerr("FAIL: ", msg)


func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_lights()
	var ps := load(MODEL) as PackedScene
	var root := ps.instantiate()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if String(mi.name).begins_with("CitizenFar"):
			_far = mi.mesh
		elif String(mi.name).begins_with("Citizen"):
			_near = mi.mesh
	root.free()
	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)
	_cam.make_current()
	_cam.position = Vector3(0, 2.2, -15.0)
	_cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	_run.call_deferred()


func _set_state(state: String, far: bool, phase_shift: float = 0.0) -> void:
	if _mi != null:
		_mi.queue_free()
	_row(state, range(13), Vector3.ZERO, 0.0, far)
	_mi = get_child(get_child_count() - 1) as MultiMeshInstance3D
	_mm = _mi.multimesh
	for k in 13:
		var c: Color = custom_of(state, arch_seed(k, 0.3 * float(k % 3)), k)
		c.g += phase_shift
		_mm.set_instance_custom_data(k, c)


func _grab() -> Image:
	for i in WAIT:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_L8)
	return img


## Screen rectangle of archetype k's column.
func _column(k: int) -> Rect2i:
	var x0 := float(13 - 1) * SPACING * 0.5 - float(k) * SPACING
	var foot := _cam.unproject_position(Vector3(x0, 0.0, 0.0))
	var head := _cam.unproject_position(Vector3(x0, 2.5, 0.0))
	var half := absf(foot.y - head.y) * 0.28
	return Rect2i(int(foot.x - half), int(head.y), int(half * 2.0), int(foot.y - head.y) + 4)


func _diff(a: Image, b: Image, r: Rect2i) -> float:
	var da := a.get_data()
	var db := b.get_data()
	var w := a.get_width()
	var sum := 0.0
	var n := 0
	for y in range(maxi(r.position.y, 0), mini(r.end.y, a.get_height())):
		for x in range(maxi(r.position.x, 0), mini(r.end.x, w)):
			sum += absf(float(da[y * w + x]) - float(db[y * w + x]))
			n += 1
	return sum / float(maxi(n, 1))


## The pixel bounding box of what differs from the empty scene inside column k.
func _bbox(img: Image, empty: Image, r: Rect2i) -> Rect2i:
	var da := img.get_data()
	var de := empty.get_data()
	var w := img.get_width()
	var x0 := 1 << 20
	var x1 := -1
	var y0 := 1 << 20
	var y1 := -1
	for y in range(maxi(r.position.y, 0), mini(r.end.y, img.get_height())):
		for x in range(maxi(r.position.x, 0), mini(r.end.x, w)):
			if absi(int(da[y * w + x]) - int(de[y * w + x])) > 14:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1) if x1 >= 0 else Rect2i()


func _run() -> void:
	_set_state("walk", false)
	_mi.visible = false
	var empty: Image = await _grab()
	_mi.visible = true
	var shots := {}
	for st in ["walk", "talk", "flee", "cower"]:
		_set_state(st, false)
		shots[st] = await _grab()
	_set_state("walk", false, 1.6)
	var walk2: Image = await _grab()
	_set_state("talk", false)
	var talk_a: Image = await _grab()
	for i in 25:
		await get_tree().process_frame
	var talk_b: Image = await _grab()
	var states := ["walk", "talk", "flee", "cower"]
	var worst := 999.0
	var weak: Array[String] = []
	for k in 13:
		var r := _column(k)
		for i in states.size():
			for j in range(i + 1, states.size()):
				var d := _diff(shots[states[i]], shots[states[j]], r)
				worst = minf(worst, d)
				if d < MIN_DIFF:
					weak.append("%d %s/%s %.2f" % [k, states[i], states[j], d])
	_check(weak.is_empty(), "every archetype looks different in walk / talk / flee / cower (weakest column difference %.2f, need %.1f; weak: %s)" % [worst, MIN_DIFF, weak])
	var still := 0
	var moving := 0
	for k in 13:
		var r := _column(k)
		if _diff(shots["walk"], walk2, r) >= MIN_DIFF:
			moving += 1
		if _diff(talk_a, talk_b, r) >= 0.15:
			still += 1
	_check(moving >= 12, "the walk cycle moves: %d of 13 archetypes differ between two phases" % moving)
	_check(still >= 10, "a talking person keeps moving over time: %d of 13 archetypes changed" % still)
	# silhouettes from the walking frame
	var box: Array[Rect2i] = []
	for k in 13:
		box.append(_bbox(shots["walk"], empty, _column(k)))
	var tallest := 0
	var smallest := 0
	var widest := 0
	for k in 13:
		print("archetype %d: %d x %d px" % [k, box[k].size.x, box[k].size.y])
		if box[k].size.y > box[tallest].size.y:
			tallest = k
		if box[k].size.y < box[smallest].size.y:
			smallest = k
		if float(box[k].size.x) / float(maxi(box[k].size.y, 1)) > float(box[widest].size.x) / float(maxi(box[widest].size.y, 1)):
			widest = k
	_check(tallest == 6, "the sylph (6) is the tallest on screen (tallest = %d)" % tallest)
	_check(smallest == 12 and box[12].size.y < int(0.7 * float(box[0].size.y)), "the child (12) is the smallest, %d px vs the commuter's %d px" % [box[12].size.y, box[0].size.y])
	_check(widest == 7 or widest == 8 or widest == 9, "a wide archetype has the widest width / height ratio (%d)" % widest)
	var distinct := {}
	for k in 13:
		distinct["%d/%d" % [roundi(box[k].size.x / 4.0), roundi(box[k].size.y / 4.0)]] = true
	_check(distinct.size() >= 9, "at least 9 different silhouette sizes on screen (%d)" % distinct.size())
	# the far mesh draws the row too
	_set_state("walk", true)
	var far_img: Image = await _grab()
	var covered := 0
	for k in 13:
		if _diff(far_img, empty, _column(k)) >= 0.5:
			covered += 1
	_check(covered == 13, "the far mesh draws all 13 archetypes (%d)" % covered)
	if OS.get_environment("QT_SAVE") != "":
		for st in shots.keys():
			(shots[st] as Image).save_png("%s_%s.png" % [OS.get_environment("QT_SAVE"), st])
	print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d of %d checks)" % [_fails, _checks])
	get_tree().quit(0 if _fails == 0 else 1)
