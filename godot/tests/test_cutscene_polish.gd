extends RefCounted
## Cutscene polish: new plans (garage reveal, teleporter first use), dolly zoom, rack focus, glitch transitions, subtitle timing for every plan.
## Run: tools/test.sh tests/test_cutscene_polish.gd

func _plans() -> Array[CinePlan]:
	var c := {"hero": Vector3(5, 0, 5), "face": Vector3.RIGHT, "boss": Vector3(40, 0, 0), "title": "T", "sub": "S", "obj": "O", "label": "L"}
	var intro := {"roof": Vector3(60, 30, 0), "roof_face": Vector3.LEFT, "spawn": Vector3(-30, 0, 4), "spawn_face": Vector3.RIGHT}
	var out: Array[CinePlan] = [CinePlan.intro(intro), CinePlan.chapter(c), CinePlan.boss_in(c), CinePlan.boss_out(c), CinePlan.credits_scene(c), CinePlan.garage_reveal(c), CinePlan.teleporter_first(c)]
	return out


func run(_host: Node) -> void:
	for p in _plans():
		var ok := true
		var t := 0.0
		while t < p.duration:
			p.sample(t)
			ok = ok and p.cam_pos.is_finite() and p.cam_fov >= 20.0 and p.cam_fov <= 120.0 and p.cam_focus >= 0.0 and p.cam_focus <= 1.0 and p.cam_transform().basis.is_finite()
			t += 0.05
		TestLib.check(ok, "%s: every sampled pose is finite, fov and focus in range" % p.id)
		TestLib.check(p.sub_problems().is_empty(), "%s: subtitle timing is clean %s" % [p.id, str(p.sub_problems())])
		TestLib.check(p.skippable and p.bars > 0.05, "%s: skippable with letterbox" % p.id)
		for g in p.glitches:
			TestLib.check(g >= 0.0 and g <= p.duration, "%s: glitch time %.1f inside the scene" % [p.id, g])
	var gp := CinePlan.garage_reveal({"hero": Vector3.ZERO, "face": Vector3.RIGHT})
	TestLib.check(gp.shots.size() >= 3 and gp.shots[1].dolly_k > 0.0, "garage reveal has a dolly zoom shot")
	gp.sample(5.0)
	var f1 := gp.cam_fov
	gp.sample(6.4)
	TestLib.check(absf(f1 - gp.cam_fov) > 1.0, "the dolly zoom changes the fov")
	gp.sample(0.0)
	TestLib.check(gp.cam_focus > 0.5, "the garage shot opens soft (rack focus)")
	gp.sample(3.9)
	TestLib.check(gp.cam_focus < 0.1, "...and ends sharp")
	var tp := CinePlan.teleporter_first({"hero": Vector3.ZERO, "face": Vector3.RIGHT})
	TestLib.check(tp.glitch_at(3.4) > 0.99 and tp.glitch_at(0.5) == 0.0 and tp.glitch_at(3.4 + CinePlan.GLITCH_LEN * 2.0) == 0.0, "glitch peaks at its time and dies away")
	TestLib.check(tp.flash_at(3.4) > 0.99, "the teleporter scene flashes at the jump")
	var subs := CineData.all_subs()
	var lim := true
	for s in subs:
		lim = lim and str(s["t"]).length() <= StoryData.LINE_MAX
	TestLib.check(lim, "all subtitles fit the line limit")
