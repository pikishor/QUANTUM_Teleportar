# w113-weapons-roster (builder: weapon roster data, mechanics, progression)

GOAL: at least 100 NEW guns, melee and energy weapons (original names), 200+ total with the blast-arsenal builder; distinct mechanics per weapon,
attachments and ammo types with real stat changes, spread over the world (crates, shops, rewards, drops, caches, ladder, HERO MODE flag),
wheel and loadout that cope with 200+ entries, a sound set per class (>= 3 layers), tests/test_weapons_v3.gd + tests/test_weapon_balance_v3.gd.

STATUS (23:55 UTC 2026-11-13): PACKS hook is in the tree (compiles, tests/test_weapons.gd passes). Next: the data file, then mechanics.

EXISTING COUNTS (WeaponDefs.IDS, 58 before this wave): pistol 7, smg 3, rifle 6, shotgun 4, sniper 6, heavy 6, melee 6, quantum 6, energy 7, blast 7.
Gear on top: 8 throwables, 1 charge (C4), 6 gadgets, hero melee combo (Gear.MELEE). Total with gear 73.

DECISIONS OTHER AGENTS DEPEND ON (the blast-arsenal builder: read this first)
- WeaponDefs.PACKS (scripts/player/weapon_defs.gd, top of file): an Array[Script] of roster packs. A pack is a script with `static func tables() -> Dictionary`;
  keys (all optional): defs, ids, class_of, family_of, alts, hit_snd, tilt, proj, price, ammo_pack, acc, stagger, vfx_class, anim_class, spec, shop, ladder, crates.
  APPEND YOUR OWN PACK SCRIPT TO PACKS (do not edit DEFS0/IDS0 etc.). A pack must NOT read WeaponDefs while it builds its tables (they are built from it).
- The old tables are renamed DEFS0 IDS0 CLASS_OF0 ALTS0 HIT_SND0 TILT0 PROJ0 (const, never extend them); the public names DEFS IDS CLASS_OF ALTS HIT_SND TILT PROJ are static vars (merged).
  Same pattern, same hook (one `static var X = X0.merged(WeaponDefs.pack_dict("key"))` line) in: Economy.WEAPON_PRICE, PlayerWeapon.AMMO_PACK, BalanceModel.ACC, AimAssist.STAGGER,
  QuantumVfx.WEAPON_CLASS, HeroAnimTuning.WEAPON_CLASS, WeaponModels.SPEC, ShopScreen.SHOP_WEAPONS (Array), WeaponLadder.LADDER + CRATES (pack ladder rows may say "crate": key).
- WeaponDefs.all_ids(), in_class(cls) (cached), ids_in_class(cls), family_of(id), in_family(fam), hero_mode (static bool; is_unlocked() is true for every weapon while it is on).
- Crates may carry "pos": Vector3 (WeaponLadder.crate_pos).
- My data file: scripts/player/weapon_defs_v3.gd (class_name WeaponDefsV3).

DONE
- weapon_defs.gd packs hook + hero_mode + all_ids/in_family; hooks in economy.gd, player_weapon.gd (AMMO_PACK), balance_model.gd, aim_assist.gd, quantum_vfx.gd, hero_anim_tuning.gd,
  weapon_models.gd, shop_screen.gd, weapon_ladder.gd; stub scripts/player/weapon_defs_v3.gd.

NEXT
1. weapon_defs_v3.gd: class templates + 100+ rows (families: pistol 10, smg 10, assault 14, battle 6, carbine 6, dmr 6, sniper 8, shotgun 10, lmg 6, rotary 4, bow 5, flamer 4, melee 24, energy 14, quantum 8, exotic 6).
2. weapon_mech.gd (status effects, ammo types, perks, alts) + small hooks in PlayerWeapon; attachments slots grip/magazine/laser.
3. ladder, crates, shops by tier, drops, caches; wheel and loadout paging, favourites, recents; sounds; models; icons; tests; renders; perf gate.

TESTS AND PERF: test_weapons.gd passes with the hooks. Nothing else run yet.
OPEN PROBLEMS: existing tests that assume the old size (test_weapon_cards "3 to 7 per class", test_balance2 ACC.size()==IDS.size(), economy tree hours) will need honest updates.

UPDATE 00:45 UTC (11-14)
- DONE: godot/scripts/player/weapon_rows_v3.gd (125 rows), weapon_defs_v3.gd (builder: damage worked out from `power`, recoil patterns, ladder + crates), weapon_mech.gd (statuses, openers, ramp,
  pierce, ricochet, cone, alt kinds ub_nade zoom brace mode surge spin shove throw_melee) + 20 one-line hooks in player_weapon.gd (grep "mech."). Everything compiles; test_weapons,
  test_weapons_available_display and test_balance2 pass with the 125 new defs (models, sounds, icons are not there yet).
- Counts now: WeaponDefs.IDS 183 = 58 old + 125 new. Families: pistol 15 smg 12 assault 14 battle 7 carbine 7 dmr 8 sniper 11 shotgun 12 lmg 7 rotary 5 bow 6 flamer 5 melee 28 energy 17
  quantum 12 exotic 6 (launcher 11 = the old blast-family ids, owned by the blast builder). Wheel classes: pistol 15 smg 12 rifle 30 shotgun 12 sniper 24 heavy 20 melee 28 quantum 12 energy 23 blast 7.
- New def keys other agents may see: family tier role mlen model_seed ammo_types opener final ramp ramp_max knock slow slow_k mark mark_time zap zap_time zap_chain chill chill_max freeze_time
  dissolve dissolve_time ricochet ricochet_k pierce_n pierce_k sunder p_heal p_refund p_hot steady crit_blast crit_blast_dmg pull cone cone_range mist zoom_alt scope layer.
- WeaponDefs.AMMO_TYPES is merged too (pack key "ammo_types"): 7 types (STANDARD HEAVY PIERCING INCENDIARY SHOCK EXPLOSIVE TIPPED QUANTUM).
- Economy decision: the tree-hours test (13.9 h now, band 14.3) cannot take 125 more priced weapons, so Economy.gear_items() will count only the core weapon prices (WEAPON_PRICE0).
NEXT: models (weapon_models_v3.gd), sounds (tools/audio/make_weapons_v3.py), icons, enemy_drop + crates hook, UI paging, attachments slots, tests.
