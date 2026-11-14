# w114-weapons-ui (builder: WEAPON PICTURES, SCREENS AND SOUND)

GOAL: (1) icon renderer: every weapon of WeaponDefs.all_ids() (229) rendered 3/4 with rim light, class tint, 512 px, per-class atlas pages, used everywhere a weapon is shown;
(2) weapon screens (card with big picture, 7 stat bars, range + blast rings beside a person, compare, filters/sort/favourites, attachments with 3D preview + live stats, ammo types, crafting entry,
loadout with 4 slots + quick swap, shop + crate reveal) at 844x390 and 1280x720 in the UI kit; (3) audio: layered class sets (4+ per major class), reload/equip, blast sizes, ricochet/impact, markers.
Tests: tests/test_weapon_ui_v3.gd (rewritten), tests/test_weapon_audio_v3.gd (new), tests/test_weapon_pics.gd (new). Perf gate at most twice.

STATUS (2026-11-14 ~18:15Z): FINISHED. Code, assets, tests, docs, perf gate and 8 contact sheets (docs/shots/round6/weapons_ui_*.jpg, incl. the audio waveforms) are in; the last regression batch (49 tests) is green.

DONE
- Pictures: tools/icons/weapon_pics.{gd,tscn,sh} + weapon_atlas.py; assets/icons/wp/ (37 WebP pages, 229 weapons, ETC2 26.7 MB raw / 7.5 MB deflated, ~6 MB repo); scripts/ui/weapon_pics.gd
  (thumb/card AtlasTextures; thumb pages stay loaded ~7 MB, card pages LRU of 5; draw_backdrop/draw_fit; stale_ids). ItemIcons -> WeaponPics. Used in loadout, wheel, HUD plates, kill feed + pickup lines,
  crate billboards (grow with distance), reveal, lists.
- Screens: scripts/ui/arsenal.gd (virtualised grid, 9 tiles of 229, drag / flick / wheel / pad scroll, filters, class row, sort, 4 slots, star, GEAR), arsenal_card.gd (plate 650x240, 7 bars + compare,
  STATS / PARTS / AMMO, 3D VIEW), weapon_rings.gd (to scale beside a person), crate_reveal.gd (CRATE OPENED / PURCHASED / MISSION REWARD), loadout_slots.gd (SWAP walks the slots).
- Audio: tools/audio/make_weapons_v4.py -> 148 OGG (1.3 MB); scripts/audio/weapon_audio.gd (83 sets, all in use, 5+ per major class; layered fire, Tail bus reverb indoors, explosions by size, impact /
  ricochet by material wired in ImpactSparks, markers, haptics). Master limiter holds, worst layer stack -4.5 dBFS.
- Tests green: test_weapon_pics (29), test_weapon_audio_v3 (104), test_weapon_ui_v3 (272, ~90 s) and the old tests updated to the new flows (list in HANDOFF); regression batches of 60 + 49 tests clean
  except the fixed ones (last one: the pad test expected the list to scroll back on UP, it only scrolls as far as the focus needs; it now checks the focus is the same tile, on screen, and walks to the top). es / hi strings in strings_weapons_v4.gd.
- Render loops (docs/shots/round6/weapons_ui_iterations.md): 9 loops. Real bugs found by looking: reveal overlay size 0, weapon pop plate hid its picture, wheel + kill feed white boxes (atlas page
  thrash, 100 loads), hero tabs registered twice, crate picture a speck.
- Measured here (software, headless): list redraw ~4-8 ms mean / 16 ms worst over 229 weapons, layout 0.26 ms, 9 tiles exist of 229.

PERF GATE (PERF_CHECK=1 tools/perf_report.sh 0 1 2, run 1 of at most 2, all OK): LOW draws 70 total 92 death spike 107 tex 112 MB; MED 97 / 129 death 149 tex 143 MB; HIGH 113 / 149 death 170 tex 209 MB.

DECISIONS OTHER AGENTS DEPEND ON
- WeaponPics.thumb(id) / card(id) are Texture2D (AtlasTexture, full-frame 256x128 / 512x256, margin restores the crop). Do not cache them in statics (pages are an LRU / resident set).
- After a model change: tools/icons/weapon_pics.sh (renders only stale ids, repacks, then tools/import.sh); tests/test_weapon_pics.gd fails when a glb changed and its picture was not rebuilt.
- SWAP / cycle() walk LoadoutSlots (4 slots), not all owned weapons. Tile taps of the Arsenal SELECT (quick mode, opened by the wheel gesture: one tap takes the weapon and resumes); EQUIP is the action
  button (ars_equip in LOADOUT, wequip_<id> in the catalogue); a part card previews, FIT / TAKE OFF / BUY (ars_apply) applies.
- A weapon picture on a HUD plate goes through Hud._weapon_pic / Hud._tex (the plate fill is queued, an immediate draw would be covered).
- WeaponAudio.set_of(id) / sets_of_class(cls); a def may name `sset`; WeaponAudio.ASSIGN picks sets for wave 113 weapons that share a family body (older weapons keep the recording their def names).
  Never call WeaponAudio.reload(), use reload_sound().

OUT OF MY SCOPE (reported)
- test_director_fixes_b: "the weapon in hand is drawn thicker ((1.3, 1.3, 1.1))" fails against the art builder's KIT_LOOK_SCALE; not touched.
- Art models are blocky in places (weapons-art builder). test_audio prints an old script error for `boom` (OGG cast to WAV).
