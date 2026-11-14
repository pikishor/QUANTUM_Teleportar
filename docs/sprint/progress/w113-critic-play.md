# w113-critic-play (independent critic and fixer, lens PLAY: function, feel, measured behaviour; scope: blasts, damage, enemy looks of wave 113)

GOAL: review the wave 113 work (BlastTable arsenal, damage everywhere, enemy look v3, weapon roster) by MEASURING it in the real scene with the real touch layout
(844x390): 12 blasts at 3 distances, damage at 0.5 / 1 / 1.5 x radius against the table, chain reactions, ring previews on the phone HUD, enemy hit / death sequences,
civilians and animals, car damage stages, wall / glass / fence / crate destruction, caps at LOW, 16 enemy types at 15 / 40 / 80 m, weapons of five classes with hit feedback,
weapon wheel with 200+ entries. Write the 8 worst defects, fix them (most severe first), add or extend regression tests, run the tests of every touched file, perf gate if rendering changed.

STATUS (2026-11-14 06:56 UTC): started. Read ROUND6, RESUME, DESIGN, WORLD_EXPANSION, the four wave 113 builder logs and the ARCHITECTURE sections. Nothing edited yet.
Other critic (LOOK lens) works in the same tree: read each file again right before editing; never revert others.

DONE
- (nothing yet)

NEXT
1. Baseline measurements (test run of test_blast_table / test_blast_arsenal / test_damage_everywhere to see the state), look at the wave 113 sheets.
2. Probe bots for the focus list (blast at 3 distances, falloff measurement, enemy statuses, civilians, car stages, destruction, caps at LOW).
3. Defect list (8), fixes, regression tests, perf gate at the end.

DECISIONS OTHER AGENTS DEPEND ON
- (none yet)

TESTS AND PERF
- (none yet)

OPEN PROBLEMS
- (none yet)
