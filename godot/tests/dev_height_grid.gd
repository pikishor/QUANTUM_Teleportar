extends RefCounted
## Dev helper (not a test): prints a text grid of ground heights (metres, '~' = water, '#' = road) for GRID_BOX="x0,z0,x1,z1" every GRID_STEP metres. tools/test.sh tests/dev_height_grid.gd


func run(_host: Node) -> void:
	TerrainHeight.warm()
	var bp := OS.get_environment("GRID_BOX").split(",")
	if bp.size() < 4:
		print("set GRID_BOX")
		return
	var x0 := float(bp[0])
	var z0 := float(bp[1])
	var x1 := float(bp[2])
	var z1 := float(bp[3])
	var step := float(OS.get_environment("GRID_STEP")) if OS.get_environment("GRID_STEP") != "" else 100.0
	var head := "      "
	var x := x0
	while x <= x1:
		head += "%5d" % int(x)
		x += step
	print(head)
	var z := z0
	while z <= z1:
		var row := "%5d " % int(z)
		x = x0
		while x <= x1:
			var h := TerrainHeight.height_at(x, z)
			if TerrainHeight.is_water(x, z):
				row += "    ~"
			elif TerrainRoads.on_road(x, z, 2.0):
				row += "    #"
			else:
				row += "%5d" % int(roundf(h))
			x += step
		print(row)
		z += step
