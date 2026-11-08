class_name EnemyGrenades
extends Node3D
## Enemy grenades you can SEE (real-fight wave): a trooper of the grenadier look lobs one at the hero from 9-26 m. A glowing ball flies in a high arc (about 1 s), a red ring on the street
## shows where it lands, as wide as the blast, and burns down over the fuse; at the end Game.explode hurts what is inside (the hero, cars) and throws the colourful blast. At most
## `max_live()` in flight per tier (LOW 1, MED 1, HIGH 2), 2 pooled slots, no node is created in play. Pure maths (`arc_point`, `flight_time`, `lead_point`) are static for tests.
## Nothing runs unless a grenade is live (physics process off), and it pauses with Game.state like everything else.

const SHADER := preload("res://assets/shaders/fx_grenade_ring.gdshader")
const SLOTS := 2
const RADIUS := 3.6                       ## blast radius (TacticsTable.FLUSH_RADIUS)
const FUSE_AFTER := 0.85                  ## seconds on the ground before it blows
const DAMAGE := 16.0                      ## the hero's damage at the centre (EASY mode scales it further down)
const SPEED := 13.0                       ## horizontal metres per second of the throw
const FLIGHT := Vector2(0.7, 1.35)
const LEAD := 0.55                        ## how much of the hero's walking the aim leads (he can run out of it: that is the game)

signal landed(at: Vector3)
signal exploded(at: Vector3)

var thrown := 0
var blasts := 0
var last_to := Vector3.INF

var _slots: Array[Dictionary] = []       ## {node, ball, ring, mat, live, t, T, from, to, h, fuse}


static func max_live(tier: int) -> int:
	return 2 if tier >= 2 else 1


static func flight_time(dist: float) -> float:
	return clampf(dist / SPEED, FLIGHT.x, FLIGHT.y)


## The point on the throw arc at `t` 0..1: a straight line plus a parabola `h` metres high at the middle.
static func arc_point(from: Vector3, to: Vector3, h: float, t: float) -> Vector3:
	var p := from.lerp(to, t)
	p.y += 4.0 * h * t * (1.0 - t)
	return p


## Where to aim: the hero's position plus a part of his walking over the flight time, on the ground.
static func lead_point(hero: Vector3, vel: Vector3, flight: float) -> Vector3:
	var q := hero + Vector3(vel.x, 0.0, vel.z) * flight * LEAD
	return q


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	set_physics_process(false)
	for i in SLOTS:
		var n := Node3D.new()
		n.visible = false
		add_child(n)
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.15
		sm.height = 0.3
		sm.radial_segments = 8
		sm.rings = 4
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.albedo_color = Color(1.0, 0.55, 0.15)
		bm.emission_enabled = true
		bm.emission = Color(1.0, 0.4, 0.1)
		bm.emission_energy_multiplier = 3.0
		sm.material = bm
		ball.mesh = sm
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(ball)
		var ring := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2.ONE * RADIUS * 2.0 * 1.1
		qm.orientation = PlaneMesh.FACE_Y
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		qm.material = mat
		ring.mesh = qm
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.top_level = true
		n.add_child(ring)
		_slots.append({"node": n, "ball": ball, "ring": ring, "mat": mat, "live": false, "t": 0.0, "T": 1.0, "from": Vector3.ZERO, "to": Vector3.ZERO, "h": 3.0, "landed": false})


func live_count() -> int:
	var n := 0
	for s in _slots:
		if bool(s["live"]):
			n += 1
	return n


## Throw from `from` to `to` (a ground point). False when every slot is in use or the tier's limit is reached.
func throw(from: Vector3, to: Vector3) -> bool:
	if live_count() >= max_live(Game.quality):
		return false
	for s in _slots:
		if bool(s["live"]):
			continue
		var dist := Vector2(to.x - from.x, to.z - from.z).length()
		s["live"] = true
		s["t"] = 0.0
		s["T"] = flight_time(dist)
		s["from"] = from
		s["to"] = to
		s["h"] = 2.4 + dist * 0.09
		s["landed"] = false
		(s["node"] as Node3D).visible = true
		(s["ball"] as MeshInstance3D).global_position = from
		(s["ring"] as MeshInstance3D).global_position = to + Vector3(0.0, 0.06, 0.0)
		(s["mat"] as ShaderMaterial).set_shader_parameter(&"k", 0.0)
		thrown += 1
		last_to = to
		set_physics_process(true)
		Sfx.play_at(&"enemy_shot", from, -3.0, 0.7)
		return true
	return false


func clear() -> void:
	for s in _slots:
		s["live"] = false
		(s["node"] as Node3D).visible = false
	set_physics_process(false)


func _physics_process(dt: float) -> void:
	if not Game.is_playing():
		return
	var any := false
	for s in _slots:
		if not bool(s["live"]):
			continue
		any = true
		s["t"] = float(s["t"]) + dt
		var t: float = s["t"]
		var T: float = s["T"]
		var ball := s["ball"] as MeshInstance3D
		var mat := s["mat"] as ShaderMaterial
		if t < T:
			ball.global_position = arc_point(s["from"], s["to"] + Vector3(0.0, 0.15, 0.0), float(s["h"]), t / T)
			mat.set_shader_parameter(&"k", 0.45 * t / (T + FUSE_AFTER))
		else:
			if not bool(s["landed"]):
				s["landed"] = true
				ball.global_position = (s["to"] as Vector3) + Vector3(0.0, 0.15, 0.0)
				landed.emit(s["to"])
				Sfx.play_at(&"impact_metal", s["to"], -8.0, 1.4)
			var k := (t - T) / FUSE_AFTER
			mat.set_shader_parameter(&"k", 0.45 + 0.55 * clampf(k, 0.0, 1.0))
			ball.scale = Vector3.ONE * (1.0 + 0.5 * absf(sin(t * 30.0)))
			if k >= 1.0:
				_blast(s)
	if not any:
		set_physics_process(false)


func _blast(s: Dictionary) -> void:
	s["live"] = false
	(s["node"] as Node3D).visible = false
	(s["ball"] as MeshInstance3D).scale = Vector3.ONE
	blasts += 1
	var at: Vector3 = s["to"]
	Game.explode(at + Vector3(0.0, 0.2, 0.0), RADIUS, {"enemy_dmg": 0.0, "car_dmg": 12.0, "player_dmg": DAMAGE, "color": Color(1.0, 0.55, 0.15)})
	exploded.emit(at)
