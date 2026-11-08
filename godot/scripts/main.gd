extends Node3D
## Composition root. Instantiates each module's scene if it exists, so modules can be built independently.
## Modules register themselves on the Game singleton (Game.player, Game.world, ...) in their own _ready().

const MODULES := [
	"res://scenes/world.tscn",
	"res://scenes/atmosphere.tscn",
	"res://scenes/player.tscn",
	"res://scenes/enemy_manager.tscn",
	"res://scenes/vehicle_manager.tscn",
	"res://scenes/missions.tscn",
	"res://scenes/hud.tscn",
	"res://scenes/story.tscn",      # after the HUD: its cards get taps before the HUD and the touch controls do
]


func _ready() -> void:
	# A real run (not a tool, test or bot) first shows LOADING and builds the heavy modules two frames later, so the title never looks frozen.
	var overlay: LoadingOverlay = null
	if not Game.autostart and DisplayServer.get_name() != "headless":
		overlay = LoadingOverlay.new()
		add_child(overlay)
		await get_tree().process_frame
		await get_tree().process_frame
	# LOW tier (saved choice, --quality=0, or a touchscreen's first launch): the model atlases drop to 1024 px before any model is instantiated (scripts/common/texture_budget.gd)
	if (not Game.autostart or OS.get_cmdline_user_args().has("--halve-textures")) and (Game.quality == 0 or UiSettings.new().quality == 0 or AutoQuality.wants_low_default()):
		TextureBudget.halve_models()
	elif (not Game.autostart or OS.get_cmdline_user_args().has("--high-textures")) and (Game.quality >= 2 or UiSettings.new().quality >= 2):
		TextureBudget.upgrade_high()
	var loaded := 0
	for path: String in MODULES:
		if ResourceLoader.exists(path):
			add_child((load(path) as PackedScene).instantiate())
			loaded += 1
	if loaded == 0:
		_build_placeholder()
	Game.set_quality(Game.quality)      # every module starts on the same graphics tier (--quality=N, saved setting)
	add_child(PerfTiers.new())          # mesh LOD threshold, anisotropy and mip bias per tier, Compatibility pool caps (scripts/common/perf_tiers.gd)
	add_child(AutoQuality.new())        # touchscreens start on LOW until the player chooses; a sustained low frame rate drops one tier
	add_child(PerfOverlay.new())        # phone profiling: frame time percentiles, device report, user://perf_log.txt, governor log (long-press the FPS box)
	add_child(BenchmarkRun.new())       # OPTIONS > RUN BENCHMARK: 30 s fixed route on LOW / MED / HIGH with a result panel (scripts/common/benchmark_run.gd)
	add_child(Stability.new())          # watchdog: held input, time scale, camera / player / HUD consistency, hurt and death feedback
	add_child(InteriorGameplay.new())   # enterable interiors: doors, fades, vendors, actors, missions (scripts/interiors_gameplay/)
	add_child(preload("res://scripts/world/city_events.gd").new())   # city events: ambush, race, rescue, drop, rift (actors, rewards, minimap markers, rift gravity)
	add_child(Breakables.new())         # breakable props (crates, glass, poles ...), pooled debris, bullet decal surfaces (scripts/world/breakables.gd)
	add_child(Wanted.new())             # wanted v2: patrol responses by level, roadblocks, hide-and-lose (scripts/enemies/wanted.gd; factions in factions.gd)
	add_child(Encounters.new())         # encounter director: a squad within 26-40 m almost always, rushing, with a threat cue (scripts/enemies/encounters.gd; off under tools / tests)
	add_child(Companion.new())          # the Vael defector ally: recruited by chapters 11-12, some side missions and the DEMO menu (scripts/npc/companion.gd)
	add_child(Activities.new())         # F8: range, rooftop run, drift course, arena (scripts/activities/)
	add_child(Freedom.new())            # open world freedom: hijacks, quantum charges (C4), street races, taxi / delivery / bounty jobs, stunt jumps (scripts/freedom/)
	add_child(Cinematics.new())         # cutscenes (intro, chapter, boss), title backdrop, shop close-up, dead / win bars and fades (scripts/cinematics/)
	TestMode.forced = UiSettings.new().test_mode or OS.get_cmdline_user_args().has("--test-mode")
	add_child(ResultCard.new())         # the mission result card: credits, the one unlock, NEXT (scripts/ui/result_card.gd); before the TEST menu so that sees input first
	add_child(TestMenu.new())           # the hack / test menu, its TEST button and the weapon quick buttons (debug builds or the 'test mode' setting); LAST: it sees input first
	add_child(DemoPanel.new())          # DEMO MODE: the DEMO menu and badge while the sandbox profile runs (scripts/demo/demo_mode.gd); after the TEST menu so it sees input first
	if not Game.autostart:
		Sfx.play_music()                # the ambient loop: not under tools, tests and bots (Game.autostart), which stay silent
	if overlay != null:                 # behind the opaque loading overlay: draw every effect, enemy type and car kind once, so the first fight has no shader hitch
		await ShaderWarmup.run(self)
	# With a HUD the menu is shown first; tools and tests (Game.autostart) skip straight to play.
	var has_ui := ResourceLoader.exists("res://scenes/hud.tscn")
	Game.state = &"play" if (Game.autostart or not has_ui) else &"menu"
	if overlay != null:
		await get_tree().process_frame
		overlay.finish()


## Shown until the first module exists, so the project always renders something.
func _build_placeholder() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 6, 12)
	cam.look_at(Vector3.ZERO)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	floor_mesh.mesh = plane
	add_child(floor_mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
