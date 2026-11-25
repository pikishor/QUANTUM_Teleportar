GOAL: w122-shops see-through windows, 6 walk-in shop kinds, BUY on the context slot, map icons, roof parapets, tests/test_shops_w122.gd
DONE:
- godot/scripts/world/shop_fronts.gd (ShopFronts): walk-in shops built in place within 15 m (closed past 22 m): room mesh (unshaded, one draw), glass front (transparent, light reflection), Label3D sign, shopkeeper (InteriorCivilian vendor), colliders = the building's boxes minus the room + glass panes + counter; door spot moved clear of street props (_free_door)
- kinds: food (bodega), clothes (new vendor type), guns (weapons), motors (new), electronics (tech), pharmacy (clinic); doors of bodega/weapons/tech/clinic keep their kind, warehouse/cargo/lab/server/control/med/teleporter doors become clothes or motors; never on tower lots (block >= 12 m: TowerFloors / w122-rooms)
- facade: building_core.gdshaderinc uniforms shop_hide (collapses that one instance), SHOP_CUT variant (assets/shaders/building_shop.gdshader, building_far_shop.gdshader: discard only in the one copy), near_rooms (LOW/LOW+ room parallax within 45 m)
- interior_data.gd: vendor types clothes (look rows: suits, schemes) and motors (ride rows: scooter, bike, compact, muscle, sport); vendor_logic.gd kinds look (buy_look + wear) and ride (ShopFronts.deliver: spawn_parked at the kerb, meta called)
- hooks: main.gd add_child x2; city.gd is_inside_building + near_rooms; touch_controls.gd _use_near + _label_of BUY; map_screen.gd shop kind/label/no fog; interior_gameplay.gd nearest_door skips walk_in; atmosphere.gd no rain / lens rain in a shop; camera_rig.gd _indoor in a shop
- godot/scripts/world/roof_parapets.gd (RoofParapets): 0.9 m colliders + dark coping mesh on roof edges within 45 m while the hero is above 5 m
- tests/test_shops_w122.gd (fingers, 844x390 + 2400x1080), tests/bot_w122_shops.gd (frames: W122_OUT, W122_LP=1 LOW+, W122_SHOPS=kinds, W122_ONLY_WIN=1)
- frames docs/shots/round7/shops_w122/*.jpg
NEXT: done (report sent)
DECISIONS:
- env switch W122_SHOPS_OLD=1 (w122-rooms uses W122_OLD). ShopFronts.enabled / RoofParapets.enabled read it at load.
TESTS AND PERF:
- test_shops_w122: PASS 54 checks both screens; W122_SHOPS_OLD=1: 11 of 15 FAIL at 844x390 (every [old fails] check)
- perf (PERF_CHECK=1, no limit touched): LOW draws=72 total=94 death=109 OK; MED draws=101 total=133 death=148 OK; HIGH draws=112 total=147 death=170 OK
OPEN PROBLEMS:
- tower floor windows (w122-rooms' TowerFloors) have no glass pane yet; shops' glass reflects
- a street planter/fountain without collider can still stand before a shop door (motors at (-60,-102))
