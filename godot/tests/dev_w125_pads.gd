extends RefCounted
## w125-pads dev: prints every helipad (no checks).
const TIMEOUT_SECONDS := 120
func run(h: Node) -> void:
	for p in Helipads.all():
		print("PAD %s | %s | %s | %s | r %.1f | %s | spawn %s kind %s" % [p["id"], p["name"], p["role"], str(p["pos"]), float(p["r"]), p["src"], p["spawn"], Helipads.kind_for(p["role"])])
	print("POINTS ", Helipads.vehicle_points().size(), " MARKERS ", Helipads.map_markers().size())
