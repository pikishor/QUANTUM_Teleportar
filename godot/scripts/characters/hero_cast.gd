class_name HeroCast
extends RefCounted
## WAVE 128 (plan line 128, agent w128-anim): THE CAST ANIMATIONS of the quantum verbs. Before this wave a verb went off with the hero standing still, both hands on the rifle: nothing on
## his body said "he did that". Now every verb plays a short gesture with a readable WIND-UP (the hand draws back to the chest, the shoulders turn away) and a RELEASE (the arm or both arms
## thrown out toward the aim, the shoulders turning into it), a short hold and a smooth return to the weapon. The hand leaves the rifle through CharacterRig.hand_w / hand_off (the arm IK).
##   point   QUANTUM TELEPORT marker and jump, LINK, ARC         the left arm thrust at the aim
##   spread  SUPERPOSITION, TIME SLIP                            the free arm from across the chest to wide open
##   pull    ENTANGLE                                            the left hand reaches out, closes and yanks back to the hip
##   slam    COLLAPSE                                            the fist raised over the head, then driven down
##   push    PHASE SHIELD                                        the open palm pushed out
## Sources (no edit of the verb code): Quantum.verb_used and QuantumVerbs.used (signals), and the TELEPORT marker / jump read from Quantum.has_beacon / bits_left every frame.
## W128_OLD=1: off (the old still pose).

const TIME := 0.78                    ## the whole gesture (s)
const WIND := 0.16                    ## wind-up ends
const HIT := 0.32                     ## release reaches its peak
const HOLD := 0.48                    ## held until
const KINDS := {&"blink": &"point", &"teleport": &"point", &"link": &"point", &"arc": &"point", &"superposition": &"spread", &"slip": &"spread",
	&"entangle": &"pull", &"collapse": &"slam", &"shield": &"push"}
## per gesture: [left wind, left release, right wind, right release (INF: the right hand keeps the weapon, which never floats free)] shoulder-relative targets (torso frame: x right, y up, z back), [twist wind, twist release, pitch wind, pitch release]
const POSES := {
	&"point": [Vector3(0.16, -0.22, -0.16), Vector3(0.06, 0.04, -0.5), Vector3.INF, Vector3.INF, Vector2(0.28, -0.18), Vector2(0.0, -0.04)],
	&"spread": [Vector3(0.22, -0.18, -0.2), Vector3(-0.46, 0.02, -0.12), Vector3.INF, Vector3.INF, Vector2(-0.2, 0.22), Vector2(0.06, -0.1)],
	&"pull": [Vector3(0.04, 0.0, -0.48), Vector3(-0.08, -0.4, 0.06), Vector3.INF, Vector3.INF, Vector2(-0.12, 0.26), Vector2(-0.05, 0.08)],
	&"slam": [Vector3(0.1, 0.44, -0.12), Vector3(0.14, -0.4, -0.34), Vector3.INF, Vector3.INF, Vector2(0.1, -0.1), Vector2(0.12, -0.3)],
	&"push": [Vector3(0.12, -0.14, -0.1), Vector3(0.16, 0.06, -0.5), Vector3.INF, Vector3.INF, Vector2(0.18, -0.24), Vector2(-0.04, -0.08)],
}

static var on := OS.get_environment("W128_OLD") != "1"
var t := -1.0                          ## seconds into the current gesture (-1 none)
var kind: StringName = &""             ## the verb being cast (tests)
var gesture: StringName = &""
var casts := 0                         ## gestures started (tests)
var weight := 0.0                      ## 0..1 how far the gesture holds the arms now
var phase: StringName = &""            ## &"wind" / &"release" / &"hold" / &"return" / &"" (tests)
var _q: Node
var _qv: Node
var _had_beacon := false
var _bits := 0.0


## Hook the verb signals of player `p` (once; cheap to call every frame).
func bind(p: Node) -> void:
	if not on or p == null:
		return
	var q = p.get(&"quantum")
	if q != _q and q is Node and (q as Node).has_signal(&"verb_used"):
		_q = q
		(q as Node).connect(&"verb_used", start)
	var qv = p.get(&"qverbs")
	if qv != _qv and qv is Node and (qv as Node).has_signal(&"used"):
		_qv = qv
		(qv as Node).connect(&"used", start)


## Start the gesture of verb `id`.
func start(id: StringName) -> void:
	if not on or not KINDS.has(id):
		return
	kind = id
	gesture = KINDS[id]
	t = 0.0
	casts += 1


## One frame: watch the teleport, advance the gesture, write the arms into `rig` (after every other layer has written its inputs, before rig.apply()).
func update(dt: float, rig: CharacterRig) -> void:
	if not on:
		return
	if _q != null and is_instance_valid(_q):
		var hb := bool(_q.get(&"has_beacon"))
		var bits := float(_q.get(&"bits_left"))
		if hb and not _had_beacon:
			start(&"blink")
		elif bits > _bits + 0.5:
			start(&"teleport")
		_had_beacon = hb
		_bits = bits
	if t < 0.0:
		weight = 0.0
		phase = &""
		return
	t += dt
	if t >= TIME:
		t = -1.0
		weight = 0.0
		phase = &""
		return
	var pose: Array = POSES[gesture]
	var k := 0.0                                           # 0 wind pose .. 1 release pose
	if t < WIND:
		weight = _ease(t / WIND)
		k = 0.0
		phase = &"wind"
	elif t < HIT:
		weight = 1.0
		k = _ease((t - WIND) / (HIT - WIND))
		phase = &"release"
	elif t < HOLD:
		weight = 1.0
		k = 1.0
		phase = &"hold"
	else:
		weight = 1.0 - _ease((t - HOLD) / (TIME - HOLD))
		k = 1.0
		phase = &"return"
	var l: Vector3 = (pose[0] as Vector3).lerp(pose[1] as Vector3, k)
	rig.hand_off_l = rig.hand_off_l.lerp(l, weight) if rig.hand_w.x > 0.0 else l
	rig.hand_w.x = maxf(rig.hand_w.x, weight)
	if pose[2] != Vector3.INF:
		var r: Vector3 = (pose[2] as Vector3).lerp(pose[3] as Vector3, k)
		rig.hand_off_r = rig.hand_off_r.lerp(r, weight) if rig.hand_w.y > 0.0 else r
		rig.hand_w.y = maxf(rig.hand_w.y, weight)
	var tw: Vector2 = pose[4]
	var pt: Vector2 = pose[5]
	rig.extra_torso += Vector3(lerpf(pt.x, pt.y, k), lerpf(tw.x, tw.y, k), 0.0) * weight


static func _ease(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)
