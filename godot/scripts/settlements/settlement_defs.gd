class_name SettlementDefs
extends RefCounted
## The seven towns of the outskirts (wave 112: "the outskirts are blank, even the houses"). Pure data in the format of OutskirtsSites.DEFS (they are appended there as sites of kind &"town", so the pad carve,
## the vegetation / wildlife / alien keep-out, the map pins, the compass, the mission hooks and the discovery reward all know them). The layout inside the pad (streets, lots, houses, shops, parked cars,
## doors, anchors, people) is generated from `style` and the id by SettlementPlan; the meshes are SettlementKit, the live nodes SettlementWorld.
##
## A town stands ON a road of SettlementRoads / TerrainRoads (`on_road`): the road is its main street, the pad is an ellipse (`r` metres across, `len` along the street) flat at the pad height, the road
## profile inside it is levelled to the same height, `pos` is snapped onto the road and `yaw` follows its direction (local +Z = along the street). Keys: id, name, kind &"town", style, pos, on_road, r, len,
## blend, reward, tag, houses (target number of houses; 20 to 80), optional `y` (pad height) and `seed`.
##   farm        HARROW FIELD       farming village on the plains north-east of the city: barns, silos, a windmill, fields, orchards, a church with a bell tower
##   industrial  IRON HOLLOW        mining and processing town at the foot of the east range: sheds, silos, a chimney stack, a crane, conveyors, a tank farm, worker rows
##   suburb      BAYVIEW ESTATES    suburban estates between the city and the sea: cul-de-sacs, lawns, garages, driveways with cars, a shopping parade, a petrol station
##   harbour     SALT QUAY          fishing town on the west coast: narrow painted houses, a pier, boats, nets, a fish market, a lighthouse
##   resort      SUNSET COVE        beach resort on the south-west shore: a hotel with a roof helipad, white villas, palm trees, a pool, a marina
##   lodge       HIGH LARK          mountain lodge hamlet on the north-west plateau: log chalets, a lodge hall with a helipad, a chapel, a ski-lift style mast
##   outpost     MIRAGE POINT       desert outpost: adobe and container houses, a radio mast, a solar field, a water tower, a fuel stop

const DEFS: Array[Dictionary] = [
	{"id": &"harrow_field", "name": "HARROW FIELD", "kind": &"town", "style": &"farm", "pos": Vector2(1460, -1120), "on_road": "RING ROAD", "r": 100.0, "len": 160.0, "blend": 48.0, "reward": 300,
		"tag": "FARMING VILLAGE", "houses": 26},
	{"id": &"iron_hollow", "name": "IRON HOLLOW", "kind": &"town", "style": &"industrial", "pos": Vector2(1470, -470), "on_road": "RING ROAD", "r": 105.0, "len": 170.0, "blend": 48.0, "reward": 350,
		"tag": "MINING AND WORKS TOWN", "houses": 30},
	{"id": &"bayview", "name": "BAYVIEW ESTATES", "kind": &"town", "style": &"suburb", "pos": Vector2(-700, 1373), "on_road": "COAST ROAD", "r": 105.0, "len": 175.0, "blend": 44.0, "reward": 300,
		"tag": "SUBURBAN ESTATES", "houses": 64},
	{"id": &"salt_quay", "name": "SALT QUAY", "kind": &"town", "style": &"harbour", "pos": Vector2(-2930, -470), "on_road": "WEST HIGHWAY", "r": 95.0, "len": 150.0, "blend": 46.0, "reward": 350,
		"tag": "FISHING TOWN", "houses": 44},
	{"id": &"sunset_cove", "name": "SUNSET COVE", "kind": &"town", "style": &"resort", "pos": Vector2(-2660, 295), "on_road": "WEST COAST ROAD", "r": 100.0, "len": 150.0, "blend": 62.0, "reward": 400,
		"tag": "BEACH RESORT", "houses": 34},
	{"id": &"high_lark", "name": "HIGH LARK", "kind": &"town", "style": &"lodge", "pos": Vector2(-2560, -1780), "on_road": "LARK ROAD", "r": 80.0, "len": 120.0, "blend": 110.0, "reward": 300,
		"tag": "MOUNTAIN LODGE HAMLET", "houses": 22},
	{"id": &"mirage_point", "name": "MIRAGE POINT", "kind": &"town", "style": &"outpost", "pos": Vector2(1555, 1262), "on_road": "OUTPOST ROAD", "r": 85.0, "len": 130.0, "blend": 40.0, "reward": 300,
		"tag": "DESERT OUTPOST", "houses": 24},
]


## Where a town stands once the roads exist: {c (the road sample nearest to `pos`), yaw (local +Z along the road there), y (pad height), road (road index), s (distance along the road)}.
## The pad height is `y` of the def or the mean of the land (OutskirtsSites.ring_mean) round the centre.
static func resolve(d: Dictionary) -> Dictionary:
	var want: Vector2 = d["pos"]
	var roads := TerrainRoads.roads()
	var ri := -1
	for i in roads.size():
		if String(roads[i]["name"]) == String(d["on_road"]):
			ri = i
			break
	if ri < 0:
		return {"c": want, "yaw": float(d.get("yaw", 0.0)), "y": OutskirtsSites.ring_mean(want, float(d["r"])), "road": -1, "s": 0.0}
	var pts: PackedVector2Array = roads[ri]["pos"]
	var best := 0
	var bd := 1.0e18
	for k in pts.size():
		var dd := pts[k].distance_squared_to(want)
		if dd < bd:
			bd = dd
			best = k
	var c := pts[best]
	var a := pts[maxi(best - 8, 0)]
	var b := pts[mini(best + 8, pts.size() - 1)]
	var dir := (b - a).normalized()
	var yaw := atan2(dir.x, dir.y)
	var s := 0.0
	for k in range(1, best + 1):
		s += pts[k].distance_to(pts[k - 1])
	var y: float = float(d["y"]) if d.has("y") else OutskirtsSites.ring_mean(c, float(d["r"]) * 0.8)
	return {"c": c, "yaw": yaw, "y": y, "road": ri, "s": s}
