class_name InteriorPrompts
extends Control
## The floating prompts of a room (InteriorTasks.items): a plate with plain words over the safe, the terminal, the hostage, the vendor, the gate and the exit, projected from the 3D room
## through the real camera. The one USE would do right now is brighter and says USE; the objective that is off screen (or far) gets an arrow on the screen edge with its distance.
## Sizes follow the HUD (UiUtil.ui_scale, label 22 px / prompt 26 px at 720 p). Drawn only while an interior is active and the game is in play; a LOW tier redraws at the HUD's own interval.

const MAX_PLATES := 6
const EDGE := 64.0                         ## base px: how far from the screen edge the objective arrow sits

var tasks: InteriorTasks
static var active_shown := false           ## the plate of the action USE does is on screen (the HUD's own bottom hint then stays quiet: one sentence, not three)

var plates: Array[Dictionary] = []         ## what was drawn last frame: [{rect, label, id, active, edge}] (tests read it)
var _t := 0.0


func _ready() -> void:
	name = "InteriorPrompts"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	var on := tasks != null and InteriorGameplay.active and Game.state == &"play" and not InteriorGameplay.vendor_open and not MapScreen.up
	if not on:
		active_shown = false
		if visible:
			visible = false
			plates.clear()
		return
	visible = true
	_t += delta
	if _t >= maxf(LowPlus.hud_interval(), 1.0 / 30.0):
		_t = 0.0
		queue_redraw()


func _draw() -> void:
	plates.clear()
	active_shown = false
	if tasks == null or not InteriorGameplay.active or Game.state != &"play":
		return
	var cam := get_viewport().get_camera_3d()
	var p := Game.player as Node3D
	if cam == null or p == null:
		return
	var vp := get_viewport_rect().size
	var s := UiUtil.ui_scale(vp)
	var font := UiUtil.font()
	var pp := p.global_position
	var now := tasks.best(pp)
	var now_kind: StringName = StringName(str(now.get("action", "")))
	var placed: Array[Rect2] = []
	var drawn := 0
	var objective := tasks.objective()
	for it: Dictionary in tasks.items:
		if drawn >= MAX_PLATES:
			break
		var pos: Vector3 = it["pos"]
		var flat := Vector2(pos.x - pp.x, pos.z - pp.z).length()
		var is_obj := bool(it.get("objective", false))
		var active := _is_active(it, now_kind)
		var anchor: Vector3 = pos + Vector3(0.0, float(it.get("height", 2.0)), 0.0)
		var behind := cam.is_position_behind(anchor)
		var sp := cam.unproject_position(anchor)
		var inside := not behind and Rect2(Vector2(40.0, 40.0) * s, vp - Vector2(80.0, 80.0) * s).has_point(sp)
		if flat > _range_for(it) and not is_obj:
			continue
		if not inside:
			if is_obj and it == objective:
				_edge_arrow(behind, sp, vp, s, font, flat, it["color"], str(it["label"]))
			continue
		var label := Tr.t(str(it["label"]))
		if active:
			label = Tr.t(str(now["prompt"]))
		var size := int(float(UiUtil.TEXT_MIN if active else UiUtil.BAR_LABEL) * s)
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x + 36.0 * s
		var h := float(size) * 1.5 + 6.0 * s
		var r := Rect2(sp.x - w * 0.5, sp.y - h - 10.0 * s, w, h)
		var guard := 0
		while guard < 6 and _hits(placed, r):
			r.position.y -= h + 4.0 * s                                  # a plate that would sit on another climbs above it
			guard += 1
		r.position.x = clampf(r.position.x, 12.0 * s, vp.x - w - 12.0 * s)
		r.position.y = maxf(r.position.y, (UiUtil.stack_bottom + 8.0) * s)       # never over the HUD's priority line
		placed.append(r)
		var col: Color = it["color"]
		var fade := 1.0 if (active or is_obj) else clampf((_range_for(it) - flat) / 4.0, 0.35, 1.0)
		draw_rect(r, Color(0.0, 0.03, 0.05, 0.72 * fade))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 3.0 * s)), Color(col, (1.0 if active else 0.75) * fade))
		draw_rect(r, Color(col, (0.9 if active else 0.35) * fade), false, (2.5 if active else 1.0) * s)
		draw_string(font, r.position + Vector2(1.5, size * 1.12 + 3.0 * s) * 1.0, label, HORIZONTAL_ALIGNMENT_CENTER, w, size, Color(0, 0, 0, 0.8 * fade))
		draw_string(font, r.position + Vector2(0.0, size * 1.12 + 2.0 * s), label, HORIZONTAL_ALIGNMENT_CENTER, w, size, Color(1, 1, 1, 0.98 * fade) if not active else Color(1, 0.95, 0.7, 1.0))
		# the pointer: a small triangle from the plate down to the object
		var tip := Vector2(sp.x, sp.y - 2.0 * s)
		var bx := clampf(sp.x, r.position.x + 12.0 * s, r.end.x - 12.0 * s)
		draw_colored_polygon(PackedVector2Array([Vector2(bx - 8.0 * s, r.end.y), Vector2(bx + 8.0 * s, r.end.y), tip]), Color(col, 0.85 * fade))
		plates.append({"rect": r, "label": label, "id": it["id"], "active": active, "edge": false})
		if active:
			active_shown = true
		drawn += 1


func _range_for(it: Dictionary) -> float:
	return InteriorTasks.SHOW_RANGE + (6.0 if it["kind"] == &"exit" else 0.0)


static func _hits(list: Array[Rect2], r: Rect2) -> bool:
	for o: Rect2 in list:
		if o.grow(2.0).intersects(r):
			return true
	return false


## The item USE would act on (`now_kind` is the InteriorTasks action): the plate shows the prompt and is bright.
func _is_active(it: Dictionary, now_kind: StringName) -> bool:
	match now_kind:
		&"gate": return it["kind"] == &"gate"
		&"mission": return it["kind"] == &"job"
		&"stealth": return it["kind"] == &"stealth"
		&"heist": return it["kind"] == &"heist"
		&"vendor": return it["kind"] == &"vendor"
		&"exit": return it["kind"] == &"exit"
	return false


func _edge_arrow(behind: bool, sp: Vector2, vp: Vector2, s: float, font: Font, flat: float, col: Color, label: String) -> void:
	var mid := vp * 0.5
	var dir := sp - mid
	if behind:
		dir = -dir
		if dir.length() < 1.0:
			dir = Vector2(0.0, 1.0)
	dir = dir.normalized()
	var half := vp * 0.5 - Vector2(EDGE, EDGE) * s
	var k := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	var at := mid + dir * k
	var side := Vector2(-dir.y, dir.x)
	var sz := 22.0 * s
	draw_colored_polygon(PackedVector2Array([at + dir * sz, at - dir * sz * 0.6 + side * sz * 0.7, at - dir * sz * 0.6 - side * sz * 0.7]), Color(col, 0.95))
	var size := int(float(UiUtil.BAR_LABEL) * s)
	var text := "%s  %d M" % [Tr.t(label), roundi(flat)]
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x + 28.0 * s
	var h := float(size) * 1.5
	var r := Rect2(at - dir * (sz * 1.6) - Vector2(w * 0.5, h * 0.5), Vector2(w, h))
	r.position.x = clampf(r.position.x, 230.0 * s, vp.x * 0.6 - w)          # clear of the minimap column and of the button clusters on the right
	r.position.y = clampf(r.position.y, 190.0 * s, vp.y - h - 8.0 * s)
	draw_rect(r, Color(0.0, 0.03, 0.05, 0.72))
	draw_rect(r, Color(col, 0.8), false, 1.5 * s)
	draw_string(font, r.position + Vector2(0.0, size * 1.12), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, Color(1, 1, 1, 0.98))
	plates.append({"rect": r, "label": text, "id": &"edge", "active": false, "edge": true})
