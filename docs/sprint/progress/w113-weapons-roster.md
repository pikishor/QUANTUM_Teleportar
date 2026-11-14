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

UPDATE 02:20 UTC (second agent): DONE since the restart
- Catalogue (WeaponsScreen): dynamic pages (WeaponBrowser classes + EXPLOSIVES + GADGETS, 3 x 3 tiles, balanced pages), class row (wcls_prev/next) + page row (wpg_*), OWNED n / m counter, role text wrapped in the
  right column, tile names keep the first words (PILLAR ASSAULT, not ASSAULT RIFLE). PAGES / PAGE_TITLES are lazy static getters (a static initialiser ran before WeaponDefs existed: keep it lazy).
- Loadout: WeaponBrowser tabs (FAVOURITES, RECENT, classes), pages of 8 (balanced via WeaponBrowser.split), caption(id) unique per class (<= 11 chars), star, headline line (first role clause), SLOT TABS (OPTIC MUZZLE GRIP
  MAGAZINE LASER, only slots the weapon can wear) + part cards + FITTED line. Attachments: 5 slots, 21 parts (scripts/player/attachment_parts_v3.gd: 12 new, fits rules, set/add mods, FX lines), Economy.attachment_price hook.
- Wheel: two levels (WeaponWheel.items: classes + RECENT + FAV, ring_items(tab, page, cur): 8 weapons + NEXT disc, activate(item, weapon)), RadialWheel.disc_scale (12 discs fit), touch_controls hooks (_wheel_pick returns true when a ring opens).
- Shops and drops (scripts/player/weapon_shops_v3.gd): hero_tier, dealer_stock (ARMS DEALER restocks with a weapon of the tier when one is owned), drop_for + WeaponLadder.enemy_drop band (DROP_CHANCE .. +0.07).
- Fixed bugs found by the new test: PlayerWeapon._tick_heat crashed for a spin-up weapon without heat keys (heat_cool); x_grav had knock 0.
- Renamed: PLASMA RIFLE -> SOLAR PLASMA GUN (blocklist), SLEDGEHAMMER -> SLEDGE HAMMER (caption).
- Tests: NEW tests/test_weapons_v3.gd (135 checks, 11 s, real player scene: every one of the 125 weapons equips, fires, reloads, alt-fires and damages a dummy; 49 status keys land; wheel, attachments, shops, save),
  NEW tests/test_weapon_balance_v3.gd (TTK table by class, family and range, outlier 3x, EASY/HARD fairness; prints TTK lines). Updated honestly: test_weapon_roster, test_weapon_cards (via new pages), test_weapons_depth,
  test_energy_destructive_weapons, test_director_round3_b. Look-dev bot: tests/bot_weapon_ui.gd (WUI_OUT, WUI_STEPS, MENU_NO3D=1).
- Counts (families, old + new): pistol 15 smg 12 assault 14 battle 7 carbine 7 dmr 8 sniper 11 shotgun 12 lmg 7 rotary 5 bow 6 flamer 5 melee 28 energy 17 quantum 12 exotic 6; wheel classes pistol 15 smg 12 rifle 30 shotgun 12
  sniper 24 heavy 20 melee 28 quantum 12 energy 23 (blast: the other builder, 53 so far). New weapons 125, total with blast 229+.
NEXT: tests/test_weapon_ui_v3.gd (main scene: loadout, catalogue, wheel through the HUD), ES / HI strings (strings_weapons_v3.gd), melee icons (thin lines), re-run touched tests (ui_kit_screens, localisation, hud, touch),
  perf gate (twice at most), contact sheet docs/shots/round6/, ARCHITECTURE.md + HANDOFF.md, final report.

UPDATE 04:10 UTC: DONE also
- tests/test_weapon_ui_v3.gd (main scene, 93 checks, 25 s: loadout flow, catalogue flow incl. BUY of a roster weapon, wheel through real touch events, 30 layout scans at 844x390 / 1200x540 / 1280x720).
- Batch of 38 touched tests run: all PASS except the known flaky test_interior_gameplay node count (+38..+50 against 12; passes on some runs, see HANDOFF wave 112).
- Honest test updates: test_weapons_available_display (class wedges only), test_director_round2_d (slot tabs: nine first parts reachable), test_hud (AMMO is in the outer MORE column), test_interior_gameplay_vendors (dealer back room opens at tier 2).
- AMMO touch button behind MORE (ammo types had a key only), toast of the loaded type; secret cache lines name their place (CACHE AT MOUNTAIN OBSERVATORY).
- Icons re-rendered (long thin weapons thicker, spear and staff on a diagonal). Gear card text wraps (the C4 chain line ran off the card: blast builder text).
- Sheets: docs/shots/round6/weapons_ui_before_after.jpg, weapon_wheel_rings.jpg, weapons_v3_in_hand.jpg.
NEXT: perf gate (LOW / MED / HIGH, once), HANDOFF.md entry, final report. Open: models are placeholders (wave 114), role texts English in es / hi.
