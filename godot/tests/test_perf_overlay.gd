extends RefCounted
## PerfOverlay (phone profiling hooks): percentiles, report content, clipboard copy, perf_log.txt, governor log, and the wiring (main.gd composes it, the FPS box long-press
## opens the debug panel, the COPY REPORT button calls it). Run: tools/test.sh tests/test_perf_overlay.gd

var host: Node


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	var path := "user://perf_log_test.txt"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var po := PerfOverlay.new()
	po.log_path = path
	host.add_child(po)
	await TestLib.frames(host, 2)
	TestLib.check(po.is_in_group(&"perf_overlay"), "overlay is in group perf_overlay")
	TestLib.check(po.percentile(50) == 0.0, "no samples: percentile 0")
	for i in 100:
		po.record(float(i + 1))
	TestLib.check(absf(po.percentile(50) - 50.0) <= 1.0, "p50 of 1..100 ms is about 50")
	TestLib.check(absf(po.percentile(99) - 99.0) <= 1.0, "p99 of 1..100 ms is about 99")
	TestLib.check(po.worst_ms() == 100.0, "worst is 100 ms")
	for i in 1000:                                  # ring wraps: only the newest SAMPLES count
		po.record(10.0)
	TestLib.check(po.count() == PerfOverlay.SAMPLES and po.percentile(99) == 10.0, "ring keeps only the newest samples")
	var r := po.report()
	for key in ["p50", "p95", "p99", "Draws", "Nodes", "Memory", "GPU", "Battery", "Thermal", "tier"]:
		TestLib.check(r.contains(key), "report mentions " + key)
	po.copy_report()
	TestLib.check(po.copies == 1, "copy counted")
	TestLib.check(not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD) or DisplayServer.clipboard_get().contains("perf report"), "clipboard holds the report (or the platform has none)")
	po.on_governor_lowered(0)
	var log := FileAccess.get_file_as_string(path)
	TestLib.check(log.contains("SESSION START") and log.contains("COPY") and log.contains("GOVERNOR lowered to LOW"), "perf_log has session, copy and governor lines")
	DirAccess.remove_absolute(path)
	po.queue_free()
	# wiring: main.gd composes it and the touch controls draw the COPY REPORT button and call it
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	TestLib.check(main_src.contains("PerfOverlay.new()"), "main.gd composes PerfOverlay")
	var tc_src := FileAccess.get_file_as_string("res://scripts/ui/touch_controls.gd")
	TestLib.check(tc_src.contains("copy_report()") and tc_src.contains("_draw_report"), "touch controls call copy_report and draw the report")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 20)
	TestLib.check(main.get_tree().get_first_node_in_group(&"perf_overlay") != null, "the composed game has the overlay")
	main.queue_free()
