extends RefCounted
## Dev probe (wave 114): writes class, family, kind and sound set of every weapon to /tmp/weapon_snd.json. Not a test.
func run(_h: Node) -> void:
	var out := {}
	for id in WeaponDefs.all_ids():
		var d := WeaponDefs.def(id)
		out[String(id)] = {"cls": String(WeaponDefs.class_of(id)), "fam": String(WeaponDefs.family_of(id)), "snd": String(d.get("snd", "")), "kind": String(d.get("kind", "")), "layer": String(d.get("layer", "")), "vol": d.get("vol", 0.0), "name": String(d.get("name", "")), "pl": d.get("pitch_lo", 1.0), "ph": d.get("pitch_hi", 1.0)}
	var f := FileAccess.open("/tmp/weapon_snd.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	print("DUMPED ", out.size())
