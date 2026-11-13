class_name HeroLook
extends RefCounted
## G2 hero customisation: a suit (surface finish) and a colour scheme (8 presets) plus an optional custom accent colour (the picker, 12 hues). Applied to the hero by material
## parameters only (PlayerBody.apply_look: albedo tint, metallic, roughness, emission and trim accent; no new models or draws). Unlocks: a credit price in the shop, or a cosmetic
## id earned by an achievement (Achievements.cosmetics). State is saved by Progress in an optional [hero] section (older saves have none: the default look).
## Item keys: "suit:<id>", "scheme:<index>", "accent" (the picker).

signal changed

## SIX SUIT PRESETS (wave 112, hero look v3). id -> name, price (credits), need (see unlock_need: an achievement cosmetic id, "ach:<id>" an achievement, "" none), albedo multiplier / metal /
## rough / glow multiplier (the old finish numbers PlayerBody.apply_look still uses), `set` = the armour kit set it wears (HeroSuit: vanguard, stealth, assault, flight: a different set
## rebuilds the hero, a different suit of the same set only changes the palette), plate (final colour of the armour plates), cloth / cloth2 (bodysuit, belt), trim_k (how much of the scheme
## accent goes into the painted trim), pmetal / prough (plate finish), story (one line for the customisation screen). The old ids stay (saves): "standard" is the VANGUARD.
const SUITS := {
	&"standard": {"name": "VANGUARD", "set": &"vanguard", "price": 0, "need": "", "albedo": Color(1.0, 1.0, 1.0), "metal": 0.0, "rough": 0.0, "glow": 1.0,
			"plate": Color(0.17, 0.185, 0.225), "cloth": Color(0.045, 0.05, 0.065), "cloth2": Color(0.07, 0.075, 0.09), "trim_k": 0.4, "pmetal": 1.0, "prough": 0.0,
			"story": "Layered plates over a graphite suit. The default.", "tag": "LAYERED PLATES"},
	&"stealth": {"name": "STEALTH", "set": &"stealth", "price": 300, "need": "", "albedo": Color(0.7, 0.72, 0.76), "metal": -0.1, "rough": 0.2, "glow": 0.6,
			"plate": Color(0.075, 0.08, 0.095), "cloth": Color(0.028, 0.03, 0.038), "cloth2": Color(0.045, 0.047, 0.055), "trim_k": 0.24, "pmetal": 0.5, "prough": 0.18,
			"story": "Matte black, light plates, dim circuits.", "tag": "MATTE  DIM CIRCUITS"},
	&"assault": {"name": "ASSAULT", "set": &"assault", "price": 450, "need": "", "albedo": Color(1.05, 1.0, 0.92), "metal": 0.05, "rough": 0.05, "glow": 1.0,
			"plate": Color(0.2, 0.21, 0.15), "cloth": Color(0.06, 0.062, 0.048), "cloth2": Color(0.09, 0.09, 0.07), "trim_k": 0.42, "pmetal": 0.8, "prough": 0.05,
			"story": "Heavy armour in olive drab: bigger shoulders, thigh and chest guards.", "tag": "HEAVY ARMOUR"},
	&"flight": {"name": "FLIGHT", "set": &"flight", "price": 0, "need": "ach:chapter_4", "albedo": Color(1.1, 1.1, 1.15), "metal": 0.1, "rough": -0.05, "glow": 1.2,
			"plate": Color(0.3, 0.33, 0.39), "cloth": Color(0.04, 0.05, 0.075), "cloth2": Color(0.07, 0.08, 0.11), "trim_k": 0.5, "pmetal": 0.7, "prough": -0.05,
			"story": "Sleek and light, with wing mounts on the back. Reach chapter 5.", "tag": "WING MOUNTS"},
	&"gilded": {"name": "GILDED", "set": &"vanguard", "price": 0, "need": "visor_gold", "albedo": Color(1.2, 1.05, 0.8), "metal": 0.3, "rough": -0.2, "glow": 1.1,
			"plate": Color(0.58, 0.46, 0.25), "cloth": Color(0.03, 0.028, 0.032), "cloth2": Color(0.06, 0.05, 0.04), "trim_k": 0.3, "pmetal": 1.4, "prough": -0.2,
			"story": "The gold hero suit. Collect all ten rooftop shards.", "tag": "GOLD PLATING"},
	&"phase": {"name": "PHASE", "set": &"vanguard", "price": 0, "need": "aura_phase", "albedo": Color(0.95, 1.0, 1.05), "metal": 0.15, "rough": -0.15, "glow": 1.5,
			"plate": Color(0.14, 0.23, 0.29), "cloth": Color(0.03, 0.05, 0.075), "cloth2": Color(0.05, 0.08, 0.11), "trim_k": 0.6, "pmetal": 1.1, "prough": -0.2,
			"story": "Glassy plates and bright circuits. Collect all thirty shards.", "tag": "GLASS PLATES"},
}
const SUIT_ORDER: Array[StringName] = [&"standard", &"stealth", &"assault", &"flight", &"gilded", &"phase"]
## name, tint (albedo multiplier of the armour), accent (emission and trim), price, need
const SCHEMES: Array[Array] = [
	["CYAN", Color(1.0, 1.0, 1.0), Color(0.2, 0.95, 1.0), 0, ""],
	["EMBER", Color(1.15, 0.85, 0.75), Color(1.0, 0.45, 0.15), 150, ""],
	["VIOLET", Color(0.95, 0.85, 1.15), Color(0.75, 0.35, 1.0), 0, "trail_violet"],
	["JADE", Color(0.8, 1.1, 0.9), Color(0.25, 1.0, 0.55), 150, ""],
	["MAGENTA", Color(1.1, 0.8, 1.0), Color(1.0, 0.35, 0.85), 0, "decal_neon"],
	["GOLD", Color(1.2, 1.05, 0.75), Color(1.0, 0.8, 0.25), 0, "outline_gold"],
	["CRIMSON", Color(1.2, 0.75, 0.75), Color(1.0, 0.2, 0.25), 200, ""],
	["ICE", Color(0.9, 0.95, 1.1), Color(0.8, 0.95, 1.0), 250, ""],
]
const ACCENT_PRICE := Economy.ACCENT_PRICE   ## raw; the charged price is Economy.accent_price()
const HUES := 12
const ACCENT_MIX := 0.6

## HERO MODE (wave 117 sets it): every suit, scheme and accent is unlocked and free.
static var hero_mode := false

var suit: StringName = &"standard"
var scheme := 0
var accent_hue := -1                      ## -1 = the scheme's own accent, 0..HUES-1 = the picker's custom accent
var owned: Array[String] = []            ## bought items (keys above)
## The superhero's person (HeroCharacter): body (male / female), skin tone (dark / light), hair style and beard. Free choices, saved with the look.
var body: StringName = &"male"
var skin_tone: StringName = &"dark"
var hair: StringName = &"parted"
var beard := false


static func scheme_count() -> int:
	return SCHEMES.size()


## THE GLOW API of the suit (scripts/characters/hero_glow.gd has the layers and the zones): every system that wants to drive the quantum circuits calls these, never the material.
##   HeroLook.set_glow(Color(0.2, 0.95, 1.0), 1.4, &"flow")     swing: energy runs from the core to the hands
##   HeroLook.set_glow(Color.WHITE, 1.3, &"wings")              flight: the wing mounts glow
##   HeroLook.pulse_glow(Color(1.0, 0.6, 0.2), 1.8, 0.4)        a bomb throw: a flash that fades by itself
##   HeroLook.set_glow(Color.WHITE, 0.0, &"flow")               release the layer (intensity <= 0)
## Modes: &"steady" &"pulse" &"charge" &"flow" &"wings" &"flicker" (layers, they do not fight), &"burst" is a one-shot flash. Returns false when no hero is alive (a menu).
static func set_glow(color: Color, intensity: float, mode: StringName = &"steady") -> bool:
	return HeroGlow.live_set(color, intensity, mode)


static func pulse_glow(color: Color, intensity: float, seconds := 0.45) -> bool:
	return HeroGlow.live_pulse(color, intensity, seconds)


static func hue_color(i: int) -> Color:
	return Color.from_hsv(float(posmod(i, HUES)) / float(HUES), 0.8, 1.0)


static func item_price(key: String) -> int:
	if key == "accent":
		return Economy.accent_price()
	if key.begins_with("suit:"):
		return Economy.suit_price(StringName(key.substr(5))) if SUITS.has(StringName(key.substr(5))) else -1
	if key.begins_with("scheme:"):
		var i := int(key.substr(7))
		return Economy.scheme_price(i) if i >= 0 and i < SCHEMES.size() else -1
	return -1


## The achievement cosmetic id an item waits for ("" when it is bought with credits); "ach:<id>" waits for that achievement itself.
static func item_need(key: String) -> String:
	if key.begins_with("suit:"):
		return String(SUITS.get(StringName(key.substr(5)), {}).get("need", ""))
	if key.begins_with("scheme:"):
		var i := int(key.substr(7))
		return String(SCHEMES[i][4]) if i >= 0 and i < SCHEMES.size() else ""
	return ""


static func valid_key(key: String) -> bool:
	return item_price(key) >= 0


## Free items, owned items and items whose achievement cosmetic is earned (`cosmetics`); everything in HERO MODE.
func is_unlocked(key: String, cosmetics: Array) -> bool:
	if not valid_key(key):
		return false
	if hero_mode:
		return true
	var need := item_need(key)
	if need.begins_with("ach:"):
		var pr := Game.progress as Progress
		return pr != null and pr.achievements != null and pr.achievements.done.has(StringName(need.substr(4)))
	if need != "":
		return cosmetics.has(StringName(need)) or cosmetics.has(need)
	return item_price(key) == 0 or owned.has(key)


## What the player has to do to get a locked item (customisation screen): a short line.
static func unlock_hint(key: String) -> String:
	var need := item_need(key)
	if need.begins_with("ach:"):
		for d: Array in Achievements.DEFS:
			if String(d[0]) == need.substr(4):
				return "%s: %s" % [String(d[1]), String(d[2])]
		return "an achievement"
	if need != "":
		for d: Array in Achievements.DEFS:
			if String(d[6]) == need:
				return "%s: %s" % [String(d[1]), String(d[2])]
		return "an achievement"
	var pr := item_price(key)
	return "%d credits" % pr if pr > 0 else "free"


## Credits wallet buy: returns true and records ownership; the caller pays.
func grant(key: String) -> void:
	if valid_key(key) and not owned.has(key):
		owned.append(key)


func equip_suit(id: StringName, cosmetics: Array) -> bool:
	if not SUITS.has(id) or not is_unlocked("suit:%s" % id, cosmetics):
		return false
	suit = id
	changed.emit()
	return true


func equip_scheme(i: int, cosmetics: Array) -> bool:
	if i < 0 or i >= SCHEMES.size() or not is_unlocked("scheme:%d" % i, cosmetics):
		return false
	scheme = i
	accent_hue = -1
	changed.emit()
	return true


## Person options: "body", "skin", "hair" (HeroCharacter.HAIRS) or "beard" (value ignored, toggled). False for an unknown value.
func set_person(what: String, value: Variant = null) -> bool:
	match what:
		"body":
			if not (StringName(str(value)) in HeroCharacter.BODIES):
				return false
			body = StringName(str(value))
			if body == &"female":
				beard = false
		"skin":
			if not (StringName(str(value)) in HeroCharacter.SKINS):
				return false
			skin_tone = StringName(str(value))
		"hair":
			if not (StringName(str(value)) in HeroCharacter.HAIRS):
				return false
			hair = StringName(str(value))
		"beard":
			if body == &"female":
				return false
			beard = not beard
		_:
			return false
	changed.emit()
	return true


func set_accent(h: int) -> bool:
	if h < -1 or h >= HUES or (h >= 0 and not owned.has("accent")):
		return false
	accent_hue = h
	changed.emit()
	return true


func accent() -> Color:
	return hue_color(accent_hue) if accent_hue >= 0 else (SCHEMES[scheme][2] as Color)


func tint() -> Color:
	return SCHEMES[scheme][1] as Color


func suit_def() -> Dictionary:
	return SUITS[suit]


## The look on a hero material (PlayerBody and the SUIT screen's showcase use it): the suit finish, the scheme's accent, the suit kit palette and the idle colour of the circuits. Parameters
## only. `quality` is the graphics tier (0 LOW tames the glow), `compat` the Compatibility renderer. Returns the accent colour.
func apply_material(mat: ShaderMaterial, glow: HeroGlow = null, quality := 1, compat := false) -> Color:
	var sd := suit_def()
	var mult := (sd["albedo"] as Color) * tint()
	var neutral := suit == &"standard" and scheme == 0 and accent_hue < 0
	var acc := accent()
	mat.set_shader_parameter(&"look_tint", Color(mult.r, mult.g, mult.b))
	mat.set_shader_parameter(&"suit_metal", clampf(0.3 + float(sd["metal"]), 0.0, 1.0))
	mat.set_shader_parameter(&"suit_rough", clampf(0.5 + float(sd["rough"]), 0.05, 1.0))
	mat.set_shader_parameter(&"glow", float(sd["glow"]) * (0.6 if quality == 0 else 1.0))
	mat.set_shader_parameter(&"accent", acc)
	mat.set_shader_parameter(&"accent_mix", 0.0 if neutral else ACCENT_MIX)
	var pal := palette()
	for k: StringName in pal:
		mat.set_shader_parameter(k, pal[k])
	mat.set_shader_parameter(&"glow_gain", 1.0 * (0.7 if quality == 0 else 1.0) * (0.6 if compat else 1.0))
	if glow != null:
		glow.set_base(acc, float(sd["glow"]))
	return acc


## The armour kit set of the equipped suit (HeroSuit.SETS): vanguard, stealth, assault or flight.
func kit_set() -> StringName:
	return StringName(SUITS[suit].get("set", &"vanguard"))


## The suit kit palette as shader uniforms of the hero material (PlayerBody._apply_hero_look): plate colour, painted trim, cloth, gold, plate finish. The preset sets the base, the colour
## scheme tints the plates and the painted trim takes the accent colour (the picker's hue or the scheme's own).
func palette() -> Dictionary:
	var sd: Dictionary = SUITS[suit]
	var t := tint()
	var a := accent()
	var plate: Color = sd["plate"]
	var tk := float(sd["trim_k"])
	var pc := Color(clampf(plate.r * lerpf(1.0, t.r, 0.6), 0.0, 1.0), clampf(plate.g * lerpf(1.0, t.g, 0.6), 0.0, 1.0), clampf(plate.b * lerpf(1.0, t.b, 0.6), 0.0, 1.0))
	var cloth: Color = sd["cloth"]
	return {
		&"plate_col": pc,
		&"trim_paint": Color(a.r * tk * 0.55, a.g * tk * 0.55, a.b * tk * 0.55),
		&"cloth_col": cloth.lerp(a * 0.12, 0.12),
		&"cloth_col2": (sd["cloth2"] as Color).lerp(a * 0.14, 0.1),
		&"gold_col": Color(0.78, 0.6, 0.28),
		&"plate_metal": float(sd["pmetal"]),
		&"plate_rough": float(sd["prough"]),
	}


func reset() -> void:
	suit = &"standard"
	scheme = 0
	accent_hue = -1
	owned.clear()
	body = &"male"
	skin_tone = &"dark"
	hair = &"parted"
	beard = false
	changed.emit()


func to_save() -> Dictionary:
	return {"suit": String(suit), "scheme": scheme, "accent": accent_hue, "owned": PackedStringArray(owned), "body": String(body), "skin": String(skin_tone), "hair": String(hair), "beard": beard}


## Damaged or unknown values fall back to the default look; an equipped item must be unlocked, otherwise it is reset (`cosmetics` as in is_unlocked).
func from_save(d: Dictionary, cosmetics: Array = []) -> void:
	owned.clear()
	var ow: Variant = d.get("owned", [])
	for k: Variant in (Array(ow) if ow is Array or ow is PackedStringArray else []):
		var key := str(k)
		if valid_key(key) and not owned.has(key):
			owned.append(key)
	var s := StringName(str(d.get("suit", "standard")))
	suit = s if SUITS.has(s) and is_unlocked("suit:%s" % s, cosmetics) else &"standard"
	var sc: Variant = d.get("scheme", 0)
	scheme = int(sc) if sc is int and int(sc) >= 0 and int(sc) < SCHEMES.size() and is_unlocked("scheme:%d" % int(sc), cosmetics) else 0
	var a: Variant = d.get("accent", -1)
	accent_hue = int(a) if a is int and int(a) >= 0 and int(a) < HUES and owned.has("accent") else -1
	var person := HeroCharacter.sanitize({"body": d.get("body", "male"), "skin": d.get("skin", "dark"), "hair": d.get("hair", "parted"), "beard": d.get("beard", false)})
	body = person["body"]
	skin_tone = person["skin"]
	hair = person["hair"]
	beard = bool(person["beard"]) and body == &"male"
	changed.emit()
