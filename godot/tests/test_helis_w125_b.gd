extends RefCounted
## The odd half of the wave 125 helicopter flights (see test_helis_w125.gd: split to stay under the 140 s runner cap).
## Run: tools/test.sh tests/test_helis_w125_b.gd
const TIMEOUT_SECONDS := 600
const Base := preload("res://tests/test_helis_w125.gd")


func run(h: Node) -> void:
	var t := Base.new()
	t.half = 1
	await t.run(h)
