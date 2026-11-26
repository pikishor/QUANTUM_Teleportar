extends RefCounted
## Part 1 of the wave 126 aeroplane flights (see test_planes_w126.gd: split to stay under the 140 s runner cap).
## Run: tools/test.sh tests/test_planes_w126_b.gd
const TIMEOUT_SECONDS := 600
const Base := preload("res://tests/test_planes_w126.gd")


func run(h: Node) -> void:
	var t := Base.new()
	t.part = 1
	await t.run(h)
