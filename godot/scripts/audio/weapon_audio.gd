class_name WeaponAudio
extends RefCounted
## What a weapon sounds like (wave 114): every weapon has a SOUND SET (`set_of(id)`), a set is a stack of LAYERS that the game mixes at run time instead of one recording:
##   mech    the mechanism, a short click or clack under the shot (slide, bolt, pump, cylinder, charge-up, spin-up, string, pin ...: files wm_*), only when the gun fires slowly enough to hear it
##   body    the shot itself (shot_v3_*, shot_v4_*, the older shot_*: three or four takes, never the same twice in a row)
##   tail    what the air does afterwards (wt_*: small, medium, large, huge outdoors, room and hall indoors, canyon), played a few ms late on the TAIL bus, whose reverb opens the closer the hero
##           is to a roof (the room send of the SFX bus: `Sfx._inside`); a suppressed gun and an energy weapon have a dry one
##   reload / equip  per class (wr_*, we_*)
## The DISTANCE FILTER is the low-pass of the 3D voices of Sfx (a far shot is dull: Sfx.play_at also swaps in the far version beyond FAR_SHOT_DIST).
## There are 60+ sets and at least four in every major class (pistol, smg, rifle, shotgun, sniper, heavy / lmg, launcher, energy, melee), each with its own body; a weapon's set follows its def `snd`
## (the roster's choice), else its family (a hash of the id picks one of the family's sets, so the 32 grenades, mines and strikes do not share one sound), and a def may name `sset`.
## Also here: explosions by size (bm_small .. bm_huge from the BlastTable radius), impacts and ricochets by material, the hit and kill markers, and haptics (UiSettings.buzz).
## Built by tools/audio/make_weapons_v4.py. Tests: tests/test_weapon_audio_v3.gd.

## [set id, class, body, mech, tail, reload, equip, level offset in dB]
const SETS: Array = [
	# pistols
	[&"pst_compact", &"pistol", &"shot_v3_pistol", &"wm_slide_l", &"wt_small", &"wr_pistol", &"we_light", 0.0],
	[&"pst_revolver", &"pistol", &"shot_rev", &"wm_cyl", &"wt_medium", &"wr_pistol", &"we_light", 0.0],
	[&"pst_magnum", &"pistol", &"shot_magnum", &"wm_slide_h", &"wt_medium", &"wr_pistol", &"we_heavy", 1.0],
	[&"pst_machine", &"pistol", &"shot_mp", &"wm_slide_l", &"wt_small", &"wr_pistol", &"we_light", -1.5],
	[&"pst_burst", &"pistol", &"shot_burst", &"wm_slide_l", &"wt_small", &"wr_pistol", &"we_light", -1.0],
	[&"pst_twin", &"pistol", &"shot_twin", &"wm_slide_l", &"wt_small", &"wr_pistol", &"we_light", -0.5],
	[&"pst_silenced", &"pistol", &"shot_v3_supp", &"wm_slide_l", &"wt_dry", &"wr_pistol", &"we_light", 0.0],
	[&"pst_stun", &"pistol", &"shot_stun", &"wm_trigger", &"wt_dry", &"wr_energy", &"we_energy", 0.0],
	# submachine guns
	[&"smg_compact", &"smg", &"shot_v3_smg", &"wm_slide_l", &"wt_small", &"wr_smg", &"we_light", 0.0],
	[&"smg_flux", &"smg", &"shot_flux", &"wm_cell", &"wt_dry", &"wr_energy", &"we_energy", 0.0],
	[&"smg_burst", &"smg", &"shot_burst", &"wm_slide_l", &"wt_small", &"wr_smg", &"we_light", -0.5],
	[&"smg_silenced", &"smg", &"shot_v3_supp", &"wm_slide_l", &"wt_dry", &"wr_smg", &"we_light", -1.5],
	[&"smg_machine", &"smg", &"shot_mp", &"wm_slide_l", &"wt_small", &"wr_smg", &"we_light", -1.0],
	# rifles
	[&"rfl_assault", &"rifle", &"shot_v3_ar", &"wm_slide_h", &"wt_large", &"wr_rifle", &"we_heavy", 0.0],
	[&"rfl_battle", &"rifle", &"shot_v3_battle", &"wm_bolt", &"wt_large", &"wr_rifle", &"we_heavy", 0.5],
	[&"rfl_carbine", &"rifle", &"shot_v3_carbine", &"wm_slide_l", &"wt_medium", &"wr_rifle", &"we_light", -0.5],
	[&"rfl_dmr", &"rifle", &"shot_v3_dmr", &"wm_bolt", &"wt_large", &"wr_rifle", &"we_heavy", 0.5],
	[&"rfl_bullpup", &"rifle", &"shot_bpup", &"wm_slide_l", &"wt_medium", &"wr_rifle", &"we_light", 0.0],
	[&"rfl_ar2", &"rifle", &"shot_ar2", &"wm_slide_h", &"wt_medium", &"wr_rifle", &"we_heavy", 0.0],
	[&"rfl_classic", &"rifle", &"shot", &"wm_slide_l", &"wt_medium", &"wr_rifle", &"we_light", 0.0],
	[&"rfl_silenced", &"rifle", &"shot_v3_supp", &"wm_slide_h", &"wt_dry", &"wr_rifle", &"we_heavy", 0.0],
	# shotguns
	[&"sg_pump", &"shotgun", &"shot_v3_shotgun", &"wm_pump", &"wt_medium", &"wr_shotgun", &"we_heavy", 0.0],
	[&"sg_scatter", &"shotgun", &"shot_scatter", &"wm_pump", &"wt_medium", &"wr_shotgun", &"we_heavy", 0.0],
	[&"sg_auto", &"shotgun", &"shot_v4_sg_auto", &"wm_slide_h", &"wt_medium", &"wr_shotgun", &"we_heavy", 0.0],
	[&"sg_slug", &"shotgun", &"shot_v4_sg_slug", &"wm_pump", &"wt_large", &"wr_shotgun", &"we_heavy", 0.5],
	[&"sg_sawn", &"shotgun", &"shot_v4_sg_sawn", &"wm_pump", &"wt_large", &"wr_shotgun", &"we_heavy", 1.0],
	# snipers and bows
	[&"snp_bolt", &"sniper", &"shot_v3_sniper", &"wm_bolt", &"wt_huge", &"wr_sniper", &"we_heavy", 0.0],
	[&"snp_silenced", &"sniper", &"shot_v3_supp", &"wm_bolt", &"wt_dry", &"wr_sniper", &"we_heavy", 1.0],
	[&"snp_marksman", &"sniper", &"shot_v3_dmr", &"wm_slide_h", &"wt_large", &"wr_sniper", &"we_heavy", 0.0],
	[&"snp_amr", &"sniper", &"shot_amr", &"wm_bolt", &"wt_huge", &"wr_sniper", &"we_heavy", 1.0],
	[&"snp_rail", &"sniper", &"shot_rail", &"wm_charge", &"wt_large", &"wr_energy", &"we_energy", 0.0],
	[&"snp_lance", &"sniper", &"shot_lance", &"wm_charge", &"wt_large", &"wr_energy", &"we_energy", 0.0],
	[&"snp_beam", &"sniper", &"shot_v3_beam", &"wm_charge", &"wt_medium", &"wr_energy", &"we_energy", 0.0],
	[&"snp_bow", &"sniper", &"shot_v3_bow", &"wm_string", &"wt_dry", &"wr_pistol", &"we_light", 0.0],
	[&"snp_crossbow", &"sniper", &"shot_xbow", &"wm_string", &"wt_dry", &"wr_pistol", &"we_light", 0.0],
	# heavy: belt-fed, rotary, flame
	[&"lmg_belt", &"heavy", &"shot_v3_lmg", &"wm_slide_h", &"wt_large", &"wr_lmg", &"we_heavy", 0.0],
	[&"lmg_classic", &"heavy", &"shot_lmg", &"wm_slide_h", &"wt_large", &"wr_lmg", &"we_heavy", 0.0],
	[&"lmg_rotary", &"heavy", &"shot_v3_rotary", &"wm_spin", &"wt_medium", &"wr_lmg", &"we_heavy", 0.0],
	[&"lmg_mini", &"heavy", &"shot_mini", &"wm_spin", &"wt_medium", &"wr_lmg", &"we_heavy", 0.0],
	[&"lmg_chain", &"heavy", &"shot_chaingun", &"wm_spin", &"wt_medium", &"wr_lmg", &"we_heavy", 0.0],
	[&"hvy_flame", &"heavy", &"shot_v3_flame", &"wm_trigger", &"wt_dry", &"wr_launcher", &"we_heavy", 0.0],
	[&"hvy_flame2", &"heavy", &"shot_flame", &"wm_trigger", &"wt_dry", &"wr_launcher", &"we_heavy", 0.0],
	[&"hvy_gravity", &"heavy", &"shot_gravity", &"wm_charge", &"wt_medium", &"wr_energy", &"we_energy", 0.0],
	# launchers
	[&"lau_rocket", &"blast", &"shot_v4_rocket", &"wm_slide_h", &"wt_huge", &"wr_launcher", &"we_heavy", 0.0],
	[&"lau_heavy", &"blast", &"shot_v4_rocket_h", &"wm_slide_h", &"wt_huge", &"wr_launcher", &"we_heavy", 1.0],
	[&"lau_gl", &"blast", &"shot_v4_gl", &"wm_slide_h", &"wt_medium", &"wr_launcher", &"we_heavy", 0.0],
	[&"lau_mortar", &"blast", &"shot_v4_mortar", &"wm_slide_h", &"wt_huge", &"wr_launcher", &"we_heavy", 0.5],
	[&"lau_missile", &"blast", &"shot_cmissile", &"wm_slide_h", &"wt_large", &"wr_launcher", &"we_heavy", 0.0],
	[&"lau_seeker", &"blast", &"shot_seeker", &"wm_charge", &"wt_large", &"wr_launcher", &"we_heavy", 0.0],
	[&"lau_napalm", &"blast", &"shot_napalm", &"wm_slide_h", &"wt_large", &"wr_launcher", &"we_heavy", 0.0],
	[&"lau_plasma", &"blast", &"shot_eplasma", &"wm_charge", &"wt_medium", &"wr_energy", &"we_energy", 0.0],
	[&"lau_pod", &"blast", &"shot_epod", &"wm_charge", &"wt_medium", &"wr_energy", &"we_energy", 0.0],
	[&"lau_singularity", &"blast", &"shot_sing", &"wm_charge", &"wt_large", &"wr_energy", &"we_energy", 0.0],
	[&"lau_orbital", &"blast", &"shot_orbital", &"wm_beacon", &"wt_huge", &"wr_energy", &"we_energy", 0.0],
	[&"lau_railgun", &"blast", &"shot_railgun", &"wm_charge", &"wt_huge", &"wr_energy", &"we_energy", 0.5],
	# thrown, placed and called in
	[&"thr_frag", &"blast", &"shot_v4_throw", &"wm_pin", &"wt_dry", &"wr_launcher", &"we_light", 0.0],
	[&"mine_place", &"blast", &"shot_v4_mine", &"wm_mine", &"wt_dry", &"wr_launcher", &"we_light", 0.0],
	[&"strike_call", &"blast", &"shot_v4_strike", &"wm_beacon", &"wt_dry", &"wr_energy", &"we_energy", 0.0],
	# energy
	[&"en_pulse", &"energy", &"shot_v3_energy", &"wm_cell", &"wt_dry", &"wr_energy", &"we_energy", 0.0],
	[&"en_beam", &"energy", &"shot_v3_beam", &"wm_cell", &"wt_small", &"wr_energy", &"we_energy", -1.0],
	[&"en_plasma", &"energy", &"shot_eplasma", &"wm_cell", &"wt_small", &"wr_energy", &"we_energy", -0.5],
	[&"en_ray", &"energy", &"shot_ebeam", &"wm_charge", &"wt_medium", &"wr_energy", &"we_energy", 0.0],
	[&"en_repeater", &"energy", &"shot_erepeat", &"wm_cell", &"wt_dry", &"wr_energy", &"we_energy", 0.0],
	[&"en_spike", &"energy", &"shot_espike", &"wm_cell", &"wt_small", &"wr_energy", &"we_energy", 0.0],
	[&"en_exotic", &"energy", &"shot_v3_exotic", &"wm_charge", &"wt_medium", &"wr_energy", &"we_energy", 0.0],
	[&"en_arc", &"energy", &"shot_arc", &"wm_cell", &"wt_small", &"wr_energy", &"we_energy", 0.0],
	# quantum
	[&"qt_flux", &"quantum", &"shot_v3_quantum", &"wm_charge", &"wt_dry", &"wr_energy", &"we_energy", 0.0],
	[&"qt_blink", &"quantum", &"shot_qblink", &"wm_charge", &"wt_dry", &"wr_energy", &"we_energy", 0.0],
	[&"qt_collapse", &"quantum", &"shot_qcollapse", &"wm_charge", &"wt_medium", &"wr_energy", &"we_energy", 0.0],
	[&"qt_link", &"quantum", &"shot_qlink", &"wm_charge", &"wt_dry", &"wr_energy", &"we_energy", 0.0],
	[&"qt_phase", &"quantum", &"shot_qphase", &"wm_charge", &"wt_dry", &"wr_energy", &"we_energy", 0.0],
	[&"qt_stasis", &"quantum", &"shot_qstasis", &"wm_charge", &"wt_dry", &"wr_energy", &"we_energy", 0.0],
	[&"qt_super", &"quantum", &"shot_qsuper", &"wm_charge", &"wt_dry", &"wr_energy", &"we_energy", 0.0],
	# melee
	[&"ml_blade", &"melee", &"shot_v3_blade", &"", &"", &"", &"we_melee", 0.0],
	[&"ml_blunt", &"melee", &"shot_v3_blunt", &"", &"", &"", &"we_melee", 0.0],
	[&"ml_chain", &"melee", &"shot_v3_chain", &"", &"", &"", &"we_heavy", 0.0],
	[&"ml_katana", &"melee", &"melee_katana", &"", &"", &"", &"we_melee", 0.0],
	[&"ml_bat", &"melee", &"melee_bat", &"", &"", &"", &"we_melee", 0.0],
	[&"ml_knife", &"melee", &"melee_tknife", &"", &"", &"", &"we_melee", 0.0],
	[&"ml_whip", &"melee", &"melee_whip", &"", &"", &"", &"we_melee", 0.0],
	[&"ml_arcblade", &"melee", &"melee_eblade", &"", &"", &"", &"we_energy", 0.0],
	[&"ml_maul", &"melee", &"melee_emaul", &"", &"", &"", &"we_energy", 0.0],
	[&"ml_cleaver", &"melee", &"melee_blade", &"", &"", &"", &"we_melee", 0.0],
]

## Where the wave 113 roster gave a whole family ONE body (a dozen SMGs on shot_v3_smg, eight shotguns on shot_v3_shotgun) or pointed a weapon at another class's set (a plasma pistol on the launcher's plasma),
## the weapon's character picks its set here: fast and light, heavy and slow, silenced, double-barrelled. The older weapons (carbine, marksman, breacher, dmr ...) keep the recording their def names (the
## `snd` of a hitscan gun is its own recorded sound, tests/test_audio_real_samples.gd); a silenced weapon keeps the silenced body. Every set of a major class has at least one weapon (tests/test_weapon_audio_v3.gd
## checks it). `sset` in a def still wins.
const ASSIGN := {
	# pistols
	&"p_grit": &"pst_magnum", &"p_nail": &"pst_machine", &"p_twin": &"pst_twin", &"p_split": &"pst_burst", &"p_flare": &"pst_revolver",
	# submachine guns
	&"vector": &"smg_burst", &"s_hush": &"smg_silenced", &"s_gale": &"smg_machine", &"s_static": &"smg_flux", &"s_double": &"smg_burst", &"s_drum": &"smg_machine",
	# rifles and marksman rifles
	&"a_sable": &"rfl_silenced", &"c_quill": &"rfl_silenced", &"d_whisper": &"rfl_silenced", &"d_arbiter": &"snp_marksman", &"d_lancer": &"snp_marksman", &"n_umbra": &"snp_silenced",
	# shotguns
	&"g_rampart": &"sg_auto", &"g_twinbore": &"sg_sawn", &"g_cyclone": &"sg_auto", &"g_doorkick": &"sg_slug", &"g_slugger": &"sg_slug",
	# launchers
	&"la_rocket": &"lau_rocket", &"la_bunker": &"lau_heavy", &"la_recoilless": &"lau_heavy", &"la_pump": &"lau_gl", &"la_revolver": &"lau_gl", &"la_mortar": &"lau_mortar", &"la_plasma": &"lau_plasma",
	# energy
	&"eplasma": &"en_plasma", &"e_laser": &"en_beam",
}

## A blast-pack weapon whose `snd` is the plain `shot` (or a def with no `snd`) has no voice of its own: its FAMILY picks the set (a hash of the id chooses among the family's sets).
const FAMILY_SETS := {
	&"grenade": [&"thr_frag"], &"mine": [&"mine_place"], &"strike": [&"strike_call"], &"launcher": [&"lau_rocket", &"lau_heavy", &"lau_gl", &"lau_mortar"],
	&"pistol": [&"pst_compact", &"pst_revolver", &"pst_magnum", &"pst_machine"], &"smg": [&"smg_compact", &"smg_burst", &"smg_machine"],
	&"assault": [&"rfl_assault", &"rfl_battle", &"rfl_bullpup", &"rfl_ar2"], &"battle": [&"rfl_battle", &"rfl_dmr"], &"carbine": [&"rfl_carbine", &"rfl_bullpup"], &"dmr": [&"rfl_dmr", &"snp_marksman"],
	&"shotgun": [&"sg_pump", &"sg_auto", &"sg_slug", &"sg_sawn", &"sg_scatter"], &"sniper": [&"snp_bolt", &"snp_amr"], &"bow": [&"snp_bow", &"snp_crossbow"],
	&"lmg": [&"lmg_belt", &"lmg_classic"], &"rotary": [&"lmg_rotary", &"lmg_mini", &"lmg_chain"], &"flamer": [&"hvy_flame", &"hvy_flame2"],
	&"energy": [&"en_pulse", &"en_beam", &"en_plasma", &"en_repeater", &"en_spike"], &"exotic": [&"en_exotic", &"en_arc"], &"quantum": [&"qt_flux", &"qt_blink", &"qt_link", &"qt_phase"],
	&"melee": [&"ml_blade", &"ml_blunt", &"ml_katana", &"ml_cleaver"],
}
## Explosion sizes: blast radius in metres up to which the size applies.
const BLAST_SIZES: Array = [[4.0, &"bm_small"], [9.0, &"bm_medium"], [18.0, &"bm_large"], [1.0e9, &"bm_huge"]]
const HAPTIC_MS := {&"shot_light": 6, &"shot_heavy": 22, &"shot_huge": 40, &"reload": 12, &"equip": 10, &"reveal": 45, &"hit": 5, &"kill": 14, &"blast_small": 30, &"blast_medium": 55, &"blast_large": 80, &"blast_huge": 120}
const TAIL_BUS := &"Tail"

static var _rows := {}                       ## set id -> {cls, body, mech, tail, reload, equip, db}
static var _by_body := {}                    ## body name -> set id (the first set that owns it)
static var _by_class := {}                   ## class -> Array of set ids
static var _tail_players: Array[AudioStreamPlayer] = []
static var _tail_next := 0
static var _reverb: AudioEffectReverb
static var _count := 0                       ## shots fired through fire(): the mech and the tail only play on some
static var shots := 0                        ## counters (tests wait on them)
static var mechs := 0
static var tails := 0
static var reloads := 0
static var equips := 0
static var explosions := 0
static var markers := 0
static var impacts := 0
static var ricochets := 0
static var last_marker: StringName = &""     ## the tick of the last hit marker (hit, hit_crit, hit_armor, hit_shield) and the thock of the last kill
static var last_kill: StringName = &""
static var last_impact: StringName = &""
static var last_body: StringName = &""
static var last_tail: StringName = &""
static var last_blast: StringName = &""


static func _build() -> void:
	if not _rows.is_empty():
		return
	for r: Array in SETS:
		_rows[r[0]] = {"id": r[0], "cls": r[1], "body": r[2], "mech": r[3], "tail": r[4], "reload": r[5], "equip": r[6], "db": float(r[7])}
		if not _by_body.has(r[2]):
			_by_body[r[2]] = r[0]
		if not _by_class.has(r[1]):
			_by_class[r[1]] = []
		(_by_class[r[1]] as Array).append(r[0])


static func all_sets() -> Array[StringName]:
	_build()
	var out: Array[StringName] = []
	for k: StringName in _rows:
		out.append(k)
	return out


static func data(set_id: StringName) -> Dictionary:
	_build()
	return _rows.get(set_id, {})


## The sets of a weapon class.
static func sets_of_class(cls: StringName) -> Array:
	_build()
	return _by_class.get(cls, [])


## The sound set of weapon `id`: its def `sset`, else the ASSIGN table, else the set that owns its def `snd` body, else (a generic body) one of its family's sets by a hash of the id, else a set of its class.
static func set_of(id: StringName) -> StringName:
	_build()
	if not WeaponDefs.DEFS.has(id):
		return &"pst_compact"
	var d := WeaponDefs.def(id)
	var forced := StringName(d.get("sset", &""))
	if forced != &"" and _rows.has(forced):
		return forced
	if ASSIGN.has(id) and _rows.has(ASSIGN[id]):
		return ASSIGN[id]
	var body := StringName(d.get("snd", &""))
	if body == &"" and StringName(d.get("kind", &"")) == &"hit" and WeaponDefs.class_of(id) != &"blast":
		body = &"shot"                                                                                # a hitscan gun that names no sound (the carbine) is the classic rifle shot
	var generic := body == &"" or (body == &"shot" and WeaponDefs.class_of(id) == &"blast")        # the blast pack never got a voice of its own: its FAMILY picks; the older guns keep their `shot`
	if not generic and _by_body.has(body):
		return _by_body[body]
	var fam := WeaponDefs.family_of(id)
	var list: Array = FAMILY_SETS.get(fam, [])
	if list.is_empty():
		list = FAMILY_SETS.get(WeaponDefs.class_of(id), [])
	if list.is_empty():
		list = _by_class.get(WeaponDefs.class_of(id), [&"pst_compact"])
	return list[absi(String(id).hash()) % list.size()]


# ---------------------------------------------------------------------------------------------------------------------------------- playing

## The shot of the hero's weapon: the body (the set's, a suppressed or overcharged variant when asked), the mechanism under it, the tail after it. `vol` / `pitch` are the def's.
static func fire(id: StringName, def: Dictionary, suppressed := false, overcharged := false) -> void:
	_build()
	var sd := data(set_of(id))
	if sd.is_empty():
		return
	_count += 1
	shots += 1
	var body := Sfx.shot_sound(StringName(sd["body"]), suppressed, overcharged)
	last_body = body
	var interval := float(def.get("interval", 0.2))
	var slow := interval >= 0.16
	if StringName(sd["mech"]) != &"" and (slow or _count % 3 == 0):                # the mechanism first (the hammer falls, the bolt cycles), then the shot on top of it
		mechs += 1
		Sfx.play(StringName(sd["mech"]), -2.0, randf_range(0.96, 1.05))
	var vol := float(def.get("vol", 0.0)) + float(sd["db"])
	var pitch := randf_range(float(def.get("pitch_lo", 1.0)), float(def.get("pitch_hi", 1.0)))
	Sfx.play(body, vol, pitch)
	if StringName(sd["tail"]) != &"" and (slow or _count % 3 == 1) and not overcharged:
		_tail(StringName(sd["tail"]), vol, suppressed)
	haptic(&"shot_huge" if String(sd["cls"]) == "blast" or interval >= 0.9 else (&"shot_heavy" if interval >= 0.3 else (&"shot_light" if slow or _count % 3 == 0 else &"")))


static func reload_sound(id: StringName) -> void:
	_build()
	var sd := data(set_of(id))
	if sd.is_empty() or StringName(sd["reload"]) == &"":
		Sfx.play(&"reload", 0.0, 1.0)
		return
	reloads += 1
	Sfx.play(StringName(sd["reload"]), -2.0, 1.0)
	haptic(&"reload")


static func equip_sound(id: StringName) -> void:
	_build()
	var sd := data(set_of(id))
	if sd.is_empty() or StringName(sd["equip"]) == &"":
		Sfx.play(&"reload", -9.0, 1.5)
		return
	equips += 1
	Sfx.play(StringName(sd["equip"]), -3.0, 1.0)
	haptic(&"equip")


## The empty click: the set's trigger click for an energy weapon, the generic dry fire otherwise.
static func dry_sound(id: StringName) -> void:
	_build()
	var sd := data(set_of(id))
	if not sd.is_empty() and (String(sd["mech"]) == "wm_charge" or String(sd["mech"]) == "wm_cell"):
		Sfx.play(&"wm_trigger", -1.0, 1.0)
	else:
		Sfx.dry_fire()


## The tail on the TAIL bus: late by a few tens of ms, bigger and longer for a big weapon; indoors (Sfx._inside) a room or a hall, and the bus's reverb opens.
static func _tail(kind: StringName, vol: float, suppressed: bool) -> void:
	if suppressed:
		kind = &"wt_dry"
	var inside := clampf(float(Sfx._inside), 0.0, 1.0)
	if inside > 0.5 and kind != &"wt_dry":
		kind = &"wt_hall" if (kind == &"wt_large" or kind == &"wt_huge") else &"wt_room"
	elif (kind == &"wt_large" or kind == &"wt_huge") and randf() < 0.35:
		kind = &"wt_canyon"
	var streams := Sfx.variants_of(kind)
	if streams.is_empty() or not _ensure_tail():
		return
	_reverb.wet = lerpf(0.08, 0.42, inside)
	var p := _tail_players[_tail_next % _tail_players.size()]
	_tail_next += 1
	p.stream = streams[randi() % streams.size()]
	p.volume_db = clampf(vol - 7.0 + 4.0 * inside, -30.0, 0.0)
	p.pitch_scale = randf_range(0.96, 1.04)
	last_tail = kind
	tails += 1
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and not Sfx.muted:
		tree.create_timer(randf_range(0.025, 0.06), true, false, true).timeout.connect(p.play)


## The TAIL bus (reverb, sends to SFX) and its voices, made on first use.
static func _ensure_tail() -> bool:
	if not _tail_players.is_empty() and is_instance_valid(_tail_players[0]) and is_instance_valid(_reverb):
		return true
	var bi := AudioServer.get_bus_index(TAIL_BUS)
	if bi < 0:
		AudioServer.add_bus()
		bi = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, TAIL_BUS)
		AudioServer.set_bus_send(bi, &"SFX")
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.8
		rv.damping = 0.5
		rv.spread = 1.0
		rv.dry = 1.0
		rv.wet = 0.1
		AudioServer.add_bus_effect(bi, rv)
	_reverb = AudioServer.get_bus_effect(bi, 0) as AudioEffectReverb
	if _reverb == null:
		return false
	_tail_players.clear()
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = TAIL_BUS
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		Sfx.add_child(p)
		_tail_players.append(p)
	return true


# ---------------------------------------------------------------------------------------------------------------------------------- explosions, impacts, markers

## The explosion sound of a blast radius: bm_small (under 4 m), bm_medium, bm_large, bm_huge (over 18 m).
static func explosion_name(radius: float) -> StringName:
	for row: Array in BLAST_SIZES:
		if radius <= float(row[0]):
			return row[1]
	return &"bm_huge"


## An explosion at `pos`: the size file by radius, a little deeper the bigger it is, a far copy beyond Sfx.FAR_SHOT_DIST is left to the distance filter of the 3D voice.
static func explosion(pos: Vector3, radius: float, vol := -3.0, pitch := 1.0) -> void:
	var nm := explosion_name(radius)
	last_blast = nm
	explosions += 1
	Sfx.play_at(nm, pos, vol, pitch * lerpf(1.08, 0.92, clampf(radius / 24.0, 0.0, 1.0)))
	var size := &"blast_small" if nm == &"bm_small" else (&"blast_medium" if nm == &"bm_medium" else (&"blast_large" if nm == &"bm_large" else &"blast_huge"))
	if is_instance_valid(Game.player) and (Game.player as Node3D).global_position.distance_to(pos) < radius * 3.0 + 12.0:
		haptic(size)


## A material hit by a bullet: wood, dirt, foliage, water, armour and shield have their own impact, the five of Sfx the rest; metal and stone (and glancing concrete) ricochet with their own whine.
static func impact(kind: StringName, pos: Vector3, normal := Vector3.UP) -> void:
	var known := [&"wood", &"dirt", &"foliage", &"water", &"armor", &"shield"]
	impacts += 1
	last_impact = StringName("impact_" + String(kind))
	if known.has(kind):
		Sfx.play_at(last_impact, pos, -2.0)
		return
	Sfx.impact(kind, pos, normal)


static func ricochet(kind: StringName, pos: Vector3) -> void:
	ricochets += 1
	Sfx.play_at(&"ricochet_metal" if kind == &"metal" else &"ricochet_stone", pos, -5.0, randf_range(0.92, 1.12))


## The hit and kill marker: a plain tick, a head shot, an armoured or shielded target, a critical; a kill adds the dull thock and glassy tick (a head kill, a blast kill have their own).
static func hit_marker(weapon_id: StringName, kill: bool, crit: bool, victim_kind: StringName = &"flesh", blast := false) -> void:
	var h := WeaponDefs.hit_snd(weapon_id)
	markers += 1
	var nm: StringName = &"hit"
	var vol := float(h[1]) - 6.0
	var pitch := float(h[0]) * (1.25 if kill else (1.1 if crit else 1.0))
	if victim_kind == &"shield":
		nm = &"hit_shield"
		pitch = 1.0
	elif victim_kind == &"armor":
		nm = &"hit_armor"
		pitch = 1.0
	elif crit and not kill:
		nm = &"hit_crit"
		pitch = 1.0
	last_marker = nm
	last_kill = &""
	Sfx.play(nm, vol if nm == &"hit" else -4.0, pitch)
	if kill:
		var kn: StringName = &"hit_kill_blast" if blast else (&"hit_kill_head" if crit else &"hit_kill")
		last_kill = kn
		Sfx.play(kn, -4.0, float(h[0]) * 0.9 + 0.15 if kn == &"hit_kill" else 1.0)
		haptic(&"kill")
	else:
		haptic(&"hit")
	if StringName(h[2]) != &"":
		Sfx.play(StringName(h[2]), -9.0, float(h[0]) + 0.3)


## A haptic pulse by kind (UiSettings.buzz honours the vibration setting and the device).
static func haptic(kind: StringName) -> void:
	if kind == &"" or not HAPTIC_MS.has(kind):
		return
	UiSettings.buzz(int(HAPTIC_MS[kind]))
