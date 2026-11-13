extends RefCounted
## Dev helper (not a test): every scattered instance (all layers) within R metres of a point, with its species and the distance to the nearest road. tools/test.sh tests/dev_veg_probe.gd (VP_X, VP_Z, VP_R)
const TIMEOUT_SECONDS := 100


func run(_host: Node) -> void:
	TerrainHeight.warm()
	var x := float(OS.get_environment("VP_X")) if OS.get_environment("VP_X") != "" else 1748.5
	var z := float(OS.get_environment("VP_Z")) if OS.get_environment("VP_Z") != "" else 563.2
	var r := float(OS.get_environment("VP_R")) if OS.get_environment("VP_R") != "" else 3.0
	for layer in 7:
		for ci in range(int(floor((x - r) / VegScatter.CELL)), int(floor((x + r) / VegScatter.CELL)) + 1):
			for cj in range(int(floor((z - r) / VegScatter.CELL)), int(floor((z + r) / VegScatter.CELL)) + 1):
				var arr := VegScatter.cell(layer, ci, cj)
				for k in arr.size() / VegScatter.STRIDE:
					var o := k * VegScatter.STRIDE
					var d := Vector2(arr[o] - x, arr[o + 2] - z).length()
					if d <= r:
						var nr := TerrainRoads.nearest(arr[o], arr[o + 2])
						print("VEGPROBE layer %d at (%.1f, %.1f, %.1f) species %d scale %.2f variant %.2f; nearest road %s at %.1f m" % [layer, arr[o], arr[o + 1], arr[o + 2], int(arr[o + 5]), arr[o + 4], arr[o + 6], str(nr[1]), float(nr[0])])
