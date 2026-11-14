extends RefCounted
## The SCREEN half of the wave 114 PLAY critic's regression tests (see tests/test_play_critic_w114.gd, which holds the sections): the kill feed lane of the play HUD, real touch events on the Arsenal at 844x390
## and the crate reveal in a fight, in the REAL game scene. Split from the other file so that neither needs more than a slow runner's time limit.
## Run: tools/test.sh tests/test_play_critic_w114_ui.gd

const TIMEOUT_SECONDS := 140.0
const Base := preload("res://tests/test_play_critic_w114.gd")


func run(host: Node) -> void:
	var base := Base.new()
	await base.run_sections(host, PackedStringArray(["hud", "touch", "reveal"]))
