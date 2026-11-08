class_name WeaponIcons
extends RefCounted
## Flat vector silhouettes of the weapons for the HUD plate and the weapon wheel: each icon is a list of rectangles [x, y, w, h] in 0..1 icon space (batches into the HUD canvas, no textures,
## no polygons). Every id of WeaponDefs.IDS has one (the test checks it).

const ICONS := {
	&"carbine": [[0.04, 0.38, 0.12, 0.24], [0.16, 0.40, 0.46, 0.18], [0.62, 0.44, 0.34, 0.08], [0.38, 0.58, 0.08, 0.28], [0.22, 0.58, 0.07, 0.22]],
	&"scatter": [[0.04, 0.36, 0.14, 0.26], [0.18, 0.40, 0.40, 0.16], [0.58, 0.40, 0.38, 0.07], [0.58, 0.50, 0.34, 0.07], [0.30, 0.56, 0.12, 0.10]],
	&"lance": [[0.04, 0.42, 0.10, 0.18], [0.14, 0.44, 0.30, 0.14], [0.44, 0.48, 0.52, 0.05], [0.24, 0.30, 0.20, 0.08], [0.30, 0.58, 0.07, 0.2]],
	&"grenade": [[0.30, 0.28, 0.40, 0.44], [0.42, 0.18, 0.16, 0.10], [0.36, 0.36, 0.28, 0.08]],
	&"burst": [[0.14, 0.38, 0.44, 0.16], [0.58, 0.40, 0.30, 0.09], [0.22, 0.54, 0.12, 0.30], [0.36, 0.30, 0.08, 0.08], [0.46, 0.30, 0.08, 0.08]],
	&"rail": [[0.04, 0.40, 0.18, 0.20], [0.22, 0.42, 0.30, 0.14], [0.52, 0.46, 0.44, 0.06], [0.52, 0.38, 0.40, 0.04], [0.52, 0.56, 0.40, 0.04], [0.30, 0.56, 0.07, 0.22]],
	&"flux": [[0.10, 0.38, 0.50, 0.18], [0.60, 0.42, 0.28, 0.08], [0.30, 0.56, 0.10, 0.34], [0.18, 0.56, 0.07, 0.18], [0.04, 0.40, 0.06, 0.14]],
	&"gravity": [[0.08, 0.34, 0.50, 0.28], [0.58, 0.30, 0.30, 0.36], [0.88, 0.26, 0.08, 0.44], [0.26, 0.62, 0.10, 0.22]],
	&"minigun": [[0.04, 0.36, 0.22, 0.28], [0.26, 0.30, 0.28, 0.40], [0.54, 0.32, 0.42, 0.08], [0.54, 0.44, 0.42, 0.08], [0.54, 0.56, 0.42, 0.08], [0.30, 0.70, 0.08, 0.20]],
	&"akimbo": [[0.04, 0.22, 0.36, 0.12], [0.10, 0.34, 0.10, 0.26], [0.60, 0.58, 0.36, 0.12], [0.80, 0.70, 0.10, 0.26], [0.04, 0.22, 0.04, 0.12]],
	&"arc": [[0.06, 0.40, 0.40, 0.18], [0.46, 0.44, 0.20, 0.10], [0.66, 0.34, 0.06, 0.16], [0.72, 0.50, 0.06, 0.16], [0.78, 0.30, 0.06, 0.16], [0.84, 0.46, 0.06, 0.16], [0.22, 0.58, 0.08, 0.24]],
	&"revolver": [[0.10, 0.34, 0.50, 0.12], [0.60, 0.34, 0.34, 0.08], [0.30, 0.46, 0.20, 0.20], [0.14, 0.46, 0.10, 0.34], [0.04, 0.30, 0.08, 0.20]],
	&"whip": [[0.04, 0.70, 0.16, 0.12], [0.20, 0.60, 0.20, 0.06], [0.40, 0.46, 0.20, 0.06], [0.60, 0.30, 0.18, 0.06], [0.78, 0.16, 0.18, 0.06]],
	&"blade": [[0.06, 0.74, 0.12, 0.10], [0.14, 0.62, 0.10, 0.08], [0.20, 0.54, 0.16, 0.08], [0.34, 0.44, 0.20, 0.08], [0.52, 0.34, 0.20, 0.08], [0.70, 0.22, 0.24, 0.08]],
}


static var _tex := {}
const TEX_W := 96
const TEX_H := 48


static func has_icon(id: StringName) -> bool:
	return ICONS.has(id) or WeaponDefs.DEFS.has(id)


## The side-view silhouette of a weapon's own mesh (the one in the hero's hand) as a white-on-clear texture, 2:1, muzzle on the right. Built once and cached, so the HUD, the wheel and the
## loadout show exactly the shape the hero holds.
static func texture(id: StringName) -> Texture2D:
	if _tex.has(id):
		return _tex[id]
	var m := WeaponModels.mesh(id)
	if m == null:
		return null
	var f := m.get_faces()
	var bb := m.get_aabb()
	var w := maxf(bb.size.z, 0.01)
	var h := maxf(bb.size.y, 0.01)
	var k := minf(float(TEX_W - 6) / w, float(TEX_H - 6) / h)
	var ox := (float(TEX_W) - w * k) * 0.5
	var oy := (float(TEX_H) - h * k) * 0.5
	var img := Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)
	var i := 0
	while i + 2 < f.size():
		var p: Array[Vector2] = []
		for j in 3:
			var v := f[i + j]
			p.append(Vector2(ox + (bb.end.z - v.z) * k, oy + (bb.end.y - v.y) * k))      # muzzle (z 0) on the right, up is up
		i += 3
		var x0 := maxi(0, int(floorf(minf(p[0].x, minf(p[1].x, p[2].x)))))
		var x1 := mini(TEX_W - 1, int(ceilf(maxf(p[0].x, maxf(p[1].x, p[2].x)))))
		var y0 := maxi(0, int(floorf(minf(p[0].y, minf(p[1].y, p[2].y)))))
		var y1 := mini(TEX_H - 1, int(ceilf(maxf(p[0].y, maxf(p[1].y, p[2].y)))))
		var den := (p[1].y - p[2].y) * (p[0].x - p[2].x) + (p[2].x - p[1].x) * (p[0].y - p[2].y)
		if absf(den) < 0.0001:                                      # an edge-on face: a one pixel line
			for xx in range(x0, x1 + 1):
				for yy in range(y0, y1 + 1):
					img.set_pixel(xx, yy, Color.WHITE)
			continue
		for yy in range(y0, y1 + 1):
			for xx in range(x0, x1 + 1):
				var q := Vector2(float(xx) + 0.5, float(yy) + 0.5)
				var a := ((p[1].y - p[2].y) * (q.x - p[2].x) + (p[2].x - p[1].x) * (q.y - p[2].y)) / den
				var b := ((p[2].y - p[0].y) * (q.x - p[2].x) + (p[0].x - p[2].x) * (q.y - p[2].y)) / den
				if a >= -0.05 and b >= -0.05 and a + b <= 1.05:
					img.set_pixel(xx, yy, Color.WHITE)
	var t := ImageTexture.create_from_image(img)
	_tex[id] = t
	return t


## Draw the picture of a weapon fitted into `r` (a uniform scale, centred) on a CanvasItem: its rendered picture (ItemIcons, opacity from `col`), else the flat silhouette of its mesh in `col`.
static func draw(c: CanvasItem, id: StringName, r: Rect2, col: Color) -> void:
	var pic := ItemIcons.weapon(id)
	if pic != null:
		ItemIcons.draw_tex(c, pic, r, Color(1, 1, 1, col.a))
		return
	draw_flat(c, id, r, col)


## The flat white-on-clear silhouette in `col` (the fallback of `draw`, and what the first versions drew).
static func draw_flat(c: CanvasItem, id: StringName, r: Rect2, col: Color) -> void:
	var sz := minf(r.size.x, r.size.y * 2.0)
	var box := Rect2(r.get_center() - Vector2(sz, sz * 0.5) * 0.5, Vector2(sz, sz * 0.5))
	var tex := texture(id)
	if tex != null:
		c.draw_texture_rect(tex, box, false, col)
		return
	if not ICONS.has(id):
		return
	for q: Array in ICONS[id]:
		c.draw_rect(Rect2(box.position + Vector2(float(q[0]) * box.size.x, float(q[1]) * box.size.y * 2.0 - box.size.y * 0.5), Vector2(float(q[2]) * box.size.x, float(q[3]) * box.size.y * 2.0)), col)
