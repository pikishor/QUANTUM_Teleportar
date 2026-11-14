class_name WeaponPics
extends RefCounted
## The pictures of the weapons (wave 114): every weapon of WeaponDefs.all_ids() rendered from its own model, 3/4 view, class-coloured rim light, on a transparent background by
## tools/icons/weapon_pics.sh and packed into ATLAS PAGES per class (assets/icons/wp/: t_<class>_<n>.png thumbs 256 x 128, c_<class>_<n>.png cards 512 x 256, manifest.json). The pictures are cropped to their visible pixels and shelf-packed into pages of at most 1024 x 1024; a page is a VRAM-compressed
## texture (1 MB), so a grid of tiles draws from one or two textures (one draw call each) and the whole roster costs memory only for the pages a screen shows:
## the thumb pages stay loaded (about 7 MB for all 11 classes), the card pages are an LRU of `MAX_CARD_PAGES`: the least recently used card page goes first. `thumb(id)` / `card(id)` return an AtlasTexture over the page, so every caller of ItemIcons gets them without changes.
## The class-coloured BACKDROP is drawn here (`draw_backdrop`, `draw_card_art`): a gradient, a soft radial glow, a floor glow and corner brackets in the class colour, so the same picture works on
## the wheel disc, the HUD plate and the big weapon card. Pictures are stale when a model file changed after they were rendered: `stale_ids()` (tests/test_weapon_pics.gd runs it).

const DIR := "res://assets/icons/wp/"
const MANIFEST := "res://assets/icons/wp/manifest.json"
const MODEL_DIR := "res://assets/models/weapons/"
const MAX_CARD_PAGES := 5                   ## card pages (512 x 256 pictures, about 1 MB each) are an LRU of this many
const MAX_PAGES := 16                      ## every thumb page (11 classes, about 7 MB in all: the wheel shows one weapon of each class at once, so they are never evicted) plus the card LRU
const THUMB := Vector2i(256, 128)
const CARD := Vector2i(512, 256)

static var _man: Dictionary = {}
static var _man_tried := false
static var _pages := {}                    ## page path -> {tex: Texture2D, used: int}
static var _atlas := {}                    ## "t:id" / "c:id" -> AtlasTexture
static var _tick := 0
static var _glow_tex := {}                 ## class -> radial GradientTexture2D (the soft glow behind a picture)
static var page_loads := 0                 ## pages loaded so far (tests watch it)


static func manifest() -> Dictionary:
	if not _man_tried:
		_man_tried = true
		if FileAccess.file_exists(MANIFEST):
			var f := FileAccess.open(MANIFEST, FileAccess.READ)
			var j: Variant = JSON.parse_string(f.get_as_text())
			if j is Dictionary:
				_man = j
	return _man


static func has(id: StringName) -> bool:
	return (manifest().get("weapons", {}) as Dictionary).has(String(id))


## How many weapons have a picture.
static func count() -> int:
	return (manifest().get("weapons", {}) as Dictionary).size()


static func _rec(id: StringName) -> Dictionary:
	return (manifest().get("weapons", {}) as Dictionary).get(String(id), {})


## Where a picture lives: {path: the page file, region: its rectangle on the page, margin: the AtlasTexture margin that puts it back at its place inside the full frame (256 x 128 or 512 x 256),
## page: its number}. `kind` is "t" (thumb) or "c" (card). {} when the weapon has no picture.
static func place(kind: String, id: StringName) -> Dictionary:
	var rec := _rec(id)
	var r: Array = rec.get(kind, [])
	if r.size() < 7:
		return {}
	var frame: Array = manifest()["thumb" if kind == "t" else "card"]
	return {"path": "%s%s_%s_%d.webp" % [DIR, kind, rec["cls"], int(r[0])], "page": int(r[0]),
			"region": Rect2(float(r[1]), float(r[2]), float(r[3]), float(r[4])), "margin": Rect2(float(r[5]), float(r[6]), float(frame[0]) - float(r[3]), float(frame[1]) - float(r[4]))}


static func _page(path: String) -> Texture2D:
	_tick += 1
	if _pages.has(path):
		_pages[path]["used"] = _tick
		return _pages[path]["tex"]
	if not ResourceLoader.exists(path):
		return null
	var t := load(path) as Texture2D
	if t == null:
		return null
	page_loads += 1
	_pages[path] = {"tex": t, "used": _tick}
	while _card_pages() > MAX_CARD_PAGES:
		_evict_oldest(path)
	return t


static func _card_pages() -> int:
	var n := 0
	for p: String in _pages:
		if p.begins_with(DIR + "c_"):
			n += 1
	return n


static func _evict_oldest(keep: String) -> void:
	var oldest := ""
	var at := 1 << 60
	for p: String in _pages:
		if p != keep and p.begins_with(DIR + "c_") and int(_pages[p]["used"]) < at:               # a thumb page stays (the HUD, the wheel, the feed and the lists all draw thumbs)
			at = int(_pages[p]["used"])
			oldest = p
	if oldest == "":
		return
	_pages.erase(oldest)
	for k: String in _atlas_src.keys():                                     # the AtlasTextures over that page go with it (a caller that still holds one keeps the page alive)
		if _atlas_src[k] == oldest:
			_atlas.erase(k)
			_atlas_src.erase(k)


static var _atlas_src := {}                ## atlas key -> page path


static func _tex(kind: String, id: StringName) -> Texture2D:
	var pl := place(kind, id)
	if pl.is_empty():
		return null
	var page := _page(String(pl["path"]))
	if page == null:
		return null
	var key := "%s:%s" % [kind, String(id)]
	if _atlas.has(key):
		return _atlas[key]
	var at := AtlasTexture.new()
	at.atlas = page
	at.region = pl["region"]
	at.margin = pl["margin"]
	at.filter_clip = true
	_atlas[key] = at
	_atlas_src[key] = String(pl["path"])
	return at


## The thumb (a 256 x 128 frame) of a weapon, null when it has none.
static func thumb(id: StringName) -> Texture2D:
	return _tex("t", id)


## The card picture (a 512 x 256 frame) of a weapon, null when it has none.
static func card(id: StringName) -> Texture2D:
	return _tex("c", id)


## Drop every loaded page (a screen closed; the next draw loads what it needs again).
static func unload() -> void:
	_pages.clear()
	_atlas.clear()
	_atlas_src.clear()


static func pages_loaded() -> int:
	return _pages.size()


## Ids whose model file changed after the picture was rendered, or that have no picture (the renderer version is part of the manifest). The model file is read for its md5 only: about 0.3 s for the roster, so
## a test or a tool calls it, the game never does.
static func stale_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	var man := manifest()
	var recs: Dictionary = man.get("weapons", {})
	for id: StringName in WeaponDefs.all_ids():
		var rec: Dictionary = recs.get(String(id), {})
		var p := "%s%s.glb" % [MODEL_DIR, id]
		var cur := FileAccess.get_md5(p) if FileAccess.file_exists(p) else ""
		if rec.is_empty() or String(rec.get("md5", "")) != cur:
			out.append(id)
	return out


# ---------------------------------------------------------------------------------------------------------------------------------- drawing

## The soft radial glow of a class colour (made once, 64 px).
static func glow_texture(cls: StringName) -> Texture2D:
	if _glow_tex.has(cls):
		return _glow_tex[cls]
	var tint := UiKit.class_tint(cls)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(tint.lerp(Color.WHITE, 0.25), 0.85), Color(tint, 0.42), Color(tint, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_glow_tex[cls] = t
	return t


## The class backdrop of a picture inside `r`: a dark gradient plate, a glow of the class colour behind the weapon, a floor glow under it, two slanted light bars and corner brackets. `t` animates
## a slow shimmer (seconds); `strength` 0..1 fades it (a locked or unowned weapon is dimmer).
static func draw_backdrop(c: CanvasItem, r: Rect2, cls: StringName, t := 0.0, strength := 1.0) -> void:
	var tint := UiKit.class_tint(cls)
	var top := Color(0.025, 0.035, 0.07).lerp(tint, 0.10)
	var bot := Color(0.045, 0.06, 0.11).lerp(tint, 0.30 * strength)
	c.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), PackedColorArray([top, top, bot, bot]))
	var gl := glow_texture(cls)
	var gs := r.size * Vector2(1.05, 1.25)
	var pulse := 0.88 + 0.12 * sin(t * 1.6)
	c.draw_texture_rect(gl, Rect2(r.get_center() - gs * 0.5 + Vector2(0.0, r.size.y * 0.04), gs), false, Color(1, 1, 1, 0.42 * strength * pulse))
	var fl := Vector2(r.size.x * 0.78, r.size.y * 0.16)                       # the floor glow
	c.draw_texture_rect(gl, Rect2(Vector2(r.get_center().x - fl.x * 0.5, r.position.y + r.size.y * 0.80), fl), false, Color(1, 1, 1, 0.55 * strength))
	var sh := r.size.y * 0.5                                                  # two slanted bars, a quiet sci-fi accent
	for k in 2:
		var x0 := r.position.x + r.size.x * (0.58 + 0.13 * float(k))
		var w := r.size.x * (0.05 - 0.02 * float(k))
		var a := (0.10 - 0.04 * float(k)) * strength
		c.draw_polygon(PackedVector2Array([Vector2(x0, r.position.y), Vector2(x0 + w, r.position.y), Vector2(x0 + w - sh * 0.35, r.position.y + sh), Vector2(x0 - sh * 0.35, r.position.y + sh)]), PackedColorArray([Color(tint, a), Color(tint, a), Color(tint, 0.0), Color(tint, 0.0)]))
	var br := minf(r.size.x, r.size.y) * 0.12
	var lw := maxf(1.5, minf(r.size.x, r.size.y) * 0.012)
	var bc := Color(tint, 0.85 * strength)
	for p: Array in [[r.position, 1.0, 1.0], [Vector2(r.end.x, r.position.y), -1.0, 1.0], [Vector2(r.position.x, r.end.y), 1.0, -1.0], [r.end, -1.0, -1.0]]:
		var o: Vector2 = p[0]
		var sx: float = p[1]
		var sy: float = p[2]
		c.draw_line(o + Vector2(0.0, lw * 0.5 * sy), o + Vector2(br * sx, lw * 0.5 * sy), bc, lw)
		c.draw_line(o + Vector2(lw * 0.5 * sx, 0.0), o + Vector2(lw * 0.5 * sx, br * sy), bc, lw)


## The visible part of a picture: {size: the cropped sprite in frame px, off: where it sits in its frame, frame: the full frame (256 x 128 or 512 x 256)}; {} without a picture.
static func tight(kind: String, id: StringName) -> Dictionary:
	var pl := place(kind, id)
	if pl.is_empty():
		return {}
	var reg: Rect2 = pl["region"]
	var mg: Rect2 = pl["margin"]
	return {"size": reg.size, "off": mg.position, "frame": reg.size + mg.size}


## The weapon's picture scaled so that its VISIBLE sprite (not its 2:1 frame) fills `area` as far as the aspect allows, centred on it, never enlarged by more than `max_scale` screen px per picture
## pixel. A long rifle and a short pistol both fill their tile, a spear runs corner to corner. `big` takes the card picture, else the thumb. Returns the rect the sprite covers.
static func draw_fit(c: CanvasItem, id: StringName, area: Rect2, big := false, col := Color.WHITE, max_scale := 2.2) -> Rect2:
	var kind := "c" if big else "t"
	var info := tight(kind, id)
	var tex: Texture2D = card(id) if big else thumb(id)
	if info.is_empty() or tex == null:
		kind = "t"
		info = tight(kind, id)
		tex = thumb(id)
	if info.is_empty() or tex == null:
		return ItemIcons.draw_tex(c, ItemIcons.weapon_large(id) if big else ItemIcons.weapon(id), area, col)
	var sz: Vector2 = info["size"]
	var k := minf(minf(area.size.x / sz.x, area.size.y / sz.y), max_scale)
	var frame: Vector2 = info["frame"]
	var tc: Vector2 = (info["off"] as Vector2 + sz * 0.5) * k
	c.draw_texture_rect(tex, Rect2(area.get_center() - tc, frame * k), false, col)
	return Rect2(area.get_center() - sz * k * 0.5, sz * k)


## The picture of weapon `id` (its card, else its thumb, else the old flat picture) fitted into `r`, aspect kept and centred. Returns the covered rect.
static func draw_picture(c: CanvasItem, id: StringName, r: Rect2, col := Color.WHITE, big := true) -> Rect2:
	var tex: Texture2D = null
	if big:
		tex = card(id)
	if tex == null:
		tex = thumb(id)
	if tex == null:
		return ItemIcons.draw_tex(c, ItemIcons.weapon_large(id) if big else ItemIcons.weapon(id), r, col)
	return ItemIcons.draw_tex(c, tex, r, col)


## The weapon card art: the class backdrop and the card picture on it, `r` filled by the backdrop and the picture fitted inside with a margin. `locked` dims it. Returns the picture's rect.
static func draw_card_art(c: CanvasItem, id: StringName, r: Rect2, t := 0.0, locked := false) -> Rect2:
	var cls := WeaponDefs.class_of(id)
	draw_backdrop(c, r, cls, t, 0.55 if locked else 1.0)
	var inner := r.grow_individual(-r.size.x * 0.03, -r.size.y * 0.05, -r.size.x * 0.03, -r.size.y * 0.10)
	return draw_picture(c, id, inner, Color(0.62, 0.66, 0.78, 1.0) if locked else Color.WHITE, true)
