extends RefCounted
## WAVE 127 TANK CREWS AND TANK MISSIONS by real fingers: the second half of tests/test_tank_arms_w127.gd (see its header; split to stay under the 140 s runner cap): an enemy tank crew
## engages the hero's tank and is destroyed by it, the ARMY AIRBASE crew, a tank at 4 stars, and TANK BATTLE starts from a finger on
## the board card in the ARMY YARD and is finished by the bot (CONVOY ESCORT and ARTILLERY STRIKE: tests/test_tank_arms_w127_c.gd). W127A_OLD=1: the checks marked [old fails] fail.
## Run: tools/test.sh tests/test_tank_arms_w127_b.gd
const TIMEOUT_SECONDS := 140
const Base := preload("res://tests/test_tank_arms_w127.gd")


func run(h: Node) -> void:
	var t = Base.new()
	t.parts_default = "crews,battle"
	await t.run(h)
