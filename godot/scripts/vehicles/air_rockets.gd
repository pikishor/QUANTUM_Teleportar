class_name AirRockets
extends Node3D
## The rockets and missiles of the aircraft (ROCKET POD of the gunship, MISSILES of the jet; numbers in VehicleSpecs.ALT_WEAPONS, fired by VehicleWeapons.tick_alt on the AIM button). A pooled set of
## real projectiles: each flies `speed` m/s along its direction for `life` s (a missile steers towards the target it locked at launch, `homing` rad/s), leaves a smoke line (FX.tracer) and explodes
## on the first thing it touches (the world, an enemy, a vehicle, the terrain): Game.explode with the weapon's blast radius, plus the direct hit damage on whatever it struck. At most POOL in the air.
##   AirRockets.launch(shooter, def, origin, dir, target) -> bool     (false when the pool is full)
##   AirRockets.instance.live_count() / detonations              (tests)

const POOL := 14

static var instance: AirRockets = null

var detonations := 0
var launched := 0
var last_blast := Vector3.INF
var _live: Array[Dictionary] = []
var _meshes: Array[MeshInstance3D] = []
## w126-air (AirArms): bombs fall (def `grav`, `inherit` = share of the aircraft's velocity they keep), cargo crates fall under a chute (`chute` m/s) and land instead of exploding,
## a def with `blast_id` explodes through the BlastTable, and a missile whose target hides behind flares (AirArms.flaring) loses it.
var by_look := {}                     ## look (&"rocket" &"bomb" &"crate") -> detonations / landings (tests)
var drops: Array[Vector3] = []        ## where the cargo crates landed (newest last, at most 16)
var hits_on := {}                     ## instance id of what a projectile struck directly -> count (tests)
var _looks := {}                      ## MeshInstance3D -> look


## Fire one projectile. `def` = the ALT_WEAPONS entry, `target` = a Node3D to steer towards (or null).
static func launch(shooter: Vehicle, def: Dictionary, origin: Vector3, dir: Vector3, target: Node3D = null) -> bool:
	var inst := _shared(shooter)
	if inst == null:
		return false
	return inst._launch(shooter, def, origin, dir, target)


static func _shared(shooter: Node) -> AirRockets:
	if is_instance_valid(instance):
		return instance
	var parent: Node = Game.world if is_instance_valid(Game.world) else (shooter.get_tree().root if shooter != null and shooter.is_inside_tree() else null)
	if parent == null:
		return null
	var n := AirRockets.new()
	n.name = "AirRockets"
	parent.add_child(n)
	return n


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func live_count() -> int:
	return _live.size()


func _launch(shooter: Vehicle, def: Dictionary, origin: Vector3, dir: Vector3, target: Node3D) -> bool:
	if _live.size() >= POOL:
		return false
	var look: StringName = def.get("look", &"rocket")
	var mi := _mesh(look)
	mi.visible = true
	var d := dir.normalized()
	var inh := float(def.get("inherit", 0.3))
	var v0 := d * float(def["speed"]) + shooter.vel * inh
	if def.has("inherit") and shooter.craft != null:
		v0.y += shooter.craft.vy * inh                                            # a bomb leaves with the climb or the dive of the aircraft
	_live.append({"pos": origin, "vel": v0, "life": float(def["life"]), "def": def, "shooter": shooter, "target": target, "mi": mi, "age": 0.0})
	mi.global_position = origin
	_orient(mi, d)
	launched += 1
	FX.burst(origin, Color(1.0, 0.9, 0.6, 0.7), 5, 4.0, 0.35, 0.0, 1.2)             # the launch puff
	Sfx.play_at(&"shot", origin, -2.0)
	return true


func _mesh(look: StringName = &"rocket") -> MeshInstance3D:
	for m in _meshes:
		if not m.visible and _looks.get(m, &"rocket") == look:
			return m
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	var cm: PrimitiveMesh
	match look:
		&"bomb":                                                                   # a fat dark body with a nose (w126-air)
			var cb := CylinderMesh.new()
			cb.top_radius = 0.16
			cb.bottom_radius = 0.22
			cb.height = 1.6
			cb.radial_segments = 8
			cb.rings = 1
			mat.albedo_color = Color(0.22, 0.25, 0.22)
			mat.roughness = 0.6
			cm = cb
		&"crate":                                                                  # a crate under an orange chute canopy (the chute is the crate's own top: one mesh)
			var bx := BoxMesh.new()
			bx.size = Vector3(1.4, 1.1, 1.4)
			mat.albedo_color = Color(0.55, 0.42, 0.22)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.5, 0.1)
			mat.emission_energy_multiplier = 0.25
			cm = bx
		_:
			var cy := CylinderMesh.new()
			cy.top_radius = 0.07
			cy.bottom_radius = 0.1
			cy.height = 1.5
			cy.radial_segments = 6
			cy.rings = 1
			mat.albedo_color = Color(0.78, 0.78, 0.8)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.6, 0.2)
			mat.emission_energy_multiplier = 2.5
			cm = cy
	cm.material = mat
	mi.mesh = cm
	_looks[mi] = look
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_meshes.append(mi)
	return mi


static func _orient(mi: Node3D, d: Vector3) -> void:
	var up := Vector3.UP if absf(d.y) < 0.98 else Vector3.RIGHT
	var b := Basis.looking_at(d, up) * Basis(Vector3.RIGHT, PI * 0.5)      # the cylinder's axis is Y: turn it onto -Z (the flight direction)
	mi.global_transform = Transform3D(b, mi.global_position)


func _physics_process(dt: float) -> void:
	var i := _live.size() - 1
	while i >= 0:
		var r := _live[i]
		var def: Dictionary = r["def"]
		var pos: Vector3 = r["pos"]
		var vel: Vector3 = r["vel"]
		var shooter := r["shooter"] as Vehicle
		var tgt := r["target"] as Node3D
		r["age"] = float(r["age"]) + dt
		var hom := float(def.get("homing", 0.0))
		if hom > 0.0 and is_instance_valid(tgt) and AirArms.flaring(tgt):              # w126-air: flares pull the missile off (it flies on straight)
			r["target"] = null
			tgt = null
			AirArms.decoyed += 1
		var grav := float(def.get("grav", 0.0))
		if grav > 0.0:
			vel.y -= grav * dt
			if def.has("chute") and float(r["age"]) > 0.8:                               # the chute opens: the crate sinks slowly and drifts less
				vel.y = maxf(vel.y, -float(def["chute"]))
				vel.x = move_toward(vel.x, 0.0, 6.0 * dt)
				vel.z = move_toward(vel.z, 0.0, 6.0 * dt)
		if hom > 0.0 and is_instance_valid(tgt) and float(r["age"]) > 0.25:        # steer: turn the velocity towards the target by at most `homing` rad/s
			var want := (tgt.global_position + Vector3(0.0, 0.8, 0.0) - pos).normalized()
			var cur := vel.normalized()
			var ang := cur.angle_to(want)
			if ang > 0.001:
				var turn := minf(ang, hom * dt)
				var axis := cur.cross(want)
				if axis.length_squared() > 1.0e-8:
					vel = vel.rotated(axis.normalized(), turn)
		var nxt := pos + vel * dt
		var hit := _sweep(pos, nxt, shooter)
		var boom := false
		var at := nxt
		var col: Object = null
		if not hit.is_empty():
			boom = true
			at = hit["position"]
			col = hit["collider"]
		elif nxt.y < TerrainHeight.height_at(nxt.x, nxt.z) and (absf(nxt.x) > TerrainHeight.CITY_HALF or absf(nxt.z) > TerrainHeight.CITY_HALF):
			boom = true
			at = Vector3(nxt.x, TerrainHeight.height_at(nxt.x, nxt.z), nxt.z)
		elif nxt.y < 0.0:
			boom = true
			at = Vector3(nxt.x, 0.0, nxt.z)
		r["life"] = float(r["life"]) - dt
		if float(r["life"]) <= 0.0:
			boom = true
		if grav <= 0.0:
			FX.tracer(pos, nxt, Color(0.85, 0.85, 0.9, 0.5))                                   # the smoke line (a bomb and a crate fall without one)
		if boom:
			_detonate(at, def, col, shooter)
			(r["mi"] as MeshInstance3D).visible = false
			_live.remove_at(i)
		else:
			r["pos"] = nxt
			r["vel"] = vel
			var mi := r["mi"] as MeshInstance3D
			mi.global_position = nxt
			_orient(mi, vel.normalized())
		i -= 1


func _sweep(a: Vector3, b: Vector3, shooter: Vehicle) -> Dictionary:
	if not is_inside_tree():
		return {}
	var q := PhysicsRayQueryParameters3D.create(a, b, Game.L_WORLD | Game.L_ENEMY | Game.L_VEHICLE)
	if is_instance_valid(shooter):
		q.exclude = [shooter.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)


func _detonate(at: Vector3, def: Dictionary, col: Object, shooter: Vehicle = null) -> void:
	var look: StringName = def.get("look", &"rocket")
	by_look[look] = int(by_look.get(look, 0)) + 1
	if look == &"crate":                                                          # w126-air: a cargo crate lands, it does not explode
		drops.append(at)
		if drops.size() > 16:
			drops.pop_front()
		FX.burst(at + Vector3(0.0, 0.4, 0.0), Color(0.85, 0.75, 0.55), 10, 4.0, 0.6, 2.0, 0.8)
		Sfx.play_at(&"hit", at, -6.0, 0.7)
		return
	detonations += 1
	last_blast = at
	var dmg := float(def["dmg"])
	if col != null and col.has_method(&"damage"):
		col.call(&"damage", dmg)
		if col is Object:
			hits_on[(col as Object).get_instance_id()] = int(hits_on.get((col as Object).get_instance_id(), 0)) + 1
		if col is Node and (col as Node).is_in_group(&"enemy"):
			BlastCredit.dealt(col, dmg)                                           # a rocket that hits a person directly counts (the splash below credits the rest)
	if def.has("blast_id") and BlastTable.has_entry(StringName(def["blast_id"])):
		BlastTable.apply(StringName(def["blast_id"]), at, shooter if is_instance_valid(shooter) else null)       # w126-air: the blast of the table (radius, falloff, damage per target)
		return
	Game.explode(at, float(def["blast"]), {"enemy_dmg": dmg * 0.8, "car_dmg": dmg * 0.8, "player_dmg": 0.0, "color": def["color"]})
