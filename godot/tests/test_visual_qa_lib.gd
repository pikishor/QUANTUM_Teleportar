extends RefCounted
## Numeric helpers of the visual QA tool. Run: tools/test.sh tests/test_visual_qa_lib.gd


func _flat(c: Color) -> Image:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return img


func run(_host: Node) -> void:
	var gray := _flat(Color(0.4, 0.4, 0.4))
	var s := VisualQaLib.stats(gray, 1)
	TestLib.check(absf(float(s["mean"]) - 0.4) < 0.01, "mean of flat gray")
	TestLib.check(float(s["contrast"]) < 0.01, "flat frame has no contrast")
	TestLib.check(VisualQaLib.verdict(s) == "flat", "flat frame fails: " + VisualQaLib.verdict(s))
	var black := VisualQaLib.stats(_flat(Color.BLACK), 1)
	TestLib.check(float(black["black"]) > 0.99 and VisualQaLib.verdict(black).contains("black"), "black frame detected")
	var half := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	half.fill(Color(0.1, 0.1, 0.1))
	half.fill_rect(Rect2i(0, 0, 16, 32), Color(0.6, 0.6, 0.6))
	var hs := VisualQaLib.stats(half, 1)
	TestLib.check(float(hs["contrast"]) > 0.2 and VisualQaLib.verdict(hs) == "", "contrasty frame passes")
	TestLib.check(VisualQaLib.verdict(VisualQaLib.stats(_flat(Color.WHITE), 1)).contains("blown"), "white frame is blown out")
	var hero := half.duplicate() as Image
	hero.fill_rect(Rect2i(20, 8, 6, 16), Color(0.9, 0.9, 0.9))
	var r := VisualQaLib.separation(hero, half, 1)
	TestLib.check(int(r["n"]) == 96 and float(r["sep"]) > 0.2, "hero separation measured: %s" % [r])
	var same := VisualQaLib.separation(half, half, 1)
	TestLib.check(float(same["sep"]) == 0.0, "no hero pixels: zero separation")
	TestLib.check(VisualQaLib.verdict({"mean": 0.3, "contrast": 0.1, "black": 0.1}, 0.0).contains("hero"), "low separation fails")
