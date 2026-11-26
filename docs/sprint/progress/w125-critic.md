# w125-critic log (independent review + fixes of wave 125: helicopter roster, cockpit, helipads)
GOAL: review w125 by a finger-only bot in the real main scene, list 8 worst defects, fix most severe first with fail-first checks.
DONE
- Bot godot/tests/bot_w125_critic.gd (CR_PARTS kinds,pads,crash,draws): all 23 kinds boarded/flown/cockpit/landed by finger (airport, LOW); 6 new pads day LOW + night MED; crash.
- Fix 1 rotor disc into walls: vehicle_craft.gd _rotor_clear (cylinder query per hub, push-out + bounce). rotor_fix flag.
- Fix 2 radio plate covered heli name badge: flight_hud.gd badge_rect (badge steps aside while a line shows). badge_fix.
- Fix 3 tower floor "ROOF" under PARKED card while in heli: tower_lift.gd floor_fix + floor_label_text().
- Fix 4 cockpit +30 draws: heli_cockpit.gd pen (one triangle array + text batch). batch_fix.
- W125C_OLD=1 turns all four off.
TESTS AND PERF
- tests/test_w125_critic.gd PASS new; old 5 FAIL (rotor 2.8 m vs 6.4, badge x3, floor). bot CR_PARTS=draws: old worst +30 FAIL, new +4 ok.
- neighbours PASS: helipads_w125, airport_aircraft, helis_w125 (h_scout,h_tandem), controls_w118.
- perf (1 run): LOW death 108 OK, MED 146 OK, HIGH 164 OK.
OPEN (not fixed): NEWS pad unreachable from the roof by the bot (hero under raised deck); pad signs fill 1/4 of the view from the roof; cockpit panel hides the pad below when landing; cockpit repeats ALT/ROTOR of bottom plate.
