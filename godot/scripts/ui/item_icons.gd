class_name ItemIcons
extends RefCounted
## The pictures of the game's things: weapons (w_), throwables and gadgets (g_), vehicles (v_), enemy types (e_). Each is a small transparent PNG in res://assets/icons rendered from the item's own
## 3D model by tools/icons/build_icons.sh (committed, so the game needs no renderer for them) and loaded on first use, then cached. Without the file a weapon falls back to its flat
## silhouette (WeaponIcons) and the others to nothing, so a missing picture never breaks a screen. Used by the weapon wheel, the loadout, the shop and the weapons catalogue, the HUD plate,
## the kill feed, pickups, the test and demo menus.

const DIR := "res://assets/icons/"

static var _cache := {}


static func path(prefix: String, id: StringName) -> String:
	return "%s%s_%s.png" % [DIR, prefix, String(id)]


## The picture of `id` under `prefix` (w, g, v, e), null when there is none. A weapon's picture is its THUMB from the atlas pages of WeaponPics (rendered from its model, a frame of 256 x 128; the pages
## are kept by WeaponPics, a few at a time, so nothing is cached here), the old per-file picture only for a weapon without one.
static func texture(prefix: String, id: StringName) -> Texture2D:
	if prefix == "w":
		var wp := WeaponPics.thumb(id)
		if wp != null:
			return wp
	var key := "%s_%s" % [prefix, String(id)]
	if _cache.has(key):
		return _cache[key]
	var t: Texture2D = null
	var p := path(prefix, id)
	if ResourceLoader.exists(p):
		t = load(p) as Texture2D
	_cache[key] = t
	return t


static func weapon(id: StringName) -> Texture2D:
	return texture("w", id)


## The big picture of a weapon (the card of WeaponPics, 512 x 256; else the old 384 x 192 `wl_<id>.png` of tools/icons/build_icons.sh --large) for the weapon card; the small one when there is none.
static func weapon_large(id: StringName) -> Texture2D:
	var cp := WeaponPics.card(id)                                      # a frame of 512 x 256 from the card pages
	if cp != null:
		return cp
	var t := texture("wl", id)
	return t if t != null else texture("w", id)


static func gear(id: StringName) -> Texture2D:
	return texture("g", id)


static func vehicle(kind: StringName) -> Texture2D:
	return texture("v", kind)


static func enemy(type: StringName) -> Texture2D:
	return texture("e", type)


## Which prefix an id of any kind belongs to ("w", "g", "e" or "v"; "" for an unknown one): the kill feed and the pickups only know a name.
static func prefix_of(id: StringName) -> String:
	if WeaponDefs.DEFS.has(id):
		return "w"
	if Gear.THROWABLES.has(id) or Gear.GADGETS.has(id) or id == &"c4":
		return "g"
	if EnemyTypes.TYPES.has(id):
		return "e"
	if VehicleSpecs.SPECS.has(id):
		return "v"
	return ""


static func any(id: StringName) -> Texture2D:
	var pf := prefix_of(id)
	return texture(pf, id) if pf != "" else null


## Draw `tex` fitted into `r` (aspect kept, centred, never upscaled past 2x its own size). Returns the rect it covered.
static func draw_tex(c: CanvasItem, tex: Texture2D, r: Rect2, col := Color.WHITE) -> Rect2:
	if tex == null or r.size.x <= 0.0 or r.size.y <= 0.0:
		return Rect2()
	var ts := tex.get_size()
	var k := minf(r.size.x / ts.x, r.size.y / ts.y)
	var sz := ts * k
	var box := Rect2(r.get_center() - sz * 0.5, sz)
	c.draw_texture_rect(tex, box, false, col)
	return box


## The picture of a weapon fitted into `r` (the flat silhouette when it has no picture). `col` only sets the opacity (rgb of the picture is kept) unless `tint` is set.
static func draw_weapon(c: CanvasItem, id: StringName, r: Rect2, col := Color.WHITE, tint := false) -> void:
	var tex := weapon(id)
	if tex != null:
		draw_tex(c, tex, r, col if tint else Color(1, 1, 1, col.a))
		return
	WeaponIcons.draw_flat(c, id, r, col)


## The big picture of a weapon fitted into `r` (the flat silhouette when it has none).
static func draw_weapon_large(c: CanvasItem, id: StringName, r: Rect2, col := Color.WHITE) -> void:
	var tex := weapon_large(id)
	if tex != null:
		draw_tex(c, tex, r, Color(1, 1, 1, col.a))
		return
	WeaponIcons.draw_flat(c, id, r, col)


static func draw_any(c: CanvasItem, id: StringName, r: Rect2, col := Color.WHITE) -> bool:
	var tex := any(id)
	if tex == null:
		return false
	draw_tex(c, tex, r, col)
	return true


static func clear_cache() -> void:
	_cache.clear()
