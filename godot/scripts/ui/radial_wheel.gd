class_name RadialWheel
extends RefCounted
## A radial pick wheel for the phone HUD (ABILITY and WEAPON). Pure data and geometry: TouchControls feeds it fingers and draws it. It never pauses the game.
## Open it by holding a button and dragging (release on a wedge to pick) or by a short tap (it stays open: tap a disc to pick, tap anywhere else to close).

const RADIUS := 195.0               ## base px: wheel centre to a disc centre
const ITEM_R := 56.0                ## base px: disc radius (a 112 px target, above the 64 px touch rule)
const EDGE := 8.0                   ## base px kept clear between a disc and the screen edge
const DEAD := 0.45                  ## fraction of RADIUS inside which a released drag picks nothing
const TAP_TIME := 0.25              ## seconds: a press that ends sooner than this (and barely moved) leaves the wheel open

var is_open := false
var sticky := false                 ## opened by a tap: stays until a pick or a tap outside
var kind: StringName = &""          ## &"ability" or &"weapon"
var items: Array = []               ## {id: StringName, label: String, ready: bool, active: bool, cd: float 0..1}
var sel := -1                       ## the wedge the dragging finger is over (-1 none)
var centre := Vector2.ZERO          ## canvas px: the thumb (the button that opened the wheel); the discs are laid out around it
var scale := 1.0
var angles := PackedFloat32Array()  ## the screen angle (radians, 0 = right, clockwise) of every disc: a full circle when it fits, else the free arc around the thumb
var span_deg := 360.0               ## the angle the discs cover (less than 360 when the thumb is near a screen edge)


## Opens the wheel around `at` (canvas px, the thumb). `bounds` (canvas px, optional) is where a disc may sit: the discs fill a full circle when it fits and otherwise the widest
## free arc around the thumb, so a wheel opened near the bottom or the side of the screen fans out over the free side instead of running off the screen or over the other buttons.
func open_at(k: StringName, list: Array, at: Vector2, s: float, tap := false, bounds := Rect2()) -> void:
	kind = k
	items = list
	centre = at
	scale = s
	sticky = tap
	sel = -1
	is_open = not list.is_empty()
	_layout(bounds)


func _layout(bounds: Rect2) -> void:
	var n := items.size()
	angles = PackedFloat32Array()
	span_deg = 360.0
	if n == 0:
		return
	var full := PackedFloat32Array()
	for i in n:
		full.append(-PI * 0.5 + TAU * float(i) / float(n))
	if bounds.size == Vector2.ZERO or n < 2:
		angles = full
		return
	var rad := RADIUS * scale
	var ok := true
	for a in full:
		if not bounds.has_point(centre + Vector2.from_angle(a) * rad):
			ok = false
	if ok:
		angles = full
		return
	var step := 1.0                                                  # degrees: find the longest run of free directions around the thumb
	var free := PackedByteArray()
	for d in 360:
		free.append(1 if bounds.has_point(centre + Vector2.from_angle(deg_to_rad(float(d) * step - 180.0)) * rad) else 0)
	var best_len := 0
	var best_start := 0
	for d0 in 360:
		if free[d0] == 0 or free[(d0 + 359) % 360] == 1:
			continue                                                 # not the start of a run
		var len := 0
		while len < 360 and free[(d0 + len) % 360] == 1:
			len += 1
		if len > best_len:
			best_len = len
			best_start = d0
	if best_len == 0:                                                # no free direction at all: keep the circle (the caller clamps the centre)
		angles = full
		return
	var span := float(best_len - 1)
	var per := span / float(n - 1)
	span_deg = span
	var a0 := float(best_start) * step - 180.0
	for i in n:
		angles.append(deg_to_rad(a0 + per * float(i)))


## The least angle (degrees) between two neighbouring discs for them not to touch at RADIUS.
static func min_step_deg() -> float:
	return rad_to_deg(2.0 * asin(minf(ITEM_R * 2.0 / (2.0 * RADIUS), 0.99)))


func close() -> void:
	is_open = false
	sticky = false
	sel = -1
	items = []
	angles = PackedFloat32Array()


## Canvas position of the centre of disc `i`: a full circle starts straight up and runs clockwise; a fan starts at its free end.
func item_angle(i: int) -> float:
	if i >= 0 and i < angles.size():
		return angles[i]
	var n := maxi(items.size(), 1)
	return -PI * 0.5 + TAU * float(i) / float(n)


func item_centre(i: int) -> Vector2:
	return centre + Vector2.from_angle(item_angle(i)) * RADIUS * scale


## The disc under `pos` (a tap), or -1.
func hit(pos: Vector2) -> int:
	for i in items.size():
		if pos.distance_to(item_centre(i)) <= ITEM_R * scale * 1.1:
			return i
	return -1


## The wedge a dragging finger points at: -1 inside the dead zone, else the disc nearest the drag direction.
func wedge(pos: Vector2) -> int:
	var d := pos - centre
	if items.is_empty() or d.length() < RADIUS * scale * DEAD:
		return -1
	var best := -1
	var best_d := 1.0e9
	for i in items.size():
		var da := absf(angle_difference(d.angle(), item_angle(i)))
		if da < best_d:
			best_d = da
			best = i
	return best


func item_id(i: int) -> StringName:
	return StringName(items[i]["id"]) if i >= 0 and i < items.size() else &""
