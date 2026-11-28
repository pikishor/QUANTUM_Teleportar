extends "res://tests/tankmis_w129_bot.gd"
## w129-tankmis: ARTILLERY STRIKE played to its normal end by fingers only, stuck recovery off (see tests/test_tankmis_w129.gd for the rules): the mobile artillery leaves the yard, stops at
## the firing position at the gate and shells the armour parked down the street (the right thumb puts the howitzer's marker on a target, a finger on FIRE).
## Run: tools/test.sh tests/test_tankmis_w129_c.gd
const TIMEOUT_SECONDS := 140

func _init() -> void:
	mission = &"tank_artillery"
	budget = 200.0


func check_extra(t: StringName, _k0: CampaignRunner) -> void:
	TestLib.check(fire_from.is_finite() and _flat(fire_from, ArmourSites.YARD) < 60.0, "[old fails] %s: the firing position is at the yard gate (%d m from the yard)" % [t, roundi(_flat(fire_from, ArmourSites.YARD)) if fire_from.is_finite() else -1])
	TestLib.check(max_off < 25.0, "%s: every target was shelled from the firing position (the gun moved %.0f m)" % [t, max_off])


## The howitzer's marker reaches armour 290 m down the street: the right thumb lays the crosshair on it and the marker snaps onto it (TankArms.indirect_aim; the old aim ray ended at 220 m).
func after(_t0: StringName) -> void:
	var v := await _own_tank(&"artillery")
	if v == null:
		TestLib.check(false, "HOWITZER: an artillery to sit in")
		return
	var at := v.global_position + v.forward() * 290.0
	vm._fixed_n += 1
	var tgt := vm.spawn_parked(&"apc", at, 0.0)
	vm._count_fixed()
	if tgt == null:
		TestLib.check(false, "HOWITZER: a target")
		return
	tgt.set_meta(&"hold", true)
	tgt.set_meta(&"tank_target", true)
	tgt.global_position = at
	await _f(6)
	await _aim_finger(tgt.global_position + Vector3(0.0, 1.0, 0.0), 0.008)
	await _wait(0.5)
	var m := TankArms.marker_point(v)
	var off := _flat(m, tgt.global_position) if m.is_finite() else 9999.0
	print("HOWITZER: marker %s, %.1f m off the target %d m away" % [m, off, roundi(_flat(v.global_position, at))])
	TestLib.check(off < 3.0, "[old fails] HOWITZER: a finger lays the marker on armour 290 m down the street (%.1f m off)" % off)
	for mm: StringName in [&"hold", &"tank_target"]:
		tgt.remove_meta(mm)
