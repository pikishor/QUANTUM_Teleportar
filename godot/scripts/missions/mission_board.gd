class_name MissionBoard
extends Node
## The Mission Board (docs/DESIGN.md core loop; Game.missions.board). It keeps THREE easy missions on offer near the hero, drawn from every mission type of the game (kill patrol,
## destroy vehicle, rescue, escort, delivery, heist, stealth, chase, convoy intercept, arena wave, boss-lite, bounty, demolition, hijack and deliver, defend, hack), starts the one the
## player taps, pays it by distance, and offers the next set the moment it is done. The campaign chapters show up as one highlighted STORY card above the three.
##
## How a mission runs: a mission is a chapter dictionary of 2-3 campaign steps (CampaignSteps; the two new kinds `smash` and `sneak` and the `car` / `on_foot` flags were added for it) played by the
## CampaignRunner through start_custom(), exactly like the heists: so every mission has the runner's checkpoint at each step, its instant retry (`retry_pause` is RETRY_PAUSE here: a failed step
## restarts after about a second), the objective line, the beacon, the minimap markers and MissionGuide's stuck handling. The board only generates, offers, starts, pays and re-offers.
## Pay: base per type + PAY_PER_M per metre of the route, +PAY_TIER per tier (a tier every 4 finished missions). MissionRewards (the sibling system) adds the weapon / mod / upgrade unlock through the
## campaign's chapter_completed signal, so a board mission needs no reward call of its own; the ResultCard's NEXT calls offer_next().
## Live game only (not under Game.autostart, which tools / tests / bots use): `take_over` switches the old flow off (the core hunt's beams, the random contract offers, the story chapter that
## armed itself): the board starts the first mission FIRST_DELAY seconds after PLAY and the story is the STORY card. Tests turn it on with `take_over = true` or call accept() directly.

signal offers_changed
signal started(offer: Dictionary)
signal finished(offer: Dictionary, ok: bool, reward: int)

const OFFERS := 3
const FIRST_DELAY := 3.5               ## seconds of play (cards over, no cutscene) before the first mission of a new game starts by itself
const RETRY_PAUSE := 1.2               ## seconds a failed step waits before it restarts ("instant retry")
const MAX_FAILS := 5                   ## failures of one mission before it is dropped and the board offers new ones (a mission never traps the player)
const STALE_DIST := 170.0              ## offers generated this far from where the hero stands now are regenerated when the board opens
const PAY_PER_M := 0.55
const PAY_TIER := 0.1
const TIER_EVERY := 4
const MOVE_HINT_WINDOW := 20.0         ## the first seconds of the first mission: the "how to move" line shows at once and again until the hero has walked
const MOVE_NEED := 4.0                 ## metres walked that end the hint
const RECENT := 4                      ## the last types offered are not offered again while another choice exists

## id -> {title, brief, base credits, weight, glyph (MapIcons kind), needs: [what the city must have]}.
const DEFS := {
	&"patrol": {"title": "KILL PATROL", "brief": "Take out two Vael patrols on the street.", "base": 150, "weight": 4, "glyph": &"target"},
	&"vehicle": {"title": "DESTROY VEHICLE", "brief": "Wreck two armoured cars before they leave.", "base": 170, "weight": 3, "glyph": &"car", "needs": [&"cars"]},
	&"rescue": {"title": "RESCUE", "brief": "Clear the captors, then bring the hostage to safety.", "base": 200, "weight": 3, "glyph": &"person"},
	&"escort": {"title": "ESCORT", "brief": "Walk the VIP across the district alive.", "base": 190, "weight": 3, "glyph": &"person"},
	&"courier": {"title": "DELIVERY", "brief": "Pick up the package and run it to the buyer.", "base": 130, "weight": 4, "glyph": &"dest"},
	&"heist": {"title": "HEIST", "brief": "Go in, take the data, get out and lose the patrols.", "base": 320, "weight": 2, "glyph": &"door", "needs": [&"doors"]},
	&"stealth": {"title": "STEALTH", "brief": "Slip past the guards without being seen.", "base": 170, "weight": 3, "glyph": &"eye"},
	&"chase": {"title": "CHASE", "brief": "Run down the fleeing car.", "base": 200, "weight": 3, "glyph": &"car", "needs": [&"cars"]},
	&"convoy": {"title": "CONVOY INTERCEPT", "brief": "Stop the convoy: wreck, collapse or entangle every car.", "base": 260, "weight": 2, "glyph": &"car", "needs": [&"cars"]},
	&"arena": {"title": "ARENA WAVE", "brief": "Beat the waves that rush you. Finish them all.", "base": 250, "weight": 3, "glyph": &"target"},
	&"boss": {"title": "BOSS-LITE", "brief": "Track down the elite and his two guards.", "base": 280, "weight": 2, "glyph": &"skull"},
	&"bounty": {"title": "BOUNTY", "brief": "Find the marked target, then collect the bounty.", "base": 220, "weight": 3, "glyph": &"skull"},
	&"demolition": {"title": "DEMOLITION", "brief": "Smash the props at two sites.", "base": 140, "weight": 3, "glyph": &"blast"},
	&"hijack": {"title": "HIJACK AND DELIVER", "brief": "Take any car and drive it to the buyer.", "base": 180, "weight": 3, "glyph": &"car", "needs": [&"cars"]},
	&"defend": {"title": "DEFEND", "brief": "Hold the position while Vael waves hit it.", "base": 230, "weight": 3, "glyph": &"shield"},
	&"hack": {"title": "HACK", "brief": "Hold the node's ring until the upload ends.", "base": 190, "weight": 3, "glyph": &"node"},
}
const TYPES: Array[StringName] = [&"patrol", &"vehicle", &"rescue", &"escort", &"courier", &"heist", &"stealth", &"chase", &"convoy", &"arena", &"boss", &"bounty", &"demolition", &"hijack", &"defend", &"hack"]

## Turned on by the live game (see the class comment); tests set it themselves.
var take_over := false
## The board opens by itself after a mission (a modal screen: off under tools, tests and bots).
var auto_open := false
## The big world's missions (WorldMissions: airport heist, helicopter extraction, mountain pursuit, river chase, air race, plane delivery) join the offers by location. On in the live game
## (Missions turns it on with the take-over), off for the tests of the sixteen city types.
var world_offers := false
## THE LONG TOMORROW (docs/STORY.md, scripts/story/story_runner.gd): the STORY card is the next of twelve story missions and starts it with a briefing cutscene. On in the live game
## (Missions turns it on with the take-over), off for the tests of the old chapter card (the campaign chapters then stay the STORY card).
var story_acts := false
var story: StoryRunner
var offers: Array[Dictionary] = []
var active: Dictionary = {}            ## the running offer ({} when none)
var state: StringName = &"idle"        ## idle | running | story
var last_result: Dictionary = {}       ## {title, ok, reward, reason}: the board shows it above the offers
var done_count := 0                    ## board missions finished this session
var failed_count := 0
var offered_total := 0
var types_done: Dictionary = {}        ## type -> finished count (this session)
var rng := RandomNumberGenerator.new()
var first_pending := false             ## a new game is waiting for its first mission
var move_hints := 0

var _camp: CampaignRunner
var _hooked := false
var _from := Vector3.INF               ## where the offers were generated
var _recent: Array[StringName] = []
var _serial := 0
var _fails := 0
var _saved_cp: Dictionary = {}
var _had_story := false
var _first_t := 0.0
var _hint_t := 0.0
var _walked := 0.0
var _last_pos := Vector3.INF
var _first_run := false
var _ended := false


func _ready() -> void:
	add_to_group(&"mission_board")
	rng.randomize()
	Game.new_game.connect(_on_new_game)
	Game.respawn.connect(_on_respawn)
	story = StoryRunner.new()
	story.name = "Story"
	story.board = self
	add_child(story)
	started.connect(func(o: Dictionary) -> void: story.on_started(o))
	finished.connect(func(o: Dictionary, ok: bool, _pay: int) -> void: story.on_finished(o, ok))


## Switches THE LONG TOMORROW on (the live game) or off (the older chapter card).
func set_story_acts(on: bool) -> void:
	story_acts = on
	if story != null:
		story.enabled = on


func _campaign() -> CampaignRunner:
	if _camp == null or not is_instance_valid(_camp):
		var m := Game.missions as Missions
		_camp = m.campaign if m != null else null
	if _camp != null and not _hooked:
		_hooked = true
		_camp.chapter_completed.connect(_on_chapter_done)
		_camp.step_failed.connect(_on_step_failed)
		_camp.step_completed.connect(_on_step_done)
	return _camp


## Switch the old flow off and the board on (the live game; MissionBoard.take_over for tests).
func set_take_over(on: bool) -> void:
	take_over = on
	auto_open = on
	var m := Game.missions as Missions
	if m != null:
		m.board_mode = on
		if m.contracts != null:
			m.contracts.enabled = not on                       # the random contract offers are the board's job now
	var k := _campaign()
	if k != null:
		k.auto_story = not on                                  # the story chapter starts from the STORY card, never by itself
		k.ignore_tutorial = on                                 # the first mission does not wait for the training


func is_running() -> bool:
	return state == &"running"


func _chapter() -> int:
	return int(Game.story.get("chapter")) if is_instance_valid(Game.story) and Game.story.get("chapter") != null else 0


func tier() -> int:
	var prog := Game.progress as Progress
	var n := maxi(done_count, prog.contracts_done if prog != null else 0)
	return clampi(n / TIER_EVERY, 0, 3)


# --- generating offers --------------------------------------------------------------------------------------------------------

func _eligible(t: StringName) -> bool:
	var needs: Array = DEFS[t].get("needs", [])
	if needs.has(&"cars") and not (is_instance_valid(Game.vehicles) and Game.vehicles.has_method(&"spawn_traffic")):
		return false
	if needs.has(&"doors"):
		var ig := InteriorGameplay.instance
		if ig == null or not is_instance_valid(ig) or ig.doors().is_empty():
			return false
	return true


## A weighted pick of `n` distinct types that skips the recently offered ones while the pool allows.
func pick_types(n: int, banned: Array = []) -> Array[StringName]:
	var out: Array[StringName] = []
	var pool: Array[StringName] = []
	for t: StringName in TYPES:
		if _eligible(t) and not banned.has(t):
			pool.append(t)
	var fresh: Array[StringName] = pool.filter(func(t: StringName) -> bool: return not _recent.has(t))
	if fresh.size() >= n:
		pool = fresh
	while out.size() < n and not pool.is_empty():
		var total := 0.0
		for t: StringName in pool:
			total += float(DEFS[t]["weight"])
		var r := rng.randf() * total
		var chosen := pool[pool.size() - 1]
		for t: StringName in pool:
			r -= float(DEFS[t]["weight"])
			if r <= 0.0:
				chosen = t
				break
		out.append(chosen)
		pool.erase(chosen)
	return out


## Builds the three offers around `origin` (the hero's position by default). Returns them.
func generate(origin := Vector3.INF, types: Array = []) -> Array[Dictionary]:
	var k := _campaign()
	if not origin.is_finite():
		origin = _hero_pos()
	_from = origin
	offers.clear()
	var picks: Array[StringName] = []
	for t: Variant in types:
		picks.append(StringName(str(t)))
	if picks.is_empty():
		picks = pick_types(OFFERS)
		if world_offers:
			picks = WorldMissions.inject(picks, origin, rng)
	for t: StringName in picks:
		var o := build(t, origin)
		if not o.is_empty():
			offers.append(o)
		_recent.append(t)
	while _recent.size() > RECENT:
		_recent.pop_front()
	offered_total += offers.size()
	offers_changed.emit()
	return offers


func _hero_pos() -> Vector3:
	var p := Game.player
	if not is_instance_valid(p):
		return Game.SPAWN
	var v := p.get(&"vehicle") as Node3D
	return v.global_position if v != null and is_instance_valid(v) else p.global_position


## One offer of type `t` near `origin`: {id, type, title, brief, glyph, steps, chapter, route_m, reward, pos, tier}.
func build(t: StringName, origin: Vector3, first := false) -> Dictionary:
	if WorldMissions.DEFS.has(t):
		return _build_world(t, origin)
	if not DEFS.has(t):
		return {}
	var tr := tier()
	_serial += 1
	var seed_val := hash("%s|%d|%d" % [t, _serial, rng.randi()])
	var r := RandomNumberGenerator.new()
	r.seed = seed_val
	var steps := MissionBoardSteps.steps(t, tr, r) if not first else MissionBoardSteps.first_steps(r)
	var k := _campaign()
	var route := 0.0
	var cur := origin
	var first_pos := Vector3.INF
	var saved_state := 0
	if k != null:
		saved_state = k.rng.state
		k.rng.seed = seed_val
	for st: Dictionary in steps:
		var kind := StringName(str(st["kind"]))
		if kind in [&"survive", &"escape", &"heist", &"enter_interior"]:
			continue
		var rg: Array = st.get("range", [])
		if rg.size() != 2:
			var d: Array = CampaignSteps.KIND_DATA[kind]["dist"]
			rg = d
		var p := _street_point(k, cur, float(rg[0]), float(rg[1]))
		st["pos"] = p
		route += absf(p.x - cur.x) + absf(p.z - cur.z)               # the grid the route line follows
		if not first_pos.is_finite():
			first_pos = p
		cur = p
	if k != null:
		k.rng.state = saved_state
	if t == &"heist":
		route += 140.0
	elif t == &"survive" or t == &"arena" or t == &"defend":
		route += 40.0
	var def: Dictionary = DEFS[t] if not first else {"title": "FIRST JOB", "brief": "Follow the beacon and clear the lookout.", "base": 120, "glyph": &"dest"}
	var reward := pay_for(float(def["base"]), route, tr)
	var gift := MissionRewards.gift_text()
	var brief := str(def["brief"]) + ("  PAYS CREDITS + %s" % gift if gift != "" else "")
	var offer := {
		"id": _serial, "type": t if not first else &"first", "title": str(def["title"]), "brief": brief, "gift": gift, "glyph": def["glyph"],
		"steps": steps, "route_m": route, "reward": reward, "pos": first_pos if first_pos.is_finite() else origin, "tier": tr, "story": false,
		"chapter": {"id": "board_%d" % _serial, "title": str(def["title"]), "clears_sector": false, "steps": steps},
	}
	return offer


## An offer of the big world: the same shape as a city offer (id, type, title, brief, glyph, steps, chapter, route_m, reward, pos, tier); the places come from WorldSites.
func _build_world(t: StringName, origin: Vector3) -> Dictionary:
	var tr := tier()
	_serial += 1
	var r := RandomNumberGenerator.new()
	r.seed = hash("%s|%d|%d" % [t, _serial, rng.randi()])
	var rec := WorldMissions.build(t, tr, origin, r)
	if rec.is_empty():
		return {}
	var reward := WorldMissions.pay_for(float(rec["base"]), float(rec["route_m"]), tr)
	var gift := MissionRewards.gift_text()
	var brief := str(rec["brief"]) + ("  PAYS CREDITS + %s" % gift if gift != "" else "")
	var steps: Array[Dictionary] = rec["steps"]
	return {
		"id": _serial, "type": t, "title": str(rec["title"]), "brief": brief, "gift": gift, "glyph": rec["glyph"], "steps": steps, "route_m": float(rec["route_m"]), "reward": reward,
		"pos": rec["pos"], "tier": tr, "story": false, "world": true,
		"chapter": {"id": "board_%d" % _serial, "title": str(rec["title"]), "clears_sector": false, "steps": steps},
	}


func _street_point(k: CampaignRunner, center: Vector3, rmin: float, rmax: float) -> Vector3:
	if k != null:
		return k.road_point(center, rmin, rmax, true)
	var a := rng.randf() * TAU
	var d := (rmin + rmax) * 0.5
	return Vector3(center.x + cos(a) * d, 0.0, center.z + sin(a) * d)


## Credits of a mission: base + PAY_PER_M per metre of route, + PAY_TIER per tier, in whole fives.
static func pay_for(base: float, route_m: float, tier_n: int) -> int:
	return maxi(5, int(round((base + PAY_PER_M * route_m) * (1.0 + PAY_TIER * float(tier_n)) / 5.0)) * 5)


## The highlighted story card: {id: "story", title, brief, chapter (index), story: true}; {} when the campaign has no chapter left to play.
func story_offer() -> Dictionary:
	if story_acts and story != null:
		return story.card()                                    # the next story mission ({} once the twelve are done: the card goes away)
	var k := _campaign()
	if k == null:
		return {}
	var ch := _chapter()
	if not k.has_steps(ch):
		return {}
	var title := CampaignRunner.chapter_title(ch)
	return {"id": 0, "type": &"story", "title": title, "brief": "Chapter %d of the story." % (ch + 1), "glyph": &"star", "story": true, "chapter_index": ch,
			"reward": 0, "route_m": 0.0, "pos": Vector3.INF}


## Distance in metres from the hero to the first goal of an offer (0 when it has none).
func distance_to(o: Dictionary) -> float:
	var p: Vector3 = o.get("pos", Vector3.INF)
	var h := _hero_pos()
	if not p.is_finite() or not h.is_finite():
		return 0.0
	return Vector2(p.x - h.x, p.z - h.z).length()


## The board's screen opens: fresh offers when none exist or the hero walked away from where they were made.
func refresh_if_stale() -> void:
	var h := _hero_pos()
	if offers.is_empty() or not _from.is_finite() or Vector2(h.x - _from.x, h.z - _from.z).length() > STALE_DIST:
		generate()


# --- starting a mission ----------------------------------------------------------------------------------------------------

func can_start() -> bool:
	if not is_instance_valid(Game.player) or _campaign() == null:
		return false
	var m := Game.missions as Missions
	if m == null:
		return false
	if state == &"running":
		return false
	if m.sides != null and m.sides.active:
		return false
	if m.heists != null and m.heists.is_running():
		return false
	if m.chases != null and m.chases.is_running():
		return false
	if m.stealth != null and m.stealth.is_running():
		return false
	if m.contracts != null and bool(m.contracts.is_active()):
		return false
	var ig := InteriorGameplay.instance
	return not InteriorGameplay.active and not (ig != null and is_instance_valid(ig) and ig.busy)


## Starts offer `index` (0..2; -1 = the STORY card). The game must be able to run it (see can_start). Returns false when it cannot.
func accept(index: int) -> bool:
	var o: Dictionary = story_offer() if index < 0 else (offers[index] if index >= 0 and index < offers.size() else {})
	if o.is_empty():
		return false
	return accept_offer(o)


func accept_offer(o: Dictionary) -> bool:
	var k := _campaign()
	if k == null or not can_start():
		return false
	if bool(o.get("story_card", false)):
		o = story.prepare()                                    # the story mission built on the world (with the step a quit left it at)
		if o.is_empty():
			return false
	if bool(o.get("story", false)):
		return _start_story(int(o["chapter_index"]))
	_saved_cp = {}
	_had_story = k.is_running() and k._demo_idx < 0
	if _had_story:
		_saved_cp = k.get_checkpoint().duplicate(true)
	_fails = 0
	_ended = false
	k.retry_pause = RETRY_PAUSE
	k.ignore_tutorial = true
	if not k.start_custom(o["chapter"] as Dictionary, int(o.get("from_step", 0))):
		k.retry_pause = CampaignRunner.RETRY_PAUSE
		return false
	active = o
	state = &"running"
	last_result = {}
	if Game.state == &"paused" or Game.state == &"menu":
		pass
	Sfx.play(&"mission_start")
	started.emit(o)
	return true


func _start_story(ch: int) -> bool:
	var k := _campaign()
	k.retry_pause = CampaignRunner.RETRY_PAUSE
	if not k.start_chapter(ch, 0, true):
		return false
	active = {"type": &"story", "title": CampaignRunner.chapter_title(ch), "story": true}
	state = &"story"
	Sfx.play(&"mission_start")
	started.emit(active)
	return true


## RETRY the running step now (the board screen button).
func retry_step() -> bool:
	var k := _campaign()
	return k != null and state == &"running" and k.retry()


## Drops the running mission (the board screen's ABANDON, a new game). The story checkpoint comes back.
func abandon(reason := "ABANDONED") -> void:
	if state == &"running":
		_end(false, reason)
	elif state == &"story":
		var k := _campaign()
		if k != null:
			k.abort()
		state = &"idle"
		active = {}


func _on_new_game() -> void:
	var was := state
	if was != &"idle":
		state = &"idle"
		active = {}
	offers.clear()
	_from = Vector3.INF
	_recent.clear()
	last_result = {}
	_fails = 0
	done_count = 0
	failed_count = 0
	types_done.clear()
	if story != null:
		story.reset_session()
	var prog := Game.progress as Progress
	_first_run = take_over and not (prog != null and bool(prog.get(&"_continue_pending")))
	first_pending = _first_run
	_first_t = 0.0
	_hint_t = 0.0
	_walked = 0.0
	_last_pos = Vector3.INF
	move_hints = 0
	var k := _campaign()
	if k != null:
		k.retry_pause = CampaignRunner.RETRY_PAUSE


func _on_respawn() -> void:
	pass


# --- the running mission ------------------------------------------------------------------------------------------------------

func _on_step_failed(_ch: int, _idx: int, _kind: StringName, _why: String) -> void:
	if state != &"running":
		return
	_fails += 1
	if _fails >= MAX_FAILS:
		_end(false, "TOO MANY TRIES")


func _on_step_done(_ch: int, _idx: int, _kind: StringName) -> void:
	if state != &"running":
		return
	var pl := Game.player as Player
	if is_instance_valid(pl) and not pl.is_dead() and Difficulty.current <= 1:
		pl.heal(pl.max_hp * (0.45 if Difficulty.current == 0 else 0.25))       # generous: a step done tops the hero up
	var m := Game.missions as Missions
	if m != null and Difficulty.current <= 1 and is_instance_valid(pl):
		var side := pl.global_basis.x * 6.0                                    # and leaves a health pack next to him for the next fight
		m.drop(&"health", pl.global_position + side)


func _on_chapter_done(_ch: int) -> void:
	if state == &"running":
		_end(true, "")
	elif state == &"story":
		state = &"idle"                                          # the story chapter clears the sector: the win screen, NEXT SECTOR, then the board offers again
		active = {}
		offers.clear()


func _end(ok: bool, reason: String) -> void:
	if _ended:
		return
	_ended = true
	var o := active
	var pay := 0
	var prog := Game.progress as Progress
	if ok:
		pay = int(o.get("reward", 0))
		if prog != null:
			prog.add_credits(pay)
			prog.bonus_score(pay)
			prog.add_reputation(4)
			prog.contracts_done += 1
		else:
			Game.add_score(pay)
		done_count += 1
		types_done[o.get("type", &"")] = int(types_done.get(o.get("type", &""), 0)) + 1
	else:
		failed_count += 1
	last_result = {"title": str(o.get("title", "")), "ok": ok, "reward": pay, "reason": reason, "type": o.get("type", &"")}
	state = &"idle"
	active = {}
	var k := _campaign()
	if k != null:
		k.retry_pause = CampaignRunner.RETRY_PAUSE
		k.abort()                                               # drops the board chapter from the story slot and stops the step
		if _had_story and not _saved_cp.is_empty() and reason != "RESET":
			_saved_cp["tp"] = false
			k.resume(_saved_cp)
			state = &"story"
			active = {"type": &"story", "title": CampaignRunner.chapter_title(int(_saved_cp.get("chapter", 0))), "story": true}
		elif prog != null and not _had_story:
			prog.clear_checkpoint()
	if ok:
		Game.say("%s COMPLETE  +%d CREDITS" % [last_result["title"], pay], 3.0)
	else:
		Game.say("%s DROPPED  %s" % [last_result["title"], reason], 3.0)
	generate()
	finished.emit(o, ok, pay)
	if auto_open and not ok:
		offer_next()
	elif auto_open and not _card_will_show() and is_inside_tree():
		get_tree().create_timer(2.0).timeout.connect(func() -> void:       # no result card: the board comes up by itself a moment after the toast
			if state == &"idle" and Game.state == &"play":
				offer_next())


## True while the sibling's ResultCard is live (it opens after a finished mission and its NEXT button calls offer_next()).
func _card_will_show() -> bool:
	return ResultCard.enabled and get_tree().get_first_node_in_group(&"result_card") != null


## The ResultCard's NEXT (or a dropped mission): open the board with fresh offers. A no-op while a mission runs.
func offer_next() -> void:
	if state == &"running":
		return
	refresh_if_stale()
	var hud := get_tree().get_first_node_in_group(&"hud") as Hud if is_inside_tree() else null
	if hud != null and Game.state in [&"play", &"paused"]:
		hud.open_board()


# --- the first minutes ----------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not take_over or Game.state != &"play":
		return
	var h := _hero_pos()
	if first_pending:
		_tick_first(delta)
	elif _first_run and state == &"running" and (String(active.get("type", &"")) == &"first" or int(active.get("story_index", -1)) == 0):
		_tick_move_hint(delta, h)
	if h.is_finite():
		_last_pos = h


func _tick_first(delta: float) -> void:
	var st: Object = Game.story if is_instance_valid(Game.story) else null
	if st != null and st.has_method(&"cards_active") and bool(st.call(&"cards_active")):
		return                                                  # the prologue lines (at most 3 s) are the only thing that can hold it
	if not is_instance_valid(Game.player) or InteriorGameplay.active:
		return
	_first_t += delta
	if _first_t < FIRST_DELAY:
		return
	first_pending = false
	_hint_t = 0.0
	_walked = 0.0
	_last_pos = _hero_pos()
	if story_acts and story != null and story.enabled and story.index() == 0:
		var card := story.card()                                # THE LONG TOMORROW: the first job is LANDFALL (told as radio, no cutscene: the player moves at once)
		if not card.is_empty() and accept_offer(card):
			return
	var o := build(&"patrol", _hero_pos(), true)
	if o.is_empty() or not accept_offer(o):
		generate()                                              # could not start (a card, a cutscene): the board is there anyway


func _tick_move_hint(delta: float, h: Vector3) -> void:
	_hint_t += delta
	if _last_pos.is_finite() and h.is_finite():
		_walked += Vector2(h.x - _last_pos.x, h.z - _last_pos.z).length()
	if _walked >= MOVE_NEED or _hint_t > MOVE_HINT_WINDOW or move_hints >= 3:
		return
	var due := 0.4 if move_hints == 0 else (8.0 if move_hints == 1 else 15.0)
	if _hint_t >= due:
		move_hints += 1
		Game.say(MissionGuide.move_hint_text(), 4.0)
