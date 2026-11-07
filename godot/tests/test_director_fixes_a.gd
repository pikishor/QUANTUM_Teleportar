extends RefCounted
## Director review fixes, gameplay half (docs/SLICE_REVIEW.md, defects 2, 5, 6, 7, 8, 9, 10, 14) in the REAL game scene:
##   6  a door closes behind the hero: a few seconds of grace and the hunters that followed come in later, not at once
##   7  inside a building the plate shows the room's own job from the first frame, or "LEAVE THE BUILDING TO CONTINUE" when a street step runs (never "CROSS THE FLOOR  0 M")
##   14 a hack / defend step never lifts the heat to patrol cars and roadblocks
##   10 one crash never wrecks a healthy hull below the survive speed and never takes more than a third of the driver's health; a scrape is one crash
##   5  the prologue cards are short and the hero cannot be hurt while he reads them
##   2/9 the shoulder camera sits further out and the driving view widens with speed
##   8  no car paint (interceptors, husks) is a pure black cut-out
## Waits on counters and state, never on frame counts; user:// state is reset first.
## Run: tools/test.sh tests/test_director_fixes_a.gd

var host: Node
var camp: CampaignRunner
var p: Player
var hud: Hud


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://interiors.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	_constants()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	p = Game.player as Player
	var m := Game.missions as Missions
	hud = host.get_tree().get_first_node_in_group(&"hud") as Hud
	TestLib.check(p != null and m != null and m.campaign != null and hud != null, "the real scene has a player, missions, a campaign and a HUD")
	if p == null or m == null or hud == null:
		return
	camp = m.campaign
	camp.set_physics_process(false)
	camp.enabled = false
	(Game.progress as Progress).autosave_enabled = false
	p.max_hp = 1000.0
	p.hp = 1000.0
	await _interior_entry()
	await _hold_heat()
	await _crash()
	_prologue_cards()
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)


func _chapter(steps: Array) -> void:
	camp.abort()
	Game.heat = 0.0
	Game.state = &"play"
	camp.start_custom({"id": "director_a", "clears_sector": false, "steps": steps})


# --- tuning numbers that carry the fixes ------------------------------------------------------------------------------------------

func _constants() -> void:
	TestLib.check(CameraRig.HIP_SHOULDER >= 0.9 and CameraRig.ADS_SHOULDER >= 0.65 and CameraRig.ADS_LIFT > 0.0, "the shoulder camera sits out and up so the rifle shows (hip %.2f, ads %.2f, lift %.2f)" % [CameraRig.HIP_SHOULDER, CameraRig.ADS_SHOULDER, CameraRig.ADS_LIFT])
	TestLib.check(CameraRig.VEH_FOV_FAST - CameraRig.VEH_FOV_REST >= 10.0, "the driving view widens with speed (it starts wide so the car stays large) (%.0f to %.0f degrees)" % [CameraRig.VEH_FOV_REST, CameraRig.VEH_FOV_FAST])
	TestLib.check(CharacterRig.LOW_READY_YAW < -0.3, "the lowered rifle swings out to the side of the hero (was -0.12; -0.4 is the most that keeps both gloves on the rifle)")
	var worst := 1.0
	for k: StringName in [&"interceptor"]:
		for c: Color in VehicleSpecs.PALETTES[k]:
			worst = minf(worst, c.v)
	TestLib.check(worst > 0.3 and VehicleSpecs.WRECK_COLOR.v > 0.1, "no car paint is a pure black cut-out (darkest interceptor %.2f, husk %.2f)" % [worst, VehicleSpecs.WRECK_COLOR.v])
	TestLib.check(VehicleSpecs.CRASH_SURVIVE_V >= 24.0 and VehicleSpecs.CRASH_LIMP_HP > 0.05 and VehicleSpecs.HERO_HURT_CAP <= 0.35, "the crash rules: a healthy hull survives one hit up to %.1f m/s, the driver loses at most %.0f %%" % [VehicleSpecs.CRASH_SURVIVE_V, VehicleSpecs.HERO_HURT_CAP * 100.0])
	TestLib.check(Story.CPS_CARD >= 80.0 and Story.CARD_HOLD_BASE <= 1.0, "story cards type fast and move on by themselves quickly")
	var chars := 0
	for c: Dictionary in StoryData.PROLOGUE:
		chars += str(c["text"]).length()
	var secs := 0.0
	for c: Dictionary in StoryData.PROLOGUE:
		var n := str(c["text"]).length()
		secs += float(n) / Story.CPS_CARD + Story.CARD_HOLD_BASE + n * Story.CARD_HOLD_PER_CHAR
	TestLib.check(secs < 12.0, "the three prologue cards take %.1f s untouched (was about 16)" % secs)


# --- 6 and 7: a door and what the plate says inside ----------------------------------------------------------------------------

func _interior_entry() -> void:
	var ig := InteriorGameplay.instance
	TestLib.check(ig != null, "the interior system runs in the real scene")
	if ig == null:
		return
	p.invuln = 0.0
	_chapter([{"kind": "reach", "pos": [-200.0, 0.0], "obj": "Cross the trading floor to the beacon"}, {"kind": "reach", "pos": [-300.0, 0.0], "obj": "Go on"}])
	camp.tick(0.1)
	await TestLib.frames(host, 2)
	TestLib.check(camp.state == &"active" and camp.kind == &"reach", "a street step runs (%s)" % str(camp.state))
	# a room with a job of its own: the job is on the plate from the first frame, the hero is safe for a moment, hunters come late
	ig.done.clear()
	TestLib.check(ig.test_enter(&"lobby").begins_with("INSIDE"), "the hero goes into a lobby")
	TestLib.check(InteriorGameplay.hud_line.begins_with("SAFE"), "the lobby's own job is the plate's line at once ('%s')" % InteriorGameplay.hud_line)
	TestLib.check(p.invuln > InteriorGameplay.ENTRY_GRACE - 1.0, "the door closes behind a hero who cannot be hurt for %.0f s (invuln %.1f)" % [InteriorGameplay.ENTRY_GRACE, p.invuln])
	var hp0 := p.hp
	p.damage(300.0, p.global_position + Vector3(0.0, 0.0, 3.0))
	TestLib.check(is_equal_approx(p.hp, hp0), "a hit in the first seconds inside does nothing (hp %.0f)" % p.hp)
	TestLib.check(ig.actors._follow_t >= InteriorActors.FOLLOW_FIRST - 0.01 and InteriorActors.FOLLOW_FIRST > InteriorGameplay.ENTRY_GRACE - 2.0, "hunters from the street come in after %.0f s, not at once" % InteriorActors.FOLLOW_FIRST)
	# a room with no job (a bar): the street step waits and the plate says so
	ig.leave(true)
	await TestLib.frames(host, 2)
	TestLib.check(ig.test_enter(&"bar").begins_with("INSIDE"), "the hero goes into a bar")
	await TestLib.frames(host, 3)
	var line := hud._campaign_line()
	TestLib.check(line == "LEAVE THE BUILDING TO CONTINUE", "inside a room without a job the plate says LEAVE THE BUILDING TO CONTINUE, not the street step ('%s')" % line)
	TestLib.check(not line.contains(" M"), "...and no '0 M' distance of a goal that is not in the room")
	ig.leave(true)
	await TestLib.frames(host, 2)
	camp.abort()
	p.invuln = 0.0


# --- 14: the hack step ------------------------------------------------------------------------------------------------------------

func _hold_heat() -> void:
	_chapter([{"kind": "hack", "pos": [-300.0, 0.0], "obj": "Hack the ledger node", "radius": 10.0}, {"kind": "reach", "pos": [-100.0, 0.0], "obj": "Go on"}])
	camp.tick(0.1)
	camp.tick(2.0)
	await TestLib.frames(host, 2)
	camp.tick(0.1)
	TestLib.check(camp.state == &"active" and camp.kind == &"hack", "the hack step runs (%s)" % str(camp.state))
	Game.heat = 4.6                                           # the step's own wave and a crowd's casualties
	camp.tick(0.1)
	TestLib.check(Game.heat <= CampaignRunner.HOLD_HEAT_CAP + 0.01, "a hack never holds more than %.1f stars (heat %.2f): no patrol cars or roadblocks" % [CampaignRunner.HOLD_HEAT_CAP, Game.heat])
	TestLib.check(CampaignRunner.HOLD_HEAT_CAP < 2.0, "...which is below the level of the patrol cars")
	camp.abort()
	Game.heat = 0.0
	_chapter([{"kind": "defend", "pos": [-300.0, 0.0], "obj": "Hold the position", "radius": 20.0}, {"kind": "reach", "pos": [-100.0, 0.0], "obj": "Go on"}])
	camp.tick(0.1)
	camp.tick(2.0)
	await TestLib.frames(host, 2)
	camp.tick(0.1)
	Game.heat = 4.0
	camp.tick(0.1)
	TestLib.check(camp.state != &"active" or camp.kind != &"defend" or Game.heat <= CampaignRunner.HOLD_HEAT_CAP + 0.01, "a defend step holds the heat down too (heat %.2f)" % Game.heat)
	camp.abort()
	Game.heat = 0.0


# --- 10: crashes ------------------------------------------------------------------------------------------------------------------

func _crash() -> void:
	var mgr := Game.vehicles as VehicleManager
	TestLib.check(mgr != null, "the real scene has a vehicle manager")
	if mgr == null:
		return
	mgr.stream_every = 1.0e9
	mgr._stream_t = 1.0e9
	var v := mgr.spawn_parked(&"sedan", Vector3(-90.0, 0.0, 40.0), 0.0)
	await TestLib.frames(host, 3)
	var n := Vector3(0.0, 0.0, 1.0)
	# a healthy sedan survives one hard hit at 92 km/h
	var v92 := 25.5
	var hp0 := v.hp
	v.crash(v92, v.global_position + Vector3(0.0, 0.7, -2.3), n, INF)
	TestLib.check(not v.dead and v.hp > 0.1 * v.max_hp, "a 92 km/h wall hit does not wreck a healthy sedan (hp %.0f of %.0f, was %.0f)" % [v.hp, v.max_hp, hp0])
	TestLib.check(v.hp < 0.8 * v.max_hp, "...but it hurts (hp %.0f of %.0f)" % [v.hp, v.max_hp])
	# the same grinding along the wall is one crash, not one per frame
	var c0 := v.crashes
	var hp1 := v.hp
	for i in 5:
		v.crash(v92 * 0.9, v.global_position + Vector3(0.0, 0.7, -2.3), n, INF)
	TestLib.check(v.crashes == c0 and is_equal_approx(v.hp, hp1), "five more scrape events within a moment count as the same crash (%d crashes, hp %.0f)" % [v.crashes - c0, v.hp])
	v.impact_t = 5.0
	# a second hard hit, once the hull is already low, can finish the car
	v.crash(v92, v.global_position + Vector3(0.0, 0.7, -2.3), n, INF)
	TestLib.check(v.dead or v.hp <= 0.12 * v.max_hp + 1.0, "a second hard hit on a hurt hull finishes it (dead %s, hp %.0f)" % [str(v.dead), v.hp])
	# a head-on at the highest speed still destroys a healthy car
	if mgr.driven != null:
		mgr.exit_vehicle()
	var w := mgr.spawn_parked(&"sedan", Vector3(-70.0, 0.0, 40.0), 0.0)
	await TestLib.frames(host, 3)
	w.crash(34.0, w.global_position + Vector3(0.0, 0.7, -2.3), n, INF)
	TestLib.check(w.dead or w.hp < 0.08 * w.max_hp, "a 120 km/h wall hit still destroys a sedan (hp %.0f)" % w.hp)
	# the driver loses at most a third of his health in one crash
	p.set_physics_process(true)
	var d := mgr.spawn_parked(&"sedan", Vector3(-50.0, 0.0, 40.0), 0.0)
	await TestLib.frames(host, 3)
	p.invuln = 0.0
	p.hp = 1000.0
	mgr.enter(d)
	d.driver_is_player = true
	d.crash(33.0, d.global_position + Vector3(0.0, 0.7, -2.3), n, INF)
	TestLib.check(p.hp >= 1000.0 * (1.0 - VehicleSpecs.HERO_HURT_CAP) - 1.0, "the worst crash costs the driver at most %.0f %% of his health (hp %.0f of 1000)" % [VehicleSpecs.HERO_HURT_CAP * 100.0, p.hp])
	if mgr.driven != null:
		mgr.exit_vehicle()
	p.hp = 1000.0
	p.invuln = 0.0


# --- 5: the cards ------------------------------------------------------------------------------------------------------------------

func _prologue_cards() -> void:
	var story := Game.story as Story
	TestLib.check(story != null, "the real scene has the story layer")
	if story == null:
		return
	Game.state = &"play"
	p.invuln = 0.0
	story.start_cards(StoryData.PROLOGUE, &"prologue")
	story.advance(0.2)
	TestLib.check(p.invuln > 0.0, "a hero who reads the prologue over a live street cannot be hurt (invuln %.2f)" % p.invuln)
	story.skip_cards()
	TestLib.check(not story.cards_active(), "a tap skips the cards")
