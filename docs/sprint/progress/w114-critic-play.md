# w114-critic-play (independent critic and fixer, lens PLAY: function, feel, measured behaviour; scope: weapons in hand and the weapon screens of wave 114)

GOAL: review the wave 114 work (weapon kit in hand and in enemy hands, Arsenal / wheel / loadout / shop / crate reveal / card screens, weapon sound) by MEASURING it in the real scene at 844x390 and 1280x720,
write the 8 worst defects, fix them (most severe first), add regression tests, run the tests of every touched file and the perf gate if rendering changed.

STATUS (2026-11-14 19:50 UTC): DONE, 6 fixed by me + 1 fixed by the LOOK critic, 1 group open. Nothing committed (the integrator does that).

DEFECTS (probes tests/dev_w114_*.gd, bots tests/bot_w114_*.gd; regression tests tests/test_play_critic_w114.gd (sound, ammo, burst) and tests/test_play_critic_w114_ui.gd (hud, touch, reveal))
1 FIXED  63 weapons never used their wave 114 sound set: 56 of the throw kind (grenades, mines, strike beacons, launchers, pods) played the QUANTUM BLINK (blink + phase_step) or another weapon's recording, 7 charge
         weapons (lance, beam / rail rifles, a BOW) the ENTANGLE hum and the plasma overcharge zap. WeaponAudio.launch / charge_start / fire_charged + hooks in player_weapon.gd (_throw, _tick_charge, _fire_lance),
         combat/blast_ops.gd, player/energy_arms.gd (salvo, fan); ASSIGN rows rocket -> lau_rocket, grenade -> thr_frag; tests/test_audio_redesign.gd (half charge = shot_lance).
2 FIXED  PlayerWeapon._auto_swap (documented since wave 85, never called): a dry weapon with nothing in reserve clicked for ever. Wired in tick + _tick_charge, prefers the 4 loadout slots, falls back to the blade.
3 FIXED  Burst weapons (10: burst pistol, bullpup, tempo, double tap, triple tap, crest, rook, pulse rifle, superposition shotgun, qsuper) fired at HALF the rate and damage per second their card shows (the last round
         of a burst added a second interval; measured 240 rpm against 429 shown): player_weapon.gd tick (burst branch).
4 FIXED  HUD: the kill / pickup feed (4 lines) hung from y = 20 across the centred objective line and the toast (23 / 19 % at 844x390, 44 / 30 % at 1280x720): hud.gd hangs it under msg_top + MSG_H, hud_feed.gd MAX_W.
5 FIXED  Crate reveal in a fight: a 50 % dim over the whole screen, 14 rays and a 560 x 366 card over the middle of the view for 3.4 s while enemies shoot: CrateReveal.in_combat() -> a small card (62 %) at the left, no dim,
         no rays, 2.0 s (crate_reveal.gd). Quiet street: unchanged.
6 FIXED  Alt-fire of every weapon ended with the ENTANGLE blip (+ its entangle_link layer) under a slug, a scope switch, a vent: removed from player_weapon.gd alt_fire; SPIN SWEEP and SHOVE (11 melee weapons and a
         shotgun) had no other sound when they hit nothing: WeaponMech._swing_sound(). tests/dev_w114_alt.gd prints the last sound of every alt kind (163 alt-fires of 11 kinds are checked).
7 FIXED (by the LOOK critic, ScopeView + tests/test_scope_view_w114.gd) sniper ADS showed no scope reticle (zoom 12 - 30 degrees).
8 OPEN   barrel lags the aim line 6 - 13 degrees during bursts while looking 26 degrees down (aim probe, 2 - 5 at level pitch: rig / player_body, LOOK area); 15 hitscan weapons need more than the 6 voices of the
         `shot` family at full auto (carbine 8.0, e_laser 22): the oldest shot is cut at 0.6 s, inaudible; the kill-feed icon is the weapon in hand when the kill is polled (a blast or car kill can show the wrong
         one); m_shield thumb is an edge-on sliver (taken by LOOK).
MEASURED OK: equip 0.9 ms mean (2.5 ms worst, +24 MB static after all 229); every weapon obtainable (7 starters, 47 shop, 68 crates (27 secret), 93 drops, 12 mission, 2 boss); no NaN in any def; ammo packs fine;
         monkey 100 s with all weapons (no script error, no stuck reload); texture memory at LOW with the Arsenal fully used 92 -> 103.8 MB (+11.8, pages cap at 16); firing adds +6.5 draws on average and +16 at the
         peak at LOW (tracers, hero flash, sparks, no single culprit); real touch events on the Arsenal (tap, drag, flick, snap, equip, back, quick mode) all work at 844x390; trigger latency: only the 7 charge weapons
         need more than 0.5 s (0.8 - 1.5 s by design), rotary spin-up 0.2 - 0.42 s; stats vs behaviour: median measured / shown rpm 1.02.

DONE (files)
- NEW tests/test_play_critic_w114.gd + _ui.gd, probes tests/dev_w114_{sound,aim,equip,hud,data,monkey,rate,latency,alt}.gd, bots tests/bot_w114_{mem,fx,fx2,reveal,feed}.gd
- EDITED scripts/audio/weapon_audio.gd, scripts/player/{player_weapon,energy_arms,weapon_mech}.gd, scripts/combat/blast_ops.gd, scripts/ui/{hud,hud_feed,crate_reveal}.gd, tests/test_audio_redesign.gd,
  tests/test_director_fixes_b.gd (thickness 1.29: float32 of 1.3), docs ARCHITECTURE.md + HANDOFF.md
- sheets docs/shots/round6/play_critic_w114_{feed,reveal}_before_after.jpg

DECISIONS OTHER AGENTS DEPEND ON
- A hero launch of ANY weapon (wave 115 snake bombs, wave 116 hero-fired ordnance) plays its voice with WeaponAudio.launch(id, def) (mechanism + body + tail of WeaponAudio.set_of(id)); a charge weapon with charge_start / fire_charged.
- The `interval` of a burst weapon is the time from the start of one burst to the start of the next (the roster formula, the card and the balance model say so); the FIRE MODE burst multiplies it by rounds x 0.85.
- A dry weapon with nothing in reserve hands the trigger to the next loadout slot that shoots (PlayerWeapon._auto_swap, toast OUT OF AMMO).
- The play HUD's kill / pickup feed lives under the objective / toast lane (HudFeed.MAX_W, Hud.msg_top + MSG_H); anything new that hangs from the top right must stay out of the centred lane or sit under it.
- CrateReveal.in_combat() (an aware enemy within 50 m) makes a reveal compact; other overlays that dim or cover the middle of the view for seconds should do the same.
- An alt-fire plays the sound of what it does (no shared blip); a new alt kind that is silent when it hits nothing needs its own sound (tests/test_play_critic_w114.gd, section sound, fails on a silent kind).

TESTS AND PERF
- Mutation runs: every fix was undone with a one-line edit and its check failed (hud, burst, sound / launch, alt blip, swing sound, auto-swap, compact reveal), then restored exactly.
- Batch of 54 files under load (JOBS=3 and another critic running): pass 42, flaky 5, fail 7; all 7 pass SOLO on a quiet machine: vehicle_realism, open_world_freedom, real_fight, shooting_accuracy (93 s, grenade 0.2 m off), full_quick
  (135 s of its 140 s limit: slow under load), weapon_pics and weapon_ui_v3 (they failed on atlas pages re-generated at 19:05 and not yet imported: not mine). After the alt change: 11 files pass (altfire, roster, depth, v3,
  energy_destructive x2, melee_gadgets, audio_redesign, weapon_audio_v3, both critic files).
- Perf gate, run once (PERF_CHECK=1 tools/perf_report.sh 0 1 2, exit 0), verdict lines:
  LOW  draws=73 total_draws=95 death_draws=107 tex_mb=112 hud_draws=19 verdict=OK   (limits total 100 / death 115)
  MED  draws=97 total_draws=129 death_draws=149 tex_mb=143 hud_draws=24 verdict=OK  (limits 130 / 150)
  HIGH draws=113 total_draws=149 death_draws=169 tex_mb=209 hud_draws=25 verdict=OK (limits 150 / 170)
  LOW is +3 draws against the builders' 70 / 92 (hero weapon size and flash are the LOOK critic's edits); my edits draw nothing in the staged view (no feed line, no reveal).

OPEN PROBLEMS
- Item 8 above.
- test_full_quick needs 135 s of its 140 s budget on this machine (a loaded runner times out); test_shooting_accuracy failed twice under load (grenade 12 m landed 284 / 651 m off, a stale well or collapse of
  an earlier section is my guess) and passed twice solo (grenade 0.2 m off): flaky, not touched by my hunks (audio, burst cadence and auto-swap act on a held trigger only).
