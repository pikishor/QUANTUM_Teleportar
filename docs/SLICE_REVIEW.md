# Creative director review (owner's eyes, after the fundamentals sprint)

Build: HEAD 5d061cc (wave 89). Method: a bot plays the real game like a new player at the phone aspect (1600x720, same 2.22:1 as 2400x1080, touch HUD on),
real camera, real input path, no test shortcuts except where marked. 120 frames at LOW (QUALITY=0), about 65 at MED (QUALITY=1); every frame was opened and compared with
docs/owner_shots/round1-2 and the round 3 complaints. Contact sheet: `docs/shots/slice/director_review_sheet.jpg` (28 numbered panels, referred to below as `#n`);
single frames in `docs/shots/slice/director_review/`.

Reproduce: `DR_OUT=/tmp/dr DR_ACTS=title,first,fight,civ,car,interior,menus BOT_RES=1600x720 QUALITY=0 ENGINE_ARGS="--fixed-fps 12" BOT_USER_ARGS="--touch" BOT_TIMEOUT=580 tools/bot.sh res://tests/bot_director_review.gd /tmp/x 100000 1`
(`godot/tests/bot_director_review.gd`; acts can be split; `DR_FIRST_SECONDS`, `DR_FIGHT_SECONDS`). It reuses `mission_audit.gd` for walking the campaign and `fight_bot.gd` for the fight.

Limits of this review: software GL (no real phone), audio is muted under bots (not judged from frames), the fight and the first objective run with the hero healed
by the bot (so difficulty was judged from the interior and the car, where it was not healed), civilians and one weapon only (carbine).

## Overall: 3.5 / 10 (owner round 2 said 2.5)

It is a real game now: the first objective is on screen, the route is walkable and the audit bot finishes the first three steps and the next chapter without a stuck state,
the city has traffic, people and rain on MED, the pause menu is four buttons, the map is no longer black. What still makes it look and feel like a prototype is the **hero
(a faceless black mannequin that reads nude from behind)**, **no visible weapon**, **toy cars with a cliff-edge damage model**, **HUD circles on top of each other**, a **600-icon map**
and an **interior that kills a new player in 11 seconds**.

| Area | Score | Why in one line |
|---|---|---|
| Shooting | 4 | Tracers, hit numbers and the red target brackets work (#7); 37 % of rounds hit in the fight (90 of 245) and the last 10 s of the fight landed 0 hits while the bot kept firing into a parked car (#8). |
| Weapons display / count | 3 | 18 weapons exist, but from the shoulder camera the weapon is a thin stick at the hip or hidden (#3, #4, #7); it only reads in the interior (#15). |
| Vehicles | 3 | Boxy flat cars, black cut-out parts, 92 km/h feels slow, one crash at 92 km/h = wreck + 67 % of the hero's health (#10-#12). |
| Objective clarity | 5 | Compass, beacon pillar and "NEXT" line are good (#3, #4); the old "QUANTUM CORES 0 / 6" line and the chapter ghost title fight them (#2, #3); inside a building the line is wrong (#14). |
| Menus | 4 | Pause is clean (#17); MORE has 11 buttons incl. TEST, options 20 buttons, loadout labels are tiny "BUY 700" (#18-#20). |
| Map | 3 | 77 % charted and ~600 overlapping icons: INTERIORS 213, SHOPS 320, JOBS 20 (#21, #28). The one thing the player needs (the objective) is lost. |
| Visual clarity | 4 | Good night streets on MED (#22, #24); LOW has a purple/pink haze and flare blobs (#3, #4); white blown surfaces at the lens in interiors and on a facade (#15, #26). |
| Life | 4 | People, cars, vendors present (#6, #9); the crowd flees when shot (#9); but everyone is a box or the same mannequin and far figures are 20 px tall (#7). |
| Fight | 4 | First contact at 8 s, a 5-man wave at 24 s, enemies stop at ~8 m and trade from behind cars (#7, #8): readable, but not frightening and not a move-and-flank fight. |
| Audio | n/a | Not assessable headless. Owner said music poor; no new evidence. |

## The 15 most damaging defects (worst first)

1. **Hero is a faceless black mannequin and reads nude from behind.** Every third-person frame: #1 title, #3, #4, #5, #7, #14. Black skin, magenta rim, bare back and rear, no clothing
   silhouette, no hair/face detail, no colour. It is the single biggest "toy" signal, on screen 100 % of the time. Files: `godot/scripts/characters/hero_character.gd`, `godot/scripts/player/hero_look.gd`, `hero_presentation.gd` (suit material, outfit geometry).
2. **The weapon is not displayed.** From the over-the-shoulder camera the carbine is a thin stick against the hip or hidden by the back (#3, #4, #7); the gun only reads in the interior close-up (#15).
   Owner round 3: "even weapons display is not good". Files: `godot/scripts/player/weapon_models.gd`, `camera_rig.gd` (shoulder offset, aim pose), `hero_presentation.gd` (hold pose).
3. **Touch HUD circles overlap each other and the scene.** MORE sits under the weapon plate, RELOAD overlaps AIM, GRAB/ENTER/AIM stack on the right edge (#4, #5, #8, #14); 9-10 circles plus pause, minimap, bars,
   status box and stars. Frame #5: the weapon plate shows "..." under MORE. File: `godot/scripts/ui/touch_controls.gd` (BUTTONS layout and context buttons), `hud.gd`.
4. **Top-of-screen banner pile and a leftover objective.** At the very start the HUD says "QUANTUM CORES 0 / 6  NEAREST 155 M" (the old sector goal) while the story cards run, then objective + compass + radio box + chapter
   title ghost ("THE SPLIT HOUR" half transparent behind the objective, #3) + DRONES NEUTRAL / SPOTTED box + stars. A new player cannot tell which line is "the" goal. Files: `godot/scripts/ui/hud.gd`, `scripts/missions/missions.gd` (core counter shown during the campaign), `campaign_runner.gd:hud_line`, `scripts/story/story.gd` (title card), `toast.gd`.
5. **Story cards take ~16 s of "TAP TO CONTINUE" over a live street** with the HUD dimmed under them and the controls greyed (#2); in the no-campaign run the hero lost 40 integrity in the first 8 s of play while nothing was asked of him.
   Cards should be 2 lines, tappable once, and the world frozen or the hero safe. Files: `godot/scripts/story/story.gd` (cards, `skip_cards`), `scripts/main.gd` (new game start).
6. **Entering a building starts a hostile job at once and kills the player.** The bot walked through the lobby for 11 s and went 100 -> 0 (#14, #15, #16 DECOHERED); no warning on the ENTER prompt (#13), no cover, enemies spawn armed inside the room.
   Owner: "sometimes too hard". Files: `godot/scripts/interiors_gameplay/interior_missions.gd`, `interior_actors.gd`, `interior_gameplay.gd` (prompt text, spawn at entry), balance in `docs/BALANCE.md`.
7. **Inside a building the objective line is wrong, then overlaps.** On entry the HUD still shows "CROSS THE TRADING FLOOR TO THE BEACON  0 M" (#14), then "SAFE  REACH THE VAULT"; the prompt "LEAVE  SILT PLAZA" sits where the weapon plate is;
   the DECOHERED title overprints "SAFE REACH THE VAULT" (#16). Files: `godot/scripts/missions/mission_guide.gd`, `campaign_runner.gd` (armed/interior line), `interior_missions.gd`, `hud.gd` (dead screen).
8. **Cars are toys.** Flat boxy sedans with black cut-out wheels and windows, one parked car rendered as a pure black silhouette (#8, #11), a parked car's wheel and hood filling a quarter of the frame at the lens (first chase-step frames, not on the sheet),
   untextured paint. Files: `godot/scripts/vehicles/vehicle.gd` (visual, LOD), `scripts/ambient/` near traffic cars (materials, key light), `scripts/world/` parked car placement vs camera.
9. **Driving feels slow and the view is small and cluttered.** The player car is ~20 % of the frame, a low tight chase camera, 92 km/h reads as walking pace in the streaks (#10); eight extra widgets while driving
   (EXIT, BACK, VIEW, RADIO, RADIO OFF, EXIT VEHICLE, HULL bar, speed). Files: `godot/scripts/player/camera_rig.gd` (driving section: FOV/distance by speed, speed lines), `touch_controls.gd` (driving column), `scripts/vehicles/car_radio.gd` (label).
10. **Crash damage is a cliff, not a curve.** A 76 km/h hit cost 12 % hull (MED run); a 92 km/h hit destroyed the car (hull -35 of 250), exploded it and the driver left with 33 / 100 integrity (LOW run, #11, #12). The player loses the car
    he just took for a single steering mistake ("gets damaged in a single crash"). Files: `godot/scripts/vehicles/vehicle_specs.gd` (`CRASH_SAFE 6.5`, `CRASH_WRECK 27`, `CRASH_POWER 1.6`, `CRASH_REF_HP 300`), `vehicle.gd:hurt_driver`/crash, `vehicle_manager.gd` (starter freed on wreck).
11. **Map is a cloud of ~600 icons at 77 % charted.** Rows: INTERIORS 213, SHOPS 320, JOBS 20, GARAGE 48, WEAPONS 11, ITEMS 30 with labels (NEON MARKET, FOUNDRY ROW ...) printed through them (#21, #28). The objective is one of the same dots.
    Hide classes by default (show the objective, the player, open jobs, the nearest few shops), keep fog for what is not known, make "77 % charted" start lower. Files: `godot/scripts/ui/map_screen.gd`, `map_icons.gd`, `scripts/ui/minimap.gd`.
12. **Menus are lists of small buttons.** Pause is only 4 buttons but 12-px labels (#17); MORE shows 11 buttons including an orange TEST on the player page (#18); options is 20 buttons in three columns (#19); the loadout shows "BUY 700 / 1260 / 980" with
    9-px captions so a player cannot tell what they buy (#20); GEAR/BACK pushed to the corner. Files: `godot/scripts/ui/hud.gd` (`_layout_more`, pause layout), `options_screen.gd`, `loadout_screen.gd`, `scripts/ui/ui_util.gd`.
13. **Fight is readable but flat.** Enemies are the hero's mannequin with a rim colour (#14, #15), tiny dark figures at 15+ m (#7), they hold at ~8 m and trade from behind parked cars where rounds are absorbed (#8); 90 hits of 245 shots,
    0 hits in the last 10 s; no flank, no grenade, no cry. Files: `godot/scripts/enemies/enemy_look.gd`, `humanoid_variants.gd`, `tactics_table.gd`, `enemy_cover.gd` (cover choice vs hero line), `encounters.gd` (waves come ~24 s after the first contact).
14. **First minutes send a new player into a 3-star response.** Step 3 "HACK THE LEDGER NODE ... RETURN TO THE RING" holds the hero in place while heat climbs 0.9 -> 3.3 (frames #5, ROADBLOCKS toast), with no way to know to fight or run; the wording "RETURN TO THE RING" is cryptic.
    Files: `godot/scripts/missions/campaign_steps.gd` (hack step, heat feed), `wanted.gd`, `mission_guide.gd` (hint text).
15. **LOW look: purple/pink haze, lens-flare blobs and blown white planes.** A magenta fog over half the street and big warm flare discs at the lens (#3, #4), a pure white/lilac facade filling the right half when walking next to a shopfront (first car run, hero on foot after the crash; not on the sheet),
    square white wall lights at the lens in the interior (#15, #26), the interior's fake window is a pixel skyline. Files: `godot/scripts/world/city_env.gd` (fog/glow by tier), `scripts/world/` shop wash and facade emissive caps, `scripts/interiors/interior_kit.gd` (wall lights, window).

## What improved since round 2 (keep)
- Title is clean: PLAY / OPTIONS / MORE, no TEST/DEMO tag clash (#1). Pause menu is four buttons (#17).
- Objective line + compass strip + beacon pillar + distance (#3, #4): the first 90 s are followable; the audit bot finished chapter 1 and entered chapter 2 without a stuck state (steps 1/3 .. 3/3, then "BLINK UP TO THE SKY BRIDGE", "CHASE THE COURIER").
- Crowd reacts to a shot civilian (people run, "WANTED LOST" toast, heat 0.9) (#9). First contact at 8 s, wave of 5 at 24 s.
- MED night streets with rain and wet roads look good in a still (#22, #24).

## Suggested order for the next sprint (gameplay and bugs before art)
1. Interior entry safe-start + correct HUD line (6, 7); hack step fairness (14); story cards shorter (5).
2. HUD button layout and banner discipline (3, 4, 12); map declutter (11).
3. Weapon visible in the shoulder view (2); hero look (1); crash damage curve and car camera (9, 10).
4. Enemy readability and cover behaviour (13); LOW haze and white planes (15); car visuals (8).

## Bot notes
- `bot_director_review.gd` leaves the audio muted and switches the campaign on (`campaign.enabled = true`; under `Game.autostart` it is off by default, so most older tool shots show no objective at all). The "QUANTUM CORES 0 / 6" line was seen in the title -> PLAY run, i.e. the real flow.
- Timings (software GL, 4 cores): LOW 1600x720 about 0.5 s per frame at 12 fps game time, MED 2-3x; the MED fight run was cut short at 15 frames because two MED runs in parallel did not fit in the 10 minute limit.


## Fix pass, gameplay half (test `godot/tests/test_director_fixes_a.gd`, real scene)
Looked at with `tools/bot.sh res://tests/bot_weapon_hold.gd` (hip and ADS from the real shoulder camera, LOW and MED, 1600x720), `tools/vehicle_bot.sh` (BOT_SET=drive, LOW) and `bot_director_review.gd` (`DR_ACTS=interior`).
Sheet: `docs/shots/slice/director_fixes_a_before_after.jpg` (left BEFORE, right AFTER). Visual half (hero look, HUD circles, banners, map, menus, LOW haze) is another builder's.

| # | Defect | Before | After |
|---|---|---|---|
| 2 | Weapon invisible from the shoulder camera | rifle hidden behind the hero's back at hip and behind the shoulder in ADS | hip camera 3.2 m / 0.95 m out (was 3.6 / 0.8), ADS 0.72 m out and 0.14 m up (was 0.55, flat), the lowered rifle swings out to the side (`CharacterRig.LOW_READY_YAW`): the barrel shows to the right of the hero at hip and in ADS. Still small: the weapon models are thin (art follow-up) |
| 5 | About 16 s of story cards over a live street | 34 cps, 2 s + 0.03 s/char hold | 90 cps, 0.6 s + 0.01 s/char (10.8 s untouched, a tap skips) and the hero cannot be hurt while the prologue runs |
| 6 | Entering a building killed the hero in 11 s | hunters 1.4 s after the door, no grace | 6 s of invulnerability after the door closes (`InteriorGameplay.ENTRY_GRACE`), first hunter after 5 s, then every 2.2 s |
| 7 | Wrong objective line inside | street step "CROSS THE TRADING FLOOR ... 0 M" for the first frames | the room's job is the plate's line from the first frame; a room without a job says LEAVE THE BUILDING TO CONTINUE while a street step runs |
| 8 | Pure black cars | interceptor palette 0.12 value, husk 0.045 | interceptor navy and slate (value >= 0.4), husk soot-brown 0.15 |
| 9 | Small, slow-feeling driving view | car length x 1.2 + 1.9 m behind, FOV 64 -> 82 | x 1.0 + 1.6 m, FOV 68 -> 98 at top speed: the car fills more of the frame and the street streams past |
| 10 | Crash damage is a cliff | 92 km/h wrecked the car, the driver lost up to 67 % | a hull above half health survives ONE hit up to 26.5 m/s (95 km/h) and limps home with 12 %, a scrape is one crash (0.35 s), the driver loses at most 30 % of his health per crash; 120 km/h still wrecks |
| 14 | The hack leads to a 3-star wanted level | the step's own kills pushed heat to 3.3+ | hack and defend hold heat at 1.9 (`HOLD_HEAT_CAP`), first drone pulse after 8 s (was 5) |

Not done in this pass (still open): 13 flat fight (clone enemies, 37 % of rounds hit; cover tuning was left alone, the Vael already barely hide), driver / passenger seats drawn, car art (still boxy, no new models), nothing measured on a phone, no audio judged.

## After: presentation fixes (director fixes B)
Before / after contact sheet: `docs/shots/slice/director_fixes_b_before_after.jpg` (hero, street HUD with the step line, pause, loadout, map; LOW, 1600x720). Rig: `godot/tests/bot_dfb.gd`
(`DF_OUT=/tmp/x DF_VIEWS=back,three,aim,walk,camp,camp_walk,enemy BOT_RES=1600x720 QUALITY=0 BOT_USER_ARGS="--touch" tools/bot.sh res://tests/bot_dfb.gd /tmp/y 100000 1`; it exits when done) and
`bot_menu_shots.gd` (new `MENU_ONLY=pause,loadout,map`). About 8 render-look-fix iterations (hero x5, HUD/story x2, map x1, menus x2); test: `tests/test_director_fixes_b.gd` (real scene, 52 checks).

| # | Defect | Status | What changed |
|---|---|---|---|
| 1 | Hero is a black mannequin | improved (not solved) | `hero_body.gdshader` now draws an OUTFIT: light steel-blue jacket that covers the hips (hem line, zip, chest flaps, dark collar yoke), dark trousers, black boots with a pale sole line, belt and buckle on the front, rucksack plate with an accent stripe on the back; rougher cloth (no oiled look), flatter muscle normals, a brighter fabric floor so he is never black in a shadowed street. Colours are uniforms (`jacket_color`, `pants_color`); `HumanoidVariants.outfit()` gives troopers dark armour and citizens their casual colour over dark trousers, so enemies no longer match the hero. Still the same low-poly body underneath: a real clothed mesh is the next step. |
| 2 | Weapon invisible from the shoulder | improved | `PlayerBody.WEAPON_LOOK_SCALE` 1.4 / 1.4 / 1.12: a thicker gun that shows past the hero's side (camera offset is the other builder's part). |
| 3 | HUD circles overlap | fixed | MORE column re-spaced (gaps 5 -> 8+ px), DETONATE, TAKEDOWN and SKIP SET PIECE moved clear (gaps were -26, 6 and 5 px); the pause button moved from the top bar to the right edge under the heat stars (the faction / wanted plate sat on it). Test: every context keeps a gap of 4+ px and 64 px targets. |
| 4 | Banner pile, leftover QUANTUM CORES line | fixed | While the campaign runs the core counter is not drawn (play HUD and the pause head: `NOW  <step>` or `CONTINUE THE STORY`), and the faded chapter banner no longer draws under the step line. |
| 11 | Map: 600 icons | fixed | Overview (zoom < 2) shows the objective, side jobs and homes, plus the nearest 3 of INTERIORS / SHOPS / GARAGE / ITEMS / WEAPONS and the nearest 8 JOBS (807 candidate markers -> 23); zoomed in shows all; the crowded legend chips lost their counts. |
| 12 | Menus | partly | Loadout part names are 18 px (fitted) instead of 14 px captions. The MORE grid, the 20 option buttons and the TEST tag (debug builds only) are unchanged: still a gap. |
| 13 | Flat fight | partly | Enemy READABILITY only (dark armour vs the hero's light jacket); cover behaviour is gameplay. |
| 15 | LOW haze / white planes | partly | Mission beam hides within 22 m (was 16 m) so the cyan column no longer washes the street. The LOW magenta haze and interior wall lights were not reproduced in these frames and are untouched. |
| 7, 5, 6, 8, 9, 10, 14 | gameplay half | not mine | see `test_director_fixes_a.gd`. |

Not done / open: audio (not judged headless), a real clothed hero mesh, MORE / OPTIONS redesign (tiles with icons, fewer buttons), driving HUD widgets, a real-phone check. No perf gate run for the shader change (one material, no new draws; the frames show 77-96 draws at LOW).
