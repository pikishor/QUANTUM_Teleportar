GOAL: w123-life street life + w122 leftovers (door-frame wall run, CLIMB hint in shops, window glass, parapet swing test)
DONE:
- scripts/ambient/street_life.gd (class StreetLife, switch StreetLife.fix, W123_LIFE_OLD=1): bus stops table, bench table, bench sitter manager (pooled crowd slots)
- near_traffic.gd: buses stop at bus stops (_bus_allow, BUS_KIND 8, bus_at_stop()); city_props.gd fills StreetLife.bus_stops / benches
- ambient_crowd.gd: _sit flag, pin_sitter, is_sitting; prop_crowd_core.gdshaderinc: seated pose (flags bit 2), phone reading on bench
- citizen_actors.gd: no 3D actor for a sitter; ambient_city.gd: life setup/tier/reset/step hook lines
- hero_verbs.gd _wall_normal: shoulder + head rays (no wall run up a door frame); snake_traversal.gd button_shown hidden in ShopFronts.inside
- probe tests/dev_w123life_probe.gd (door-frame jumps; old code: wall run up the jamb beside the door to y 3.4, 0.45-1.0 s hang)
- bus stop waiters (StreetLife._step_waiters, crowd _sit=2) who board the bus (crowd.board)
- tests/test_life_w123.gd: new PASS 16/16; W123_LIFE_OLD=1 FAIL 9 of 16 (street kinds, benches, seat, bus stand/board/leave, door frame, shop CLIMB x2)
- tests/bot_w123_life.gd frames LOW+MED (bench with a seated person; bus stop; bus dwell + 2 boarded per print)
TESTS AND PERF: test_life_w123 PASS 16/16, OLD FAIL 9/16. PERF_CHECK LOW draws=75 total=97 death=106 OK; MED draws=98 total=130 death=144 OK; HIGH draws=116 total=152 death=163 OK
NEXT: done (report sent). Not done: glass in tower/lobby window holes; dogs, steam vents, puddles, delivery vans unloading, birds beyond existing fauna
DECISIONS: StreetLife.fix; StreetLife.bus_dwells/bus_leaves counters; crowd INSTANCE_CUSTOM.w = 4 means seated
OPEN: window glass in tower floors/lobby not started; tests/dev_w123_probe.gd belongs to w123-clutter (not mine)
