class_name ShaderWarmup
extends RefCounted
## Shader / material / texture pre-warm. The first time a material is drawn the renderer compiles its pipeline (and a model's textures are uploaded the first time it is
## instantiated), which shows up as a frame that takes 20-300 ms: the first shot, the first blast, the first enemy to come into view. `ShaderWarmup.run(host)` makes that
## happen once, behind the loading overlay (main.gd awaits it before the overlay finishes; tools and tests skip it under Game.autostart unless they call it):
##   * one enemy of every type (models, textures, drone Body / Fins / Eye, the trooper's skinned body and its shadow proxy) and every kind of car, shown for 3 frames
##     with their marks lit (threat ring, muzzle flare, aim line, health bar);
##   * the FX pools: spark burst, tracer, muzzle flash, an explosion of each style (fire, quantum collapse, burning wreck);
##   * everything the quantum module keeps hidden until used (beacon, ghost, links): its hidden meshes are shown at the warm point for the same 3 frames;
##   * the UI text: the HUD font at every size the layouts use is drawn once, so the first menu / tutorial / radio line does not rasterise glyphs on the spot.
## Everything sits 8 m in front of the gameplay camera (inside the frustum, so it is really drawn), behind the opaque overlay, then it is hidden, released and restored.
## Nothing here changes game state: enemies and cars go back to their pools, FX.reset() hides the effects, moved nodes get their transform and visibility back.

const FRAMES := 3
const DISTANCE := 8.0
const GLYPHS := " ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.,:;!?'\"-+/%()[]<>=*#&@_·→←"
const UI_SIZES := [14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 36, 40, 46, 56, 72]

static var done := false                 ## the warm-up was started in this process (it runs once)
static var finished := false             ## ... and has put everything back (the first-use probe waits for it)


## Run the whole warm-up; returns what it did ({items, ms}). `host` is any node in the tree (it awaits its frames).
static func run(host: Node, force := false) -> Dictionary:
	if done and not force:
		return {"items": 0, "ms": 0, "skipped": true}
	done = true
	finished = false
	var t0 := Time.get_ticks_msec()
	var tree := host.get_tree()
	var cam := Game.camera
	if not is_instance_valid(cam):
		finished = true
		return {"items": 0, "ms": 0, "no_camera": true}
	var at := cam.global_position - cam.global_basis.z * DISTANCE
	var ground := Vector3(at.x, 0.0, at.z)
	var items := 0
	var state: Array = []                                             # [node, visible, global transform] to restore
	var enemies: Array[Drone] = []
	var cars: Array[Vehicle] = []
	var em := Game.enemies as EnemyManager
	if em != null:
		enemies = em.warm_begin(ground)
		items += enemies.size()
	var vm := Game.vehicles as VehicleManager
	if vm != null:
		cars = vm.warm_begin(ground + Vector3(0.0, 0.0, 6.0))
		items += cars.size()
	items += _warm_fx(at)
	items += _warm_hidden(_quantum_root(), at, state)
	var ui := _warm_ui(host)
	items += 1 if ui != null else 0
	for i in FRAMES:
		await tree.process_frame
	# put everything back
	if is_instance_valid(ui):
		ui.queue_free()                                              # the layer and its control
	for e in state:
		var n: Node3D = e[0]
		if is_instance_valid(n):
			n.visible = e[1]
			n.global_transform = e[2]
	if em != null:
		em.warm_end(enemies)
	if vm != null:
		vm.warm_end(cars)
	FX.reset()
	finished = true
	return {"items": items, "ms": Time.get_ticks_msec() - t0}


## The pooled effects of FX: a burst, a tracer with its muzzle flash, and an explosion of every style.
static func _warm_fx(at: Vector3) -> int:
	FX.burst(at, Color(1.0, 0.8, 0.4), 8, 3.0, 0.4, 2.0, 1.0)
	FX.burst(at, Color(0.9, 0.8, 0.7), 6, 2.0, 0.4, 1.0, 6.0)
	FX.tracer(at + Vector3(-1.5, 0.0, 0.0), at + Vector3(1.5, 0.3, 0.0))
	FX.muzzle_flash(at + Vector3(0.0, 0.5, 0.0), Vector3.RIGHT)
	FX.blast(at + Vector3(-3.0, 0.0, 0.0), 3.0, Color(1.0, 0.5, 0.15), 0.5)                 # fire
	FX.blast(at + Vector3(3.0, 0.0, 0.0), 3.0, Color(0.3, 0.94, 1.0), 0.5)                  # quantum collapse
	FX.blast(at + Vector3(0.0, 0.0, -3.0), 9.0, Color(1.0, 0.5, 0.15), 0.5, FX.ExplosionPool.STYLE_WRECK, 0.5)   # burning wreck
	return 7


static func _quantum_root() -> Node3D:
	var p := Game.player
	if not is_instance_valid(p):
		return null
	var q: Variant = p.get(&"quantum")
	if q is Node and is_instance_valid(q):
		var r: Variant = (q as Node).get(&"fx_root")
		if r is Node3D and is_instance_valid(r):
			return r as Node3D
	return null


## Show every hidden mesh below `root` at `at` for the warm-up frames (the originals are recorded in `state` and restored by run()).
static func _warm_hidden(root: Node3D, at: Vector3, state: Array) -> int:
	if root == null:
		return 0
	var n := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var g := node as GeometryInstance3D
		if g == null or g.visible or g is CPUParticles3D:
			continue
		# the node and the hidden ancestors up to the root must be visible to be drawn
		var chain: Array[Node3D] = [g]
		var a: Node = g.get_parent()
		while a is Node3D and a != root.get_parent():
			if not (a as Node3D).visible:
				chain.append(a as Node3D)
			a = a.get_parent()
		for c in chain:
			state.append([c, c.visible, c.global_transform])
			c.visible = true
		g.global_position = at
		n += 1
	return n


## A hidden control that draws the glyphs of the HUD font at every layout size (the glyph atlas is filled before the first menu).
static func _warm_ui(host: Node) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 99
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(c)
	var font := UiUtil.font()
	var vp := host.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	c.draw.connect(func() -> void:
		var y := 0.0
		for sz: int in UI_SIZES:
			var px := maxi(8, int(round(float(sz) * s)))
			c.draw_string(font, Vector2(0.0, y + px), GLYPHS, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, Color(1, 1, 1, 0.01))
			y += px * 1.2)
	host.add_child(layer)
	c.queue_redraw()
	return layer
