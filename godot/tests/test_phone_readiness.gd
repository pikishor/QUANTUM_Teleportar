extends RefCounted
## Phone readiness: LOW death-spike budget, startup self-check in the perf log, first-launch recommendation, governor logging. Run: tools/test.sh tests/test_phone_readiness.gd

var host: Node


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestLib.check(int(PerfProbe.BUDGETS[0]["death_draws"]) <= 115 and int(PerfProbe.BUDGETS[2]["death_draws"]) <= 170, "LOW death-spike budget <= 115, HIGH <= 170")
	TestLib.check(FX.LOW_PARTICLES < FX.PARTICLE_POOL and FX.LOW_PARTICLES >= 2, "LOW rotates a smaller burst pool")
	TestLib.check(PerfOverlay.recommended_tier() >= 0 and PerfOverlay.recommended_tier() <= 2, "recommended tier is a valid tier")
	var path := "user://perf_log_phone_test.txt"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var aq := AutoQuality.new()
	aq.enabled = false
	host.add_child(aq)
	var po := PerfOverlay.new()
	po.log_path = path
	host.add_child(po)
	await TestLib.frames(host, 2)
	var log := FileAccess.get_file_as_string(path)
	TestLib.check(log.contains("STARTUP CHECK") and log.contains("renderer=") and log.contains("recommended=") and log.contains("gpu="), "startup self-check logs renderer, device and recommended tier")
	# governor events say tier, resolution and FPS
	po.on_governor_lowered(0)
	po.on_governor_res("BALANCED")
	log = FileAccess.get_file_as_string(path)
	TestLib.check(log.contains("GOVERNOR lowered tier to LOW") and log.contains("GOVERNOR lowered resolution to BALANCED"), "governor tier and resolution drops are logged")
	TestLib.check(log.contains("Governor: tier") and log.contains("render ") and log.contains("FPS"), "governor lines carry tier, resolution and FPS")
	TestLib.check(po.report().contains("Governor: tier"), "copy report states what the governor settled on")
	# the first-launch notice
	aq.announce_first_launch()
	TestLib.check(aq.notice_left > 0.0, "first launch shows the recommended tier notice")
	# the live wiring
	var src := FileAccess.get_file_as_string("res://scripts/main.gd")
	TestLib.check(src.contains("AutoQuality.new()") and src.contains("PerfOverlay.new()"), "main.gd composes both")
	var q := AutoQuality.new()
	var fired := [0]
	q.res_lowered.connect(func(_m: String) -> void: fired[0] += 1)
	TestLib.check(q.has_signal("res_lowered") and q.has_signal("lowered"), "governor signals resolution and tier drops")
	q.free()
	DirAccess.remove_absolute(path)
	po.queue_free()
	aq.queue_free()
