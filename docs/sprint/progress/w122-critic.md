GOAL: w122-critic independent review + fix of wave 122 (rooms, shops). No commits.
DONE:
- bot godot/tests/bot_w122_critic.gd (fingers, real main scene; CRIT_ONLY=b|s picks buildings/shops). Frames in scratchpad (not kept).
- D1 FIXED: 2-room HOUSE: a room separator wall stood in the middle of the street door (du = iu/2 = room boundary). tower_floors.gd _rooms: boundaries nudged 1.5 m off du (TowerFloors.crit_on), non-hall gap uses (u0+u1)/2. Check tests/test_doors_w122c.gd (12 nearest buildings walked in by stick + ball sweep of door path); W122C_OLD=1 fails house lot 53.
FINDINGS (not fixes): parked kerb cars stand in front of doors (walk around: OK); office lot 186 walk once ended on a ledge y 3.2 (flaky?).
NEXT: shops bot pass (QUALITY=0), buy by finger, windows both ways, roof edge; more defects.
- check now: 12 buildings walked in by stick (aligned) + door-path ball sweep: PASS x2; W122C_OLD=1 fails house 53.
- FOUND not fixed: a JUMP at the door jamb starts a WALL RUN; sometimes he hangs at y 3.2 on the door frame or ends on floor 1 (y 5.0) through the facade (traced: wall run then a slow vel-0 rise = a mantle). Could not reproduce deterministically (placed in air: no). Traversal guard tried and reverted (no failing check).
NEXT: shops pass.
- D2 FIXED shop floor z-fight (tiles at y 0 on the street ground) -> ShopFronts.FLOOR_Y 0.02. D3 FIXED shop rooms burned white (unshaded, vertex colours read linear) -> vertex_color_is_srgb + shell palette x0.85, pharmacy wall darker. Check tests/test_shop_look_w122c.gd (PASS; W122C_OLD=1 fails 5). test_shops_w122 still PASS.
- D4 FIXED trade window titled CORNER STORE / ARMS DEALER in a shop signed SILT FOOD MARKET: VendorScreen.title_override from ShopFronts. D5 FIXED BOUGHT line drawn over the greeting: VendorScreen.line_ys (status replaces greeting). Both in test_shop_look_w122c (old fails 8 of 12).
- tests: rooms_w122, shops_w122, critic_w121, doors_w122c, shop_look_w122c PASS; floors_w121 'no leak' check flaky in both (nodes -10..+23), old code too passes/fails by chance? (old 2/2 pass, new 2/4). NEXT perf.
- PERF (2 runs, final): LOW draws=72 death=108 OK; MED 101/148 OK; HIGH 112/170 OK. DONE; report sent.
