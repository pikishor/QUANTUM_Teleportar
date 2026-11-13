extends RefCounted
## Dev helper (not a test): the first metres of a road against the ground, the waterfalls and the pools. tools/test.sh tests/dev_summit_probe.gd   (SP_ROAD name, SP_S0, SP_S1)
const TIMEOUT_SECONDS := 100


func run(_host: Node) -> void:
	TerrainHeight.warm()
	var rn := OS.get_environment("SP_ROAD") if OS.get_environment("SP_ROAD") != "" else "SUMMIT ROAD"
	var s0 := float(OS.get_environment("SP_S0")) if OS.get_environment("SP_S0") != "" else 0.0
	var s1 := float(OS.get_environment("SP_S1")) if OS.get_environment("SP_S1") != "" else 140.0
	for f: Dictionary in LandscapeSites.falls():
		print("SUMMIT fall %s pool %s base %s lip %s drop %.0f pool_y %.1f" % [f.get("name", "?"), str(f["pool"]), str(f["base"]), str(f["lip"]), float(f["drop"]), float(f["pool_y"])])
	for r: Dictionary in TerrainRoads.roads():
		if String(r["name"]) != rn:
			continue
		var pos: PackedVector2Array = r["pos"]
		var prof: PackedFloat32Array = r["prof"]
		var i := int(s0 / TerrainRoads.STEP)
		while i < mini(int(s1 / TerrainRoads.STEP) + 1, pos.size()):
			var q := pos[i]
			var h := TerrainHeight.height_at(q.x, q.y)
			var pl := LandscapeSites.pool_level(q.x, q.y)
			var wl := TerrainHeight.water_level_at(q.x, q.y)
			var nf := LandscapeSites.near_feature(q.x, q.y, 6.0)
			print("SUMMIT s=%3d (%.0f, %.0f) profile %.2f height_at %.2f diff %.2f pool_level %s water %s near_feature %s" % [i * 10, q.x, q.y, prof[i], h, h - prof[i], str(pl), str(wl), str(nf)])
			i += 1
