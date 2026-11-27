extends RefCounted
## Part 2 of the wave 127 military ground vehicles (see test_tanks_w127.gd: split to stay under the 140 s runner cap): the odd kinds of TankRoster.NEW.
## Run: tools/test.sh tests/test_tanks_w127_b.gd
const TIMEOUT_SECONDS := 600
const Base := preload("res://tests/test_tanks_w127.gd")


func run(h: Node) -> void:
	var t := Base.new()
	t.part = 1
	await t.run(h)
