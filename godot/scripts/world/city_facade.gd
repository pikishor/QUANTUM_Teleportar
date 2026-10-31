extends RefCounted
## Facade kit: real depth on the street-facing walls that the facade shader can only paint. ONE MultiMesh family ("FacadeKit", one draw call) whose mesh holds
## four modules (balcony with rail, wall air-conditioner with a drip pipe, drain pipe with a conduit, projecting cornice band). Each instance shows ONE module:
## the prop shader collapses the others in the vertex stage (UV.x = -(1 + module), INSTANCE_CUSTOM.w = (module + 0.5) / 4), so balconies, units, pipes and
## bands can sit at any height, flip and scale per instance without a draw call each. Mesh: +Z is outward from the wall, origin on the wall plane at the
## module's base (y = 0), see city_roofs.gd wall_point(). Placement is deterministic (own RNG) and runs after the roof builder, so no other family moves.

const MB := preload("res://scripts/world/mesh_builder.gd")
const Roofs := preload("res://scripts/world/city_roofs.gd")
const BM := preload("res://scripts/world/building_meshes.gd")

const RADIUS := 62.0
const GROUND_H := 5.0
const FLOOR_H := 3.5
const MAX_Y := 38.0

const M_BALCONY := 0
const M_AC := 1
const M_PIPE := 2
const M_CORNICE := 3


static func kit_mesh() -> ArrayMesh:
	var b := MB.new()
	var concrete := Color(0.15, 0.15, 0.155, 0.0)
	var iron := Color(0.045, 0.05, 0.055, 0.0)
	# --- balcony: slab, rail, posts (3 m wide, 1.1 m deep) ---
	b.uv = Vector2(-1.0 - M_BALCONY, 0.0)
	b.uv2 = Vector2(0.0, 0.85)
	b.box(Vector3(0.0, 0.0, 0.55), Vector3(3.0, 0.14, 1.1), concrete)
	b.uv2 = Vector2(0.8, 0.5)
	b.box(Vector3(0.0, 0.58, 1.05), Vector3(3.0, 1.0, 0.035), iron, false, Vector2(0.8, 0.5), MB.F_BOTTOM)     # railing as one solid screen
	b.box(Vector3(0.0, 1.1, 1.04), Vector3(3.04, 0.05, 0.07), iron, false)
	# --- wall AC unit on a bracket, drip pipe ---
	b.uv = Vector2(-1.0 - M_AC, 0.0)
	b.uv2 = Vector2(0.5, 0.5)
	b.box(Vector3(0.0, 0.3, 0.24), Vector3(0.92, 0.6, 0.46), Color(0.20, 0.205, 0.21, 0.0), false)
	b.box(Vector3(0.0, 0.3, 0.475), Vector3(0.72, 0.42, 0.03), Color(0.02, 0.02, 0.022, 0.0), false, Vector2(0.5, 0.5), MB.F_PX | MB.F_NX | MB.F_TOP | MB.F_NZ | MB.F_BOTTOM)
	b.strut(Vector3(0.4, 0.1, 0.2), Vector3(0.62, -1.3, 0.1), 0.035, Color(0.06, 0.055, 0.05, 0.0), false)
	# --- drain pipe (scaled in y by the instance) with a horizontal conduit ---
	b.uv = Vector2(-1.0 - M_PIPE, 0.0)
	b.uv2 = Vector2(0.6, 0.55)
	b.cylinder(Vector3(0.0, 0.0, 0.09), 0.055, 1.0, 6, Color(0.09, 0.085, 0.08, 0.0), -1.0, false)
	b.box(Vector3(0.9, 0.97, 0.05), Vector3(1.8, 0.05, 0.05), Color(0.06, 0.06, 0.065, 0.0), false)
	# --- cornice: a projecting band with a drip lip (4 m, scaled in x by the instance) ---
	b.uv = Vector2(-1.0 - M_CORNICE, 0.0)
	b.uv2 = Vector2(0.0, 0.85)
	b.box(Vector3(0.0, 0.1, 0.17), Vector3(4.0, 0.2, 0.34), Color(0.17, 0.168, 0.165, 0.0), false)
	b.box(Vector3(0.0, 0.25, 0.25), Vector3(4.0, 0.07, 0.5), Color(0.12, 0.12, 0.125, 0.0), false)
	return b.build(null, true, true)


static func _inst(props_rng: RandomNumberGenerator, lot: CityLayout.Lot, face: int, u: float, y: float, module: int, scale := Vector3.ONE) -> Array:
	var wp: Array = Roofs.wall_point(lot, face, u)
	var p2: Vector2 = wp[0]
	var xf := Transform3D(Basis(Vector3.UP, float(wp[1])) * Basis.from_scale(scale), Vector3(lot.cx + p2.x, y, lot.cz + p2.y))
	return [xf, Color(props_rng.randf(), 0.0, 0.0, (float(module) + 0.5) / 4.0)]


func build(props, layout: CityLayout, buildings: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var items: Array = []
	for b in buildings:
		var lot: CityLayout.Lot = b.lot
		if lot.h < 10.0:
			continue
		var bx := -CityLayout.HALF + (lot.block_i + 0.5) * CityLayout.PITCH
		var bz := -CityLayout.HALF + (lot.block_j + 0.5) * CityLayout.PITCH
		var sx := 1 if lot.cx > bx else -1
		var sz := 1 if lot.cz > bz else -1
		var faces: Array[int] = [0 if sx > 0 else 1, 2 if sz > 0 else 3]
		var top := minf(lot.h - 1.5, MAX_Y)
		var nfl := int(floor((top - GROUND_H) / FLOOR_H))
		var curtain: bool = b.style == 2 or b.style == 3                      # glass walls and fins carry no balconies
		for face in faces:
			var fw := Roofs.wall_width(lot, face)
			var nb := maxi(2, int(floor(fw / 4.8 + 0.5)))
			var bw := fw / float(nb)
			# a continuous cornice band over the shop floor on about two faces in three
			if rng.randf() < 0.55:
				for k in nb:
					items.append(_inst(rng, lot, face, (float(k) + 0.5) * bw, GROUND_H - 0.1, M_CORNICE, Vector3(bw / 4.0 + 0.002, 1.0, 1.0)))
			if nfl >= 2 and not curtain:
				# balcony columns: one or two bays, every second floor, from a random start floor
				var cols := 1 if rng.randf() < 0.6 else 0
				for c in cols:
					var k := rng.randi_range(0, nb - 1)
					var f0 := rng.randi_range(1, 2)
					var f := f0
					while f <= nfl:
						if rng.randf() < 0.7:
							items.append(_inst(rng, lot, face, (float(k) + 0.5) * bw, GROUND_H + float(f - 1) * FLOOR_H + 0.35, M_BALCONY,
									Vector3(bw * 0.72 / 3.0, 1.0, 1.0)))
						f += 2
				# window air-conditioners, scattered
				var acs := rng.randi_range(0, nb)
				for a in acs:
					var k2 := rng.randi_range(0, nb - 1)
					var f2 := rng.randi_range(1, maxi(1, nfl))
					var off := rng.randf_range(-bw * 0.3, bw * 0.3)
					items.append(_inst(rng, lot, face, (float(k2) + 0.5) * bw + off, GROUND_H + float(f2 - 1) * FLOOR_H + 0.9, M_AC))
			# drain pipes at the wall ends and, on tall faces, a conduit between
			if rng.randf() < 0.7:
				var u := rng.randf_range(0.3, 0.6) if rng.randf() < 0.5 else fw - rng.randf_range(0.3, 0.6)
				items.append(_inst(rng, lot, face, u, 0.0, M_PIPE, Vector3(1.0, minf(lot.h - 1.4, MAX_Y), 1.0)))
	props.add_family("FacadeKit", kit_mesh(), items, false, false, 0, RADIUS)
