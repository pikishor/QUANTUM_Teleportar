extends RefCounted
## District identity of the city (wave 16 art library). The four districts are the four quadrants of the 8x8 grid: the dividing lines x = 0 and z = 0 are road centre lines,
## so every sidewalk and every building belongs to exactly one district. The numbering and the names are the ones the music layer already uses (`Sfx.DISTRICTS`:
## market x<0,z<0 / foundry x>=0,z<0 / slums x<0,z>=0 / towers x>=0,z>=0); the spawn (-30, 4) lies in the slums.
##
## Each district has its own palette (prop paint tint, glow accents, facade tint, neon index, sidewalk tint), its own prop mix (relative weights per street-kit kind, see
## city_kit.gd) and a landmark silhouette on a plaza (city_landmarks.gd). Everything here is pure data: no nodes, safe to read from tests and shaders' setup code.

const MARKET := 0
const FOUNDRY := 1
const SLUMS := 2
const TOWERS := 3
const COUNT := 4

const IDS: Array[StringName] = [&"market", &"foundry", &"slums", &"towers"]
const TITLES: Array[String] = ["NEON MARKET", "FOUNDRY ROW", "RAIN SLUMS", "GLASS TOWERS"]
const LANDMARKS: Array[StringName] = [&"lantern_spire", &"twin_stacks", &"relay_tower", &"vael_needle"]

## Where each landmark wants to stand: the empty plaza lot nearest to this point (x, z) in the district.
const LANDMARK_TARGETS: Array[Vector2] = [Vector2(-170.0, -170.0), Vector2(170.0, -150.0), Vector2(-150.0, 190.0), Vector2(170.0, 170.0)]

## Palette per district. tint: multiplier of the painted props (linear), accent / accent2: glow colours (emissive parts, light sprites), fabric: stall awnings and banners,
## wall: multiplier of the facade tint, neon: index into the neon palette (0 cyan, 1 magenta, 2 violet, 3 green) the district's lots are biased towards,
## walk: multiplier of the sidewalk slab colour (the one tint that also reaches the LOW tier), lamp: street-lamp variant bias (0 warm .. 1 cool cyan).
const PALETTES: Array[Dictionary] = [
	{"tint": Color(1.30, 0.95, 0.70), "accent": Color(1.0, 0.45, 0.12), "accent2": Color(1.0, 0.15, 0.55),
	 "fabric": [Color(0.55, 0.06, 0.20), Color(0.60, 0.22, 0.04), Color(0.05, 0.30, 0.32)],
	 "wall": Color(1.16, 0.96, 0.82), "neon": 1, "walk": Color(1.15, 0.96, 0.80), "lamp": 0.0},
	{"tint": Color(1.08, 0.80, 0.64), "accent": Color(1.0, 0.27, 0.05), "accent2": Color(1.0, 0.62, 0.10),
	 "fabric": [Color(0.30, 0.10, 0.04), Color(0.20, 0.20, 0.22), Color(0.45, 0.16, 0.03)],
	 "wall": Color(0.98, 0.88, 0.84), "neon": 2, "walk": Color(0.92, 0.88, 0.88), "lamp": 0.0},
	{"tint": Color(0.78, 1.00, 0.92), "accent": Color(0.30, 1.0, 0.45), "accent2": Color(0.20, 0.80, 0.70),
	 "fabric": [Color(0.08, 0.26, 0.16), Color(0.22, 0.24, 0.10), Color(0.10, 0.18, 0.24)],
	 "wall": Color(0.86, 1.02, 0.96), "neon": 3, "walk": Color(0.86, 1.0, 0.96), "lamp": 0.0},
	{"tint": Color(0.82, 0.95, 1.25), "accent": Color(0.25, 0.85, 1.0), "accent2": Color(0.60, 0.50, 1.0),
	 "fabric": [Color(0.06, 0.16, 0.34), Color(0.30, 0.32, 0.38), Color(0.20, 0.10, 0.40)],
	 "wall": Color(0.92, 1.0, 1.20), "neon": 0, "walk": Color(0.94, 1.0, 1.14), "lamp": 1.0},
]


## The district (0..3) under a world position (x, z).
static func at(x: float, z: float) -> int:
	return (1 if x >= 0.0 else 0) + (2 if z >= 0.0 else 0)


static func at_v(p: Vector3) -> int:
	return at(p.x, p.z)


static func palette(d: int) -> Dictionary:
	return PALETTES[clampi(d, 0, COUNT - 1)]


static func title(d: int) -> String:
	return TITLES[clampi(d, 0, COUNT - 1)]


## Facade tint of a lot: the layout's own tint times the district's wall multiplier (alpha, the lit-window probability, is kept).
static func wall_tint(base: Color, d: int) -> Color:
	var w: Color = PALETTES[clampi(d, 0, COUNT - 1)]["wall"]
	return Color(minf(base.r * w.r, 1.0), minf(base.g * w.g, 1.0), minf(base.b * w.b, 1.0), base.a)


## Neon index of a lot: 60 % of the lots take the district's accent, the rest keep the layout's own index (so every district still has a mix).
static func neon_index(layout_neon: int, lot_index: int, d: int) -> int:
	var h := fposmod(sin(float(lot_index) * 12.9898 + 4.1414) * 43758.5453, 1.0)
	return int(PALETTES[clampi(d, 0, COUNT - 1)]["neon"]) if h < 0.6 else layout_neon
