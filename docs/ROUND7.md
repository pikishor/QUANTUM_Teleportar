# Owner round 7 (2026-11-20, wave 115 APK, rating "still 4/10, even worse")

Screenshots: docs/owner_shots/round7/ (20 frames, phone, tier LOW+, FPS 37 to 45, worst 13 to 35).

## What the owner said
1. Demo mode: "I just keep on seeing weapons but can't choose any" (a MISSION REWARD card over the game, the pause menu, the loadout, the test menu, for minutes).
2. "Opening the map, no back button etc works, which I have told you many many times."
3. Gameplay in general: "small silly errors. Are you even checking."
4. Not many details on the street.
5. He wants to walk into buildings and climb stairs.
6. Snake bombs and the snake zip line do not work properly.
7. "Many many other comments which I am tired of typing."

## Root causes found and fixed first (commit "Round 7 fix 1")
- (1) `DemoMode._grant_all` unlocked 229 weapons through `Progress.grant_weapon`, each one queued a 3.4 s reward card: about 13 minutes of cards, drawn at z 50 with PROCESS_MODE_ALWAYS over every
  screen. Fix: the bulk unlock switches the cards off and clears the queue; the queue holds 2 at most; a tap closes a card; a card never stays over a menu or a pause.
  Why the tests missed it: `CrateReveal.suppressed()` is true under every test and bot, so no test ever saw a card.
- (2) `emulate_mouse_from_touch` is off and a Godot `Button` only answers the mouse. The map's CLOSE / MISSIONS / ZOOM / GPS / YOU / GOAL / CLEAR and filter chips, the garage, the fast-travel list
  and the watchdog's rescue BACK are `Button` nodes: on a phone none of them ever fired. Every test clicked them with a mouse or called the function. Fix: `TouchButtons` (scripts/ui/touch_buttons.gd)
  turns a finger on any visible Button into a press. Test `tests/test_touch_buttons_r7.gd` sends real `InputEventScreenTouch` events; it fails 5 checks with `TB_OFF=1` (the old behaviour).

## RULE from this round
A UI test must drive the screen with real `InputEventScreenTouch` events through `Input.parse_input_event` (window coordinates), never the mouse and never a direct call, and must run with
the phone-only layers (reward cards, hints) switched ON.

## Still open (next)
- Snake zip and snake bombs on a phone: reproduce with touch events (what exactly fails is not known yet: ask the owner or find by a touch bot).
- Buildings with stairs and floors to walk; street detail (clutter, storefronts); frame rate (37 to 45 FPS on LOW+, drops to 13 to 28 while flying: VEHICLES script time 4 to 6.5 ms in the air far from any car).
- A touch-only audit of every screen and every HUD button (the same class of bug may sit elsewhere).
