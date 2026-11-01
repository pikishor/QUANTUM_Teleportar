extends Node3D
## A flat Game.world stand-in for the weapon tests: road queries, ground height 0, the real junction list.

var intersections: Array[Vector3] = CityLayout.make_intersections()


func random_road_point() -> Vector3:
	return Vector3(float(randi_range(-3, 3)) * 80.0 + 5.0, 0.0, randf_range(-280.0, 280.0))


func road_point_near(center: Vector3, rmin: float, rmax: float) -> Vector3:
	var a := randf() * TAU
	var r := randf_range(rmin, rmax)
	return Vector3(center.x + cos(a) * r, 0.0, center.z + sin(a) * r)


func ground_height(_x: float, _z: float, _from := 0.0) -> float:
	return 0.0
