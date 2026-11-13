class_name SettlementSpecials
extends RefCounted
## The buildings and structures of the towns that are not houses (wave 112): church, barn, silo, windmill, water tower, lattice mast, chimney stack, tower crane, tank farm, works shed, petrol station,
## hotel with a roof helipad, lighthouse, container houses, solar rows, a pier, boats, a fish market, a lodge hall, a chapel. Each builder returns
##   {mesh, far, size (collider box), door (local door base, optional), anchor ({kind, name, height, radius}, optional), rotors ([{mesh, pos, axis, speed}], optional), cyl (collider cylinder radius, optional)}
## in the part's own frame (origin on the ground at the middle of the footprint, front -Z). They use the same material codes and the same parametric parts as the houses.

const P := preload("res://scripts/settlements/settlement_parts.gd")
const SM := preload("res://scripts/settlements/settlement_mesh.gd")


static func _res(m: SettlementMesh, far: SettlementMesh, size: Vector3) -> Dictionary:
	return {"mesh": m, "far": far, "size": size}


static func _far_box(w: float, h: float, d: float, wall: Color, roof: Color, gable := true) -> SettlementMesh:
	var f := SettlementMesh.new()
	f.box(Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, d), wall, SM.PAINT, 32 | 4, 1.0, 0.8)
	if gable:
		P.gable_roof(f, w, d, h, 0.45, 0.3, 0.2, roof, SM.PAINT, wall, SM.PAINT, false)
	else:
		f.box(Vector3(0.0, h + 0.06, 0.0), Vector3(w + 0.1, 0.12, d + 0.1), roof, SM.PAINT, 32, 1.0, 1.0)
	return f


## A church: nave, tower with a belfry and a pointed spire in front, tall windows.
static func church(s: Dictionary) -> Dictionary:
	var m := SettlementMesh.new()
	var wall: Color = s.get("wall", Color(0.88, 0.86, 0.8))
	var roof: Color = s.get("roof", Color(0.3, 0.3, 0.34))
	var wcode: int = s.get("wall_code", SM.PAINT)
	var nw := 8.0
	var nd := 15.0
	var nh := 6.0
	var tw := 4.6
	var th := 13.0
	var nz := 1.0                                                          # the nave starts behind the tower
	m.box(Vector3(0.0, nh * 0.5, nz + nd * 0.5 - 3.0), Vector3(nw, nh, nd), wall, wcode, 32 | 4, 1.0, 0.6)
	var cz := nz + nd * 0.5 - 3.0
	var t := SettlementMesh.new()
	P.gable_roof(t, nw, nd, nh, 0.78, 0.5, 0.3, roof, SM.SHINGLE, wall, wcode)
	m.append(t, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, cz)))
	# tower at the front
	var tz := -nd * 0.5 + nz - 3.0 + 1.0 - tw * 0.5 + 0.0
	tz = cz - nd * 0.5 - tw * 0.5 + 0.4
	m.box(Vector3(0.0, th * 0.5, tz), Vector3(tw, th, tw), wall, wcode, 32 | 4, 1.0, 0.6)
	m.box(Vector3(0.0, 0.3, tz), Vector3(tw + 0.2, 0.6, tw + 0.2), Color(0.5, 0.47, 0.43), SM.STONE, 32 | 4, 0.95, 0.7)
	# belfry openings and a clock
	for k in 4:
		var a := float(k) * PI * 0.5
		var nrm := Vector3(sin(a), 0.0, -cos(a))
		var c := Vector3(0.0, th - 2.0, tz) + nrm * (tw * 0.5 + 0.03)
		P.window(m, c, nrm, 1.3, 2.4, Color(0.3, 0.3, 0.32), 0.0)
	P.window(m, Vector3(0.0, th - 5.0, tz - tw * 0.5 - 0.03), Vector3(0, 0, -1), 1.0, 1.0, Color(0.9, 0.9, 0.85), 0.0)
	m.cone(Vector3(0.0, th, tz), tw * 0.72, 7.5, 4, roof, SM.SHINGLE, 1.0)
	m.box(Vector3(0.0, th + 7.5 + 0.7, tz), Vector3(0.1, 1.6, 0.1), Color(0.8, 0.7, 0.3), SM.METAL, 32, 1.0, 1.0)
	m.box(Vector3(0.0, th + 7.5 + 1.0, tz), Vector3(0.7, 0.1, 0.1), Color(0.8, 0.7, 0.3), SM.METAL, 32, 1.0, 1.0)
	# big front door and tall windows
	P.door(m, Vector3(0.0, 0.0, tz - tw * 0.5), Vector3(0, 0, -1), 1.6, 2.7, Color(0.28, 0.17, 0.1), Color(0.8, 0.78, 0.72))
	for i in 3:
		var zz := cz - nd * 0.5 + 3.0 + float(i) * 4.0
		P.window(m, Vector3(-nw * 0.5 - 0.03, 3.1, zz), Vector3(-1, 0, 0), 1.0, 2.6, Color(0.35, 0.3, 0.28), 1.0)
		P.window(m, Vector3(nw * 0.5 + 0.03, 3.1, zz), Vector3(1, 0, 0), 1.0, 2.6, Color(0.35, 0.3, 0.28), 1.0)
	var far := SettlementMesh.new()
	far.append(_far_box(nw, nh, nd, wall, roof), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, cz)))
	far.box(Vector3(0.0, th * 0.5, tz), Vector3(tw, th, tw), wall, SM.PAINT, 32 | 4, 1.0, 0.8)
	far.cone(Vector3(0.0, th, tz), tw * 0.72, 7.5, 4, roof, SM.PAINT, 1.0)
	var res := _res(m, far, Vector3(nw, nh + 3.0, nd))
	res["extra_boxes"] = [{"pos": Vector3(0.0, th * 0.5, tz), "size": Vector3(tw, th, tw)}]
	res["size_pos"] = Vector3(0.0, 0.0, cz)
	res["door"] = Vector3(0.0, 0.0, tz - tw * 0.5)
	res["anchor"] = {"kind": &"church_tower", "name": "CHURCH TOWER", "height": th + 7.8, "radius": 0.9, "at": Vector3(0.0, 0.0, tz)}
	return res


## A barn: gambrel roof, big doors, a hayloft door.
static func barn(s: Dictionary) -> Dictionary:
	var m := SettlementMesh.new()
	var wall: Color = s.get("wall", Color(0.55, 0.14, 0.1))
	var w := 11.0
	var d := 16.0
	var h := 5.2
	m.box(Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, d), wall, SM.SIDING, 32 | 4, 1.0, 0.6)
	var roof_c: Color = s.get("roof", Color(0.42, 0.42, 0.45))
	P.gambrel_roof(m, w, d, h, 2.6, 2.2, 0.5, roof_c, SM.SHEET, wall, SM.SIDING)
	var trim := Color(0.93, 0.92, 0.88)
	# the big door: frame, two leaves, a white X on each
	m.quad(Vector3(2.9, 0.0, -d * 0.5 - 0.04), Vector3(-2.9, 0.0, -d * 0.5 - 0.04), Vector3(-2.9, 4.2, -d * 0.5 - 0.04), Vector3(2.9, 4.2, -d * 0.5 - 0.04), trim, SM.PAINT, 1.0, 0.9, Vector2.ZERO, 0.0, Vector3(0, 0, -1))
	m.quad(Vector3(2.6, 0.0, -d * 0.5 - 0.07), Vector3(-2.6, 0.0, -d * 0.5 - 0.07), Vector3(-2.6, 3.9, -d * 0.5 - 0.07), Vector3(2.6, 3.9, -d * 0.5 - 0.07), wall.darkened(0.2), SM.WOOD, 1.0, 0.8, Vector2.ZERO, 0.0, Vector3(0, 0, -1))
	m.box(Vector3(0.0, 1.95, -d * 0.5 - 0.09), Vector3(0.12, 3.9, 0.06), trim, SM.PAINT, 32, 1.0, 1.0)
	P.window(m, Vector3(0.0, h + 1.9, -d * 0.5 - 0.03), Vector3(0, 0, -1), 1.3, 1.5, trim, 0.0)
	for i in 3:
		P.window(m, Vector3(-w * 0.5 - 0.03, 2.6, -d * 0.5 + 3.0 + float(i) * 5.0), Vector3(-1, 0, 0), 0.9, 0.9, trim, 0.0)
		P.window(m, Vector3(w * 0.5 + 0.03, 2.6, -d * 0.5 + 3.0 + float(i) * 5.0), Vector3(1, 0, 0), 0.9, 0.9, trim, 0.0)
	var far := _far_box(w, h, d, wall, roof_c)
	var res := _res(m, far, Vector3(w, h + 3.0, d))
	res["door"] = Vector3(0.0, 0.0, -d * 0.5)
	return res


## A grain silo (tower with a dome): the farm's tall anchor.
static func silo(s: Dictionary) -> Dictionary:
	var m := SettlementMesh.new()
	var col: Color = s.get("wall", Color(0.62, 0.66, 0.7))
	var r: float = s.get("r", 2.6)
	var h: float = s.get("h", 12.0)
	m.cylinder(Vector3.ZERO, r, h, 14, col, SM.METAL, -1.0, false, 1.0, 0.7)
	m.cone(Vector3(0.0, h, 0.0), r * 1.02, r * 0.55, 14, col.darkened(0.12), SM.METAL, 1.0)
	m.cylinder(Vector3(0.0, 0.0, 0.0), r + 0.12, 0.5, 14, Color(0.5, 0.5, 0.5), SM.CONCRETE, -1.0, false, 1.0, 0.7)
	m.box(Vector3(0.0, h * 0.5, -r - 0.05), Vector3(0.5, h, 0.12), Color(0.35, 0.35, 0.37), SM.METAL, 32, 1.0, 1.0)              # a ladder rail
	var far := SettlementMesh.new()
	far.cylinder(Vector3.ZERO, r, h, 8, col, SM.PAINT, -1.0, false, 1.0, 0.8)
	far.cone(Vector3(0.0, h, 0.0), r * 1.02, r * 0.55, 8, col.darkened(0.12), SM.PAINT, 1.0)
	var res := _res(m, far, Vector3(r * 2.0, h, r * 2.0))
	res["cyl"] = r
	res["anchor"] = {"kind": &"silo", "name": "GRAIN SILO", "height": h + r * 0.55, "radius": r}
	return res


## A windmill: tapered tower, cap and four sails (a rotor that turns).
static func windmill(s: Dictionary) -> Dictionary:
	var m := SettlementMesh.new()
	var wall: Color = s.get("wall", Color(0.9, 0.88, 0.82))
	var h := 12.0
	m.cylinder(Vector3.ZERO, 3.3, h, 8, wall, SM.PAINT, 2.1, false, 1.0, 0.6)
	m.cone(Vector3(0.0, h, 0.0), 2.5, 2.4, 8, Color(0.3, 0.2, 0.16), SM.SHINGLE, 1.0)
	P.door(m, Vector3(0.0, 0.0, -3.3), Vector3(0, 0, -1), 1.1, 2.0, Color(0.3, 0.18, 0.1), Color(0.8, 0.78, 0.72))
	for k in 4:
		var a := TAU * float(k) / 4.0 + 0.4
		P.window(m, Vector3(sin(a) * 2.9, 6.0, cos(a) * 2.9), Vector3(sin(a), 0.0, cos(a)), 0.7, 1.0, Color(0.3, 0.2, 0.15), 0.0)
	var sails := SettlementMesh.new()
	for k in 4:
		var a2 := PI * 0.5 * float(k)
		var dir := Vector3(cos(a2), sin(a2), 0.0)
		var side := Vector3(-sin(a2), cos(a2), 0.0)
		var inner := dir * 1.0
		var outer := dir * 9.5
		sails.quad(inner - side * 0.12, outer - side * 0.12, outer + side * 0.12, inner + side * 0.12, Color(0.45, 0.32, 0.2), SM.WOOD, 1.0, 1.0, Vector2.ZERO, 0.0, Vector3(0, 0, -1))
		sails.quad(inner + side * 0.12, outer + side * 0.12, outer - side * 0.12, inner - side * 0.12, Color(0.45, 0.32, 0.2), SM.WOOD, 1.0, 1.0, Vector2.ZERO, 0.0, Vector3(0, 0, 1))
		var a3 := inner + dir * 1.6 + side * 0.12
		var b3 := outer + side * 0.12
		var c3 := outer + side * 2.0
		var d3 := a3 + side * 1.9
		sails.quad(a3, b3, c3, d3, Color(0.88, 0.85, 0.78), SM.SHEET, 1.0, 1.0, Vector2.ZERO, 0.0, Vector3(0, 0, -1))
		sails.quad(d3, c3, b3, a3, Color(0.88, 0.85, 0.78), SM.SHEET, 1.0, 1.0, Vector2.ZERO, 0.0, Vector3(0, 0, 1))
	var far := SettlementMesh.new()
	far.cylinder(Vector3.ZERO, 3.3, h, 8, wall, SM.PAINT, 2.1, false, 1.0, 0.8)
	far.cone(Vector3(0.0, h, 0.0), 2.5, 2.4, 8, Color(0.3, 0.2, 0.16), SM.PAINT, 1.0)
	var res := _res(m, far, Vector3(6.6, h, 6.6))
	res["cyl"] = 3.3
	res["rotors"] = [{"mesh": sails, "pos": Vector3(0.0, h - 1.0, -3.0), "axis": Vector3(0, 0, 1), "speed": 0.45}]
	res["anchor"] = {"kind": &"windmill", "name": "WINDMILL", "height": h + 2.4, "radius": 2.2}
	return res


## A water tower on four legs with bracing.
static func water_tower(s: Dictionary) -> Dictionary:
	var m := SettlementMesh.new()
	var col: Color = s.get("wall", Color(0.78, 0.8, 0.82))
	var legs := Color(0.3, 0.32, 0.34)
	var lh := 11.0
	var hw := 2.2
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			m.tube(Vector3(float(sx) * hw, 0.0, float(sz) * hw), Vector3(float(sx) * hw * 0.82, lh, float(sz) * hw * 0.82), 0.2, 0.17, 6, legs, SM.METAL, 1.0, 0.7)
	for y in [3.6, 7.2, lh - 0.2]:
		var k: float = 1.0 - 0.18 * (float(y) / lh)
		m.box(Vector3(0.0, y, -hw * k), Vector3(hw * 2.0 * k, 0.14, 0.14), legs, SM.METAL, 32, 1.0, 1.0)
		m.box(Vector3(0.0, y, hw * k), Vector3(hw * 2.0 * k, 0.14, 0.14), legs, SM.METAL, 32, 1.0, 1.0)
		m.box(Vector3(-hw * k, y, 0.0), Vector3(0.14, 0.14, hw * 2.0 * k), legs, SM.METAL, 32, 1.0, 1.0)
		m.box(Vector3(hw * k, y, 0.0), Vector3(0.14, 0.14, hw * 2.0 * k), legs, SM.METAL, 32, 1.0, 1.0)
	m.cylinder(Vector3(0.0, lh, 0.0), 3.0, 3.6, 14, col, SM.METAL, -1.0, false, 1.0, 1.0)
	m.cone(Vector3(0.0, lh + 3.6, 0.0), 3.1, 1.3, 14, col.darkened(0.2), SM.METAL, 1.0)
	m.cylinder(Vector3(0.0, lh - 0.3, 0.0), 3.05, 0.3, 14, legs, SM.METAL, -1.0, false, 0.8, 1.0)
	var far := SettlementMesh.new()
	far.cylinder(Vector3(0.0, lh, 0.0), 3.0, 3.6, 8, col, SM.PAINT, -1.0, false, 1.0, 1.0)
	far.cone(Vector3(0.0, lh + 3.6, 0.0), 3.1, 1.3, 8, col.darkened(0.2), SM.PAINT, 1.0)
	far.box(Vector3(0.0, lh * 0.5, 0.0), Vector3(3.2, lh, 3.2), legs, SM.PAINT, 32 | 4, 0.6, 1.0)
	var res := _res(m, far, Vector3(hw * 2.0 + 0.6, lh + 5.0, hw * 2.0 + 0.6))
	res["anchor"] = {"kind": &"water_tower", "name": "WATER TOWER", "height": lh + 4.9, "radius": 3.0}
	return res


## A lattice radio mast: three legs in alternate red and white sections, rings, a lamp on top and a hut at the foot.
static func mast(s: Dictionary) -> Dictionary:
	var m := SettlementMesh.new()
	var h: float = s.get("h", 46.0)
	var base_r := 2.1
	var top_r := 0.7
	var sections := int(h / 4.0)
	var red := Color(0.8, 0.12, 0.1)
	var white := Color(0.9, 0.9, 0.88)
	for leg in 3:
		var a := TAU * float(leg) / 3.0
		for k in sections:
			var f0 := float(k) / float(sections)
			var f1 := float(k + 1) / float(sections)
			var r0 := lerpf(base_r, top_r, f0)
			var r1 := lerpf(base_r, top_r, f1)
			var p0 := Vector3(cos(a) * r0, h * f0, sin(a) * r0)
			var p1 := Vector3(cos(a) * r1, h * f1, sin(a) * r1)
			m.tube(p0, p1, 0.07, 0.065, 5, red if k % 2 == 0 else white, SM.METAL, 1.0, 0.8 if k == 0 else 1.0)
	for k in range(1, sections + 1):
		var f := float(k) / float(sections)
		var r := lerpf(base_r, top_r, f)
		for leg in 3:
			var a0 := TAU * float(leg) / 3.0
			var a1 := TAU * float(leg + 1) / 3.0
			m.tube(Vector3(cos(a0) * r, h * f, sin(a0) * r), Vector3(cos(a1) * r, h * f, sin(a1) * r), 0.045, 0.045, 4, Color(0.6, 0.6, 0.62), SM.METAL)
			if k < sections:
				var f2 := float(k + 1) / float(sections)
				var r2 := lerpf(base_r, top_r, f2)
				m.tube(Vector3(cos(a0) * r, h * f, sin(a0) * r), Vector3(cos(a1) * r2, h * f2, sin(a1) * r2), 0.035, 0.035, 4, Color(0.6, 0.6, 0.62), SM.METAL)
	m.box(Vector3(0.0, h + 0.5, 0.0), Vector3(0.14, 1.0, 0.14), Color(0.8, 0.8, 0.82), SM.METAL, 32, 1.0, 1.0)
	m.box(Vector3(0.0, h + 1.1, 0.0), Vector3(0.3, 0.25, 0.3), Color(1.0, 0.2, 0.15), SM.GLOW, 4, 1.0, 1.0)
	m.box(Vector3(3.6, 1.2, 0.0), Vector3(2.4, 2.4, 3.0), Color(0.6, 0.62, 0.6), SM.PAINT, 32 | 4, 1.0, 0.7)
	m.box(Vector3(3.6, 2.5, 0.0), Vector3(2.6, 0.2, 3.2), Color(0.4, 0.4, 0.42), SM.CONCRETE, 32, 1.0, 1.0)
	var far := SettlementMesh.new()
	for leg in 3:
		var a := TAU * float(leg) / 3.0
		far.tube(Vector3(cos(a) * base_r, 0.0, sin(a) * base_r), Vector3(cos(a) * top_r, h, sin(a) * top_r), 0.12, 0.08, 4, red, SM.PAINT)
	var res := _res(m, far, Vector3(4.6, 3.0, 4.6))
	res["cyl"] = 2.4
	res["anchor"] = {"kind": &"mast", "name": "RADIO MAST", "height": h + 1.2, "radius": 0.9}
	return res


## A tall brick chimney stack with white bands.
static func stack(s: Dictionary) -> Dictionary:
	var m := SettlementMesh.new()
	var h: float = s.get("h", 34.0)
	var brick: Color = s.get("wall", Color(0.55, 0.28, 0.2))
	m.cylinder(Vector3.ZERO, 2.2, h, 12, brick, SM.BRICK, 1.4, false, 1.0, 0.7)
	for f in [0.72, 0.84, 0.94]:
		var r: float = lerpf(2.2, 1.4, float(f))
		m.cylinder(Vector3(0.0, h * float(f), 0.0), r + 0.05, 1.0, 12, Color(0.92, 0.9, 0.86), SM.PAINT, -1.0, false, 1.0, 1.0)
	m.cylinder(Vector3(0.0, h, 0.0), 1.55, 0.4, 12, Color(0.3, 0.3, 0.32), SM.METAL, 1.2, true, 1.0, 1.0)
	m.box(Vector3(0.0, 0.4, 0.0), Vector3(5.4, 0.8, 5.4), Color(0.5, 0.48, 0.45), SM.CONCRETE, 32 | 4, 1.0, 0.8)
	var far := SettlementMesh.new()
	far.cylinder(Vector3.ZERO, 2.2, h, 8, brick, SM.PAINT, 1.4, true, 1.0, 0.8)
	var res := _res(m, far, Vector3(4.4, h, 4.4))
	res["cyl"] = 2.4
	res["anchor"] = {"kind": &"chimney", "name": "FOUNDRY STACK", "height": h + 0.4, "radius": 1.4}
	return res


## A tower crane: lattice mast, jib with trolley, counter jib, cab (works yard, quay).
static func crane(s: Dictionary) -> Dictionary:
	var m := SettlementMesh.new()
	var h: float = s.get("h", 34.0)
	var yellow: Color = s.get("wall", Color(0.95, 0.75, 0.1))
	var grey := Color(0.4, 0.4, 0.42)
	for sx in [-0.7, 0.7]:
		for sz in [-0.7, 0.7]:
			m.box(Vector3(float(sx), h * 0.5, float(sz)), Vector3(0.18, h, 0.18), yellow, SM.METAL, 32, 1.0, 0.8)
	var k := 1.4
	while k < h:
		m.box(Vector3(0.0, k, -0.7), Vector3(1.5, 0.1, 0.1), yellow, SM.METAL, 32, 1.0, 1.0)
		m.box(Vector3(0.0, k, 0.7), Vector3(1.5, 0.1, 0.1), yellow, SM.METAL, 32, 1.0, 1.0)
		m.box(Vector3(-0.7, k, 0.0), Vector3(0.1, 0.1, 1.5), yellow, SM.METAL, 32, 1.0, 1.0)
		m.box(Vector3(0.7, k, 0.0), Vector3(0.1, 0.1, 1.5), yellow, SM.METAL, 32, 1.0, 1.0)
		k += 2.2
	var arm := SettlementMesh.new()
	arm.box(Vector3(0.0, 0.9, -13.0), Vector3(0.9, 0.5, 26.0), yellow, SM.METAL, 32, 1.0, 1.0)
	arm.box(Vector3(0.0, 1.6, -13.0), Vector3(0.14, 0.14, 26.0), yellow, SM.METAL, 32, 1.0, 1.0)
	arm.box(Vector3(0.0, 0.9, 5.0), Vector3(0.9, 0.5, 9.0), yellow, SM.METAL, 32, 1.0, 1.0)
	arm.box(Vector3(0.0, 0.5, 8.4), Vector3(2.2, 1.6, 2.2), grey, SM.CONCRETE, 32, 1.0, 1.0)
	arm.box(Vector3(0.0, 2.6, 0.0), Vector3(0.12, 3.4, 0.12), yellow, SM.METAL, 32, 1.0, 1.0)
	arm.box(Vector3(0.0, 0.9, -19.0), Vector3(0.6, 0.5, 0.8), grey, SM.METAL, 32, 1.0, 1.0)
	arm.box(Vector3(0.0, -2.0, -19.0), Vector3(0.05, 4.8, 0.05), Color(0.2, 0.2, 0.2), SM.METAL, 32, 1.0, 1.0)
	arm.box(Vector3(0.0, -4.6, -19.0), Vector3(0.7, 0.5, 0.7), Color(0.8, 0.2, 0.1), SM.METAL, 32, 1.0, 1.0)
	arm.box(Vector3(1.3, -0.1, -0.8), Vector3(1.4, 1.6, 1.6), Color(0.9, 0.9, 0.9), SM.PAINT, 32, 1.0, 1.0)
	m.box(Vector3(0.0, 0.5, 0.0), Vector3(3.4, 1.0, 3.4), grey, SM.CONCRETE, 32 | 4, 1.0, 0.8)
	var far := SettlementMesh.new()
	far.box(Vector3(0.0, h * 0.5, 0.0), Vector3(1.6, h, 1.6), yellow, SM.PAINT, 32 | 4, 1.0, 1.0)
	far.box(Vector3(0.0, h + 0.9, -9.0), Vector3(0.9, 0.5, 36.0), yellow, SM.PAINT, 32, 1.0, 1.0)
	var res := _res(m, far, Vector3(3.4, h, 3.4))
	res["cyl"] = 1.9
	res["rotors"] = [{"mesh": arm, "pos": Vector3(0.0, h, 0.0), "axis": Vector3(0, 1, 0), "speed": 0.06}]
	res["anchor"] = {"kind": &"crane", "name": "TOWER CRANE", "height": h + 2.0, "radius": 1.4}
	return res


## A round storage tank with a rim and a ladder.
static func tank(s: Dictionary) -> Dictionary:
	var m := SettlementMesh.new()
	var col: Color = s.get("wall", Color(0.88, 0.88, 0.86))
	var r: float = s.get("r", 5.5)
	var h: float = s.get("h", 8.0)
	m.cylinder(Vector3.ZERO, r, h, 16, col, SM.METAL, -1.0, true, 1.0, 0.65)
	m.cylinder(Vector3(0.0, h, 0.0), r + 0.1, 0.25, 16, Color(0.5, 0.5, 0.52), SM.METAL, -1.0, true, 1.0, 1.0)
	m.box(Vector3(0.0, h * 0.5, -r - 0.05), Vector3(0.5, h, 0.1), Color(0.3, 0.3, 0.32), SM.METAL, 32, 1.0, 1.0)
	var far := SettlementMesh.new()
	far.cylinder(Vector3.ZERO, r, h, 8, col, SM.PAINT, -1.0, true, 1.0, 0.8)
	var res := _res(m, far, Vector3(r * 2.0, h, r * 2.0))
	res["cyl"] = r
	return res


## A works hall: long shed with a ribbed roof, a loading door and high windows.
static func shed(s: Dictionary) -> Dictionary:
	var m := SettlementMesh.new()
	var w: float = s.get("w", 22.0)
	var d: float = s.get("d", 16.0)
	var h: float = s.get("h", 7.0)
	var wall: Color = s.get("wall", Color(0.6, 0.62, 0.62))
	var roof: Color = s.get("roof", Color(0.5, 0.52, 0.54))
	m.box(Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, d), wall, SM.SHEET, 32 | 4, 1.0, 0.6)
	var t := SettlementMesh.new()
	P.gable_roof(t, d, w, h, 0.22, 0.4, 0.4, roof, SM.SHEET, wall, SM.SHEET)
	m.append(t, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO))
	m.quad(Vector3(2.8, 0.0, -d * 0.5 - 0.05), Vector3(-2.8, 0.0, -d * 0.5 - 0.05), Vector3(-2.8, 4.6, -d * 0.5 - 0.05), Vector3(2.8, 4.6, -d * 0.5 - 0.05), Color(0.75, 0.55, 0.12), SM.SHEET, 1.0, 0.8, Vector2.ZERO, 0.0, Vector3(0, 0, -1))
	var nwin := int(w / 3.5)
	for i in nwin:
		P.window(m, Vector3(-w * 0.5 + (float(i) + 0.5) * w / float(nwin), h - 1.3, -d * 0.5 - 0.03), Vector3(0, 0, -1), 1.8, 0.9, Color(0.35, 0.36, 0.38), 0.5)
	P.door(m, Vector3(w * 0.5 - 2.0, 0.0, -d * 0.5), Vector3(0, 0, -1), 1.0, 2.1, Color(0.25, 0.27, 0.3), Color(0.8, 0.8, 0.78))
	var far := _far_box(w, h, d, wall, roof, true)
	var res := _res(m, far, Vector3(w, h + 1.5, d))
	res["door"] = Vector3(w * 0.5 - 2.0, 0.0, -d * 0.5)
	return res


## A petrol station: canopy on four posts over two pumps, a small shop (with its door), a tall price sign.
static func petrol(s: Dictionary) -> Dictionary:
	var m := SettlementMesh.new()
	var red := Color(0.85, 0.15, 0.1)
	var white := Color(0.94, 0.94, 0.92)
	m.box(Vector3(0.0, 5.2, -4.0), Vector3(12.0, 0.45, 8.0), white, SM.PAINT, 32, 1.0, 1.0)
	m.box(Vector3(0.0, 5.25, -8.05), Vector3(12.1, 0.55, 0.12), red, SM.PAINT, 32, 1.0, 1.0)
	m.box(Vector3(0.0, 5.25, -0.0), Vector3(12.1, 0.55, 0.12), red, SM.PAINT, 32, 1.0, 1.0)
	for sx in [-4.5, 4.5]:
		for sz in [-6.2, -1.8]:
			m.box(Vector3(float(sx), 2.5, float(sz)), Vector3(0.28, 5.0, 0.28), white, SM.METAL, 32 | 4, 1.0, 0.8)
	for sx in [-2.2, 2.2]:
		m.box(Vector3(float(sx), 0.06, -4.0), Vector3(1.4, 0.12, 4.2), Color(0.45, 0.45, 0.47), SM.CONCRETE, 32, 1.0, 1.0)
		m.box(Vector3(float(sx), 0.55, -4.0), Vector3(0.5, 1.1, 0.7), red, SM.METAL, 32, 1.0, 0.8)
		m.box(Vector3(float(sx), 1.12, -4.0), Vector3(0.52, 0.12, 0.72), Color(0.2, 0.2, 0.22), SM.METAL, 32, 1.0, 1.0)
	# the shop behind the pumps
	var sw := 8.0
	var sd := 5.0
	var sh := 3.4
	m.box(Vector3(0.0, sh * 0.5, 4.0), Vector3(sw, sh, sd), Color(0.88, 0.86, 0.8), SM.PAINT, 32 | 4, 1.0, 0.6)
	P.flat_roof(m, sw, sd, sh, 0.3, Color(0.88, 0.86, 0.8), SM.PAINT, Color(0.42, 0.42, 0.44))
	m.quad(Vector3(3.5, 0.5, 1.46), Vector3(-1.0, 0.5, 1.46), Vector3(-1.0, 2.6, 1.46), Vector3(3.5, 2.6, 1.46), Color(0.3, 0.3, 0.32), SM.GLASS, 1.0, 1.0, Vector2.ZERO, 0.9, Vector3(0, 0, -1), true)
	P.door(m, Vector3(-2.2, 0.0, 1.5), Vector3(0, 0, -1), 1.2, 2.15, Color(0.3, 0.32, 0.36), Color(0.9, 0.9, 0.88))
	m.box(Vector3(0.0, 3.3 + 0.5, 1.4), Vector3(sw, 0.6, 0.12), red, SM.GLOW, 4, 1.0, 1.0)
	# the price sign
	m.box(Vector3(7.5, 3.6, -3.0), Vector3(0.22, 7.2, 0.22), Color(0.35, 0.35, 0.37), SM.METAL, 32, 1.0, 0.8)
	m.box(Vector3(7.5, 6.8, -3.0), Vector3(1.6, 1.5, 0.3), red, SM.PAINT, 32, 1.0, 1.0)
	m.box(Vector3(7.5, 5.6, -3.0), Vector3(1.4, 1.1, 0.25), Color(1.0, 0.95, 0.7), SM.GLOW, 32, 1.0, 1.0)
	var far := SettlementMesh.new()
	far.box(Vector3(0.0, 5.0, -4.0), Vector3(12.0, 0.5, 8.0), white, SM.PAINT, 32, 1.0, 1.0)
	far.box(Vector3(0.0, sh * 0.5, 4.0), Vector3(sw, sh, sd), Color(0.88, 0.86, 0.8), SM.PAINT, 32, 1.0, 0.8)
	var res := _res(m, far, Vector3(sw, sh, sd))
	res["size_pos"] = Vector3(0.0, 0.0, 4.0)
	res["door"] = Vector3(-2.2, 0.0, 1.5)
	return res


## A hotel: five floors in strips of windows with balconies, a flat roof with a HELIPAD (a disc, an H and a ring of lights), an entrance canopy.
static func hotel(s: Dictionary) -> Dictionary:
	var m := SettlementMesh.new()
	var w := 34.0
	var d := 13.0
	var floors := 5
	var fh := 3.3
	var h := float(floors) * fh
	var wall: Color = s.get("wall", Color(0.95, 0.93, 0.88))
	var trim := Color(0.55, 0.62, 0.66)
	m.box(Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, d), wall, SM.PAINT, 32 | 4, 1.0, 0.6)
	for f in floors:
		var y := float(f) * fh + 0.95
		P.window_row(m, Vector3(w * 0.5, 0.0, -d * 0.5), Vector3(-1, 0, 0), w, y, Vector3(0, 0, -1), 2.6, 1.7, 1.7, trim, 0.7, Color(0, 0, 0, 0), 3000 + f, -1.0, -1.0)
		P.window_row(m, Vector3(-w * 0.5, 0.0, d * 0.5), Vector3(1, 0, 0), w, y, Vector3(0, 0, 1), 3.4, 1.4, 1.5, trim, 0.4, Color(0, 0, 0, 0), 3100 + f)
		if f > 0:
			for i in 7:
				var bx := -w * 0.5 + (float(i) + 0.5) * w / 7.0
				P.balcony(m, bx, -d * 0.5, 3.2, 1.1, float(f) * fh + 0.05, Color(0.8, 0.8, 0.78), Color(0.95, 0.95, 0.93))
	P.window_row(m, Vector3(-w * 0.5, 0.0, -d * 0.5), Vector3(0, 0, 1), d, 1.0, Vector3(-1, 0, 0), 3.0, 1.2, 1.4, trim, 0.4, Color(0, 0, 0, 0), 3200)
	P.window_row(m, Vector3(w * 0.5, 0.0, d * 0.5), Vector3(0, 0, -1), d, 1.0, Vector3(1, 0, 0), 3.0, 1.2, 1.4, trim, 0.4, Color(0, 0, 0, 0), 3300)
	# entrance: canopy and glass doors
	m.box(Vector3(0.0, 3.4, -d * 0.5 - 2.2), Vector3(9.0, 0.3, 4.4), Color(0.85, 0.3, 0.2), SM.PAINT, 32, 1.0, 1.0)
	for sx in [-4.0, 4.0]:
		m.box(Vector3(float(sx), 1.7, -d * 0.5 - 3.9), Vector3(0.3, 3.4, 0.3), Color(0.9, 0.9, 0.88), SM.PAINT, 32 | 4, 1.0, 0.8)
	P.door(m, Vector3(0.0, 0.0, -d * 0.5), Vector3(0, 0, -1), 2.2, 2.4, Color(0.2, 0.28, 0.34), Color(0.9, 0.9, 0.88))
	# roof: parapet, plant boxes, the helipad
	P.flat_roof(m, w, d, h, 0.9, wall, SM.PAINT, Color(0.42, 0.42, 0.44))
	var hx := -w * 0.5 + 9.5
	m.cylinder(Vector3(hx, h + 0.12, 0.0), 8.5, 0.18, 24, Color(0.2, 0.22, 0.25), SM.CONCRETE, -1.0, true, 1.0, 1.0)
	m.cylinder(Vector3(hx, h + 0.3, 0.0), 7.6, 0.04, 24, Color(0.95, 0.75, 0.1), SM.PAINT, -1.0, true, 1.0, 1.0)
	m.cylinder(Vector3(hx, h + 0.34, 0.0), 7.1, 0.04, 24, Color(0.2, 0.22, 0.25), SM.CONCRETE, -1.0, true, 1.0, 1.0)
	for sx in [-1.5, 1.5]:
		m.box(Vector3(hx + float(sx), h + 0.42, 0.0), Vector3(0.7, 0.05, 5.0), Color(0.95, 0.95, 0.92), SM.PAINT, 32, 1.0, 1.0)
	m.box(Vector3(hx, h + 0.42, 0.0), Vector3(3.2, 0.05, 0.7), Color(0.95, 0.95, 0.92), SM.PAINT, 32, 1.0, 1.0)
	for k in 12:
		var a := TAU * float(k) / 12.0
		m.box(Vector3(hx + cos(a) * 8.3, h + 0.3, sin(a) * 8.3), Vector3(0.3, 0.2, 0.3), Color(0.4, 1.0, 0.5), SM.GLOW, 4, 1.0, 1.0)
	m.box(Vector3(w * 0.5 - 7.0, h + 1.4, 0.0), Vector3(6.0, 2.0, 5.0), Color(0.62, 0.64, 0.66), SM.METAL, 32, 1.0, 1.0)
	m.box(Vector3(w * 0.5 - 14.0, h + 1.0, 2.0), Vector3(3.0, 1.2, 2.5), Color(0.62, 0.64, 0.66), SM.METAL, 32, 1.0, 1.0)
	var far := SettlementMesh.new()
	far.box(Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, d), wall, SM.PAINT, 32, 1.0, 0.8)
	far.cylinder(Vector3(hx, h + 0.1, 0.0), 8.5, 0.15, 12, Color(0.2, 0.22, 0.25), SM.PAINT, -1.0, true, 1.0, 1.0)
	var res := _res(m, far, Vector3(w, h + 0.2, d))                         # (the collider stops at the roof: a helicopter can land on the pad)
	res["extra_boxes"] = [{"pos": Vector3(w * 0.5 - 7.0, h + 1.4, 0.0), "size": Vector3(6.0, 2.0, 5.0)}, {"pos": Vector3(w * 0.5 - 14.0, h + 1.0, 2.0), "size": Vector3(3.0, 1.2, 2.5)}]
	res["door"] = Vector3(0.0, 0.0, -d * 0.5)
	res["helipad"] = Vector3(hx, h + 0.45, 0.0)
	res["anchor"] = {"kind": &"tower", "name": "HOTEL ROOF", "height": h + 2.6, "radius": 4.0, "at": Vector3(w * 0.5 - 7.0, 0.0, 0.0)}
	return res


## A lighthouse: tapered tower in red and white bands, a gallery, a glowing lantern and a cap.
static func lighthouse(s: Dictionary) -> Dictionary:
	var m := SettlementMesh.new()
	var h := 21.0
	var bands := 6
	for k in bands:
		var f0 := float(k) / float(bands)
		var f1 := float(k + 1) / float(bands)
		var c := Color(0.9, 0.9, 0.88) if k % 2 == 0 else Color(0.82, 0.14, 0.1)
		m.cylinder(Vector3(0.0, h * f0, 0.0), lerpf(3.1, 1.9, f0), h * (f1 - f0), 12, c, SM.PAINT, lerpf(3.1, 1.9, f1), false, 1.0, 0.7 if k == 0 else 1.0)
	m.cylinder(Vector3(0.0, h, 0.0), 2.6, 0.4, 12, Color(0.25, 0.25, 0.27), SM.METAL, -1.0, true, 1.0, 1.0)
	m.cylinder(Vector3(0.0, h + 0.4, 0.0), 1.3, 1.8, 10, Color(1.0, 0.95, 0.6), SM.GLOW, -1.0, true, 1.0, 1.0)
	m.cone(Vector3(0.0, h + 2.2, 0.0), 1.7, 1.4, 10, Color(0.25, 0.25, 0.27), SM.METAL, 1.0)
	P.door(m, Vector3(0.0, 0.0, -3.1), Vector3(0, 0, -1), 1.0, 2.0, Color(0.2, 0.18, 0.16), Color(0.9, 0.9, 0.88))
	var far := SettlementMesh.new()
	far.cylinder(Vector3.ZERO, 3.1, h, 8, Color(0.88, 0.5, 0.45), SM.PAINT, 1.9, true, 1.0, 0.8)
	far.cylinder(Vector3(0.0, h, 0.0), 1.6, 2.0, 8, Color(1.0, 0.95, 0.6), SM.GLOW, -1.0, true, 1.0, 1.0)
	var res := _res(m, far, Vector3(6.2, h, 6.2))
	res["cyl"] = 3.1
	res["door"] = Vector3(0.0, 0.0, -3.1)
	res["anchor"] = {"kind": &"lighthouse", "name": "LIGHTHOUSE", "height": h + 3.6, "radius": 1.5}
	return res


## A shipping-container house: two containers stacked (or one), windows cut in, an outside stair and a door.
static func container_house(s: Dictionary) -> Dictionary:
	var m := SettlementMesh.new()
	var cols: Array = s.get("cols", [Color(0.7, 0.28, 0.18), Color(0.2, 0.4, 0.55)])
	var stack_n: int = s.get("stack", 2)
	var len := 12.2
	var wid := 2.44
	var ch := 2.6
	for i in stack_n:
		var col: Color = cols[i % cols.size()]
		m.box(Vector3(0.0, ch * 0.5 + float(i) * ch, 0.0), Vector3(wid, ch, len), col, SM.METAL, 32 | (4 if i < stack_n - 1 else 0), 1.0, 0.7)
		for k in 3:
			var z := -len * 0.5 + 2.4 + float(k) * 3.6
			P.window(m, Vector3(wid * 0.5 + 0.03, float(i) * ch + 1.5, z), Vector3(1, 0, 0), 1.2, 0.9, Color(0.92, 0.92, 0.9), 0.8)
			P.window(m, Vector3(-wid * 0.5 - 0.03, float(i) * ch + 1.5, z), Vector3(-1, 0, 0), 1.2, 0.9, Color(0.92, 0.92, 0.9), 0.5)
	P.door(m, Vector3(0.0, 0.0, -len * 0.5), Vector3(0, 0, -1), 1.0, 2.1, Color(0.9, 0.9, 0.88), Color(0.3, 0.3, 0.32))
	if stack_n > 1:
		m.box(Vector3(wid * 0.5 + 0.9, ch * 0.5, -len * 0.5 + 1.8), Vector3(1.4, 0.12, 3.4), Color(0.4, 0.4, 0.42), SM.METAL, 32, 1.0, 1.0)
	var far := SettlementMesh.new()
	far.box(Vector3(0.0, ch * 0.5 * float(stack_n), 0.0), Vector3(wid, ch * float(stack_n), len), cols[0], SM.PAINT, 32, 1.0, 0.8)
	var res := _res(m, far, Vector3(wid, ch * float(stack_n), len))
	res["door"] = Vector3(0.0, 0.0, -len * 0.5)
	return res


## One row of solar panels: a long tilted sheet on posts.
static func solar_row(s: Dictionary) -> Dictionary:
	var m := SettlementMesh.new()
	var length: float = s.get("len", 18.0)
	var blue := Color(0.1, 0.16, 0.3)
	var back := Color(0.55, 0.57, 0.6)
	var p0 := Vector3(-length * 0.5, 0.9, 1.2)
	var p1 := Vector3(length * 0.5, 0.9, 1.2)
	var p2 := Vector3(length * 0.5, 2.1, -1.2)
	var p3 := Vector3(-length * 0.5, 2.1, -1.2)
	P.quad_h(m, p0, p1, p2, p3, Vector3(0, 1, -0.5), blue, SM.METAL, 1.0, 1.0, Vector2.ZERO)
	P.quad_h(m, p0, p1, p2, p3, Vector3(0, -1, 0.5), back, SM.METAL, 0.8, 1.0)
	var posts := int(length / 4.0) + 1
	for i in posts:
		var x := -length * 0.5 + length * float(i) / float(posts - 1)
		m.box(Vector3(x, 0.55, 1.2), Vector3(0.1, 1.1, 0.1), back, SM.METAL, 32, 0.8, 0.8)
		m.box(Vector3(x, 1.0, -1.2), Vector3(0.1, 2.0, 0.1), back, SM.METAL, 32, 0.8, 0.8)
	var far := SettlementMesh.new()
	P.quad_h(far, p0, p1, p2, p3, Vector3(0, 1, -0.5), blue, SM.PAINT, 1.0, 1.0)
	return _res(m, far, Vector3(length, 2.2, 2.6))


## A wooden pier along +Z... the deck at y = 0 (the caller puts the part at the right height), piles going down 4 m, bollards, lamps.
static func pier(s: Dictionary) -> Dictionary:
	var m := SettlementMesh.new()
	var length: float = s.get("len", 46.0)
	var wid := 3.4
	var wood := Color(0.42, 0.32, 0.22)
	m.box(Vector3(0.0, -0.1, length * 0.5), Vector3(wid, 0.2, length), wood, SM.WOOD, 32, 0.95, 1.0)
	var rails := int(length / 4.0)
	for i in rails + 1:
		var z := float(i) * length / float(rails)
		for sx in [-1.0, 1.0]:
			m.cylinder(Vector3(float(sx) * (wid * 0.5 - 0.15), -4.5, z), 0.17, 4.7, 6, wood.darkened(0.2), SM.WOOD, -1.0, true, 1.0, 1.0)
		if i % 2 == 0:
			m.box(Vector3(wid * 0.5 - 0.1, 0.25, z), Vector3(0.18, 0.5, 0.18), Color(0.2, 0.2, 0.22), SM.METAL, 32, 1.0, 1.0)
	for sx in [-1.0, 1.0]:
		m.box(Vector3(float(sx) * (wid * 0.5 + 0.0), 0.5, length * 0.5), Vector3(0.08, 0.08, length), wood.lightened(0.1), SM.WOOD, 32, 1.0, 1.0)
	m.cylinder(Vector3(0.0, 0.0, length - 0.5), 0.07, 3.2, 6, Color(0.2, 0.2, 0.22), SM.METAL, 0.05, true, 1.0, 1.0)
	m.box(Vector3(0.0, 3.2, length - 0.5), Vector3(0.35, 0.28, 0.35), Color(1.0, 0.85, 0.55), SM.GLOW, 4, 1.0, 1.0)
	var far := SettlementMesh.new()
	far.box(Vector3(0.0, -0.1, length * 0.5), Vector3(wid, 0.2, length), wood, SM.PAINT, 32, 1.0, 1.0)
	return _res(m, far, Vector3(wid, 0.3, length))


## A fishing boat (hull from section lofts, cabin, mast) about 8 m long, bow at -Z, keel at y 0.
static func boat(s: Dictionary) -> Dictionary:
	var m := SettlementMesh.new()
	var hull: Color = s.get("hull", Color(0.2, 0.35, 0.55))
	var length: float = s.get("len", 8.0)
	var secs: Array = [[-0.5, 0.1, 0.35], [-0.35, 0.9, 1.2], [-0.1, 1.1, 1.6], [0.2, 1.1, 1.7], [0.45, 1.0, 1.55]]
	var rings: Array = []
	for sec: Array in secs:
		var z: float = float(sec[0]) * length
		var hw: float = float(sec[1])
		var top: float = float(sec[2])
		rings.append([Vector3(-hw, top, z), Vector3(-hw * 0.55, 0.25, z), Vector3(hw * 0.55, 0.25, z), Vector3(hw, top, z)])
	for i in rings.size() - 1:
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		for k in 3:
			P.quad_h(m, a[k], b[k], b[k + 1], a[k + 1], (a[k] + a[k + 1]) * 0.5 - Vector3(0.0, 0.8, 0.0) if k == 1 else Vector3((a[k].x + a[k + 1].x) * 0.5, 0.2, 0.0), hull, SM.PAINT, 0.9, 1.0)
	m.box(Vector3(0.0, 2.2, length * 0.18), Vector3(1.8, 1.2, 2.4), Color(0.92, 0.9, 0.85), SM.PAINT, 32, 1.0, 1.0)
	m.box(Vector3(0.0, 2.9, length * 0.18), Vector3(2.0, 0.12, 2.6), Color(0.3, 0.3, 0.32), SM.METAL, 32, 1.0, 1.0)
	m.box(Vector3(0.0, 3.2, -length * 0.05), Vector3(0.12, 3.4, 0.12), Color(0.35, 0.3, 0.25), SM.WOOD, 32, 1.0, 1.0)
	m.box(Vector3(0.0, 1.62, 0.0), Vector3(1.9, 0.08, length * 0.88), Color(0.55, 0.42, 0.28), SM.WOOD, 32, 1.0, 1.0)
	var far := SettlementMesh.new()
	far.box(Vector3(0.0, 0.9, 0.0), Vector3(2.2, 1.4, length), hull, SM.PAINT, 32, 1.0, 1.0)
	return _res(m, far, Vector3(2.2, 3.0, length))


## A fish market: a long low hall open to the front with counters under a shed roof.
static func fish_market(s: Dictionary) -> Dictionary:
	var m := SettlementMesh.new()
	var w := 16.0
	var d := 8.0
	var wall: Color = s.get("wall", Color(0.85, 0.9, 0.92))
	m.box(Vector3(0.0, 1.5, d * 0.5 - 0.15), Vector3(w, 3.0, 0.3), wall, SM.PAINT, 32 | 4, 1.0, 0.7)
	m.box(Vector3(-w * 0.5 + 0.15, 1.5, 0.0), Vector3(0.3, 3.0, d), wall, SM.PAINT, 32 | 4, 1.0, 0.7)
	m.box(Vector3(w * 0.5 - 0.15, 1.5, 0.0), Vector3(0.3, 3.0, d), wall, SM.PAINT, 32 | 4, 1.0, 0.7)
	var t := SettlementMesh.new()
	P.shed_roof(t, w, d, 4.2, 3.4, 0.7, Color(0.2, 0.42, 0.55), SM.SHEET, wall, SM.PAINT)
	m.append(t, Transform3D.IDENTITY)
	for i in 3:
		m.box(Vector3(-5.0 + float(i) * 5.0, 0.5, -1.0), Vector3(3.2, 1.0, 1.0), Color(0.75, 0.75, 0.72), SM.CONCRETE, 32, 1.0, 0.8)
		m.box(Vector3(-5.0 + float(i) * 5.0, 1.02, -1.0), Vector3(3.3, 0.06, 1.1), Color(0.8, 0.85, 0.88), SM.METAL, 32, 1.0, 1.0)
	for i in 4:
		m.box(Vector3(-w * 0.5 + 0.2 + float(i) * 5.2, 1.7, -d * 0.5 + 0.2), Vector3(0.2, 3.4, 0.2), Color(0.9, 0.9, 0.88), SM.PAINT, 32 | 4, 1.0, 0.9)
	var far := _far_box(w, 3.2, d, wall, Color(0.2, 0.42, 0.55), false)
	var res := _res(m, far, Vector3(w, 3.6, d))
	res["door"] = Vector3(0.0, 0.0, -d * 0.5)
	return res


## A lodge hall: a big log chalet with a stone chimney, a deep porch and a flag pole (the field helipad is the plan's).
static func lodge_hall(s: Dictionary) -> Dictionary:
	var spec := {"w": 17.0, "d": 11.0, "floors": 2, "fh": 3.0, "wall": Color(0.5, 0.32, 0.18), "wall_code": SM.LOG, "trim": Color(0.88, 0.84, 0.74), "roof": Color(0.28, 0.2, 0.17), "roof_code": SM.SHINGLE,
		"roof_type": "gable", "slope": 0.62, "ov": 1.1, "ovg": 0.8, "ridge": "z", "chimney": true, "chim_side": 1, "chim_col": Color(0.5, 0.48, 0.44), "chim_code": SM.STONE, "porch": true, "porch_w": 6.0,
		"balcony": true, "seed": 77, "glow": 0.9, "door_col": Color(0.26, 0.16, 0.1), "win_w": 1.3, "win_h": 1.4, "bay": 3.4}
	spec["roof_type"] = &"gable"
	spec["ridge"] = &"z"
	return SettlementHouses.house(spec)


## A small stone chapel with a bell gable.
static func chapel(s: Dictionary) -> Dictionary:
	var m := SettlementMesh.new()
	var w := 5.6
	var d := 8.0
	var wall: Color = s.get("wall", Color(0.62, 0.6, 0.56))
	m.box(Vector3(0.0, 2.2, 0.0), Vector3(w, 4.4, d), wall, SM.STONE, 32 | 4, 1.0, 0.6)
	P.gable_roof(m, w, d, 4.4, 0.85, 0.4, 0.3, Color(0.25, 0.2, 0.18), SM.SHINGLE, wall, SM.STONE)
	m.box(Vector3(0.0, 4.4 + 2.4 + 0.8, -d * 0.5 + 0.1), Vector3(0.9, 1.6, 0.5), wall, SM.STONE, 32, 1.0, 1.0)
	P.window(m, Vector3(0.0, 4.4 + 2.4 + 0.9, -d * 0.5 - 0.17), Vector3(0, 0, -1), 0.45, 0.7, Color(0.2, 0.2, 0.22), 0.0)
	P.door(m, Vector3(0.0, 0.0, -d * 0.5), Vector3(0, 0, -1), 1.3, 2.4, Color(0.25, 0.16, 0.1), Color(0.8, 0.78, 0.72))
	for i in 2:
		P.window(m, Vector3(-w * 0.5 - 0.03, 2.4, -1.2 + float(i) * 3.2), Vector3(-1, 0, 0), 0.8, 1.8, Color(0.3, 0.28, 0.26), 1.0)
		P.window(m, Vector3(w * 0.5 + 0.03, 2.4, -1.2 + float(i) * 3.2), Vector3(1, 0, 0), 0.8, 1.8, Color(0.3, 0.28, 0.26), 1.0)
	var far := _far_box(w, 4.4, d, wall, Color(0.25, 0.2, 0.18))
	var res := _res(m, far, Vector3(w, 7.0, d))
	res["door"] = Vector3(0.0, 0.0, -d * 0.5)
	return res


## A well with a little roof (village square).
static func well(s: Dictionary) -> Dictionary:
	var m := SettlementMesh.new()
	m.cylinder(Vector3.ZERO, 0.95, 0.9, 10, Color(0.55, 0.52, 0.48), SM.STONE, -1.0, false, 1.0, 0.7)
	for sx in [-0.8, 0.8]:
		m.box(Vector3(float(sx), 1.5, 0.0), Vector3(0.12, 3.0, 0.12), Color(0.35, 0.26, 0.18), SM.WOOD, 32, 1.0, 1.0)
	var t := SettlementMesh.new()
	P.gable_roof(t, 2.4, 1.8, 3.0, 0.7, 0.25, 0.2, Color(0.4, 0.22, 0.16), SM.SHINGLE, Color(0.4, 0.3, 0.2), SM.WOOD, false)
	m.append(t, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO))
	var far := SettlementMesh.new()
	far.cylinder(Vector3.ZERO, 0.95, 1.0, 6, Color(0.55, 0.52, 0.48), SM.PAINT, -1.0, true, 1.0, 1.0)
	return _res(m, far, Vector3(2.0, 3.0, 2.0))
