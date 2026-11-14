# w113-critic-play (independent critic and fixer, lens PLAY: function, feel, measured behaviour; scope: blasts, damage, enemy looks of wave 113)

GOAL: review the wave 113 work (BlastTable arsenal, damage everywhere, enemy look v3, weapon roster) by MEASURING it in the real scene: blasts at 0.5 / 1 / 1.5 x radius against the table,
chains, hero rules, enemy statuses and pooled reuse, civilians and animals, car damage, caps and draws at LOW, enemies at 15 / 40 / 80 m, hit feedback of the weapon classes, the wheel.
Write the 8 worst defects, fix them (most severe first), add regression tests (tests/test_play_critic_w113.gd), run the tests of every touched file, perf gate if rendering changed.

STATUS (2026-11-14 08:20 UTC): 7 defects fixed and covered by tests/test_play_critic_w113.gd (40 checks, about 35 s, mutation-checked: the pull, freed-body and credit checks fail without their fix). Docs and perf gate still to do.
Other critic (LOOK lens) works in the same tree: read each file again before editing.

MEASURED (probes tests/dev_w113_*.gd, bot tests/bot_w113_blast_perf.gd; delete the dev_* probes at the end or keep as look-dev)
- Table: ALL 81 entries (65 + 15 legacy + storm bolt) at 0.5 / 1.0 / 1.5 x radius equal BlastTable.damage_at (cover applied); only ARC COIL (gr_arc) differs on purpose (its shock chain adds 13.6 at 1.5 x R).
- apply() costs ~0.8 ms mean headless (3.5 ms first call): no CPU hitch.
- Chains: 8 barrels in 0.7 s (9 of 8 went off, one more prop nearby), 4 parked cars 4 of 4 in 3.4 s.
- Pooled enemy after a freeze + blast death comes back clean (not disabled, upright, scale ok, FoeFx state fresh).
- Draws at LOW (640x360, fixed 30 fps, 4 enemies dying, hero view): frag +13 (93 -> 106), rocket +11, mortar +14, C4 +12, airstrike L +9, orbital +7, fire line +7, gas tank +18 (106 -> 124), car blast +7, ult_mega +1; every blast adds 5 CPUParticles emitters,
  3 meshes (ExplosionPool), the cloud MultiMesh, the marks MultiMesh and the debris MultiMesh. The gate only measures 4 enemies dying, so 8 of 13 blasts go over the LOW death ceiling of 115 when the street is busy. NOT FIXED (see OPEN).
- Enemies (22 + 10 roster types, 15 / 40 / 80 m, open ground, 12 s): every type closes in or holds its keep range and fires; merc_medic never fires beyond 15 m (heals, parks at 28 m) by design.
- TTK: every weapon class takes 1.9 - 2.4 s against an operative at every range (shotgun at 15 m = sniper at 2 m): flat by design, noted.

DEFECTS FOUND (most severe first) and STATUS
1 FIXED  Explosives, fire, shock chains and burns gave NO hit feedback and NO kill credit: three enemies killed by a frag left the BOSS-LITE HUNT job at 0 of 8 (bullets +3), no crosshair X / kill ring / camera tick /
         damage number / hit tick, no achievement kill stat (7 of the 20 side jobs have kill stages: a player with launchers could not finish them). New scripts/combat/blast_credit.gd (BlastCredit.dealt / credited),
         hooks: BlastTable._targets + _legacy_targets (hero blasts, world blasters, quantum abilities, vehicle rockets), BlastOps burn / shock chain / fire field / stuck charge, Throwables spikes + EMP gear + plasma
         stuck host, Gadgets drone and turret. Frames: docs/shots/round6/play_critic_blast_feedback_before_after.jpg. Damage numbers per frame by tier (LOW 1, MED 2, HIGH 3: each is a Label3D draw).
2 FIXED  A grenade, rocket or strike kill on an unaware guard was paid and announced as a SILENT TAKEDOWN (+150, stealth takedown counter) and, inside a room, the other guards heard nothing (no alert, no heat):
         Drone.damage scores `_unaware_hit = not aware`. BlastTable._loud(en) sets the guard aware before any named weapon blast, burn tick, shock jump, stuck charge, spike and EMP gear damage; ad-hoc legacy
         blasts (the hero's own quantum abilities, the blink strike) stay as quiet as they were.
3 FIXED  The hero's own tank wrecked itself: an AP shell 4 m ahead cost 520 of 2000 hull points, HE 168. BlastTable._spared_vehicle (friendly:false entries never damage the vehicle named as source, nor the one
         the hero drives when he fired; legacy blasts spare the hero's car for non-friendly shots: vehicle weapons, flak, the hero's ultimates).
4 FIXED  Casualties option off: a grenade at a crowd's feet made nobody run ("they only run" per the option text): _civilians(hurt = false) + _scare_crowd, fire fields scare regardless.
5 FIXED  A well (WELL SEED, GRAVITY MINE, COLLAPSE FIELD, BLACK-HOLE) dragged people THROUGH walls (BlastOps._tick_pre moved them with no ray): somebody in a room 8 m away was pulled into the street.
6 FIXED  `Trying to cast a freed object` in BlastOps._step_toss / _step_air / _step_burn / _step_hold when a body is freed while a blast carries it (found by 90 blasts at HIGH: the entry stayed, the error came back
         every physics frame and the steps after it never ran: every other tossed car froze mid-air). Validity is checked before the cast now.
7 FIXED? tests: the table sweep (81 entries x enemy + 70 x car at 0.5 / 1 / 1.5 x R) is a regression test now (it found nothing wrong: the table is exact; ARC COIL's chain adds to it on purpose).
8 NOT FIXED (measured, decision for the integrator / wave 119): LOW draws during blasts. Frag among 4 enemies +13 (93 -> 106), rocket +11, mortar +14, C4 +12, airstrike L +9, orbital +7, fire line +7, gas tank +18 (106 -> 124),
         car blast +7; with the damage layers off (QT_DMG=0) +12 / +12, so they cost 0 - 3 of it. Each blast adds 5 CPUParticles emitters, 3 ExplosionPool meshes and the cloud / marks / debris MultiMeshes. On a clean
         street the peak stays under the death ceiling 115 (93 -> 108); on a busy one (a patrol car, drops: base 104 - 115) 8 of 13 blasts go over. Needs per-tier caps of the pooled emitters (FX.burst, ExplosionPool).
         Also measured: TTK is flat (1.9 - 2.4 s against an operative for EVERY weapon class at EVERY range: a shotgun at 15 m kills as slowly as a sniper at 2 m): balance, not changed. Pooled pools warm up in the first
         90 blasts (+640 nodes, then +5 per 45 blasts: no leak). EMP / BLIND / STUN hit humans too although the cards say machines. merc_medic never fires beyond 15 m (parks at 28 m).

DONE (files)
- NEW scripts/combat/blast_credit.gd, tests/test_play_critic_w113.gd, bots tests/bot_w113_feedback.gd + bot_w113_blast_perf.gd, sheet docs/shots/round6/play_critic_blast_feedback_before_after.jpg
- EDITED scripts/combat/blast_table.gd (credit, loud, spared vehicle, crowd scare), scripts/combat/blast_ops.gd (credit, loud, pull ray, freed bodies, fire scare), scripts/combat/throwables.gd, scripts/combat/gadgets.gd
- Probes (dev): tests/dev_w113_sweep.gd (table sweep + apply() cost + hero damage per difficulty), dev_w113_behaviour.gd (feedback, chains, pool reuse, crowd, tank), dev_w113_cars.gd, dev_w113_engage.gd (22 types x 3 distances),
  bot tests/bot_w113_blast_perf.gd (draws per blast: QUALITY=0 BOT_RES=640x360 ENGINE_ARGS="--fixed-fps 30" tools/bot.sh res://tests/bot_w113_blast_perf.gd /tmp/x 100000 1; BX_IDS, BX_CENSUS=1, BX_CENSUS_AT=7,14)

NEXT
1. More defects (8 total): measure the pull-through-wall, pooled car hood, LOW draw caps, civilians + animals at blast, wall / glass / fence / crate destruction, car damage stages by weapon class, hero in car.
2. tests/test_play_critic_w113.gd (real scene): credit (kills, job progress, marker), own tank spared, crowd flees with casualties off, full table sweep, plus tests of the later fixes.
3. Run touched tests: test_blast_table, test_blast_arsenal, test_damage_everywhere, test_throwables / gadgets tests, test_blasts_liquid_damage, test_side_missions, test_energy_destructive_weapons.
4. Perf gate once at the end if rendering changed (it has not so far), ARCHITECTURE.md + HANDOFF.md notes, remove or keep dev probes.

DECISIONS OTHER AGENTS DEPEND ON
- BlastCredit.dealt(enemy, amount, at := Vector3.INF, marker := true) must be called right after any damage the hero (or his world) deals to an ENEMY with a blast, fire or gadget; BlastCredit.credited(source, by_hero).
  Wave 115 snake bombs and wave 116 aircraft ordnance go through BlastTable.apply and get it for free; a new direct-damage path (snake grab, bite) should call it itself.
- Vehicle sparing: entries with friendly:false never damage the vehicle named as `source` (nor the hero's vehicle when the hero fired).

TESTS AND PERF
- probes only so far (see MEASURED). No rendering file touched yet: perf gate not needed for fixes 1-3.

OPEN PROBLEMS
- LOW draws during blasts (+7 .. +18 on a busy street) are above the death ceiling in 8 of 13 blasts; reducing needs per-tier caps of the pooled CPUParticles emitters (FX.burst) and ExplosionPool meshes, owned by the look critic's area.
