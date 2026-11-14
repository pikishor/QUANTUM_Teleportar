# w113-critic-look (independent critic and fixer, lens LOOK) - started 2026-11-14 06:57Z

GOAL: review wave 113 (damage, blasts, enemy looks) by phone-size frames (LOW and MED, 1200x540 = 2400x1080 aspect), write the 8 worst
defects, fix them (render-look-fix), add regression tests, perf gate if rendering changed. Report under 200 words.

DONE (07:50Z)
- read ROUND6/RESUME/DESIGN/WORLD_EXPANSION/ROADMAP/STATE, builders' reports, ARCHITECTURE sections (blast, enemy look, damage).
- bot tests/bot_critic_blasts.gd (extends bot_blast_arsenal.gd, adds a registered entry crit_snake). Spot for ALL runs: BX_SPOT="-47.57867,-2.931496,1.5707963267949".
- baseline frames rendered and opened: 12 blasts x 3 distances x 3 moments at LOW and MED (scratchpad bl_low, bl_med), damage scenes (dm_low), HUD rings (hud_low).

CANDIDATE DEFECTS SEEN (evidence = frames in scratchpad bl_low, bl_med, dm_low, hud_low, fl_low; 08:00Z)
 1 STATUS LOOKS: burning humanoids = orange/black TIGER STRIPES (gas tank, fire line, wb_car frames), frozen = black/white zebra, shock = flat pale silhouette
   (hero_body.gdshader + foe_body.gdshader dmg_fx use UV / v_pos stripes). ALIENS (foe_creature.gdshader) have NO burn/freeze/shock look at all (FoeFx._shader only sets humanoid_body).
 2 SHATTERED WINDSCREEN = black/white cow print on every blasted car (car_glass.gdshader shatter state; visible 6-14 m in c4, mortar, gas tank, wb_car frames)
 3 FIRE LINE / flame tongues: flat yellow teardrops float in the air at random heights, no ground bed (BlastFx ember recipe)
 4 WALL SCORCH sticker: cream/tan starburst with dark centre on shop fronts after an airstrike (fx_marks.gdshader kind 2 ember ring too bright and flat)
 5 DEBRIS: thrown car panels are flat dark slabs (150 px at the lens), tyres smooth black balls (CarDebris; blast builder gap #3)
 6 IDENTITY: frag, mortar, rocket, mine, C4 look the same fireball (only size differs); the table has recipes (dust, dome, shock...) unused for them
 7 RING PREVIEW: orange ring on an orange sodium street is faint at 20-34 m (strike 13 m ring barely visible), label touches the equip card
 8 (to verify) dying operative = pale beige translucent mannequin for ~2 s (bot_damage enemy_op_*): maybe bot artefact, check with own bot
 9 HUMANS at 15 m read as black silhouettes, kit colours lost; at 40 m dots (markers/pips carry the read) - camera/fog, low priority
 Notes: marks/rings around flung enemies = EnemyMarks death shock ring (white), by design.

FIX LOG (critic edits; every file read again right before the edit)
- D1 STATUS LOOKS (08:50Z): NEW assets/shaders/dmg_status.gdshaderinc (burn = dark char with glowing seams that crawl up, freeze = faceted ice + cold rim + glints, shock = crawling arcs + cold flicker,
  dissolve = motes); used by hero_body.gdshader, foe_body.gdshader (their UV/v_pos stripe code removed) and foe_creature.gdshader (NEW uniform dmg_fx: aliens could not burn/freeze/shock before);
  scripts/damage/foe_fx.gd _shader() sets dmg_fx on the creature's own material (foe_creature.gdshader only). Frames: scratchpad st/base_* (before) vs st/v3_burn, v2_shock, v1_freeze (after).

NEXT
- render 16+ enemy types at 15/40/80 m (own bot), civilians and animals reacting, enemy hit/death sequences from the real camera
- fix in order of severity, re-render same frames, tests, perf gate (if rendering changed)

DECISIONS
- (none yet)

TESTS AND PERF
- (none yet)

OPEN PROBLEMS
- the PLAY critic works in the same tree; read each file again right before editing
