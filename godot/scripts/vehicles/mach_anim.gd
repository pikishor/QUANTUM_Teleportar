class_name MachAnim
extends RefCounted
## WAVE 129 MACHINE AND AIRCRAFT ANIMATION AND EFFECTS (w129-machanim). Everything that moves or smokes on a machine beyond its drive code, run from VehicleCraft.sync / Vehicle._sync:
##   HELICOPTERS  the blades fade into a streaked blur disc as they spool up (shader rotor_disc: tip ring, streaks, cone), the TAIL ROTOR has its own disc (before: its blades were
##                hidden at speed and nothing was drawn: no tail rotor in flight), the blades cone up under lift and droop at rest, flap once a turn in forward flight (shader
##                rotor_blade), the rotor head tilts with the cyclic, the skids flex on a landing and settle as the rotor takes the weight; the downwash throws dust or spray outwards.
##   AEROPLANES   PlaneRig (scripts/vehicles/plane_rig.gd): ailerons, elevator, rudder and flaps on their hinges, gear that folds away with its doors; nav and strobe lights at
##                night, wingtip vortices and contrails, the jet's heat glow (see plane()).
##   ARMOUR, CARS gun recoil, muzzle flash and smoke, track dust, exhaust (see tank() / car()), burning wrecks.
## Budgets: the puffs ride BlastFx's one cloud MultiMesh at low priority (BlastFx.machine_puff: a blast always wins a slot), blur discs and blades swap with each other (never both
## at full), lights and trails exist only for a craft with its engines running near the player. Per tier: LOW keeps the player's own machine's effects only.
##   old            W129_OLD=1: the code before this wave (every [old fails] check of tests/test_machanim_w129.gd fails with it)
##   lod_margin(m)  the hysteresis margin of a near/far mesh pair (Body / Body_LOD1). Godot keeps a per-instance "was visible" state for a range with fade disabled: a NEW
##                  instance starts hidden, so with a margin m the near body needs the camera under d - m and the far body over d + m: between the two NEITHER drew
##                  (the parked AWACS that showed only its wheels, cars spawning 39 to 45 m away). Margin 0 makes the pair an exact complement.

const DISC_SHADER := preload("res://assets/shaders/rotor_disc.gdshader")
const FLAME_SHADER := preload("res://assets/shaders/jet_flame.gdshader")
const NAV_SHADER := preload("res://assets/shaders/nav_lights.gdshader")
const TRAIL_SHADER := preload("res://assets/shaders/contrail.gdshader")
const BLADE_SHADER := preload("res://assets/shaders/rotor_blade.gdshader")
const BLUR_FROM := 0.55                 ## share of VehicleCraft.BLUR_SPIN where the disc starts to show (the blades fade out as it fills in)
const BLUR_FULL := 1.15
const CONE_LIFT := 0.07                 ## rad of coning at full lift
const DROOP := 0.035                    ## rad the blades sag at rest
const FLAP := 0.035                     ## rad of once-a-turn flap at full forward speed
const TILT := 0.1                       ## rad the rotor head tilts with full cyclic
const WASH_EVERY := 0.09

static var old := OS.get_environment("W129_OLD") == "1"
static var _disc_mesh: CylinderMesh
static var _disc_mat: ShaderMaterial
static var _blade_mats := {}
static var wash_puffs := 0              ## counters (tests read them)
static var _flame_meshes := {}
static var _nav_meshes := {}
static var _flame_mat: ShaderMaterial
static var _nav_mat: ShaderMaterial
static var _trail_mat: ShaderMaterial


## w129-integrator: the shared cloud node (BlastFx) for the machines' puffs. When a machine is the first to need it (a car's exhaust on a quiet street) it is freed with the game
## (Game.world leaving the tree), as the game's other effects are: test_integration "freeing the game leaves no nodes behind" counted its 8 nodes under the FX autoload.
static func _fx() -> BlastFx:
	if is_instance_valid(BlastFx.instance):
		return BlastFx.instance
	var fx := BlastFx.shared()
	var w: Node = Game.world
	if fx_free_with_game and is_instance_valid(fx) and is_instance_valid(w) and not w.tree_exiting.is_connected(fx.queue_free):
		w.tree_exiting.connect(fx.queue_free, CONNECT_ONE_SHOT)
	return fx


static var fx_free_with_game := OS.get_environment("W129I_OLD") != "1"


static func lod_margin(m: float) -> float:
	return m if old else 0.0


## Per-craft animation state (VehicleCraft.State.mach).
class St extends RefCounted:
	var cone := 0.0
	var tilt_x := 0.0
	var tilt_z := 0.0
	var flex := 0.0                     ## m the body sits below its rest height on the gear (negative = compressed)
	var flex_v := 0.0
	var flex_min := 0.0                 ## deepest flex since the last read (tests)
	var landings := 0
	var wash_t := 0.0
	var fx_t := 0.0
	var trail_t := 0.0
	var pose := {"aileron": 0.0, "elevator": 0.0, "rudder": 0.0, "flap": 0.0, "gear": 0.0, "door": 1.0}   ## the moving parts of an aeroplane (PlaneRig.pose)
	var posed := {}                     ## what the skeleton holds now (it is only written when something moved)
	var gear_cycles := 0                ## gear retractions so far (tests)
	var lights: MeshInstance3D
	var trail: Node3D


static func st(c: VehicleCraft.State) -> St:
	if c.mach == null:
		c.mach = St.new()
	return c.mach as St


# --- build time ------------------------------------------------------------------------------------------------------------------------

static func _unit_disc() -> CylinderMesh:
	if _disc_mesh == null:
		_disc_mesh = CylinderMesh.new()
		_disc_mesh.top_radius = 1.0
		_disc_mesh.bottom_radius = 1.0
		_disc_mesh.height = 0.01
		_disc_mesh.radial_segments = 32
		_disc_mesh.rings = 1
		_disc_mat = ShaderMaterial.new()
		_disc_mat.resource_name = "Blur"
		_disc_mat.shader = DISC_SHADER
	return _disc_mesh


static func _blade_material(src: Material) -> ShaderMaterial:
	var key := src.resource_name
	if not _blade_mats.has(key):
		var m := ShaderMaterial.new()
		m.resource_name = "Blade"
		m.shader = BLADE_SHADER
		if src is BaseMaterial3D:
			var b := src as BaseMaterial3D
			m.set_shader_parameter(&"albedo", b.albedo_color)
			m.set_shader_parameter(&"metallic", b.metallic)
			m.set_shader_parameter(&"roughness", b.roughness)
		_blade_mats[key] = m
	return _blade_mats[key]


static func _blades_of(kind: StringName) -> int:
	if HeliModels.has_classic(kind) or HeliRoster.DEFS.has(kind):
		var r: Array = HeliModels.params(kind).get("rotor", [])
		if r.size() > 2:
			return int(r[2])
	return 4


## VehicleVisual._bind_craft, after the discs were made: the new blur discs (one shared unit mesh and material, scaled to the rotor), the tail rotor's disc, the coning blades.
static func bind(vis: VehicleVisual, spec: Dictionary, kind: StringName) -> void:
	if old:
		return
	var mesh := _unit_disc()
	var tail := vis.parts.get("TailRotor") as MeshInstance3D
	if tail != null and tail.mesh != null and not vis.parts.has("TailRotorDisc"):
		var a := tail.mesh.get_aabb()
		var tr := maxf(maxf(absf(a.position.y), absf(a.end.y)), maxf(absf(a.position.z), absf(a.end.z)))
		var d := MeshInstance3D.new()
		d.name = "TailRotorDisc"
		d.position = tail.position
		d.visible = false
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		vis.model.add_child(d)
		vis.parts["TailRotorDisc"] = d
		d.set_meta(&"r", maxf(tr, 0.3))
		d.set_meta(&"axis", 0)
	var nb := _blades_of(kind)
	for nm: String in vis.parts.keys():
		if not nm.ends_with("Disc"):
			continue
		var dm := vis.parts[nm] as MeshInstance3D
		if dm == null:
			continue
		var r := float(dm.get_meta(&"r", 0.0))
		if r <= 0.0:
			var am := dm.mesh as CylinderMesh
			r = am.top_radius if am != null else 1.0
			dm.set_meta(&"r", r)
		dm.mesh = mesh
		dm.material_override = _disc_mat
		var prop := nm.begins_with("Prop")
		var ax := int(dm.get_meta(&"axis", 2 if prop else 1))              # 1: about Y (main rotor), 2: about Z (propeller), 0: about X (tail rotor)
		dm.set_meta(&"axis", ax)
		dm.transform.basis = _axis_basis(ax) * Basis.from_scale(Vector3(r, 1.0, r))
		dm.set_instance_shader_parameter(&"blades", float(3 if prop else (4 if nm == "TailRotorDisc" else nb)))
		dm.set_instance_shader_parameter(&"rate", 1.3 if prop else 0.9)
		dm.set_instance_shader_parameter(&"cone", 0.0)
	for nm: String in ["Rotor", "Rotor2"]:
		var rm := vis.parts.get(nm) as MeshInstance3D
		if rm == null or rm.mesh == null or VehicleSpecs.cls_of(kind) != &"heli":
			continue
		for s in rm.mesh.get_surface_count():
			var src := rm.mesh.surface_get_material(s)
			if src != null and (src.resource_name == "Trim" or src.resource_name == "Chrome"):
				rm.set_surface_override_material(s, _blade_material(src))
	_paint_rig(vis)
	if GLB_GEAR.has(vis.model_name) and vis.body != null:
		_glb_gear(vis, GLB_GEAR[vis.model_name])
	if VehicleSpecs.cls_of(kind) == &"plane" and (bool(spec.get("jet", false)) or bool(spec.get("burner", false))):
		_add_flame(vis, spec, kind)


## The moving parts of an aeroplane (PlaneRig) wear the hull's paint like the body they were cut from.
static func _paint_rig(vis: VehicleVisual) -> void:
	var det := vis.model.get_node_or_null("Detail") as MeshInstance3D
	if det == null or det.skin == null or det.mesh == null or vis._body_mat == null:
		return
	for i in det.mesh.get_surface_count():
		var m := det.mesh.surface_get_material(i)
		if m != null and m.resource_name == "Body":
			det.set_surface_override_material(i, vis._body_mat)


static func _axis_basis(ax: int) -> Basis:
	match ax:
		0:
			return Basis(Vector3.BACK, PI * 0.5)                 # the disc's Y axis turned onto X (tail rotor)
		2:
			return Basis(Vector3.RIGHT, PI * 0.5)                # onto Z (propeller)
	return Basis.IDENTITY


# --- helicopters -----------------------------------------------------------------------------------------------------------------------

## The rotors of a helicopter, per tick (VehicleCraft.sync, heli branch, `near`: the player flies it or it is within 90 m). Returns the body's flex offset (m) for the model.
static func heli(v: Vehicle, dt: float, near: bool) -> float:
	var c := v.craft
	var vis := v.visual
	var s := st(c)
	var top := maxf(float(v.spec["max"]), 1.0)
	var load := clampf(0.55 + c.vy * 0.06 + (0.35 if c.airborne else 0.0), 0.0, 1.2)
	var want := -DROOP * (1.0 - c.spool) + CONE_LIFT * c.spool * load
	s.cone = lerpf(s.cone, want, 1.0 - exp(-4.0 * dt))
	s.tilt_x = lerpf(s.tilt_x, -TILT * clampf(c.thr_in, -1.0, 1.0) * c.spool, 1.0 - exp(-6.0 * dt))
	s.tilt_z = lerpf(s.tilt_z, TILT * 0.6 * clampf(v.steer_in, -1.0, 1.0) * c.spool, 1.0 - exp(-6.0 * dt))
	var flap := FLAP * clampf(absf(v.speed) / top, 0.0, 1.0) * c.spool
	var spin := c.spool * 38.0
	var blur := smoothstep(VehicleCraft.BLUR_SPIN * BLUR_FROM, VehicleCraft.BLUR_SPIN * BLUR_FULL, spin)
	if near:
		var tb := Basis(Vector3.RIGHT, s.tilt_x) * Basis(Vector3.BACK, s.tilt_z)
		for nm: String in ["Rotor", "Rotor2"]:
			var rot := vis.parts.get(nm) as MeshInstance3D
			if rot == null:
				continue
			var dir := 1.0 if nm == "Rotor" else -1.0
			rot.transform.basis = tb * Basis(Vector3.UP, c.ang * dir)
			rot.visible = blur < 0.97
			rot.set_instance_shader_parameter(&"cone", s.cone)
			rot.set_instance_shader_parameter(&"flap", flap)
			rot.set_instance_shader_parameter(&"azim", c.ang * dir)
			var d := vis.parts.get(nm + "Disc") as MeshInstance3D
			if d != null:
				var r := float(d.get_meta(&"r", 4.0))
				d.visible = blur > 0.02
				d.transform.basis = tb * Basis.from_scale(Vector3(r, 1.0, r))
				d.set_instance_shader_parameter(&"blur", blur)
				d.set_instance_shader_parameter(&"cone", tan(s.cone) * r)
		var tail := vis.parts.get("TailRotor") as Node3D
		if tail != null:
			var tspin := c.spool * 60.0
			var tblur := smoothstep(VehicleCraft.BLUR_SPIN * BLUR_FROM, VehicleCraft.BLUR_SPIN * BLUR_FULL, tspin)
			tail.rotation = Vector3(c.tail_ang, 0.0, 0.0)
			tail.visible = tblur < 0.97
			var td := vis.parts.get("TailRotorDisc") as MeshInstance3D
			if td != null:
				td.visible = tblur > 0.02
				td.set_instance_shader_parameter(&"blur", tblur)
	# the gear: a landing compresses it (the harder the sink, the deeper), the body sits a little lower while the rotor does not carry it and rises as the rotor takes the weight
	if c.landings != s.landings:
		s.landings = c.landings
		s.flex_v -= clampf(c.hard, 1.5, 9.0) * 0.3
	var rest := 0.0 if c.airborne else -0.035 * (1.0 - c.spool)
	var left := minf(dt, 0.05)
	while left > 0.0:
		var h := minf(left, 0.01)
		s.flex_v += (80.0 * (rest - s.flex) - 6.0 * s.flex_v) * h
		s.flex += s.flex_v * h
		left -= h
	s.flex = clampf(s.flex, -0.22, 0.06)
	s.flex_min = minf(s.flex_min, s.flex)
	var det := vis.model.get_node_or_null("Detail") as Node3D
	if det != null:
		det.position.y = -s.flex                                             # the skids stay on the ground while the body sinks onto them
	return s.flex


## The rotor's downwash (AircraftFlight._wash calls it): dust, sand or spray thrown OUT from under the disc along the ground, more the lower it hovers; a ripple ring on water.
static func wash(v: Vehicle, dt: float, agl: float, range_m: float) -> void:
	var s := st(v.craft)
	s.wash_t -= dt
	if s.wash_t > 0.0:
		return
	s.wash_t = WASH_EVERY if Game.quality > 0 else WASH_EVERY * 2.0
	var k := clampf(1.0 - agl / range_m, 0.0, 1.0)
	var p := v.global_position
	var gy := AircraftFlight.ground_y(v)
	var wl := TerrainHeight.water_level_at(p.x, p.z)
	var water := wl != TerrainHeight.NO_WATER and (absf(p.x) > TerrainHeight.CITY_HALF or absf(p.z) > TerrainHeight.CITY_HALF)
	var gk := &"water" if water else BlastFx.ground_kind(Vector3(p.x, gy, p.z))
	var col := BlastFx.dust_color(gk)
	col.a = (0.42 if gk == &"dirt" else (0.5 if water else 0.26)) * (0.5 + 0.5 * k)
	var fx := _fx()
	var rr := float(v.spec.get("rotor_r", 3.6))
	var s0 := 0.8 + rr * 0.1
	var s1 := 1.8 + rr * 0.22
	var y := (wl if water else gy) + s1 * 0.42                              # a camera-facing puff cut by the ground shows a hard line: keep it above the ground as it grows
	for i in 2:
		var a := randf() * TAU
		var out := Vector3(cos(a), 0.0, sin(a))
		var at := Vector3(p.x, y, p.z) + out * rr * randf_range(0.55, 0.95)
		if fx.machine_puff(at, out * (5.0 + 8.0 * k) + Vector3(0.0, 0.5 + 0.6 * k, 0.0), s0, s1, 1.0 + 0.4 * k, col, BlastFx.K_SPRAY if water else BlastFx.K_SMOKE, 0.0, 1.4):
			wash_puffs += 1
	if water and FX.marks != null:
		FX.marks.ripple(Vector3(p.x, wl, p.z), 2.0 + rr * 0.5)


# --- aeroplanes ------------------------------------------------------------------------------------------------------------------------

const GEAR_UP_AGL := 18.0               ## m above the ground where the gear folds away after a take-off
const GEAR_DOWN_AGL := 70.0             ## m: below this, descending, the gear comes down for the landing
const GEAR_RATE := 0.45                 ## share of the travel per second (about 2.2 s up or down)
const SURF_RATE := 7.0


## Per tick (VehicleCraft.sync, plane branch): the control surfaces follow the stick (ailerons opposite, elevators with UP / DOWN, the rudder with the turn), the flaps come out slow
## and on the ground with the engines running, the gear folds away after a take-off and comes down for the landing with its doors.
static func plane(v: Vehicle, dt: float, near: bool) -> void:
	var c := v.craft
	var s := st(c)
	var d := s.pose
	var stall := maxf(float(v.spec.get("stall", 30.0)), 5.0)
	var gt := 0.0
	if c.airborne:
		gt = float(d["gear"])
		if c.agl > GEAR_UP_AGL and c.vy > -3.0 and v.speed > stall * 1.05:
			gt = 1.0
		if (c.agl < GEAR_DOWN_AGL and c.vy < -0.8) or v.speed < stall * 0.95 or c.agl < GEAR_UP_AGL * 0.5:
			gt = 0.0
	var g0 := float(d["gear"])
	d["gear"] = move_toward(g0, gt, GEAR_RATE * dt)
	if g0 < 1.0 and float(d["gear"]) >= 1.0:
		s.gear_cycles += 1
	d["door"] = 1.0 - smoothstep(0.72, 1.0, float(d["gear"]))
	var k := 1.0 - exp(-SURF_RATE * dt)
	var steer := clampf(v.steer_in, -1.0, 1.0)
	d["aileron"] = lerpf(float(d["aileron"]), steer * PlaneRig.AILERON, k)
	d["elevator"] = lerpf(float(d["elevator"]), clampf(c.lift_in, -1.0, 1.0) * PlaneRig.ELEVATOR, k)
	d["rudder"] = lerpf(float(d["rudder"]), steer * PlaneRig.RUDDER * 0.7, k)
	var ft := 0.0
	if c.spool > 0.12:
		ft = 0.45 if not c.airborne else clampf((stall * 1.7 - v.speed) / (stall * 0.6), 0.0, 1.0)
	d["flap"] = move_toward(float(d["flap"]), ft * PlaneRig.FLAP, 0.35 * dt)
	if near:
		_pose_rig(v.visual, s)
	_flame(v, near)
	_lights(v, s)
	if v.driver_is_player or s.trail != null:
		_trails(v, s, dt)


static func _pose_rig(vis: VehicleVisual, s: St) -> void:
	var m := vis.model
	if m == null or not m.has_meta(&"rig"):
		return
	var sk := m.get_node_or_null("Rig") as Skeleton3D
	if sk == null:
		return
	var moved := s.posed.is_empty()
	for key: String in s.pose:
		if absf(float(s.pose[key]) - float(s.posed.get(key, 99.0))) > 0.002:
			moved = true
			break
	if not moved:
		return
	PlaneRig.pose(sk, m.get_meta(&"rig"), s.pose)
	s.posed = s.pose.duplicate()


## The angle (rad) a part of the plane's rig has now (tests): `part` is its bone name ("AileronR", "MainGearL", "NoseDoorL" ...); NAN when the plane has no such part.
static func part_angle(v: Vehicle, part: String) -> float:
	var m := v.visual.model if v.visual != null else null
	if m == null or not m.has_meta(&"rig"):
		return NAN
	var sk := m.get_node_or_null("Rig") as Skeleton3D
	var i := sk.find_bone(part) if sk != null else -1
	if i < 0:
		return NAN
	var q := sk.get_bone_pose_rotation(i)
	var a := q.get_angle()
	return a if q.get_axis().dot((m.get_meta(&"rig") as Array)[i - 1]["axis"]) >= 0.0 else -a


# --- jet exhaust, navigation lights, trails ---------------------------------------------------------------------------------------------

const AB_FROM := 0.55                   ## thrust share where the afterburner lights (as the old Burner cone)
const NIGHT_FROM := 0.35                ## DayNight.night_now from which the lights are on
const LIGHTS_FAR := 900.0
const TRAIL_EVERY := 0.05
const CONTRAIL_ALT := 320.0             ## m above the sea where the engines leave contrails
const VORTEX_LIFE := 0.9
const CONTRAIL_LIFE := 7.0


## One soft cone per nozzle (unit length, UV.y along), merged: the jet's heat glow and afterburner (replaces the old single Burner cone).
static func _add_flame(vis: VehicleVisual, spec: Dictionary, kind: StringName) -> void:
	var noz: Array = vis.model.get_meta(&"nozzles", [])
	var old_b := vis.parts.get("Burner") as Node3D
	if noz.is_empty():
		if old_b == null:
			return
		noz = [[old_b.position - Vector3(0.0, 0.0, 0.5), 0.42]]
	if old_b != null:
		old_b.queue_free()
	if not _flame_meshes.has(kind):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for nz: Array in noz:
			var c: Vector3 = nz[0]
			var r := float(nz[1])
			var segs := 10
			for i in segs:
				var a0 := TAU * float(i) / float(segs)
				var a1 := TAU * float(i + 1) / float(segs)
				var q := [[a0, 0.0], [a1, 0.0], [a1, 1.0], [a0, 0.0], [a1, 1.0], [a0, 1.0]]
				for e: Array in q:
					var a := float(e[0])
					var t := float(e[1])
					var rr := r * lerpf(1.0, 0.3, t)
					var n := Vector3(cos(a), sin(a), 0.0)
					st.set_normal(n)
					st.set_uv(Vector2(a / TAU, t))
					st.add_vertex(c + n * rr + Vector3(0.0, 0.0, t))
		_flame_meshes[kind] = st.commit()
	if _flame_mat == null:
		_flame_mat = ShaderMaterial.new()
		_flame_mat.resource_name = "Flame"
		_flame_mat.shader = FLAME_SHADER
	var mi := MeshInstance3D.new()
	mi.name = "Flame"
	mi.mesh = _flame_meshes[kind]
	mi.material_override = _flame_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 12.0
	mi.visible = false
	vis.model.add_child(mi)
	vis.parts["Flame"] = mi
	vis.parts["Burner"] = mi                                                       # (the name older code and tests look the afterburner up by)
	mi.set_meta(&"r", float((noz[0] as Array)[1]))
	mi.set_meta(&"ab", bool(spec.get("burner", false)))


## The exhaust: a heat glow in the nozzles while the engines run, the afterburner's long blue-white core with shock diamonds above AB_FROM of the thrust.
static func _flame(v: Vehicle, near: bool) -> void:
	var f := v.visual.parts.get("Flame") as MeshInstance3D
	if f == null:
		return
	var c := v.craft
	var th := AircraftFlight.air(c).thrust
	var on := near and c.spool > 0.15 and not v.wreck and not v.dead
	f.visible = on
	if not on:
		return
	var abv := clampf((th - AB_FROM) / (1.0 - AB_FROM), 0.0, 1.0) if bool(f.get_meta(&"ab", false)) else 0.0
	var r := float(f.get_meta(&"r", 0.5))
	f.set_instance_shader_parameter(&"power", clampf(0.3 + 0.7 * th, 0.0, 1.0) * c.spool)
	f.set_instance_shader_parameter(&"ab", abv)
	f.set_instance_shader_parameter(&"flame_len", r * (1.6 + 12.0 * abv))


static func _nav_mesh(kind: StringName, lights: Array) -> ArrayMesh:
	if _nav_meshes.has(kind):
		return _nav_meshes[kind]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for l: Array in lights:
		var p: Vector3 = l[0]
		var col: Color = l[1]
		col.a = float(l[2])
		for uv: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
			st.set_color(col)
			st.set_uv(uv)
			st.set_uv2(Vector2(float(l[3]), 0.0))
			st.add_vertex(p)
	var m := st.commit()
	_nav_meshes[kind] = m
	return m


## The navigation lights at night while the engines run (one mesh per plane, made on first use; hidden by day, parked or far).
static func _lights(v: Vehicle, s: St) -> void:
	var m := v.visual.model
	var want := DayNight.night_now >= NIGHT_FROM and v.craft.spool > 0.1 and not v.wreck and not v.dead and (v.driver_is_player or v._dist < LIGHTS_FAR) and m.has_meta(&"navl")
	if s.lights == null:
		if not want:
			return
		if _nav_mat == null:
			_nav_mat = ShaderMaterial.new()
			_nav_mat.resource_name = "NavLights"
			_nav_mat.shader = NAV_SHADER
		var mi := MeshInstance3D.new()
		mi.name = "NavLights"
		mi.mesh = _nav_mesh(StringName(m.get_meta(&"kind", &"")), m.get_meta(&"navl"))
		mi.material_override = _nav_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 4.0
		mi.set_instance_shader_parameter(&"phase", float(v.get_instance_id() % 97) * 0.173)
		m.add_child(mi)
		s.lights = mi
	if s.lights.visible != want:
		s.lights.visible = want
	if want:
		s.lights.set_instance_shader_parameter(&"power", clampf((DayNight.night_now - NIGHT_FROM) / 0.3, 0.0, 1.0))


## Whether the plane's navigation lights are on now (tests).
static func lights_on(v: Vehicle) -> bool:
	var s := st(v.craft)
	return s.lights != null and is_instance_valid(s.lights) and s.lights.visible


## Wingtip vortices (hard pull or roll at speed: short white threads off the tips) and contrails (high and fast: long trails behind the engines), for the player's own aircraft.
class Trail extends MeshInstance3D:
	var strands: Array = []             ## per strand: Array of [pos, age, strength]
	var lives: Array[float] = []
	var widths: Array[float] = []
	var im: ImmediateMesh
	var points := 0

	func _init() -> void:
		top_level = true
		im = ImmediateMesh.new()
		mesh = im
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		extra_cull_margin = 4000.0

	func add_strand(life: float, width: float) -> int:
		strands.append([])
		lives.append(life)
		widths.append(width)
		return strands.size() - 1

	func push(i: int, p: Vector3, strength: float) -> void:
		var a: Array = strands[i]
		if strength > 0.02:
			a.push_front([p, 0.0, strength])
		elif not a.is_empty() and float((a[0] as Array)[2]) > 0.0:
			a.push_front([p, 0.0, 0.0])                    # close the ribbon where it stopped

	func step(dt: float, cam: Vector3) -> void:
		im.clear_surfaces()
		points = 0
		var any := false
		for i in strands.size():
			var a: Array = strands[i]
			for e: Array in a:
				e[1] = float(e[1]) + dt
			while not a.is_empty() and float((a.back() as Array)[1]) > lives[i]:
				a.pop_back()
			if a.size() >= 2:
				any = true
		visible = any
		if not any:
			return
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in strands.size():
			var a: Array = strands[i]
			for k in a.size() - 1:
				var e0: Array = a[k]
				var e1: Array = a[k + 1]
				var p0: Vector3 = e0[0]
				var p1: Vector3 = e1[0]
				var dir := p1 - p0
				if dir.length_squared() < 0.0001:
					continue
				var w0 := widths[i] * (1.0 + float(e0[1]) / lives[i] * 2.0)
				var w1 := widths[i] * (1.0 + float(e1[1]) / lives[i] * 2.0)
				var side0 := dir.cross(cam - p0).normalized()
				var side1 := dir.cross(cam - p1).normalized()
				var u0 := float(e0[1]) / lives[i]
				var u1 := float(e1[1]) / lives[i]
				var c0 := Color(1, 1, 1, minf(float(e0[2]), float(e1[2])))
				var quad := [[p0 - side0 * w0, Vector2(u0, 0.0)], [p0 + side0 * w0, Vector2(u0, 1.0)], [p1 + side1 * w1, Vector2(u1, 1.0)],
					[p0 - side0 * w0, Vector2(u0, 0.0)], [p1 + side1 * w1, Vector2(u1, 1.0)], [p1 - side1 * w1, Vector2(u1, 0.0)]]
				for q: Array in quad:
					im.surface_set_color(c0)
					im.surface_set_uv(q[1])
					im.surface_add_vertex(q[0])
				points += 1
		im.surface_end()


static func _trails(v: Vehicle, s: St, dt: float) -> void:
	var c := v.craft
	var A := AircraftFlight.air(c)
	var stall := maxf(float(v.spec.get("stall", 30.0)), 5.0)
	var top := maxf(float(v.spec["max"]), 1.0)
	var vort := 0.0
	if c.airborne and v.speed > stall * 1.5:
		vort = clampf(maxf(absf(c.lift_in), absf(v.steer_in) * 0.8) * (v.speed / top) * 1.4 - 0.25, 0.0, 0.8)
	var jet := bool(v.spec.get("jet", false)) or v.visual.model.has_meta(&"nozzles")
	var con := 0.0
	if jet and c.airborne and v.global_position.y > CONTRAIL_ALT and v.speed > top * 0.55:
		con = clampf((v.global_position.y - CONTRAIL_ALT) / 120.0, 0.0, 1.0) * 0.75
	if s.trail == null:
		if vort <= 0.0 and con <= 0.0:
			return
		var t := Trail.new()
		t.name = "Trails"
		if _trail_mat == null:
			_trail_mat = ShaderMaterial.new()
			_trail_mat.resource_name = "Trail"
			_trail_mat.shader = TRAIL_SHADER
		t.material_override = _trail_mat
		v.add_child(t)
		t.global_transform = Transform3D.IDENTITY
		var nav: Array = v.visual.model.get_meta(&"navl", [])
		var span := float(v.spec.get("span", v.spec["wid"])) * 0.5
		var tips: Array = [Vector3(-span, float(v.spec["hgt"]) * 0.35, 0.3), Vector3(span, float(v.spec["hgt"]) * 0.35, 0.3)]
		if nav.size() >= 2:
			tips = [(nav[0] as Array)[0], (nav[1] as Array)[0]]
		t.set_meta(&"tips", tips)
		t.add_strand(VORTEX_LIFE, 0.11)
		t.add_strand(VORTEX_LIFE, 0.11)
		var noz: Array = v.visual.model.get_meta(&"nozzles", [])
		var outs: Array = []
		for nz: Array in noz.slice(0, 4):
			outs.append((nz[0] as Vector3) + Vector3(0.0, 0.0, 1.5))
		if outs.is_empty():
			outs = [Vector3(0.0, float(v.spec["hgt"]) * 0.4, float(v.spec["len"]) * 0.5 + 1.0)]
		t.set_meta(&"outs", outs)
		for o in outs:
			t.add_strand(CONTRAIL_LIFE, 0.5)
		s.trail = t
	var tr := s.trail as Trail
	s.trail_t -= dt
	if s.trail_t <= 0.0:
		s.trail_t = TRAIL_EVERY
		var xf := v.visual.model.global_transform
		var tips: Array = tr.get_meta(&"tips")
		tr.push(0, xf * (tips[0] as Vector3), vort)
		tr.push(1, xf * (tips[1] as Vector3), vort)
		var outs: Array = tr.get_meta(&"outs")
		for i in outs.size():
			tr.push(2 + i, xf * (outs[i] as Vector3), con)
	var cam := Game.camera.global_position if is_instance_valid(Game.camera) else v.global_position + Vector3.UP * 10.0
	tr.step(dt, cam)


## Trail points drawn now (tests): vortices + contrails.
static func trail_points(v: Vehicle) -> int:
	var s := st(v.craft)
	return (s.trail as Trail).points if s.trail != null and is_instance_valid(s.trail) and (s.trail as Trail).visible else 0


# --- armour --------------------------------------------------------------------------------------------------------------------------------

const RECOIL := 0.42                    ## m the barrel runs back into the turret on a shot (scaled by the barrel length)
const RECOIL_BACK := 9.0                ## 1/s: how fast it runs out again
const DUST_EVERY := 0.11
const EXHAUST_EVERY := 0.32
static var gun_shots := 0               ## counters (tests read them)
static var dust_puffs := 0
static var exhaust_puffs := 0
static var muzzle_puffs := 0


## A main gun shot (VehicleWeapons._shoot / _shell): the barrel recoils into the turret and runs out, the hull rocks back, a flash at the muzzle, a ring of blast smoke
## round the muzzle and the dust it kicks up from the ground beside the tank.
static func gun_fired(car: Vehicle, origin: Vector3, dir: Vector3) -> void:
	if old or car == null or car.craft == null or car.cls != &"tank":
		return
	var s := st(car.craft)
	s.set_meta(&"recoil", 1.0)
	s.set_meta(&"rock", 1.0)
	gun_shots += 1
	if not (car.driver_is_player or car._dist < 120.0):
		return
	var cal := clampf(float(car.spec.get("gun_len", 3.4)) / 3.4, 0.5, 1.6)
	FX.muzzle_flash(origin, dir, Color(1.0, 0.78, 0.4), 2.6 * cal)
	var fx := _fx()
	var side := dir.cross(Vector3.UP).normalized()
	var n := 3 if Game.quality == 0 else 5
	for i in n:
		var a := (float(i) / float(maxi(n - 1, 1)) - 0.5) * 2.2
		var out := (dir * (0.9 - absf(a) * 0.35) + side * a * 0.6).normalized()
		if fx.machine_puff(origin + dir * 0.6, out * randf_range(5.0, 9.0) + Vector3(0.0, 0.8, 0.0), 0.7 * cal, 3.2 * cal, 1.8, Color(0.62, 0.6, 0.57, 0.55), BlastFx.K_SMOKE, 0.0, 2.2):
			muzzle_puffs += 1
	var gy := AircraftFlight.ground_y(car)
	var gk := BlastFx.ground_kind(Vector3(origin.x, gy, origin.z))
	var dc := BlastFx.dust_color(gk)
	dc.a = 0.5 if gk == &"dirt" else 0.3
	for sx: float in [-1.0, 1.0]:
		var at := Vector3(origin.x, gy + 0.9, origin.z) - dir * 1.0 + side * sx * 1.6
		if fx.machine_puff(at, side * sx * 6.0 + Vector3(0.0, 0.5, 0.0), 1.0, 3.6, 1.6, dc, BlastFx.K_SMOKE, 0.0, 2.0):
			muzzle_puffs += 1


## Per tick (VehicleCraft.sync, tank branch, after the turret): the barrel recoil and the hull's rock, track dust by the ground kind, diesel exhaust with the throttle.
static func tank(v: Vehicle, dt: float) -> void:
	var c := v.craft
	var s := st(c)
	var vis := v.visual
	var rec := float(s.get_meta(&"recoil", 0.0))
	var rock := float(s.get_meta(&"rock", 0.0))
	if rec > 0.0 or rock > 0.0:
		rec = maxf(0.0, rec - RECOIL_BACK * dt * (0.35 + rec))
		rock = maxf(0.0, rock - 2.6 * dt)
		s.set_meta(&"recoil", rec)
		s.set_meta(&"rock", rock)
		var turret := vis.parts.get("Turret") as Node3D
		var gun := turret.get_node_or_null("Gun") as Node3D if turret != null else null
		if gun != null:
			if not gun.has_meta(&"rest"):
				gun.set_meta(&"rest", gun.position)
			var cal := clampf(float(v.spec.get("gun_len", 3.4)) / 3.4, 0.5, 1.6)
			var kick := RECOIL * cal * smoothstep(0.0, 1.0, rec)
			gun.position = (gun.get_meta(&"rest") as Vector3) + gun.transform.basis.z * kick       # the barrel points along -Z: it runs back along +Z
		var yaw := c.turret_yaw - v.heading
		var r := sin(rock * PI) * 0.035 * rock                                        # the hull rocks away from the shot
		vis.model.rotation.x += cos(yaw) * r
		vis.model.rotation.z += -sin(yaw) * r
	if not (v.driver_is_player or (v._dist < 70.0 and Game.quality > 0 and (v.ai or v.scripted or absf(v.speed) > 0.5))):
		return                                                       # a parked tank's engine is off
	var fx := _fx()
	var sp := absf(v.speed)
	var ln := float(v.spec["len"])
	var wid := float(v.spec["wid"])
	s.fx_t -= dt
	if sp > 2.5 and s.fx_t <= 0.0:
		s.fx_t = DUST_EVERY * (1.6 if Game.quality == 0 else 1.0)
		var gy := AircraftFlight.ground_y(v)
		var gk := BlastFx.ground_kind(Vector3(v.global_position.x, gy, v.global_position.z))
		if gk != &"water":
			var col := BlastFx.dust_color(gk)
			col.a = clampf(sp / 12.0, 0.25, 1.0) * (0.55 if gk == &"dirt" or gk == &"snow" else 0.22)
			var back := -v.forward() * ln * 0.45 * signf(v.speed)
			var sx := 1.0 if randf() < 0.5 else -1.0
			var at := v.global_position + back + v.right() * sx * wid * 0.42 + Vector3(0.0, 0.7, 0.0)
			if fx.machine_puff(at, -v.forward() * signf(v.speed) * sp * 0.25 + Vector3(0.0, 0.8, 0.0) + BlastFx.WIND * 0.5, 0.8, 2.6 + sp * 0.12, 1.5, col, BlastFx.K_SMOKE, 0.0, 0.9):
				dust_puffs += 1
	s.trail_t -= dt
	if s.trail_t <= 0.0:
		var load := clampf(absf(c.thr_in) + absf(v.steer_in) * 0.5, 0.0, 1.0)
		s.trail_t = EXHAUST_EVERY * (1.4 - 0.7 * load)
		var ex := v.global_position - v.forward() * ln * 0.46 + v.right() * wid * 0.3 + Vector3(0.0, float(v.spec["hgt"]) * 0.55, 0.0)
		var ecol := Color(0.16, 0.16, 0.17, 0.25 + 0.4 * load)
		if fx.machine_puff(ex, Vector3(0.0, 1.4, 0.0) - v.forward() * 1.2 + BlastFx.WIND * 0.6, 0.35, 1.3 + load, 1.4, ecol, BlastFx.K_SMOKE, 0.0, 1.0):
			exhaust_puffs += 1


## The barrel's recoil now (0 at rest .. 1 just fired), for the tests.
static func recoil_of(v: Vehicle) -> float:
	return float(st(v.craft).get_meta(&"recoil", 0.0)) if v.craft != null else 0.0


# --- cars and bikes ------------------------------------------------------------------------------------------------------------------------

## Exhaust from the tail pipe of a car or bike near the camera: a faint shimmer at idle, a darker puff when the throttle opens (Vehicle._sync).
static func car(v: Vehicle, dt: float) -> void:
	if not (v.driver_is_player or (v._dist < 22.0 and Game.quality > 0 and (v.ai or v.chasing))) or v.dead or v.wreck or not v.active:
		return                                                       # a parked car's engine is off: no smoke (and no puff draw in a quiet street)
	if v.cls == &"hover" or bool(v.spec.get("electric", false)):
		return
	var t := float(v.get_meta(&"exh_t", 0.0)) - dt
	var acc := clampf(v.long_acc / 4.0, 0.0, 1.0) if v.driver_is_player else clampf((v.speed - v._last_vf) / maxf(dt, 0.001) / 4.0, 0.0, 1.0)
	if t <= 0.0:
		t = (0.55 - 0.35 * acc) * (1.5 if Game.quality == 0 else 1.0)
		var ln := float(v.spec["len"])
		var at := v.global_position - v.forward() * ln * 0.5 + v.right() * float(v.spec["wid"]) * 0.28 + Vector3(0.0, 0.32 if v.cls == &"car" else 0.45, 0.0)
		var col := Color(0.66, 0.67, 0.69, 0.07 + 0.2 * acc)
		if _fx().machine_puff(at, -v.forward() * (1.0 + 2.0 * acc) + Vector3(0.0, 0.5, 0.0) + v.vel * 0.6, 0.15, 0.55 + 0.5 * acc, 0.8, col, BlastFx.K_SMOKE, 0.0, 1.2):
			exhaust_puffs += 1
	v.set_meta(&"exh_t", t)


# --- wrecks --------------------------------------------------------------------------------------------------------------------------------

const BURN_SECS := 28.0                 ## a husk burns this long (an armoured hull longer), then smoulders
const SMOULDER_SECS := 40.0
const WRECK_NEAR := 150.0
static var wreck_puffs := 0


## Vehicle.become_wreck: the husk starts to burn.
static func on_wreck(v: Vehicle) -> void:
	if old:
		return
	v.set_meta(&"burn", BURN_SECS * (1.5 if v.cls == &"tank" else 1.0))
	v.set_meta(&"smoulder", SMOULDER_SECS)
	v.set_meta(&"burn_t", 0.0)


## Per physics tick from VehicleManager: every husk near the camera burns (flame tongues licking off the hull, a thick black column that leans with the wind), then smoulders
## (a thin grey thread). Pooled puffs, LOW at half the rate.
static func wrecks(list: Array, dt: float) -> void:
	if old or list.is_empty():
		return
	var cam := Game.camera.global_position if is_instance_valid(Game.camera) else Vector3.INF
	for e: Dictionary in list:
		var raw: Variant = e.get("car")
		if not is_instance_valid(raw):
			continue
		var v := raw as Vehicle
		if not v.wreck or not v.has_meta(&"burn"):
			continue
		var burn := float(v.get_meta(&"burn")) - dt
		var smo := float(v.get_meta(&"smoulder"))
		if burn <= 0.0:
			smo -= dt
			v.set_meta(&"smoulder", smo)
		v.set_meta(&"burn", burn)
		if smo <= 0.0 or v.global_position.distance_to(cam) > WRECK_NEAR:
			continue
		var t := float(v.get_meta(&"burn_t")) - dt
		if t > 0.0:
			v.set_meta(&"burn_t", t)
			continue
		var lowk := 2.0 if Game.quality == 0 else 1.0
		var fx := _fx()
		var ln := float(v.spec["len"])
		var wid := float(v.spec["wid"])
		var top := v.global_position + Vector3(0.0, float(v.spec["hgt"]) * 0.7, 0.0)
		var size := clampf(maxf(ln, wid) / 4.5, 0.7, 3.0)
		if burn > 0.0:
			v.set_meta(&"burn_t", 0.16 * lowk)
			var heat := clampf(burn / 8.0, 0.25, 1.0)
			var at := top + v.forward() * randf_range(-0.35, 0.35) * ln + v.right() * randf_range(-0.3, 0.3) * wid
			if fx.machine_puff(at, Vector3(0.0, 2.2, 0.0), 0.9 * size, 1.9 * size * heat, 0.8, Color(1.0, 0.55, 0.2, 0.95), BlastFx.K_FLAME, 0.75, 0.4, 1.6):
				wreck_puffs += 1
			if randf() < 0.55:
				var col := Color(0.09, 0.085, 0.08, 0.7)
				if fx.machine_puff(top + Vector3(0.0, 1.2 * size, 0.0), Vector3(0.0, 3.2, 0.0) + BlastFx.WIND * 1.5, 1.4 * size, 5.0 * size, 4.5, col, BlastFx.K_SMOKE, 0.0, 0.25):
					wreck_puffs += 1
		else:
			v.set_meta(&"burn_t", 0.9 * lowk)
			if fx.machine_puff(top, Vector3(0.0, 1.5, 0.0) + BlastFx.WIND, 0.5 * size, 2.6 * size, 4.0, Color(0.42, 0.42, 0.43, 0.35 * smo / SMOULDER_SECS + 0.1), BlastFx.K_SMOKE, 0.0, 0.2):
				wreck_puffs += 1


# --- the old art aeroplanes: a nose leg instead of the tail wheel ------------------------------------------------------------------------

## The xv_jet and xv_cargo art models stood on two main legs and a TAIL WHEEL (a jet and a cargo lifter are tricycles): the tail wheel's triangles go (box `cut`), a nose leg
## with its wheel (or a pair) is added under the nose (`at` = the strut top inside the belly, `r` wheel radius). One extra small mesh within DETAIL_FAR m, one surface.
const GLB_GEAR := {
	"xv_jet": {"cut": AABB(Vector3(-0.215, -0.1, 3.3), Vector3(0.43, 1.37, 2.4)), "at": Vector3(0.0, 0.98, -5.1), "r": 0.36, "pair": false},
	"xv_cargo": {"cut": AABB(Vector3(-0.32, -0.1, 15.05), Vector3(0.64, 2.66, 1.6)), "at": Vector3(0.0, 5.05, -17.6), "r": 0.62, "pair": true},
}
static var _glb_meshes := {}


static func _glb_gear(vis: VehicleVisual, g: Dictionary) -> void:
	var key := vis.model_name
	if not _glb_meshes.has(key):
		var src := vis.body.mesh
		var cut: AABB = g["cut"]
		var out := ArrayMesh.new()
		for si in src.get_surface_count():
			var arr := src.surface_get_arrays(si)
			var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			if not idx.is_empty():
				var keep := PackedInt32Array()
				for t in range(0, idx.size() - 2, 3):
					if cut.has_point(vv[idx[t]]) and cut.has_point(vv[idx[t + 1]]) and cut.has_point(vv[idx[t + 2]]):
						continue
					keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
				arr[Mesh.ARRAY_INDEX] = keep
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			out.surface_set_material(si, src.surface_get_material(si))
			out.surface_set_name(si, src.surface_get_name(si))
		var b := PlaneModels.new()
		var top: Vector3 = g["at"]
		var r := float(g["r"])
		var hub := Vector3(top.x, r, top.z)
		b._slab(VehicleCraftModels.S_TRIM, top, hub + Vector3(0.0, r * 0.3, 0.0), maxf(0.12, r * 0.32), maxf(0.1, r * 0.26), Vector3.BACK)
		b._slab(VehicleCraftModels.S_TRIM, hub + Vector3(0.0, r * 0.9, -r * 0.2), top + Vector3(0.0, -0.3, -absf(top.y - r) * 0.35), 0.08, 0.08, Vector3.BACK)     # the drag brace
		if bool(g["pair"]):
			for dx in [-r * 0.62, r * 0.62]:
				b._cyl(VehicleCraftModels.S_TRIM, hub + Vector3(dx, 0.0, 0.0), r, r * 0.55, 0, 12)
		else:
			b._cyl(VehicleCraftModels.S_TRIM, hub, r, r * 0.55, 0, 12)
		_glb_meshes[key] = [out, b._finish()]
	var pair: Array = _glb_meshes[key]
	vis.body.mesh = pair[0]
	var mi := MeshInstance3D.new()
	mi.name = "NoseGear"
	mi.mesh = pair[1]
	mi.visibility_range_end = PlaneModels.DETAIL_FAR
	mi.layers = mi.layers | VehicleVisual.KEY_BIT
	vis.model.add_child(mi)
