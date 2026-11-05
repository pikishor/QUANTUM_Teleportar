class_name RadialWheel
extends RefCounted
## A radial pick wheel for the phone HUD (ABILITY and WEAPON). Pure data and geometry: TouchControls feeds it fingers and draws it. It never pauses the game.
## Open it by holding a button and dragging (release on a wedge to pick) or by a short tap (it stays open: tap a disc to pick, tap anywhere else to close).

const RADIUS := 195.0               ## base px: wheel centre to a disc centre
const ITEM_R := 62.0                ## base px: disc radius (a 112 px target, above the 64 px touch rule)
const DEAD := 0.45                  ## fraction of RADIUS inside which a released drag picks nothing
const TAP_TIME := 0.25              ## seconds: a press that ends sooner than this (and barely moved) leaves the wheel open

var is_open := false
var sticky := false                 ## opened by a tap: stays until a pick or a tap outside
var kind: StringName = &""          ## &"ability" or &"weapon"
var items: Array = []               ## {id: StringName, label: String, ready: bool, active: bool, cd: float 0..1}
var sel := -1                       ## the wedge the dragging finger is over (-1 none)
var centre := Vector2.ZERO          ## canvas px
var scale := 1.0


func open_at(k: StringName, list: Array, at: Vector2, s: float, tap := false) -> void:
	kind = k
	items = list
	centre = at
	scale = s
	sticky = tap
	sel = -1
	is_open = not list.is_empty()


func close() -> void:
	is_open = false
	sticky = false
	sel = -1
	items = []


## Canvas position of the centre of disc `i`: first item straight up, then clockwise.
func item_centre(i: int) -> Vector2:
	var n := maxi(items.size(), 1)
	return centre + Vector2.from_angle(-PI * 0.5 + TAU * float(i) / float(n)) * RADIUS * scale


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
	var n := items.size()
	var a := fposmod(d.angle() + PI * 0.5, TAU)
	return int(roundf(a / (TAU / float(n)))) % n


func item_id(i: int) -> StringName:
	return StringName(items[i]["id"]) if i >= 0 and i < items.size() else &""
