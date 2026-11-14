extends RefCounted
## The weapon sound system (wave 114: scripts/audio/weapon_audio.gd, assets from tools/audio/make_weapons_v4.py out of the CC0 sample library). No scene, about 20 s.
##   * every weapon of WeaponDefs.all_ids() maps to a SOUND SET and every stream of every set exists (no silent gun, no missing mechanism, tail, reload or equip sound)
##   * at least four distinct sets in every major class (pistol, SMG, rifle, shotgun, sniper, LMG, launcher, energy, melee), and each set is somebody's voice (no dead set)
##   * the layers: mechanism click, shot body, tail on the TAIL bus (its reverb send opens indoors), the distance filter of the 3D voices, reload and equip sounds per class
##   * explosions by blast size (small, medium, large, huge) from the BlastTable radius, impact and ricochet by material, hit and kill markers, haptics by kind
##   * no clipping: every generated file peaks at -3 dBFS or lower, the worst stack of layers stays under full scale, the Master bus ends in a limiter
## Waits on counters (WeaponAudio.shots, .tails, ...), never on frames. Run: tools/test.sh tests/test_weapon_audio_v3.gd

const MAJOR := {
	&"pistol": &"pistol", &"smg": &"smg", &"rifle": &"rifle", &"shotgun": &"shotgun", &"sniper": &"sniper", &"energy": &"energy", &"melee": &"melee",
}
const PREFIX_GROUPS := {"LMG": "lmg_", "launcher": "lau_"}
const MATERIALS: Array[StringName] = [&"asphalt", &"concrete", &"glass", &"metal", &"flesh", &"wood", &"dirt", &"foliage", &"water", &"armor", &"shield"]
const MARKERS: Array[StringName] = [&"hit", &"hit_crit", &"hit_head", &"hit_armor", &"hit_shield", &"hit_marker", &"hit_kill", &"hit_kill_head", &"hit_kill_blast", &"hit_kill_streak"]
const LEVELS := "res://tools/audio/weapons_v4_levels.json"


func _takes(nm: StringName) -> int:
	return Sfx.variants_of(nm).size()


func run(_host: Node) -> void:
	WeaponAudio.all_sets()
	var ids := WeaponDefs.all_ids()
	_mapping(ids)
	_classes(ids)
	_layers()
	_reload_equip()
	_explosions()
	_materials()
	_markers()
	_haptics()
	_clipping(ids)
	_voices()


# ---------------------------------------------------------------------------------------------------------------------------------- mapping

func _mapping(ids: Array[StringName]) -> void:
	TestLib.check(ids.size() >= 200, "the roster has %d weapons" % ids.size())
	var sets := WeaponAudio.all_sets()
	TestLib.check(sets.size() >= 60, "%d sound sets (at least 60)" % sets.size())
	var unmapped: Array[String] = []
	var used := {}
	for id in ids:
		var st := WeaponAudio.set_of(id)
		var sd := WeaponAudio.data(st)
		if sd.is_empty() or StringName(sd["body"]) == &"":
			unmapped.append(String(id))
		else:
			used[st] = int(used.get(st, 0)) + 1
	TestLib.check(unmapped.is_empty(), "every one of the %d weapons maps to a sound set with a shot body (%s)" % [ids.size(), str(unmapped.slice(0, 6))])
	var dead: Array[String] = []
	for st in sets:
		if not used.has(st):
			dead.append(String(st))
	TestLib.check(dead.is_empty(), "every sound set is the voice of at least one weapon (dead sets: %s)" % str(dead))
	# no stream is missing: body, mechanism, tail, reload and equip of every set exist, with takes enough not to machine-gun one sample
	var missing: Array[String] = []
	var thin: Array[String] = []
	for st in sets:
		var sd := WeaponAudio.data(st)
		for k: String in ["body", "mech", "tail", "reload", "equip"]:
			var nm := StringName(sd[k])
			if nm == &"":
				continue
			var n := _takes(nm)
			if n == 0:
				missing.append("%s.%s=%s" % [st, k, nm])
			elif n < 2 and k != "body":
				thin.append("%s.%s=%s" % [st, k, nm])
	TestLib.check(missing.is_empty(), "no missing stream in any of the %d sets: %s" % [sets.size(), str(missing.slice(0, 8))])
	TestLib.check(thin.is_empty(), "mechanism, tail, reload and equip sounds have two takes or more (thin: %s)" % str(thin.slice(0, 6)))
	var one_take: Array[String] = []
	for st in sets:
		var sd := WeaponAudio.data(st)
		var interval_fast := String(sd["mech"]) in ["wm_spin"] or String(sd["cls"]) in ["smg"]
		if interval_fast and _takes(StringName(sd["body"])) < 2:
			one_take.append(String(st))
	TestLib.check(one_take.is_empty(), "a rapid-fire body has takes (never the same sample twice in a row): %s" % str(one_take))
	TestLib.check(_takes(&"shot_supp") >= 1 and _takes(&"shot_oc") >= 1 and Sfx.shot_sound(&"shot", true) == &"shot_supp" and Sfx.shot_sound(&"shot", false, true) == &"shot_oc", "the suppressed and the overcharged variants of a shot exist")
	# the rows themselves are unique: no two sets are the same stack of layers
	var seen := {}
	var twins: Array[String] = []
	for st in sets:
		var sd := WeaponAudio.data(st)
		var key := "%s|%s|%s|%s" % [sd["body"], sd["mech"], sd["tail"], sd["db"]]
		if seen.has(key):
			twins.append("%s = %s" % [st, seen[key]])
		seen[key] = st
	TestLib.check(twins.is_empty(), "no two sets are the same stack of body, mechanism, tail and level (%s)" % str(twins))


func _classes(ids: Array[StringName]) -> void:
	for cls: StringName in MAJOR:
		var list := WeaponAudio.sets_of_class(cls)
		var bodies := {}
		for st in list:
			bodies[WeaponAudio.data(st)["body"]] = true
		TestLib.check(list.size() >= 4 and bodies.size() >= 4, "%s: %d sets, %d different shot bodies (at least 4 of each)" % [cls, list.size(), bodies.size()])
		var used := {}
		for id in ids:
			var st := WeaponAudio.set_of(id)
			if list.has(st):
				used[st] = true
		TestLib.check(used.size() >= 4, "%s: %d of its sets are in the hands of weapons (at least 4)" % [cls, used.size()])
	for group: String in PREFIX_GROUPS:
		var pre: String = PREFIX_GROUPS[group]
		var n := 0
		var bodies := {}
		for st in WeaponAudio.all_sets():
			if String(st).begins_with(pre):
				n += 1
				bodies[WeaponAudio.data(st)["body"]] = true
		TestLib.check(n >= 4 and bodies.size() >= 4, "%s: %d sets (%s*), %d different bodies" % [group, n, pre, bodies.size()])
	# a weapon sounds like its own kind: the set of nine in ten weapons is a set of their class
	var same := 0
	for id in ids:
		if StringName(WeaponAudio.data(WeaponAudio.set_of(id))["cls"]) == WeaponDefs.class_of(id):
			same += 1
	TestLib.check(float(same) / float(ids.size()) >= 0.88, "%d of %d weapons wear a set of their own class" % [same, ids.size()])
	# the family rules still hand a hash-picked set to weapons without a voice of their own: not one sound for the 32 grenades, mines and strikes
	var blast_sets := {}
	for id in ids:
		if WeaponDefs.class_of(id) == &"blast":
			blast_sets[WeaponAudio.set_of(id)] = true
	TestLib.check(blast_sets.size() >= 10, "the blast pack uses %d different sets" % blast_sets.size())
	# a def that names its own `sset` names a set that exists; the table of per-weapon voices names sets that exist too
	var bad_named: Array[String] = []
	for id in ids:
		var named := StringName(WeaponDefs.def(id).get("sset", &""))
		if named != &"" and WeaponAudio.data(named).is_empty():
			bad_named.append("%s -> %s" % [id, named])
	for id: StringName in WeaponAudio.ASSIGN:
		if not WeaponDefs.DEFS.has(id) or WeaponAudio.data(WeaponAudio.ASSIGN[id]).is_empty():
			bad_named.append("ASSIGN %s -> %s" % [id, WeaponAudio.ASSIGN[id]])
		elif WeaponAudio.set_of(id) != WeaponAudio.ASSIGN[id] and StringName(WeaponDefs.def(id).get("sset", &"")) == &"":
			bad_named.append("ASSIGN %s is not honoured" % id)
	TestLib.check(bad_named.is_empty(), "every named set (def sset, the ASSIGN table) exists and is honoured (%s)" % str(bad_named))
	TestLib.check(WeaponAudio.set_of(&"no_such_weapon") == &"pst_compact", "an unknown weapon falls back to the compact pistol set instead of crashing")


# ---------------------------------------------------------------------------------------------------------------------------------- layers

func _layers() -> void:
	var was_muted := Sfx.muted
	var was_inside: float = Sfx._inside
	Sfx.muted = false
	Sfx._inside = 0.0
	# a slow gun plays all three layers: the mechanism, the body, the tail
	var amr := WeaponDefs.def(&"amr")
	var s0 := WeaponAudio.shots
	var m0 := WeaponAudio.mechs
	var t0 := WeaponAudio.tails
	WeaponAudio.fire(&"amr", amr)
	var sd := WeaponAudio.data(WeaponAudio.set_of(&"amr"))
	TestLib.check(WeaponAudio.shots == s0 + 1 and WeaponAudio.mechs == m0 + 1 and WeaponAudio.tails == t0 + 1, "a slow shot plays body, mechanism and tail (shots %d, mechs %d, tails %d)" % [WeaponAudio.shots - s0, WeaponAudio.mechs - m0, WeaponAudio.tails - t0])
	TestLib.check(WeaponAudio.last_body == StringName(sd["body"]) and String(WeaponAudio.last_tail).begins_with("wt_"), "the body is the set's (%s) and the tail is a wt_ file (%s)" % [WeaponAudio.last_body, WeaponAudio.last_tail])
	# a rapid-fire gun does not click and echo on every round: some mechanisms, some tails, every body
	var mini := WeaponDefs.def(&"minigun")
	var s1 := WeaponAudio.shots
	var m1 := WeaponAudio.mechs
	var t1 := WeaponAudio.tails
	for i in 12:
		WeaponAudio.fire(&"minigun", mini)
	var dm := WeaponAudio.mechs - m1
	var dt := WeaponAudio.tails - t1
	TestLib.check(WeaponAudio.shots == s1 + 12 and dm >= 1 and dm <= 6 and dt >= 1 and dt <= 6, "a minigun burst of 12 plays 12 bodies, %d mechanism clicks and %d tails (not one of each per round)" % [dm, dt])
	# melee has no mechanism and no tail
	var k0 := WeaponAudio.mechs
	var kt0 := WeaponAudio.tails
	WeaponAudio.fire(&"m_arcsabre", WeaponDefs.def(&"m_arcsabre"))
	TestLib.check(WeaponAudio.mechs == k0 and WeaponAudio.tails == kt0, "a blade swing is a body only")
	# a suppressed shot has the dry tail, an overcharged one none
	WeaponAudio.fire(&"amr", amr, true)
	TestLib.check(WeaponAudio.last_tail == &"wt_dry", "a suppressed shot leaves a dry tail (%s)" % WeaponAudio.last_tail)
	# the TAIL bus: its own bus, sent to SFX, with a reverb that opens indoors
	var bi := AudioServer.get_bus_index(WeaponAudio.TAIL_BUS)
	TestLib.check(bi >= 0 and AudioServer.get_bus_send(bi) == &"SFX" and AudioServer.get_bus_effect(bi, 0) is AudioEffectReverb, "the Tail bus exists, sends to SFX and carries a reverb")
	var rv := AudioServer.get_bus_effect(bi, 0) as AudioEffectReverb
	Sfx._inside = 0.0
	WeaponAudio.fire(&"amr", amr)
	var wet_out := rv.wet
	var tail_out := WeaponAudio.last_tail
	Sfx._inside = 1.0
	WeaponAudio.fire(&"amr", amr)
	var wet_in := rv.wet
	var tail_in := WeaponAudio.last_tail
	TestLib.check(wet_in > wet_out + 0.2 and wet_in <= 0.5, "the reverb send opens indoors (wet %.2f outside, %.2f inside)" % [wet_out, wet_in])
	TestLib.check(tail_in in [&"wt_room", &"wt_hall"] and tail_out != &"wt_room" and tail_out != &"wt_hall", "indoors the tail is a room or a hall (%s), outdoors it is not (%s)" % [tail_in, tail_out])
	Sfx._inside = 1.0
	WeaponAudio.fire(&"p_grit", WeaponDefs.def(&"p_grit"))
	TestLib.check(WeaponAudio.last_tail == &"wt_room", "a hand cannon indoors is a room (%s)" % WeaponAudio.last_tail)
	WeaponAudio.fire(&"amr", amr)
	TestLib.check(WeaponAudio.last_tail == &"wt_hall", "an anti-material rifle indoors is a hall (%s)" % WeaponAudio.last_tail)
	# the distance filter: every 3D voice rolls its highs off with distance
	var filt_bad := 0
	for p: AudioStreamPlayer3D in Sfx._players3d:
		if p.attenuation_filter_cutoff_hz > 5000.0 or p.attenuation_filter_db > -10.0:
			filt_bad += 1
	TestLib.check(Sfx._players3d.size() >= 8 and filt_bad == 0, "the %d positional voices filter highs with distance (cutoff at most 5 kHz, at least -10 dB)" % Sfx._players3d.size())
	Sfx._inside = was_inside
	Sfx.muted = was_muted


func _reload_equip() -> void:
	var was := Sfx.muted
	Sfx.muted = false
	var by_class := {&"pistol": &"pistol", &"smg": &"s_rivet", &"rifle": &"a_pillar", &"shotgun": &"g_bulwark", &"sniper": &"n_ridge", &"heavy": &"l_belt", &"energy": &"e_pulse"}
	var no_reload: Array[String] = []
	for cls: StringName in by_class:
		if StringName(WeaponAudio.data(WeaponAudio.set_of(by_class[cls]))["reload"]) == &"":
			no_reload.append(String(cls))
	TestLib.check(no_reload.is_empty(), "every ranged class has a reload sound (without: %s)" % str(no_reload))
	var names := {}
	for cls: StringName in by_class:
		var id: StringName = by_class[cls]
		var r0 := WeaponAudio.reloads
		var e0 := WeaponAudio.equips
		WeaponAudio.reload_sound(id)
		WeaponAudio.equip_sound(id)
		names[WeaponAudio.data(WeaponAudio.set_of(id))["reload"]] = true
		TestLib.check(WeaponAudio.reloads == r0 + 1 and WeaponAudio.equips == e0 + 1, "%s (%s): a reload and an equip sound play" % [id, cls])
	TestLib.check(names.size() >= 6, "reloads differ by class (%d different files)" % names.size())
	var r1 := WeaponAudio.reloads
	var e1 := WeaponAudio.equips
	WeaponAudio.reload_sound(&"m_arcsabre")
	WeaponAudio.equip_sound(&"m_arcsabre")
	TestLib.check(WeaponAudio.reloads == r1 and WeaponAudio.equips == e1 + 1, "a blade has an equip sound and no reload")
	TestLib.check(_takes(&"wm_trigger") >= 2 and _takes(&"dry_fire") >= 1, "the dry-fire clicks exist")
	WeaponAudio.dry_sound(&"e_pulse")
	WeaponAudio.dry_sound(&"a_pillar")
	Sfx.muted = was


# ---------------------------------------------------------------------------------------------------------------------------------- explosions

func _explosions() -> void:
	var want := {0.5: &"bm_small", 4.0: &"bm_small", 4.1: &"bm_medium", 9.0: &"bm_medium", 9.1: &"bm_large", 18.0: &"bm_large", 18.1: &"bm_huge", 60.0: &"bm_huge"}
	var wrong: Array[String] = []
	for r: float in want:
		if WeaponAudio.explosion_name(r) != want[r]:
			wrong.append("%.1f -> %s" % [r, WeaponAudio.explosion_name(r)])
	TestLib.check(wrong.is_empty(), "the explosion size follows the blast radius (%s)" % str(wrong))
	# every size has its takes, and the bigger the blast the longer it rings
	var lens := []
	for nm: StringName in [&"bm_small", &"bm_medium", &"bm_large", &"bm_huge"]:
		var v := Sfx.variants_of(nm)
		TestLib.check(v.size() >= 3, "%s has %d takes (at least 3)" % [nm, v.size()])
		var total := 0.0
		for st: AudioStream in v:
			total += st.get_length()
		lens.append(total / maxf(1.0, float(v.size())))
	TestLib.check(lens[0] < lens[1] and lens[1] < lens[2] and lens[2] < lens[3], "small, medium, large and huge explosions ring longer and longer (%.2f, %.2f, %.2f, %.2f s)" % [lens[0], lens[1], lens[2], lens[3]])
	TestLib.check(lens[3] >= 2.0 * lens[0], "a huge blast rings at least twice as long as a small one")
	# the BlastTable covers all four sizes
	var sizes := {}
	for id in BlastTable.ids():
		sizes[WeaponAudio.explosion_name(float((BlastTable.entry(id) as Dictionary).get("radius", 0.0)))] = int(sizes.get(WeaponAudio.explosion_name(float((BlastTable.entry(id) as Dictionary).get("radius", 0.0))), 0)) + 1
	TestLib.check(sizes.size() == 4, "the %d entries of the BlastTable use all four explosion sizes (%s)" % [BlastTable.count(), str(sizes)])
	var was := Sfx.muted
	Sfx.muted = false
	var n0 := WeaponAudio.explosions
	for r in [2.0, 6.0, 12.0, 30.0]:
		WeaponAudio.explosion(Vector3(0.0, 1.0, 0.0), float(r))
	TestLib.check(WeaponAudio.explosions == n0 + 4 and WeaponAudio.last_blast == &"bm_huge", "four explosions play, the last of them huge (%s)" % WeaponAudio.last_blast)
	Sfx.muted = was


# ---------------------------------------------------------------------------------------------------------------------------------- materials

func _materials() -> void:
	var firsts := {}
	var missing: Array[String] = []
	var dup: Array[String] = []
	for kind in MATERIALS:
		var nm := StringName("impact_" + String(kind))
		var v := Sfx.variants_of(nm)
		if v.size() < 2:
			missing.append("%s (%d)" % [nm, v.size()])
			continue
		var path := (v[0] as Resource).resource_path
		if firsts.has(path):
			dup.append("%s = %s" % [nm, firsts[path]])
		firsts[path] = nm
	TestLib.check(missing.is_empty(), "every material has an impact sound with two takes or more (%s)" % str(missing))
	TestLib.check(dup.is_empty(), "no two materials share a recording (%s)" % str(dup))
	TestLib.check(_takes(&"ricochet_metal") >= 2 and _takes(&"ricochet_stone") >= 2, "metal and stone have their own ricochet whine")
	TestLib.check((Sfx.variants_of(&"ricochet_metal")[0] as Resource).resource_path != (Sfx.variants_of(&"ricochet_stone")[0] as Resource).resource_path, "the two ricochets are different recordings")
	var was := Sfx.muted
	Sfx.muted = false
	var i0 := WeaponAudio.impacts
	var r0 := WeaponAudio.ricochets
	for kind in MATERIALS:
		WeaponAudio.impact(kind, Vector3(2.0, 1.0, 3.0))
		TestLib.check(WeaponAudio.last_impact == StringName("impact_" + String(kind)), "a hit on %s plays impact_%s" % [kind, kind])
	WeaponAudio.ricochet(&"metal", Vector3.ZERO)
	WeaponAudio.ricochet(&"concrete", Vector3.ZERO)
	TestLib.check(WeaponAudio.impacts == i0 + MATERIALS.size() and WeaponAudio.ricochets == r0 + 2, "impacts and ricochets are counted")
	Sfx.muted = was
	# the world tells the materials apart: a lake, the mud, a trunk, a hull
	var water := ImpactSparks.surface_at(Vector3(0.0, 0.2, 0.0), Vector3.UP)
	TestLib.check(water == &"asphalt", "inside the city a hit on the street is still asphalt (%s)" % water)
	var kinds := {}
	for ix in range(-12, 13):
		for iz in range(-12, 13):
			kinds[ImpactSparks.surface_at(Vector3(float(ix) * 250.0, 5.0, float(iz) * 250.0), Vector3.UP)] = true
	TestLib.check(kinds.has(&"dirt") and kinds.has(&"water"), "out in the land a hit on the ground is the terrain's material: earth and water both occur (%s)" % str(kinds.keys()))
	TestLib.check(ImpactSparks.surface_at(Vector3(3.0, 12.0, 0.0), Vector3.RIGHT) == &"concrete" and ImpactSparks.surface_at(Vector3(3.0, 20.0, 0.0), Vector3.UP) == &"concrete", "a wall and a roof of the city are still concrete")


# ---------------------------------------------------------------------------------------------------------------------------------- markers

func _markers() -> void:
	var missing: Array[String] = []
	for nm in MARKERS:
		if _takes(nm) == 0:
			missing.append(String(nm))
	TestLib.check(missing.is_empty(), "every hit and kill marker sound exists (%s)" % str(missing))
	var was := Sfx.muted
	Sfx.muted = false
	var cases := [
		[false, false, &"flesh", false, &"hit", &""],
		[false, true, &"flesh", false, &"hit_crit", &""],
		[false, false, &"armor", false, &"hit_armor", &""],
		[false, false, &"shield", false, &"hit_shield", &""],
		[true, false, &"flesh", false, &"hit", &"hit_kill"],
		[true, true, &"flesh", false, &"hit", &"hit_kill_head"],
		[true, false, &"flesh", true, &"hit", &"hit_kill_blast"],
	]
	for c: Array in cases:
		var m0 := WeaponAudio.markers
		WeaponAudio.hit_marker(&"a_pillar", bool(c[0]), bool(c[1]), c[2], bool(c[3]))
		var tick: StringName = WeaponAudio.last_marker
		var want_tick: StringName = c[4]
		TestLib.check(WeaponAudio.markers == m0 + 1 and tick == want_tick and WeaponAudio.last_kill == c[5], "kill %s crit %s on %s blast %s: tick %s, kill sound %s" % [c[0], c[1], c[2], c[3], tick, WeaponAudio.last_kill])
	Sfx.muted = was


# ---------------------------------------------------------------------------------------------------------------------------------- haptics

func _haptics() -> void:
	var keys := [&"shot_light", &"shot_heavy", &"shot_huge", &"reload", &"equip", &"reveal", &"hit", &"kill", &"blast_small", &"blast_medium", &"blast_large", &"blast_huge"]
	var gone: Array[String] = []
	for k in keys:
		if not WeaponAudio.HAPTIC_MS.has(k):
			gone.append(String(k))
	TestLib.check(gone.is_empty(), "a haptic pulse is defined for every event (%s)" % str(gone))
	var h := WeaponAudio.HAPTIC_MS
	TestLib.check(h[&"shot_light"] < h[&"shot_heavy"] and h[&"shot_heavy"] < h[&"shot_huge"] and h[&"blast_small"] < h[&"blast_medium"] and h[&"blast_medium"] < h[&"blast_large"] and h[&"blast_large"] < h[&"blast_huge"] and h[&"hit"] < h[&"kill"],
			"bigger events buzz longer (shots %d < %d < %d ms, blasts %d .. %d ms)" % [h[&"shot_light"], h[&"shot_heavy"], h[&"shot_huge"], h[&"blast_small"], h[&"blast_huge"]])
	var on := UiSettings.s_vibration
	UiSettings.s_vibration = true
	var n0 := UiSettings.buzzed
	WeaponAudio.haptic(&"shot_heavy")
	TestLib.check(UiSettings.buzzed == n0 + 1 and int(UiSettings.last_plan["ms"]) > 0, "a heavy shot buzzes the device or pad")
	WeaponAudio.haptic(&"nothing")
	WeaponAudio.haptic(&"")
	TestLib.check(UiSettings.buzzed == n0 + 1, "an unknown event buzzes nothing")
	UiSettings.s_vibration = false
	WeaponAudio.haptic(&"blast_huge")
	TestLib.check(UiSettings.buzzed == n0 + 1, "with vibration off nothing buzzes")
	UiSettings.s_vibration = on
	# a shot fires a pulse by its weight: a pistol click is light, a launcher is huge
	UiSettings.s_vibration = true
	var was := Sfx.muted
	Sfx.muted = false
	var b0 := UiSettings.buzzed
	WeaponAudio.fire(&"orbital", WeaponDefs.def(&"orbital"))
	var huge_ms := int(UiSettings.last_plan["ms"]) if UiSettings.buzzed > b0 else 0
	var b1 := UiSettings.buzzed
	WeaponAudio.fire(&"p_spark", WeaponDefs.def(&"p_spark"))
	var light_ms := int(UiSettings.last_plan["ms"]) if UiSettings.buzzed > b1 else 0
	TestLib.check(huge_ms > light_ms and huge_ms >= 20, "an orbital beacon (%d ms) buzzes longer than a compact pistol (%d ms)" % [huge_ms, light_ms])
	Sfx.muted = was
	UiSettings.s_vibration = on


# ---------------------------------------------------------------------------------------------------------------------------------- clipping

func _peak_of(levels: Dictionary, nm: StringName) -> float:
	var worst := -99.0
	var keys: Array[String] = [String(nm)]
	for k in 16:
		keys.append("%s_%d" % [nm, k])
	for key in keys:
		if levels.has(key):
			worst = maxf(worst, float((levels[key] as Dictionary)["peak"]))
	return worst


func _clipping(ids: Array[StringName]) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEVELS))
	TestLib.check(data is Dictionary and (data as Dictionary).size() >= 140, "the generator's level table lists the new files (%d)" % ((data as Dictionary).size() if data is Dictionary else 0))
	var levels: Dictionary = data as Dictionary
	var loud: Array[String] = []
	var absent: Array[String] = []
	var quiet: Array[String] = []
	for k: String in levels:
		var e: Dictionary = levels[k]
		if float(e["peak"]) > -3.0:
			loud.append("%s %.1f" % [k, e["peak"]])
		if float(e["peak"]) < -24.0:
			quiet.append("%s %.1f" % [k, e["peak"]])
		if not ResourceLoader.exists("res://assets/audio/%s.ogg" % k):
			absent.append(k)
	TestLib.check(loud.is_empty(), "no generated file peaks above -3 dBFS (%s)" % str(loud.slice(0, 6)))
	TestLib.check(quiet.is_empty(), "no generated file is buried below -24 dBFS (%s)" % str(quiet.slice(0, 6)))
	TestLib.check(absent.is_empty(), "every file of the level table is in assets/audio (%s)" % str(absent.slice(0, 6)))
	# the worst stack: body + mechanism + tail at their relative levels, all peaking in the same instant, stays under full scale
	var worst := -99.0
	var worst_id: StringName = &""
	for id in ids:
		var sd := WeaponAudio.data(WeaponAudio.set_of(id))
		var d := WeaponDefs.def(id)
		var vol := float(d.get("vol", 0.0)) + float(sd["db"])
		var body_pk := _peak_of(levels, StringName(sd["body"]))
		if body_pk < -90.0:
			body_pk = -9.0                                       # the older recordings: tests/test_audio_real_samples.gd holds them under -9 dBFS
		var sum := pow(10.0, (body_pk + vol) / 20.0)
		if StringName(sd["mech"]) != &"":
			sum += pow(10.0, (_peak_of(levels, StringName(sd["mech"])) - 2.0) / 20.0)
		if StringName(sd["tail"]) != &"":
			sum += pow(10.0, (_peak_of(levels, StringName(sd["tail"])) + vol - 7.0) / 20.0)
		var db := 20.0 * log(sum) / log(10.0)
		if db > worst:
			worst = db
			worst_id = id
	TestLib.check(worst <= -1.0, "the loudest stack of layers (%s) peaks at %.1f dBFS before the limiter (at most -1.0)" % [worst_id, worst])
	TestLib.check(AudioServer.get_bus_effect_count(0) >= 1 and AudioServer.get_bus_effect(0, 0) is AudioEffectLimiter, "the Master bus ends in a limiter: a firefight never clips")
	var lim := AudioServer.get_bus_effect(0, 0) as AudioEffectLimiter
	TestLib.check(lim != null and lim.ceiling_db <= -0.1, "its ceiling is below full scale (%.1f dB)" % (lim.ceiling_db if lim != null else 0.0))
	# explosions are the loudest sounds of the game and duck the rest: they are normalised to the same ceiling as the shots
	var exp_pk := -99.0
	for nm: StringName in [&"bm_small", &"bm_medium", &"bm_large", &"bm_huge"]:
		exp_pk = maxf(exp_pk, _peak_of(levels, nm))
	TestLib.check(exp_pk <= -3.0 and exp_pk >= -12.0, "the explosions peak between -12 and -3 dBFS (%.1f)" % exp_pk)


# ---------------------------------------------------------------------------------------------------------------------------------- voice rules

func _voices() -> void:
	var rules: Array[String] = []
	for nm: StringName in [&"bm_small", &"bm_huge", &"wm_slide_l", &"wt_large", &"wr_rifle", &"we_heavy", &"hit_kill", &"impact_wood", &"ricochet_metal"]:
		var rule: Array = Sfx._rule(nm)
		if String(rule[0]) == "":
			rules.append(String(nm))
	TestLib.check(rules.is_empty(), "the new sound families have their own voice rules (no default rule for: %s)" % str(rules))
	var rule: Array = Sfx._rule(&"bm_huge")
	TestLib.check(int(rule[1]) >= 4, "an explosion has the top priority, a tail or a click does not (explosion %d, tail %d)" % [int(rule[1]), int((Sfx._rule(&"wt_large") as Array)[1])])
	TestLib.check(int((Sfx._rule(&"wt_large") as Array)[1]) < int(rule[1]) and int((Sfx._rule(&"wm_slide_l") as Array)[1]) < int(rule[1]), "tails and mechanisms never steal a voice from an explosion")
