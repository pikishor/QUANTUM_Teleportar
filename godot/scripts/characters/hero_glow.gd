class_name HeroGlow
extends RefCounted
## The quantum-energy circuit glow of the hero's suit (wave 112, hero look v3). ONE place decides what the circuits, emitters, core, wing mounts and eyes of the suit do; everything that
## wants to drive them (abilities now, the QUANTUM SNAKE wave later) calls the clean API and never touches the material:
##
##   HeroLook.set_glow(color, intensity, mode)     static, targets the live hero. intensity <= 0 releases the layer. Returns false when no hero is alive.
##   HeroLook.pulse_glow(color, intensity, secs)   one-shot flash that fades by itself
##
## MODES are independent LAYERS (they do not fight: per zone the strongest layer wins, the colour is the intensity-weighted mix):
##   &"base"     the suit's own idle glow (the look's accent colour, set by PlayerBody): a calm breathing of the circuits
##   &"steady"   a constant glow everywhere (an ability that is switched on)
##   &"pulse"    the same, breathing (a power that charges, a hold)
##   &"charge"   steady with the core and the head brightest (aiming QUANTUM TELEPORT)
##   &"flow"     SWING: energy runs from the core down the arms to the hands in repeating waves, the hands burn (the snake emitters)
##   &"wings"    FLIGHT: the wing mounts and the back unit glow, the arms a little (the wings of SNAKE FLIGHT)
##   &"burst"    a flash that decays (bomb throw, a shot, a teleport arrival); use pulse_glow()
##   &"flicker"  an unstable stutter (damage, a failing power)
##   &"alarm"    a red heartbeat (low health; set by sense())
## ZONES of the suit (the per-vertex zone of the mesh, set by HeroCharacter): CORE chest belt back, ARMS shoulders arms bracers, HANDS gloves and bracer emitters, LEGS, WINGS back unit
## fins and wing mounts, HEAD collar, temple and eyes.
##
## Outputs for the material (apply_to): `glow_rgb`, `gz_a` (core, arms, hands, legs), `gz_b` (wings, head), `gflow` (x = front of the travelling wave 0 core .. 1 fingertips,
## y = strength). Nothing allocates per frame (fixed arrays, no Dictionary walks).

const ZONE_CORE := 0
const ZONE_ARMS := 1
const ZONE_HANDS := 2
const ZONE_LEGS := 3
const ZONE_WINGS := 4
const ZONE_HEAD := 5
const ZONES := 6

const M_BASE := 0
const M_STEADY := 1
const M_PULSE := 2
const M_CHARGE := 3
const M_FLOW := 4
const M_WINGS := 5
const M_BURST := 6
const M_FLICKER := 7
const M_ALARM := 8
const MODE_NAMES: Array[StringName] = [&"base", &"steady", &"pulse", &"charge", &"flow", &"wings", &"burst", &"flicker", &"alarm"]
## Per mode, how much of its intensity each zone shows (core, arms, hands, legs, wings, head).
const WEIGHTS := [
	[1.0, 0.6, 0.55, 0.5, 0.7, 0.35],      # base
	[1.0, 1.0, 1.0, 1.0, 1.0, 0.8],        # steady
	[1.0, 1.0, 1.0, 1.0, 1.0, 0.8],        # pulse
	[1.3, 0.8, 0.8, 0.55, 0.6, 1.1],       # charge
	[0.9, 0.75, 1.5, 0.3, 0.0, 0.25],      # flow
	[0.8, 0.35, 0.15, 0.0, 1.5, 0.2],      # wings
	[1.0, 1.0, 1.0, 1.0, 1.0, 1.0],        # burst
	[1.0, 1.0, 1.0, 0.8, 0.7, 1.0],        # flicker
	[1.0, 0.8, 0.5, 0.6, 0.5, 0.7],        # alarm (low health: a red heartbeat)
]
const RATE_IN := 12.0                       ## how fast a layer rises (1 / s)
const RATE_OUT := 3.2                       ## how fast it falls when released
const PULSE_HZ := 1.35
const FLOW_HZ := 1.7                        ## waves of the flow layer per second
const MAX_INTENSITY := 3.0

## The live hero's glow (PlayerBody registers it); the static API targets it. Previews (portrait, look screen) keep their own and never register.
static var primary: HeroGlow

var color: Array[Color] = []                ## per layer
var target := PackedFloat32Array()
var value := PackedFloat32Array()
var decay := PackedFloat32Array()           ## burst: intensity lost per second
var zones := PackedFloat32Array()           ## outputs
var out_rgb := Color(0.2, 0.95, 1.0)
var flow_front := -1.0
var flow_k := 0.0
var _clock := 0.0
var _flick := 1.0
var _flick_t := 0.0
## ability sensor state (sense())
var _prev_fx := 0.0
var _prev_collapse := 0.0
var _prev_clone := false
var _prev_links := 0


func _init() -> void:
	for i in MODE_NAMES.size():
		color.append(Color(0.2, 0.95, 1.0))
		target.append(0.0)
		value.append(0.0)
		decay.append(0.0)
	zones.resize(ZONES)
	set_layer(&"base", Color(0.2, 0.95, 1.0), 1.0)
	value[M_BASE] = 1.0
	for z in ZONES:
		zones[z] = float((WEIGHTS[M_BASE] as Array)[z])


static func mode_index(mode: StringName) -> int:
	var i := MODE_NAMES.find(mode)
	return i if i >= 0 else M_STEADY


## The static API behind HeroLook.set_glow: false when no live hero has registered.
static func live_set(col: Color, intensity: float, mode: StringName) -> bool:
	if primary == null:
		return false
	primary.set_layer(mode, col, intensity)
	return true


static func live_pulse(col: Color, intensity: float, secs: float) -> bool:
	if primary == null:
		return false
	primary.pulse(col, intensity, secs)
	return true


## Sets (or, with intensity <= 0, releases) the layer `mode`.
func set_layer(mode: StringName, col: Color, intensity: float) -> void:
	var m := mode_index(mode)
	if m == M_WINGS and not _sensing:
		_wings_api = intensity > 0.0
	if m == M_BURST:                                           # a burst through the layer call is a one-shot flash of 0.4 s
		pulse(col, intensity, 0.4)
		return
	color[m] = Color(col.r, col.g, col.b, 1.0)
	target[m] = clampf(intensity, 0.0, MAX_INTENSITY)


## A flash: the burst layer jumps to `intensity` and fades out in `secs` seconds.
func pulse(col: Color, intensity: float, secs := 0.45) -> void:
	if intensity <= 0.0:
		return
	var k := clampf(intensity, 0.0, MAX_INTENSITY)
	if k >= value[M_BURST] * 0.8:
		color[M_BURST] = Color(col.r, col.g, col.b, 1.0)
	value[M_BURST] = maxf(value[M_BURST], k)
	target[M_BURST] = 0.0
	decay[M_BURST] = maxf(decay[M_BURST], k / maxf(secs, 0.05))


## The strength of one layer right now (tests, HUD).
func level(mode: StringName) -> float:
	return value[mode_index(mode)]


func release_all() -> void:
	for i in MODE_NAMES.size():
		if i != M_BASE:
			target[i] = 0.0
			value[i] = 0.0
	decay[M_BURST] = 0.0


## The base layer is the suit's idle: PlayerBody sets it from the look's accent.
func set_base(col: Color, intensity: float) -> void:
	set_layer(&"base", col, intensity)


func update(dt: float) -> void:
	_clock += dt
	for i in MODE_NAMES.size():
		if i == M_BURST:
			value[i] = maxf(0.0, value[i] - decay[i] * dt)
			if value[i] <= 0.0:
				decay[i] = 0.0
			continue
		var t := target[i]
		var v := value[i]
		if v < t:
			v = minf(t, v + (t - v) * minf(1.0, RATE_IN * dt) + 0.001)
		else:
			v = maxf(t, v - (v - t) * minf(1.0, RATE_OUT * dt) - 0.0005)
		value[i] = v
	# stutter of the flicker layer: a new random level every 40 ms
	_flick_t -= dt
	if _flick_t <= 0.0:
		_flick_t = 0.04
		_flick = 0.25 + 0.75 * fposmod(sin(_clock * 91.7) * 43758.5453, 1.0)
	var breath := 0.62 + 0.38 * sin(_clock * TAU * PULSE_HZ * 0.55)
	var pulse_m := 0.5 + 0.5 * sin(_clock * TAU * PULSE_HZ)
	var base_breath := 0.82 + 0.18 * sin(_clock * 1.7)
	var hb := fposmod(_clock * 1.25, 1.0)                      # two beats per cycle
	var heart := pow(maxf(0.0, sin(hb * TAU * 2.0)), 3.0) * (1.0 if hb < 0.5 else 0.7)
	var tot := 0.0
	var rr := 0.0
	var gg := 0.0
	var bb := 0.0
	for z in ZONES:
		zones[z] = 0.0
	for i in MODE_NAMES.size():
		var v2 := value[i]
		if v2 <= 0.001:
			continue
		var mod := 1.0
		match i:
			M_BASE:
				mod = base_breath
			M_PULSE:
				mod = 0.35 + 0.65 * pulse_m
			M_CHARGE:
				mod = 0.7 + 0.3 * pulse_m
			M_WINGS:
				mod = breath
			M_FLICKER:
				mod = _flick
			M_FLOW:
				mod = 0.65 + 0.35 * pulse_m
			M_ALARM:
				mod = 0.25 + 0.75 * heart
		var w: Array = WEIGHTS[i]
		var peak := 0.0
		for z in ZONES:
			var s := v2 * mod * float(w[z])
			if s > zones[z]:
				zones[z] = s
			peak = maxf(peak, s)
		var c := color[i]
		var wgt := peak + (0.0 if i != M_BASE else 0.0)
		if i == M_BASE:
			wgt *= 0.5                                         # the base colour gives way to any ability colour
		rr += c.r * wgt
		gg += c.g * wgt
		bb += c.b * wgt
		tot += wgt
	if tot > 0.0001:
		out_rgb = Color(rr / tot, gg / tot, bb / tot, 1.0)
	# the travelling wave of FLOW: repeating fronts from the core (0) over the arms to the hands (1)
	var fl := value[M_FLOW]
	if fl > 0.02:
		flow_front = fposmod(_clock * FLOW_HZ, 1.0) * 1.55 - 0.15
		flow_k = clampf(fl, 0.0, 1.6)
	else:
		flow_front = -1.0
		flow_k = 0.0


## Writes the outputs into the hero shader's uniforms.
func apply_to(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	mat.set_shader_parameter(&"glow_rgb", out_rgb)
	mat.set_shader_parameter(&"gz_a", Vector4(zones[ZONE_CORE], zones[ZONE_ARMS], zones[ZONE_HANDS], zones[ZONE_LEGS]))
	mat.set_shader_parameter(&"gz_b", Vector2(zones[ZONE_WINGS], zones[ZONE_HEAD]))
	mat.set_shader_parameter(&"gflow", Vector2(flow_front, flow_k))


# ---- the abilities: what the hero does -> which layers --------------------------------------------------------------------------------

const VIOLET := Color(0.72, 0.4, 1.0)
const CYAN := Color(0.25, 0.95, 1.0)
const MAGENTA := Color(1.0, 0.3, 0.9)
const AMBER := Color(1.0, 0.72, 0.28)
const RED := Color(1.0, 0.18, 0.15)
const WHITE := Color(0.9, 0.97, 1.0)


## Reads the hero's powers once per frame and drives the layers: QUANTUM TELEPORT (aim = charge, arrival = flash), SUPERPOSITION (the ghost exists = breathing pale cyan),
## ENTANGLE (links = steady magenta), COLLAPSE (flash and stutter), glide (steady cyan on the arms and wings), flight (the wings layer, `flying` on the player once it exists),
## low health (a red heartbeat). `p` is the Player (or null), `accent` the look's colour.
func sense(p: Object, accent: Color) -> void:
	if p == null:
		return
	_sensing = true
	var q: Variant = p.get(&"quantum") if "quantum" in p else null
	if q != null:
		var aiming: bool = "aiming" in q and q.aiming
		set_layer(&"charge", VIOLET, 1.25 if aiming else 0.0)
		var fx := float(q.fx_flash) if "fx_flash" in q else 0.0
		if fx > _prev_fx + 0.3:                                # a teleport just happened
			pulse(VIOLET.lerp(WHITE, 0.5), 1.9, 0.55)
		_prev_fx = fx
		var cf := float(q.collapse_fx) if "collapse_fx" in q else 0.0
		if cf > _prev_collapse + 0.3:                          # COLLAPSE
			pulse(AMBER.lerp(WHITE, 0.4), 2.3, 0.6)
			set_layer(&"flicker", AMBER, 1.0)
			_flicker_until = _clock + 0.5
		_prev_collapse = cf
		var has_clone: bool = "clone" in q and q.clone != null
		set_layer(&"pulse", CYAN.lerp(WHITE, 0.45), 0.95 if has_clone else 0.0)
		if has_clone and not _prev_clone:                      # SUPERPOSITION: the ghost splits off
			pulse(CYAN, 1.5, 0.4)
		_prev_clone = has_clone
		var n_links: int = (q.links as Array).size() if "links" in q else 0
		set_layer(&"steady", MAGENTA, 0.9 if n_links > 0 else 0.0)
		if n_links > _prev_links:                              # ENTANGLE: a new link
			pulse(MAGENTA, 1.5, 0.4)
		_prev_links = n_links
	if target[M_FLICKER] > 0.0 and _clock > _flicker_until:
		target[M_FLICKER] = 0.0
	var gliding: bool = "gliding" in p and p.gliding
	var flying: bool = "flying" in p and p.flying
	if flying:
		set_layer(&"wings", accent.lerp(WHITE, 0.2), 1.35)
	elif gliding:
		set_layer(&"wings", accent.lerp(CYAN, 0.5), 0.8)
	elif target[M_WINGS] > 0.0 and not _wings_api:
		target[M_WINGS] = 0.0
	if "hp" in p and "max_hp" in p and float(p.max_hp) > 0.0:
		var frac := float(p.hp) / float(p.max_hp)
		set_layer(&"alarm", RED, 0.9 * clampf((0.3 - frac) / 0.3, 0.0, 1.0) if frac > 0.0 else 0.0)
	_sensing = false


var _flicker_until := 0.0
var _sensing := false
var _wings_api := false                                        ## true once a caller set the wings layer through the API (sense() then leaves it alone)


## A hit on the hero: a red flash and a stutter (strength 0..1).
func hurt(strength: float) -> void:
	var s := clampf(strength, 0.0, 1.0)
	pulse(RED, 0.9 + 1.1 * s, 0.35)
	set_layer(&"flicker", RED.lerp(AMBER, 0.3), 0.8 * s)
	_flicker_until = _clock + 0.3 + 0.3 * s


## A shot: a short pulse in `col` (the weapon's energy colour).
func fired(col: Color, strength := 1.0) -> void:
	pulse(col, 0.55 * clampf(strength, 0.0, 2.0), 0.12)
