# w113-weapons-blast (builder: BLAST-RADIUS ARSENAL; BlastTable, BlastFx, BlastPreview, weapon_defs_blast.gd)

GOAL: 60+ explosive and area weapons and gadgets, each with a real, visible and measurable blast radius, all through one BlastTable
that Game.explode consults; radius ring previews; blast visuals with strict per-tier budgets; tests/test_blast_arsenal.gd in the real scene.

STATUS (2026-11-14, restart): the earlier agent with this label died at the usage limit before doing anything (no files). Starting from scratch.
Parallel builder w113-weapons-roster has the PACKS hook in WeaponDefs (my pack goes into WeaponDefs.PACKS) and owns weapon_defs_v3.gd.

FILES I OWN: scripts/combat/blast_table.gd, blast_fx.gd, blast_preview.gd, scripts/player/weapon_defs_blast.gd, tests/test_blast_arsenal.gd
(plus small hooks in autoload/game.gd explode, throwables.gd, gadgets.gd, charges.gd, energy_arms.gd, player_weapon.gd).

DONE
- (nothing yet)

NEXT
1. Survey: Game.explode callers (29), FX.blast, ExplosionPool, BlastElements, BlastMarks, Charges, Throwables, Gadgets, EnergyArms, WeaponDefs.PACKS.
2. BlastTable (data + API), migrate old numbers, hook Game.explode.
3. Content: grenades 12, launchers 14, mines/charges 10, strikes 10, vehicle/aircraft ordnance 8, ultimates 6, world blasters 4.
4. Previews, HUD radius, weapon-card ring, FX budgets, tests, renders (12 types x 3 distances, LOW + MED, 6+ iterations), perf gate.

DECISIONS OTHER AGENTS DEPEND ON
- (to be filled: BlastTable entry format, register API)

TESTS AND PERF: nothing run yet.
OPEN PROBLEMS: none yet.
