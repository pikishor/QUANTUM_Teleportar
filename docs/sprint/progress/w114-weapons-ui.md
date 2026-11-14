# w114-weapons-ui (builder: WEAPON PICTURES, SCREENS AND SOUND)

GOAL: (1) icon renderer: every weapon of WeaponDefs.all_ids() (229) rendered 3/4 with rim light, class tint, 512 px, per-class atlas pages, used everywhere a weapon is shown;
(2) weapon screens (card with big picture, 7 stat bars, range + blast rings beside a person, compare, filters/sort/favourites, attachments with 3D preview + live stats, ammo types, crafting entry,
loadout with 4 slots + quick swap, shop + crate reveal) at 844x390 and 1280x720 in the UI kit; (3) audio: layered class sets (4+ per major class), reload/equip, blast sizes, ricochet/impact, markers.
Tests: tests/test_weapon_ui_v3.gd (rewritten), tests/test_weapon_audio_v3.gd (new), tests/test_weapon_pics.gd (new). Perf gate at most twice.

STATUS (2026-11-14 ~17:00Z): code, assets and tests are in; running the regression batch, then render loops (reveal, wheel, HUD, kill feed, shop), perf gate, docs, contact sheets.

DONE
- Pictures: tools/icons/weapon_pics.{gd,tscn,sh} + weapon_atlas.py; assets/icons/wp/ (37 WebP pages, manifest 30 KB, ETC2 26.7 MB raw / 7.5 MB deflated, ~6 MB repo); scripts/ui/weapon_pics.gd (thumb/card
  AtlasTextures, page LRU of 7, draw_backdrop/draw_fit, stale_ids); ItemIcons -> WeaponPics (old PNGs = fallback). Used in loadout, wheel discs, kill feed, crate billboards, reveal, shop.
- Screens: scripts/ui/arsenal.gd (virtualised grid, filters, class row, sort, 4 slots, star), arsenal_card.gd (picture plate 650x240, 7 bars + compare, tabs STATS / PARTS / AMMO, 3D VIEW), weapon_rings.gd
  (to scale beside a person), crate_reveal.gd (CRATE OPENED / PURCHASED / MISSION REWARD; none for a pickup in a fight; quiet under tests unless forced), loadout_slots.gd (SWAP walks the slots).
  Hooks: hud.gd (press/tap/drag/tick/layout key/_tex queue), PlayerWeapon.grant, WeaponCrates.open, Progress.buy_weapon/grant_weapon, WeaponBrowser seen/slots save, HudFeed kill icon.
- Audio: tools/audio/make_weapons_v4.py -> 148 OGG (1.3 MB); scripts/audio/weapon_audio.gd (83 sets, 5-12 used sets per major class, ASSIGN table for the wave 113 families, layered fire: mechanism +
  body + tail on the Tail bus whose reverb opens indoors), explosions by size (small 0.9 s .. huge 3.0 s), impact/ricochet by material (wood/dirt/foliage/water/armor/shield wired in ImpactSparks,
  vegetation trunks = wood/leaves), hit/kill markers, haptics. Master limiter holds; worst layer stack -4.5 dBFS.
- Tests green: test_weapon_pics (28), test_weapon_audio_v3 (104), test_weapon_ui_v3 (263, ~90 s), plus updated test_weapon_cards, test_weapons_depth, test_menu_cut, test_director_round2_d,
  test_ui_kit_screens, test_rewards_progression, test_weapons, test_audio_budget2, test_audio_real_samples (honest updates to the new flows: scroll list not pages, tile tap selects, FIT/BUY button).
- Measured here (software, headless): list redraw ~3.7 ms mean / 22 ms worst over 229 weapons, layout 0.26 ms, 9 tiles exist of 229.

NEXT
1. Batch 2 regression log (scratchpad batch2.log); fix real failures only.
2. Render loops: reveal, wheel, HUD plate, kill feed, crate pictures, shop at 844x390 and 1280x720 (6+ loops), contact sheets docs/shots/round6/weapons_ui_*.jpg (<= 12, q80).
3. Perf gate (PERF_CHECK=1 tools/perf_report.sh 0 1 2, at most twice), ARCHITECTURE.md + HANDOFF.md, final report.

DECISIONS OTHER AGENTS DEPEND ON
- WeaponPics.thumb(id) / card(id) are Texture2D (AtlasTexture, full-frame 256x128 / 512x256, margin restores the crop). Do not cache them in statics (pages are an LRU).
- After a model change: tools/icons/weapon_pics.sh (renders only stale ids, repacks, then tools/import.sh); tests/test_weapon_pics.gd fails when a glb changed and its picture was not rebuilt.
- SWAP / cycle() walk LoadoutSlots (4 slots), not all owned weapons. Tile taps of the Arsenal SELECT (quick mode, opened by the wheel gesture: one tap takes the weapon and resumes); EQUIP is the action
  button (ars_equip in LOADOUT, wequip_<id> in the catalogue); a part card previews, FIT / TAKE OFF / BUY (ars_apply) applies.
- WeaponAudio.set_of(id) / sets_of_class(cls); a def may name `sset`; WeaponAudio.ASSIGN picks sets for wave 113 weapons that share a family body (older weapons keep the recording their def names).
  Never call WeaponAudio.reload(), use reload_sound().

OUT OF MY SCOPE (reported)
- test_director_fixes_b: "the weapon in hand is drawn thicker ((1.3, 1.3, 1.1))" fails against the art builder's KIT_LOOK_SCALE; not touched.
- Art models are blocky in places (weapons-art builder).
