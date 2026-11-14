# w113-critic-look (independent critic and fixer, lens LOOK) - started 2026-11-14 06:57Z

GOAL: review wave 113 (damage, blasts, enemy looks) by phone-size frames (LOW and MED, 2400x1080 aspect), write the 8 worst
defects, fix them (render-look-fix), add regression tests, perf gate if rendering changed. Report under 200 words.

DONE
- (nothing yet) read ROUND6/RESUME/DESIGN/WORLD_EXPANSION/ROADMAP/STATE.

NEXT
- read reports_w113.md and w113-* progress notes, ARCHITECTURE sections for BlastTable/damage/enemy look
- render baseline frames: 12 blasts x 3 distances, ring previews, enemy hit/death, car damage stages, destruction, 16 enemies at 15/40/80 m
- write the 8 worst defects, fix in loops

DECISIONS
- (none yet)

TESTS AND PERF
- (none yet)

OPEN PROBLEMS
- the enemy-look builder is still running in the same tree (w113-enemy-look); read files again before editing
