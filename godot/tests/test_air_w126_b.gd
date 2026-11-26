extends RefCounted
## WAVE 126 AIR MISSIONS by real fingers: the second half of tests/test_air_w126.gd (see its header; split to stay under the 140 s runner cap): the six air missions come up on the
## Mission Board at the airport, start from a finger on the card (the board opened from the pause button) and are finished by the bot (ENTER, FIRE, BOMB, DROP, DOWN are fingers on the
## drawn buttons). W126A_OLD=1: the checks marked [old fails] fail (no air mission on the board).
## Run: tools/test.sh tests/test_air_w126_b.gd
const TIMEOUT_SECONDS := 140
const Base := preload("res://tests/test_air_w126.gd")


func run(h: Node) -> void:
	var t = Base.new()
	t.parts_default = "missions"
	await t.run(h)
