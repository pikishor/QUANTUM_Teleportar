extends RefCounted
## Probe: weapon tiles of the LOADOUT / catalogue at phone sizes.
const TIMEOUT_SECONDS := 120
const Audit := preload("res://tests/touch_audit_lib.gd")


func run(h: Node) -> void:
	var a := Audit.new()
	if not await a.boot(h, "probe3"):
		return
	(Game.progress as Progress).new_campaign()
	Game.state = &"play"
	await a.frames(20)
	if OS.has_environment("TA_STORY"):
		await a.goto(&"paused", ["board_open", "board_story"])
		await a.frames(10)
		print("after story: state ", Game.state)
	for size: Vector2i in [Vector2i(844, 390)]:
		a.root.size = size
		await a.frames(4)
		for path: Array in [["loadout"], ["hero_open", "hero_tab_weapons"]]:
			await a.goto(&"paused", path)
			var n := 0
			var first := {}
			for c: Dictionary in a.controls():
				if String(c["id"]).begins_with("wheel_") or String(c["id"]).begins_with("wsel_"):
					n += 1
					if first.is_empty():
						first = c
			var mode: StringName = &"loadout" if path[0] == "loadout" else &"catalogue"
			var vp := a.vp()
			var s := UiUtil.ui_scale(vp)
			print("ids ", a.controls().map(func(c: Dictionary) -> String: return c["id"]))
			print(size, " ", path, " vp ", vp, " tiles ", n, " list ", Arsenal.list(mode).size(), " list_rect ", Arsenal.list_rect, " tile0 ", Arsenal.tile_rect(vp, s, 0, 0.0), " tile1 ", Arsenal.tile_rect(vp, s, 1, 0.0), " filter ", Arsenal.st(mode)["filter"])
			if not first.is_empty():
				var w0 := a.hud._loadout_w
				var sel0 := Arsenal.selected(a.hud, mode)
				await a.tap(a.centre_of(first))
				print("   tap ", first["id"], " sel ", sel0, " -> ", Arsenal.selected(a.hud, mode), " key ", a.screen_key())
	await a.shutdown()
