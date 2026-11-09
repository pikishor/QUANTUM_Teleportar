class_name AlienLoot
extends RefCounted
## The alien tech parts (wave 107b: "loot (alien tech parts)"). Aliens drop glowing shards (AlienWorld pickups); walking into one banks it: its credit value at once, a count in the
## inventory (saved in user://alien_world.cfg), and the matching weapon-crafting part (SCRAP / ALLOY / QUANTUM CORE, Crafting.add_part) for the bench that the default menus hide. Every
## MILESTONE parts a next weapon of the ladder drops beside the hero (docs/DESIGN.md: loot feeds weapons).
## Static state like Crafting; tests call `reset()`.

const SAVE_PATH := "user://alien_world.cfg"
const MILESTONE := 10                         ## parts per bonus weapon drop
const TOAST_GAP := 1.4

static var counts := {}                       ## part id -> total banked
static var total := 0
static var credits_paid := 0
static var milestones := 0
static var _toast_t := -99.0
static var _loaded := false


static func reset() -> void:
	counts.clear()
	total = 0
	credits_paid = 0
	milestones = 0
	_loaded = true


static func count(part: StringName) -> int:
	_load()
	return int(counts.get(part, 0))


static func all_parts() -> int:
	_load()
	return total


## Banks `n` parts of `part`: credits, the crafting part, the toast, the milestone weapon. Returns the credits paid.
static func collect(part: StringName, n := 1, at := Vector3.ZERO) -> int:
	_load()
	if not AlienSpecies.PARTS.has(part) or n <= 0:
		return 0
	var def: Dictionary = AlienSpecies.PARTS[part]
	counts[part] = int(counts.get(part, 0)) + n
	var before := total
	total += n
	var pay := int(def["value"]) * n
	var pg := Game.progress as Progress
	if pg != null:
		pg.add_credits(pay)
	credits_paid += pay
	var cp: StringName = def.get("crafting", &"")
	if cp != &"":
		Crafting.add_part(cp, n)
	Sfx.play(&"pickup", -4.0, 1.25)
	var now := Time.get_ticks_msec() * 0.001
	if now - _toast_t >= TOAST_GAP:
		_toast_t = now
		Game.say("%s  +%d" % [String(def["name"]), pay], 1.6)
	if int(total / MILESTONE) > int(before / MILESTONE):
		milestones += 1
		_milestone(at)
	save()
	return pay


static func _milestone(at: Vector3) -> void:
	var m := Game.missions
	if not is_instance_valid(m) or not m.has_method(&"drop_weapon"):
		return
	var w := WeaponLadder.next_target()
	if w == &"":
		return
	var p := at if at != Vector3.ZERO else (Game.player.global_position if is_instance_valid(Game.player) else Vector3.ZERO)
	m.call(&"drop_weapon", w, p + Vector3(1.5, 0.0, 1.5))
	Game.say("ALIEN TECH: %s" % WeaponDefs.title(w), 2.6)


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	if cf.has_section("parts"):
		for k in cf.get_section_keys("parts"):
			counts[StringName(k)] = int(cf.get_value("parts", k, 0))
			total += int(counts[StringName(k)])
	milestones = int(cf.get_value("stats", "milestones", 0))
	credits_paid = int(cf.get_value("stats", "credits", 0))


static func save() -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	for k: StringName in counts:
		cf.set_value("parts", String(k), int(counts[k]))
	cf.set_value("stats", "milestones", milestones)
	cf.set_value("stats", "credits", credits_paid)
	cf.save(SAVE_PATH)
