extends RefCounted
## The four stealth missions (UNSEEN ENTRY, PLANT THE DEVICE, DATA THEFT, SILENT ROUTE) in the REAL scene (main.tscn): the table is complete and priced by Economy, every mission starts through
## the DEMO menu entry (kind "stealth"), plays in its own interior with the real Vael guards, a scripted bot (teleports the player along the objective, melee takedown behind a guard) completes
## each one and is paid, a guard that becomes ALERTED fails the run (SPOTTED) while suspicion alone does not, a kill costs the no-kills bonus, a silent kill raises no heat and wakes nobody,
## the clock fails DATA THEFT, leaving ends a run quietly, and the live wiring (entering the interior of a mission offers it, sector-gated) works. HUD line, alert meter and minimap markers are read.
## The runner is ticked by hand (physics off) so timing is exact; waits are on state; the guards' sight is shortened for the bot so a random glance never ends a scripted run. Progress writes to a
## throw-away file. Not run: a phone, the feel of real guard patrols.
## Run: tools/test.sh tests/test_stealth_missions.gd

const TMP := "user://test_stealth_missions_save.cfg"

var host: Node
var main: Node
var st: StealthRunner
var ig: InteriorGameplay
var prog: Progress
var p: Player
var ended: Array = []


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	_data()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	var m := Game.missions as Missions
	p = Game.player as Player
	ig = InteriorGameplay.instance
	TestLib.check(m != null and m.stealth != null and p != null and ig != null, "main.tscn composes Missions.stealth, the player and the interior layer")
	if m == null or m.stealth == null or p == null or ig == null:
		return
	st = m.stealth
	prog = Game.progress as Progress
	prog.path = TMP
	prog.autosave_enabled = false
	ig.autosave = false
	st.set_physics_process(false)
	st.finished.connect(func(sid: StringName, ok: bool, why: String) -> void: ended.append([sid, ok, why]))
	var was_demo := DemoMode.active
	DemoMode.active = true
	await _reset()

	await _infiltrate_and_alerts()
	await _plant()
	await _data_theft()
	await _route()
	await _live_offer()

	DemoMode.active = was_demo
	st.abort("TEST")
	if InteriorGameplay.active:
		ig.leave(true)
	Game.heat = 0.0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	main.queue_free()
	await frames(5)
	Game.state = &"menu"
	Sfx.muted = false


# --- helpers ---------------------------------------------------------------------------------------------------------------

func _reset() -> void:
	st.abort("TEST")
	if InteriorGameplay.active:
		ig.leave(true)
	Game.state = &"play"
	Game.heat = 0.0
	p.hp = p.max_hp
	ended.clear()
	st.done.clear()
	await frames(3)


func _guards() -> Array[Drone]:
	var out: Array[Drone] = []
	for g in ig.actors.guards:
		if is_instance_valid(g) and g.active and not g.dead:
			out.append(g)
	return out


## The bot keeps the guards from noticing it by chance: sight shortened to a hand's breadth (noise, damage and alerts still work).
func _blind_guards() -> void:
	for g in _guards():
		g.aware_dist = 0.2
		g.suspicion = 0.0
	Game.heat = 0.0


func _launch(sid: StringName) -> void:
	await _reset()
	var status := DemoMode.launch(&"stealth", sid)
	TestLib.check(status != "" and st.is_running() and st.id == sid, "%s starts through the DEMO menu (%s%s)" % [sid, status, "" if status != "" else " blocked: " + ig.block_reason() + " state " + str(Game.state) + " can " + str(st.can_start(sid))])
	await frames(2)
	_blind_guards()


func _stand(pos: Vector3) -> void:
	p.teleport_to(Vector3(pos.x, 0.1, pos.z))


## Ticks the runner in 0.25 s steps until `cond` is true (at most max_s of game time); true when it held.
func _until(cond: Callable, max_s := 30.0) -> bool:
	var t := 0.0
	while t < max_s:
		if cond.call():
			return true
		st.tick(0.25)
		t += 0.25
	return cond.call()


func _last() -> Array:
	return ended[ended.size() - 1] if not ended.is_empty() else [&"", false, ""]


# --- data ------------------------------------------------------------------------------------------------------------------

func _data() -> void:
	var ok := StealthScripts.IDS.size() == 4
	for id: StringName in StealthScripts.IDS:
		var why := StealthScripts.validate(id)
		TestLib.check(why == "", "%s: table entry sane (%s)" % [id, why])
		ok = ok and Economy.STEALTH_PAY.has(id) and StealthScripts.reward(id, 0, 0, true) > StealthScripts.reward(id, 0, 0, false)
	TestLib.check(ok, "four missions, each priced in Economy.STEALTH_PAY, the bonus pays more")
	var kinds := {}
	for id: StringName in StealthScripts.IDS:
		kinds[StealthScripts.DEFS[id]["interior"]] = true
	TestLib.check(kinds.size() == 4, "four distinct interiors")
	var base := float(Economy.STEALTH_PAY[&"infiltrate"]) * float(Progress.difficulty(0)["reward"]) * (1.0 + Progress.rep_bonus(0))
	TestLib.check(StealthScripts.reward(&"infiltrate", 0, 0, false) == maxi(5, int(round(base / 5.0)) * 5), "pay reads the Economy table")
	TestLib.check(StealthScripts.reward(&"datatheft", 6, 0, false) > StealthScripts.reward(&"datatheft", 0, 0, false), "pay grows with the sector")
	TestLib.check(StealthScripts.for_interior(&"cargo_bay") == &"takedown" and StealthScripts.for_interior(&"bar") == &"", "interior type maps to its mission")
	var cat := DemoMode.catalog()
	var group: Dictionary = {}
	for g: Dictionary in cat:
		if g["kind"] == &"stealth":
			group = g
	TestLib.check(not group.is_empty() and (group["items"] as Array).size() == 4, "the DEMO catalogue has the four stealth missions")
	TestLib.check(DemoPanel.TABS.size() >= cat.size(), "the DEMO panel has a tab for every catalogue page")


# --- UNSEEN ENTRY, alerts ----------------------------------------------------------------------------------------------------

func _infiltrate_and_alerts() -> void:
	var credits0 := prog.credits
	await _launch(&"infiltrate")
	var want := StealthScripts.DEFS[&"infiltrate"]["interior"]
	TestLib.check(InteriorGameplay.active and StringName(ig.door["type"]) == want, "UNSEEN ENTRY plays in the teleporter hall")
	TestLib.check(st.hud_line().find("UNSEEN ENTRY") == 0, "the HUD plate shows the mission line (%s)" % st.hud_line())
	var mt := st.meter()
	TestLib.check(not mt.is_empty() and str(mt["label"]) == "UNSEEN" and float(mt["frac"]) < 0.05, "the alert meter starts UNSEEN")
	TestLib.check(st.marker_visible(), "the objective is marked in the room")
	var found := false
	for mk: Dictionary in ig.minimap_markers():
		if (mk["pos"] as Vector3).distance_to(st.target_pos) < 0.01 and mk.has("radius") and float(mk["radius"]) >= 1.0:
			found = true
	TestLib.check(found, "the objective is on the interior minimap")
	var door_at: Vector3 = ig.interior.get("door_pos")
	TestLib.check(st.target_pos.distance_to(door_at) > 3.0, "the objective is away from the door")

	# suspicion alone does not fail; the meter follows it
	var g := _guards()[0]
	g.suspicion = 0.5
	st.tick(0.1)
	mt = st.meter()
	TestLib.check(st.is_running() and float(mt["frac"]) >= 0.5 and str(mt["label"]) != "UNSEEN", "suspicion fills the meter but does not fail the run (%s)" % str(mt["label"]))
	g.suspicion = 0.0

	# the scripted bot walks to the terminal
	var steps := 6
	var start := door_at
	for i in steps:
		_stand(start.lerp(st.target_pos, float(i + 1) / float(steps)))
		await frames(1)
		_blind_guards()
		st.tick(0.2)
	await _until(func() -> bool: return not st.is_running(), 3.0)
	TestLib.check(not ended.is_empty() and _last()[1] == true, "the bot reaches the terminal unseen: UNSEEN ENTRY complete (%s)" % str(_last()))
	TestLib.check(bool(st.result["bonus"]) and int(st.result["reward"]) > 0, "paid with the no-kills bonus")
	TestLib.check(prog.credits >= credits0 + int(st.result["reward"]) - 5 and int(st.result["reward"]) > 0, "the credits arrive (%d)" % int(st.result["reward"]))
	TestLib.check(st.hud_line() == "" and st.meter().is_empty() and not st.marker_visible(), "HUD line, meter and marker clear after the run")

	# an alerted guard fails the run: gunfire right next to a guard goes through the real noise rules
	await _launch(&"infiltrate")
	var victim := _guards()[0]
	var em := Game.enemies as EnemyManager
	Stealth.noise(em.list, victim.global_position + Vector3(1.0, 0.0, 1.0), &"gun")
	TestLib.check(victim.aware, "gunfire beside a guard alerts it (real Stealth.noise)")
	st.tick(0.1)
	TestLib.check(not st.is_running() and _last()[1] == false and _last()[2] == "SPOTTED", "an ALERTED guard fails the run: SPOTTED (%s)" % str(_last()))
	TestLib.check(int(st.result["reward"]) == 0 and not st.done.has(int(ig.door["id"])), "a failed run pays nothing and is not remembered")

	# a guard that takes damage but lives is alerted too
	await _launch(&"infiltrate")
	var v2 := _guards()[0]
	v2.damage(1.0)
	st.tick(0.1)
	TestLib.check(not st.is_running() and _last()[2] == "SPOTTED", "a wounded guard sounds the alarm: SPOTTED")

	# leaving unseen ends the run without a penalty
	await _launch(&"infiltrate")
	var rep0 := prog.reputation
	ig.leave(true)
	await frames(2)
	st.tick(0.1)
	TestLib.check(not st.is_running() and _last()[2] == "LEFT" and prog.reputation == rep0, "leaving ends the run quietly (no reputation lost)")
	await _reset()


# --- PLANT THE DEVICE --------------------------------------------------------------------------------------------------------

func _plant() -> void:
	await _launch(&"plant")
	TestLib.check(StringName(ig.door["type"]) == &"warehouse", "PLANT THE DEVICE plays in the warehouse")
	TestLib.check(st.phase == &"approach" and st.hud_line().find("CRATES") > 0, "phase 1: reach the crates (%s)" % st.hud_line())
	var crates := st.target_pos
	_stand(crates + Vector3(6.0, 0.0, 0.0))
	await frames(1)
	_blind_guards()
	st.tick(0.25)
	TestLib.check(st.phase == &"approach", "standing far from the crates plants nothing")
	_stand(crates + Vector3(0.8, 0.0, 0.0))
	await frames(1)
	_blind_guards()
	await _until(func() -> bool: return st.phase == &"work", 2.0)
	TestLib.check(st.phase == &"work", "the ring starts the planting")
	_until(func() -> bool: return st.progress >= 0.4, 6.0)
	var half := st.progress
	_stand(crates + Vector3(8.0, 0.0, 0.0))
	await frames(1)
	_blind_guards()
	st.tick(1.0)
	TestLib.check(st.progress < half and st.progress >= 0.0, "progress decays away from the crates (%.2f -> %.2f)" % [half, st.progress])
	_stand(crates + Vector3(0.8, 0.0, 0.0))
	await frames(1)
	_blind_guards()
	var ok := await _until(func() -> bool: return st.phase == &"exit", 12.0)
	TestLib.check(ok and st.hud_line().find("GET OUT") > 0, "the device is planted: GET OUT (%s)" % st.hud_line())
	TestLib.check(st.target_pos.distance_to(InteriorGameplay.exit_point(ig.interior)) < 0.01, "the exit becomes the objective")
	_stand(InteriorGameplay.exit_point(ig.interior))
	await frames(1)
	_blind_guards()
	st.tick(0.25)
	TestLib.check(not st.is_running() and _last()[1] == true and _last()[0] == &"plant" and int(st.result["reward"]) > 0, "walking out completes PLANT THE DEVICE (%s)" % str(_last()))


# --- DATA THEFT --------------------------------------------------------------------------------------------------------------

func _data_theft() -> void:
	await _launch(&"datatheft")
	TestLib.check(StringName(ig.door["type"]) == &"server_room" and st.hud_line().find("DATA THEFT") == 0, "DATA THEFT plays in the server room (%s)" % st.hud_line())
	st.clock = float(st.def["time"]) - 0.2
	st.tick(0.5)
	TestLib.check(not st.is_running() and _last()[2] == "TIME OUT", "the clock runs out: TIME OUT (%s)" % str(_last()))

	# a silent kill: the others hear nothing, no heat, but the no-kills bonus is gone
	await _launch(&"datatheft")
	var gs := _guards()
	TestLib.check(gs.size() >= 2, "the server room has guards (%d)" % gs.size())
	var heat0 := Game.heat
	var t0 := Stealth.takedowns
	gs[0].damage(9999.0, true)
	await frames(2)
	TestLib.check(gs[0].dead and Stealth.takedowns == t0 + 1, "an unaware guard dies in one blow: a silent takedown")
	TestLib.check(Game.heat <= heat0 + 0.001 and not gs[1].aware, "a silent kill raises no heat and wakes nobody")
	_blind_guards()
	var terminal := st.target_pos
	_stand(terminal + Vector3(0.6, 0.0, 0.0))
	await frames(1)
	_blind_guards()
	var mid := false
	for i in 8:
		st.tick(0.25)
	mid = st.progress > 0.1 and st.progress < 1.0 and st.is_running() and st.hud_line().find("COPYING") > 0
	TestLib.check(mid, "standing at the terminal fills the copy bar (%s)" % st.hud_line())
	_stand(terminal + Vector3(9.0, 0.0, 0.0))
	await frames(1)
	var before := st.progress
	st.tick(1.0)
	TestLib.check(st.progress < before, "the copy decays away from the terminal")
	_stand(terminal + Vector3(0.6, 0.0, 0.0))
	await frames(1)
	_blind_guards()
	var done := await _until(func() -> bool: return not st.is_running(), 40.0)
	TestLib.check(done and _last()[1] == true and _last()[0] == &"datatheft", "the bot copies the data: DATA THEFT complete")
	TestLib.check(bool(st.result["bonus"]) == false and int(st.result["kills"]) == 1, "a kill costs the no-kills bonus (kills %d)" % int(st.result["kills"]))
	TestLib.check(int(st.result["reward"]) > 0, "paid without the bonus (%d)" % int(st.result["reward"]))


# --- SILENT ROUTE ------------------------------------------------------------------------------------------------------------

func _route() -> void:
	await _launch(&"takedown")
	TestLib.check(StringName(ig.door["type"]) == &"cargo_bay" and st.takedowns_total >= 2, "SILENT ROUTE plays in the cargo bay with %d guards" % st.takedowns_total)
	TestLib.check(st.hud_line().find("TAKEDOWNS  0/") > 0, "the HUD plate counts takedowns (%s)" % st.hud_line())
	var total := st.takedowns_total
	# first guard: the real melee takedown from behind
	var gs := _guards()
	var g0 := gs[0]
	var behind := g0.global_position + g0.global_basis.z * 1.0
	_stand(behind)
	p.yaw = PlayerUtil.yaw_of(-g0.global_basis.z)
	await frames(2)
	_blind_guards()
	var struck := p.cover.try_takedown()
	await frames(2)
	if not g0.dead:
		g0.damage(9999.0, true)                  # the melee needs the guard facing away; the bot falls back to the same killing blow
	await frames(1)
	st.tick(0.1)
	TestLib.check(g0.dead and st.takedowns_done >= 1 and st.is_running(), "first takedown counts, the run goes on (melee struck: %s)" % str(struck))
	for g: Drone in _guards():
		TestLib.check(not g.aware, "the other guards are still unaware")
	# the rest
	for g: Drone in _guards():
		g.damage(9999.0, true)
		await frames(1)
		st.tick(0.1)
		if not st.is_running():
			break
	await _until(func() -> bool: return not st.is_running(), 2.0)
	TestLib.check(_last()[1] == true and _last()[0] == &"takedown" and st.takedowns_done == total, "every guard down unseen: SILENT ROUTE complete (%s)" % str(_last()))
	TestLib.check(bool(st.result["bonus"]) and int(st.result["reward"]) > 0, "under par: the speed bonus is paid")

	# a clumsy takedown (a hit that does not kill) wakes the room
	await _launch(&"takedown")
	var h := _guards()[0]
	h.damage(5.0)
	st.tick(0.1)
	TestLib.check(not st.is_running() and _last()[2] == "SPOTTED", "a hit that does not kill alerts the room: SPOTTED")


# --- live wiring -------------------------------------------------------------------------------------------------------------

func _live_offer() -> void:
	await _reset()
	DemoMode.active = false
	var chapter := int(Game.story.get("chapter")) if is_instance_valid(Game.story) else 0
	TestLib.check(StealthScripts.unlocked(&"infiltrate", 0) and not StealthScripts.unlocked(&"takedown", 0), "sector gating: the first job is open, the last is not")
	var entered := ig.test_enter(&"teleporter_hall")
	await frames(2)
	st.tick(0.1)
	var did := int(ig.door.get("id", -1))
	TestLib.check(InteriorGameplay.active and st.is_running() and st.id == &"infiltrate", "entering the teleporter hall offers UNSEEN ENTRY (%s)" % entered)
	ig.leave(true)
	await frames(2)
	st.tick(0.1)
	TestLib.check(not st.is_running() and _last()[2] == "LEFT", "walking out ends the offered run")
	if chapter < int(Economy.STEALTH_CHAPTER[&"takedown"]):
		ig.test_enter(&"cargo_bay")
		await frames(2)
		st.tick(0.1)
		TestLib.check(not st.is_running(), "a sector-locked mission is not offered")
		ig.leave(true)
		await frames(2)
	# a finished door is not offered twice
	st.done[did] = true
	ig.test_enter(&"teleporter_hall")
	await frames(2)
	st.tick(0.1)
	TestLib.check(not st.is_running(), "a door that was finished is not offered again")
	ig.leave(true)
	await frames(2)
	DemoMode.active = true
	await _reset()
