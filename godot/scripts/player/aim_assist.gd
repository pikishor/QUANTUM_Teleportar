class_name AimAssist
extends Node
## Soft aim assist for touch (and optional on mouse): near an enemy the look slows down (look_scale) and the view is nudged toward it (magnetism) while the trigger or
## ADS is held. Off for the Pulse Lance (the sniper rewards precision). `auto_fire` (a setting, off by default) holds the trigger while the crosshair is on a target.
## The pure maths are static so tests need no scene. Settings come from UiSettings (assist, auto_fire) through load_settings().

const CONE := 0.09                  ## radians off the crosshair where assist begins (about 5 degrees)
const SLOW_MIN := 0.45              ## look speed multiplier right on a target
const PULL := 1.6                   ## magnetism, fraction of the angular error closed per second
const PULL_MAX := 0.9               ## rad/s cap
const RANGE := 60.0
const LOS_CHECKS := 4                ## rays a frame spent on candidates (nearest to the crosshair first)
## Right-stick aiming (a controller) gets a stronger assist than touch: a wider cone, a deeper slowdown and a harder pull.
const PAD_CONE := 1.6
const PAD_SLOW_MIN := 0.3
const PAD_PULL := 2.2
const PAD_PULL_MAX := 1.3

## Hit reaction strength per weapon (flinch / stagger on the enemy): the scatter and lance rock a target, the carbine only flinches it.
const STAGGER := {&"carbine": 0.4, &"scatter": 0.9, &"lance": 1.5, &"grenade": 1.2, &"minigun": 0.15, &"akimbo": 0.3, &"arc": 0.7, &"revolver": 1.1, &"whip": 0.9, &"blade": 1.0, &"pistol": 0.35, &"marksman": 0.8, &"breacher": 0.8, &"rocket": 1.3, &"swarm": 0.15, &"vector": 0.3, &"battle": 0.6, &"sawn": 1.0, &"auto": 0.6, &"bolt": 1.4, &"dmr": 0.9, &"knife": 0.5}

static var enabled := true
static var auto_fire := false

var on_target := false              ## a shot fired now would hit this enemy (its real shape, nothing in the way): the HUD tints the crosshair and brackets it
var aim_zone: StringName = &""      ## head / body / legs of that hit
var target: Node3D
var _p: Player


static func load_settings() -> void:
	var s := UiSettings.new()
	enabled = s.aim_assist
	auto_fire = s.auto_fire


## True for weapons the assist applies to (every weapon but the Pulse Lance).
## A taller hero looks down on enemies from higher up: the assist cone grows with the eye height (1.0 .. 1.3).
static func cone_scale() -> float:
	return clampf(float(HeroPresentation.camera_scale()["eye"]), 1.0, 1.3)


static func applies_to(weapon_id: StringName) -> bool:
	return weapon_id != &"lance"


## Look speed multiplier for a target `ang` radians off the crosshair whose body spans `rad_ang` radians: 1 outside the cone, SLOW_MIN on it.
static func slow_factor(ang: float, rad_ang: float, pad := false) -> float:
	var edge := CONE * (PAD_CONE if pad else 1.0) + rad_ang
	if ang >= edge:
		return 1.0
	return lerpf(PAD_SLOW_MIN if pad else SLOW_MIN, 1.0, smoothstep(rad_ang * 0.5, edge, ang))


## Magnetism: the angular correction (radians) toward the target for one frame. Zero on the target's centre line and outside the cone.
static func pull(err: float, ang: float, rad_ang: float, dt: float, pad := false) -> float:
	var edge := CONE * (PAD_CONE if pad else 1.0) + rad_ang
	if ang >= edge:
		return 0.0
	var k := 1.0 - smoothstep(0.0, edge, ang)
	var cap := PAD_PULL_MAX if pad else PULL_MAX
	return clampf(err * (PAD_PULL if pad else PULL) * k * dt, -cap * dt, cap * dt)


func _ready() -> void:
	_p = get_parent() as Player
	load_settings()


## Nearest live enemy in the cone: {node, ang, rad_ang, yaw_err, pitch_err}, empty when none. With `los_from` (the muzzle line's start) a candidate the world or a car hides
## is passed over (the look must not be pulled toward a trooper behind a parked car: the round would hit the car): the nearest one with a clear line wins, at most LOS_CHECKS rays a frame.
func find(origin: Vector3, dir: Vector3, los_from := Vector3.INF) -> Dictionary:
	var cands: Array[Dictionary] = []
	for e in get_tree().get_nodes_in_group(&"enemy"):
		var n := e as Node3D
		if n == null or not n.has_method(&"center") or n.get(&"dead") == true:
			continue
		var c: Vector3 = n.call(&"center")
		var to := c - origin
		var d := to.length()
		if d < 1.0 or d > RANGE or to.dot(dir) <= 0.0:
			continue
		var r := maxf(float(n.get(&"radius")) if n.get(&"radius") != null else 0.5, 0.3)
		var rad_ang := atan(r / d)
		var ang := dir.angle_to(to / d)
		if ang < CONE * cone_scale() * (PAD_CONE if ControllerInput.stick_aim else 1.0) + rad_ang:
			var flat_dir := Vector2(dir.x, dir.z)
			var flat_to := Vector2(to.x, to.z)
			var yaw_err := flat_dir.angle_to(flat_to) if flat_dir.length() > 0.001 and flat_to.length() > 0.001 else 0.0
			var pitch_err := asin(clampf(to.y / d, -1.0, 1.0)) - asin(clampf(dir.y, -1.0, 1.0))
			cands.append({"node": n, "ang": ang, "rad_ang": rad_ang, "yaw_err": yaw_err, "pitch_err": pitch_err, "center": c})
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["ang"]) < float(b["ang"]))
	var checks := 0
	for cd in cands:
		if los_from.is_finite() and _p != null and _p.is_inside_tree():
			if checks >= LOS_CHECKS:
				break
			checks += 1
			if not clear_line(los_from, cd["center"], cd["node"]):
				continue
		cd.erase("center")
		return cd
	return {}


## Nothing of the world or of a vehicle (the hero's own car excepted) between `from` and `to`: the way a round flies. `who` (the target) is ignored.
func clear_line(from: Vector3, to: Vector3, _who: Node3D = null) -> bool:
	var mask := Game.L_WORLD
	if _p == null or _p.get(&"vehicle") == null:
		mask |= Game.L_VEHICLE
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	return _p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _process(dt: float) -> void:
	on_target = false
	aim_zone = &""
	target = null
	var rig: CameraRig = _p.camera_rig if _p != null else null
	if rig == null:
		return
	rig.look_scale = 1.0
	if not Game.is_playing() or _p.weapon == null or not applies_to(_p.weapon.current):
		return
	var aim := _p.get_aim()
	var f := find(aim["origin"], aim["dir"], aim["start"])
	if f.is_empty():
		return
	target = f["node"]
	var zh := HitZones.of(target, aim["start"], aim["dir"])               # exactly the test a shot makes (zero spread): the real body shape, the world in the way
	on_target = not zh.is_empty() and float(zh["t"]) <= (aim["start"] as Vector3).distance_to(aim["hit"]) + 0.05
	if on_target:
		aim_zone = zh["zone"]
	if not enabled:
		return
	var rad_ang: float = f["rad_ang"]
	var pad := ControllerInput.stick_aim
	rig.look_scale = slow_factor(f["ang"], rad_ang, pad)
	if Input.is_action_pressed(&"fire") or Input.is_action_pressed(&"aim"):
		# yaw_err is the 2D (x,z) angle, which runs opposite to the Node3D yaw
		rig.yaw -= pull(f["yaw_err"], f["ang"], rad_ang, dt, pad)
		rig.pitch = clampf(rig.pitch + pull(f["pitch_err"], f["ang"], rad_ang, dt, pad), CameraRig.PITCH_MIN, CameraRig.PITCH_MAX)


## True when auto-fire should hold the trigger this frame.
func wants_auto_fire() -> bool:
	return auto_fire and on_target and _p != null and _p.weapon != null and applies_to(_p.weapon.current)


static func stagger_for(weapon_id: StringName) -> float:
	return float(STAGGER.get(weapon_id, 0.4))
