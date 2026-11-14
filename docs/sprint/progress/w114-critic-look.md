# w114-critic-look (independent critic and fixer, lens LOOK: weapons in hand and the weapon screens)

STATUS: FIXING (2026-11-14 18:50Z). The PLAY critic works in the same tree (it owns: sound, ammo, the kill-feed vs objective overlap in hud.gd, crate reveal in a fight).
GOAL: phone-resolution frames (LOW and MED) of weapons in hand, wheel, loadout, crate, cards, icons; the 8 worst defects; fix them in render-look-fix loops; tests; perf gate once.

EVIDENCE SO FAR (frames in the scratchpad, not committed): 30+ in-hand frames (hA, hB, hC, hD), 16 arsenal screens at 2400x1080 (ui1), 8 enemy frames (fo), 40 random icons.
DEFECT LIST (measured / seen):
 D1 weapons in hand do not read from the shoulder camera: pistol 35 px of 1280, carbine at the hip hidden behind the arm, SMG hidden, end-on when aimed. FIX: class-based drawn size
    (WeaponModels.look_scale by model length, hold-distance model _reach), hero-only carry spread of the relaxed weapon (CharacterRig.carry_spread). tests/test_weapon_view_w114.gd measures it.
 D2 muzzle flash = cream blob twice the size of the gun, covers the weapon (flux, pistol). FIX: star 0.85 -> 0.55 m, tighter halo, stronger rays (player_body.gd _build_flash, _paint_flash_textures).
 D3 hands: the support hand floats above the handguard with spread fingers in the aimed frames (baked grip curl). NOT FIXED yet (rig finger curl), see open problems.
 D4 enemy weapons are 15 px at 7 m (FoeArms SCALE fixed 1.3/1.3/1.1). FIX: use WeaponModels.look_scale by class (in progress).
 D5 weapon wheel: title box cuts the objective line, weapon plate shows behind the discs (text collisions). FIX: planned (touch_controls.gd / hud.gd, wheel open hides plate + objective).
 D6 parts card: label and number collide ("AIM SPREAD0.24 > 0.12") (arsenal_card.gd). planned.
 D7 loadout tab row: PARTS hidden for blast weapons leaves a hole between STATS and AMMO (arsenal_card.gd). planned.
 D8 scoped weapons: aimed view has no lens / reticle; the railgun tracer is a huge white wedge toward the lens. planned (reticle overlay).
 (kill feed vs objective line: reported by the PLAY critic too, theirs.)

DONE (files)
- scripts/player/weapon_models.gd: look_scale by length, _reach (hold distance), muzzle_shift / grip_offsets use it.
- scripts/characters/character_rig.gd: carry_spread (hero-only extra outward yaw at low ready / relaxed hip). scripts/player/player_body.gd: static carry_spread 0.45 (tune to 0.5), smaller flash.
- tests/bot_critic_hand_w114.gd (look-dev bot: many weapons x idle/aim/fireA/fireB/reload, HC_IDS=id@spread), tests/test_weapon_view_w114.gd (projected size of 24 weapons idle + aimed).

NEXT: carry_spread 0.5; FoeArms class scale; wheel overlaps; card label + tab gap; scope reticle; re-render in hand (LOW + MED), contact sheet docs/shots/round6/w114_critic_look_*.jpg;
 run test_weapon_view_w114, test_weapons_available_display, test_combat_feel, test_director_fixes_b, test_enemy_look_v3, test_weapon_ui_v3 (UI files), perf gate once at the end.

DECISIONS: WeaponModels.look_scale(id) is now per weapon (callers must not assume 1.3/1.3/1.1); muzzle_shift / grip_offsets keep the hand's hold distance when the weapon is drawn bigger.

TESTS AND PERF: test_weapon_view_w114 runs (51 s); the rest pending.

OPEN PROBLEMS: hands do not grip (D3), enemy readability beyond 15 m, scope reticle art.

UPDATE 19:35Z (for the PLAY critic, so nothing is done twice):
- DONE by LOOK: the sniper scope (new scripts/ui/scope_view.gd ScopeView + 3 hook lines in hud.gd: draw_mask before the top stack, scoped flag + draw_reticle in _draw_crosshair; tests/test_scope_view_w114.gd, 28 checks).
  Your defect 7 (no scope reticle) is fixed by this; do not add another one.
- DONE by LOOK: parts card label collision (arsenal_card.gd), tab gap (arsenal.gd), BLAST RADIUS touching its bar (BAR_LAB 132), wheel scrim 0.86 for the weapon wheel (touch_controls.gd one line).
- I take your defect 8 (m_shield thumb edge-on) and the in-hand look; I have NOT touched the kill feed, reveal or sound.
- Files I edit: weapon_models.gd (look_scale, _reach), character_rig.gd (carry_spread), player_body.gd (flash, carry_spread), roster/foe_arms.gd (scale_of), ui/scope_view.gd (new), ui/hud.gd (3 scope hooks),
  ui/arsenal.gd, ui/arsenal_card.gd, ui/touch_controls.gd (1 line), tests/bot_critic_hand_w114.gd, tests/test_weapon_view_w114.gd, tests/test_scope_view_w114.gd.
