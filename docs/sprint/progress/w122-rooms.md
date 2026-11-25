GOAL: w122-rooms rooms that match the outside + furniture; w121 leftovers (stairwell holes, MED lobby rain, gun at fade, foes/NPCs on floors); test_rooms_w122.
PROBE (godot/tests/dev_w122_probe.gd, real fingers, old code):
- towers (office lot 77 26x26, apartment lot 44 18x18): walk-in, inside = outside footprint, 6 floors on facade lines; 28 stairwell window holes onto the street; 0 people inside; rooms = flat vertex-colour boxes.
- city house lot 8 (26x26x16): USE door -> teleport to a 14.2 x 6.7 m room far away (no match). Only 40 core towers h>=24 walk-in.
- outskirts house: USE by finger found no slot at the town door (not followed up); airport hangars: solid, no door; army yard: no building to enter.
DONE:
- tower_floors.gd: rooms_on (W122_OLD=1 off): every city block lot h>=12 any district walk-in (968: house 375 / office 210 / apartment 269 / hotel 114), kind house for h<24;
  furniture by kind (_room_boxes_w122: desks+chairs+screens, meeting, bedrooms, living, kitchens, storage shelves, lobby desk/plants/mail, house hall in line with the door), tags in b[9];
  stairwell windows closed; surface classes in UV.x -> shader tiles/plaster/ceiling panels; people: 3 InteriorCivilian on hero floor, 2 operatives on top floor of 40% of towers.
  nearest(p, min_h := MIN_H, kind) keeps the old meaning for old tests.
- atmosphere.gd _air_step: lens rain 0 when camera or hero inside a tower (rooms_on).
- player_body.gd: gun_fade_on + GUN_HIDE 0.35: all meshes on the muzzle taken out of layers while faded.
- tests/test_rooms_w122.gd (new).
- new lots without a clear door spot skipped (critic_w121 prop check); actor pool made in _ready (floors_w121 leak check); office/house palette darker (MED pale).
- frames: tests/bot_w122_rooms.gd, docs/shots/round7/rooms_w122/sheet_low.jpg, sheet_med.jpg, sheet_med2.jpg (1200x540), looked at.
STATUS: done, report handed back.
DECISIONS: TowerFloors.rooms_on, HOUSE_MIN_H 12, FOE_CHANCE 0.4, ACTOR_MAX 3, people(); PlayerBody.gun_fade_on, GUN_HIDE.
TESTS AND PERF: test_rooms_w122 PASS 20/20; W122_OLD=1 14 FAIL. floors_w121, critic_w121, lifts_w121 PASS. perf (2nd run): LOW draws=72 death=109 OK; MED 101 / 148 OK; HIGH 112 / 170 OK.
OPEN PROBLEMS: USE-door rooms (InteriorGameplay) still do not match the outside; airport/army not enterable.
