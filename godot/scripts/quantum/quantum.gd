class_name Quantum
extends Node
## The quantum toolkit, child of the Player (Player._attach_quantum, exposed as `player.quantum`). Port of src/quantum.js. Contract: ARCHITECTURE.md "quantum".
##   BLINK       blink action: first press throws a Bell-pair beacon at the aimed point (<= 48 m, dropped onto the floor or roof, 8 s), the second press teleports
##               there (Player.teleport_to). Alice's two classical bits m0 m1 are drawn at random; Bob applies X when m1 = 1, then Z when m0 = 1 (nothing for 00).
##   ENTANGLE    entangle action: the aimed drone (generous aim assist) and the nearest free drone within 45 m are linked for 9 s: damage to one is mirrored to
##               the other (Drone.linked, damage(..., mirrored = true)); a beam joins them and both become aware.
##   SUPERPOSE   superpose action: leaves a ghost clone (6 s, group "clone", the enemies shoot at it half of the time and collapse it when it is hit);
##               the player runs 30 % faster while it exists. Pressing again, expiry or a hit collapses it into Game.explode (r 9, 70 enemy / 40 car damage).
##   COLLAPSE    collapse action: a shockwave around the player that collapses every quantum effect out at once: the decoy detonates (SUPERPOSITION combo),
##               the beacon bursts where it lies, every entangled pair takes heavy damage whatever the distance (ENTANGLE combo, mirrored), and all enemies in
##               WAVE_RADIUS take damage, stagger and are flipped off for a moment (drones stop thinking and shooting). Costs coherence, long cooldown.
## Everything is pooled: the beacon, the ghost (the player's own meshes under one shared hologram material, no lights) and the link beams are built once and
## only shown or hidden. All simulation and input reading happens only while Game.is_playing(). The three timers, the energy costs and the cooldowns are
## the prototype's. Graphics tiers (Game.quality): the number of simultaneous links (LOW 1, MED 2, HIGH 3), the particle counts, and LOW drops the glow sprite,
## the second ring, the ghost's ground ring and the second beam of a link.

signal verb_used(id: StringName)    ## a core verb fired: &"link" &"entangle" &"superposition" &"collapse" (the campaign's rift hold and convoy steps listen)

const CYAN := Color(0.3, 0.94, 1.0)
const MAGENTA := Color(1.0, 0.24, 0.94)
const PALE := Color(0.62, 0.98, 1.0)

const BLINK_COST := 15.0
const BLINK_CD := 0.3
const TELEPORT_CD := 0.4
const BLINK_RANGE := 48.0
const BEACON_LIFE := 8.0
const HOLD_AIM := 0.22              ## QUANTUM TELEPORT: a tap throws / uses the beacon, holding this long (game seconds) aims a destination, release teleports there
const SLOW_SCALE := 0.35            ## short slow motion while aiming and just after a teleport (Engine.time_scale factor, timed in real seconds)
const SLOW_AFTER := 0.25
const LINK_COST := 25.0
const LINK_CD := 0.8
const LINK_RANGE := 70.0            ## how far the aimed drone may be
const LINK_PARTNER := 45.0          ## the second drone must be this close to the first (metres, on the ground plane)
const LINK_LIFE := 9.0
const AIM_ASSIST := 1.7             ## multiplier on a drone's hit radius for choosing the first target
const SWAP_COST := 25.0
const SWAP_CD := 4.0
const SWAP_RANGE := 40.0
const SWAP_BEAM := 0.45
const SWAP_CONFUSE := 2.0            ## seconds of slowed, unaware drone after a swap
const SUPER_COST := 35.0
const SUPER_LIFE := 6.0
const COLLAPSE_CD := 1.5
const SUPER_SPEED := 1.3
const BLAST_RADIUS := 9.0
const WAVE_COST := 50.0
const WAVE_CD := 8.0
const WAVE_RADIUS := 16.0
const WAVE_DMG := 35.0              ## at the centre, 50 % at the rim
const WAVE_OFF := 2.5               ## seconds the drones stay switched off
const WAVE_LINK_DMG := 40.0         ## extra damage to each entangled pair (the link mirrors it to the partner)
const WAVE_BEACON_RADIUS := 7.0
const BITS_SHOWN := 5.0             ## seconds the HUD keeps the Alice / Bob readout after a teleport
const MAX_LINKS := [1, 2, 3]        ## per graphics tier
const FX_SCALE := [0.5, 0.8, 1.0]   ## particle count factor per graphics tier
const MAX_GHOST_PARTS := 16
const MAX_ECHOES := 2
const PULSE_RADIUS := 4.0           ## the small pulse when the decoy times out on its own (a manual or bolt collapse uses BLAST_RADIUS)
const PULSE_DMG := 25.0

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
	float flick = 0.8 + 0.2 * sin(TIME * 47.0 + wy * 3.0) * sin(TIME * 13.0);
	float seam = smoothstep(0.93, 1.0, sin(wy * 6.0 + TIME * 1.7));
	vec3 film = 0.5 + 0.5 * cos(6.2832 * (wy * 0.35 + f * 0.6 + TIME * 0.15 + vec3(0.0, 0.33, 0.67)));
	ALBEDO = mix(tint, film, 0.35 * f) * (0.32 + f * 1.5 + seam * 0.8) * scan * flick * gain;
	ALPHA = clamp(0.42 + f * 0.6, 0.0, 1.0);
}
"

static var _mat_cyan: StandardMaterial3D
static var _mat_magenta: StandardMaterial3D
static var _mat_pale: StandardMaterial3D
static var _mat_glow: StandardMaterial3D
static var _mat_ghost: ShaderMaterial
static var _glow_tex: Texture2D

# --- public state (read by the HUD, the minimap and the enemies) ---------------------------------------------------------
var has_beacon := false
var beacon_pos := Vector3.ZERO
var beacon_left := 0.0
var clone: Node3D = null               ## the ghost while it exists (group "clone"), else null
var clone_left := 0.0
var _boost := 0.0                      ## the speed boost SUPERPOSITION gave (SUPER_SPEED x skill tree), to take it back exactly
var _echoes: Array[MeshInstance3D] = []
var cd_blink := 0.0
var chain_left := 0                    ## QUANTUM TELEPORT hops still free in the current chain (HeroPower)
var _chain_t := 0.0
var aiming := false                    ## QUANTUM TELEPORT hold-to-aim: the destination marker follows the crosshair, release goes
var aim_pos := Vector3.ZERO
var fx_flash := 0.0                    ## screen effect strength 0..1 (HUD), 1 at the moment of a teleport, decays
var cd_link := 0.0
var cd_super := 0.0
var cd_collapse := 0.0
var collapse_fx := 0.0                 ## COLLAPSE screen effect strength 0..1 (HUD), decays
var _swap_a := Vector3.ZERO
var _swap_b := Vector3.ZERO
var _swap_left := 0.0
var _swap_beams: Array[MeshInstance3D] = []
var links: Array = []                  ## {a: Drone, b: Drone, t: float (seconds left), slot: int}
## The last teleport: Alice's classical bits and Bob's correction, kept for the HUD for BITS_SHOWN seconds.
var last_m0 := 0
var last_m1 := 0
var last_fix := ""                     ## "" before the first teleport, else NOTHING / X / Z / X THEN Z
var bits_left := 0.0
var fx_root: Node3D                    ## top-level parent of every visual of this module

var phase: PhaseThrough               ## phase-through thin walls during QUANTUM TELEPORT and the short phase-step
var _p: Player
var _rich := true                      ## MED / HIGH: glow sprite, second ring, ghost ring and second beam
var _clock := 0.0
var _hold := 0.0
var _holding := false
var _slow_until := 0
var _slow_base := 1.0
var _slow_on := false
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
	phase = PhaseThrough.new(_p)
	_build_visuals()
	Game.new_game.connect(reset)
	Game.respawn.connect(reset)
	Game.next_sector.connect(reset)
	Game.quality_changed.connect(_on_quality)
	Game.player_died.connect(_on_player_died)
	_on_quality(Game.quality)


func _exit_tree() -> void:
	if phase != null:
		phase.end()
	reset()


# ---------------------------------------------------------------------------------------------------------------------
# simulation
# ---------------------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _p == null or not Game.is_playing():
		return
	phase.tick(delta)
	cd_blink = maxf(cd_blink - delta, 0.0)
	_chain_t = maxf(_chain_t - delta, 0.0)
	cd_link = maxf(cd_link - delta, 0.0)
	cd_super = maxf(cd_super - delta, 0.0)
	cd_collapse = maxf(cd_collapse - delta, 0.0)
	bits_left = maxf(bits_left - delta, 0.0)
	_blink_input(delta)
	if Input.is_action_just_pressed(&"entangle") and entangle():
		GameFeel.fire(&"ability")
	if Input.is_action_just_pressed(&"superpose") and superpose():
		GameFeel.fire(&"ability")
	if Input.is_action_just_pressed(&"collapse") and collapse_all():
		GameFeel.fire(&"ability")
	if has_beacon:
		beacon_left -= delta
		if beacon_left <= 0.0:
			_remove_beacon()
	if clone != null:
		clone_left -= delta
		if clone_left <= 0.0:
			collapse(true)
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
	if phase != null:
		phase.end()
		phase.cd = 0.0
	cd_blink = 0.0
	cd_link = 0.0
	cd_super = 0.0
	_swap_left = 0.0
	bits_left = 0.0
	_holding = false
	_hold = 0.0
	aiming = false
	fx_flash = 0.0
	_slow_end()
	last_fix = ""
	last_m0 = 0
	last_m1 = 0


func _on_quality(level: int) -> void:
	_rich = level > 0
	while links.size() > _max_links():
		_drop_link(0)


func _max_links() -> int:
	return MAX_LINKS[clampi(Game.quality, 0, 2)] + SkillTree.extra_links()


func _fx_count(n: int) -> int:
	return maxi(2, int(round(n * float(FX_SCALE[clampi(Game.quality, 0, 2)]))))


# --- quantum teleport (hold to aim, release to go) -----------------------------------------------------------------------

## Tap (released before HOLD_AIM): the beacon throw / teleport of blink(). Hold: aim a destination (marker + slow motion), release teleports straight there.
func _blink_input(delta: float) -> void:
	if Input.is_action_just_pressed(&"blink"):
		_holding = true
		_hold = 0.0
	if not _holding:
		return
	if Input.is_action_pressed(&"blink"):
		_hold += delta
		if _hold >= HOLD_AIM and not has_beacon:
			if not aiming and not can_aim():
				_holding = false
				return
			aiming = true
			aim_pos = _aim_floor_point()
			beacon_pos = aim_pos
			_slow_begin(0.0)
			_animate_beacon()
	else:
		_holding = false
		if aiming:
			aim_go()
		else:
			blink()


func can_aim() -> bool:
	return _p != null and Game.is_playing() and not _p.is_dead() and _p.vehicle == null and cd_blink <= 0.0 and _p.energy >= HeroPower.cost(BLINK_COST) * SkillTree.cost_mult(&"teleport")


## Release of an aimed QUANTUM TELEPORT: go to the marker, pay the cost. Returns true when the teleport happened.
func aim_go() -> bool:
	var was := aiming
	aiming = false
	if not was or not can_aim():
		_remove_beacon()
		_slow_end()
		return false
	_p.energy -= HeroPower.cost(BLINK_COST) * SkillTree.cost_mult(&"teleport")
	beacon_pos = aim_pos
	has_beacon = true
	return teleport()


## Short phase-step (touch / key hook): pass thin walls for PhaseThrough.STEP_TIME.
func phase_step() -> bool:
	return phase.step()


func cancel_aim() -> void:
	if aiming:
		aiming = false
		_remove_beacon()
	_holding = false
	_slow_end()


func _slow_begin(after_real: float) -> void:
	if UiSettings.s_reduce_motion:
		return
	if not _slow_on:
		_slow_base = Engine.time_scale if Engine.time_scale > 0.0 else 1.0
		_slow_on = true
		Engine.time_scale = _slow_base * SLOW_SCALE
	_slow_until = Time.get_ticks_msec() + int(after_real * 1000.0) if after_real > 0.0 else 0


func _slow_end() -> void:
	if _slow_on:
		_slow_on = false
		Engine.time_scale = _slow_base
	_slow_until = 0


## A particle trail from the old position to the new one.
func _trail(from: Vector3, to: Vector3) -> void:
	FX.qvfx.teleport(from, to)                    # portals at both ends, tapered trail, dust, aura (scripts/fx/quantum_vfx.gd)


# --- blink -----------------------------------------------------------------------------------------------------------

## Throws the beacon at the aimed point, or teleports to it when one is out. Returns true when something happened.
func blink() -> bool:
	if _p == null or not Game.is_playing() or _p.is_dead():
		return false
	if _p.vehicle != null:
		Game.say("QUANTUM TELEPORT OFFLINE IN VEHICLE", 1.2)
		return false
	if has_beacon:
		return teleport()
	if cd_blink > 0.0:
		return false
	if _p.energy < HeroPower.cost(BLINK_COST) * SkillTree.cost_mult(&"teleport"):
		Game.say("NOT ENOUGH COHERENCE", 1.0)
		return false
	beacon_pos = _aim_floor_point()
	has_beacon = true
	beacon_left = BEACON_LIFE
	_p.energy -= HeroPower.cost(BLINK_COST) * SkillTree.cost_mult(&"teleport")
	cd_blink = HeroPower.cd(BLINK_CD)
	_show_beacon()
	FX.burst(beacon_pos + Vector3(0.0, 0.5, 0.0), CYAN, _fx_count(14), 4.0, 0.5, 0.0)
	Sfx.play(&"link")
	Game.say("TELEPORT MARKER SET · QUANTUM TELEPORT AGAIN TO GO", 1.6)
	return true


## Where the beacon lands: along the camera ray (stopping 0.6 m short of a wall, 48 m at most), then down onto whatever is below (floor, roof, ledge).
func _aim_floor_point() -> Vector3:
	var aim := _p.get_aim()
	var o: Vector3 = aim["origin"]
	var d: Vector3 = aim["dir"]
	var t := o.distance_to(aim["hit"] as Vector3)
	var reach := (BLINK_RANGE + Upgrades.blink_bonus()) * HeroPower.f("tp_range") * SkillTree.range_mult()
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
	phase.begin(PhaseThrough.TELEPORT_TIME)
	_p.teleport_to(dest + Vector3(0.0, 0.05, 0.0))
	Cinematics.first_time(&"teleporter_first")
	FX.burst(to, MAGENTA, _fx_count(40), 7.0, 0.6, 0.0)
	if _rich:
		FX.blast(to, 2.5, MAGENTA, 0.35)
	_trail(from, to)
	_skill_blink_damage(from, to)
	GameFeel.fire(&"teleport")
	PostFx2.pulse(1.0)
	fx_flash = 1.0
	aiming = false
	_slow_begin(SLOW_AFTER)
	Sfx.play(&"blink")
	last_m0 = randi() & 1
	last_m1 = randi() & 1
	last_fix = fix_for(last_m0, last_m1)
	bits_left = BITS_SHOWN
	Game.say("QUANTUM TELEPORT", 1.2)
	_remove_beacon()
	cd_blink = HeroPower.cd(TELEPORT_CD)
	if _chain_t > 0.0 and chain_left > 0:                  # chained hop (HeroPower tp_hops): no cooldown, the window keeps running
		chain_left -= 1
		cd_blink = 0.0
	else:
		chain_left = HeroPower.hops() + SkillTree.hops_extra() - 1
	_chain_t = HeroPower.CHAIN_WINDOW
	return true


## Skill tree: BLINK STRIKE hurts what stands at the arrival point, AFTERIMAGE what stood at the departure point.
func _skill_blink_damage(from: Vector3, to: Vector3) -> void:
	var strike := SkillTree.strike_damage()
	if strike > 0.0:
		Game.explode(to, 4.0, {"enemy_dmg": TestMode.damage(strike), "car_dmg": 0.0, "player_dmg": 0.0, "color": MAGENTA})
	var after := SkillTree.afterimage_damage()
	if after > 0.0:
		Game.explode(from, 3.5, {"enemy_dmg": TestMode.damage(after), "car_dmg": 0.0, "player_dmg": 0.0, "color": CYAN})


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
func link_drones() -> bool:
	if _p == null or not Game.is_playing() or _p.is_dead() or cd_link > 0.0:
		return false
	if _p.energy < HeroPower.cost(LINK_COST) * SkillTree.cost_mult(&"entangle"):
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
	_p.energy -= HeroPower.cost(LINK_COST) * SkillTree.cost_mult(&"entangle")
	cd_link = HeroPower.cd(LINK_CD)
	while links.size() >= _max_links():
		_drop_link(0)
	a.linked = b
	b.linked = a
	a.aware = true
	b.aware = true
	var slot := _free_slot()
	_slot_beams(slot)
	links.append({"a": a, "b": b, "t": LINK_LIFE + SkillTree.link_life(), "slot": slot})
	_animate_link(links[links.size() - 1])
	for d: Drone in [a, b]:
		FX.burst(d.center(), PALE, _fx_count(18), 5.0, 0.5, 0.0)
	Sfx.play(&"link")
	Game.say("ENTANGLED · DAMAGE IS SHARED ACROSS DISTANCE", 1.8)
	verb_used.emit(&"link")
	return true


# --- entangle (swap places) --------------------------------------------------------------------------------------------

## ENTANGLE: swap places with the enemy, car or pickup in the crosshair (SWAP_RANGE, line of sight). Returns true when the swap happened.
func entangle() -> bool:
	if _p == null or not Game.is_playing() or _p.is_dead() or cd_link > 0.0:
		return false
	if _p.vehicle != null:
		Game.say("ENTANGLE OFFLINE IN VEHICLE", 1.0)
		return false
	if _p.energy < HeroPower.cost(SWAP_COST) * SkillTree.cost_mult(&"entangle"):
		Game.say("NOT ENOUGH COHERENCE", 1.0)
		return false
	var t := swap_target()
	if t.is_empty():
		Game.say("NO TARGET IN SIGHT", 1.0)
		return false
	_p.energy -= HeroPower.cost(SWAP_COST) * SkillTree.cost_mult(&"entangle")
	cd_link = HeroPower.cd(SWAP_CD) * SkillTree.swap_cd_mult()
	var node: Node3D = t["node"]
	var from := _p.global_position
	var to: Vector3 = t["pos"]
	var kind: StringName = t["kind"]
	var tgt_pos := PlayerUtil.safe_spot(from, Game.world if is_instance_valid(Game.world) else null)
	FX.burst(from + Vector3(0.0, 1.0, 0.0), PALE, _fx_count(24), 6.0, 0.5, 0.0)
	FX.burst(to + Vector3(0.0, 1.0, 0.0), MAGENTA, _fx_count(24), 6.0, 0.5, 0.0)
	_swap_a = from + Vector3(0.0, 1.0, 0.0)
	_swap_b = to + Vector3(0.0, 1.0, 0.0)
	_swap_left = SWAP_BEAM
	FX.qvfx.entangle(_swap_a, _swap_b, SWAP_BEAM)
	PostFx2.pulse(0.8)
	_p.teleport_to(to + Vector3(0.0, 0.05, 0.0))
	match kind:
		&"enemy":
			node.global_position = Vector3(tgt_pos.x, node.global_position.y if tgt_pos.y < 0.5 else tgt_pos.y, tgt_pos.z)
			var d := node as Drone
			d.aware = false
			d.set("_stagger", SWAP_CONFUSE)
			d.stagger(1.0)
		&"car":
			node.global_position = Vector3(tgt_pos.x, tgt_pos.y + 0.6, tgt_pos.z)
			if "linear_velocity" in node:
				node.set("linear_velocity", Vector3.ZERO)
				node.set("angular_velocity", Vector3.ZERO)
		&"crate":
			node.global_position = Vector3(from.x, to.y, from.z)
		&"pickup":
			node.global_position = tgt_pos + Vector3(0.0, 0.5, 0.0)
			var pd: Dictionary = t["pd"]
			pd["pos"] = tgt_pos
	fx_flash = 1.0
	_slow_begin(SLOW_AFTER)
	FX.shake(0.25)
	Sfx.play(&"link")
	Game.say("ENTANGLE", 1.2)
	verb_used.emit(&"entangle")
	return true


## The best swap target in the crosshair: {kind, node, pos, pd?} or {} (nothing aimed, out of range, or no line of sight).
func swap_target() -> Dictionary:
	var aim := _p.get_aim()
	var o: Vector3 = aim["origin"]
	var dir: Vector3 = aim["dir"]
	var best := SWAP_RANGE
	var res := {}
	var mgr := Game.enemies
	if is_instance_valid(mgr):
		for e: Variant in mgr.get("list"):
			var d := e as Drone
			if d == null or not _alive(d):
				continue
			var r := _ray_sphere(o, dir, d.center(), d.radius * AIM_ASSIST)
			if r < best and _clear(o, d.center()):
				best = r
				res = {"kind": &"enemy", "node": d, "pos": d.global_position}
	for v: Node in get_tree().get_nodes_in_group(&"vehicle"):
		var c := v as Node3D
		if c == null or not c.is_inside_tree() or c == _p.vehicle:
			continue
		var ctr := c.global_position + Vector3(0.0, 0.8, 0.0)
		var r := _ray_sphere(o, dir, ctr, 2.6)
		if r < best and _clear(o, ctr):
			best = r
			res = {"kind": &"car", "node": c, "pos": c.global_position}
	for cr: Node in get_tree().get_nodes_in_group(&"puzzle_crate"):   # QuantumPuzzles key crates (phase doors)
		var cn := cr as Node3D
		if cn == null or not cn.is_inside_tree():
			continue
		var cc := cn.global_position + Vector3(0.0, 0.5, 0.0)
		var r := _ray_sphere(o, dir, cc, 1.4)
		if r < best and _clear(o, cc):
			best = r
			res = {"kind": &"crate", "node": cn, "pos": cn.global_position}
	var mis: Object = Game.missions if is_instance_valid(Game.missions) else null
	if mis != null and mis.get("pickups") is Array:
		for pk: Variant in mis.get("pickups"):
			var pd: Dictionary = pk
			var n := pd.get("node") as Node3D
			if n == null or not is_instance_valid(n):
				continue
			var pp: Vector3 = pd.get("pos", n.global_position)
			var ctr := pp + Vector3(0.0, 0.6, 0.0)
			var r := _ray_sphere(o, dir, ctr, 1.4)
			if r < best and _clear(o, ctr):
				best = r
				res = {"kind": &"pickup", "node": n, "pos": pp, "pd": pd}
	return res


func _clear(o: Vector3, to: Vector3) -> bool:
	if _p == null or not _p.is_inside_tree():
		return true
	_rq.from = o
	_rq.to = to
	_rq.collision_mask = Game.L_WORLD
	return _p.get_world_3d().direct_space_state.intersect_ray(_rq).is_empty()


func _animate_swap(delta: float) -> void:
	if _swap_beams.is_empty():
		for k in 2:
			var m := FX.make_beam(Color(0.25, 0.9, 1.0) if k == 0 else Color(1.0, 0.3, 0.9), 0.14 if k == 0 else 0.06)
			m.visible = false
			fx_root.add_child(m)
			_swap_beams.append(m)
	if _swap_left <= 0.0:
		if _swap_beams[0].visible:
			_swap_beams[0].visible = false
			_swap_beams[1].visible = false
		return
	_swap_left -= delta
	var on := false                                           # the braid (FX.qvfx.entangle) replaced the flickering box beams
	FX.place_beam(_swap_beams[0], _swap_a, _swap_b)
	FX.place_beam(_swap_beams[1], _swap_a, _swap_b)
	_swap_beams[0].visible = on
	_swap_beams[1].visible = on and _rich


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
	if _p.energy < HeroPower.cost(SUPER_COST) * SkillTree.cost_mult(&"superposition"):
		Game.say("NOT ENOUGH COHERENCE", 1.0)
		return false
	_p.energy -= HeroPower.cost(SUPER_COST) * SkillTree.cost_mult(&"superposition")
	_make_clone()
	FX.qvfx.superposition_start(_p.global_position + Vector3(0.0, 1.0, 0.0))
	_boost = SUPER_SPEED * SkillTree.split_speed()
	_p.speed_boost = _boost
	FX.burst(_p.global_position + Vector3(0.0, 1.0, 0.0), Color(0.4, 1.0, 0.93), _fx_count(30), 5.0, 0.6, 0.0)
	Sfx.play(&"superpos")
	Game.say("SUPERPOSITION · ENEMIES SEE TWO OF YOU · BE FAST", 1.8)
	verb_used.emit(&"superposition")
	return true


## The decoy collapses into a damaging blast. Called by the player (second press), the timer and the enemies (their bolts hit the ghost).
func collapse(timeout := false) -> void:
	if clone == null:
		return
	var pos := clone.global_position
	_kill_clone()
	cd_super = HeroPower.cd(COLLAPSE_CD)
	if timeout:
		Game.explode(pos + Vector3(0.0, 1.0, 0.0), PULSE_RADIUS, {"enemy_dmg": PULSE_DMG, "car_dmg": 10.0, "player_dmg": 0.0, "color": Color(0.4, 1.0, 0.93)})
	else:
		Game.explode(pos + Vector3(0.0, 1.0, 0.0), BLAST_RADIUS, {"enemy_dmg": 70.0, "car_dmg": 40.0, "player_dmg": 0.0, "color": Color(0.4, 1.0, 0.93)})
	PostFx2.pulse(1.0)
	Game.say("WAVEFUNCTION COLLAPSE", 1.4)


# --- collapse ----------------------------------------------------------------------------------------------------------

## COLLAPSE shockwave (see the header). Returns true when it fired.
func collapse_all() -> bool:
	if _p == null or not Game.is_playing() or _p.is_dead():
		return false
	if _p.vehicle != null:
		Game.say("COLLAPSE OFFLINE IN VEHICLE", 1.2)
		return false
	if cd_collapse > 0.0:
		return false
	if _p.energy < HeroPower.cost(WAVE_COST) * SkillTree.cost_mult(&"collapse"):
		Game.say("NOT ENOUGH COHERENCE", 1.0)
		return false
	_p.energy -= HeroPower.cost(WAVE_COST) * SkillTree.cost_mult(&"collapse")
	cd_collapse = HeroPower.cd(WAVE_CD)
	var origin := _p.global_position + Vector3(0.0, 1.0, 0.0)
	var combo := ""
	if clone != null:                                     # SUPERPOSITION: the decoy detonates at full strength
		collapse()
		combo = " · DECOY DETONATED"
	if has_beacon:                                        # the beacon bursts where it lies instead of teleporting
		var bp := beacon_pos + Vector3(0.0, 1.0, 0.0)
		_remove_beacon()
		Game.explode(bp, WAVE_BEACON_RADIUS, {"enemy_dmg": 50.0, "car_dmg": 25.0, "player_dmg": 0.0, "color": Color(CYAN)})
	var pairs := links.duplicate()
	for l: Dictionary in pairs:                           # ENTANGLE: both ends of every pair take the hit, however far apart
		var a: Drone = l["a"]
		if _alive(a):
			a.damage(TestMode.damage(WAVE_LINK_DMG))
			combo = " · LINKS SHATTERED"
	var i := links.size() - 1
	while i >= 0:
		_drop_link(i)
		i -= 1
	var rad := WAVE_RADIUS * SkillTree.wave_radius_mult()
	var pull := SkillTree.wave_pull()
	var chain := SkillTree.wave_chain()
	var chained := 0
	for e: Node3D in get_tree().get_nodes_in_group(&"enemy"):
		var d := e.global_position.distance_to(origin)
		if d > rad + 0.8:
			continue
		var f := 1.0 - 0.5 * d / (rad + 0.8)
		if pull > 0.0 and d > 2.0:                          # skill tree PULL: drawn toward the centre before the hit lands
			var flat := Vector3(origin.x - e.global_position.x, 0.0, origin.z - e.global_position.z)
			if flat.length() > 0.1:
				e.global_position += flat.normalized() * minf(pull, maxf(flat.length() - 1.5, 0.0))
		if e.has_method(&"damage"):
			e.call(&"damage", TestMode.damage(WAVE_DMG * f * SkillTree.wave_damage_mult()))
			if chain > 0.0 and chained < 6 and is_instance_valid(e) and bool(e.get(&"dead")):      # skill tree CHAIN: a kill detonates
				chained += 1
				Game.explode(e.global_position + Vector3(0.0, 1.0, 0.0), 5.0, {"enemy_dmg": TestMode.damage(chain), "car_dmg": 0.0, "player_dmg": 0.0, "color": MAGENTA})
		if is_instance_valid(e) and e.has_method(&"stagger"):
			e.call(&"stagger", 1.5)
		if is_instance_valid(e) and e.has_method(&"disable"):
			e.call(&"disable", WAVE_OFF * (0.6 + 0.4 * f))
	FX.qvfx.collapse(origin, rad)
	FX.blast(origin, rad, MAGENTA, 0.6)
	if _rich:
		FX.blast(origin, rad * 0.6, CYAN, 0.4)
	FX.burst(origin, PALE, _fx_count(40), 9.0, 0.6, 0.0)
	FX.shake(0.9)
	collapse_fx = 1.0
	Sfx.play(&"blink")
	Sfx.play_at(&"boom", origin, -2.0)
	Game.say("COLLAPSE" + combo, 1.4)
	verb_used.emit(&"collapse")
	return true


## Takes the ghost down without a blast and gives the player his normal speed back.
func _kill_clone() -> void:
	if clone == null:
		return
	if clone.is_in_group(&"clone"):
		clone.remove_from_group(&"clone")
	clone.visible = false
	clone = null
	clone_left = 0.0
	for e: MeshInstance3D in _echoes:
		e.visible = false
	if _ghost_ring != null:
		_ghost_ring.visible = false
	if _p != null and _boost > 0.0 and is_equal_approx(_p.speed_boost, _boost):
		_p.speed_boost = 1.0


## Skill tree DECOY COUNT: extra holograms beside the ghost. Enemies pick among all of them (decoy_pick); they vanish with the ghost.
func _make_echoes(xf: Transform3D) -> void:
	for i in SkillTree.extra_decoys():
		if i >= MAX_ECHOES:
			break
		while _echoes.size() <= i:
			var m := MeshInstance3D.new()
			var cap := CapsuleMesh.new()
			cap.radius = 0.3
			cap.height = 1.7
			m.mesh = cap
			m.material_override = _mat_ghost
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			fx_root.add_child(m)
			_echoes.append(m)
		var ang := _p.yaw + (1.0 if i % 2 == 0 else -1.0) * (1.2 + 0.5 * float(i / 2))
		var off := Vector3(sin(ang), 0.0, cos(ang)) * 3.0
		_echoes[i].global_position = xf.origin + off + Vector3(0.0, 0.85, 0.0)
		_echoes[i].visible = true


## The decoy the enemies look at this moment: the ghost or one of its echoes (changes twice a second).
func decoy_pick() -> Node3D:
	if clone == null:
		return null
	var live: Array[Node3D] = [clone]
	for e: MeshInstance3D in _echoes:
		if e.visible:
			live.append(e)
	return live[(Engine.get_physics_frames() / 30) % live.size()]


func _on_player_died() -> void:
	var dmg := SkillTree.death_blast()
	if dmg > 0.0 and _p != null:
		Game.explode(_p.global_position + Vector3(0.0, 1.0, 0.0), 8.0, {"enemy_dmg": TestMode.damage(dmg), "car_dmg": 30.0, "player_dmg": 0.0, "color": CYAN})


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
	clone_left = SUPER_LIFE + Upgrades.decoy_bonus() + SkillTree.decoy_life()
	_make_echoes(xf)


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
	fx_flash = maxf(fx_flash - delta * 2.5, 0.0)
	collapse_fx = maxf(collapse_fx - delta * 1.6, 0.0)
	if _slow_on and not aiming and Time.get_ticks_msec() >= _slow_until:
		_slow_end()
	if has_beacon or aiming:
		_animate_beacon()
	if clone != null:
		_animate_clone()
	for l: Dictionary in links:
		_animate_link(l)
	_animate_swap(delta)


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
	_glow_tex = SoftDot.radial(g)
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
