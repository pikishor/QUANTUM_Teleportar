class_name HeroFingers
extends RefCounted
## Finger poses of the superhero as bone rotations on top of the baked grip curl (HeroCharacter._curl_fingers): `grip` is the rest (the hands hold the rifle), `relaxed` opens
## every finger, `aim` stretches the right index onto the trigger guard. Pure bone poses (no allocation per call beyond the cached bone list), safe on any skeleton: bones
## that do not exist are skipped.

## Extra curl (radians) per joint 1..3 for each finger, negative = straighter than the grip.
const RELAXED := {"index": [-0.2, -0.35, -0.25], "middle": [-0.25, -0.4, -0.3], "ring": [-0.3, -0.4, -0.3], "pinky": [-0.35, -0.4, -0.3], "thumb": [-0.1, -0.15, -0.1]}
const AIM_INDEX := [-0.45, -0.6, -0.4]
const META := &"hero_fingers"


## Pose the fingers of both hands: mode &"grip", &"relaxed" or &"aim" (aim: right index straight, left hand as grip). Unknown modes act as grip.
static func pose(sk: Skeleton3D, mode: StringName) -> void:
	if sk == null:
		return
	var list: Array = sk.get_meta(META) if sk.has_meta(META) else _collect(sk)
	for e: Array in list:
		var bone: int = e[0]
		var base: String = e[1]
		var joint: int = e[2]
		var side: float = e[3]
		var delta := 0.0
		if mode == &"relaxed" and RELAXED.has(base):
			delta = RELAXED[base][clampi(joint - 1, 0, 2)]
		elif mode == &"aim" and base == "index" and side < 0.0:
			delta = AIM_INDEX[clampi(joint - 1, 0, 2)]
		var r := sk.get_bone_rest(bone)
		sk.set_bone_pose(bone, Transform3D(r.basis * Basis(Vector3.BACK, side * delta), r.origin))


static func _collect(sk: Skeleton3D) -> Array:
	var out := []
	for i in sk.get_bone_count():
		var nm := sk.get_bone_name(i)
		var side := 0.0
		if nm.ends_with("_l"):
			side = 1.0
		elif nm.ends_with("_r"):
			side = -1.0
		if side == 0.0 or nm.contains("leaf"):
			continue
		var base := nm.get_slice("_", 0)
		var js := nm.get_slice("_", 1)
		if base in RELAXED and js.is_valid_int():
			out.append([i, base, int(js), side])
	sk.set_meta(META, out)
	return out
