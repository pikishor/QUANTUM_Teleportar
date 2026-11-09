class_name RoamWorld
extends Node
## THE FREE-ROAM WORLD (wave 111; docs/DESIGN.md "side activities, races, events -> optional open-world fun with markers; rewards feed weapons", docs/WORLD_EXPANSION.md "free roam"). Child of Freedom
## (`RoamWorld.instance`, `Freedom.current.roam_world`). Roaming the big world pays: everything below counts as a DISCOVERY on one counter (shown on the map: "DISCOVERED 12 / 71"):
##   QUANTUM PADS     fast travel: walk or drive up to a pad (the city hub, the airport, the harbour quay, six camps) and it is found; stand on a found pad and pick any other found pad
##   SIGNAL RELICS    24 hidden relics in the mountains, forests, deserts, plains and beaches: the SCANNER PULSE gadget shows those within 140 m (beam, ring, map pin) and pings the direction of
##                    those within 400 m; walking up to one picks it up (the scanner is handed over free the first time the hero comes near one)
##   PHOTO SPOTS      eight views with a time of day (NIGHT SKY, SUNSET LIGHT, DUNE SUNSET ...): take a picture in PHOTO MODE from inside the ring at the right hour
##   FISHING          six places and eight species that bite by water and time of day (RoamFishing)
##   HUNT LOG         eight animals of the outskirts, the first of each kind taken counts (WildlifeWorld.killed); the wildlife already pays its bounty
##   STUNT JUMPS      five ramps on the outskirt roads (RoamRuns)
##   LANDMARK RACES   five races along the real roads between the landmarks (RoamRuns)
##   WORLD EVENTS     convoys, crashes, alien raids and smugglers turn up in every biome, more raids at night (RoamEvents); the first of each kind counts
## Rewards feed the loop: every discovery pays credits, every 5th counts as a finished mission for MissionRewards (the weapon ladder moves), and at 6 / 12 / 20 / 28 / 38 / 50 discoveries a
## VEHICLE starts to wait on a pad (hover bike, mountain rover, armoured carrier, gunship, light tank, jet fighter; `RoamData.RIDES`). Saved in user://roam_world.cfg; a new game forgets it.
## Logic is driven by `poll(dt)` from _physics_process in play; tests call it with their own dt.

signal discovered(kind: StringName, id: StringName, count: int)
signal ride_unlocked(index: int)

static var instance: RoamWorld
static var rides_unlocked := 0             ## how many of RoamData.RIDES wait on their pads (VehicleSpawns reads this)

const SAVE_PATH := "user://roam_world.cfg"
const SHOW_R := 340.0                      ## rings of pads, photo spots and fishing places show from this far
const PAD_FIND_R := 30.0
const RELIC_R := 4.0
const SCAN_REVEAL_R := 140.0
const SCAN_PING_R := 400.0
const SHOW_TIME := 40.0
const HINT_R := 220.0
const PAY := {&"pad": 120, &"relic": 150, &"photo": 180, &"fish": 0, &"hunt": 60, &"stunt": 140, &"race": 0, &"event": 0}
const MAP_SKIP: Array[StringName] = [&"airport", &"harbour"]
const MARK_PADS := 0                        ## the first marker slots: pads (3), relics (3), photo spots (2), the fishing place (1), the ramp / race (1)
const MARK_RELICS := 3
const MARK_PHOTOS := 6
const MARK_FISH := 8
const MARK_RUN := 9

var pads_found: Dictionary = {}            ## pad id -> true
var relics_found: Dictionary = {}          ## relic id -> true
var photos: Dictionary = {}                ## photo spot id -> true
var fish_log: Dictionary = {}              ## species -> catches
var hunts: Dictionary = {}                 ## species -> true
var stunts: Dictionary = {}                ## stunt id -> landing error of the best jump
var races_done: Dictionary = {}            ## race id -> best seconds
var events_done: Dictionary = {}           ## kind -> completions
var ladder_paid := 0
var revealed: Dictionary = {}              ## relic id -> seconds its beam still shows
var scans := 0
var pings := 0
var prompt := ""                           ## the contextual line of what the hero is doing right now (a race, a bite on the line, a pad): Freedom.job_prompt() falls back to it
var hint := ""                             ## the quiet line (a photo spot, the running world event): shown only when nothing else wants the hint slot (Freedom.roam_hint())
var marks: RoamMarks
var events: RoamEvents
var fishing: RoamFishing
var runs: RoamRuns
var travel: RoamTravel

var _hooked: Gadgets
var _wild_hooked := false
var _photo: PhotoMode
var _vis_t := 0.0
var _hint_t := 0.0
var _hunt_n := 0


func _ready() -> void:
	instance = self
	name = "RoamWorld"
	_load()
	marks = RoamMarks.new(12)
	marks.host = self
	events = RoamEvents.new(self)
	add_child(events)
	fishing = RoamFishing.new(self)
	add_child(fishing)
	runs = RoamRuns.new(self)
	add_child(runs)
	travel = RoamTravel.new(self)
	add_child(travel)
	Game.new_game.connect(_on_new_game)
	set_physics_process(true)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not Game.is_playing():
		return
	poll(delta)


func _process(delta: float) -> void:
	if marks != null:
		marks.animate(delta)


# --- the counter ------------------------------------------------------------------------------------------------------------------------

func count() -> int:
	var n := pads_found.size() + relics_found.size() + photos.size() + fish_log.size() + hunts.size() + stunts.size() + races_done.size()
	for k in events_done:
		if int(events_done[k]) > 0:
			n += 1
	return n


func total() -> int:
	return RoamData.total()


## "DISCOVERED 12 / 71" (the map's title row).
func counter_text() -> String:
	return "DISCOVERED %d / %d" % [count(), total()]


## Per-kind progress for the map and the tests: {kind: [found, of]}.
func breakdown() -> Dictionary:
	var ev := 0
	for k in events_done:
		if int(events_done[k]) > 0:
			ev += 1
	return {&"pad": [pads_found.size(), RoamData.pads().size()], &"relic": [relics_found.size(), RoamData.relics().size()], &"photo": [photos.size(), RoamData.photo_spots().size()],
			&"fish": [fish_log.size(), RoamData.FISH.size()], &"hunt": [hunts.size(), RoamData.HUNTS.size()], &"stunt": [stunts.size(), RoamData.stunts().size()],
			&"race": [races_done.size(), RoamData.races().size()], &"event": [ev, RoamData.EVENT_KINDS.size()]}


## A new discovery: the counter moves, credits are paid, the toast says so, the milestones run, the save is written. `pay` < 0 uses the table.
func note(kind: StringName, id: StringName, text: String, pay := -1) -> int:
	var amount := int(PAY.get(kind, 0)) if pay < 0 else pay
	var prog := Game.progress as Progress
	if prog != null and amount > 0:
		prog.add_credits(amount)
		prog.bonus_score(amount)
	var n := count()
	Game.say("%s  %d / %d%s" % [text, n, total(), ("  +%d" % amount) if amount > 0 else ""], 3.2)
	Sfx.play(&"ui_contract_accept")
	_milestones(n)
	_save()
	discovered.emit(kind, id, n)
	return amount


func _milestones(n: int) -> void:
	while rides_unlocked < RoamData.RIDES.size() and n >= int(RoamData.RIDES[rides_unlocked]["need"]):
		var r: Dictionary = RoamData.RIDES[rides_unlocked]
		rides_unlocked += 1
		var pd := RoamData.pad(StringName(r["pad"]))
		Game.say("NEW RIDE  %s WAITS AT %s" % [String(r["label"]), String(pd.get("name", "A PAD"))], 4.0)
		ride_unlocked.emit(rides_unlocked - 1)
	while ladder_paid < n / RoamData.LADDER_EVERY:
		ladder_paid += 1
		if not DemoMode.active and Game.progress != null:
			MissionRewards.complete(&"activity", "EXPLORER")


## The next ride the counter unlocks: {need, label} or {} when all are out.
func next_ride() -> Dictionary:
	return RoamData.RIDES[rides_unlocked] if rides_unlocked < RoamData.RIDES.size() else {}


# --- the poll ---------------------------------------------------------------------------------------------------------------------------

func _hero() -> Vector3:
	var p := Game.player
	if not is_instance_valid(p):
		return Vector3.INF
	var v := WorldSteps.hero_vehicle()
	return v.global_position if v != null else (p as Node3D).global_position


func busy() -> bool:
	var m := Game.missions as Missions
	if m != null and m.board != null and m.board.state != &"idle":
		return true
	if InteriorGameplay.active:
		return true
	var wr := WorldRoam.instance
	return wr != null and wr.active != &""


static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func poll(dt: float) -> void:
	var hero := _hero()
	if not hero.is_finite():
		return
	_hook_gadgets()
	_hook_wild()
	_hook_photo()
	_tick_pads(hero)
	_tick_relics(dt, hero)
	var photo_line := _tick_photos(hero)
	runs.poll(dt, hero)
	fishing.poll(dt, hero)
	events.poll(dt, hero)
	travel.poll(dt, hero)
	_vis_t -= dt
	if _vis_t <= 0.0:
		_vis_t = 0.25
		_refresh_marks(hero)
	prompt = ""
	for cand in [fishing.prompt, runs.prompt, travel.prompt]:
		if String(cand) != "":
			prompt = String(cand)
			break
	hint = photo_line if photo_line != "" else events.prompt


# --- pads -------------------------------------------------------------------------------------------------------------------------------

func _tick_pads(hero: Vector3) -> void:
	for p in RoamData.pads():
		var id: StringName = p["id"]
		if pads_found.has(id):
			continue
		var pp: Vector3 = p["pos"]
		if flat(pp, hero) < PAD_FIND_R and absf(pp.y - hero.y) < 30.0 and not InteriorGameplay.active:
			found_pad(id)


## A pad the hero can travel from and to: found ones, and every pad in the DEMO profile (everything is unlocked there; the demo never writes the real save).
func pad_known(id: StringName) -> bool:
	return pads_found.has(id) or DemoMode.active


func found_pad(id: StringName) -> bool:
	if pads_found.has(id):
		return false
	var p := RoamData.pad(id)
	if p.is_empty():
		return false
	pads_found[id] = true
	note(&"pad", id, "QUANTUM PAD  %s" % String(p["name"]))
	return true


# --- relics and the scanner -------------------------------------------------------------------------------------------------------------

func _hook_gadgets() -> void:
	var pl := Game.player as Player
	if pl == null or pl.gadgets == null or pl.gadgets == _hooked:
		return
	_hooked = pl.gadgets
	if not _hooked.used.is_connected(_on_gadget):
		_hooked.used.connect(_on_gadget)


func _on_gadget(id: StringName) -> void:
	if id == &"scanner":
		scan(_hero())


## A scanner pulse at `at`: the relics within SCAN_REVEAL_R show a beam for SHOW_TIME seconds, the nearest one within SCAN_PING_R says which way it lies. Returns the number revealed.
func scan(at: Vector3) -> int:
	scans += 1
	var n := 0
	var near_d := INF
	var near_dir := ""
	for r in RoamData.relics():
		var id: StringName = r["id"]
		if relics_found.has(id):
			continue
		var p: Vector3 = r["pos"]
		var d := flat(p, at)
		if d <= SCAN_REVEAL_R:
			revealed[id] = SHOW_TIME
			n += 1
		elif d <= SCAN_PING_R and d < near_d:
			near_d = d
			near_dir = WorldRoam._compass(Vector2(p.x - at.x, p.z - at.z))
	if n > 0:
		Game.say("RELIC SIGNAL  %d NEAR" % n, 2.5)
	elif near_dir != "":
		pings += 1
		Game.say("FAINT RELIC SIGNAL  %s  %d M" % [near_dir, roundi(near_d)], 2.5)
	return n


func _tick_relics(dt: float, hero: Vector3) -> void:
	for r in RoamData.relics():
		var id: StringName = r["id"]
		if relics_found.has(id):
			continue
		var p: Vector3 = r["pos"]
		var d := flat(p, hero)
		if revealed.has(id):
			revealed[id] = float(revealed[id]) - dt
			if float(revealed[id]) <= 0.0:
				revealed.erase(id)
		if d < RELIC_R and absf(hero.y - p.y) < 8.0 and not busy():
			collect_relic(id)
			continue
		if d < HINT_R:
			if not Gear.is_owned(&"scanner"):
				Gear.give(&"scanner")
				if Gear.gadget == &"":
					Gear.equip(&"scanner")
				Game.say("RELICS NEAR  SCANNER PULSE ADDED  USE GADGET", 3.5)
			elif Gear.gadget == &"":
				Gear.equip(&"scanner")
			_hint_t -= dt
			if _hint_t <= 0.0 and not revealed.has(id) and not busy():
				_hint_t = 30.0
				Game.say("SIGNAL RELIC NEAR  USE THE SCANNER", 3.0)


func collect_relic(id: StringName) -> bool:
	if relics_found.has(id):
		return false
	for r in RoamData.relics():
		if r["id"] == id:
			relics_found[id] = true
			revealed.erase(id)
			var p: Vector3 = r["pos"]
			FX.burst(p + Vector3(0.0, 0.6, 0.0), Color(0.3, 1.0, 0.8), 14, 7.0, 0.5, 0.0)
			note(&"relic", id, String(r["name"]))
			return true
	return false


# --- photo spots ------------------------------------------------------------------------------------------------------------------------

func _hook_photo() -> void:
	if _photo != null and is_instance_valid(_photo):
		return
	var n := get_tree().root.find_child("Photo", true, false)
	if n is PhotoMode:
		_photo = n as PhotoMode
		if not _photo.captured.is_connected(_on_photo):
			_photo.captured.connect(_on_photo)


func _on_photo(path: String) -> void:
	if path == "":
		return
	take_photo(_hero())


## A picture was taken with the hero at `at`: the spot whose ring holds him counts when the hour fits. Returns the spot id or &"".
func take_photo(at: Vector3) -> StringName:
	var h := RoamData.hour_now()
	for s in RoamData.photo_spots():
		var id: StringName = s["id"]
		if photos.has(id):
			continue
		var p: Vector3 = s["pos"]
		if flat(p, at) > float(s["r"]) or absf(p.y - at.y) > 60.0:
			continue
		if not RoamData.when_ok(StringName(s["when"]), h):
			Game.say("%s  WRONG LIGHT  COME BACK AT %s" % [String(s["name"]), _when_word(StringName(s["when"]))], 3.0)
			continue
		photos[id] = true
		note(&"photo", id, "PHOTO  %s" % String(s["name"]))
		return id
	return &""


static func _when_word(w: StringName) -> String:
	match w:
		&"night":
			return "NIGHT"
		&"dusk":
			return "DUSK OR DAWN"
		&"day":
			return "DAYTIME"
	return "ANY TIME"


## The prompt of the photo spot the hero stands in, "" when none.
func _tick_photos(hero: Vector3) -> String:
	var h := RoamData.hour_now()
	for s in RoamData.photo_spots():
		if photos.has(s["id"]):
			continue
		var p: Vector3 = s["pos"]
		if flat(p, hero) > float(s["r"]) or absf(p.y - hero.y) > 60.0:
			continue
		if RoamData.when_ok(StringName(s["when"]), h):
			return "PHOTO SPOT  %s  OPEN PHOTO MODE" % String(s["name"])
		return "PHOTO SPOT  %s  COME BACK AT %s" % [String(s["name"]), _when_word(StringName(s["when"]))]
	return ""


# --- the hunt log -----------------------------------------------------------------------------------------------------------------------

func _hook_wild() -> void:
	if _wild_hooked or WildlifeWorld.instance == null:
		return
	_wild_hooked = true
	WildlifeWorld.instance.killed.connect(_on_killed)


func _on_killed(species: StringName, _pos: Vector3, by_hero: bool) -> void:
	if by_hero:
		log_hunt(species)


func log_hunt(species: StringName) -> bool:
	if not RoamData.HUNTS.has(species) or hunts.has(species):
		return false
	hunts[species] = true
	_hunt_n += 1
	note(&"hunt", species, "HUNT LOG  %s" % String(AnimalSpecies.data(species).get("name", String(species).to_upper())))
	return true


# --- markers ----------------------------------------------------------------------------------------------------------------------------

## The rings of the things near the hero: the nearest pads (3), revealed relics (3), photo spots (2), the fishing place (1).
func _refresh_marks(hero: Vector3) -> void:
	if marks == null:
		return
	marks.hide_all()
	if busy():
		return
	# pads
	var near := _nearest(RoamData.pads(), hero, SHOW_R, 2)
	for k in near.size():
		var p: Dictionary = near[k]
		var found := pads_found.has(p["id"])
		marks.show_at(MARK_PADS + k, p["pos"], 6.5, Color(0.3, 0.94, 1.0) if found else Color(1.0, 0.72, 0.25), k == 0, true)   # only the nearest pad lights a column (draw budget)
	# relics (only while the scanner shows them)
	var k2 := 0
	for r in RoamData.relics():
		if k2 >= 3:
			break
		if revealed.has(r["id"]) and not relics_found.has(r["id"]):
			marks.show_at(MARK_RELICS + k2, r["pos"], 2.6, Color(0.3, 1.0, 0.8), true, false)
			k2 += 1
	# photo spots (the unfinished ones; the colour says whether the light is right)
	var pl: Array[Dictionary] = []
	for s in RoamData.photo_spots():
		if not photos.has(s["id"]):
			pl.append(s)
	var hr := RoamData.hour_now()
	var np := _nearest(pl, hero, SHOW_R, 2)
	for k3 in np.size():
		var s2: Dictionary = np[k3]
		marks.show_at(MARK_PHOTOS + k3, s2["pos"], float(s2["r"]) * 0.18, Color(0.7, 0.55, 1.0) if RoamData.when_ok(StringName(s2["when"]), hr) else Color(0.45, 0.4, 0.6), false, false)
	fishing.show_mark(marks, MARK_FISH, hero)
	runs.show_mark(marks, MARK_RUN, hero)


static func _nearest(list: Array[Dictionary], from: Vector3, within: float, n: int) -> Array[Dictionary]:
	var c: Array[Dictionary] = []
	for e in list:
		var d := flat(e["pos"], from)
		if d <= within:
			var x: Dictionary = e
			c.append({"d": d, "e": x})
	c.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	var out: Array[Dictionary] = []
	for i in mini(n, c.size()):
		out.append(c[i]["e"])
	return out


## Minimap markers {pos, color, radius, goal, label, kind} (Freedom.markers): the near pads, revealed relics, the running event, race or stunt.
func markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var hero := _hero()
	if hero.is_finite():
		for p in RoamData.pads():
			if flat(p["pos"], hero) < 700.0:
				out.append({"pos": p["pos"], "color": Color(0.3, 0.94, 1.0) if pads_found.has(p["id"]) else Color(1.0, 0.72, 0.25), "radius": 10.0, "goal": false, "label": "PAD", "kind": &"job"})
	for id in revealed:
		if not relics_found.has(id):
			for r in RoamData.relics():
				if r["id"] == id:
					out.append({"pos": r["pos"], "color": Color(0.3, 1.0, 0.8), "radius": 6.0, "goal": false, "label": "RELIC", "kind": &"job"})
	out.append_array(events.markers())
	out.append_array(runs.markers())
	return out


## Pins of the big map: {kind, pos, fog, label, glyph?}: the pads (found ones lit), the spots that still wait for a photo or a rod, the stunts and races, active events, revealed relics.
static func map_markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rw := instance
	if rw == null:
		return out
	for p in RoamData.pads():
		if MAP_SKIP.has(p["id"]):
			continue                                                # the airport and the harbour pads stand beside the airport and harbour glyphs, which are named: a second icon would take their labels' room
		out.append({"kind": &"garage", "pos": p["pos"], "fog": false, "label": ("QUANTUM PAD  %s" % String(p["name"])) + ("" if rw.pads_found.has(p["id"]) else "  NOT FOUND"), "glyph": &"pad", "no_label": true})
	for s in RoamData.photo_spots():
		if not rw.photos.has(s["id"]):
			out.append({"kind": &"items", "pos": s["pos"], "fog": false, "label": "PHOTO SPOT  %s" % String(s["name"])})
	for f in RoamData.fish_spots():
		out.append({"kind": &"items", "pos": f["pos"], "fog": false, "label": "FISHING  %s" % String(f["name"])})
	for st in RoamData.stunts():
		if not rw.stunts.has(st["id"]):
			out.append({"kind": &"job", "pos": st["pos"], "fog": false, "label": "STUNT JUMP  %s" % String(st["name"])})
	for rc in RoamData.races():
		out.append({"kind": &"job", "pos": rc["start"], "fog": false, "label": "RACE  %s" % String(rc["name"])})
	for id in rw.revealed:
		if not rw.relics_found.has(id):
			for r in RoamData.relics():
				if r["id"] == id:
					out.append({"kind": &"items", "pos": r["pos"], "fog": false, "label": "SIGNAL RELIC"})
	for e in rw.events.active:
		out.append({"kind": &"danger", "pos": e["pos"], "fog": false, "label": String(RoamEvents.DEF[e["kind"]]["label"])})
	return out


# --- saving -----------------------------------------------------------------------------------------------------------------------------

func _load() -> void:
	var cf := ConfigFile.new()
	rides_unlocked = 0
	if cf.load(SAVE_PATH) != OK:
		return
	for sec: Array in [["pads", pads_found], ["relics", relics_found], ["photos", photos], ["hunts", hunts]]:
		if not cf.has_section(String(sec[0])):
			continue
		for k in cf.get_section_keys(String(sec[0])):
			if bool(cf.get_value(String(sec[0]), k, false)):
				(sec[1] as Dictionary)[StringName(k)] = true
	if cf.has_section("fish"):
		for k in cf.get_section_keys("fish"):
			fish_log[StringName(k)] = int(cf.get_value("fish", k, 1))
	if cf.has_section("stunts"):
		for k in cf.get_section_keys("stunts"):
			stunts[StringName(k)] = float(cf.get_value("stunts", k, 0.0))
	if cf.has_section("races"):
		for k in cf.get_section_keys("races"):
			races_done[StringName(k)] = float(cf.get_value("races", k, 0.0))
	if cf.has_section("events"):
		for k in cf.get_section_keys("events"):
			events_done[StringName(k)] = int(cf.get_value("events", k, 0))
	ladder_paid = int(cf.get_value("meta", "ladder_paid", 0))
	rides_unlocked = clampi(int(cf.get_value("meta", "rides", 0)), 0, RoamData.RIDES.size())


func _save() -> void:
	if DemoMode.active:
		return
	var cf := ConfigFile.new()
	for sec: Array in [["pads", pads_found], ["relics", relics_found], ["photos", photos], ["hunts", hunts]]:
		for k: StringName in (sec[1] as Dictionary):
			cf.set_value(String(sec[0]), String(k), true)
	for k: StringName in fish_log:
		cf.set_value("fish", String(k), int(fish_log[k]))
	for k: StringName in stunts:
		cf.set_value("stunts", String(k), float(stunts[k]))
	for k: StringName in races_done:
		cf.set_value("races", String(k), float(races_done[k]))
	for k: StringName in events_done:
		cf.set_value("events", String(k), int(events_done[k]))
	cf.set_value("meta", "ladder_paid", ladder_paid)
	cf.set_value("meta", "rides", rides_unlocked)
	cf.save(SAVE_PATH)


func save_now() -> void:
	_save()


## Forget everything (tests, a fresh game).
func reset() -> void:
	pads_found.clear()
	relics_found.clear()
	photos.clear()
	fish_log.clear()
	hunts.clear()
	stunts.clear()
	races_done.clear()
	events_done.clear()
	revealed.clear()
	ladder_paid = 0
	rides_unlocked = 0
	scans = 0
	pings = 0
	if events != null:
		events.reset()
	if fishing != null:
		fishing.reset()
	if runs != null:
		runs.reset()
	if marks != null:
		marks.hide_all()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _on_new_game() -> void:
	var prog := Game.progress as Progress
	if prog != null and bool(prog.get(&"fresh_game")):
		reset()
