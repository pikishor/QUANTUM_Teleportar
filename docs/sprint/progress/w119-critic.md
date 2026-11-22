GOAL: independent review + fixes of wave 119 (snake blasts, hud5) with a finger-only bot
DONE (all checks in godot/tests/test_w119_critic.gd, PASS; W119C_OLD=1 fails 7):
- FIX1 context slot settles: touch_controls._settle_slot (+SLOT_SETTLE 0.25 to ENTER, back to BLAST at once, locked under a finger, BLAST 2.5 s after a throw); SnakeBlasts.since_throw
- FIX2 fire species short BLAZE (button read FIRE 3)
- FIX3 SNAKE TYPE disc item type &"snake" in touch_controls ability items -> test_menu_cut PASS (was 3 red)
- FIX4 snake_bombs.throw: crosshair on sky -> street under it (was airburst 5-11 m up)
- FIX5 vehicle.ignite: tank/armoured above 40% does not catch fire (BLAZE/ACID one-shot a tank)
- off switch: TouchControls.CRITIC_OLD (env W119C_OLD=1)
- probe bot godot/tests/dev_w119_critic.gd (rendered, traffic on)
NEXT: done; report sent. PERF (one run): LOW draws 72 death 107 OK, MED 97/149 OK, HIGH 113/170 OK
TESTS: test_snake_blasts_w119 PASS (alone; flaky under load, pre-existing), test_controls_w118 PASS (plane ENTER flaky, hud5 known), test_menu_cut PASS
OPEN: species pick 3 taps deep; parked cars keep ENTER in slot often; ENTER may board another car than the one beside
WHITE QUADS: hover ~7 m up after a FROST burst at LOW, source not traced (docs/shots/round7/w119_critic_white_quads.jpg)
