extends RefCounted
## WAVE 127 TANK MISSIONS by real fingers, the third part of tests/test_tank_arms_w127.gd (see its header; split to stay under the 140 s runner cap): CONVOY ESCORT and ARTILLERY STRIKE
## come up on the Mission Board in the ARMY YARD, start from a finger on the card (the board opened from the pause button) and are finished by the bot (ENTER, FIRE, SHELL are fingers on
## the drawn buttons). W127A_OLD=1: the checks marked [old fails] fail (no tank mission on the board).
## Run: tools/test.sh tests/test_tank_arms_w127_c.gd
const TIMEOUT_SECONDS := 140
const Base := preload("res://tests/test_tank_arms_w127.gd")


func run(h: Node) -> void:
	var t = Base.new()
	t.parts_default = "convoy,artillery"
	await t.run(h)
