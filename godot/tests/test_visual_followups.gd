extends RefCounted
## Visual QA follow-ups: street brightness / crowd rules in VisualQaLib, vehicle paint finish, HUD shard plate on screen, look and garage layouts at
## 844x390 and 1280x720. Run: tools/test.sh tests/test_visual_followups.gd

const SIZES: Array[Vector2] = [Vector2(844, 390), Vector2(1280, 720)]


func run(_host: Node) -> void:
	# QA rules
	var dark := {"mean": 0.05, "contrast": 0.1, "black": 0.1}
	var ok := {"mean": 0.2, "contrast": 0.1, "black": 0.1}
	TestLib.check(VisualQaLib.verdict(dark, -1.0, 10).contains("too dark"), "a dark street fails")
	TestLib.check(VisualQaLib.verdict(ok, -1.0, 0).contains("empty"), "an empty street fails")
	TestLib.check(VisualQaLib.verdict(ok, -1.0, 6) == "", "a lit street with people passes")
	TestLib.check(VisualQaLib.verdict(ok) == "", "non-street spots ignore the street rules")
	# paint: lacquer is no longer matte
	TestLib.check(VehicleVisual.PAINT_ROUGH_MAX <= 0.55 and VehicleVisual.PAINT_ROUGH_MIN < VehicleVisual.PAINT_ROUGH_MAX, "paint roughness range is glossy")
	TestLib.check(VehicleVisual.PAINT_RIM > 0.0, "paint has a grazing sheen")
	# crowd near count
	var cr := preload("res://scripts/ambient/ambient_crowd.gd").new()
	TestLib.check(cr.COUNTS[1] >= 50 and cr.COUNTS[0] <= 48 and cr.COUNTS[1] > cr.COUNTS[0], "MED crowd is denser, LOW unchanged")
	# look screen buttons inside the screen
	var old = Game.progress
	Game.progress = Progress.new()
	for vp in SIZES:
		var s := UiUtil.ui_scale(vp)
		var hud := Hud.new()
		LookScreen.layout(hud, vp.x * 0.5, s)
		TestLib.check(hud.buttons.size() > 5, "look screen has buttons at %s" % vp)
		var inside := true
		for b in hud.buttons:
			var r: Rect2 = b["rect"]
			if r.position.x < -1.0 or r.position.y < -1.0 or r.end.x > vp.x + 1.0 or r.end.y > vp.y + 1.0:
				inside = false
				print("look button off screen: ", b["id"], " ", r)
		TestLib.check(inside, "look screen buttons inside %s" % vp)
		hud.free()
	Game.progress = old
	# garage panel fits
	var g := GarageScreen.new()
	g._ready()
	for vp in SIZES:
		var k := g.fit(vp)
		var sz := g._box.size * k
		TestLib.check(k <= 1.0 and 840.0 * k <= vp.x and 600.0 * k <= vp.y, "garage panel fits %s (scale %.2f)" % [vp, k])
		if vp.x > 1200.0:
			TestLib.check(k == 1.0, "garage keeps full size at 1280x720")
	g.free()
