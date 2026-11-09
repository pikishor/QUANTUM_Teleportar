class_name StoryRunner
extends Node
## Plays THE LONG TOMORROW (docs/STORY.md) on the Mission Board. A child of MissionBoard (`board.story`); on in the live game (`board.story_acts`), off in tools, tests and bots unless a test turns it on.
##
##  * The highlighted STORY card (`card()`) is always the next unfinished mission of StoryActs, in order; it disappears only when all twelve are done.
##  * Starting it (`prepare()`, the board's accept) builds the mission on the world (StoryMissions), gives it the saved step when the player quit in the middle of it, and runs it through
##    CampaignRunner.start_custom like every board mission: checkpoint at every step, instant retry, objective line, MissionGuide, the shared reward ladder. A mission dropped after too many
##    failures is not lost: it is the STORY card again.
##  * Telling it: the briefing cutscene (`story_brief`, once per save) when a mission starts from its first step, a beat cutscene (`story_beat`) when the step named by the mission data begins (once
##    per save), one radio line per step (the campaign runner says it), the outro line when the mission is done, and the finale (`story_end` credits, then the ending cards) after the twelfth.
##    With cutscenes off (the CINE option, tools, tests) every scene is told as radio lines instead, so the story is never lost.
##  * Progress lives in Progress (`story_done`, `story_cp`, `story_seen`: the optional [story] section of save.cfg).

signal mission_started(id: String)
signal mission_finished(id: String, ok: bool)
signal scene_started(key: String)
signal story_finished

var board: MissionBoard
var enabled := false
var scenes_as_radio := 0                   ## scenes told as radio lines instead of a cutscene (tests)
var scenes_played: Array[String] = []      ## keys of the cutscenes that started this session
var running_id := ""                       ## the story mission under way ("" none)
var running_index := -1

var _pending: Array[Dictionary] = []       ## {id: scene id, ctx, key, lines, then_cards}
var _hooked_camp: CampaignRunner
var _local_done := {}                      ## used when there is no Progress (a stub world)
var _local_seen: Array[StringName] = []
var _local_cp := {}
var _watch_end := false


func _ready() -> void:
	add_to_group(&"story_runner")
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)


# --- progress ------------------------------------------------------------------------------------------------------------------------

func _prog() -> Progress:
	return Game.progress as Progress if is_instance_valid(Game.progress) else null


func done_map() -> Dictionary:
	var p := _prog()
	return p.story_done if p != null else _local_done


func seen(key: String) -> bool:
	var p := _prog()
	return (p.story_seen if p != null else _local_seen).has(StringName(key))


func _mark_seen(key: String) -> void:
	var p := _prog()
	if p != null:
		p.story_mark_seen(StringName(key))
	elif not _local_seen.has(StringName(key)):
		_local_seen.append(StringName(key))


func checkpoint() -> Dictionary:
	var p := _prog()
	return p.story_cp if p != null else _local_cp


## Index of the mission the STORY card offers, StoryActs.count() when the story is done.
func index() -> int:
	return StoryActs.next_index(done_map())


func is_finished() -> bool:
	return index() >= StoryActs.count()


## The step the running offer resumes at: the saved one when it is for this mission, else 0.
func resume_step(id: String, n_steps: int) -> int:
	var cp := checkpoint()
	if str(cp.get("id", "")) != id:
		return 0
	return clampi(int(cp.get("step", 0)), 0, maxi(n_steps - 1, 0))


# --- the card and the offer ------------------------------------------------------------------------------------------------------------

## The highlighted STORY card the board shows: {id 0, type story, story_card, title, brief, meta, resume, glyph, reward, route_m, pos}; {} when the story is done or off.
func card() -> Dictionary:
	if not enabled:
		return {}
	var i := index()
	if i >= StoryActs.count():
		return {}
	var m := StoryActs.mission(i)
	if i >= 8:
		AlienSites.start()                                    # the outpost mission places its camp with a short search: warm it before the card is tapped
	var id := str(m["id"])
	var cp := checkpoint()
	var resume := str(cp.get("id", "")) == id and int(cp.get("step", 0)) > 0
	var meta := StoryActs.progress_text(i)
	if resume:
		meta += "  RESUME STEP %d" % (int(cp.get("step", 0)) + 1)
	return {"id": 0, "type": &"story", "story_card": true, "story_id": id, "story_index": i, "title": str(m["title"]), "brief": str(m["card"]), "meta": meta, "resume": resume,
			"act": int(m["act"]), "glyph": &"star", "reward": int(m["reward"]), "route_m": 0.0, "pos": Vector3.INF}


## The offer the board runs for the card ({} when there is none): StoryMissions.build plus the saved step.
func prepare() -> Dictionary:
	var i := index()
	if not enabled or i >= StoryActs.count():
		return {}
	var o := StoryMissions.build(str(StoryActs.mission(i)["id"]))
	if o.is_empty():
		return {}
	o["from_step"] = resume_step(str(o["story_id"]), (o["steps"] as Array).size())
	o["gift"] = MissionRewards.gift_text()
	if o["gift"] != "":
		o["brief"] = str(o["brief"]) + "  PAYS CREDITS + %s" % o["gift"]
	return o


# --- the board's signals -----------------------------------------------------------------------------------------------------------------

## Called by the board when it has started `o` (its `started` signal).
func on_started(o: Dictionary) -> void:
	if not enabled or not bool(o.get("story_act", false)):
		return
	running_id = str(o["story_id"])
	running_index = int(o["story_index"])
	_hook_campaign()
	mission_started.emit(running_id)
	if int(o.get("from_step", 0)) == 0:
		_queue_brief(running_index)
	elif int(o.get("from_step", 0)) > 0:
		_say_line(StoryActs.mission(running_index)["radio"][mini(int(o["from_step"]), (StoryActs.mission(running_index)["radio"] as Array).size() - 1)], "resume.%s" % running_id)
	var p := _prog()
	if p != null:
		p.story_checkpoint(running_id, int(o.get("from_step", 0)))
	else:
		_local_cp = {"id": running_id, "step": int(o.get("from_step", 0))}


## Called by the board when a mission ended (its `finished` signal).
func on_finished(o: Dictionary, ok: bool) -> void:
	if not enabled or not bool(o.get("story_act", false)):
		return
	var id := str(o["story_id"])
	var idx := int(o["story_index"])
	running_id = ""
	running_index = -1
	if ok:
		var p := _prog()
		if p != null:
			p.story_finish(id)
		else:
			_local_done[id] = int(_local_done.get(id, 0)) + 1
			_local_cp = {}
		_say_line(StoryActs.mission(idx)["outro"], "outro.%s" % id)
		if idx >= StoryActs.count() - 1:
			_queue_finale()
	mission_finished.emit(id, ok)
	if ok and is_finished():
		story_finished.emit()


func _hook_campaign() -> void:
	if board == null:
		return
	var k := board._campaign()
	if k == null or k == _hooked_camp:
		return
	_hooked_camp = k
	k.step_started.connect(_on_step_started)
	k.step_completed.connect(_on_step_completed)


func _on_step_started(_ch: int, idx: int, _kind: StringName) -> void:
	if running_id == "" or not enabled:
		return
	var beats: Array = StoryActs.mission(running_index).get("beats", [])
	for n in beats.size():
		var b: Dictionary = beats[n]
		if int(b["step"]) != idx:
			continue
		var key := "beat_%s_%d" % [running_id, n]
		if seen(key):
			continue
		_mark_seen(key)
		_queue({"id": &"story_beat", "ctx": {"index": running_index, "beat": b}, "key": key, "lines": b["lines"]})


func _on_step_completed(_ch: int, idx: int, _kind: StringName) -> void:
	if running_id == "" or not enabled:
		return
	var p := _prog()
	if p != null:
		p.story_checkpoint(running_id, idx + 1)
	else:
		_local_cp = {"id": running_id, "step": idx + 1}


# --- scenes ----------------------------------------------------------------------------------------------------------------------------

func _queue_brief(i: int) -> void:
	var m := StoryActs.mission(i)
	var key := "brief_%s" % str(m["id"])
	if seen(key):
		return
	_mark_seen(key)
	_queue({"id": &"story_brief", "ctx": {"index": i}, "key": key, "lines": m["brief"], "radio_only": i == 0})   # LANDFALL follows the intro cinematic: radio only, the player moves at once


func _queue_finale() -> void:
	if seen("end"):
		return
	_mark_seen("end")
	_queue({"id": &"story_end", "ctx": {}, "key": "end", "lines": StoryActs.END_SUBS, "then_cards": true})


func _queue(item: Dictionary) -> void:
	_pending.append(item)


## True while a scene is waiting or playing.
func busy() -> bool:
	var cin := Cinematics.instance
	return not _pending.is_empty() or (cin != null and cin.active and str(cin.active_id).begins_with("story_"))


func _process(_delta: float) -> void:
	if _pending.is_empty() or not enabled:
		return
	if Game.state != &"play" or not is_instance_valid(Game.player):
		return
	var cin := Cinematics.instance
	if cin != null and cin.active:
		return
	var item: Dictionary = _pending.pop_front()
	var key := str(item["key"])
	if cin != null and cin.scenes_allowed() and Game.is_playing() and not bool(item.get("radio_only", false)):
		if cin.play(StringName(str(item["id"])), item["ctx"] as Dictionary):
			scenes_played.append(key)
			scene_started.emit(key)
			if bool(item.get("then_cards", false)):
				_watch_end = true
				if not cin.finished.is_connected(_on_scene_end):
					cin.finished.connect(_on_scene_end)
			return
	scenes_as_radio += 1                                       # cutscenes off (option, tools, tests): the same words as radio lines
	for l: Variant in item["lines"] as Array:
		var d: Dictionary = l
		_say_line(d, "scene.%s.%s" % [key, str(d["t"]).md5_text().substr(0, 6)])
	if bool(item.get("then_cards", false)):
		_ending_cards()
	scene_started.emit(key)


func _on_scene_end(id: StringName, _skipped: bool) -> void:
	if id == &"story_end" and _watch_end:
		_watch_end = false
		_ending_cards()


func _ending_cards() -> void:
	var st: Object = Game.story if is_instance_valid(Game.story) else null
	if st != null and st.has_method(&"start_cards"):
		st.call(&"start_cards", StoryActs.ENDING, &"epilogue")


func _say_line(l: Dictionary, id: String) -> void:
	var st: Object = Game.story if is_instance_valid(Game.story) else null
	if st != null and st.has_method(&"say"):
		st.call(&"say", str(l.get("s", StoryActs.O)), str(l.get("t", "")), "story." + id, 0.0, 1)
	else:
		Game.say(str(l.get("t", "")), 3.0)


## A new game: nothing under way, scenes forgotten (progress is reset by Progress itself).
func reset_session() -> void:
	_pending.clear()
	running_id = ""
	running_index = -1
	scenes_played.clear()
	scenes_as_radio = 0
	_local_done.clear()
	_local_seen.clear()
	_local_cp = {}
