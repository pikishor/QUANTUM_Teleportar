class_name Helipads
extends Node3D
## WAVE 125 (plan line 125 "helicopter roster, cockpits, helipads"; agent w125-pads, log docs/sprint/progress/w125-pads.md): EVERY HELIPAD OF THE WORLD in one list, the new pads,
## the parking on a pad and the pads on the map.
##   all()              every pad: {id, name, role, pos (pad surface), r, src, spawn (the spawn point id of the helicopter that waits on it)}
##                      roles: roof (tall city towers), hospital, police, news, city (the two plaza pads of wave 118), airport (the apron), army (ARMY AIRBASE east of the runway),
##                      mountain (the mountain pads and the two mountain sites), outskirts (the pads of the towns)
##   NEW PADS (src &"w125"): four raised ROOF pads on tall towers (one per quarter of the city), the HOSPITAL, POLICE HQ and NEWS STATION roof pads, three ARMY AIRBASE ground pads
##                      on the free strip east of the runway, a helicopter on the last two apron pads. A raised roof pad stands LIFT m over the roof on four legs (clear of the roof
##                      clutter), with steps down to the roof, a rim of lights that glow at night, the role's colours and markings and a sign. Built only within BUILD_IN m of the hero
##                      (one draw for the pad, one for the sign), freed beyond BUILD_OUT: nothing of it is within 460 m of the start of the game.
##   vehicle_points()   the helicopters of the new pads (VehicleSpawns.all_points appends them; owns(id) makes them FIXED like the wave 118 places)
##   map_markers()      one never-fogged H badge per pad (ArmourSites.map_markers appends them: the map and the minimap)
##   PARKING: a helicopter the hero sets down on a pad is PARKED there (meta parked_pad, kept like a fixed vehicle, the rotor winds down when he gets out); `parks` counts them.
## W125_PADS_OLD=1 (or `enabled = false`): the wave 124 world (no new pads, no pad markers, no parking) for the checks' fail-first run.

static var enabled := OS.get_environment("W125_PADS_OLD") != "1"
const LIFT := 2.6                     ## a raised roof pad's surface over the roof (Airport.ROOF_LIFT)
const CITY_R := 7.5
const MIN_START := 460.0              ## no new pad nearer the start of the game (the perf gate's staged views stand there)
const BUILD_IN := 330.0
const BUILD_OUT := 380.0
const SHOW := 360.0
const PARK_DY := 2.5                  ## a grounded helicopter within the pad's radius and this height of its surface is on the pad
## The helicopter kind a pad of each role holds: the first of the list that exists (w125-helis adds the roster; the plain helicopter is the fallback).
const KINDS := {
	&"hospital": [&"medevac", &"air_ambulance", &"heli"], &"police": [&"police_heli", &"heli"], &"news": [&"news_heli", &"heli"],
	&"army": [&"gunship", &"heli"], &"roof": [&"exec_heli", &"heli"], &"airport": [&"heli"], &"city": [&"heli"], &"mountain": [&"heli"], &"outskirts": [&"heli"],
}
const ROLE_COL := {
	&"hospital": Color(0.86, 0.1, 0.12), &"police": Color(0.12, 0.28, 0.82), &"news": Color(0.98, 0.55, 0.08), &"army": Color(0.95, 0.78, 0.12), &"roof": Color(0.95, 0.78, 0.12),
}
const SIGN := {&"hospital": "HOSPITAL", &"police": "POLICE HQ", &"news": "NEWS 9", &"army": "ARMY AIRBASE", &"roof": "HELIPAD"}
## ARMY AIRBASE: ground pads on the flat strip between the runway (local x 1240..1284) and the east edge of the field (1380), beside the military line of the apron.
const ARMY_LOCAL: Array[Vector3] = [Vector3(1334.0, 0.0, -900.0), Vector3(1334.0, 0.0, -862.0), Vector3(1334.0, 0.0, -824.0)]
const ARMY_R := 10.0
const BLD := preload("res://scripts/world/city_buildings.gd")
const BM := preload("res://scripts/world/building_meshes.gd")
const MB := preload("res://scripts/world/mesh_builder.gd")

static var instance: Helipads
static var parks := 0                 ## landings that parked a helicopter on a pad (tests)
static var last_park: StringName = &""
static var _all: Array[Dictionary] = []
static var _new: Array[Dictionary] = []
static var _markers: Array[Dictionary] = []

var _built := {}                      ## pad id -> Node3D
var _t := 0.0


# --- the data ---------------------------------------------------------------------------------------------------------------------------

## The building class and flags of lot `i` as CityBuildings.assign gives them (same hashes and thresholds; read from the live city when it exists).
static func _cls_flags(i: int, h: float, lot: CityLayout.Lot) -> Array:
	var w: Object = Game.world if is_instance_valid(Game.world) else null
	if w != null and w.get(&"building_data") is Array and (w.get(&"building_data") as Array).size() > i:
		var b: Object = (w.get(&"building_data") as Array)[i]
		return [b.get(&"cls"), int(b.get(&"flags"))]
	var r := BLD.hash01(i, 2)
	var cls := &"block"
	if h < 20.0:
		cls = &"block"
	elif h < 36.0:
		cls = &"block" if r < 0.55 else &"offset"
	elif h < 52.0:
		cls = &"stepped" if r < 0.40 else (&"offset" if r < 0.65 else &"podium")
	elif h < 75.0:
		cls = &"tiered" if r < 0.40 else (&"stepped" if r < 0.60 else &"podium")
	else:
		cls = &"landmark" if r < 0.55 else (&"tiered" if r < 0.80 else &"podium")
	var fl := 0
	var block_cz := -CityLayout.HALF + (lot.block_j + 0.5) * CityLayout.PITCH
	if h >= 44.0 and lot.cz > block_cz and BLD.hash01(i, 7) < 0.4:
		fl |= BLD.FLAG_SCREEN
	if h >= 28.0 and BLD.hash01(i, 6) < 0.45:
		fl |= BLD.FLAG_ROOF_NEON
	return [cls, fl]


## The centre of the top part of a lot's building and its free size (x, z).
static func _top(lot: CityLayout.Lot, cls: StringName) -> Array:
	var tp: Array = BM.top_part(cls)
	var cx := lot.cx + (float(tp[0]) + float(tp[1])) * 0.5 * lot.w
	var cz := lot.cz + (float(tp[2]) + float(tp[3])) * 0.5 * lot.d
	return [Vector2(cx, cz), Vector2((float(tp[1]) - float(tp[0])) * lot.w, (float(tp[3]) - float(tp[2])) * lot.d)]


## The new roof pads of the city: HOSPITAL, POLICE HQ and NEWS STATION on mid-height buildings, and one ROOF pad on the tallest suitable tower of each quarter. Never on a walk-in
## block tower (its stair house is on the roof), never on a roof with an LED screen, never within MIN_START of the start, 260 m or more from each other and from the old CITY ROOF PAD.
static func _city_pads() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lay := CityLayout.new()
	var taken: Array[Vector2] = []
	var rf := Airport.roof()
	if not rf.is_empty():
		taken.append(Vector2((rf["pos"] as Vector3).x, (rf["pos"] as Vector3).z))
	var cands: Array = []
	for lot: CityLayout.Lot in lay.lots:
		if lot.h < 24.0 or absf(lot.cx) > CityLayout.HALF - 60.0 or absf(lot.cz) > CityLayout.HALF - 60.0:
			continue
		var cf := _cls_flags(lot.index, lot.h, lot)
		if cf[0] == &"block" or (int(cf[1]) & BLD.FLAG_SCREEN) != 0:
			continue
		var top := _top(lot, cf[0])
		var c: Vector2 = top[0]
		var sz: Vector2 = top[1]
		if minf(sz.x, sz.y) < 2.0 * (CITY_R + 1.4) or c.length() < MIN_START:
			continue
		cands.append([lot, c])
	# role, wanted height band, wanted distance from the start, quarter (angle) or none
	var plan := [[&"hospital", 30.0, 60.0, 620.0, -1], [&"police", 30.0, 60.0, 560.0, -1], [&"news", 44.0, 90.0, 700.0, -1],
		[&"roof", 60.0, 999.0, 800.0, 0], [&"roof", 60.0, 999.0, 800.0, 1], [&"roof", 60.0, 999.0, 800.0, 2], [&"roof", 60.0, 999.0, 800.0, 3]]
	var qnames := ["EAST", "SOUTH", "WEST", "NORTH"]
	for p: Array in plan:
		var best: Array = []
		var bs := -INF
		for cd: Array in cands:
			var lot: CityLayout.Lot = cd[0]
			var c: Vector2 = cd[1]
			var near := false
			for t: Vector2 in taken:
				if t.distance_to(c) < 260.0:
					near = true
					break
			if near:
				continue
			var q := int(p[4])
			if q >= 0:
				var ang := fposmod(atan2(c.y, c.x) + PI * 0.25, TAU)        # 0 east, 1 south (+z), 2 west, 3 north
				if int(ang / (PI * 0.5)) != q:
					continue
			var band := 0.0 if (lot.h >= float(p[1]) and lot.h <= float(p[2])) else -200.0
			var score := band - absf(c.length() - float(p[3])) * 0.2 + (lot.h * 0.6 if p[0] == &"roof" else 0.0)
			if score > bs:
				bs = score
				best = cd
		if best.is_empty():
			continue
		var bl: CityLayout.Lot = best[0]
		var bc: Vector2 = best[1]
		taken.append(bc)
		var role: StringName = p[0]
		var nm := ""
		match role:
			&"hospital":
				nm = "CITY HOSPITAL PAD"
			&"police":
				nm = "POLICE HQ PAD"
			&"news":
				nm = "NEWS STATION PAD"
			_:
				nm = "%s TOWER PAD" % qnames[int(p[4])]
		var id := StringName("w125_%s" % (String(role) if role != &"roof" else "roof_" + String(qnames[int(p[4])]).to_lower()))
		out.append({"id": id, "name": nm, "role": role, "pos": Vector3(bc.x, bl.h + LIFT, bc.y), "r": CITY_R, "src": &"w125", "spawn": StringName("hp_" + String(id)),
			"raised": true, "roof_y": bl.h, "lot": bl.index})
	return out


## The pads this wave adds (city roofs, the airbase).
static func new_pads() -> Array[Dictionary]:
	if not enabled:
		var none: Array[Dictionary] = []
		return none
	if _new.is_empty():
		_new = _city_pads()
		for i in ARMY_LOCAL.size():
			var w := Airport.to_world(ARMY_LOCAL[i])
			var id := StringName("w125_army_%d" % (i + 1))
			_new.append({"id": id, "name": "ARMY AIRBASE PAD %d" % (i + 1), "role": &"army", "pos": Vector3(w.x, 0.0, w.z), "r": ARMY_R, "src": &"w125", "spawn": StringName("hp_" + String(id)), "raised": false})
	return _new


## Every helipad of the world (see the header). Cached.
static func all() -> Array[Dictionary]:
	if not _all.is_empty():
		return _all
	var out: Array[Dictionary] = []
	for s in ArmourSites.SITES:
		if s["type"] == &"helipad":
			out.append({"id": s["id"], "name": s["name"], "role": &"city", "pos": Vector3((s["pos"] as Vector3).x, 0.0, (s["pos"] as Vector3).z), "r": 8.4, "src": &"armour",
				"spawn": &"heli_pad" if s["id"] == &"pad_east" else &"pad_south_heli"})
	var apron_spawn := {&"apron_a": &"ap_heli_a", &"apron_b": &"ap_heli_b", &"apron_c": &"ap_heli_c"}
	for p in Airport.pads():
		var e := {"id": p["id"], "name": p["name"], "pos": p["pos"], "r": float(p["r"]), "src": &"airport"}
		match p["kind"]:
			&"apron":
				e["role"] = &"airport"
				e["spawn"] = apron_spawn.get(p["id"], StringName("hp_" + String(p["id"])))
			&"roof":
				e["role"] = &"roof"
				e["spawn"] = StringName("sp_" + String(p["id"]))
			_:
				e["role"] = &"mountain"
				e["spawn"] = StringName("sp_" + String(p["id"]))
		out.append(e)
	for hp in SettlementData.helipads():
		out.append({"id": hp["id"], "name": hp["name"], "role": &"outskirts", "pos": hp["pos"], "r": float(hp["r"]), "src": &"town", "spawn": StringName("sp_%s" % hp["id"])})
	if enabled:
		out.append_array(new_pads())
	if OutskirtsSites.built:                                            # the towns' pads exist once the roads are built: cache only the whole list
		_all = out
	return out


static func pad(id: StringName) -> Dictionary:
	for p in all():
		if p["id"] == id:
			return p
	return {}


## The helicopter kind for a pad role (the first of KINDS[role] that the roster has).
static func kind_for(role: StringName) -> StringName:
	for k: StringName in KINDS.get(role, [&"heli"]):
		if VehicleSpecs.SPECS.has(k):
			return k
	return &"heli"


## The helicopters of the new pads and of the apron pads that had none (VehicleSpawns.all_points).
static func vehicle_points() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not enabled:
		return out
	for p in all():
		var sid: StringName = p["spawn"]
		if not String(sid).begins_with("hp_"):
			continue
		out.append({"id": sid, "kind": kind_for(p["role"]), "pos": p["pos"], "h": 0.0, "label": String(p["name"])})
	return out


## True for a spawn point this file adds (ArmourSites.is_fixed: kept near the hero like the wave 118 places).
static func owns(id: StringName) -> bool:
	return enabled and String(id).begins_with("hp_")


## One never-fogged H badge per pad (kind armour, glyph helipad): ArmourSites.map_markers appends them.
static func map_markers() -> Array[Dictionary]:
	if not enabled:
		var none: Array[Dictionary] = []
		return none
	if not _markers.is_empty():
		return _markers
	var out: Array[Dictionary] = []
	for p in all():
		out.append({"kind": &"armour", "pos": p["pos"], "fog": false, "label": String(p["name"]), "glyph": &"helipad", "pad": p["id"]})
	if OutskirtsSites.built:
		_markers = out
	return out


## The pad under a point (a grounded helicopter's position): {} when none.
static func pad_at(pos: Vector3) -> Dictionary:
	for p in all():
		var c: Vector3 = p["pos"]
		if Vector2(pos.x - c.x, pos.z - c.z).length() <= float(p["r"]) + 1.0 and absf(pos.y - c.y) <= PARK_DY:
			return p
	return {}


# --- the node -----------------------------------------------------------------------------------------------------------------------------

static func attach(parent: Node) -> void:
	if not enabled or is_instance_valid(instance) or parent == null:
		return
	instance = Helipads.new()
	instance.name = "Helipads"
	parent.add_child(instance)
	var ck := HeliCockpit.new()                                      # the helicopter cockpit view (the VIEW button's third state)
	ck.name = "HeliCockpit"
	instance.add_child(ck)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.25
	if not is_instance_valid(Game.player):
		return
	var pp := Game.player.global_position
	for p in new_pads():
		var id: StringName = p["id"]
		var c: Vector3 = p["pos"]
		var d := Vector2(c.x - pp.x, c.z - pp.z).length()
		if not _built.has(id) and d < BUILD_IN:
			var n := build_pad(p)
			add_child(n)
			_built[id] = n
		elif _built.has(id) and d > BUILD_OUT:
			(_built[id] as Node).queue_free()
			_built.erase(id)
	_check_park()


func built_ids() -> Array:
	return _built.keys()


## A helicopter the hero set down on a pad is parked there (once per landing).
func _check_park() -> void:
	var vm := Game.vehicles as VehicleManager
	if vm == null or vm.driven == null:
		return
	var v := vm.driven
	if v.cls != &"heli" or v.craft == null:
		return
	if v.craft.airborne:
		if v.has_meta(&"parked_pad"):
			v.remove_meta(&"parked_pad")
		return
	if v.has_meta(&"parked_pad"):
		return
	var p := pad_at(v.global_position)
	if p.is_empty():
		return
	v.set_meta(&"parked_pad", p["id"])
	v.set_meta(&"hold", true)
	v.set_meta(&"fixed", true)
	parks += 1
	last_park = p["id"]
	Game.say("PARKED: %s" % String(p["name"]), 1.8)


# --- the pad meshes -------------------------------------------------------------------------------------------------------------------------

static func _c(col: Color, code: float) -> Color:
	return Color(col.r, col.g, col.b, code)


## The mesh of a new pad around its surface centre (the node sits at pad.pos): deck (raised pads: a steel deck on four legs with steps down to the roof), the role's paint and a rim
## of lamps (the kit shader's LAMP code glows at night). One surface, the kit material.
static func pad_mesh(p: Dictionary) -> ArrayMesh:
	var mb := MB.new()
	var r: float = p["r"]
	var role: StringName = p["role"]
	var raised := bool(p.get("raised", false))
	var col: Color = ROLE_COL.get(role, Color(0.95, 0.78, 0.12))
	var white := _c(Color(0.93, 0.93, 0.9), AirportKit.PAINT)
	if raised:
		mb.cylinder(Vector3(0.0, -0.45, 0.0), r + 1.2, 0.45, 20, _c(Color(0.46, 0.47, 0.5), AirportKit.STEEL), -1.0, true, true)
		for k in 4:
			var a := TAU * (float(k) + 0.5) / 4.0
			mb.box(Vector3(cos(a) * r * 0.62, -LIFT * 0.5 - 0.2, sin(a) * r * 0.62), Vector3(0.5, LIFT, 0.5), _c(Color(0.28, 0.3, 0.33), AirportKit.STEEL), false)
		for s in 4:                                                     # steps down to the roof on the +z side
			var h := LIFT - 0.62 * float(s + 1)
			mb.box(Vector3(0.0, -LIFT + h * 0.5 + 0.02, r + 1.75 + 0.7 * float(s)), Vector3(2.2, maxf(h, 0.1), 0.7), _c(Color(0.4, 0.41, 0.44), AirportKit.STEEL), false)
		for k in 16:
			var a2 := TAU * float(k) / 16.0
			mb.box(Vector3(cos(a2) * (r + 0.9), 0.08, sin(a2) * (r + 0.9)), Vector3(0.36, 0.22, 0.36), _c(Color(0.35, 1.0, 0.45) if k % 2 == 0 else Color(1.0, 0.86, 0.5), AirportKit.LAMP), true)
	else:
		mb.cylinder(Vector3(0.0, -0.02, 0.0), r + 2.5, 0.08, 20, _c(Color(0.4, 0.42, 0.36), AirportKit.CONCRETE), -1.0, true, false)
		for k in 12:
			var a3 := TAU * float(k) / 12.0
			mb.box(Vector3(cos(a3) * (r + 1.6), 0.12, sin(a3) * (r + 1.6)), Vector3(0.36, 0.22, 0.36), _c(Color(0.35, 1.0, 0.45) if k % 2 == 0 else Color(1.0, 0.86, 0.5), AirportKit.LAMP), true)
	# the paint: the role's ring, the disc, the markings
	mb.cylinder(Vector3(0.0, 0.03, 0.0), r, 0.04, 24, _c(col, AirportKit.PAINT), -1.0, true, false)
	var disc := Color(0.22, 0.25, 0.2) if role == &"army" else Color(0.42, 0.43, 0.45)
	mb.cylinder(Vector3(0.0, 0.06, 0.0), r - 0.7, 0.03, 24, _c(disc, AirportKit.CONCRETE), -1.0, true, false)
	var hw := r * 0.32
	var hh := r * 0.44
	var t := r * 0.11
	var hcol := white
	if role == &"hospital":                                             # a white cross with a red H on it
		mb.box(Vector3(0.0, 0.1, 0.0), Vector3(r * 1.25, 0.02, r * 0.5), white, false)
		mb.box(Vector3(0.0, 0.1, 0.0), Vector3(r * 0.5, 0.02, r * 1.25), white, false)
		hcol = _c(col, AirportKit.PAINT)
		hw = r * 0.2
		hh = r * 0.3
		t = r * 0.08
	elif role == &"police":
		mb.box(Vector3(0.0, 0.1, 0.0), Vector3(r * 1.1, 0.02, r * 1.1), _c(Color(0.08, 0.16, 0.45), AirportKit.PAINT), false)
	elif role == &"army":
		hcol = _c(Color(0.95, 0.78, 0.12), AirportKit.PAINT)
		for sx: float in [-1.0, 1.0]:                                    # the four corners of the touchdown box
			for sz: float in [-1.0, 1.0]:
				var cc := Vector3(sx * r * 0.62, 0.1, sz * r * 0.62)
				mb.box(cc - Vector3(sx * r * 0.1, 0.0, 0.0), Vector3(r * 0.24, 0.02, t * 0.8), white, false)
				mb.box(cc - Vector3(0.0, 0.0, sz * r * 0.1), Vector3(t * 0.8, 0.02, r * 0.24), white, false)
	mb.box(Vector3(-hw, 0.12, 0.0), Vector3(t, 0.03, hh * 2.0), hcol, false)
	mb.box(Vector3(hw, 0.12, 0.0), Vector3(t, 0.03, hh * 2.0), hcol, false)
	mb.box(Vector3(0.0, 0.12, 0.0), Vector3(hw * 2.0, 0.03, t), hcol, false)
	if role == &"news":                                                  # a mast with a dish and a red beacon
		mb.box(Vector3(-r - 0.6, 3.0, -r * 0.5), Vector3(0.3, 6.0, 0.3), _c(Color(0.7, 0.7, 0.72), AirportKit.STEEL), false)
		mb.cylinder(Vector3(-r - 0.6, 4.2, -r * 0.5 + 0.2), 1.0, 0.3, 12, _c(Color(0.85, 0.85, 0.86), AirportKit.STEEL), -1.0, true, true)
		mb.box(Vector3(-r - 0.6, 6.15, -r * 0.5), Vector3(0.45, 0.35, 0.45), _c(Color(1.0, 0.2, 0.15), AirportKit.LAMP), true)
	# the sign board on the edge facing the steps
	var bc := _c(col if role != &"roof" else Color(0.1, 0.22, 0.4), AirportKit.STEEL)
	mb.box(Vector3(0.0, 1.0, -r - 1.0), Vector3(r * 0.9, 1.3, 0.16), bc, false)
	for sx: float in [-r * 0.4, r * 0.4]:
		mb.box(Vector3(sx, 0.2, -r - 1.0), Vector3(0.14, 0.6, 0.14), _c(Color(0.25, 0.26, 0.28), AirportKit.STEEL), false)
	return mb.build(BridgeKit.kit_material())


## The node of one new pad: the mesh, the deck collider (raised pads, and the steps), the sign's words.
static func build_pad(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Pad_" + String(p["id"])
	root.position = p["pos"]
	var mi := MeshInstance3D.new()
	mi.mesh = pad_mesh(p)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.visibility_range_end = SHOW
	root.add_child(mi)
	var r: float = p["r"]
	if bool(p.get("raised", false)):
		var body := StaticBody3D.new()
		body.collision_layer = Game.L_WORLD
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = r + 1.2
		cyl.height = 0.5
		cs.shape = cyl
		cs.position = Vector3(0.0, -0.25, 0.0)
		body.add_child(cs)
		for s in 4:
			var h := LIFT - 0.62 * float(s + 1)
			if h <= 0.05:
				continue
			var sc := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			bx.size = Vector3(2.2, h, 0.7)
			sc.shape = bx
			sc.position = Vector3(0.0, -LIFT + h * 0.5 + 0.02, r + 1.75 + 0.7 * float(s))
			body.add_child(sc)
		root.add_child(body)
	var l := Label3D.new()
	l.text = String(SIGN.get(p["role"], "HELIPAD"))
	l.font_size = 72
	l.pixel_size = 0.012
	l.outline_size = 0
	l.modulate = Color(0.97, 0.96, 0.9)
	l.shaded = false
	l.double_sided = true
	l.position = Vector3(0.0, 1.0, -r - 0.9)
	l.visibility_range_end = 90.0
	root.add_child(l)
	return root
