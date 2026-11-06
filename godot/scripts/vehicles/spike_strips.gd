class_name SpikeStrips
extends Node3D
## Police spike strips: a flat dark bar of teeth across the road, laid ahead of a fleeing hero by the pursuit ladder (VehicleManager._tick_cops, from COP_SPIKE_HEAT). Two pooled bars
## of one shared mesh; any car that is not a police car and rolls over one has its tyres shot (Vehicle.blow_tires) and the bar is used up. Simulates only while Game.is_playing().

const POOL := 2

var laid := 0                          ## strips laid so far (tests, stats)
var hits := 0                          ## cars that drove into one
var _bars: Array[Node3D] = []
var _life: Array[float] = []
var _mgr: VehicleManager


func _ready() -> void:
	_mgr = get_parent() as VehicleManager
	var bm := BoxMesh.new()
	bm.size = Vector3(VehicleSpecs.SPIKE_HALF_WIDTH * 2.0, 0.12, VehicleSpecs.SPIKE_HALF_DEPTH * 2.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.11)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.1)
	mat.emission_energy_multiplier = 1.4
	bm.material = mat
	for i in POOL:
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_bars.append(mi)
		_life.append(0.0)


## Lay a strip centred on `pos`, its long side across `dir` (the direction of travel). Reuses the oldest bar when both are out. Returns the bar.
func lay(pos: Vector3, dir: Vector3) -> Node3D:
	var k := 0
	var oldest := INF
	for i in POOL:
		if _life[i] <= 0.0:
			k = i
			break
		if _life[i] < oldest:
			oldest = _life[i]
			k = i
	var b := _bars[k]
	b.visible = true
	b.global_position = Vector3(pos.x, 0.07, pos.z)
	b.rotation = Vector3(0.0, atan2(-dir.x, -dir.z), 0.0)
	_life[k] = VehicleSpecs.SPIKE_LIFE
	laid += 1
	return b


func active_count() -> int:
	var n := 0
	for i in POOL:
		if _life[i] > 0.0:
			n += 1
	return n


func clear() -> void:
	for i in POOL:
		_life[i] = 0.0
		_bars[i].visible = false


func _physics_process(dt: float) -> void:
	if not Game.is_playing() or _mgr == null:
		return
	for i in POOL:
		if _life[i] <= 0.0:
			continue
		_life[i] -= dt
		var b := _bars[i]
		if _life[i] <= 0.0:
			b.visible = false
			continue
		for v in _mgr.list:
			if not v.active or v.dead or v.cop or v.tires_flat > 0.0 or v.cls != &"car" and v.cls != &"bike":
				continue
			if absf(v.speed) < 2.0:
				continue
			var d := v.global_position - b.global_position
			var along := d.dot(-b.global_transform.basis.z)
			var across := d.dot(b.global_transform.basis.x)
			if absf(along) < VehicleSpecs.SPIKE_HALF_DEPTH + float(v.spec["len"]) * 0.3 and absf(across) < VehicleSpecs.SPIKE_HALF_WIDTH:
				v.blow_tires()
				hits += 1
				_life[i] = 0.0
				b.visible = false
				break
