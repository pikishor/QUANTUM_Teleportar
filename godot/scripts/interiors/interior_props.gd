class_name InteriorProps
extends RefCounted
## Prop recipes of the interiors: counters, shelves, stools, tables, screens, vending machines, bunks, crates, pipes, lamps and the rest, built from the world's MeshBuilder
## (boxes, struts, cylinders) into the interior's merged meshes. Nothing here creates a node: build() appends to two MeshBuilders (surface, glow) and the caller makes ONE mesh from each.
## A prop is a Dictionary {kind, pos: Vector3 (footprint centre, y = floor or mount height), yaw, size: Vector3 (w, h, d), tint, acc, trim, seed}. Local frame: x = width, y up, front = -Z.
## Vertex data written for shaders/interior_surface.gdshader: COLOR = albedo + emission strength in alpha, UV.x = surface class, UV.y = per-object phase.

const MB := preload("res://scripts/world/mesh_builder.gd")

const C_WALL := 0.0
const C_FLOOR := 1.0
const C_CEIL := 2.0
const C_METAL := 3.0
const C_SOFT := 4.0
const C_NEON := 5.0
const C_DANCE := 6.0
const C_SCREEN := 7.0
const C_STRIP := 8.0
const C_SIGN := 9.0

const F_COLLIDER := 1
const F_WALL := 2           ## mounted on a wall: pos.y is the centre height; no collider
const F_DETAIL := 4         ## decor and clutter: a lower graphics tier drops some of it
const F_CEILING := 8        ## hangs from the ceiling: pos.y is the ceiling height

## kind -> [width, height, depth, flags]
const DEFS := {
	"counter": [3.4, 1.0, 0.8, F_COLLIDER], "bar": [5.0, 1.1, 0.75, F_COLLIDER], "reception": [3.8, 1.1, 0.95, F_COLLIDER],
	"shelf": [2.0, 2.0, 0.5, F_COLLIDER], "stool": [0.42, 0.72, 0.42, F_COLLIDER], "table": [1.3, 0.78, 0.8, F_COLLIDER], "table_round": [1.0, 0.78, 1.0, F_COLLIDER],
	"vending": [0.95, 1.9, 0.8, F_COLLIDER], "fridge": [1.0, 1.9, 0.7, F_COLLIDER], "bed": [2.0, 0.6, 1.1, F_COLLIDER], "bunk": [2.0, 1.9, 1.0, F_COLLIDER],
	"cot": [1.9, 0.5, 0.8, F_COLLIDER], "medbed": [0.9, 0.85, 2.0, F_COLLIDER], "crate": [1.0, 1.0, 1.0, F_COLLIDER], "crate_stack": [1.5, 1.9, 1.0, F_COLLIDER],
	"pallet": [1.2, 1.6, 1.2, F_COLLIDER], "barrel": [0.62, 0.95, 0.62, F_COLLIDER], "couch": [2.1, 0.85, 0.95, F_COLLIDER], "plant": [0.6, 1.4, 0.6, F_COLLIDER],
	"speaker": [0.75, 1.6, 0.65, F_COLLIDER], "dj": [3.2, 1.1, 1.2, F_COLLIDER], "desk": [1.6, 0.78, 0.8, F_COLLIDER], "locker": [0.9, 1.9, 0.5, F_COLLIDER],
	"cabinet": [1.1, 1.4, 0.5, F_COLLIDER], "rack_tall": [2.6, 2.9, 0.9, F_COLLIDER], "workbench": [2.2, 1.0, 0.85, F_COLLIDER], "gate": [3.0, 2.6, 1.0, F_COLLIDER],
	"terminal": [1.3, 1.35, 0.8, F_COLLIDER], "safe": [0.7, 0.8, 0.55, F_COLLIDER], "elevator": [2.2, 2.7, 0.3, F_WALL], "screen": [1.4, 0.8, 0.1, F_WALL | F_DETAIL],
	"poster": [0.8, 1.1, 0.04, F_WALL | F_DETAIL], "rack": [2.2, 1.5, 0.2, F_WALL], "neon_sign": [1.8, 0.5, 0.08, F_WALL],
	"lamp_floor": [0.4, 1.7, 0.4, F_DETAIL], "lamp_hang": [0.7, 0.5, 0.7, F_CEILING], "pipe_run": [4.0, 0.3, 0.3, F_CEILING | F_DETAIL],
	"wall_light": [0.3, 0.4, 0.14, F_WALL | F_DETAIL], "vent": [0.9, 0.12, 0.6, F_CEILING | F_DETAIL], "cables": [1.4, 0.8, 0.08, F_WALL | F_DETAIL],
	"ac_unit": [1.0, 0.34, 0.3, F_WALL | F_DETAIL], "box_stack": [0.9, 0.62, 0.7, F_DETAIL], "trash_bag": [0.5, 0.45, 0.5, F_DETAIL],
	"rug": [2.4, 0.02, 1.7, F_DETAIL], "bin": [0.42, 0.7, 0.42, F_DETAIL], "crate_small": [0.5, 0.5, 0.5, F_DETAIL],
	# interior kit (scripts/interiors/interior_kit.gd): Quaternius pieces appended to the surface mesh
	"kit_teleporter": [1.21, 1.34, 1.19, F_COLLIDER], "kit_pad": [1.23, 0.9, 1.19, F_COLLIDER], "kit_pod": [1.45, 2.8, 1.45, F_COLLIDER], "kit_server": [0.8, 2.08, 0.7, F_COLLIDER],
	"kit_console": [0.9, 1.54, 0.55, F_COLLIDER], "kit_capsule": [0.88, 1.63, 0.88, F_COLLIDER], "kit_crate": [0.9, 0.9, 0.9, F_COLLIDER], "kit_crate_long": [1.3, 0.8, 0.8, F_COLLIDER],
	"kit_container": [1.3, 0.8, 0.8, F_COLLIDER], "kit_shelf": [1.8, 2.5, 0.8, F_COLLIDER], "kit_shelf_tall": [1.9, 2.8, 0.75, F_COLLIDER], "kit_vessel": [0.3, 1.02, 0.3, F_DETAIL],
	"kit_laser": [3.0, 1.1, 1.2, F_COLLIDER], "kit_column": [0.63, 3.0, 0.63, F_COLLIDER], "kit_base": [2.4, 0.2, 2.4, F_DETAIL], "kit_pipes": [3.5, 0.35, 0.3, F_WALL | F_DETAIL],
}

static var _rng := RandomNumberGenerator.new()

const GOODS := [Color(0.55, 0.12, 0.1), Color(0.14, 0.34, 0.5), Color(0.6, 0.5, 0.12), Color(0.15, 0.42, 0.22), Color(0.4, 0.4, 0.42), Color(0.5, 0.25, 0.5), Color(0.7, 0.35, 0.1)]


static func size_of(kind: String) -> Vector3:
	var d: Array = DEFS.get(kind, DEFS["crate"])
	return Vector3(d[0], d[1], d[2])


static func flags_of(kind: String) -> int:
	var d: Array = DEFS.get(kind, DEFS["crate"])
	return int(d[3])


static func has_collider(kind: String) -> bool:
	return flags_of(kind) & F_COLLIDER != 0


## Collision boxes of a prop in its local frame as [center, size] pairs (usually one box; a scanner gate is two posts you walk between).
static func local_boxes(kind: String, size: Vector3) -> Array:
	if kind == "gate":
		return [[Vector3(-(size.x * 0.5 - 0.17), size.y * 0.5, 0.0), Vector3(0.34, size.y, size.z)], [Vector3(size.x * 0.5 - 0.17, size.y * 0.5, 0.0), Vector3(0.34, size.y, size.z)],
			[Vector3(0.0, size.y - 0.15, 0.0), Vector3(size.x, 0.3, size.z)]]
	if kind == "stool":
		return [[Vector3(0.0, size.y * 0.5, 0.0), Vector3(0.36, size.y, 0.36)]]
	return [[Vector3(0.0, size.y * 0.5, 0.0), size]]


static func _bx(mb: RefCounted, c: Vector3, s: Vector3, col: Color, cls: float = 4.0, em: float = 0.0, phase: float = 0.0) -> void:
	mb.uv = Vector2(cls, phase)
	mb.box(c, s, Color(col.r, col.g, col.b, em), false)


static func _cyl(mb: RefCounted, base: Vector3, r: float, h: float, col: Color, cls: float = 3.0, em: float = 0.0, segs: int = 10, top_r: float = -1.0, cap: bool = true) -> void:
	mb.uv = Vector2(cls, 0.0)
	mb.cylinder(base, r, h, segs, Color(col.r, col.g, col.b, em), top_r, cap, false)


static func _halo(gb: RefCounted, c: Vector3, w: float, h: float, col: Color, inten: float) -> void:
	var hw := w * 0.5
	var hh := h * 0.5
	gb.quad(Vector3(c.x - hw, c.y - hh, c.z), Vector3(c.x + hw, c.y - hh, c.z), Vector3(c.x + hw, c.y + hh, c.z), Vector3(c.x - hw, c.y + hh, c.z), Vector3(0, 0, -1),
		Color(col.r, col.g, col.b, inten), Vector2.ZERO, Vector2.ZERO, PackedVector2Array([Vector2(2, 0), Vector2(3, 0), Vector2(3, 1), Vector2(2, 1)]))


static func _shade(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)


## Pseudo-script glyphs (bars and ticks, no real lettering): `n` glyphs across width w at height y, local z = z.
static func _glyphs(mb: RefCounted, x0: float, y: float, z: float, w: float, h: float, n: int, col: Color, cls: float, em: float, phase: float) -> void:
	var step := w / float(n)
	for i in n:
		var gw := step * _rng.randf_range(0.35, 0.8)
		var gh := h * _rng.randf_range(0.45, 1.0)
		var cx := x0 + step * (float(i) + 0.5)
		_bx(mb, Vector3(cx, y + (gh - h) * 0.5 * _rng.randf_range(-0.4, 0.6), z), Vector3(gw, gh, 0.012), col, cls, em, phase)
		if _rng.randf() < 0.4:
			_bx(mb, Vector3(cx, y + h * 0.5 * _rng.randf_range(-0.8, 0.8), z), Vector3(step * 0.9, h * 0.12, 0.012), col, cls, em, phase)


static func build(sb: RefCounted, gb: RefCounted, p: Dictionary) -> void:
	var kind: String = p["kind"]
	var size: Vector3 = p["size"]
	var tint: Color = p["tint"]
	var acc: Color = p["acc"]
	var trim: Color = p["trim"]
	_rng.seed = int(p["seed"])
	var s0: int = sb.verts.size()
	var g0: int = gb.verts.size()
	var w := size.x
	var h := size.y
	var d := size.z
	var ph := _rng.randf() * 20.0
	match kind:
		"counter", "bar", "reception":
			var top := trim.lerp(Color(0.3, 0.3, 0.33), 0.55)
			_bx(sb, Vector3(0, h * 0.47, 0), Vector3(w, h * 0.94, d), tint, C_METAL)
			_bx(sb, Vector3(0, h * 0.97, 0.02), Vector3(w + 0.08, 0.07, d + 0.12), top, C_METAL)
			_bx(sb, Vector3(0, 0.18, -d * 0.5 - 0.012), Vector3(w - 0.2, 0.06, 0.03), acc, C_STRIP, 1.9)
			_bx(sb, Vector3(0, h * 0.62, -d * 0.5 - 0.01), Vector3(w - 0.3, 0.025, 0.02), _shade(trim, 0.8), C_METAL)
			_halo(gb, Vector3(0, 0.16, -d * 0.5 - 0.1), w, 0.7, acc, 0.45)
			var sx := w * 0.28 * (1.0 if _rng.randf() < 0.5 else -1.0)
			_bx(sb, Vector3(sx, h + 0.04, 0.0), Vector3(0.4, 0.04, 0.32), Color(0.06, 0.06, 0.07), C_METAL)
			_bx(sb, Vector3(sx, h + 0.26, 0.1), Vector3(0.36, 0.24, 0.03), acc.lerp(Color.WHITE, 0.35), C_SCREEN, 1.3, ph)
			_bx(sb, Vector3(sx, h + 0.14, 0.1), Vector3(0.05, 0.12, 0.05), Color(0.08, 0.08, 0.09), C_METAL)
			for i in 3:
				_bx(sb, Vector3(-w * 0.3 + i * 0.4 + _rng.randf() * 0.1, h + 0.1, _rng.randf_range(-0.15, 0.15)), Vector3(0.18, 0.14, 0.14), GOODS[_rng.randi() % GOODS.size()], C_SOFT)
			if kind == "bar":
				_bx(sb, Vector3(0, 0.22, -d * 0.5 - 0.16), Vector3(w - 0.4, 0.04, 0.04), Color(0.45, 0.42, 0.38), C_METAL)         # foot rail
				for i in int(w / 0.45):
					_cyl(sb, Vector3(-w * 0.5 + 0.3 + i * 0.45, h + 0.03, 0.12), 0.045, 0.22 + _rng.randf() * 0.08, Color(acc.r, acc.g, acc.b), C_NEON, 0.9, 6, -1.0, true)
			if kind == "reception":
				_bx(sb, Vector3(0, h + 0.5, d * 0.5 - 0.05), Vector3(w * 0.7, 0.5, 0.05), trim.lerp(acc, 0.4), C_STRIP, 0.8)
		"shelf":
			var back := _shade(tint, 0.85)
			_bx(sb, Vector3(0, h * 0.5, d * 0.5 - 0.02), Vector3(w, h, 0.04), back, C_METAL)
			sb.strut(Vector3(-w * 0.5 + 0.06, 0.1, d * 0.5 + 0.01), Vector3(w * 0.5 - 0.06, h - 0.1, d * 0.5 + 0.01), 0.035, Color(0.5, 0.45, 0.35, 0.0), false)
			sb.strut(Vector3(w * 0.5 - 0.06, 0.1, d * 0.5 + 0.01), Vector3(-w * 0.5 + 0.06, h - 0.1, d * 0.5 + 0.01), 0.035, Color(0.5, 0.45, 0.35, 0.0), false)
			_bx(sb, Vector3(0, h - 0.18, d * 0.5 + 0.012), Vector3(0.5, 0.12, 0.012), acc, C_STRIP, 0.8)
			_bx(sb, Vector3(-w * 0.5 + 0.02, h * 0.5, 0), Vector3(0.04, h, d), tint, C_METAL)
			_bx(sb, Vector3(w * 0.5 - 0.02, h * 0.5, 0), Vector3(0.04, h, d), tint, C_METAL)
			var levels := 5
			for i in levels:
				var y := 0.1 + float(i) * (h - 0.22) / float(levels - 1)
				_bx(sb, Vector3(0, y, 0), Vector3(w - 0.06, 0.03, d - 0.04), tint, C_METAL)
				if i < levels - 1:
					var x := -w * 0.5 + 0.15
					while x < w * 0.5 - 0.2:
						var iw := _rng.randf_range(0.14, 0.3)
						var ih := _rng.randf_range(0.18, (h - 0.22) / float(levels - 1) - 0.06)
						var col: Color = GOODS[_rng.randi() % GOODS.size()]
						_bx(sb, Vector3(x + iw * 0.5, y + 0.015 + ih * 0.5, _rng.randf_range(-0.04, 0.06)), Vector3(iw, ih, d * 0.62), col, C_SOFT, 0.35 if _rng.randf() < 0.18 else 0.0)
						x += iw + 0.03
			_bx(sb, Vector3(0, h - 0.02, -d * 0.5 + 0.01), Vector3(w - 0.1, 0.05, 0.02), acc, C_STRIP, 1.4)
		"stool":
			_cyl(sb, Vector3(0, 0.0, 0), 0.17, 0.04, _shade(tint, 0.8), C_METAL, 0.0, 8)
			_cyl(sb, Vector3(0, 0.04, 0), 0.03, 0.58, Color(0.3, 0.3, 0.33), C_METAL, 0.0, 6)
			_cyl(sb, Vector3(0, 0.6, 0), 0.19, 0.1, tint, C_SOFT, 0.0, 10, 0.17)
		"table":
			_bx(sb, Vector3(0, h - 0.03, 0), Vector3(w, 0.06, d), trim.lerp(tint, 0.5), C_METAL)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_bx(sb, Vector3(sx * (w * 0.5 - 0.07), (h - 0.06) * 0.5, sz * (d * 0.5 - 0.07)), Vector3(0.06, h - 0.06, 0.06), _shade(tint, 0.7), C_METAL)
			_bx(sb, Vector3(_rng.randf_range(-0.3, 0.3), h + 0.04, _rng.randf_range(-0.15, 0.15)), Vector3(0.18, 0.08, 0.18), acc.lerp(Color.WHITE, 0.2), C_STRIP, 0.8)
		"table_round":
			_cyl(sb, Vector3(0, h - 0.05, 0), w * 0.5, 0.05, trim.lerp(tint, 0.45), C_METAL, 0.0, 14)
			_cyl(sb, Vector3(0, 0.05, 0), 0.05, h - 0.1, _shade(tint, 0.7), C_METAL, 0.0, 6)
			_cyl(sb, Vector3(0, 0.0, 0), 0.28, 0.05, _shade(tint, 0.7), C_METAL, 0.0, 10)
			_cyl(sb, Vector3(_rng.randf_range(-0.15, 0.15), h, _rng.randf_range(-0.15, 0.15)), 0.05, 0.1, acc, C_STRIP, 1.1, 6)
		"screen":
			_bx(sb, Vector3(0, 0, 0.02), Vector3(w, h, 0.06), Color(0.04, 0.04, 0.05), C_METAL)
			_bx(sb, Vector3(0, 0, -0.012), Vector3(w - 0.08, h - 0.08, 0.02), acc.lerp(Color(0.3, 0.9, 1.0), _rng.randf() * 0.7), C_SCREEN, 1.4, ph)
			_halo(gb, Vector3(0, 0, -0.1), w * 1.5, h * 1.6, acc, 0.22)
		"poster":
			_bx(sb, Vector3(0, 0, 0.01), Vector3(w, h, 0.03), _shade(tint, 0.55), C_SOFT)
			_bx(sb, Vector3(0, h * 0.18, -0.012), Vector3(w - 0.1, h * 0.55, 0.012), acc.lerp(tint, 0.55), C_STRIP, 0.9)
			_glyphs(sb, -w * 0.5 + 0.06, -h * 0.28, -0.014, w - 0.12, h * 0.16, 6, acc.lerp(Color.WHITE, 0.4), C_SIGN, 1.6, ph)
		"vending":
			_bx(sb, Vector3(0, h * 0.5, 0), Vector3(w, h, d), tint, C_METAL)
			var pc := acc.lerp(Color.WHITE, 0.25)
			_bx(sb, Vector3(0, h * 0.58, -d * 0.5 - 0.01), Vector3(w - 0.22, h * 0.62, 0.025), pc, C_STRIP, 1.0)
			for r in 4:
				for c in 3:
					_bx(sb, Vector3(-0.22 + c * 0.22, h * 0.34 + r * 0.17, -d * 0.5 - 0.03), Vector3(0.14, 0.11, 0.03), GOODS[_rng.randi() % GOODS.size()], C_SOFT, 0.2)
			_bx(sb, Vector3(0, 0.22, -d * 0.5 - 0.01), Vector3(0.5, 0.22, 0.02), Color(0.03, 0.03, 0.03), C_METAL)
			_bx(sb, Vector3(0, h - 0.07, -d * 0.5 - 0.012), Vector3(w - 0.1, 0.06, 0.02), acc, C_STRIP, 2.0)
			_halo(gb, Vector3(0, h * 0.55, -d * 0.5 - 0.15), w + 0.5, h * 0.9, pc, 0.3)
		"fridge":
			_bx(sb, Vector3(0, h * 0.5, 0), Vector3(w, h, d), Color(0.4, 0.42, 0.45), C_METAL)
			_bx(sb, Vector3(0, h * 0.55, -d * 0.5 - 0.01), Vector3(w - 0.14, h * 0.8, 0.02), Color(0.6, 0.85, 1.0), C_STRIP, 0.55)
			for r in 4:
				_bx(sb, Vector3(0, 0.45 + r * 0.38, -d * 0.5 - 0.03), Vector3(w - 0.3, 0.2, 0.03), GOODS[_rng.randi() % GOODS.size()], C_SOFT, 0.3)
			_bx(sb, Vector3(w * 0.5 - 0.1, h * 0.5, -d * 0.5 - 0.04), Vector3(0.03, 0.6, 0.04), Color(0.7, 0.7, 0.72), C_METAL)
			_halo(gb, Vector3(0, h * 0.55, -d * 0.5 - 0.15), w + 0.3, h * 0.9, Color(0.5, 0.85, 1.0), 0.16)
		"bed", "cot":
			var bh := 0.3 if kind == "bed" else 0.25
			_bx(sb, Vector3(0, bh * 0.5, 0), Vector3(w, bh, d), _shade(tint, 0.7), C_METAL)
			_bx(sb, Vector3(0, bh + 0.09, 0), Vector3(w - 0.1, 0.18, d - 0.1), tint.lerp(Color(0.5, 0.5, 0.55), 0.35), C_SOFT)
			_bx(sb, Vector3(0, bh + 0.2, -d * 0.2), Vector3(w - 0.14, 0.05, d * 0.55), acc.lerp(tint, 0.65), C_SOFT)
			_bx(sb, Vector3(w * 0.5 - 0.3, bh + 0.24, d * 0.28), Vector3(0.45, 0.1, 0.3), Color(0.55, 0.55, 0.6), C_SOFT)
			if kind == "bed":
				_bx(sb, Vector3(0, 0.55, d * 0.5 - 0.03), Vector3(w, 0.5, 0.06), _shade(tint, 0.6), C_METAL)
		"bunk":
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_bx(sb, Vector3(sx * (w * 0.5 - 0.04), h * 0.5, sz * (d * 0.5 - 0.04)), Vector3(0.07, h, 0.07), Color(0.3, 0.3, 0.32), C_METAL)
			for lv in 2:
				var y := 0.35 + float(lv) * 0.85
				_bx(sb, Vector3(0, y, 0), Vector3(w - 0.1, 0.06, d - 0.1), Color(0.25, 0.25, 0.28), C_METAL)
				_bx(sb, Vector3(0, y + 0.1, 0), Vector3(w - 0.16, 0.12, d - 0.16), tint.lerp(Color(0.3, 0.4, 0.4), 0.5), C_SOFT)
			_bx(sb, Vector3(w * 0.5 - 0.02, 0.9, -d * 0.5 + 0.25), Vector3(0.04, 1.6, 0.05), Color(0.35, 0.35, 0.38), C_METAL)
		"medbed":
			_bx(sb, Vector3(0, 0.3, 0.05), Vector3(0.5, 0.6, d - 0.5), Color(0.3, 0.32, 0.33), C_METAL)
			_bx(sb, Vector3(0, 0.66, 0), Vector3(w, 0.14, d), Color(0.55, 0.62, 0.62), C_SOFT)
			_bx(sb, Vector3(0, 0.75, d * 0.5 - 0.3), Vector3(0.5, 0.1, 0.4), Color(0.7, 0.75, 0.75), C_SOFT)
			_bx(sb, Vector3(w * 0.5 - 0.02, 0.78, 0), Vector3(0.04, 0.12, d * 0.8), Color(0.45, 0.47, 0.48), C_METAL)
			_bx(sb, Vector3(-w * 0.5 + 0.02, 0.78, 0), Vector3(0.04, 0.12, d * 0.8), Color(0.45, 0.47, 0.48), C_METAL)
			_bx(sb, Vector3(0, 1.05, d * 0.5 + 0.0), Vector3(0.55, 0.32, 0.05), acc, C_SCREEN, 1.3, ph)
			_bx(sb, Vector3(0, 0.86, d * 0.5 - 0.06), Vector3(0.05, 0.4, 0.05), Color(0.35, 0.35, 0.37), C_METAL)
		"crate", "crate_small":
			_bx(sb, Vector3(0, h * 0.5, 0), size, tint, C_METAL)
			_bx(sb, Vector3(0, h * 0.5, 0), Vector3(w + 0.02, h * 0.1, d + 0.02), _shade(tint, 0.6), C_METAL)
			for sx in [-1.0, 1.0]:
				_bx(sb, Vector3(sx * (w * 0.5 - 0.04), h * 0.5, 0), Vector3(0.06, h + 0.02, d + 0.02), _shade(tint, 1.35), C_METAL)
			_bx(sb, Vector3(w * 0.2, h * 0.7, -d * 0.5 - 0.01), Vector3(w * 0.3, h * 0.12, 0.012), acc, C_STRIP, 0.8)
		"crate_stack":
			_bx(sb, Vector3(0, 0.475, 0), Vector3(w, 0.95, d), tint, C_METAL)
			_bx(sb, Vector3(0, 0.475, 0), Vector3(w + 0.02, 0.1, d + 0.02), _shade(tint, 0.6), C_METAL)
			_bx(sb, Vector3(-0.1, 1.42, 0.05), Vector3(w * 0.72, 0.95, d * 0.8), _shade(tint, 1.15), C_METAL)
			_bx(sb, Vector3(-0.1, 1.42, 0.05), Vector3(w * 0.72 + 0.02, 0.1, d * 0.8 + 0.02), _shade(tint, 0.6), C_METAL)
			_bx(sb, Vector3(w * 0.25, 0.7, -d * 0.5 - 0.01), Vector3(w * 0.25, 0.1, 0.012), acc, C_STRIP, 0.9)
		"pallet":
			_bx(sb, Vector3(0, 0.07, 0), Vector3(w, 0.14, d), Color(0.3, 0.22, 0.14), C_SOFT)
			for i in 2:
				_bx(sb, Vector3(0, 0.14 + 0.38 + i * 0.76, 0), Vector3(w - 0.12, 0.74, d - 0.12), Color(0.3, 0.3, 0.28).lerp(tint, 0.4), C_SOFT)
				_bx(sb, Vector3(0, 0.14 + 0.38 + i * 0.76, 0), Vector3(w - 0.08, 0.04, d - 0.08), Color(0.55, 0.57, 0.6), C_METAL)
			_bx(sb, Vector3(0.2, 1.1, -d * 0.5 + 0.04), Vector3(0.3, 0.2, 0.012), acc, C_STRIP, 1.0)
		"barrel":
			_cyl(sb, Vector3(0, 0, 0), w * 0.5, h, tint, C_METAL, 0.0, 10)
			_cyl(sb, Vector3(0, h * 0.3, 0), w * 0.5 + 0.012, 0.05, _shade(tint, 0.6), C_METAL, 0.0, 10)
			_cyl(sb, Vector3(0, h * 0.72, 0), w * 0.5 + 0.012, 0.05, _shade(tint, 0.6), C_METAL, 0.0, 10)
			_cyl(sb, Vector3(0, h * 0.5 - 0.02, 0), w * 0.5 + 0.014, 0.05, acc, C_STRIP, 0.6, 10)
		"lamp_floor":
			_cyl(sb, Vector3(0, 0, 0), 0.16, 0.03, Color(0.12, 0.12, 0.13), C_METAL, 0.0, 8)
			_cyl(sb, Vector3(0, 0.03, 0), 0.02, h - 0.4, Color(0.2, 0.2, 0.22), C_METAL, 0.0, 6)
			_cyl(sb, Vector3(0, h - 0.4, 0), 0.2, 0.36, acc.lerp(Color(1.0, 0.8, 0.5), 0.5), C_STRIP, 1.7, 10, 0.12)
			_halo(gb, Vector3(0, h - 0.2, 0), 1.4, 1.4, acc.lerp(Color(1.0, 0.8, 0.5), 0.5), 0.5)
		"lamp_hang":
			_bx(sb, Vector3(0, -0.4, 0), Vector3(0.02, 0.8, 0.02), Color(0.1, 0.1, 0.11), C_METAL)
			_cyl(sb, Vector3(0, -0.8, 0), 0.32, 0.22, Color(0.12, 0.1, 0.1), C_METAL, 0.0, 10, 0.12)
			_cyl(sb, Vector3(0, -0.8, 0), 0.26, 0.04, acc.lerp(Color(1.0, 0.85, 0.6), 0.5), C_STRIP, 2.0, 10, 0.26)
			_halo(gb, Vector3(0, -0.85, 0), 1.6, 1.6, acc.lerp(Color(1.0, 0.8, 0.5), 0.4), 0.55)
		"couch":
			_bx(sb, Vector3(0, 0.2, 0), Vector3(w, 0.4, d), _shade(tint, 0.8), C_SOFT)
			_bx(sb, Vector3(0, 0.62, d * 0.5 - 0.11), Vector3(w, 0.45, 0.22), tint, C_SOFT)
			for sx in [-1.0, 1.0]:
				_bx(sb, Vector3(sx * (w * 0.5 - 0.1), 0.5, 0), Vector3(0.2, 0.3, d), tint, C_SOFT)
			var n := 3 if w > 1.8 else 2
			for i in n:
				_bx(sb, Vector3(-w * 0.5 + 0.25 + (w - 0.5) * (float(i) + 0.5) / float(n), 0.46, -0.08), Vector3((w - 0.5) / float(n) - 0.04, 0.12, d - 0.35), tint.lerp(Color.WHITE, 0.12), C_SOFT)
			_bx(sb, Vector3(w * 0.3, 0.62, 0.0), Vector3(0.4, 0.4, 0.12), acc.lerp(tint, 0.5), C_SOFT)
		"plant":
			_cyl(sb, Vector3(0, 0, 0), 0.22, 0.36, Color(0.16, 0.14, 0.14), C_METAL, 0.0, 8, 0.19)
			mb_sphere(sb, Vector3(0, 0.85, 0), Vector3(0.34, 0.5, 0.34), Color(0.05, 0.16, 0.1))
			mb_sphere(sb, Vector3(0.12, 1.15, 0.05), Vector3(0.22, 0.3, 0.22), Color(0.07, 0.22, 0.14))
			_bx(sb, Vector3(0.0, 1.38, 0.0), Vector3(0.08, 0.08, 0.08), acc, C_STRIP, 1.6)
		"speaker":
			_bx(sb, Vector3(0, h * 0.5, 0), size, Color(0.05, 0.05, 0.06), C_METAL)
			_bx(sb, Vector3(0, h * 0.34, -d * 0.5 - 0.01), Vector3(w * 0.7, w * 0.7, 0.03), Color(0.1, 0.1, 0.11), C_METAL)
			_bx(sb, Vector3(0, h * 0.34, -d * 0.5 - 0.03), Vector3(w * 0.34, w * 0.34, 0.03), Color(0.02, 0.02, 0.02), C_METAL)
			_bx(sb, Vector3(0, h * 0.78, -d * 0.5 - 0.01), Vector3(w * 0.4, w * 0.4, 0.03), Color(0.1, 0.1, 0.11), C_METAL)
			_bx(sb, Vector3(0, h - 0.06, -d * 0.5 - 0.012), Vector3(w - 0.1, 0.04, 0.02), acc, C_STRIP, 2.0)
		"dj":
			_bx(sb, Vector3(0, h * 0.46, 0), Vector3(w, h * 0.92, d), Color(0.06, 0.06, 0.08), C_METAL)
			_bx(sb, Vector3(0, h * 0.95, 0), Vector3(w + 0.06, 0.06, d + 0.06), Color(0.15, 0.15, 0.18), C_METAL)
			for sx in [-1.0, 1.0]:
				_cyl(sb, Vector3(sx * w * 0.3, h * 0.98, -0.05), 0.28, 0.05, Color(0.04, 0.04, 0.05), C_METAL, 0.0, 14)
				_cyl(sb, Vector3(sx * w * 0.3, h * 1.03, -0.05), 0.1, 0.01, acc, C_STRIP, 1.8, 8)
			_bx(sb, Vector3(0, h * 1.0 + 0.03, -0.05), Vector3(0.7, 0.06, 0.5), Color(0.1, 0.1, 0.12), C_METAL)
			_bx(sb, Vector3(0, h * 1.0 + 0.07, -0.15), Vector3(0.5, 0.025, 0.04), acc, C_STRIP, 2.0)
			_bx(sb, Vector3(0, 0.55, -d * 0.5 - 0.01), Vector3(w - 0.4, 0.6, 0.02), acc, C_SCREEN, 1.2, ph)
			_bx(sb, Vector3(0, 1.95, d * 0.5 - 0.04), Vector3(w + 0.4, 1.5, 0.06), acc.lerp(Color(0.2, 0.2, 1.0), 0.5), C_SCREEN, 1.4, ph + 3.0)
			_halo(gb, Vector3(0, 1.9, -0.3), w + 2.0, 2.6, acc, 0.35)
		"desk":
			_bx(sb, Vector3(0, h - 0.03, 0), Vector3(w, 0.06, d), trim.lerp(tint, 0.5), C_METAL)
			for sx in [-1.0, 1.0]:
				_bx(sb, Vector3(sx * (w * 0.5 - 0.03), (h - 0.06) * 0.5, 0), Vector3(0.05, h - 0.06, d - 0.06), _shade(tint, 0.75), C_METAL)
			_bx(sb, Vector3(w * 0.3, 0.3, 0.0), Vector3(0.45, 0.5, d - 0.08), _shade(tint, 0.9), C_METAL)
			_bx(sb, Vector3(-w * 0.15, h + 0.2, d * 0.2), Vector3(0.5, 0.32, 0.04), acc, C_SCREEN, 1.2, ph)
			_bx(sb, Vector3(-w * 0.15, h + 0.04, d * 0.05), Vector3(0.4, 0.02, 0.14), Color(0.07, 0.07, 0.08), C_METAL)
			_bx(sb, Vector3(w * 0.25, h + 0.04, -0.1), Vector3(0.22, 0.06, 0.3), Color(0.5, 0.45, 0.35), C_SOFT)
		"locker", "cabinet":
			_bx(sb, Vector3(0, h * 0.5, 0), size, tint, C_METAL)
			var nd := 3 if kind == "locker" else 2
			for i in nd:
				var cx := -w * 0.5 + w * (float(i) + 0.5) / float(nd)
				_bx(sb, Vector3(cx, h * 0.5, -d * 0.5 - 0.008), Vector3(w / float(nd) - 0.05, h - 0.1, 0.012), _shade(tint, 1.25), C_METAL)
				_bx(sb, Vector3(cx + 0.12, h * 0.52, -d * 0.5 - 0.025), Vector3(0.03, 0.14, 0.025), Color(0.1, 0.1, 0.11), C_METAL)
				_bx(sb, Vector3(cx, h * 0.88, -d * 0.5 - 0.02), Vector3(0.18, 0.015, 0.012), Color(0.02, 0.02, 0.02), C_METAL)
			_bx(sb, Vector3(-w * 0.5 + 0.1, h - 0.1, -d * 0.5 - 0.02), Vector3(0.04, 0.04, 0.012), acc, C_STRIP, 2.0)
		"rack_tall":
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_bx(sb, Vector3(sx * (w * 0.5 - 0.05), h * 0.5, sz * (d * 0.5 - 0.05)), Vector3(0.09, h, 0.09), Color(0.7, 0.35, 0.08), C_METAL)
			for lv in 3:
				var y := 0.35 + float(lv) * 0.95
				_bx(sb, Vector3(0, y, 0), Vector3(w, 0.07, d - 0.06), Color(0.16, 0.16, 0.18), C_METAL)
				var x := -w * 0.5 + 0.1
				while x < w * 0.5 - 0.35:
					var cw := _rng.randf_range(0.45, 0.8)
					var ch := _rng.randf_range(0.35, 0.8)
					_bx(sb, Vector3(x + cw * 0.5, y + 0.035 + ch * 0.5, _rng.randf_range(-0.05, 0.05)), Vector3(cw, ch, d - 0.2), tint.lerp(Color(0.35, 0.28, 0.18), 0.5) * _rng.randf_range(0.7, 1.2), C_SOFT)
					x += cw + 0.06
				_bx(sb, Vector3(0, y - 0.02, -d * 0.5 + 0.01), Vector3(w - 0.1, 0.03, 0.015), acc, C_STRIP, 1.0)
		"workbench":
			_bx(sb, Vector3(0, h - 0.04, 0), Vector3(w, 0.08, d), Color(0.18, 0.18, 0.2), C_METAL)
			for sx in [-1.0, 1.0]:
				_bx(sb, Vector3(sx * (w * 0.5 - 0.05), (h - 0.08) * 0.5, 0), Vector3(0.06, h - 0.08, d - 0.1), Color(0.12, 0.12, 0.14), C_METAL)
			_bx(sb, Vector3(0, h * 0.4, 0.05), Vector3(w - 0.1, 0.04, d - 0.2), Color(0.12, 0.12, 0.14), C_METAL)
			_bx(sb, Vector3(0, 1.45, d * 0.5 - 0.03), Vector3(w, 0.8, 0.05), Color(0.1, 0.12, 0.14), C_METAL)
			for i in 6:
				_bx(sb, Vector3(-w * 0.5 + 0.2 + i * (w - 0.4) / 5.0, 1.42 + _rng.randf_range(-0.2, 0.2), d * 0.5 - 0.07), Vector3(0.06, _rng.randf_range(0.15, 0.4), 0.05), Color(0.4, 0.4, 0.43), C_METAL)
			_bx(sb, Vector3(-w * 0.25, h + 0.22, 0.12), Vector3(0.55, 0.36, 0.04), acc, C_SCREEN, 1.3, ph)
			_bx(sb, Vector3(w * 0.2, h + 0.05, -0.05), Vector3(0.5, 0.1, 0.35), Color(0.08, 0.1, 0.1), C_METAL)
			_bx(sb, Vector3(w * 0.2, h + 0.12, -0.05), Vector3(0.3, 0.02, 0.02), acc, C_STRIP, 2.2)
		"gate":
			for sx in [-1.0, 1.0]:
				_bx(sb, Vector3(sx * (w * 0.5 - 0.17), h * 0.5, 0), Vector3(0.34, h, d), Color(0.12, 0.15, 0.16), C_METAL)
				_bx(sb, Vector3(sx * (w * 0.5 - 0.17), h * 0.55, -d * 0.5 - 0.01), Vector3(0.08, h * 0.6, 0.012), acc, C_STRIP, 1.8)
			_bx(sb, Vector3(0, h - 0.15, 0), Vector3(w, 0.3, d), Color(0.1, 0.12, 0.13), C_METAL)
			_bx(sb, Vector3(0, h - 0.32, 0), Vector3(w - 0.7, 0.04, d - 0.2), acc, C_STRIP, 2.0)
			gb.quad(Vector3(-w * 0.5 + 0.34, 0.05, 0), Vector3(w * 0.5 - 0.34, 0.05, 0), Vector3(w * 0.5 - 0.34, h - 0.32, 0), Vector3(-w * 0.5 + 0.34, h - 0.32, 0), Vector3(0, 0, -1),
				Color(acc.r, acc.g, acc.b, 0.22), Vector2.ZERO, Vector2.ZERO, PackedVector2Array([Vector2(2, 0), Vector2(3, 0), Vector2(3, 1), Vector2(2, 1)]))
		"terminal":
			_bx(sb, Vector3(0, 0.4, 0.05), Vector3(w, 0.8, d - 0.1), Color(0.1, 0.12, 0.13), C_METAL)
			_bx(sb, Vector3(0, 0.82, 0.0), Vector3(w + 0.04, 0.05, d), Color(0.18, 0.2, 0.22), C_METAL)
			_bx(sb, Vector3(0, 1.1, d * 0.5 - 0.1), Vector3(w * 0.75, 0.5, 0.07), Color(0.04, 0.04, 0.05), C_METAL)
			_bx(sb, Vector3(0, 1.1, d * 0.5 - 0.14), Vector3(w * 0.75 - 0.08, 0.42, 0.02), acc, C_SCREEN, 1.5, ph)
			_bx(sb, Vector3(0, 0.86, -0.1), Vector3(0.5, 0.025, 0.2), Color(0.05, 0.05, 0.06), C_METAL)
			_halo(gb, Vector3(0, 1.1, 0.1), w * 1.6, 1.0, acc, 0.3)
		"safe":
			_bx(sb, Vector3(0, h * 0.5, 0), size, Color(0.12, 0.12, 0.14), C_METAL)
			_bx(sb, Vector3(0, h * 0.5, -d * 0.5 - 0.012), Vector3(w - 0.1, h - 0.1, 0.02), Color(0.2, 0.2, 0.23), C_METAL)
			_cyl(sb, Vector3(0.05, h * 0.5 - 0.02, -d * 0.5 - 0.03), 0.07, 0.03, Color(0.45, 0.45, 0.48), C_METAL, 0.0, 10)
			_bx(sb, Vector3(-w * 0.28, h * 0.78, -d * 0.5 - 0.03), Vector3(0.05, 0.03, 0.02), Color(0.2, 1.0, 0.4), C_STRIP, 2.2)
		"elevator":
			_bx(sb, Vector3(0, 0, 0.1), Vector3(w + 0.2, h + 0.2, 0.1), trim, C_METAL)
			for sx in [-1.0, 1.0]:
				_bx(sb, Vector3(sx * (w * 0.25 + 0.02), -0.05, 0.0), Vector3(w * 0.5 - 0.04, h - 0.2, 0.06), Color(0.3, 0.3, 0.33), C_METAL)
			_bx(sb, Vector3(0, h * 0.5 + 0.28, -0.04), Vector3(0.6, 0.12, 0.03), acc, C_STRIP, 2.2)
			_bx(sb, Vector3(w * 0.5 + 0.35, 0.0, -0.02), Vector3(0.1, 0.22, 0.03), acc, C_STRIP, 1.8)
			_halo(gb, Vector3(0, h * 0.5 + 0.28, -0.2), 1.5, 0.8, acc, 0.4)
		"rack":
			_bx(sb, Vector3(0, 0, 0.08), Vector3(w, h, 0.05), Color(0.08, 0.08, 0.09), C_METAL)
			for i in 4:
				var y := h * 0.5 - 0.22 - float(i) * (h - 0.3) / 3.0
				var len := _rng.randf_range(0.8, 1.1)
				var x := -w * 0.5 + 0.25 + _rng.randf() * (w - 0.5 - len)
				_bx(sb, Vector3(x + len * 0.5, y, 0.0), Vector3(len, 0.045, 0.045), Color(0.14, 0.14, 0.16), C_METAL)
				_bx(sb, Vector3(x + 0.12, y - 0.05, 0.0), Vector3(0.28, 0.1, 0.06), Color(0.22, 0.16, 0.12), C_SOFT)
				_bx(sb, Vector3(x + len * 0.65, y + 0.04, 0.0), Vector3(0.1, 0.03, 0.03), Color(0.1, 0.1, 0.11), C_METAL)
				_bx(sb, Vector3(x + len - 0.05, y, -0.03), Vector3(0.025, 0.025, 0.012), acc, C_STRIP, 2.0)
			_bx(sb, Vector3(0, h * 0.5 - 0.02, -0.04), Vector3(w - 0.1, 0.03, 0.02), acc, C_STRIP, 1.0)
		"neon_sign":
			_bx(sb, Vector3(0, 0, 0.03), Vector3(w, h, 0.05), Color(0.03, 0.03, 0.04), C_METAL)
			_glyphs(sb, -w * 0.5 + 0.1, 0.0, -0.012, w - 0.2, h * 0.7, 7, acc, C_NEON, 2.2, ph)
			_bx(sb, Vector3(0, h * 0.5 - 0.03, -0.012), Vector3(w - 0.1, 0.03, 0.012), acc, C_NEON, 2.0, ph)
			_bx(sb, Vector3(0, -h * 0.5 + 0.03, -0.012), Vector3(w - 0.1, 0.03, 0.012), acc, C_NEON, 2.0, ph)
			_halo(gb, Vector3(0, 0, -0.12), w + 1.6, h + 1.4, acc, 0.75)
		"rug":
			_bx(sb, Vector3(0, 0.01, 0), size, acc.lerp(tint, 0.6) * 0.45, C_SOFT)
			_bx(sb, Vector3(0, 0.012, 0), Vector3(w - 0.3, 0.02, d - 0.3), tint * 0.7, C_SOFT)
		"wall_light":
			_bx(sb, Vector3(0, 0, 0.05), Vector3(w, h, 0.06), Color(0.06, 0.06, 0.07), C_METAL)
			_bx(sb, Vector3(0, h * 0.18, -0.01), Vector3(w * 0.6, h * 0.5, 0.05), acc.lerp(Color(1.0, 0.85, 0.6), 0.55), C_STRIP, 1.6)
			_halo(gb, Vector3(0, h * 0.2, -0.15), 1.3, 1.5, acc.lerp(Color(1.0, 0.85, 0.6), 0.5), 0.4)
		"vent":
			_bx(sb, Vector3(0, -0.04, 0), Vector3(w, 0.08, d), Color(0.12, 0.12, 0.13), C_METAL)
			for i in 5:
				_bx(sb, Vector3(0, -0.09, -d * 0.5 + 0.08 + i * (d - 0.16) / 4.0), Vector3(w - 0.12, 0.03, 0.04), Color(0.03, 0.03, 0.03), C_METAL)
		"cables":
			var cols: Array = [Color(0.05, 0.05, 0.06), Color(0.04, 0.04, 0.05), acc.lerp(Color(0.1, 0.1, 0.1), 0.6)]
			for k in 3:
				var y0 := h * 0.45 - k * 0.08
				var prev := Vector3(-w * 0.5, y0 + 0.2 * k, 0.04)
				for i in range(1, 7):
					var t := float(i) / 6.0
					var sag := -sin(t * PI) * (0.25 + 0.06 * k)
					var cur := Vector3(-w * 0.5 + w * t, y0 + 0.2 * k * (1.0 - t) + sag, 0.04 + 0.01 * k)
					sb.uv = Vector2(C_METAL, 0.0)
					sb.strut(prev, cur, 0.035, Color(cols[k].r, cols[k].g, cols[k].b, 0.0), false)
					prev = cur
		"ac_unit":
			_bx(sb, Vector3(0, 0, 0.1), size, Color(0.55, 0.57, 0.6), C_METAL)
			for i in 5:
				_bx(sb, Vector3(0, -h * 0.35 + i * 0.045, -0.055), Vector3(w - 0.16, 0.02, 0.02), Color(0.2, 0.2, 0.22), C_METAL)
			_bx(sb, Vector3(w * 0.38, h * 0.28, -0.055), Vector3(0.04, 0.04, 0.02), Color(0.2, 1.0, 0.5), C_STRIP, 2.0)
			_bx(sb, Vector3(-w * 0.45, -h * 0.5 - 0.12, 0.12), Vector3(0.03, 0.26, 0.03), Color(0.1, 0.1, 0.11), C_METAL)
		"box_stack":
			_bx(sb, Vector3(-0.15, 0.17, 0.0), Vector3(0.55, 0.34, 0.5), Color(0.3, 0.24, 0.17), C_SOFT)
			_bx(sb, Vector3(0.28, 0.14, 0.1), Vector3(0.4, 0.28, 0.4), Color(0.26, 0.22, 0.18), C_SOFT)
			_bx(sb, Vector3(-0.1, 0.46, 0.02), Vector3(0.4, 0.26, 0.38), Color(0.34, 0.27, 0.2), C_SOFT)
			_bx(sb, Vector3(-0.1, 0.46, -0.18), Vector3(0.3, 0.05, 0.012), acc, C_STRIP, 1.0)
		"trash_bag":
			mb_sphere(sb, Vector3(0, 0.2, 0), Vector3(0.26, 0.2, 0.24), Color(0.03, 0.03, 0.035))
			mb_sphere(sb, Vector3(0.22, 0.14, 0.12), Vector3(0.16, 0.13, 0.15), Color(0.04, 0.045, 0.04))
		"bin":
			_cyl(sb, Vector3(0, 0, 0), 0.2, h, Color(0.14, 0.15, 0.16), C_METAL, 0.0, 8)
			_cyl(sb, Vector3(0, h - 0.04, 0), 0.215, 0.06, Color(0.2, 0.2, 0.22), C_METAL, 0.0, 8)
		"pipe_run":
			_bx(sb, Vector3(0, 0, 0), Vector3(w, 0.14, 0.14), Color(0.22, 0.2, 0.2), C_METAL)
			_bx(sb, Vector3(0, 0.15, 0.0), Vector3(w, 0.08, 0.08), _shade(trim, 0.7), C_METAL)
			for i in int(w / 1.3):
				_bx(sb, Vector3(-w * 0.5 + 0.4 + i * 1.3, 0.1, 0), Vector3(0.05, 0.3, 0.2), Color(0.1, 0.1, 0.11), C_METAL)
			_bx(sb, Vector3(_rng.randf_range(-w * 0.3, w * 0.3), 0.0, -0.12), Vector3(0.14, 0.14, 0.05), Color(0.6, 0.12, 0.1), C_METAL)
		_:
			if InteriorKit.is_kit(kind):
				var ok := InteriorKit.append(sb, kind, size, acc, tint, ph, -h * 0.5 if flags_of(kind) & F_WALL != 0 else 0.0)
				if ok and kind in ["kit_teleporter", "kit_pad", "kit_pod", "kit_capsule"]:
					_halo(gb, Vector3(0, h * 0.5, 0.0), w * 1.3, h * 1.1, acc, 0.35)
				if not ok:
					_bx(sb, Vector3(0, h * 0.5, 0), size, tint, C_METAL)
			else:
				_bx(sb, Vector3(0, h * 0.5, 0), size, tint, C_METAL)
	var xf := Transform3D(Basis(Vector3.UP, float(p["yaw"])), p["pos"])
	sb.xform_from(s0, xf)
	gb.xform_from(g0, xf)


static func mb_sphere(mb: RefCounted, c: Vector3, radii: Vector3, col: Color) -> void:
	mb.uv = Vector2(C_SOFT, 0.0)
	mb.sphere(c, radii, 7, 4, Color(col.r, col.g, col.b, 0.0))
