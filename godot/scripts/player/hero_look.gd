class_name HeroLook
extends RefCounted
## G2 hero customisation: a suit (surface finish) and a colour scheme (8 presets) plus an optional custom accent colour (the picker, 12 hues). Applied to the hero by material
## parameters only (PlayerBody.apply_look: albedo tint, metallic, roughness, emission and trim accent; no new models or draws). Unlocks: a credit price in the shop, or a cosmetic
## id earned by an achievement (Achievements.cosmetics). State is saved by Progress in an optional [hero] section (older saves have none: the default look).
## Item keys: "suit:<id>", "scheme:<index>", "accent" (the picker).

signal changed

## id -> name, price (credits), need (achievement cosmetic id, "" none), albedo multiplier, metallic delta, roughness delta, glow multiplier
const SUITS := {
	&"standard": {"name": "STANDARD", "price": 0, "need": "", "albedo": Color(1.0, 1.0, 1.0), "metal": 0.0, "rough": 0.0, "glow": 1.0},
	&"stealth": {"name": "STEALTH", "price": 300, "need": "", "albedo": Color(0.7, 0.72, 0.76), "metal": -0.1, "rough": 0.2, "glow": 0.6},
	&"phase": {"name": "PHASE", "price": 0, "need": "aura_phase", "albedo": Color(0.95, 1.0, 1.05), "metal": 0.15, "rough": -0.15, "glow": 1.5},
	&"gilded": {"name": "GILDED", "price": 0, "need": "visor_gold", "albedo": Color(1.2, 1.05, 0.8), "metal": 0.3, "rough": -0.2, "glow": 1.1},
}
const SUIT_ORDER: Array[StringName] = [&"standard", &"stealth", &"phase", &"gilded"]
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
const ACCENT_PRICE := 250
const HUES := 12
const ACCENT_MIX := 0.6

var suit: StringName = &"standard"
var scheme := 0
var accent_hue := -1                      ## -1 = the scheme's own accent, 0..HUES-1 = the picker's custom accent
var owned: Array[String] = []            ## bought items (keys above)


static func scheme_count() -> int:
	return SCHEMES.size()


static func hue_color(i: int) -> Color:
	return Color.from_hsv(float(posmod(i, HUES)) / float(HUES), 0.8, 1.0)


static func item_price(key: String) -> int:
	if key == "accent":
		return ACCENT_PRICE
	if key.begins_with("suit:"):
		return int(SUITS.get(StringName(key.substr(5)), {}).get("price", -1))
	if key.begins_with("scheme:"):
		var i := int(key.substr(7))
		return int(SCHEMES[i][3]) if i >= 0 and i < SCHEMES.size() else -1
	return -1


## The achievement cosmetic id an item waits for ("" when it is bought with credits).
static func item_need(key: String) -> String:
	if key.begins_with("suit:"):
		return String(SUITS.get(StringName(key.substr(5)), {}).get("need", ""))
	if key.begins_with("scheme:"):
		var i := int(key.substr(7))
		return String(SCHEMES[i][4]) if i >= 0 and i < SCHEMES.size() else ""
	return ""


static func valid_key(key: String) -> bool:
	return item_price(key) >= 0


## Free items, owned items and items whose achievement cosmetic is earned (`cosmetics`).
func is_unlocked(key: String, cosmetics: Array) -> bool:
	if not valid_key(key):
		return false
	var need := item_need(key)
	if need != "":
		return cosmetics.has(StringName(need)) or cosmetics.has(need)
	return item_price(key) == 0 or owned.has(key)


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


func reset() -> void:
	suit = &"standard"
	scheme = 0
	accent_hue = -1
	owned.clear()
	changed.emit()


func to_save() -> Dictionary:
	return {"suit": String(suit), "scheme": scheme, "accent": accent_hue, "owned": PackedStringArray(owned)}


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
	changed.emit()
