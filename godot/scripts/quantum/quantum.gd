class_name Quantum
extends Node
## The quantum toolkit, child of the Player (Player._attach_quantum, exposed as `player.quantum`). Port of src/quantum.js. Contract: ARCHITECTURE.md "quantum".
##   BLINK       blink action: first press throws a Bell-pair beacon at the aimed point (<= 48 m, dropped onto the floor or roof, 8 s), the second press teleports
##               there (Player.teleport_to). Alice's two classical bits m0 m1 are drawn at random; Bob applies X when m1 = 1, then Z when m0 = 1 (nothing for 00).
##   ENTANGLE    entangle action: the aimed drone (generous aim assist) and the nearest free drone within 45 m are linked for 9 s: damage to one is mirrored to
##               the other (Drone.linked, damage(..., mirrored = true)); a beam joins them and both become aware.
##   SUPERPOSE   superpose action: leaves a ghost clone (6 s, group "clone", the enemies shoot at it half of the time and collapse it when it is hit);
##               the player runs 30 % faster while it exists. Pressing again, expiry or a hit collapses it into Game.explode (r 9, 70 enemy / 40 car damage).
## Everything is pooled: the beacon, the ghost (the player's own meshes under one shared hologram material, no lights) and the link beams are built once and
## only shown or hidden. All simulation and input reading happens only while Game.is_playing(). The three timers, the energy costs and the cooldowns are
## the prototype's. Graphics tiers (Game.quality): the number of simultaneous links (LOW 1, MED 2, HIGH 3), the particle counts, and LOW drops the glow sprite,
## the second ring, the ghost's ground ring and the second beam of a link.

const CYAN := Color(0.3, 0.94, 1.0)
const MAGENTA := Color(1.0, 0.24, 0.94)
const PALE := Color(0.62, 0.98, 1.0)

const BLINK_COST := 15.0
const BLINK_CD := 0.3
const TELEPORT_CD := 0.4
const BLINK_RANGE := 48.0
const BEACON_LIFE := 8.0
const LINK_COST := 25.0
const LINK_CD := 0.8
const LINK_RANGE := 70.0            ## how far the aimed drone may be
const LINK_PARTNER := 45.0          ## the second drone must be this close to the first (metres, on the ground plane)
const LINK_LIFE := 9.0
const AIM_ASSIST := 1.7             ## multiplier on a drone's hit radius for choosing the first target
const SUPER_COST := 35.0
const SUPER_LIFE := 6.0
const COLLAPSE_CD := 1.5
const SUPER_SPEED := 1.3
const BLAST_RADIUS := 9.0
const BITS_SHOWN := 5.0             ## seconds the HUD keeps the Alice / Bob readout after a teleport
const MAX_LINKS := [1, 2, 3]        ## per graphics tier
const FX_SCALE := [0.5, 0.8, 1.0]   ## particle count factor per graphics tier
const MAX_GHOST_PARTS := 16

## The hologram look of the ghost: a Fresnel rim, scan lines running up the body, additive, unshaded (so it needs no light and works in every renderer).
const GHOST_SHADER := "shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 tint : source_color = vec3(0.3, 0.94, 1.0);
uniform float gain = 1.0;
varying float wy;
void vertex() { wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y; }
void fragment() {
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	float scan = 0.7 + 0.3 * sin(wy * 38.0 - TIME * 7.0);
	ALBEDO = tint * (0.32 + f * 1.5) * scan * gain;
	ALPHA = clamp(0.42 + f * 0.6, 0.0, 1.0);
}
"

static var _mat_cyan: StandardMaterial3D
static var _mat_magenta: StandardMaterial3D
static var _mat_pale: StandardMaterial3D
static var _mat_glow: StandardMaterial3D
static var _mat_ghost: ShaderMaterial
static var _glow_tex: GradientTexture2D

# --- public state (read by the HUD, the minimap and the enemies) ---------------------------------------------------------
var has_beacon := false
var beacon_pos := Vector3.ZERO
var beacon_left := 0.0
var clone: Node3D = null               ## the ghost while it exists (group "clone"), else null
var clone_left := 0.0
var cd_blink := 0.0
var cd_link := 0.0
var cd_super := 0.0
var links: Array = []                  ## {a: Drone, b: Drone, t: float (seconds left), slot: int}
## The last teleport: Alice's classical bits and Bob's correction, kept for the HUD for BITS_SHOWN seconds.
var last_m0 := 0
var last_m1 := 0
var last_fix := ""                     ## "" before the first teleport, else NOTHING / X / Z / X THEN Z
var bits_left := 0.0
var fx_root: Node3D                    ## top-level parent of every visual of this module

var _p: Player
var _rich := true                      ## MED / HIGH: glow sprite, second ring, ghost ring and second beam
var _clock := 0.0
var _rq := PhysicsRayQueryParameters3D.new()
var _ring: MeshInstance3D
var _ring2: MeshInstance3D
var _pillar: MeshInstance3D
var _core: MeshInstance3D
var _glow: MeshInstance3D
var _ghost: Node3D
var _ghost_ring: MeshInstance3D
var _ghost_meshes: Array[MeshInstance3D] = []
var _beams: Array[MeshInstance3D] = []  ## two per link slot
var _slot_used: Array[bool] = []


func _ready() -> void:
	_p = get_parent() as Player
	_rq.collision_mask = Game.L_WORLD
	_build_visuals()
	Game.new_game.connect(reset)
	Game.respawn.connect(reset)
	Game.next_sector.connect(reset)
	Game.quality_changed.connect(_on_quality)
	_on_quality(Game.quality)


func _exit_tree() -> void:
	reset()


# ---------------------------------------------------------------------------------------------------------------------
# simulation
# ---------------------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _p == null or not Game.is_playing():
		return
	cd_blink = maxf(cd_blink - delta, 0.0)
	cd_link = maxf(cd_link - delta, 0.0)
	cd_super = maxf(cd_super - delta, 0.0)
	bits_left = maxf(bits_left - delta, 0.0)
	if Input.is_action_just_pressed(&"blink"):
		blink()
	if Input.is_action_just_pressed(&"entangle"):
		entangle()
	if Input.is_action_just_pressed(&"superpose"):
		superpose()
	if has_beacon:
		beacon_left -= delta
		if beacon_left <= 0.0:
			_remove_beacon()
	if clone != null:
		clone_left -= delta
		if clone_left <= 0.0:
			collapse()
	var i := links.size() - 1
	while i >= 0:
		var l: Dictionary = links[i]
		l["t"] = float(l["t"]) - delta
		var a: Drone = l["a"]
		var b: Drone = l["b"]
		if float(l["t"]) <= 0.0 or not _alive(a) or not _alive(b) or a.linked != b or b.linked != a:
			_drop_link(i)
		i -= 1


func _alive(d: Drone) -> bool:
	return is_instance_valid(d) and not d.dead and d.active


## Beacon, link and clone state back to idle (new game, respawn, next sector, leaving the tree). Nothing explodes.
func reset() -> void:
	_remove_beacon()
	var i := links.size() - 1
	while i >= 0:
		_drop_link(i)
		i -= 1
	_kill_clone()
	cd_blink = 0.0
	cd_link = 0.0
	cd_super = 0.0
	bits_left = 0.0
	last_fix = ""
	last_m0 = 0
	last_m1 = 0


func _on_quality(level: int) -> void:
	_rich = level > 0
	while links.size() > _max_links():
		_drop_link(0)


func _max_links() -> int:
	return MAX_LINKS[clampi(Game.quality, 0, 2)]


func _fx_count(n: int) -> int:
	return maxi(2, int(round(n * float(FX_SCALE[clampi(Game.quality, 0, 2)]))))


# --- blink -----------------------------------------------------------------------------------------------------------

## Throws the beacon at the aimed point, or teleports to it when one is out. Returns true when something happened.
func blink() -> bool:
	if _p == null or not Game.is_playing() or _p.is_dead():
		return false
	if _p.vehicle != null:
		Game.say("BLINK OFFLINE IN VEHICLE", 1.2)
		return false
	if has_beacon:
		return teleport()
	if cd_blink > 0.0:
		return false
	if _p.energy < BLINK_COST:
		Game.say("NOT ENOUGH COHERENCE", 1.0)
		return false
	beacon_pos = _aim_floor_point()
	has_beacon = true
	beacon_left = BEACON_LIFE
	_p.energy -= BLINK_COST
	cd_blink = BLINK_CD
	_show_beacon()
	FX.burst(beacon_pos + Vector3(0.0, 0.5, 0.0), CYAN, _fx_count(14), 4.0, 0.5, 0.0)
	Sfx.play(&"link")
	Game.say("BELL-PAIR BEACON PLACED · BLINK AGAIN TO TELEPORT", 1.6)
	return true


## Where the beacon lands: along the camera ray (stopping 0.6 m short of a wall, 48 m at most), then down onto whatever is below (floor, roof, ledge).
func _aim_floor_point() -> Vector3:
	var aim := _p.get_aim()
	var o: Vector3 = aim["origin"]
	var d: Vector3 = aim["dir"]
	var t := o.distance_to(aim["hit"] as Vector3)
	var reach := BLINK_RANGE + Upgrades.blink_bonus()
	var pt := o + d * (maxf(0.0, t - 0.6) if t < reach else reach)
	pt = PlayerUtil.safe_spot(pt, Game.world if is_instance_valid(Game.world) else null)      # inside the walls, not in a building volume (sky / horizon / off-map aims)
	_rq.from = pt + Vector3(0.0, 0.5, 0.0)
	_rq.to = pt + Vector3(0.0, -150.0, 0.0)
	var res := _p.get_world_3d().direct_space_state.intersect_ray(_rq)
	pt.y = (res["position"] as Vector3).y if not res.is_empty() else 0.0
	return pt


## Second press: move the player onto the beacon and show Alice's bits and Bob's correction.
func teleport() -> bool:
	if not has_beacon or _p == null:
		return false
	var from := _p.global_position + Vector3(0.0, 1.0, 0.0)
	var dest := beacon_pos
	var to := dest + Vector3(0.0, 1.0, 0.0)
	FX.tracer(from, to, CYAN)
	FX.burst(from, CYAN, _fx_count(40), 7.0, 0.6, 0.0)
	_p.teleport_to(dest + Vector3(0.0, 0.05, 0.0))
	FX.burst(to, MAGENTA, _fx_count(40), 7.0, 0.6, 0.0)
	if _rich:
		FX.blast(to, 2.5, MAGENTA, 0.35)
	FX.shake(0.35)
	Sfx.play(&"blink")
	last_m0 = randi() & 1
	last_m1 = randi() & 1
	last_fix = fix_for(last_m0, last_m1)
	bits_left = BITS_SHOWN
	Game.say("TELEPORTED · ALICE BITS %d%d → BOB APPLIES %s" % [last_m0, last_m1, last_fix], 2.0)
	_remove_beacon()
	cd_blink = TELEPORT_CD
	return true


## Bob's correction for Alice's classical bits (teleportation protocol): m1 = 1 means X, m0 = 1 means Z, X first.
static func fix_for(m0: int, m1: int) -> String:
	if m1 == 1 and m0 == 1:
		return "X THEN Z"
	if m1 == 1:
		return "X"
	if m0 == 1:
		return "Z"
	return "NOTHING"


func _remove_beacon() -> void:
	has_beacon = false
	beacon_left = 0.0
	if fx_root != null:
		for n: Node3D in [_ring, _ring2, _pillar, _core, _glow]:
			n.visible = false


# --- entangle --------------------------------------------------------------------------------------------------------

## Links the drone under the crosshair with the nearest free drone within 45 m. Returns true when a link was made.
func entangle() -> bool:
	if _p == null or not Game.is_playing() or _p.is_dead() or cd_link > 0.0:
		return false
	if _p.energy < LINK_COST:
		Game.say("NOT ENOUGH COHERENCE", 1.0)
		return false
	var mgr := Game.enemies
	if not is_instance_valid(mgr):
		Game.say("NO TARGET IN SIGHT", 1.0)
		return false
	var list: Array = mgr.get("list")
	var aim := _p.get_aim()
	var o: Vector3 = aim["origin"]
	var dir: Vector3 = aim["dir"]
	var best := minf(o.distance_to(aim["hit"] as Vector3), LINK_RANGE)
	var a: Drone = null
	for e: Variant in list:
		var d := e as Drone
		if d == null or not _alive(d) or d.linked != null:
			continue
		var r := _ray_sphere(o, dir, d.center(), d.radius * AIM_ASSIST)
		if r < best:
			best = r
			a = d
	if a == null:
		Game.say("NO TARGET IN SIGHT", 1.0)
		return false
	var b: Drone = null
	var bd := LINK_PARTNER
	for e: Variant in list:
		var d := e as Drone
		if d == null or d == a or not _alive(d) or d.linked != null:
			continue
		var dd := Vector2(d.global_position.x - a.global_position.x, d.global_position.z - a.global_position.z).length()
		if dd < bd:
			bd = dd
			b = d
	if b == null:
		Game.say("NEED A SECOND TARGET WITHIN 45 m", 1.4)
		return false
	_p.energy -= LINK_COST
	cd_link = LINK_CD
	while links.size() >= _max_links():
		_drop_link(0)
	a.linked = b
	b.linked = a
	a.aware = true
	b.aware = true
	var slot := _free_slot()
	_slot_beams(slot)
	links.append({"a": a, "b": b, "t": LINK_LIFE, "slot": slot})
	_animate_link(links[links.size() - 1])
	for d: Drone in [a, b]:
		FX.burst(d.center(), PALE, _fx_count(18), 5.0, 0.5, 0.0)
	Sfx.play(&"link")
	Game.say("ENTANGLED · DAMAGE IS SHARED ACROSS DISTANCE", 1.8)
	return true


## Distance along the unit ray (o, d) to the sphere, INF when it is missed or behind.
static func _ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var oc := c - o
	var tca := oc.dot(d)
	if tca < 0.0:
		return INF
	var h2 := oc.length_squared() - tca * tca
	if h2 > r * r:
		return INF
	return maxf(tca - sqrt(r * r - h2), 0.0)


func _free_slot() -> int:
	for i in _slot_used.size():
		if not _slot_used[i]:
			return i
	_slot_used.append(false)
	return _slot_used.size() - 1


func _slot_beams(slot: int) -> void:
	_slot_used[slot] = true
	while _beams.size() < (slot + 1) * 2:
		var thick := _beams.size() % 2 == 0
		var m := FX.make_beam(Color(0.25, 0.9, 1.0) if thick else Color(1.0, 0.3, 0.9), 0.14 if thick else 0.06)
		fx_root.add_child(m)
		_beams.append(m)


func _drop_link(i: int) -> void:
	var l: Dictionary = links[i]
	links.remove_at(i)
	var a: Variant = l["a"]
	var b: Variant = l["b"]
	if is_instance_valid(a) and (a as Drone).linked == b:
		(a as Drone).linked = null
	if is_instance_valid(b) and (b as Drone).linked == a:
		(b as Drone).linked = null
	var slot: int = l["slot"]
	_slot_used[slot] = false
	_beams[slot * 2].visible = false
	_beams[slot * 2 + 1].visible = false


# --- superposition -----------------------------------------------------------------------------------------------------

## Leaves the ghost (or, with one out, collapses it). Returns true when something happened.
func superpose() -> bool:
	if _p == null or not Game.is_playing() or _p.is_dead():
		return false
	if clone != null:
		collapse()
		return true
	if _p.vehicle != null:
		Game.say("SUPERPOSITION OFFLINE IN VEHICLE", 1.2)
		return false
	if cd_super > 0.0:
		return false
	if _p.energy < SUPER_COST:
		Game.say("NOT ENOUGH COHERENCE", 1.0)
		return false
	_p.energy -= SUPER_COST
	_make_clone()
	_p.speed_boost = SUPER_SPEED
	FX.burst(_p.global_position + Vector3(0.0, 1.0, 0.0), Color(0.4, 1.0, 0.93), _fx_count(30), 5.0, 0.6, 0.0)
	Sfx.play(&"superpos")
	Game.say("SUPERPOSITION · ENEMIES SEE TWO OF YOU · BE FAST", 1.8)
	return true


## The decoy collapses into a damaging blast. Called by the player (second press), the timer and the enemies (their bolts hit the ghost).
func collapse() -> void:
	if clone == null:
		return
	var pos := clone.global_position
	_kill_clone()
	cd_super = COLLAPSE_CD
	Game.explode(pos + Vector3(0.0, 1.0, 0.0), BLAST_RADIUS, {"enemy_dmg": 70.0, "car_dmg": 40.0, "player_dmg": 0.0, "color": Color(0.4, 1.0, 0.93)})
	Game.say("WAVEFUNCTION COLLAPSE", 1.4)


## Takes the ghost down without a blast and gives the player his normal speed back.
func _kill_clone() -> void:
	if clone == null:
		return
	if clone.is_in_group(&"clone"):
		clone.remove_from_group(&"clone")
	clone.visible = false
	clone = null
	clone_left = 0.0
	if _ghost_ring != null:
		_ghost_ring.visible = false
	if _p != null and _p.speed_boost == SUPER_SPEED:
		_p.speed_boost = 1.0


## The ghost is the player's own meshes (one per body part, in the pose of this moment) under one shared hologram material.
func _make_clone() -> void:
	var xf := Transform3D(Basis(Vector3.UP, _p.yaw), _p.global_position)
	_ghost.global_transform = xf
	var inv := xf.affine_inverse()
	var parts: Array = _p.body.get("_parts") if _p.body != null else []
	var n := 0
	for part: Variant in parts:
		var mi := part as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_inside_tree() or n >= MAX_GHOST_PARTS:
			continue
		var g := _ghost_mesh(n)
		g.mesh = mi.mesh
		g.transform = inv * mi.global_transform
		g.visible = true
		n += 1
	if n == 0:                       # no model parts (a stripped-down player): a plain capsule stands in
		var g := _ghost_mesh(0)
		var cap := CapsuleMesh.new()
		cap.radius = 0.3
		cap.height = 1.7
		g.mesh = cap
		g.position = Vector3(0.0, 0.85, 0.0)
		g.visible = true
		n = 1
	for i in range(n, _ghost_meshes.size()):
		_ghost_meshes[i].visible = false
	_ghost.visible = true
	_animate_clone()
	_ghost.add_to_group(&"clone")
	clone = _ghost
	clone_left = SUPER_LIFE


func _ghost_mesh(i: int) -> MeshInstance3D:
	while _ghost_meshes.size() <= i:
		var m := MeshInstance3D.new()
		m.material_override = _mat_ghost
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		_ghost.add_child(m)
		_ghost_meshes.append(m)
	return _ghost_meshes[i]


# ---------------------------------------------------------------------------------------------------------------------
# visuals (built once, animated while something is out)
# ---------------------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if fx_root == null or not Game.is_playing():
		return
	_clock += delta
	if has_beacon:
		_animate_beacon()
	if clone != null:
		_animate_clone()
	for l: Dictionary in links:
		_animate_link(l)


func _show_beacon() -> void:
	_animate_beacon()


func _animate_beacon() -> void:
	var c := _clock
	var bx := beacon_pos.x
	var bz := beacon_pos.z
	var by := beacon_pos.y
	var s1 := 1.0 + 0.12 * sin(c * 4.0)
	_ring.position = Vector3(bx, by + 0.15, bz)
	_ring.scale = Vector3(s1, 1.0, s1)
	var k := fposmod(c * 0.9, 1.0)                       # the second ring climbs the pillar and shrinks
	_ring2.position = Vector3(bx, by + 0.2 + k * 3.2, bz)
	var s2 := 1.0 - 0.6 * k
	_ring2.scale = Vector3(s2, 1.0, s2)
	_pillar.position = Vector3(bx, by + 5.0, bz)
	_core.position = Vector3(bx, by + 1.2 + sin(c * 3.0) * 0.2, bz)
	_core.rotation.y = c * 3.0
	_glow.position = Vector3(bx, by + 1.0, bz)
	var s3 := 1.0 + 0.15 * sin(c * 5.0)
	_glow.scale = Vector3(s3, s3, s3)
	var shown := beacon_left > 1.5 or int(floor(c * 8.0)) % 2 == 0     # blinks in its last 1.5 s
	for n: Node3D in [_ring, _pillar, _core]:
		n.visible = shown
	_ring2.visible = shown and _rich
	_glow.visible = shown and _rich


func _animate_clone() -> void:
	var c := _clock
	_ghost.visible = clone_left > 1.0 or int(floor(c * 10.0)) % 2 == 0
	_ghost_ring.visible = _ghost.visible and _rich
	var s := 1.0 + 0.15 * sin(c * 5.0)
	_ghost_ring.position = _ghost.position + Vector3(0.0, 0.05, 0.0)
	_ghost_ring.scale = Vector3(s, 1.0, s)


func _animate_link(l: Dictionary) -> void:
	var a: Drone = l["a"]
	var b: Drone = l["b"]
	if not is_instance_valid(a) or not is_instance_valid(b):
		return
	var slot: int = l["slot"]
	var pulse := 0.6 + 0.4 * sin(_clock * 12.0)
	var left := float(l["t"])
	var flicker := left > 1.5 or int(floor(_clock * 8.0)) % 2 == 0
	var b1 := _beams[slot * 2]
	var b2 := _beams[slot * 2 + 1]
	var ca := a.center()
	var cb := b.center()
	FX.place_beam(b1, ca, cb)
	b1.visible = b1.visible and flicker
	(b1.material_override as StandardMaterial3D).albedo_color = Color(0.25, 0.9, 1.0, pulse)
	if _rich:
		FX.place_beam(b2, ca, cb)
		b2.visible = b2.visible and flicker
		(b2.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.3, 0.9, 1.0 - pulse * 0.5)
	else:
		b2.visible = false


func _build_visuals() -> void:
	_build_materials()
	fx_root = Node3D.new()
	fx_root.name = "QuantumFx"
	fx_root.top_level = true
	add_child(fx_root)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.82
	torus.outer_radius = 0.98
	torus.rings = 24
	torus.ring_segments = 6
	_ring = _part(torus, _mat_cyan)
	var torus2 := TorusMesh.new()
	torus2.inner_radius = 1.32
	torus2.outer_radius = 1.46
	torus2.rings = 24
	torus2.ring_segments = 6
	_ring2 = _part(torus2, _mat_magenta)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.09
	cyl.height = 10.0
	cyl.radial_segments = 6
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	_pillar = _part(cyl, _mat_cyan)
	var oct := SphereMesh.new()                         # four segments and two rings make an octahedron
	oct.radius = 0.4
	oct.height = 0.8
	oct.radial_segments = 4
	oct.rings = 2
	_core = _part(oct, _mat_pale)
	var quad := QuadMesh.new()
	quad.size = Vector2(4.5, 4.5)
	_glow = _part(quad, _mat_glow)
	var ring3 := TorusMesh.new()
	ring3.inner_radius = 0.7
	ring3.outer_radius = 0.82
	ring3.rings = 20
	ring3.ring_segments = 5
	_ghost_ring = _part(ring3, _mat_cyan)
	_ghost = Node3D.new()
	_ghost.name = "QuantumClone"
	_ghost.visible = false
	fx_root.add_child(_ghost)
	for n: Node3D in [_ring, _ring2, _pillar, _core, _glow, _ghost_ring]:
		n.visible = false


func _part(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_root.add_child(m)
	return m


static func _additive(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.albedo_color = color
	return m


static func _build_materials() -> void:
	if _mat_cyan != null:
		return
	_mat_cyan = _additive(Color(CYAN, 0.9))
	_mat_magenta = _additive(Color(MAGENTA, 0.85))
	_mat_pale = _additive(Color(PALE, 0.7))
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 1.0, 1.0, 0.9))
	g.add_point(0.3, Color(1.0, 1.0, 1.0, 0.35))
	g.set_color(g.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
	_glow_tex = GradientTexture2D.new()
	_glow_tex.gradient = g
	_glow_tex.fill = GradientTexture2D.FILL_RADIAL
	_glow_tex.fill_from = Vector2(0.5, 0.5)
	_glow_tex.fill_to = Vector2(1.0, 0.5)
	_glow_tex.width = 64
	_glow_tex.height = 64
	_mat_glow = _additive(Color(CYAN, 0.8))
	_mat_glow.albedo_texture = _glow_tex
	_mat_glow.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mat_glow.billboard_keep_scale = true
	var sh := Shader.new()
	sh.code = GHOST_SHADER
	_mat_ghost = ShaderMaterial.new()
	_mat_ghost.shader = sh
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		_mat_ghost.set_shader_parameter(&"gain", 0.4)      # the Compatibility renderer's bloom and exposure make the same hologram far brighter
