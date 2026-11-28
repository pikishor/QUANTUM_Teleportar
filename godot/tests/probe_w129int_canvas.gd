extends "res://tests/test_airfield_perf_w129.gd"
## w129-integrator scratch probe (deleted before commit): what the canvas draws are made of in a view.

func _cv() -> int:
	var rid := host.get_viewport().get_viewport_rid()
	var m := 0
	for i in 4:
		await _f(1)
		m = maxi(m, RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
	return m

func _measure(view: String, settle := 45) -> void:
	await _f(settle)
	var base: int = await _cv()
	print("CV %s base %d" % [view, base])
	var layers: Array = []
	for c in host.get_tree().root.find_children("*", "CanvasLayer", true, false):
		if (c as CanvasLayer).visible:
			layers.append(c)
	for l in layers:
		var items: Array = []
		for ch in (l as Node).find_children("*", "CanvasItem", true, false):
			if (ch as CanvasItem).is_visible_in_tree():
				items.append(ch)
		if items.is_empty():
			continue
		print("CV %s layer %s (%d) items %d" % [view, (l as Node).get_path(), (l as CanvasLayer).layer, items.size()])
		for ch in items:
			if ch.get_parent() == l or ch.get_parent().get_parent() == l:
				var b0: int = await _cv()
				(ch as CanvasItem).visible = false
				var b1: int = await _cv()
				(ch as CanvasItem).visible = true
				print("CV %s    %s [%s] %d -> %d" % [view, (l as Node).get_path_to(ch), ch.get_class(), b0, b1])
	var e0: int = await _cv()
	FlightHud.enabled = false
	var e1: int = await _cv()
	FlightHud.enabled = true
	print("CV %s flighthud %d -> %d ; labels %s" % [view, e0, e1, str(FlightHud.labels)])
