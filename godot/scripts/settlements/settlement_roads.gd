class_name SettlementRoads
extends RefCounted
## The extra road network of the 9 km world (wave 112): a RING ROAD round the north and east of the city, the WEST HIGHWAY and the COAST LINK to the new western land, the WEST COAST ROAD, the LARK ROAD
## up to the mountain hamlet and the SHORE TRACK. Pure data in the format of TerrainRoads.DEFS (it is appended there, after the nine original roads, so their indices do not move); the roads are
## routed by the same A* with the same grade limits, bridges appear wherever one crosses a river (Bridges.ensure) and RoadLanes / RoadTraffic carry cars on every one of them.
## A road starts on a parent road (`branch`: [parent name, metres from its start]) and may end on one (`end_on`, new in wave 112: the last via point is the parent's sample at that distance).
## The towns of SettlementDefs stand ON these roads (the road is the main street): the via points that name a town centre are listed here as well, 150 m of straight street either side of it.
## (This file must not reference TerrainRoads: TerrainRoads.DEFS is built from it at parse time.)

const DEFS: Array = [
	# the ring: from the desert road in the east, north through IRON HOLLOW and HARROW FIELD, then west along the foothills across the pass road to the end of the forest road
	{"name": "RING ROAD", "kind": "highway", "from_city": false, "branch": ["DESERT ROAD", 250.0], "end_on": ["FOREST ROAD", 99999.0],
		"via": [Vector2(1330, -150), Vector2(1470, -320), Vector2(1470, -470), Vector2(1470, -620), Vector2(1465, -960), Vector2(1460, -1120), Vector2(1460, -1270), Vector2(1200, -1390), Vector2(800, -1440),
			Vector2(450, -1460), Vector2(240, -1345), Vector2(-300, -1330), Vector2(-560, -1270), Vector2(-800, -1290), Vector2(-960, -1390)]},
	# west: from the forest road along the valley of the HIGHLINE RIVER to the fishing town at the coast
	{"name": "WEST HIGHWAY", "kind": "highway", "from_city": false, "branch": ["FOREST ROAD", 400.0], "slack": 1.7,
		"via": [Vector2(-1650, -270), Vector2(-2000, -330), Vector2(-2300, -480), Vector2(-2600, -500), Vector2(-2780, -480), Vector2(-2930, -480), Vector2(-3050, -475)]},
	# the end of the coast road, north to the forest road (a link) and west along the south shore to the beach resort
	{"name": "COAST LINK", "kind": "highway", "from_city": false, "branch": ["COAST ROAD", 99999.0], "end_on": ["FOREST ROAD", 300.0], "slack": 1.6,
		"via": [Vector2(-1420, -30)]},
	{"name": "WEST COAST ROAD", "kind": "highway", "from_city": false, "branch": ["COAST ROAD", 99999.0], "slack": 1.7,
		"via": [Vector2(-2000, 330), Vector2(-2450, 300), Vector2(-2660, 295), Vector2(-2780, 335)]},
	# up to the mountain hamlet on the north-west plateau
	{"name": "LARK ROAD", "kind": "track", "from_city": false, "branch": ["WEST HIGHWAY", 1500.0], "slack": 1.3,
		"via": [Vector2(-2480, -950), Vector2(-2520, -1350), Vector2(-2560, -1640), Vector2(-2560, -1780), Vector2(-2560, -1900)]},
	# the desert outpost on the plain below the pass of the desert road
	{"name": "OUTPOST ROAD", "kind": "highway", "from_city": false, "branch": ["DESERT ROAD", 1200.0], "slack": 1.3,
		"via": [Vector2(1650, 900), Vector2(1585, 1120), Vector2(1555, 1262), Vector2(1470, 1345)]},
	# along the west coast between the two towns on the shore
	{"name": "SHORE TRACK", "kind": "track", "from_city": false, "branch": ["WEST COAST ROAD", 1000.0], "end_on": ["WEST HIGHWAY", 99999.0], "slack": 1.3,
		"via": [Vector2(-2640, 150), Vector2(-2780, 20), Vector2(-2860, -250)]},
]
