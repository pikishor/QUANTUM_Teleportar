class_name SnakeUi
extends RefCounted
## THE SNAKE POWERS ON THE PHONE (wave 115, combat side): two more wedges on the weapon wheel (SNAKE = the ten verbs, BOMBS = the twelve snake bombs; a pick opens a ring of their pictures, a pick of a picture
## ARMS the power: the gun is holstered and FIRE casts it), four quick casts on the ABILITY wheel (SNAKE PULL, SNAKE NET, SNAKE SHIELD and the SNAKE BOMB last armed: they work with a gun in hand), and the text of
## the HUD while a power is in hand (ENERGY, the second mode on ALT, the cost). The wheel items follow the format of scripts/ui/weapon_wheel.gd (`type`: &"snake" for a wedge, &"snake_power" for a disc).
## Hooks (one line each): WeaponWheel.items / activate / ring_items, WeaponIcons.draw / draw_flat (the picture), TouchControls (the ability entries, the WEAPON face), Hud.ammo_text / weapon_text / alt_text.

const TAB_VERBS := &"snake_verbs"
const TAB_BOMBS := &"snake_bombs"
const RING := 8
const SHORT := {&"sv_pull": "PULL", &"sv_grab": "GRAB", &"sv_disarm": "DISARM", &"sv_yank": "YANK", &"sv_net": "NET", &"sv_lash": "LASH", &"sv_shield": "SHIELD", &"sv_decoy": "DECOY", &"sv_trap": "TRAP",
	&"sv_guard": "GUARD", &"sb_coil": "COIL", &"sb_swarm": "SWARM", &"sb_flare": "FLARE", &"sb_freeze": "FREEZE", &"sb_seeker": "SEEKER", &"sb_chain": "CHAIN", &"sb_cluster": "CLUSTER", &"sb_constrict": "MINE",
	&"sb_burrow": "BURROW", &"sb_gravity": "GRAVITY", &"sb_storm": "STORM", &"sb_mega": "MEGA"}
const QUICK := {&"snake_pull": &"sv_pull", &"snake_net": &"sv_net", &"snake_shield": &"sv_shield"}


static func is_tab(tab: StringName) -> bool:
	return tab == TAB_VERBS or tab == TAB_BOMBS


static func ids_of(tab: StringName) -> Array[StringName]:
	return SnakeRows.VERB_IDS if tab == TAB_VERBS else SnakeRows.BOMB_IDS


static func short_name(id: StringName) -> String:
	return String(SHORT.get(id, String(SnakeRows.title(id)).split(" ")[0]))


static func armed_id() -> StringName:
	return SnakeWar.instance.armed if is_instance_valid(SnakeWar.instance) else &""


## The picture id the weapon button / HUD plate shows: the armed power while one is in hand, else the weapon's own.
static func shown(weapon_id: StringName) -> StringName:
	var a := armed_id()
	return a if a != &"" else weapon_id


static func unlocked_count(tab: StringName) -> int:
	var n := 0
	for id in ids_of(tab):
		if SnakeRows.unlocked(id):
			n += 1
	return n


# --- the weapon wheel --------------------------------------------------------------------------------------------------------------------

## The two wedges after the classes: SNAKE (verbs) and BOMBS. A wedge shows the power last armed in it (or the first), a count of the open ones.
static func wheel_items() -> Array:
	var out: Array = []
	var war := SnakeWar.instance if is_instance_valid(SnakeWar.instance) else null
	var armed := armed_id()
	for tab: StringName in [TAB_VERBS, TAB_BOMBS]:
		var ids := ids_of(tab)
		var show: StringName = ids[0]
		if war != null:
			var sel: StringName = war.verb_sel if tab == TAB_VERBS else war.bomb_sel
			if SnakeRows.has(sel):
				show = sel
		var is_armed := armed != &"" and ids.has(armed)
		if is_armed:
			show = armed
		out.append({"id": tab, "type": &"snake", "icon": show, "label": "SNAKE" if tab == TAB_VERBS else "BOMBS", "ready": true, "active": is_armed, "cd": 0.0, "current": is_armed, "cls": tab,
				"owned": unlocked_count(tab), "total": ids.size(), "cname": "SNAKE" if tab == TAB_VERBS else "SNAKE BOMB", "wname": ("SNAKE POWERS  %s" if tab == TAB_VERBS else "SNAKE BOMBS  %s") % SnakeRows.title(show)})
	return out


static func pages(tab: StringName) -> int:
	return maxi(1, int(ceil(float(ids_of(tab).size()) / float(RING))))


## Level two: the powers of a tab on one page as wheel discs, then a NEXT disc when there is more than one page.
static func ring_items(tab: StringName, page: int) -> Array:
	var ids := ids_of(tab)
	var n := pages(tab)
	page = posmod(page, n)
	var armed := armed_id()
	var war := SnakeWar.instance if is_instance_valid(SnakeWar.instance) else null
	var out: Array = []
	for id in ids.slice(page * RING, mini(ids.size(), (page + 1) * RING)):
		var open := SnakeRows.unlocked(id)
		out.append({"id": id, "type": &"snake_power", "icon": id, "label": String(SnakeRows.row(id)["tag"]), "ready": open, "active": id == armed, "cd": war.cd_fraction(id) if war != null else 0.0, "current": id == armed,
				"cls": tab, "owned": 1, "total": 1, "cname": short_name(id), "wname": SnakeRows.caption(id), "tab": tab, "page": page})
	if n > 1:
		out.append({"id": &"page", "type": &"page", "icon": &"", "label": "NEXT", "ready": true, "active": false, "cd": 0.0, "current": false, "cls": tab, "owned": 1, "total": 1,
				"cname": "PAGE %d / %d" % [page + 1, n], "wname": "NEXT PAGE  %d OF %d" % [posmod(page + 1, n) + 1, n], "tab": tab, "page": page + 1})
	return out


static func handles_item(it: Dictionary) -> bool:
	var t := StringName(it.get("type", &""))
	return t == &"snake" or t == &"snake_power"


## A pick of a wedge opens its ring (the page of the armed power); a pick of a power arms it (the wheel closes). Returns the ring to open next ({tab, page}) or {}.
static func activate(it: Dictionary) -> Dictionary:
	var war := SnakeWar.of()
	if war == null:
		return {}
	if StringName(it.get("type", &"")) == &"snake":
		var tab: StringName = it["id"]
		var armed := armed_id()
		var page := 0
		if armed != &"" and ids_of(tab).has(armed):
			page = ids_of(tab).find(armed) / RING
		return {"tab": tab, "page": page}
	war.arm(StringName(it["id"]))
	return {}


# --- the ABILITY wheel ---------------------------------------------------------------------------------------------------------------

## State of a quick cast: ready (can be cast now), active (its snakes are out), cd (the cooldown share, 0..1).
static func ability_state(action: StringName) -> Dictionary:
	var war := SnakeWar.instance if is_instance_valid(SnakeWar.instance) else null
	if war == null:
		return {"ready": false, "active": false, "cd": 0.0}
	var id: StringName = war.bomb_sel if action == &"snake_bomb" else StringName(QUICK.get(action, &""))
	var active := false
	match id:
		&"sv_shield": active = not war.verbs.shield.is_empty()
		&"sv_guard": active = not war.verbs.guard_list.is_empty()
	return {"ready": SnakeRows.unlocked(id) and war.cd_left(id) <= 0.0 and (SnakePower.unlimited() or war.energy() >= war.cost_of(id)), "active": active, "cd": war.cd_fraction(id)}


static func ability_label(action: StringName) -> String:
	if action == &"snake_bomb":
		var war := SnakeWar.instance if is_instance_valid(SnakeWar.instance) else null
		return "SNAKE BOMB" if war == null else "SNAKE %s" % short_name(war.bomb_sel)
	return SnakeRows.title(StringName(QUICK.get(action, &"")))


# --- the HUD while a power is in hand ---------------------------------------------------------------------------------------------------

static func ammo_text() -> String:
	var war := SnakeWar.instance if is_instance_valid(SnakeWar.instance) else null
	if war == null:
		return ""
	var id := war.armed
	var cdl := war.cd_left(id)
	if cdl > 0.05:
		return "%.1f S" % cdl
	return "%d%%" % roundi(war.energy_fraction() * 100.0)                   # the WEAPON button is round and small: "82%"; the desktop plate says the same


static func weapon_text() -> String:
	var id := armed_id()
	if id == &"":
		return ""
	var row := SnakeRows.row(id)
	return "%s  %s  COST %d" % [String(row["name"]), String(row["tag"]), roundi(SnakePower.cost(float(row["cost"])))]


static func alt_text() -> String:
	var id := armed_id()
	if id == &"":
		return ""
	var a := SnakeRows.alt_name(id)
	return "ALT  %s" % a if a != "" else ""
