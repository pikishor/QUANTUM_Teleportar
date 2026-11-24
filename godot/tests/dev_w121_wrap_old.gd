extends RefCounted
## w121-critic: runs tests/test_floors_w121.gd with the critic's fixes off (dev only).
const TIMEOUT_SECONDS := 150
func run(h: Node) -> void:
	TowerFloors.critic_on = false
	PlayerBody.fade_all_on = false
	HeroVerbs.ceiling_stop = false
	var t = load("res://tests/test_floors_w121.gd").new()
	await t.run(h)
