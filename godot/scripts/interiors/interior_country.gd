class_name InteriorCountry
extends RefCounted
## The interiors of the outskirts (wave 112): nineteen layouts for the houses, shops, farms and halls of the towns (scripts/settlements/*). The CITY tables stay as they are (six tests pin their sixteen
## entries); the generator, the gameplay and the vendors ask these tables second, through one-line hooks in InteriorKinds (has_type / spec / ambience / guaranteed), InteriorData (title / color / names / plan /
## stock / radio / has_vendor) and InteriorGameplay.doors(). Same recipe format as InteriorKinds.SPECS, warmer and brighter than the city on purpose: daylight, wood, lamps.
##   InteriorCountry.TYPES            the nineteen type ids
##   InteriorCountry.spec(type)       the dressed spec (InteriorKinds._dress): drop-in for InteriorKinds.spec
##   InteriorCountry.STOCK_ALIAS      vendor types -> the city stock they sell (drinks, kits, rumours, upgrades)

const TYPES: Array[StringName] = [&"cottage", &"farmhouse", &"suburb_home", &"fisher_home", &"cabin_home", &"villa", &"outpost_home", &"general_store", &"cafe", &"tavern", &"petrol_shop",
	&"fish_market", &"barn", &"chapel", &"workshop", &"hotel_lobby", &"lodge_hall", &"lighthouse", &"clinic_village"]

## Vendor types and the stock of the city type they sell (InteriorData.STOCK).
const STOCK_ALIAS := {&"general_store": &"bodega", &"petrol_shop": &"bodega", &"fish_market": &"bodega", &"cafe": &"bar", &"tavern": &"bar", &"hotel_lobby": &"bar", &"lodge_hall": &"bar",
	&"workshop": &"tech", &"clinic_village": &"clinic"}

const TITLES := {
	&"cottage": "COTTAGE", &"farmhouse": "FARMHOUSE", &"suburb_home": "FAMILY HOME", &"fisher_home": "FISHER HOME", &"cabin_home": "LOG CABIN", &"villa": "BEACH VILLA", &"outpost_home": "OUTPOST HOME",
	&"general_store": "GENERAL STORE", &"cafe": "ROADSIDE CAFE", &"tavern": "VILLAGE TAVERN", &"petrol_shop": "FUEL STOP", &"fish_market": "FISH MARKET", &"barn": "BARN", &"chapel": "CHAPEL",
	&"workshop": "WORKSHOP", &"hotel_lobby": "HOTEL LOBBY", &"lodge_hall": "LODGE HALL", &"lighthouse": "LIGHTHOUSE", &"clinic_village": "VILLAGE CLINIC",
}

const COLORS := {
	&"cottage": Color(1.0, 0.78, 0.45), &"farmhouse": Color(1.0, 0.7, 0.35), &"suburb_home": Color(1.0, 0.82, 0.55), &"fisher_home": Color(0.55, 0.9, 1.0), &"cabin_home": Color(1.0, 0.62, 0.3),
	&"villa": Color(1.0, 0.7, 0.8), &"outpost_home": Color(1.0, 0.7, 0.4), &"general_store": Color(0.7, 1.0, 0.45), &"cafe": Color(1.0, 0.75, 0.35), &"tavern": Color(1.0, 0.65, 0.25),
	&"petrol_shop": Color(1.0, 0.55, 0.2), &"fish_market": Color(0.4, 0.9, 1.0), &"barn": Color(0.95, 0.85, 0.35), &"chapel": Color(0.85, 0.9, 1.0), &"workshop": Color(0.6, 0.75, 1.0),
	&"hotel_lobby": Color(1.0, 0.55, 0.85), &"lodge_hall": Color(1.0, 0.6, 0.3), &"lighthouse": Color(1.0, 0.45, 0.4), &"clinic_village": Color(0.45, 1.0, 0.65),
}

const NAME_A: Array[String] = ["OAK", "MILL", "ROSE", "HOLLOW", "HERON", "OLD ELM", "MARSH", "WILLOW", "STONE", "LARK", "IRONWOOD", "SUNSET", "BRAMBLE", "COPPER", "HARBOUR", "JUNIPER"]
const NAME_B := {
	&"cottage": ["COTTAGE", "HOUSE", "LODGE"], &"farmhouse": ["FARM", "HOMESTEAD", "GRANGE"], &"suburb_home": ["HOUSE", "RESIDENCE", "HOME"], &"fisher_home": ["COTTAGE", "ROW HOUSE", "NETHOUSE"],
	&"cabin_home": ["CABIN", "CHALET", "LODGE"], &"villa": ["VILLA", "SUITES", "BUNGALOW"], &"outpost_home": ["HOUSE", "CONTAINER", "ADOBE"],
	&"general_store": ["GENERAL STORE", "MERCANTILE", "PROVISIONS", "TRADING POST"], &"cafe": ["CAFE", "DINER", "TEA ROOM", "BAKERY"], &"tavern": ["TAVERN", "ARMS", "INN", "PUB"],
	&"petrol_shop": ["FUEL STOP", "PUMPS", "SERVICE", "GAS AND GO"], &"fish_market": ["FISH MARKET", "CATCH", "SMOKEHOUSE"], &"barn": ["BARN", "STABLE", "HAYLOFT", "GRANGE"],
	&"chapel": ["CHAPEL", "CHURCH", "MEETING HOUSE"], &"workshop": ["WORKS", "FORGE", "TOOL SHOP", "GARAGE"], &"hotel_lobby": ["HOTEL", "RESORT", "GRAND", "INN"],
	&"lodge_hall": ["LODGE", "HALL", "REFUGE", "CLUBHOUSE"], &"lighthouse": ["LIGHTHOUSE", "BEACON", "LAMP HOUSE"], &"clinic_village": ["CLINIC", "SURGERY", "INFIRMARY"],
}

## Who stands in an interior (same keys as InteriorData.PLAN): the people of the house, the shopkeeper and the customers. No guards: the outskirts are quiet.
const PLAN := {
	&"cottage": {"vendor": 0, "civilians": 3, "guards": 0}, &"farmhouse": {"vendor": 0, "civilians": 3, "guards": 0}, &"suburb_home": {"vendor": 0, "civilians": 3, "guards": 0},
	&"fisher_home": {"vendor": 0, "civilians": 2, "guards": 0}, &"cabin_home": {"vendor": 0, "civilians": 2, "guards": 0}, &"villa": {"vendor": 0, "civilians": 2, "guards": 0},
	&"outpost_home": {"vendor": 0, "civilians": 2, "guards": 0}, &"general_store": {"vendor": 1, "civilians": 2, "guards": 0}, &"cafe": {"vendor": 1, "civilians": 3, "guards": 0},
	&"tavern": {"vendor": 1, "civilians": 3, "guards": 0}, &"petrol_shop": {"vendor": 1, "civilians": 2, "guards": 0}, &"fish_market": {"vendor": 1, "civilians": 3, "guards": 0},
	&"barn": {"vendor": 0, "civilians": 2, "guards": 0}, &"chapel": {"vendor": 0, "civilians": 3, "guards": 0}, &"workshop": {"vendor": 1, "civilians": 2, "guards": 0},
	&"hotel_lobby": {"vendor": 1, "civilians": 3, "guards": 0}, &"lodge_hall": {"vendor": 1, "civilians": 3, "guards": 0}, &"lighthouse": {"vendor": 0, "civilians": 2, "guards": 0},
	&"clinic_village": {"vendor": 1, "civilians": 2, "guards": 0},
}

## Radio lines (speaker, text), at most StoryData.LINE_MAX (112) characters.
const RADIO := {
	&"cottage": [["ORACLE", "A cottage. Tea on the stove, a clock ticking. The Vael have never bothered with a house like this."], ["KESTREL", "Someone's home. Wipe your boots."]],
	&"farmhouse": [["ORACLE", "A farmhouse. Honest bread, a tin of coffee and a family who sleeps with the door unlocked."], ["KESTREL", "Quiet in a way the city forgot."]],
	&"suburb_home": [["ORACLE", "A family home. Toys on the rug, a games console and a very worried cat."], ["KESTREL", "Garage, lawn and a fence. Almost a normal life."]],
	&"fisher_home": [["ORACLE", "A fisher's row house. Nets on the hooks, the sea in the walls."], ["KESTREL", "Smells of salt and diesel. I like it."]],
	&"cabin_home": [["ORACLE", "A log cabin. Wood stove, bunk beds, a rifle over the door for the wolves."], ["KESTREL", "Warm in here. The cold is outside for once."]],
	&"villa": [["ORACLE", "A beach villa. Marble floors, linen and nobody who has ever heard of the Vael."], ["KESTREL", "I could get used to this view."]],
	&"outpost_home": [["ORACLE", "An outpost home. Sand outside, shade inside, water counted in cups."], ["KESTREL", "Hot, still and honest."]],
	&"general_store": [["ORACLE", "The general store. Everything the village needs and a bell on the door."], ["KESTREL", "Shelves of tins. I could live on this."]],
	&"cafe": [["ORACLE", "A roadside cafe. Hot coffee, cold news. Buy a rumour with the pie."], ["KESTREL", "Truckers talk. Listen."]],
	&"tavern": [["ORACLE", "The village tavern. Everything that happens within ten miles is said here first."], ["KESTREL", "Low beams, loud laughter. Mind your head."]],
	&"petrol_shop": [["ORACLE", "A fuel stop. Maps, snacks and a clerk who watches the road."], ["KESTREL", "Every road ends at a pump. Top up."]],
	&"fish_market": [["ORACLE", "The fish market. Ice, salt and the freshest news on the coast."], ["KESTREL", "Gulls outside, gossip inside."]],
	&"barn": [["ORACLE", "A barn. Hay, harness and a tractor that has seen better decades."], ["KESTREL", "Smells like summer. Watch the loft."]],
	&"chapel": [["ORACLE", "A chapel. Candle smoke, creaking pews. Even the drones keep their distance."], ["KESTREL", "I do not pray. I will sit a minute."]],
	&"workshop": [["ORACLE", "A workshop. Lathes, cable and enough scrap to build a second Rift gun."], ["KESTREL", "Sparks and oil. Home."]],
	&"hotel_lobby": [["ORACLE", "A resort lobby. Sea breeze, cold drinks and guests who tip in rumours."], ["KESTREL", "Marble and palms. Do not touch the minibar."]],
	&"lodge_hall": [["ORACLE", "The lodge hall. A fire, a long table and hikers swapping trail news."], ["KESTREL", "Stew smell. I am staying for dinner."]],
	&"lighthouse": [["ORACLE", "The lighthouse. One keeper, one lamp, forty miles of dark water."], ["KESTREL", "Quiet up here. The sea does the talking."]],
	&"clinic_village": [["ORACLE", "A village clinic. One nurse, one bed and a very good first aid kit."], ["KESTREL", "She will patch you for the price of a tea."]],
}

const AMBIENCE := {
	&"cottage": {"dedicated": &"interior_apartment", "loops": [[&"rain_awning", -22.0], [&"drone_hum", -34.0]], "oneshots": [[&"animal_bird", 14.0, 30.0, -28.0]], "muffle": 0.8},
	&"farmhouse": {"dedicated": &"interior_apartment", "loops": [[&"rain_awning", -22.0], [&"drone_hum", -34.0]], "oneshots": [[&"animal_cow", 18.0, 40.0, -30.0], [&"animal_bird", 14.0, 30.0, -28.0]], "muffle": 0.8},
	&"suburb_home": {"dedicated": &"interior_apartment", "loops": [[&"rain_awning", -22.0], [&"city_hum", -32.0]], "oneshots": [[&"radio_static", 20.0, 40.0, -30.0]], "muffle": 0.85},
	&"fisher_home": {"dedicated": &"interior_apartment", "loops": [[&"rain_awning", -20.0], [&"drone_hum", -34.0]], "oneshots": [[&"animal_gull", 10.0, 24.0, -26.0]], "muffle": 0.75},
	&"cabin_home": {"dedicated": &"interior_apartment", "loops": [[&"rain_awning", -20.0], [&"drone_hum", -34.0]], "oneshots": [[&"animal_wolf", 25.0, 55.0, -32.0], [&"animal_bird", 12.0, 28.0, -28.0]], "muffle": 0.85},
	&"villa": {"dedicated": &"interior_lobby", "loops": [[&"city_hum", -30.0], [&"rain_awning", -26.0]], "oneshots": [[&"animal_gull", 12.0, 28.0, -28.0]], "muffle": 0.85},
	&"outpost_home": {"dedicated": &"interior_apartment", "loops": [[&"drone_hum", -30.0], [&"rain_awning", -26.0]], "oneshots": [[&"animal_coyote", 25.0, 55.0, -32.0]], "muffle": 0.7},
	&"general_store": {"dedicated": &"interior_bodega", "loops": [[&"drone_hum", -26.0], [&"rain_awning", -26.0]], "oneshots": [[&"babble", 15.0, 30.0, -28.0], [&"ui_tick", 20.0, 40.0, -28.0]], "muffle": 0.8},
	&"cafe": {"dedicated": &"interior_bar", "loops": [[&"babble", -24.0], [&"rain_awning", -28.0], [&"drone_hum", -32.0]], "oneshots": [[&"impact_glass", 12.0, 28.0, -28.0]], "muffle": 0.75},
	&"tavern": {"dedicated": &"interior_bar", "loops": [[&"babble", -18.0], [&"rain_awning", -28.0], [&"drone_hum", -32.0]], "oneshots": [[&"impact_glass", 8.0, 18.0, -24.0]], "muffle": 0.8},
	&"petrol_shop": {"dedicated": &"interior_bodega", "loops": [[&"drone_hum", -22.0], [&"rain_awning", -26.0]], "oneshots": [[&"radio_static", 14.0, 30.0, -28.0], [&"car_door", 20.0, 40.0, -30.0]], "muffle": 0.8},
	&"fish_market": {"dedicated": &"interior_bodega", "loops": [[&"babble", -24.0], [&"rain_awning", -24.0]], "oneshots": [[&"animal_gull", 6.0, 16.0, -24.0]], "muffle": 0.65},
	&"barn": {"dedicated": &"interior_warehouse", "loops": [[&"rain_metal", -22.0], [&"drone_hum", -36.0]], "oneshots": [[&"animal_cow", 8.0, 22.0, -26.0], [&"animal_horse", 14.0, 34.0, -28.0], [&"animal_sheep", 14.0, 34.0, -28.0]], "muffle": 0.55},
	&"chapel": {"dedicated": &"interior_lobby", "loops": [[&"drone_hum", -34.0], [&"rain_awning", -28.0]], "oneshots": [[&"animal_bird", 16.0, 34.0, -30.0]], "muffle": 0.92},
	&"workshop": {"dedicated": &"interior_tech", "loops": [[&"drone_hum", -22.0], [&"rain_metal", -26.0]], "oneshots": [[&"impact_metal", 5.0, 12.0, -22.0]], "muffle": 0.7},
	&"hotel_lobby": {"dedicated": &"interior_lobby", "loops": [[&"city_hum", -28.0], [&"babble", -28.0]], "oneshots": [[&"ui_tick", 18.0, 40.0, -28.0]], "muffle": 0.85},
	&"lodge_hall": {"dedicated": &"interior_bar", "loops": [[&"babble", -22.0], [&"rain_awning", -26.0], [&"drone_hum", -34.0]], "oneshots": [[&"animal_wolf", 30.0, 60.0, -34.0]], "muffle": 0.85},
	&"lighthouse": {"dedicated": &"interior_apartment", "loops": [[&"rain_awning", -18.0], [&"drone_hum", -34.0]], "oneshots": [[&"animal_gull", 8.0, 20.0, -24.0], [&"distant_boom", 30.0, 60.0, -30.0]], "muffle": 0.8},
	&"clinic_village": {"dedicated": &"interior_clinic", "loops": [[&"drone_hum", -26.0], [&"rain_awning", -30.0]], "oneshots": [[&"heartbeat", 14.0, 28.0, -28.0]], "muffle": 0.85},
}

static var _specs := {}
static var _dressed := {}


static func has_type(type: StringName) -> bool:
	return TYPES.has(type)


static func has_vendor(type: StringName) -> bool:
	return STOCK_ALIAS.has(type)


## The anchors every country type guarantees (InteriorKinds.GUARANTEED format).
static func guaranteed(type: StringName) -> Dictionary:
	var need := {&"civilian": 3}
	if has_vendor(type):
		need[&"vendor"] = 1
	return need


static func door_name(type: StringName, id: int) -> String:
	var b: Array = NAME_B.get(type, ["HOUSE"])
	var h := fposmod(sin(float(id) * 12.9898 + 4.1) * 43758.5453, 1.0)
	var h2 := fposmod(sin(float(id) * 78.233 + 1.7) * 43758.5453, 1.0)
	return "%s %s" % [NAME_A[int(h * NAME_A.size()) % NAME_A.size()], str(b[int(h2 * b.size()) % b.size()])]


static func spec(type: StringName) -> Dictionary:
	if not _dressed.has(type):
		var all := specs()
		_dressed[type] = InteriorKinds._dress(all.get(type, all[&"cottage"]))
	return _dressed[type]


static func specs() -> Dictionary:
	if _specs.is_empty():
		_specs = _build()
	return _specs


# --- the layouts -----------------------------------------------------------------------------------------------------------------------------------

static func _pal(wall: Color, wall2: Color, floor_c: Color, ceil_c: Color, trim: Color, neon: Array, key: Color, amb: Color) -> Dictionary:
	return {"wall": wall, "wall2": wall2, "floor": floor_c, "ceil": ceil_c, "trim": trim, "neon": neon, "key": key, "amb": amb}


const LAMPS := [Color(1.0, 0.78, 0.45), Color(1.0, 0.62, 0.3), Color(1.0, 0.9, 0.7)]
const COOL := [Color(0.5, 0.85, 1.0), Color(1.0, 0.85, 0.55), Color(0.8, 1.0, 0.9)]


static func _build() -> Dictionary:
	var s := {}
	var home_living := ["wall", "couch", 1, 1, "back"]
	# --- homes ---
	s[&"cottage"] = {"name": "COTTAGE", "ceil": [2.7, 3.0], "windows": 0.9, "hostile": false, "style": 0, "styles": {"kitchen": 1}, "fstyle": 2, "fstyles": {"kitchen": 1},
		"pal": _pal(Color(0.50, 0.42, 0.33), Color(0.40, 0.32, 0.25), Color(0.34, 0.22, 0.13), Color(0.46, 0.42, 0.36), Color(0.55, 0.40, 0.26), LAMPS, Color(1.0, 0.88, 0.68), Color(0.2, 0.17, 0.14)),
		"rooms": [
			{"role": "living", "w": [5.2, 6.4], "d": [4.6, 5.4], "prog": [home_living, ["wall", "tv_unit", 1, 1, "left"], ["wall", "bookcase", 1, 2, "right"], ["free", "armchair", 1, 1], ["free", "plant", 1, 2],
				["free", "lamp_floor", 1, 2], ["wm", "poster", 1, 2, "any"], ["detail", "rug", 1, 1], ["detail", "coffee_table", 1, 1], ["detail", "coat_rack", 1, 1], ["anchor", "civilian", 2, 3]]},
			{"role": "kitchen", "w": [3.6, 4.4], "d": [3.4, 4.2], "prog": [["wall", "kitchen_run", 1, 1, "back"], ["wall", "fridge_home", 1, 1, "left"], ["free", "table", 1, 1], ["detail", "chair", 2, 3], ["detail", "bin", 1, 1], ["anchor", "civilian", 1, 1]]},
			{"role": "bedroom", "w": [3.8, 4.6], "d": [3.8, 4.6], "prog": [["wall", "bed", 1, 1, "back"], ["wall", "side_table", 1, 2, "any"], ["wall", "locker", 1, 1, "right"], ["wall", "bookcase", 1, 1, "any"], ["anchor", "civilian", 1, 1]]},
		]}
	s[&"farmhouse"] = {"name": "FARMHOUSE", "ceil": [2.8, 3.2], "windows": 0.8, "hostile": false, "style": 0, "styles": {"pantry": 2}, "fstyle": 2, "fstyles": {"pantry": 3},
		"pal": _pal(Color(0.52, 0.44, 0.32), Color(0.36, 0.28, 0.2), Color(0.32, 0.2, 0.12), Color(0.42, 0.36, 0.3), Color(0.5, 0.34, 0.2), LAMPS, Color(1.0, 0.86, 0.62), Color(0.19, 0.16, 0.13)),
		"rooms": [
			{"role": "kitchen", "w": [6.8, 8.4], "d": [5.4, 6.8], "prog": [["wall", "kitchen_run", 1, 1, "back"], ["wall", "fridge_home", 1, 1, "left"], ["sets", "table", "chair", 1, 1, 4], ["wall", "bookcase", 1, 1, "right"],
				["free", "armchair", 1, 1], ["free", "plant", 1, 1], ["wm", "poster", 1, 2, "any"], ["detail", "rug", 1, 1], ["detail", "coat_rack", 1, 1], ["detail", "bin", 1, 1], ["anchor", "civilian", 2, 3]]},
			{"role": "pantry", "w": [3.2, 4.0], "d": [3.2, 4.0], "prog": [["aisles", "shelf", 1, 2], ["free", "barrel", 1, 2], ["free", "crate", 1, 2], ["free", "box_pile", 1, 1], ["anchor", "civilian", 1, 1]]},
			{"role": "bedroom", "w": [4.0, 5.0], "d": [4.0, 5.0], "prog": [["wall", "bed", 1, 1, "back"], ["wall", "side_table", 1, 2, "any"], ["wall", "locker", 1, 2, "right"], ["free", "desk", 1, 1], ["anchor", "civilian", 1, 1]]},
		]}
	s[&"suburb_home"] = {"name": "FAMILY HOME", "ceil": [2.7, 3.0], "windows": 1.0, "hostile": false, "style": 0, "styles": {"kitchen": 1, "garage": 2}, "fstyle": 2, "fstyles": {"kitchen": 1, "garage": 3},
		"pal": _pal(Color(0.58, 0.55, 0.5), Color(0.44, 0.48, 0.5), Color(0.36, 0.27, 0.18), Color(0.55, 0.54, 0.5), Color(0.62, 0.6, 0.55), COOL, Color(1.0, 0.95, 0.85), Color(0.23, 0.22, 0.2)),
		"rooms": [
			{"role": "living", "w": [6.0, 7.6], "d": [5.0, 6.2], "prog": [["wall", "couch", 1, 1, "back"], ["wall", "tv_unit", 1, 1, "left"], ["wall", "bookcase", 1, 2, "right"], ["free", "armchair", 1, 2], ["free", "plant", 1, 2],
				["free", "lamp_floor", 1, 2], ["wm", "poster", 1, 3, "any"], ["detail", "rug", 1, 1], ["detail", "coffee_table", 1, 1], ["detail", "coat_rack", 1, 1], ["anchor", "civilian", 2, 3]]},
			{"role": "kitchen", "w": [4.0, 5.0], "d": [3.6, 4.4], "prog": [["wall", "kitchen_run", 1, 1, "back"], ["wall", "fridge_home", 1, 1, "left"], ["free", "table", 1, 1], ["detail", "chair", 2, 3], ["detail", "bin", 1, 1], ["anchor", "civilian", 1, 1]]},
			{"role": "bedroom", "w": [4.0, 5.0], "d": [4.0, 5.0], "prog": [["wall", "bed", 1, 1, "back"], ["wall", "side_table", 1, 2, "any"], ["wall", "locker", 1, 2, "right"], ["free", "desk", 1, 1], ["wall", "bookcase", 1, 1, "any"], ["anchor", "civilian", 1, 1]]},
			{"role": "garage", "w": [4.6, 5.6], "d": [4.6, 5.6], "prog": [["wall", "workbench", 1, 1, "back"], ["free", "crate", 1, 2], ["free", "box_pile", 1, 1], ["free", "barrel", 1, 1], ["wall", "cabinet", 1, 1, "left"], ["anchor", "civilian", 1, 1]]},
		]}
	s[&"fisher_home"] = {"name": "FISHER HOME", "ceil": [2.6, 2.9], "windows": 0.8, "hostile": false, "style": 0, "styles": {"kitchen": 1}, "fstyle": 2, "fstyles": {"kitchen": 1},
		"pal": _pal(Color(0.34, 0.5, 0.58), Color(0.5, 0.45, 0.36), Color(0.3, 0.2, 0.13), Color(0.5, 0.5, 0.46), Color(0.7, 0.66, 0.55), COOL, Color(0.95, 0.95, 0.85), Color(0.2, 0.2, 0.19)),
		"rooms": [
			{"role": "living", "w": [4.4, 5.2], "d": [5.8, 6.8], "prog": [["wall", "kitchen_run", 1, 1, "back"], ["free", "table", 1, 1], ["detail", "chair", 2, 3], ["wall", "bookcase", 1, 1, "left"], ["wall", "fridge_home", 1, 1, "right"],
				["free", "barrel", 1, 2], ["detail", "coat_rack", 1, 2], ["wm", "poster", 1, 2, "any"], ["detail", "rug", 1, 1], ["detail", "bin", 1, 1], ["anchor", "civilian", 2, 3]]},
			{"role": "bedroom", "w": [3.6, 4.4], "d": [3.6, 4.4], "prog": [["wall", "bed", 1, 1, "back"], ["wall", "locker", 1, 1, "left"], ["wall", "side_table", 1, 1, "right"], ["free", "crate", 1, 1], ["anchor", "civilian", 1, 1]]},
		]}
	s[&"cabin_home"] = {"name": "LOG CABIN", "ceil": [2.9, 3.4], "windows": 0.6, "hostile": false, "style": 0, "fstyle": 2,
		"pal": _pal(Color(0.5, 0.33, 0.2), Color(0.4, 0.26, 0.16), Color(0.3, 0.19, 0.11), Color(0.36, 0.26, 0.18), Color(0.55, 0.38, 0.22), LAMPS, Color(1.0, 0.8, 0.52), Color(0.19, 0.15, 0.11)),
		"rooms": [
			{"role": "main", "w": [7.0, 8.6], "d": [5.8, 7.0], "prog": [["wall", "kitchen_run", 1, 1, "back"], ["wall", "bunk", 1, 2, "left"], ["wall", "couch", 1, 1, "right"], ["free", "armchair", 1, 1], ["sets", "table", "chair", 1, 1, 3],
				["wall", "bookcase", 1, 1, "any"], ["free", "barrel", 1, 1], ["wm", "poster", 1, 2, "any"], ["detail", "rug", 1, 2], ["detail", "coat_rack", 1, 1], ["detail", "bin", 1, 1], ["anchor", "civilian", 2, 3]]},
			{"role": "store", "w": [3.2, 4.0], "d": [3.2, 4.0], "prog": [["free", "crate_stack", 1, 1], ["free", "barrel", 1, 2], ["wall", "locker", 1, 1, "back"], ["anchor", "civilian", 1, 1]]},
		]}
	s[&"villa"] = {"name": "BEACH VILLA", "ceil": [3.0, 3.4], "windows": 1.0, "hostile": false, "style": 0, "fstyle": 0, "fstyles": {"bedroom": 2},
		"pal": _pal(Color(0.7, 0.68, 0.62), Color(0.5, 0.62, 0.66), Color(0.55, 0.5, 0.42), Color(0.7, 0.7, 0.67), Color(0.35, 0.6, 0.65), COOL, Color(1.0, 0.97, 0.88), Color(0.28, 0.27, 0.25)),
		"rooms": [
			{"role": "living", "w": [7.6, 9.4], "d": [6.0, 7.4], "prog": [["wall", "couch", 1, 2, "back"], ["wall", "tv_unit", 1, 1, "left"], ["free", "armchair", 1, 2], ["free", "plant", 2, 3], ["free", "lamp_floor", 1, 2],
				["wm", "poster", 2, 3, "any"], ["detail", "rug", 1, 2], ["detail", "coffee_table", 1, 1], ["hang", 2], ["anchor", "civilian", 2, 3]]},
			{"role": "kitchen", "w": [4.4, 5.4], "d": [3.8, 4.6], "prog": [["wall", "kitchen_run", 1, 1, "back"], ["wall", "fridge_home", 1, 1, "left"], ["free", "table", 1, 1], ["detail", "chair", 2, 3], ["anchor", "civilian", 1, 1]]},
			{"role": "bedroom", "w": [5.0, 6.0], "d": [4.4, 5.4], "prog": [["wall", "bed", 1, 1, "back"], ["wall", "side_table", 1, 2, "any"], ["wall", "wash_station", 1, 1, "right"], ["free", "plant", 1, 1], ["wm", "poster", 1, 1, "any"], ["anchor", "civilian", 1, 1]]},
		]}
	s[&"outpost_home"] = {"name": "OUTPOST HOME", "ceil": [2.6, 2.9], "windows": 0.6, "hostile": false, "style": 0, "styles": {"store": 2}, "fstyle": 3, "fstyles": {"store": 3},
		"pal": _pal(Color(0.62, 0.48, 0.34), Color(0.52, 0.36, 0.26), Color(0.46, 0.34, 0.24), Color(0.55, 0.47, 0.38), Color(0.62, 0.36, 0.2), LAMPS, Color(1.0, 0.86, 0.62), Color(0.24, 0.2, 0.16)),
		"rooms": [
			{"role": "living", "w": [5.0, 6.2], "d": [4.6, 5.6], "prog": [["wall", "bed", 1, 1, "back"], ["wall", "kitchen_run", 1, 1, "left"], ["free", "table", 1, 1], ["detail", "chair", 1, 2], ["wall", "locker", 1, 1, "right"],
				["free", "barrel", 1, 1], ["wm", "poster", 1, 2, "any"], ["detail", "rug", 1, 1], ["detail", "bin", 1, 1], ["anchor", "civilian", 2, 3]]},
			{"role": "store", "w": [3.0, 3.8], "d": [3.0, 3.8], "prog": [["free", "crate_stack", 1, 1], ["free", "barrel", 1, 2], ["free", "box_pile", 1, 1], ["wall", "shelf", 1, 1, "back"], ["anchor", "civilian", 1, 1]]},
		]}
	# --- shops, food and drink ---
	s[&"general_store"] = {"name": "GENERAL STORE", "ceil": [3.0, 3.3], "windows": 1.0, "hostile": false, "style": 0, "styles": {"stock": 2}, "fstyle": 2, "fstyles": {"stock": 3},
		"pal": _pal(Color(0.5, 0.44, 0.34), Color(0.36, 0.42, 0.34), Color(0.34, 0.24, 0.15), Color(0.5, 0.46, 0.4), Color(0.6, 0.42, 0.22), LAMPS, Color(1.0, 0.92, 0.75), Color(0.22, 0.2, 0.17)),
		"rooms": [
			{"role": "shop", "w": [7.0, 9.0], "d": [6.0, 8.0], "prog": [["counter", "counter"], ["aisles", "shelf", 3, 4], ["wall", "fridge", 1, 2, "right"], ["wall", "vending", 1, 1, "left"], ["free", "crate", 1, 2],
				["free", "box_pile", 1, 2], ["free", "plant", 1, 1], ["wm", "poster", 2, 4, "any"], ["detail", "bin", 1, 2], ["detail", "crate_small", 2, 5], ["anchor", "civilian", 3, 4]]},
			{"role": "stock", "w": [4.0, 5.0], "d": [4.0, 5.0], "prog": [["free", "box_pile", 2, 3], ["free", "crate", 1, 2], ["wall", "rack_tall", 1, 1, "back"], ["detail", "crate_small", 2, 4], ["anchor", "civilian", 1, 2]]},
		]}
	s[&"cafe"] = {"name": "ROADSIDE CAFE", "ceil": [2.9, 3.2], "windows": 1.0, "hostile": false, "style": 1, "styles": {"kitchen": 1}, "fstyle": 1, "fstyles": {"kitchen": 0},
		"pal": _pal(Color(0.58, 0.46, 0.36), Color(0.36, 0.5, 0.5), Color(0.36, 0.3, 0.26), Color(0.55, 0.52, 0.47), Color(0.7, 0.4, 0.28), [Color(1.0, 0.7, 0.35), Color(0.4, 0.9, 0.9), Color(1.0, 0.45, 0.4)], Color(1.0, 0.9, 0.72), Color(0.22, 0.2, 0.18)),
		"rooms": [
			{"role": "cafe", "w": [7.6, 9.4], "d": [6.0, 7.6], "prog": [["counter", "counter"], ["sets", "table_round", "stool", 3, 4, 2], ["wall", "couch", 1, 2, "right"], ["wm", "poster", 2, 3, "any"], ["free", "plant", 1, 2],
				["hang", 3], ["detail", "coat_rack", 1, 1], ["detail", "bin", 1, 2], ["anchor", "civilian", 3, 4]]},
			{"role": "kitchen", "w": [3.8, 4.6], "d": [3.6, 4.4], "prog": [["wall", "kitchen_run", 1, 1, "back"], ["wall", "fridge_home", 1, 1, "left"], ["free", "barrel", 1, 1], ["detail", "crate_small", 2, 3], ["anchor", "civilian", 1, 1]]},
		]}
	s[&"tavern"] = {"name": "VILLAGE TAVERN", "ceil": [2.9, 3.3], "windows": 0.8, "hostile": false, "style": 0, "styles": {"cellar": 3}, "fstyle": 2, "fstyles": {"cellar": 3},
		"pal": _pal(Color(0.46, 0.3, 0.2), Color(0.34, 0.22, 0.15), Color(0.28, 0.18, 0.1), Color(0.34, 0.27, 0.2), Color(0.55, 0.36, 0.2), [Color(1.0, 0.62, 0.28), Color(1.0, 0.8, 0.4), Color(1.0, 0.4, 0.25)], Color(1.0, 0.78, 0.5), Color(0.18, 0.14, 0.1)),
		"rooms": [
			{"role": "bar", "w": [8.2, 10.2], "d": [6.4, 8.0], "prog": [["counter", "bar"], ["sets", "table_round", "stool", 3, 5, 2], ["wall", "couch", 1, 2, "right"], ["wm", "poster", 2, 3, "any"], ["free", "barrel", 1, 2],
				["hang", 4], ["wm", "screen", 1, 1, "left"], ["detail", "coat_rack", 1, 1], ["detail", "bin", 1, 2], ["anchor", "civilian", 4, 5]]},
			{"role": "cellar", "w": [4.4, 5.6], "d": [4.0, 5.0], "prog": [["free", "barrel", 3, 5], ["free", "crate_stack", 1, 2], ["free", "box_pile", 1, 2], ["wall", "rack_tall", 1, 1, "back"], ["pipes", 1], ["anchor", "civilian", 1, 2]]},
		]}
	s[&"petrol_shop"] = {"name": "FUEL STOP", "ceil": [2.9, 3.2], "windows": 1.0, "hostile": false, "style": 1, "styles": {"store": 2}, "fstyle": 1, "fstyles": {"store": 3},
		"pal": _pal(Color(0.6, 0.58, 0.52), Color(0.7, 0.4, 0.2), Color(0.44, 0.42, 0.38), Color(0.62, 0.6, 0.56), Color(0.85, 0.45, 0.15), [Color(1.0, 0.5, 0.15), Color(0.3, 0.9, 1.0), Color(1.0, 0.9, 0.3)], Color(1.0, 0.97, 0.88), Color(0.26, 0.25, 0.23)),
		"rooms": [
			{"role": "shop", "w": [6.4, 7.8], "d": [5.4, 6.6], "prog": [["counter", "counter"], ["wall", "fridge", 2, 3, "right"], ["wall", "vending", 1, 1, "left"], ["aisles", "shelf", 2, 3], ["wm", "rack", 1, 2, "back"],
				["free", "crate", 1, 1], ["wm", "poster", 2, 4, "any"], ["detail", "bin", 1, 2], ["detail", "crate_small", 2, 4], ["anchor", "civilian", 2, 3]]},
			{"role": "store", "w": [3.4, 4.2], "d": [3.4, 4.2], "prog": [["free", "box_pile", 1, 2], ["free", "barrel", 1, 2], ["wall", "rack_tall", 1, 1, "back"], ["anchor", "civilian", 1, 1]]},
		]}
	s[&"fish_market"] = {"name": "FISH MARKET", "ceil": [3.2, 3.6], "windows": 0.7, "hostile": false, "style": 1, "styles": {"cold": 2}, "fstyle": 3, "fstyles": {"cold": 1},
		"pal": _pal(Color(0.55, 0.6, 0.6), Color(0.38, 0.5, 0.55), Color(0.42, 0.44, 0.44), Color(0.55, 0.56, 0.55), Color(0.2, 0.5, 0.6), [Color(0.4, 0.9, 1.0), Color(1.0, 0.8, 0.4), Color(0.8, 1.0, 0.9)], Color(0.92, 1.0, 1.0), Color(0.24, 0.26, 0.26)),
		"rooms": [
			{"role": "market", "w": [8.6, 10.6], "d": [6.6, 8.2], "prog": [["counter", "counter"], ["free", "table", 2, 3], ["free", "crate", 2, 4], ["free", "barrel", 2, 3], ["wall", "fridge", 1, 2, "right"],
				["wm", "poster", 1, 2, "any"], ["hang", 3], ["detail", "crate_small", 3, 6], ["detail", "bin", 1, 2], ["anchor", "civilian", 3, 4]]},
			{"role": "cold", "w": [4.0, 5.0], "d": [3.6, 4.6], "prog": [["wall", "fridge", 2, 3, "back"], ["free", "crate_stack", 1, 1], ["free", "box_pile", 1, 2], ["pipes", 2], ["anchor", "civilian", 1, 1]]},
		]}
	# --- work and worship ---
	s[&"barn"] = {"name": "BARN", "ceil": [5.4, 6.4], "windows": 0.2, "hostile": false, "style": 0, "fstyle": 3,
		"pal": _pal(Color(0.5, 0.3, 0.2), Color(0.4, 0.26, 0.17), Color(0.42, 0.34, 0.2), Color(0.34, 0.26, 0.18), Color(0.55, 0.4, 0.22), [Color(1.0, 0.8, 0.45), Color(1.0, 0.7, 0.35), Color(1.0, 0.9, 0.6)], Color(1.0, 0.86, 0.6), Color(0.24, 0.2, 0.15)),
		"rooms": [
			{"role": "floor", "w": [9.0, 11.0], "d": [10.0, 12.6], "prog": [["free", "box_pile", 4, 6], ["free", "crate_stack", 1, 2], ["free", "pallet", 1, 2], ["free", "barrel", 2, 3], ["wall", "workbench", 1, 1, "back"],
				["wall", "rack_tall", 1, 2, "left"], ["hang", 4], ["detail", "crate_small", 3, 6], ["detail", "bin", 1, 1], ["anchor", "civilian", 2, 3]]},
			{"role": "tools", "w": [3.6, 4.6], "d": [3.4, 4.4], "prog": [["wall", "workbench", 1, 1, "back"], ["wall", "locker", 1, 2, "left"], ["wall", "cabinet", 1, 1, "right"], ["free", "barrel", 1, 1], ["anchor", "civilian", 1, 1]]},
		]}
	s[&"chapel"] = {"name": "CHAPEL", "ceil": [4.6, 5.4], "windows": 0.7, "hostile": false, "style": 3, "styles": {"vestry": 0}, "fstyle": 2, "fstyles": {"vestry": 2},
		"pal": _pal(Color(0.62, 0.6, 0.55), Color(0.5, 0.48, 0.44), Color(0.38, 0.26, 0.17), Color(0.6, 0.58, 0.54), Color(0.6, 0.45, 0.25), [Color(1.0, 0.85, 0.5), Color(0.8, 0.85, 1.0), Color(1.0, 0.7, 0.4)], Color(1.0, 0.92, 0.78), Color(0.24, 0.23, 0.22)),
		"rooms": [
			{"role": "nave", "w": [6.4, 7.6], "d": [9.0, 11.0], "prog": [["aisles", "couch", 2, 3], ["wall", "desk", 1, 1, "back"], ["wall", "bookcase", 1, 2, "left"], ["free", "lamp_floor", 2, 3], ["wm", "banner", 2, 3, "any"],
				["free", "plant", 1, 2], ["hang", 3], ["detail", "rug", 1, 1], ["anchor", "civilian", 3, 4]]},
			{"role": "vestry", "w": [3.4, 4.2], "d": [3.4, 4.2], "prog": [["free", "desk", 1, 1], ["wall", "cabinet", 1, 2, "any"], ["wall", "locker", 1, 1, "back"], ["wall", "bookcase", 1, 1, "any"], ["anchor", "civilian", 1, 1]]},
		]}
	s[&"workshop"] = {"name": "WORKSHOP", "ceil": [4.0, 4.8], "windows": 0.4, "hostile": false, "style": 2, "styles": {"office": 0}, "fstyle": 3, "fstyles": {"office": 2},
		"pal": _pal(Color(0.4, 0.4, 0.38), Color(0.3, 0.34, 0.38), Color(0.32, 0.31, 0.3), Color(0.38, 0.38, 0.38), Color(0.8, 0.55, 0.15), [Color(1.0, 0.7, 0.2), Color(0.4, 0.8, 1.0), Color(1.0, 0.4, 0.2)], Color(1.0, 0.9, 0.7), Color(0.22, 0.22, 0.21)),
		"rooms": [
			{"role": "shop", "w": [8.0, 10.0], "d": [6.6, 8.2], "prog": [["counter", "counter"], ["free", "workbench", 2, 3], ["wall", "rack_tall", 1, 2, "left"], ["free", "crate", 2, 3], ["free", "barrel", 1, 2],
				["pipes", 3], ["hang", 3], ["wm", "poster", 1, 2, "any"], ["detail", "crate_small", 3, 6], ["detail", "bin", 1, 2], ["anchor", "civilian", 2, 3]]},
			{"role": "office", "w": [3.6, 4.6], "d": [3.6, 4.4], "prog": [["free", "desk", 1, 1], ["wall", "cabinet", 1, 2, "any"], ["wall", "bookcase", 1, 1, "any"], ["detail", "coat_rack", 1, 1], ["anchor", "civilian", 1, 1]]},
		]}
	s[&"hotel_lobby"] = {"name": "HOTEL LOBBY", "ceil": [3.8, 4.2], "windows": 1.0, "hostile": false, "style": 0, "styles": {"suite": 0}, "fstyle": 0, "fstyles": {"suite": 2},
		"pal": _pal(Color(0.74, 0.7, 0.62), Color(0.5, 0.6, 0.64), Color(0.56, 0.5, 0.42), Color(0.74, 0.72, 0.68), Color(0.35, 0.62, 0.68), [Color(1.0, 0.6, 0.85), Color(0.4, 0.9, 1.0), Color(1.0, 0.85, 0.5)], Color(1.0, 0.96, 0.86), Color(0.3, 0.29, 0.27)),
		"rooms": [
			{"role": "lobby", "w": [9.2, 11.2], "d": [7.4, 9.0], "prog": [["counter", "bar"], ["wall", "reception", 1, 1, "right"], ["free", "couch", 2, 3], ["free", "plant", 3, 4], ["wm", "poster", 2, 3, "any"],
				["hang", 4], ["detail", "rug", 2, 3], ["detail", "bin", 1, 2], ["anchor", "civilian", 3, 5]]},
			{"role": "office", "w": [4.0, 5.0], "d": [4.0, 5.0], "prog": [["free", "desk", 1, 1], ["wall", "cabinet", 1, 2, "any"], ["wall", "bookcase", 1, 1, "any"], ["anchor", "civilian", 1, 1]]},
			{"role": "suite", "w": [5.0, 6.0], "d": [4.4, 5.4], "prog": [["wall", "bed", 1, 1, "back"], ["free", "couch", 1, 1], ["free", "plant", 1, 1], ["wall", "side_table", 1, 2, "any"], ["wm", "poster", 1, 1, "any"], ["anchor", "civilian", 1, 1]]},
		]}
	s[&"lodge_hall"] = {"name": "LODGE HALL", "ceil": [4.4, 5.2], "windows": 0.7, "hostile": false, "style": 0, "styles": {"kitchen": 1}, "fstyle": 2, "fstyles": {"kitchen": 3},
		"pal": _pal(Color(0.5, 0.34, 0.22), Color(0.38, 0.26, 0.17), Color(0.32, 0.2, 0.12), Color(0.38, 0.28, 0.2), Color(0.58, 0.4, 0.22), LAMPS, Color(1.0, 0.8, 0.52), Color(0.2, 0.16, 0.12)),
		"rooms": [
			{"role": "hall", "w": [10.0, 12.0], "d": [7.4, 9.2], "prog": [["counter", "bar"], ["sets", "table", "chair", 3, 4, 4], ["wall", "couch", 1, 2, "left"], ["wall", "bookcase_wide", 1, 1, "right"], ["free", "armchair", 1, 2],
				["wm", "poster", 2, 3, "any"], ["hang", 4], ["free", "barrel", 1, 1], ["detail", "rug", 2, 3], ["detail", "coat_rack", 1, 2], ["anchor", "civilian", 4, 5]]},
			{"role": "kitchen", "w": [4.4, 5.4], "d": [3.8, 4.6], "prog": [["wall", "kitchen_run", 1, 1, "back"], ["wall", "fridge_home", 1, 1, "left"], ["free", "table", 1, 1], ["free", "barrel", 1, 1], ["anchor", "civilian", 1, 1]]},
		]}
	s[&"lighthouse"] = {"name": "LIGHTHOUSE", "ceil": [2.8, 3.2], "windows": 0.5, "hostile": false, "style": 3, "styles": {"store": 2}, "fstyle": 2, "fstyles": {"store": 3},
		"pal": _pal(Color(0.62, 0.6, 0.56), Color(0.5, 0.5, 0.5), Color(0.34, 0.24, 0.16), Color(0.56, 0.55, 0.52), Color(0.7, 0.2, 0.18), [Color(1.0, 0.85, 0.5), Color(1.0, 0.4, 0.35), Color(0.8, 0.9, 1.0)], Color(1.0, 0.92, 0.78), Color(0.22, 0.22, 0.21)),
		"rooms": [
			{"role": "keeper", "w": [4.8, 5.8], "d": [4.8, 5.8], "prog": [["wall", "bed", 1, 1, "back"], ["wall", "kitchen_run", 1, 1, "left"], ["free", "desk", 1, 1], ["wall", "bookcase", 1, 2, "right"], ["free", "lamp_floor", 1, 1],
				["wm", "clock", 1, 1, "any"], ["wm", "poster", 1, 2, "any"], ["detail", "rug", 1, 1], ["detail", "coat_rack", 1, 1], ["anchor", "civilian", 2, 3]]},
			{"role": "store", "w": [3.2, 3.8], "d": [3.2, 3.8], "prog": [["free", "barrel", 1, 2], ["free", "crate", 1, 2], ["wall", "locker", 1, 1, "back"], ["anchor", "civilian", 1, 1]]},
		]}
	s[&"clinic_village"] = {"name": "VILLAGE CLINIC", "ceil": [2.9, 3.2], "windows": 0.9, "hostile": false, "style": 1, "styles": {"ward": 0}, "fstyle": 0, "fstyles": {"ward": 1},
		"pal": _pal(Color(0.62, 0.68, 0.66), Color(0.45, 0.6, 0.58), Color(0.5, 0.54, 0.52), Color(0.68, 0.7, 0.68), Color(0.3, 0.6, 0.5), [Color(0.4, 1.0, 0.7), Color(0.4, 0.8, 1.0), Color(1.0, 0.5, 0.5)], Color(0.95, 1.0, 0.98), Color(0.28, 0.3, 0.3)),
		"rooms": [
			{"role": "waiting", "w": [6.0, 7.4], "d": [5.0, 6.2], "prog": [["counter", "counter"], ["wall", "couch", 1, 2, "left"], ["wall", "vending", 1, 1, "right"], ["free", "plant", 1, 2], ["wall", "side_table", 1, 2, "any"],
				["wm", "poster", 1, 2, "any"], ["detail", "coat_rack", 1, 1], ["detail", "bin", 1, 2], ["anchor", "civilian", 2, 3]]},
			{"role": "exam", "w": [3.8, 4.6], "d": [3.8, 4.6], "prog": [["free", "medbed", 1, 1], ["wall", "wash_station", 1, 1, "left"], ["wall", "cabinet", 1, 2, "back"], ["detail", "bin", 1, 1], ["anchor", "civilian", 1, 1]]},
			{"role": "ward", "w": [4.4, 5.4], "d": [3.8, 4.6], "prog": [["wall", "cot", 2, 2, "back"], ["wall", "locker", 1, 1, "left"], ["wall", "side_table", 1, 1, "any"], ["anchor", "civilian", 1, 1]]},
		]}
	return s
