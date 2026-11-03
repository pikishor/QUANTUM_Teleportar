class_name Story
extends Node
## The story layer (Game.story): prologue cards at DEPLOY, chapter banners, radio subtitles (ORACLE / KESTREL / VAEL BROADCAST) typed with a radio beep,
## a short objective line, death quotes, chapter end cards and an epilogue. All words live in story_data.gd. It reacts to the Game signals
## (new_game, respawn, next_sector, heat_changed, message, player_died, sector_cleared) and polls the missions, the player's quantum powers, vehicle and
## health once per frame while playing. Drawing is StoryView (its own CanvasLayer above the HUD). No per-frame allocation beyond short strings.
## Timers run only in the states play / dead / win (never while paused or in the menu); the radio only while playing.

signal line_started(id: String, speaker: String)
signal chapter_started(index: int)
signal cards_finished(kind: StringName)

const CPS_LINE := 46.0              ## radio typing speed, characters per second
const CPS_CARD := 34.0
const HOLD_BASE := 1.4              ## seconds a finished line stays up: base + per character
const HOLD_PER_CHAR := 0.03
const LINE_GAP := 0.3               ## seconds between two radio lines
const CARD_HOLD_BASE := 2.0         ## a finished card moves on by itself after this + per character
const CARD_HOLD_PER_CHAR := 0.03
const CARD_MIN := 0.35              ## seconds before a tap may advance a card (a firing finger must not skip it)
const BANNER_TIME := 4.4
const QUEUE_MAX := 4
const LOW_HP := 0.3
const LOW_HP_COOLDOWN := 20.0
const BEEP_EVERY := 8               ## characters per radio beep (Sfx voices are shared with gunfire)
const EPILOGUE_DELAY := 0.3
const DEATH_DELAY := 0.5
const HEAT_STEPS := [1.0, 3.0]      ## heat1 / heat3 chapter lines; 5.0 is the global heat5 line

var enabled := true
var chapter := 0                    ## 0-based sector index; chapter_data() clamps it to the aftermath entry
var shown: Array[String] = []       ## ids of every line group queued, in order (tests and debugging)
var queue: Array[Dictionary] = []   ## radio lines waiting: {s, t, id, wait, prio}
var current: Dictionary = {}        ## the radio line being typed or held
var typed := 0.0
var hold_left := 0.0
var wait_left := 0.0
var banner_t := -1.0                ## seconds since the chapter banner appeared (negative: hidden)
var cards: Array[Dictionary] = []   ## cards left, the first one is showing
var card_kind: StringName = &""     ## &"prologue" or &"epilogue" while cards are showing
var card_typed := 0.0
var card_age := 0.0
var card_hold := 0.0
var death_quote: Dictionary = {}
var death_age := 0.0
var end_card: Dictionary = {}
var end_age := 0.0
var epilogue_seen := false
var view: StoryView
var first_use: FirstUse              ## icon first-use prompts (scripts/story/first_use.gd)
var tutorial: Tutorial               ## first-launch training (scripts/story/tutorial.gd)

var _seen := {}
var _bags := {}
var _rng := RandomNumberGenerator.new()
var _started := false               ## the current line passed its wait and is on screen
var _beeped := 0
var _epi_wait := -1.0
var _resync := true                 ## take new baselines on the next poll (after every module handled a lifecycle signal)
var _last_got := 0
var _prev_heat := 0.0
var _had_vehicle := false
var _had_beacon := false
var _had_bits := false
var _had_links := false
var _had_clone := false
var _low := false
var _low_cd := 0.0
var _drawn := false


func _ready() -> void:
	_rng.randomize()
	Game.story = self
	var layer := CanvasLayer.new()
	layer.name = "StoryLayer"
	layer.layer = 11                # above the HUD (10): subtitles and cards sit on top of every screen
	add_child(layer)
	view = StoryView.new()
	view.name = "View"
	view.story = self
	layer.add_child(view)
	tutorial = Tutorial.new()
	tutorial.name = "Tutorial"
	add_child(tutorial)
	first_use = FirstUse.new()
	first_use.name = "FirstUse"
	add_child(first_use)
	cards_finished.connect(_on_cards_finished)
	Game.new_game.connect(_on_new_game)
	Game.respawn.connect(_on_respawn)
	Game.next_sector.connect(_on_next_sector)
	Game.heat_changed.connect(_on_heat)
	Game.message.connect(_on_message)
	Game.player_died.connect(_on_died)
	Game.sector_cleared.connect(_on_cleared)


func _exit_tree() -> void:
	if Game.story == self:
		Game.story = null


# ---------------------------------------------------------------------------------------------------------------------
# data access
# ---------------------------------------------------------------------------------------------------------------------

## A card or quote with its drawn strings in the active language (the typewriter counts the translated characters).
static func _tr_card(c: Dictionary) -> Dictionary:
	if Tr.lang == "en":
		return c
	var d := c.duplicate()
	for k: String in ["head", "text", "t"]:
		if d.has(k):
			d[k] = Tr.t(str(d[k]))
	return d


func tagline() -> String:
	return Tr.t(StoryData.TAGLINE)


func chapter_data() -> Dictionary:
	return StoryData.CHAPTERS[mini(chapter, StoryData.CHAPTERS.size() - 1)]


func chapter_label() -> String:
	return Tr.t("CHAPTER %d" % (chapter + 1)) if chapter <= StoryData.FINAL else Tr.t("FREE SECTOR %02d" % (chapter + 1))


func objective_text() -> String:
	return Tr.t(str(chapter_data().get("obj", "")))


func cards_active() -> bool:
	return not cards.is_empty()


func banner_visible() -> bool:
	return banner_t >= 0.0 and banner_t < BANNER_TIME


func line_visible() -> bool:
	return not current.is_empty() and _started


func line_text() -> String:
	return str(current.get("t", "")).substr(0, int(typed)) if _started else ""


## 0..1: fades out in the last 0.4 s of a held line.
func line_alpha() -> float:
	if current.is_empty() or not _started:
		return 0.0
	return 1.0 if hold_left < 0.0 else clampf(hold_left / 0.4, 0.0, 1.0)


func card_text() -> String:
	return str(cards[0].get("text", "")).substr(0, int(card_typed)) if not cards.is_empty() else ""


func has_text_on_screen() -> bool:
	return line_visible() or cards_active() or banner_visible() or not death_quote.is_empty() or not end_card.is_empty()


# ---------------------------------------------------------------------------------------------------------------------
# radio
# ---------------------------------------------------------------------------------------------------------------------

## Queues one radio line. Returns false when the queue is full of lines at least as important. prio: 0 normal, 1 important (story beats), 2 urgent.
func say(speaker: String, text: String, id := "", wait := 0.0, prio := 0) -> bool:
	if not enabled:
		return false
	var entry := {"s": speaker, "t": Tr.t(text), "id": id, "wait": wait, "prio": prio}
	if queue.size() >= QUEUE_MAX:
		var drop := -1
		for i in queue.size():
			if int(queue[i]["prio"]) <= prio:
				drop = i
				break
		if drop < 0:
			return false
		queue.remove_at(drop)
	queue.append(entry)
	return true


## Said once per run: the RADIO lines of `event`. Returns true when something was queued.
func trigger(event: String) -> bool:
	if not enabled or _seen.has(event) or not StoryData.RADIO.has(event):
		return false
	return _queue_group(event, StoryData.RADIO[event], 1)


func _queue_group(id: String, lines: Variant, prio: int) -> bool:
	if _seen.has(id):
		return false
	var list: Array = lines if lines is Array else [lines]
	var queued := false
	for l: Variant in list:
		var d: Dictionary = l
		queued = say(str(d["s"]), str(d["t"]), id, 0.0, prio) or queued
	if queued:
		_seen[id] = true
		shown.append(id)
	return queued


## A line of the current chapter: key is "intro", "heat1", "heat3" or "core<N>".
func trigger_chapter(key: String) -> bool:
	var data := chapter_data()
	var id := "c%d.%s" % [chapter + 1, key]
	if key.begins_with("core"):
		var cores: Dictionary = data.get("cores", {})
		var n := key.substr(4).to_int()
		return cores.has(n) and _queue_group(id, cores[n], 1)
	return data.has(key) and _queue_group(id, data[key], 1)


## Next line of a pool in shuffled order, never the same twice in a row and none repeated before the pool has been used up.
func pick(pool_name: String, pool: Array) -> Dictionary:
	var bag: Array = _bags.get(pool_name, [])
	if bag.is_empty():
		for i in pool.size():
			bag.append(i)
		bag.shuffle()
		if bag.size() > 1 and int(bag[bag.size() - 1]) == int(_bags.get(pool_name + ".last", -1)):
			bag.push_front(bag.pop_back())     # the next pick (the back) must differ from the previous pool's last pick
	var idx: int = bag.pop_back()
	_bags[pool_name] = bag
	_bags[pool_name + ".last"] = idx
	return pool[idx]


func skip_line() -> void:
	current = {}
	_started = false


func _tick_radio(delta: float) -> void:
	if cards_active():
		return
	if current.is_empty():
		if queue.is_empty():
			return
		current = queue.pop_front()
		typed = 0.0
		hold_left = -1.0
		wait_left = maxf(float(current["wait"]), LINE_GAP)
		_started = false
		_beeped = 0
	if not _started:
		wait_left -= delta
		if wait_left > 0.0:
			return
		_started = true
		Sfx.radio_begin()
		line_started.emit(str(current["id"]), str(current["s"]))
	var n := str(current["t"]).length()
	if typed < n:
		typed = minf(typed + CPS_LINE * delta, float(n))
		Sfx.radio_type(str(current["t"]), int(typed))              # a syllable of radio babble per vowel typed, ducking the music under it
		if typed >= n:
			hold_left = HOLD_BASE + n * HOLD_PER_CHAR
	else:
		hold_left -= delta
		if hold_left <= 0.0:
			skip_line()


# ---------------------------------------------------------------------------------------------------------------------
# cards (prologue, epilogue)
# ---------------------------------------------------------------------------------------------------------------------

func start_cards(list: Array, kind: StringName) -> void:
	cards.clear()
	for c: Variant in list:
		cards.append(_tr_card(c as Dictionary))
	card_kind = kind
	card_typed = 0.0
	card_age = 0.0
	card_hold = -1.0
	_epi_wait = -1.0


## The cards typed over the win screen after the final chapter: the campaign's ending cards (CampaignData.ENDING, which end with the credits cinematic on NEXT SECTOR);
## StoryData.EPILOGUE stays as the fallback when the campaign data has none.
func ending_cards() -> Array:
	return CampaignData.ENDING if not CampaignData.ENDING.is_empty() else StoryData.EPILOGUE


func start_prologue() -> void:
	start_cards(StoryData.PROLOGUE, &"prologue")
	shown.append("prologue")


## A tap, click or Enter: finishes the typing of the card, or moves on to the next one. Returns true while cards are showing (the event is consumed).
func advance_card() -> bool:
	if cards.is_empty():
		return false
	if card_age < CARD_MIN:
		return true
	var n := str(cards[0]["text"]).length()
	if card_typed < n:
		card_typed = float(n)
		card_hold = CARD_HOLD_BASE + n * CARD_HOLD_PER_CHAR
	else:
		_next_card()
	return true


func skip_cards() -> void:
	while not cards.is_empty():
		_next_card()


func _next_card() -> void:
	cards.pop_front()
	card_typed = 0.0
	card_age = 0.0
	card_hold = -1.0
	if cards.is_empty():
		var kind := card_kind
		card_kind = &""
		cards_finished.emit(kind)
		if kind == &"prologue":
			_begin_chapter()
		elif kind == &"epilogue":
			epilogue_seen = true


func _tick_cards(delta: float) -> void:
	if cards.is_empty():
		return
	card_age += delta
	var n := str(cards[0]["text"]).length()
	if card_typed < n:
		card_typed = minf(card_typed + CPS_CARD * delta, float(n))
		if card_typed >= n:
			card_hold = CARD_HOLD_BASE + n * CARD_HOLD_PER_CHAR
	else:
		card_hold -= delta
		if card_hold <= 0.0:
			_next_card()


func _input(event: InputEvent) -> void:
	if cards.is_empty():
		return
	var hit := false
	if event is InputEventScreenTouch:
		hit = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		hit = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventKey:
		var k := event as InputEventKey
		hit = k.pressed and not k.echo and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER or k.keycode == KEY_SPACE)
	# Only while the cards are on screen (play, dead, win: the same states as `view.visible` and advance()). Cards left over from an aborted run stay frozen and invisible in the
	# menu; swallowing taps there made DEPLOY / NEW GAME unreachable after "ABORT TO MENU" during the prologue (found by tests/bot_soak.gd).
	if hit and (Game.state == &"play" or Game.state == &"dead" or Game.state == &"win") and advance_card():
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------------------------------------------------
# lifecycle and events
# ---------------------------------------------------------------------------------------------------------------------

func _clear_transient() -> void:
	queue.clear()
	skip_line()
	banner_t = -1.0
	cards.clear()
	card_kind = &""
	death_quote = {}
	death_age = 0.0
	end_card = {}
	end_age = 0.0
	_epi_wait = -1.0
	_resync = true


func _begin_chapter() -> void:
	banner_t = 0.0
	trigger_chapter("intro")
	chapter_started.emit(chapter)


## Jumps to a chapter without the prologue (CONTINUE from a save): the banner and the chapter intro play, nothing else.
func set_chapter(index: int) -> void:
	_clear_transient()
	cards.clear()
	card_kind = &""
	chapter = maxi(index, 0)
	_resync = true
	tutorial.stop()
	if enabled:
		_begin_chapter()


func _on_cards_finished(kind: StringName) -> void:
	if kind == &"prologue" and tutorial != null:
		tutorial.maybe_start()


func _on_new_game() -> void:
	_clear_transient()
	_seen.clear()
	_bags.clear()
	shown.clear()
	chapter = 0
	epilogue_seen = false
	_low_cd = 0.0
	if enabled:
		start_prologue()


func _on_respawn() -> void:
	_clear_transient()
	if enabled:
		_prev_heat = 0.0
		var r := pick("respawn", StoryData.RESPAWN)
		say(str(r["s"]), str(r["t"]), "respawn", 1.0, 2)
		shown.append("respawn")


func _on_next_sector() -> void:
	_clear_transient()
	chapter += 1
	_prev_heat = 0.0
	if enabled:
		_begin_chapter()


func _on_died() -> void:
	queue.clear()
	skip_line()
	banner_t = -1.0
	cards.clear()
	card_kind = &""
	end_card = {}
	death_age = 0.0
	if enabled:
		death_quote = _tr_card(pick("death", StoryData.DEATH))
		shown.append("death")


func _on_cleared() -> void:
	queue.clear()
	skip_line()
	banner_t = -1.0
	if not enabled:
		return
	end_card = _tr_card(chapter_data()["end"])
	end_age = 0.0
	shown.append("c%d.end" % (chapter + 1))
	if chapter == StoryData.FINAL and not epilogue_seen:
		_epi_wait = EPILOGUE_DELAY


func _on_heat(h: float) -> void:
	var prev := _prev_heat
	_prev_heat = h
	if not enabled or not Game.is_playing():
		return
	if prev < float(HEAT_STEPS[0]) and h >= float(HEAT_STEPS[0]):
		trigger_chapter("heat1")
	if prev < float(HEAT_STEPS[1]) and h >= float(HEAT_STEPS[1]):
		trigger_chapter("heat3")
	if prev < 5.0 and h >= 5.0:
		trigger("heat5")


func _on_message(text: String, _seconds: float) -> void:
	if not enabled or not Game.is_playing():
		return
	for t: Dictionary in StoryData.MESSAGE_TRIGGERS:
		if text.find(str(t["contains"])) >= 0:
			trigger(str(t["event"]))


## Reads the missions, the player's quantum powers, vehicle and health once and reacts to changes.
func poll() -> void:
	var m: Object = Game.missions if is_instance_valid(Game.missions) else null
	var p: Object = Game.player if is_instance_valid(Game.player) else null
	var got := 0
	var total := 0
	if m != null:
		got = int(m.get("got"))
		total = int(m.get("total"))
	var veh := false
	var beacon := false
	var bits := false
	var links := false
	var clone := false
	var frac := 1.0
	if p != null:
		veh = p.get("vehicle") != null
		var hp_v: Variant = p.get("hp")
		var max_v: Variant = p.get("max_hp")
		if hp_v != null:
			frac = float(hp_v) / maxf(float(max_v) if max_v != null else 100.0, 1.0)
		var q: Object = p.get("quantum")
		if q != null:
			beacon = q.get("has_beacon") == true
			var bl: Variant = q.get("bits_left")
			bits = (bl is float or bl is int) and float(bl) > 0.0
			var lk: Variant = q.get("links")
			links = lk is Array and not (lk as Array).is_empty()
			clone = is_instance_valid(q.get("clone") as Object)
	if _resync:
		_resync = false
		_last_got = got
		_had_vehicle = veh
		_had_beacon = beacon
		_had_bits = bits
		_had_links = links
		_had_clone = clone
		_low = frac < LOW_HP
		return
	if got > _last_got:
		for n in range(_last_got + 1, got + 1):
			if n < total:
				trigger_chapter("core%d" % n)
	_last_got = got
	if veh and not _had_vehicle:
		trigger("first_vehicle")
	if beacon and not _had_beacon:
		trigger("first_beacon")
	if bits and not _had_bits:
		trigger("first_teleport")
	if links and not _had_links:
		trigger("first_link")
	if clone and not _had_clone:
		trigger("first_super")
	_had_vehicle = veh
	_had_beacon = beacon
	_had_bits = bits
	_had_links = links
	_had_clone = clone
	var low := frac < LOW_HP
	if low and not _low and _low_cd <= 0.0:
		_low_cd = LOW_HP_COOLDOWN
		if not trigger("first_low_health"):
			var l := pick("low_health", StoryData.LOW_HEALTH)
			say(str(l["s"]), str(l["t"]), "low_health", 0.0, 2)
			shown.append("low_health")
	_low = low


# ---------------------------------------------------------------------------------------------------------------------
# time
# ---------------------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	advance(delta / maxf(Engine.time_scale, 0.05))      # real seconds, so slow motion never freezes a card
	if view != null:
		var st := Game.state
		view.visible = st == &"play" or st == &"dead" or st == &"win"
		var vp := get_viewport().get_visible_rect().size
		if view.size != vp:
			view.size = vp                 # a Control under a CanvasLayer does not always get its anchors resolved
		var active := view.visible and (has_text_on_screen() or st == &"play")
		if active or _drawn:
			view.queue_redraw()
		_drawn = active


## Advances every timer by `delta` real seconds (the tests call it directly).
func advance(delta: float) -> void:
	var st := Game.state
	if not (st == &"play" or st == &"dead" or st == &"win"):
		return
	_tick_cards(delta)
	if st == &"dead":
		death_age += delta
	elif st == &"win":
		end_age += delta
		if _epi_wait >= 0.0:
			_epi_wait -= delta
			if _epi_wait < 0.0:
				start_cards(ending_cards(), &"epilogue")
				shown.append("epilogue")
	if st != &"play":
		return
	_low_cd = maxf(_low_cd - delta, 0.0)
	poll()
	if banner_t >= 0.0 and not cards_active():
		banner_t += delta
		if banner_t >= BANNER_TIME:
			banner_t = -1.0
	_tick_radio(delta)
