class_name HeroPortrait
extends RefCounted
## Portrait pictures of the hero for the menus and the story cast (wave 112): committed renders of the real hero kit (tools/hero/bake_portraits.sh renders them through HeroShowcase, the
## studio of the SUIT screen) and live renders of the look in hand for everything else.
##   committed()      the default hero's portrait (assets/ui/hero_portrait.webp, 384 x 480), or null when the file is absent
##   suit_thumb(id)   the picture of a suit preset on its card in the SUIT screen (assets/ui/hero_suit_<id>.webp, 192 x 240), or null
##   for_look(look)   the best picture of the look in hand: the live render of this exact look when one was made (a cache), the committed portrait when the look is the default,
##                    else null (the story cast then keeps its drawn bust). With a `host` node, a menu state and the kit available, a missing live render is requested (once per look).
##   compose(img)     a rendered hero (transparent background) over the portrait backdrop: a dark gradient with a halo in the accent colour
## Nothing here needs a scene tree except `request` (it asks HeroShowcase, which lives in the tree); drawing helpers take a CanvasItem.

const DIR := "res://assets/ui"
const PORTRAIT := "res://assets/ui/hero_portrait.webp"
const SIZE := Vector2i(384, 480)
const THUMB := Vector2i(192, 240)

static var _cache := {}                       ## file path -> Texture2D (or false when absent)
static var _live := {}                        ## look signature -> ImageTexture
static var _pending := {}                     ## look signature -> true while a capture is under way
static var requests := 0                      ## captures started (tests)


static func _tex(path: String) -> Texture2D:
	if _cache.has(path):
		var v: Variant = _cache[path]
		return v as Texture2D if v is Texture2D else null
	var t: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_cache[path] = t if t != null else false
	return t


static func committed() -> Texture2D:
	return _tex(PORTRAIT)


static func suit_thumb(id: StringName) -> Texture2D:
	return _tex("%s/hero_suit_%s.webp" % [DIR, id])


## A stable key of everything that changes the picture (body, skin, hair, beard, suit, scheme, accent).
static func signature(look: HeroLook) -> String:
	if look == null:
		return "default"
	return "%s|%s|%s|%d|%s|%d|%d" % [look.body, look.skin_tone, look.hair, 1 if look.beard else 0, look.suit, look.scheme, look.accent_hue]


## True for the look the committed portrait shows (male, dark skin, parted hair, no beard, the standard suit in the first scheme).
static func is_default(look: HeroLook) -> bool:
	return look == null or (look.body == &"male" and look.skin_tone == &"dark" and look.hair == &"parted" and not look.beard and look.suit == &"standard" and look.scheme == 0 and look.accent_hue < 0)


static func store(look: HeroLook, tex: Texture2D) -> void:
	if look != null and tex != null:
		_live[signature(look)] = tex


static func has_live(look: HeroLook) -> bool:
	return _live.has(signature(look))


## The picture to show for `look`, or null when there is none yet. `host` (a node in the tree) lets a missing live render be requested while a menu is open.
static func for_look(look: HeroLook, host: Node = null) -> Texture2D:
	var k := signature(look)
	if _live.has(k):
		return _live[k] as Texture2D
	if is_default(look):
		var c := committed()
		if c != null:
			return c
	if host != null and host.is_inside_tree() and (Game.state == &"paused" or Game.state == &"menu"):
		request(host, look)
	return null


## Starts the live render of `look` (once; the result lands in the cache and the next `for_look` finds it).
static func request(host: Node, look: HeroLook) -> void:
	if look == null or host == null or not host.is_inside_tree():
		return
	var k := signature(look)
	if _live.has(k) or _pending.has(k) or not HeroCharacter.available(look.body):
		return
	_pending[k] = true
	requests += 1
	_capture(host, copy_of(look), k)


## A detached copy of the look (the render must not follow later changes of the live look).
static func copy_of(look: HeroLook) -> HeroLook:
	var c := HeroLook.new()
	c.body = look.body
	c.skin_tone = look.skin_tone
	c.hair = look.hair
	c.beard = look.beard
	c.suit = look.suit
	c.scheme = look.scheme
	c.accent_hue = look.accent_hue
	return c


static func _capture(host: Node, look: HeroLook, k: String) -> void:
	var sc := HeroShowcase.of(host)
	var img := await sc.capture(look, &"bust", 0.5)
	_pending.erase(k)
	if img == null:
		return
	var tex := ImageTexture.create_from_image(compose(img, look.accent(), SIZE))
	_live[k] = tex


## `hero` (a render with a transparent background, any size, a 4:5 window) over the portrait backdrop, resized to `size`: a dark vertical gradient and a halo of `accent` behind the head.
static func compose(hero: Image, accent: Color, size := SIZE) -> Image:
	var bg := Image.create(48, 60, false, Image.FORMAT_RGBA8)
	for y in 60:
		var ty := float(y) / 59.0
		var base := Color(0.05, 0.07, 0.12).lerp(Color(0.012, 0.018, 0.035), ty)
		for x in 48:
			var d := Vector2(float(x) / 47.0 - 0.5, (float(y) / 59.0 - 0.36) * 0.8).length()
			var halo := clampf(1.0 - d / 0.46, 0.0, 1.0)
			halo = halo * halo
			var col := base.lerp(Color(accent.r * 0.55, accent.g * 0.55, accent.b * 0.55), halo * 0.55)
			bg.set_pixel(x, y, Color(col.r, col.g, col.b, 1.0))
	bg.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	var fg := hero.duplicate() as Image
	fg.convert(Image.FORMAT_RGBA8)
	fg.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	bg.blend_rect(fg, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	return bg


## Draws `tex` (a portrait) into `r` of `ci`, cropped to the rectangle's aspect (a card shows the head and shoulders, the story plate a square): the source is cut from the centre column
## when the box is narrower than the picture and from the bottom when it is taller.
static func draw_into(ci: CanvasItem, tex: Texture2D, r: Rect2, modulate := Color.WHITE) -> void:
	if tex == null or not r.has_area():
		return
	var ts := tex.get_size()
	var want := r.size.x / r.size.y
	var src := Rect2(Vector2.ZERO, ts)
	if ts.x / ts.y > want:                                   # the picture is wider than the box: cut the sides
		var w := ts.y * want
		src = Rect2((ts.x - w) * 0.5, 0.0, w, ts.y)
	else:                                                    # taller: keep the head, cut the lower part
		var h := ts.x / want
		src = Rect2(0.0, 0.0, ts.x, h)
	ci.draw_texture_rect_region(tex, r, src, modulate)
