# w114-critic-play (independent critic and fixer, lens PLAY: function, feel, measured behaviour; scope: weapons in hand and the weapon screens of wave 114)

GOAL: review the wave 114 work (weapon kit in hand and in enemy hands, Arsenal / wheel / loadout / shop / crate reveal / card screens, weapon sound) by MEASURING it in the real scene at 844x390 and 1280x720,
write the 8 worst defects, fix them (most severe first), add regression tests, run the tests of every touched file and the perf gate if rendering changed.

STATUS (2026-11-14 19:30 UTC): FIXED 5, regression batch running. The LOOK critic works in the same tree (read a file again before editing it).

DEFECTS (measured with probes tests/dev_w114_*.gd and bots tests/bot_w114_*.gd; regression tests in tests/test_play_critic_w114.gd, sections sound / ammo / hud / touch / reveal / burst)
1 FIXED  63 weapons never used their wave 114 sound set: 56 of the throw kind (grenades, mines, strike beacons, launchers, pods) played the QUANTUM BLINK (blink + phase_step) or another weapon's recording, 7 charge
         weapons (lance, beam / rail rifles, a BOW) the ENTANGLE hum and the plasma overcharge zap. WeaponAudio.launch / charge_start / fire_charged + hooks in player_weapon.gd (_throw, _tick_charge, _fire_lance),
         combat/blast_ops.gd, player/energy_arms.gd (salvo, fan); ASSIGN rows rocket -> lau_rocket, grenade -> thr_frag; tests/test_audio_redesign.gd (half charge = shot_lance).
2 FIXED  PlayerWeapon._auto_swap (documented since wave 85, never called): a dry weapon with nothing in reserve clicked for ever. Wired in tick + _tick_charge, prefers the 4 loadout slots, falls back to the blade.
3 FIXED  Burst weapons (10: burst pistol, bullpup, tempo, double tap, triple tap, crest, rook, pulse rifle, superposition shotgun, qsuper) fired at HALF the rate and damage per second their card shows (the last round
         of a burst added a second interval; measured 240 rpm against 429 shown): player_weapon.gd tick (burst branch).
4 FIXED  HUD: the kill / pickup feed (4 lines) hung from y = 20 across the centred objective line and the toast (23 / 19 % at 844x390, 44 / 30 % at 1280x720): hud.gd hangs it under msg_top + MSG_H, hud_feed.gd MAX_W.
5 FIXED  Crate reveal in a fight: a 50 % dim over the whole screen, 14 rays and a 560 x 366 card over the middle of the view for 3.4 s while enemies shoot: CrateReveal.in_combat() -> a small card (62 %) at the left, no dim,
         no rays, 2.0 s (crate_reveal.gd). Quiet street: unchanged.
6 OPEN   alt-fire of every weapon ends with the ENTANGLE `link` blip (player_weapon.gd alt_fire last line): a quantum sound under a shotgun slug.
7 OPEN   sniper ADS (rail, bolt, amr, railgun, xbow, marksman, battle): the zoomed view (12 - 30 deg) shows no weapon and no scope reticle, the tracer starts off screen (aim probe: weapon rect 0 % on screen).
8 OPEN   (LOOK) the m_shield thumb is an edge-on sliver; barrel lags the aim line by 6 - 13 deg during bursts while looking 26 deg down (aim probe); 15 hitscan weapons need more than the 6 voices of the shot family
         at full auto (carbine 8.0, e_laser 22): the oldest shot is cut at about 0.6 s, inaudible.
MEASURED OK: equip 0.9 ms mean (2.5 ms worst, +24 MB static after all 229); every weapon obtainable (7 starters, 47 shop, 68 crates (27 secret), 93 drops, 12 mission, 2 boss); no NaN in any def; ammo packs fine;
         monkey 100 s with all weapons (no script error, no stuck reload); texture memory at LOW with the Arsenal fully used 92 -> 103.8 MB (+11.8, pages cap at 16); firing adds +6.5 draws on average and +16 at the
         peak at LOW (tracers, hero flash, sparks, no single culprit); real touch events on the Arsenal (tap, drag, flick, snap, equip, back, quick mode) all work at 844x390.

DONE (files)
- NEW tests/test_play_critic_w114.gd, probes tests/dev_w114_{sound,aim,equip,hud,data,monkey,rate}.gd, bots tests/bot_w114_{mem,fx,fx2,reveal,feed}.gd
- EDITED scripts/audio/weapon_audio.gd, scripts/player/{player_weapon,energy_arms}.gd, scripts/combat/blast_ops.gd, scripts/ui/{hud,hud_feed,crate_reveal}.gd, tests/test_audio_redesign.gd
- sheets docs/shots/round6/play_critic_w114_{feed,reveal}_before_after.jpg

NEXT
1. Read the regression batch (batch1), fix what my changes broke. 2. perf gate once (PERF_CHECK=1 tools/perf_report.sh 0 1 2). 3. docs: ARCHITECTURE.md + HANDOFF.md. 4. optional: alt-fire sound, sniper reticle.

DECISIONS OTHER AGENTS DEPEND ON
- A hero launch of ANY weapon (wave 115 snake bombs, wave 116 hero-fired ordnance) plays its voice with WeaponAudio.launch(id, def) (mechanism + body + tail of WeaponAudio.set_of(id)); a charge weapon with charge_start / fire_charged.
- The `interval` of a burst weapon is the time from the start of one burst to the start of the next (the roster formula, the card and the balance model say so); the FIRE MODE burst multiplies it by rounds x 0.85 (WeaponMech.interval_mult).
- A dry weapon with nothing in reserve hands the trigger to the next loadout slot that shoots (PlayerWeapon._auto_swap, toast OUT OF AMMO).
- The play HUD's kill / pickup feed lives under the objective / toast lane (HudFeed.MAX_W, Hud.msg_top + MSG_H); anything new that hangs from the top right must stay out of the centred lane or sit under it.
- CrateReveal.in_combat() (an aware enemy within 50 m) makes a reveal compact; other overlays that dim or cover the middle of the view for seconds should do the same.
- The LOOK critic works on hud.gd, player_body.gd, weapon_models.gd, foe_arms.gd, touch_controls.gd and scope_view.gd in the same tree: edit them with one-line hooks and never restore a whole file from a copy.

TESTS AND PERF
- (none yet)

OPEN PROBLEMS
- (none yet)
