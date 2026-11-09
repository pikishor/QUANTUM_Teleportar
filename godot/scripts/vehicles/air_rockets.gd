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
	var mi := _mesh()
	mi.visible = true
	var d := dir.normalized()
	_live.append({"pos": origin, "vel": d * float(def["speed"]) + shooter.vel * 0.3, "life": float(def["life"]), "def": def, "shooter": shooter, "target": target, "mi": mi, "age": 0.0})
	mi.global_position = origin
	_orient(mi, d)
	launched += 1
	FX.burst(origin, Color(1.0, 0.9, 0.6, 0.7), 5, 4.0, 0.35, 0.0, 1.2)             # the launch puff
	Sfx.play_at(&"shot", origin, -2.0)
	return true


func _mesh() -> MeshInstance3D:
	for m in _meshes:
		if not m.visible:
			return m
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.07
	cm.bottom_radius = 0.1
	cm.height = 1.5
	cm.radial_segments = 6
	cm.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.78, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.2)
	mat.emission_energy_multiplier = 2.5
	cm.material = mat
	mi.mesh = cm
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
		FX.tracer(pos, nxt, Color(0.85, 0.85, 0.9, 0.5))                                       # the smoke line
		if boom:
			_detonate(at, def, col)
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


func _detonate(at: Vector3, def: Dictionary, col: Object) -> void:
	detonations += 1
	last_blast = at
	var dmg := float(def["dmg"])
	if col != null and col.has_method(&"damage"):
		col.call(&"damage", dmg)
	Game.explode(at, float(def["blast"]), {"enemy_dmg": dmg * 0.8, "car_dmg": dmg * 0.8, "player_dmg": 0.0, "color": def["color"]})
