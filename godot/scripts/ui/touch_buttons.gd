class_name TouchButtons
extends Node
## Makes every plain Button answer a finger. `emulate_mouse_from_touch` is off in this project (the sticks and the look pad need real touches), and a Godot Button only answers the
## mouse: so on a phone the map's CLOSE / MISSIONS / ZOOM / filter chips, the garage, the fast-travel list and even the watchdog's rescue BACK never fired (owner rounds 4 to 7:
## "opening the map, no back button works"). The desktop tests clicked them with a mouse and passed. This node sits last under the root, so it sees a touch before anything else:
## a press on a visible, enabled button is taken, and the lift on the same button presses it (a toggle flips first). Nothing else gets that touch.

static var presses := 0                       ## buttons pressed by a finger (tests)
var _held := {}                               ## finger index -> BaseButton


static func ensure(tree: SceneTree) -> void:
	if tree.root.get_node_or_null("TouchButtons") == null:
		var n := TouchButtons.new()
		n.name = "TouchButtons"
		n.process_mode = Node.PROCESS_MODE_ALWAYS
		tree.root.add_child.call_deferred(n)


static func _layer_of(c: Node) -> int:
	var n := c
	while n != null:
		if n is CanvasLayer:
			return (n as CanvasLayer).layer
		n = n.get_parent()
	return 0


## The top-most visible, enabled button under `pos` (the highest canvas layer, then the last in tree order).
func button_at(pos: Vector2) -> BaseButton:
	var best: BaseButton = null
	var best_layer: int = -1000000
	for n in get_tree().root.find_children("*", "BaseButton", true, false):
		var b := n as BaseButton
		if b == null or b.disabled or not b.is_visible_in_tree() or b.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		if not b.get_global_rect().has_point(pos):
			continue
		var l := _layer_of(b)
		if l >= best_layer:
			best = b
			best_layer = l
	return best


func _input(event: InputEvent) -> void:
	var t := event as InputEventScreenTouch
	if t == null:
		return
	if OS.has_environment("TB_OFF"):                    # A/B switch for the test: the old behaviour (buttons deaf to a finger)
		return
	if t.pressed:
		var b := button_at(t.position)
		if b != null:
			_held[t.index] = b
			get_viewport().set_input_as_handled()
	elif _held.has(t.index):
		var b: BaseButton = _held[t.index]
		_held.erase(t.index)
		get_viewport().set_input_as_handled()
		if is_instance_valid(b) and b.is_visible_in_tree() and not b.disabled and b.get_global_rect().grow(24.0).has_point(t.position):
			press(b)


static func press(b: BaseButton) -> void:
	presses += 1
	if b.toggle_mode:
		b.button_pressed = not b.button_pressed          # emits toggled
	b.pressed.emit()


## Stay the last child of the root: input goes to the last node first, and scenes are added after this node.
func _process(_dt: float) -> void:
	var p := get_parent()
	if p != null and get_index() != p.get_child_count() - 1:
		p.move_child(self, -1)
