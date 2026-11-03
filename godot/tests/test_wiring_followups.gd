extends RefCounted
## Wiring follow-ups: one-time cinematic flags, SKIP SET PIECE (button + HUD hook), strike-zone rings, alt-fire / ammo readout and saved ammo type,
## achievement cosmetics worn at once, ALT button spacing at 844x390 and 1280x720.
## Run: tools/test.sh tests/test_wiring_followups.gd

const Env := preload("res://tests/player_env.gd")

var e := Env.new()


func run(host: Node) -> void:
	await e.setup(host)
	var p: Player = e.p
	var w: PlayerWeapon = p.weapon
	Game.state = &"play"
	WeaponDefs.reset_unlocked()
	var prog := Progress.new()
	host.add_child(prog)
	prog.autosave_enabled = false
	Game.progress = prog

	# one-time cinematics are recorded once
	prog.cine_seen.clear()
	TestLib.check(prog.mark_cine(&"garage_reveal") and not prog.mark_cine(&"garage_reveal"), "garage_reveal recorded once")
	TestLib.check(not Cinematics.first_time(&"teleporter_first"), "silent under autostart without force")
	var snap := prog.snapshot()
	TestLib.check((snap["cine_seen"] as Array).has(&"garage_reveal"), "cine_seen is in the save snapshot")

	# alt-fire / ammo readout and saved ammo type
	w.reset()
	TestLib.check(w.alt_text().begins_with("ALT "), "alt text names the alt-fire: " + w.alt_text())
	if String(w.def["kind"]) == "hit":
		TestLib.check(w.alt_text().contains("AMMO"), "hitscan weapon shows its ammo type")
		var before := w.ammo_type
		w.swap_t = 0.0
		TestLib.check(w.cycle_ammo_type() and prog.ammo_type == w.ammo_type and w.ammo_type != before, "cycling saves the ammo choice")
		prog.set_ammo_type(0)
	prog.set_ammo_type(99)
	TestLib.check(prog.ammo_type == WeaponDefs.AMMO_TYPES.size() - 1, "ammo choice is clamped")
	prog.set_ammo_type(0)

	# strike-zone rings: pooled, shown per zone, hidden on empty
	var vis := ContractVisuals.new()
	host.add_child(vis)
	var zs: Array[Vector3] = [Vector3(5, 0, 5), Vector3(-8, 0, 3)]
	vis.show_zones(zs, 5.0, false)
	TestLib.check(vis.zones_visible() == 2, "two strike zones drawn")
	vis.show_zones(zs, 5.0, true)
	TestLib.check(vis.zones_visible() == 2, "still two while hitting")
	var none: Array[Vector3] = []
	vis.show_zones(none, 5.0, false)
	TestLib.check(vis.zones_visible() == 0, "no zones hidden")
	vis.free()

	# SKIP SET PIECE: only inside an optional piece
	var r := CampaignRunner.new()
	r.enabled = false
	TestLib.check(r.start_chapter(1, 0, true), "chapter starts")
	TestLib.check(not r.in_optional_set_piece() or r.skip_set_piece(), "skip only when inside a piece")
	var fi := 0
	while fi < r.steps.size() and not (r.steps[fi].has("set_piece") and bool(r.steps[fi].get("optional", false))):
		fi += 1
	if fi < r.steps.size():
		r.step_index = fi
		r.state = &"armed"
		TestLib.check(r.in_optional_set_piece(), "optional piece detected")
		TestLib.check(r.skip_set_piece() and not r.in_optional_set_piece(), "skipped")
	var has_btn := false
	for b: Dictionary in TouchControls.BUTTONS:
		has_btn = has_btn or b["action"] == &"skip_piece"
	TestLib.check(has_btn, "SKIP SET PIECE touch button exists")
	r.free()

	# achievement cosmetics are worn at once
	prog.hero.reset()
	prog.achievements.cosmetics.clear()
	prog.achievements.cosmetics.append(&"aura_phase")
	prog._on_achievement_cosmetic(&"shard_30")
	TestLib.check(prog.hero.suit == &"phase", "aura_phase wears the phase suit")
	prog.achievements.cosmetics.append(&"trail_violet")
	prog._on_achievement_cosmetic(&"shard_20")
	TestLib.check(prog.hero.scheme == 2, "trail_violet wears the violet scheme")
	prog.hero.reset()
	prog.achievements.cosmetics.clear()

	# ALT button clear of its neighbours at phone and desktop sizes
	var alt := {}
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == &"altfire":
			alt = b
	for vp: Vector2 in [Vector2(844, 390), Vector2(1280, 720)]:
		var s := UiUtil.ui_scale(vp)
		for b: Dictionary in TouchControls.BUTTONS:
			if b["action"] in [&"fire", &"aim", &"jump", &"reload", &"swap", &"entangle"]:
				var d := Vector2(float(alt["dx"]) - float(b["dx"]), float(alt["dy"]) - float(b["dy"])).length() * s
				TestLib.check(d >= (float(alt["r"]) + float(b["r"])) * s - 0.5, "ALT clear of %s at %dx%d" % [b["action"], vp.x, vp.y])
