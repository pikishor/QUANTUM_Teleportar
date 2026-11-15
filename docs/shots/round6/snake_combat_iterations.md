# QUANTUM SNAKE combat: render-look-fix iterations (wave 115, combat builder)

Tool: `tests/bot_snake_war.gd` (the real game, the real camera behind the hero, ONE power at a time cast at three troopers 10 m ahead and a parked sedan; four frames per power) driven by `tools/bot.sh`
at 1200x540 (the size of the owner's round 5 shots), `QUALITY=0` (LOW) and `QUALITY=1` (MED), `--fixed-fps 12`, `BOT_USER_ARGS="--touch"` for the phone HUD from loop 11 on. A bomb is shot at the street
between the troopers, its frames are counted from the moment it goes off (throw, burst, spread, after). Every loop opened the frames as sheets (`tools/contact_sheet.py` and a labelled composer) and wrote the defects down first.

## Loop 1: LOW, 11 powers, 10 m (the first sweep of the wave)
Defects: snakes read as thin pale ghosts at 10 to 13 m; the default blast fx fogged the street (smoke, a 12 m dome); the guard ring was a 25 m disc and the net ring a line on the horizon.
Fixes: fx recipe `snake` (a small pop, a thin ring, no smoke) in BlastFx, blast fx radius clamped at 3 m, rings only for net, trap and shield and snapped to the street, thicker bodies, glow 0.6.

## Loop 2: LOW, coil, swarm, chain, seeker, guard after the rework
Defects: bigger snakes but the burst still hid them; bombs of 4 snakes at LOW looked like a handful of worms. Fixes: crawlers 0.12 to 0.15 m, longer life after the bite, rings as the radius sign.

## Loop 3: MED, the wheels and the HUD with the touch layer (`tests/bot_snake_ui.gd`)
Defects: the WEAPON button text "ENERGY 100" was clipped; the ring pictures were fine. Fixes: the button says "82%" (a cooldown reads "1.2 S").

## Loop 4: LOW, the draw and triangle budget (`tests/bot_snake_war_perf.gd`)
Result: the free snakes are one draw; shield +1 draw, swarm bomb +1 draw, everything at once +33 draws of which the snakes are 1. No fix needed.

## Loop 5: LOW, all verbs and bombs again (this session)
Defects written down: (1) the bombs of the sheet landed 22 m away: the bot set the crosshair AFTER the cast (bot fixed: aim first, snap, cast); (2) a body pooled from the stage before kept its freeze tint
(bot resets the damage layers: `DamageWorld.current.foes.reset()`); (3) white rectangles over the troopers while the decoy was out: the stealth pips are drawn as white plates (`fx_threat.gdshader`, NOT mine,
reported); (4) shield tubes as thick as the hero and a cyan floor disc (the preview ring of the shield); (5) a guard snake at the lens like a crystal; (6) the storm ring seen edge on as a white bar across the frame.

## Loop 6: LOW, the 12 bombs with the right aim and frames counted from the detonation
Result: coil, swarm, constrictor and net wrap every trooper in violet or green coils, the freeze dome and the gravity dome read at once, the flare flash and its diamonds read, the mega python is the best frame.
Defects: seeker and burrower are pale clumps with a rope at the hand; cluster bomblets tiny; chain arcs thin; storm colour washed out.

## Loop 7: LOW after the first fixes (shield, guard, trap, seeker, burrower, cluster)
Fixes: snakes closer than 4.4 m to the lens are drawn thinner (`SnakeSwarm.NEAR_FROM / NEAR_TO`), the shield is slim, low and wide (3 / 4 / 5 snakes by tier) and has no floor disc, the trap has a coiled nest,
the cluster bomblets are 0.3 m balls, ICE / STORM / GOLD are more saturated.

## Loop 8: MED (shield, yank, grab, swarm, storm, seeker)
Result: the shield swirls round the hero without hiding him, the yank sends the car into the troopers, the grab lifts and slams. Defect: the seeker still starts with a thick loop of rope next to the shoulder camera.

## Loop 9: LOW (guard, trap, seeker, burrower, storm, decoy)
Fixes: no rope at the hand for the seeker and the burrower (a pop of sparks), slimmer seeker (0.12 m, 4.2 m long), burrower 0.15 m with a darker dust ridge, trap ring and nest thicker.

## Loop 10: LOW (yank, decoy, seeker, burrower, disarm, lash)
Defects: the decoy was a dim spiral behind a trooper (fixed: a standing cobra, thicker coils, a bigger ring); the yank staging put the car beside the troopers (bot: the car stands in front of them).

## Loop 11: MED with the phone HUD (net, coil bomb)
The frames now show what the owner sees (buttons AIM, RELOAD, ZIP, FIRE, JUMP, ABILITY, the WEAPON button with the armed power and its energy). All later sheets use `--touch`.

## Loop 12: the final sheets, LOW and MED, 22 powers x 4 frames, plus the wheels and the HUD and the before / after
`snake_combat_{verbs_a,verbs_b,bombs_a,bombs_b}_{low,med}.jpg`, `snake_combat_wheels_hud_med.jpg`, `snake_combat_before_after.jpg`. A last tweak came out of this loop: the shield orbit radius 1.3 to 1.15 m.

## Review against docs/owner_shots/round5 (the phone frames of the owner)
Same size, same HUD, same night street; the snakes sit in the colours of the powers and are readable at 10 m on a phone. Still open: the hero has no cast animation (arms keep the rifle hold, the hands glow);
a trooper that was hit shows the white hit flash of the game for a moment (looks like a white cut-out in the lash and yank frames); the flare and gravity domes are large (the table radius 12 and 9 m);
the seeker and the chain arcs are small at 10 m; nothing is measured on a phone.

## Budget at LOW (bot_snake_war_perf.gd, 640x360, `--fixed-fps 15`; staged view 65 visible draws, 121k triangles, 104 MB textures)
armed (ring, arc, label) +3 visible draws; shield +2; net +3; guard +5; flare with its marks +11; mega python (11 bodies and the blast) +19. One snake body is 216 triangles at LOW (18 rings x 6 sides), a full pool of 16
is 3.5k triangles in one draw; the particles are the pooled `FX.burst` emitters of the tier (a swarm bomb adds 3 bursts at most). The gate afterwards: LOW 70 draws / 112 MB, MED 97 / 143 MB, HIGH 113 / 209 MB, all OK.
