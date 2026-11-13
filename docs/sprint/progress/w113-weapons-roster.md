# w113-weapons-roster (builder: weapon roster data, mechanics, progression)

GOAL: at least 100 NEW guns, melee and energy weapons (original names), 200+ total with the blast-arsenal builder; distinct mechanics per weapon,
attachments and ammo types with real stat changes, spread over the world (crates, shops, rewards, drops, caches, ladder, HERO MODE flag),
wheel and loadout that cope with 200+ entries, a sound set per class (>= 3 layers), tests/test_weapons_v3.gd + tests/test_weapon_balance_v3.gd.

STATUS (22:50 UTC 2026-11-13): started. Reading code (weapon_defs.gd, player_weapon.gd, attachments, ladder, wheel, loadout, audio).

DONE
- (nothing yet)

NEXT
1. Count existing weapons per class (exact numbers go in the final reply).
2. scripts/player/weapon_defs_v3.gd (data: DEFS_V3, ALTS_V3, class lists) + one merge hook in weapon_defs.gd.
3. New mechanics in my own file (status effects, ammo types, perks, alt-fires), hooked into PlayerWeapon with small lines.
4. Progression (ladder, crates, shops by tier, drops, caches, HERO MODE flag), wheel + loadout for 200+, sounds, tests, renders, perf gate.

DECISIONS (other agents depend on these)
- New file for my data: scripts/player/weapon_defs_v3.gd (class_name WeaponDefsV3). WeaponDefs.all_ids() and per-class lists come from WeaponDefs.

TESTS AND PERF: none yet.
OPEN PROBLEMS: none yet.
