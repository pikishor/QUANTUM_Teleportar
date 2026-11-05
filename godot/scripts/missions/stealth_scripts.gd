class_name StealthScripts
extends RefCounted
## Pure data and rules of the four stealth missions (wave 69). The runner is scripts/missions/stealth_runner.gd (Game.missions.stealth); nothing here touches the scene tree.
## Each one plays inside its own interior (none of them has an InteriorMissions job) and uses the existing alert system (scripts/enemies/stealth.gd): ANY guard reaching the ALERTED
## level fails the run (SPOTTED), suspicion alone does not. Rewards live in Economy.STEALTH_PAY, scaled like contracts (sector factor, reputation), +Economy.STEALTH_BONUS on a bonus.
##   infiltrate  UNSEEN ENTRY      reach the far terminal of the TELEPORTER HALL unseen. Bonus: nobody killed.
##   plant       PLANT THE DEVICE  WAREHOUSE: hold the ring at the crate stack (PLANT_S s, decays), then walk out. Bonus: nobody killed.
##   datatheft   DATA THEFT        SERVER ROOM: copy the data at the terminal (FILL_S s, decays at half speed away) before the clock runs out. Bonus: nobody killed.
##   takedown    SILENT ROUTE      CARGO BAY: take every guard down from behind (melee TAKEDOWN). A killing blow on an unaware guard no longer alerts the others. Bonus: under PAR s.

const IDS: Array[StringName] = [&"infiltrate", &"plant", &"datatheft", &"takedown"]
const REACH := 2.4                     ## metres from an objective that count as being there
const PLANT_S := 4.0
const FILL_S := 10.0
const FILL_DECAY := 0.5
const PAR := 80.0                      ## takedown: seconds for the speed bonus
const FAIL_REP := -1                   ## reputation lost when the run fails (spotted, time out); leaving unseen costs nothing

const DEFS := {
	&"infiltrate": {"title": "UNSEEN ENTRY", "brief": "Reach the terminal at the back without being seen.", "interior": &"teleporter_hall", "mode": &"reach", "terminal": &"terminal", "time": 0.0, "rep": 4},
	&"plant": {"title": "PLANT THE DEVICE", "brief": "Plant the device at the crates, then walk out unseen.", "interior": &"warehouse", "mode": &"plant", "terminal": &"safe", "time": 0.0, "rep": 5},
	&"datatheft": {"title": "DATA THEFT", "brief": "Copy the data before the clock runs out. Stay unseen.", "interior": &"server_room", "mode": &"data", "terminal": &"terminal", "time": 70.0, "rep": 6},
	&"takedown": {"title": "SILENT ROUTE", "brief": "Take every guard down from behind. Nobody may sound the alarm.", "interior": &"cargo_bay", "mode": &"route", "terminal": &"guard", "time": 0.0, "rep": 6},
}


static func def(id: StringName) -> Dictionary:
	return DEFS.get(id, {})


static func title(id: StringName) -> String:
	return String(def(id).get("title", String(id).to_upper()))


## The stealth mission that plays in interior type `t` (&"" when none).
static func for_interior(t: StringName) -> StringName:
	for id: StringName in IDS:
		if StringName(DEFS[id]["interior"]) == t:
			return id
	return &""


## Sector needed (Economy.STEALTH_CHAPTER); DEMO MODE opens all of them.
static func unlocked(id: StringName, chapter: int) -> bool:
	return DEFS.has(id) and (chapter >= int(Economy.STEALTH_CHAPTER[id]) or DemoMode.active)


## Credits: Economy.STEALTH_PAY x sector reward factor x reputation bonus, x (1 + STEALTH_BONUS) with the bonus, a multiple of 5, never below 5.
static func reward(id: StringName, chapter: int, rep: int, bonus: bool) -> int:
	if not DEFS.has(id):
		return 0
	var v := float(Economy.STEALTH_PAY[id]) * float(Progress.difficulty(chapter)["reward"]) * (1.0 + Progress.rep_bonus(rep))
	if bonus:
		v *= 1.0 + Economy.STEALTH_BONUS
	return maxi(5, int(round(v / 5.0)) * 5)


## The bonus rule text shown on the end banner.
static func bonus_name(id: StringName) -> String:
	return "UNDER PAR" if mode_of(id) == &"route" else "NO KILLS"


static func mode_of(id: StringName) -> StringName:
	return StringName(def(id).get("mode", &""))


## "" when the entry is complete and sane (the test walks every id).
static func validate(id: StringName) -> String:
	if not DEFS.has(id) or not Economy.STEALTH_PAY.has(id) or not Economy.STEALTH_CHAPTER.has(id):
		return "missing table entry"
	var d: Dictionary = DEFS[id]
	for k: String in ["title", "brief", "interior", "mode", "terminal", "time", "rep"]:
		if not d.has(k):
			return "missing key " + k
	if not InteriorData.TYPES.has(StringName(d["interior"])):
		return "unknown interior"
	if InteriorData.mission_for(StringName(d["interior"])) != &"":
		return "interior already has its own mission"
	if String(d["title"]).length() > CampaignSteps.MAX_TEXT or String(d["brief"]).length() > 80:
		return "text too long"
	return ""
