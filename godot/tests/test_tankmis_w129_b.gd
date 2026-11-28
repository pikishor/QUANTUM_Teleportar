extends "res://tests/tankmis_w129_bot.gd"
## w129-tankmis: CONVOY ESCORT played to its normal end by fingers only, stuck recovery off (see tests/test_tankmis_w129.gd for the rules). The convoy waits for the escort, then the
## trucks DRIVE the street in order (their own physics, Vehicle.scripted): they stay on the road lanes, turn the corner, keep their order and gap; enemy tanks come at them up the road.
## Run: tools/test.sh tests/test_tankmis_w129_b.gd
const TIMEOUT_SECONDS := 140

func _init() -> void:
	mission = &"tank_convoy"
	budget = 260.0


func check_extra(t: StringName, _k0: CampaignRunner) -> void:
	print("CONVOY CHECKS: off road %.1f m, order %s, lead turned %.2f rad, waited %s, driven %s, samples %d" % [off_road, order_ok, lead_turn, waited, driven, samples])
	TestLib.check(waited, "[old fails] %s: the convoy waits at the yard for the escort to join" % t)
	TestLib.check(samples > 10 and driven, "[old fails] %s: the trucks drive themselves (their own physics, not puppets moved along a line)" % t)
	TestLib.check(samples > 10 and off_road < 1.0, "[old fails] %s: every truck stayed on the city's road lanes (farthest %.1f m off)" % [t, off_road])
	TestLib.check(samples > 10 and order_ok, "[old fails] %s: the trucks kept their order along the road" % t)
	TestLib.check(lead_turn > 1.2, "[old fails] %s: the lead truck followed the road round the corner (turned %.2f rad)" % [t, lead_turn])
