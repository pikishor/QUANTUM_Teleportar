class_name HeistRunner
extends Node
## The three heist missions (Game.missions.heists, wave 71): data and rules in heist_scripts.gd. A run is a chapter dictionary of campaign steps (HeistScripts.chapter) played by the
## CampaignRunner through start_custom(), so every stage (reach, hack, defend, rift_hold, convoy_intercept, heist, escape, kill_target) is the existing, tested step. This node adds what
## is new: the plan (heist, approach, crew), the story chapter's checkpoint saved before and restored after, the failure budget (HeistScripts.MAX_FAILS), the pay (HeistScripts.reward,
## Economy.HEIST_REPLAY on a repeat), the tally (Progress.heist_done) and the crew (the Companion ally for the run).
## Live wiring: the pause shop's HEISTS button opens the planning screen (scripts/ui/heist_board.gd); LAUNCH calls start(). The DEMO menu HEIST tab starts any heist + approach at once.
## API: can_start(id) · start(id, approach, crew) · abort(reason) · is_running() · stage() · result (last run) · state (&"idle" &"running")

signal started(id: StringName, approach: StringName)
signal finished(id: StringName, ok: bool, reason: String)

var id: StringName = &""
var approach: StringName = &"stealth"
var crew := false
var state: StringName = &"idle"
var fails := 0
var result: Dictionary = {}             ## {id, approach, ok, reason, reward, replay, fails, crew}

var _camp: CampaignRunner
var _saved_cp: Dictionary = {}
var _had_story := false
var _ended := false


func _ready() -> void:
	add_to_group(&"heists")
	Game.new_game.connect(abort.bind("RESET"))


func _campaign() -> CampaignRunner:
	if _camp == null or not is_instance_valid(_camp):
		var m := Game.missions as Missions
		_camp = m.campaign if m != null else null
		if _camp != null:
			_camp.chapter_completed.connect(_on_done)
			_camp.step_failed.connect(_on_step_failed)
	return _camp


func is_running() -> bool:
	return state == &"running"


func _chapter() -> int:
	return int(Game.story.get("chapter")) if is_instance_valid(Game.story) else 0


## 1-based stage number and count of the running heist ("" parts when idle).
func stage() -> Dictionary:
	var k := _campaign()
	if not is_running() or k == null:
		return {"index": 0, "count": 0}
	return {"index": k.step_index + 1, "count": k.steps.size()}


## True when `hid` could start now: sector open (or DEMO), nothing of ours or another side/chase/stealth job runs, the hero is on the street.
func can_start(hid: StringName) -> bool:
	if is_running() or not HeistScripts.DEFS.has(hid) or not is_instance_valid(Game.player) or _campaign() == null:
		return false
	if not HeistScripts.unlocked(hid, _chapter()):
		return false
	var m := Game.missions as Missions
	if m == null:
		return false
	if m.sides != null and m.sides.active:
		return false
	if m.chases != null and m.chases.is_running():
		return false
	if m.stealth != null and m.stealth.is_running():
		return false
	if m.contracts != null and bool(m.contracts.is_active()):
		return false
	var ig := InteriorGameplay.instance
	return not InteriorGameplay.active and not (ig != null and is_instance_valid(ig) and ig.busy)


func start(hid: StringName, ap: StringName = &"stealth", with_crew := false) -> bool:
	if not can_start(hid) or not HeistScripts.APPROACH_DEFS.has(ap):
		return false
	var k := _campaign()
	var prog := Game.progress as Progress
	_saved_cp = {}
	_had_story = k.is_running() and k._demo_idx < 0
	if _had_story:
		_saved_cp = k.get_checkpoint().duplicate(true)             # the story chapter comes back from here when the heist ends
	id = hid
	approach = ap
	crew = with_crew
	fails = 0
	_ended = false
	result = {}
	if not k.start_custom(HeistScripts.chapter(hid, ap)):
		id = &""
		return false
	state = &"running"
	if crew:
		var c := Companion.current
		if c != null and not c.active:
			c.recruit("heist")
	if prog != null:
		prog.changed.emit()
	Game.say("%s  %s" % [HeistScripts.title(hid), HeistScripts.approach_title(ap)], 3.0)
	Sfx.play(&"mission_start")
	started.emit(hid, ap)
	return true


func abort(reason := "ABANDONED") -> void:
	if is_running():
		_end(false, reason)


func _on_step_failed(_ch: int, _idx: int, _k: StringName, why: String) -> void:
	if not is_running():
		return
	fails += 1
	if fails >= HeistScripts.MAX_FAILS:
		_end(false, why)


func _on_done(_ch: int) -> void:
	if is_running():
		_end(true, "")


func _end(ok: bool, reason: String) -> void:
	if _ended:
		return
	_ended = true
	var hid := id
	var ap := approach
	var pay := 0
	var replay := false
	var prog := Game.progress as Progress
	if ok:
		var rep := prog.reputation if prog != null else 0
		replay = prog != null and int(prog.heist_done.get(hid, 0)) > 0
		pay = HeistScripts.reward(hid, ap, _chapter(), rep, replay)
		if prog != null:
			prog.add_credits(pay)
			prog.bonus_score(pay)
			prog.add_reputation(HeistScripts.WIN_REP)
			prog.heist_done[hid] = int(prog.heist_done.get(hid, 0)) + 1
			prog.contracts_done += 1
		else:
			Game.add_score(pay)
	elif reason != "RESET" and reason != "DEMO" and prog != null:
		prog.add_reputation(HeistScripts.FAIL_REP)
	result = {"id": hid, "approach": ap, "ok": ok, "reason": reason, "reward": pay, "replay": replay, "fails": fails, "crew": crew}
	state = &"idle"
	id = &""
	var k := _campaign()
	if k != null:
		k.abort()                                                     # drops the heist chapter from the story slot and stops the step
		if _had_story and not _saved_cp.is_empty() and reason != "RESET":
			_saved_cp["tp"] = false                                    # back to the chapter where the hero stands, not where its checkpoint was
			k.resume(_saved_cp)
	if crew:
		var c := Companion.current
		if c != null and c.active and c.reason == "heist":
			c.dismiss()
	Sfx.play(&"ui_contract_complete" if ok else &"ui_contract_fail")
	if ok:
		Game.say("%s COMPLETE  +%d CREDITS" % [HeistScripts.title(hid), pay], 4.0)
	else:
		Game.say("%s FAILED  %s" % [HeistScripts.title(hid), reason], 4.0)
	finished.emit(hid, ok, reason)
