extends Node3D
## The nearest citizens as real skinned actors (HumanoidVariants "citizen" on the Superhero base meshes): the NpcLife promotes up to 12 people, this pool draws them in 3D (near mesh
## <= HumanoidVariants.NEAR_CITIZEN triangles, the mid mesh beyond MID_RANGE) and the crowd MultiMesh skips them (Crowd.set_hidden), so nobody is drawn twice. Walk cycle: CharacterRig +
## Locomotion (shared with the hero). The actors never cast shadows (a draw each) and the pool is capped per tier: LOW 0, MED 6, HIGH 12 (every actor is one draw call).
## Without the hero files nothing is built and the crowd keeps drawing everybody.

const CAPS: Array[int] = [0, 6, 12]
const SHOW_RADIUS := 22.0                       ## only people this close become actors (the rest of the promoted 12 stay MultiMesh people)

var crowd: RefCounted
var npc: RefCounted
var cap := 12
var slots: Array[Dictionary] = []               ## {person, root, body, rig, loco, variant, prev}
var steps := 0
var assigned_total := 0
var enabled := true

var _free: Array[Dictionary] = []
var _clock := 0.0
var _lod_t := 0.0


func setup(crowd_ref: RefCounted, npc_ref: RefCounted) -> void:
	name = "CitizenActors"
	crowd = crowd_ref
	npc = npc_ref


func set_tier(level: int) -> void:
	cap = CAPS[clampi(level, 0, 2)]
	while slots.size() > cap:
		_release(slots.size() - 1)


func active_count() -> int:
	return slots.size()


func reset() -> void:
	while not slots.is_empty():
		_release(slots.size() - 1)


func _exit_tree() -> void:
	for s in _free:
		if is_instance_valid(s["root"]) and not (s["root"] as Node).is_inside_tree():
			(s["root"] as Node).free()
	_free.clear()


func step(delta: float, center: Vector3) -> void:
	if not enabled or crowd == null or cap <= 0 or not HumanoidVariants.available():
		if not slots.is_empty():
			reset()
		return
	steps += 1
	_clock += delta
	var want: Array[int] = []
	for i: int in npc.actors:
		if want.size() >= cap:
			break
		var p: Vector3 = crowd.person_position(i)
		if crowd.is_alive(i) and (p.x - center.x) * (p.x - center.x) + (p.z - center.z) * (p.z - center.z) < SHOW_RADIUS * SHOW_RADIUS:
			want.append(i)
	for k in range(slots.size() - 1, -1, -1):                 # release the ones that left the nearest set
		if not (int(slots[k]["person"]) in want) or not crowd.is_alive(int(slots[k]["person"])):
			_release(k)
	for i in want:
		var has := false
		for s in slots:
			if int(s["person"]) == i:
				has = true
				break
		if not has and not _acquire(i):
			break
	_lod_t -= delta
	var do_lod := _lod_t <= 0.0
	if do_lod:
		_lod_t = 0.25
	for s in slots:
		_drive(s, delta, center, do_lod)


func _acquire(person: int) -> bool:
	var s: Dictionary
	if not _free.is_empty():
		s = _free.pop_back()
	else:
		var r := HumanoidVariants.build(&"citizen", person * 7 + slots.size() + assigned_total)
		if r["root"] == null or not bool(r["ok"]):
			if r["root"] != null:
				(r["root"] as Node).free()
			enabled = false
			return false
		var root := r["root"] as Node3D
		var rig := CharacterRig.find(root)
		if rig == null:
			root.free()
			enabled = false
			return false
		var loco := Locomotion.new(rig)
		loco.scale_amp = 0.95
		rig.ready = 0.0
		rig.set_shadow(false)
		s = {"root": root, "body": r["body"], "rig": rig, "loco": loco, "variant": r["variant"]}
	s["person"] = person
	s["prev"] = Vector3.INF
	var root_n := s["root"] as Node3D
	if root_n.get_parent() != self:
		add_child(root_n)
	root_n.visible = true
	slots.append(s)
	crowd.set_hidden(person, true)
	assigned_total += 1
	return true


func _release(k: int) -> void:
	var s: Dictionary = slots[k]
	slots.remove_at(k)
	if crowd != null:
		crowd.set_hidden(int(s["person"]), false)
	var root := s["root"] as Node3D
	if is_instance_valid(root):
		root.visible = false
		(s["loco"] as Locomotion).reset()
		_free.append(s)


func _drive(s: Dictionary, delta: float, center: Vector3, do_lod: bool) -> void:
	var i := int(s["person"])
	var root := s["root"] as Node3D
	var p: Vector3 = crowd.person_position(i)
	var yaw: float = crowd.person_yaw(i)
	var prev: Vector3 = s["prev"]
	var disp := Vector3.ZERO if prev == Vector3.INF else p - prev
	s["prev"] = p
	root.position = p
	root.rotation.y = yaw
	var sp: float = crowd.person_speed(i)
	var loco := s["loco"] as Locomotion
	var rig := s["rig"] as CharacterRig
	# Locomotion takes the displacement in the world, the yaw of the body and whether the person wants to move
	loco.update(maxf(delta, 0.001), disp, yaw, true, 0.0, 1.0 if sp > 0.1 else 0.0, sp > 3.5, false)
	rig.ready = 0.0
	rig.apply()
	if do_lod:
		HumanoidVariants.set_lod(s["body"], s["variant"], center.distance_to(p))
