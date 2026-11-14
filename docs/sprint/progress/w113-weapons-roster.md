# w113-weapons-roster (builder: weapon roster data, mechanics, progression)

GOAL: at least 100 NEW guns, melee and energy weapons (original names), 200+ total with the blast-arsenal builder; distinct mechanics per weapon,
attachments and ammo types with real stat changes, spread over the world (crates, shops, rewards, drops, caches, ladder, HERO MODE flag),
wheel and loadout that cope with 200+ entries, a sound set per class (>= 3 layers), tests/test_weapons_v3.gd + tests/test_weapon_balance_v3.gd.

STATUS (restart at 00:31 UTC 2026-11-14, second agent): tree compiles, tests/test_weapons.gd passes with 183 weapon ids. The first agent had finished data, mechanics, models, icons, sounds and the
first half of the browser UI (log below was behind: read DONE).

EXISTING COUNTS (WeaponDefs.IDS, 58 before this wave): pistol 7, smg 3, rifle 6, shotgun 4, sniper 6, heavy 6, melee 6, quantum 6, energy 7, blast 7.
Gear on top: 8 throwables, 1 charge (C4), 6 gadgets, hero melee combo (Gear.MELEE). Total with gear 73.
NOW: IDS 183 = 58 old + 125 new. Families: pistol 15 smg 12 assault 14 battle 7 carbine 7 dmr 8 sniper 11 shotgun 12 lmg 7 rotary 5 bow 6 flamer 5 melee 28 energy 17 quantum 12 exotic 6 launcher 11 (old blast ids).

DECISIONS OTHER AGENTS DEPEND ON (the blast-arsenal builder: read this first)
- WeaponDefs.PACKS (scripts/player/weapon_defs.gd, top of file): Array[Script] of roster packs. A pack is a script with `static func tables() -> Dictionary`; keys (all optional): defs, ids,
  class_of, family_of, alts, hit_snd, tilt, proj, price, ammo_pack, acc, stagger, vfx_class, anim_class, spec, shop, ladder, crates, ammo_types. APPEND YOUR PACK SCRIPT TO PACKS
  (never edit DEFS0/IDS0). A pack must NOT read WeaponDefs while it builds its tables.
- Old tables are DEFS0 IDS0 CLASS_OF0 ALTS0 HIT_SND0 TILT0 PROJ0 (const); public DEFS IDS CLASS_OF ALTS HIT_SND TILT PROJ are static vars (merged). Same hook line in Economy.WEAPON_PRICE,
  PlayerWeapon.AMMO_PACK, BalanceModel.ACC, AimAssist.STAGGER, QuantumVfx.WEAPON_CLASS, HeroAnimTuning.WEAPON_CLASS, WeaponModels.SPEC, ShopScreen.SHOP_WEAPONS, WeaponLadder.LADDER + CRATES.
- WeaponDefs.all_ids(), in_class(cls), ids_in_class(cls), family_of(id), in_family(fam), hero_mode (static bool; is_unlocked() true for every weapon while on), AMMO_TYPES merged (7 types).
- Crates may carry "pos": Vector3 or "site" + "off" (outskirts cache); WeaponLadder.crate_known(i) hides secret caches until the site is known.
- Def keys (mechanics, read by scripts/player/weapon_mech.gd): family tier role mlen model_seed ammo_types opener final ramp ramp_max knock slow slow_k mark mark_time zap zap_time zap_chain chill
  chill_max freeze_time dissolve dissolve_time ricochet ricochet_k pierce_n pierce_k sunder p_heal p_refund p_hot steady crit_blast crit_blast_dmg pull cone cone_range mist zoom_alt scope layer.
- Economy: gear_items() counts only WEAPON_PRICE0 (tree-hours test). Blast builder files: blast_table.gd, weapon_defs_blast.gd (its pack), blast_fx.gd; it makes small hooks in player_weapon.gd too.

DONE (files)
- scripts/player/weapon_rows_v3.gd (125 rows), weapon_defs_v3.gd (class templates, damage from power, patterns, ladder, crates, caches), weapon_mech.gd (statuses, openers, ramp, pierce, ricochet,
  cone, 9 alt kinds) + one-line hooks in player_weapon.gd (grep "mech."), weapon_models_v3.gd (125 meshes), icons (assets/icons/w_*.png + wl_*.png, 250 files), tools/audio/make_weapons_v3.py
  + 84 ogg (shot_v3_<class>[_1..3]), weapon_browser.gd (favourites, recent, class tabs, pages of 8, save), loadout_screen.gd paging + star + class chips, hud.gd routes (wheelcls_*, fav_toggle),
  progress.gd save/load of favourites + recent, weapon_crates.gd secret caches.

NEXT (second agent)
1. Compile + run weapon tests (done: test_weapons PASS). Run test_weapon_roster, test_weapon_cards, test_balance2, test_audio_real_samples, test_weapons_available_display, test_menu_cut.
2. Attachment slots grip / magazine / laser with real stat changes (Attachments), tests; ammo types UI.
3. tests/test_weapons_v3.gd (real scene) + tests/test_weapon_balance_v3.gd (TTK table).
4. Wheel paging + loadout renders at phone resolution with 200+ entries (6+ loops), contact sheet docs/shots/round6/.
5. Shops by tier paging, mission reward weapon grants, enemy drops check, HERO MODE test; docs (ARCHITECTURE, HANDOFF); perf gate (max twice).

TESTS AND PERF: test_weapons PASS (26 s). Nothing else run yet by the second agent. Perf gate not run.
OPEN PROBLEMS: existing tests that assume the old size (test_weapon_cards "3 to 7 per class", test_balance2 ACC.size()==IDS.size(), economy tree hours) may need honest updates.
