# w114-weapons-ui (builder: WEAPON PICTURES, SCREENS AND SOUND)

GOAL: (1) icon renderer: every weapon of WeaponDefs.all_ids() (229+) rendered 3/4 with rim light + class backdrop at 512 px, per-class atlases, used everywhere a weapon is shown;
(2) weapon screens (card with big picture, stat bars, range and blast rings beside a person, compare, filters, favourites, attachments with live stats, loadout 3+ slots, shop, crate reveal) at 844x390 and 1280x720;
(3) audio: per-class layered weapon sound sets (4+ per major class), reload/equip, explosions by blast size, ricochet and impact by material, hit/kill markers, mix without clipping.
Tests: tests/test_weapon_ui_v3.gd (extend), tests/test_weapon_audio_v3.gd (new). Perf gate at most twice.

STATUS (2026-11-14 15:10Z): restart notice read; earlier agent with this label did NOTHING (hit the usage limit at once). The weapons-art builder (w114-weapons-art) left 229 glb in
assets/models/weapons (uncommitted, in the shared tree): WeaponModels.build/mesh/material_for are the entry points.

DONE
- (nothing yet) survey of weapon UI code in progress.

NEXT
1. survey: weapon_icons.gd, weapon_preview.gd, weapons_screen.gd, loadout_screen.gd, weapon_wheel.gd, shop_screen.gd, tools/icons, audio tools (make_weapons_v3.py), Audio autoload mapping.
2. icon renderer + atlases, 3. screens, 4. audio, 5. tests, 6. render-look-fix loops, 7. perf gate, docs.

DECISIONS OTHER AGENTS DEPEND ON
- (none yet)

TESTS AND PERF: none yet.
OPEN PROBLEMS: none yet.
