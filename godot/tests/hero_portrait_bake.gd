extends Node
## Bakes the hero portraits through HeroShowcase (wave 112, not part of the test suite): tools/hero/bake_portraits.sh runs it under xvfb and converts the PNGs to WebP.
##   args: out=<dir> (PNG output, default /tmp/hero_portraits)  suits=standard,stealth,...  yaw=0.5  kind=bust|waist|full  size=384x480  look=male:dark:parted:0:standard:0 (body:skin:hair:beard:suit:scheme)
## Writes hero_portrait.png (the default hero, bust) and hero_suit_<id>.png (waist framing, one per suit); with look= it renders that one look as look.png.

var _args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			_args[kv[0]] = kv[1]
	HeroShowcase.freeze = true
	await get_tree().process_frame
	var out := String(_args.get("out", "/tmp/hero_portraits"))
	DirAccess.make_dir_recursive_absolute(out)
	var sc := HeroShowcase.of(self)
	var yaw := float(_args.get("yaw", "0.5"))
	if _args.has("look"):
		var p := String(_args["look"]).split(":")
		var lk := HeroLook.new()
		lk.body = StringName(p[0])
		lk.skin_tone = StringName(p[1])
		lk.hair = StringName(p[2])
		lk.beard = p[3] == "1"
		lk.suit = StringName(p[4])
		lk.scheme = int(p[5])
		if p.size() > 6:
			lk.accent_hue = int(p[6])
		await _one(sc, lk, StringName(String(_args.get("kind", "bust"))), yaw, out + "/look.png", _size())
	else:
		var base := HeroLook.new()
		await _one(sc, base, &"bust", yaw, out + "/hero_portrait.png", HeroPortrait.SIZE)
		var ids := String(_args.get("suits", "standard,stealth,assault,flight,gilded,phase")).split(",", false)
		for id in ids:
			var lk2 := HeroLook.new()
			lk2.suit = StringName(id)
			var y2 := yaw + (PI if (id == "flight" and _args.has("flightback")) else 0.0)
			await _one(sc, lk2, StringName(String(_args.get("kind", "waist"))), y2, "%s/hero_suit_%s.png" % [out, id], HeroPortrait.THUMB)
	print("BAKE DONE ", out)
	get_tree().quit()


func _size() -> Vector2i:
	var p := String(_args.get("size", "384x480")).split("x")
	return Vector2i(int(p[0]), int(p[1]))


func _one(sc: HeroShowcase, lk: HeroLook, kind: StringName, yaw: float, path: String, size: Vector2i) -> void:
	var img := await sc.capture(lk, kind, yaw, 8)
	if img == null:
		print("BAKE no image for ", path)
		return
	var comp := HeroPortrait.compose(img, lk.accent(), size) if kind != &"full" else img
	comp.save_png(path)
	print("BAKE ", path, " ", comp.get_size(), " tris ", sc.info.get("tris", "?"))
