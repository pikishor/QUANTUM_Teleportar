class_name InteriorKinds
extends RefCounted
## Data of the interior types: palette, room recipes, prop programs, ambience hooks. Pure data (no nodes), read by InteriorPlan.
##
## A room recipe is {role, w:[min,max], d:[min,max], h:[min,max] (optional), prog:[steps]}; the FIRST room is the street room (front wall = +Z, the door and the shop windows).
## Program steps (arrays, first element is the op):
##   ["counter", kind]                  counter facing the entrance in the back zone with a gap at one end; vendor anchor behind it; "bar" kind adds a back-bar and stools
##   ["wall", kind, n0, n1, side]       n props in a row against a wall ("back", "left", "right", "front", "any"), facing the room
##   ["free", kind, n0, n1]             props at free spots, random yaw (multiples of 90 degrees)
##   ["aisles", kind, n0, n1]           parallel rows (shelf aisles) across the room
##   ["sets", table, seat, n0, n1, k]   tables with k seats each
##   ["corner", kind, n0, n1]           props in the corners
##   ["detail", kind, n0, n1]           small decor and clutter (no collider; the first thing a lower tier drops)
##   ["wm", kind, n0, n1, side]         wall-mounted things (screens, posters, racks, signs); side as in "wall"
##   ["hang", n]                        hanging lamps on a grid
##   ["pipes", n]                       ceiling pipe runs
##   ["dance"]                          the room gets a dance floor (animated tiles) in its middle
##   ["beams", n]                       club light-show beams from the ceiling
##   ["safe"] ["terminal"] ["hostage"] ["officer"]   the prop (if any) plus its anchor
##   ["anchor", kind, n0, n1]           anchors (civilian, guard, ...) at free reachable floor spots
## Colours are linear and dark on purpose: the light comes from the neon, the pools and the emissive strips.

const TYPES: Array[StringName] = [&"weapons", &"clinic", &"tech", &"bar", &"club", &"lobby", &"apartment", &"checkpoint", &"bodega", &"warehouse", &"corridor_lab", &"teleporter_hall", &"server_room", &"cargo_bay", &"med_bay", &"control_room"]

## Anchors every type guarantees (docs/interiors_interface.md): kind -> minimum count.
const GUARANTEED := {
	&"weapons": {&"vendor": 1, &"civilian": 4, &"safe": 1},
	&"clinic": {&"vendor": 1, &"civilian": 4},
	&"tech": {&"vendor": 1, &"civilian": 4, &"guard": 4, &"terminal": 1},
	&"bar": {&"vendor": 1, &"civilian": 4},
	&"club": {&"civilian": 4, &"guard": 4, &"officer": 1},
	&"lobby": {&"civilian": 4, &"guard": 4, &"safe": 1},
	&"apartment": {&"civilian": 4, &"guard": 4, &"safe": 1, &"hostage": 1},
	&"checkpoint": {&"guard": 4, &"terminal": 1},
	&"bodega": {&"vendor": 1, &"civilian": 4},
	&"warehouse": {&"civilian": 4, &"guard": 4},
	&"corridor_lab": {&"civilian": 4, &"guard": 4},
	&"teleporter_hall": {&"civilian": 4, &"guard": 4},
	&"server_room": {&"civilian": 4, &"guard": 4, &"terminal": 1},
	&"cargo_bay": {&"civilian": 4, &"guard": 4},
	&"med_bay": {&"civilian": 4, &"guard": 4},
	&"control_room": {&"civilian": 4, &"guard": 4, &"terminal": 1},
}

const SPECS := {
	&"weapons": {
		"name": "PAWN AND ARMS", "ceil": [3.0, 3.4], "windows": 0.9, "hostile": false, "style": 4, "styles": {"office": 0}, "fstyle": 2, "fstyles": {"office": 3},
		"pal": {"wall": Color(0.30, 0.20, 0.15), "wall2": Color(0.17, 0.16, 0.18), "floor": Color(0.19, 0.15, 0.11), "ceil": Color(0.14, 0.13, 0.13), "trim": Color(0.42, 0.32, 0.22),
			"neon": [Color(1.0, 0.45, 0.1), Color(1.0, 0.1, 0.3), Color(0.2, 0.9, 1.0)], "key": Color(1.0, 0.74, 0.48), "amb": Color(0.14, 0.11, 0.095)},
		"rooms": [
			{"role": "shop", "w": [7.0, 9.0], "d": [6.0, 8.0], "prog": [["counter", "counter"], ["wm", "rack", 3, 4, "back"], ["wall", "shelf", 1, 2, "left"], ["wall", "locker", 1, 2, "right"],
				["free", "crate", 1, 3], ["free", "box_pile", 1, 2], ["detail", "tv_old", 1, 1], ["wm", "screen", 1, 2, "right"], ["wm", "poster", 1, 3, "any"], ["detail", "crate_small", 2, 5], ["detail", "bin", 1, 2], ["pipes", 2], ["anchor", "civilian", 3, 4]]},
			{"role": "office", "w": [4.0, 5.0], "d": [4.0, 5.0], "prog": [["safe"], ["wall", "cabinet", 1, 2, "any"], ["free", "desk", 1, 1], ["wall", "bookcase", 1, 1, "any"], ["detail", "coat_rack", 1, 1], ["free", "crate", 1, 2], ["detail", "crate_small", 1, 3], ["anchor", "civilian", 1, 2]]},
		],
	},
	&"clinic": {
		"name": "STREET CLINIC", "ceil": [3.0, 3.3], "windows": 0.8, "hostile": false, "style": 1, "styles": {"waiting": 0}, "fstyle": 0, "fstyles": {"waiting": 1},
		"pal": {"wall": Color(0.26, 0.30, 0.31), "wall2": Color(0.15, 0.24, 0.24), "floor": Color(0.20, 0.23, 0.23), "ceil": Color(0.20, 0.21, 0.22), "trim": Color(0.5, 0.6, 0.6),
			"neon": [Color(0.25, 1.0, 0.75), Color(0.2, 0.7, 1.0), Color(1.0, 0.25, 0.4)], "key": Color(0.8, 1.0, 0.95), "amb": Color(0.10, 0.12, 0.12)},
		"rooms": [
			{"role": "waiting", "w": [7.0, 9.0], "d": [6.0, 7.0], "prog": [["counter", "counter"], ["wall", "couch", 2, 3, "left"], ["wall", "vending", 1, 1, "right"], ["free", "plant", 1, 2],
				["wall", "side_table", 1, 2, "any"], ["detail", "coat_rack", 1, 1], ["wm", "screen", 1, 2, "right"], ["wm", "poster", 1, 2, "any"], ["detail", "bin", 1, 2], ["anchor", "civilian", 3, 4]]},
			{"role": "exam", "w": [4.0, 5.0], "d": [4.0, 5.0], "prog": [["free", "medbed", 1, 2], ["wall", "wash_station", 1, 1, "left"], ["wall", "cabinet", 1, 2, "back"], ["wm", "screen", 1, 2, "any"], ["detail", "bin", 1, 1], ["detail", "crate_small", 1, 2], ["anchor", "civilian", 1, 2]]},
			{"role": "ward", "w": [5.0, 6.0], "d": [4.0, 5.0], "prog": [["wall", "cot", 2, 3, "back"], ["wall", "locker", 1, 2, "left"], ["wall", "side_table", 1, 2, "any"], ["wm", "screen", 1, 1, "any"], ["anchor", "civilian", 1, 2]]},
		],
	},
	&"tech": {
		"name": "REPAIR DEN", "ceil": [3.0, 3.4], "windows": 0.7, "hostile": false,
		"pal": {"wall": Color(0.11, 0.13, 0.16), "wall2": Color(0.08, 0.10, 0.13), "floor": Color(0.08, 0.09, 0.10), "ceil": Color(0.07, 0.07, 0.09), "trim": Color(0.22, 0.3, 0.38),
			"neon": [Color(0.1, 0.85, 1.0), Color(0.2, 1.0, 0.45), Color(1.0, 0.2, 0.75)], "key": Color(0.6, 0.85, 1.0), "amb": Color(0.06, 0.075, 0.095)},
		"rooms": [
			{"role": "shop", "w": [7.0, 9.0], "d": [6.0, 7.0], "prog": [["counter", "counter"], ["free", "workbench", 2, 3], ["wall", "shelf", 2, 3, "left"], ["wm", "screen", 3, 5, "any"],
				["free", "crate", 1, 3], ["detail", "crate_small", 3, 6], ["detail", "bin", 1, 2], ["pipes", 3], ["hang", 3], ["anchor", "civilian", 3, 4], ["anchor", "guard", 2, 3]]},
			{"role": "lab", "w": [4.0, 6.0], "d": [4.0, 5.0], "prog": [["terminal"], ["wall", "rack_tall", 1, 2, "back"], ["free", "workbench", 1, 1], ["wm", "screen", 2, 3, "any"], ["pipes", 2], ["anchor", "guard", 2, 3], ["anchor", "civilian", 1, 2]]},
		],
	},
	&"bar": {
		"name": "NOODLE BAR", "ceil": [3.0, 3.4], "windows": 0.9, "hostile": false, "style": 3, "styles": {"kitchen": 1}, "fstyle": 2, "fstyles": {"kitchen": 0},
		"pal": {"wall": Color(0.40, 0.17, 0.12), "wall2": Color(0.12, 0.17, 0.20), "floor": Color(0.16, 0.12, 0.09), "ceil": Color(0.09, 0.08, 0.08), "trim": Color(0.5, 0.26, 0.14),
			"neon": [Color(1.0, 0.22, 0.2), Color(1.0, 0.72, 0.18), Color(0.15, 0.85, 1.0)], "key": Color(1.0, 0.68, 0.42), "amb": Color(0.105, 0.075, 0.06)},
		"rooms": [
			{"role": "bar", "w": [8.0, 10.0], "d": [6.0, 8.0], "prog": [["counter", "bar"], ["sets", "table_round", "stool", 3, 4, 2], ["hang", 5], ["wall", "couch", 1, 2, "right"], ["wm", "poster", 2, 3, "any"], ["wm", "screen", 1, 2, "left"],
				["free", "plant", 1, 1], ["detail", "coat_rack", 1, 1], ["detail", "bin", 1, 2], ["detail", "crate_small", 1, 3], ["anchor", "civilian", 4, 5]]},
			{"role": "kitchen", "w": [4.0, 5.0], "d": [4.0, 5.0], "prog": [["wall", "kitchen_run", 1, 1, "back"], ["wall", "fridge_home", 1, 1, "left"], ["free", "barrel", 1, 2], ["free", "box_pile", 1, 1], ["pipes", 3], ["detail", "bin", 1, 1], ["detail", "crate_small", 2, 4], ["anchor", "civilian", 1, 2]]},
		],
	},
	&"club": {
		"name": "CLUB", "ceil": [5.4, 6.0], "windows": 0.3, "hostile": false,
		"pal": {"wall": Color(0.07, 0.05, 0.10), "wall2": Color(0.05, 0.05, 0.09), "floor": Color(0.05, 0.045, 0.07), "ceil": Color(0.04, 0.04, 0.06), "trim": Color(0.25, 0.1, 0.35),
			"neon": [Color(1.0, 0.1, 0.65), Color(0.15, 0.7, 1.0), Color(0.7, 0.2, 1.0)], "key": Color(0.8, 0.4, 1.0), "amb": Color(0.085, 0.06, 0.115)},
		"rooms": [
			{"role": "hall", "w": [11.0, 14.0], "d": [9.0, 12.0], "prog": [["dance"], ["wall", "dj", 1, 1, "back"], ["wall", "speaker", 2, 4, "back"], ["counter", "bar", "right"], ["wall", "couch", 2, 4, "left"],
				["sets", "table_round", "stool", 1, 2, 2], ["wm", "screen", 2, 3, "right"], ["beams", 5], ["hang", 3], ["detail", "bin", 1, 2], ["anchor", "civilian", 5, 7], ["anchor", "guard", 2, 3]]},
			{"role": "vip", "w": [5.0, 6.0], "d": [4.0, 5.0], "prog": [["officer"], ["wall", "couch", 2, 2, "back"], ["free", "table_round", 1, 1], ["wm", "screen", 1, 2, "any"], ["anchor", "guard", 2, 3], ["anchor", "civilian", 1, 2]]},
			{"role": "store", "w": [4.0, 5.0], "d": [3.5, 4.5], "prog": [["free", "crate", 2, 4], ["wall", "shelf", 1, 1, "back"], ["pipes", 2], ["anchor", "civilian", 1, 1]]},
		],
	},
	&"lobby": {
		"name": "HOTEL LOBBY", "ceil": [4.0, 4.5], "windows": 0.9, "hostile": false,
		"pal": {"wall": Color(0.17, 0.13, 0.12), "wall2": Color(0.10, 0.12, 0.15), "floor": Color(0.13, 0.12, 0.13), "ceil": Color(0.10, 0.09, 0.10), "trim": Color(0.55, 0.42, 0.22),
			"neon": [Color(1.0, 0.7, 0.25), Color(1.0, 0.2, 0.5), Color(0.2, 0.8, 1.0)], "key": Color(1.0, 0.8, 0.55), "amb": Color(0.09, 0.075, 0.07)},
		"rooms": [
			{"role": "lobby", "w": [10.0, 12.0], "d": [8.0, 10.0], "prog": [["wall", "reception", 1, 1, "back"], ["wall", "elevator", 1, 1, "left"], ["free", "couch", 3, 4], ["free", "plant", 3, 4],
				["wm", "screen", 1, 2, "right"], ["wm", "poster", 2, 3, "any"], ["hang", 4], ["detail", "rug", 2, 3], ["detail", "bin", 1, 2], ["anchor", "civilian", 5, 6], ["anchor", "guard", 3, 4]]},
			{"role": "office", "w": [4.0, 5.0], "d": [4.0, 5.0], "prog": [["safe"], ["free", "desk", 1, 1], ["wall", "cabinet", 1, 2, "any"], ["anchor", "guard", 1, 2], ["anchor", "civilian", 1, 2]]},
			{"role": "suite", "w": [5.0, 6.0], "d": [4.0, 5.0], "prog": [["wall", "bed", 1, 1, "back"], ["free", "couch", 1, 1], ["free", "plant", 1, 1], ["wm", "screen", 1, 1, "any"], ["anchor", "civilian", 1, 2]]},
		],
	},
	&"apartment": {
		"name": "APARTMENT", "ceil": [2.8, 3.1], "windows": 0.9, "hostile": false, "style": 4, "styles": {"kitchen": 1, "stash": 0}, "fstyle": 2, "fstyles": {"kitchen": 0, "stash": 3},
		"pal": {"wall": Color(0.30, 0.22, 0.22), "wall2": Color(0.18, 0.20, 0.23), "floor": Color(0.17, 0.13, 0.10), "ceil": Color(0.16, 0.15, 0.15), "trim": Color(0.42, 0.34, 0.30),
			"neon": [Color(1.0, 0.25, 0.6), Color(0.2, 0.75, 1.0), Color(1.0, 0.65, 0.25)], "key": Color(1.0, 0.76, 0.55), "amb": Color(0.15, 0.12, 0.115)},
		"rooms": [
			{"role": "living", "w": [6.0, 8.0], "d": [5.0, 6.0], "prog": [["wall", "couch", 1, 1, "back"], ["wall", "tv_unit", 1, 1, "left"], ["wall", "bookcase", 1, 2, "right"], ["free", "armchair", 1, 1], ["free", "plant", 1, 2], ["free", "lamp_floor", 1, 2],
				["wm", "poster", 1, 2, "any"], ["detail", "rug", 1, 1], ["detail", "coffee_table", 1, 1], ["detail", "coat_rack", 1, 1], ["detail", "bin", 1, 1], ["anchor", "civilian", 2, 3], ["anchor", "guard", 2, 3]]},
			{"role": "kitchen", "w": [4.0, 5.0], "d": [3.5, 4.5], "prog": [["wall", "kitchen_run", 1, 1, "back"], ["wall", "fridge_home", 1, 1, "left"], ["free", "table", 1, 1], ["detail", "chair", 2, 3], ["detail", "bin", 1, 1], ["pipes", 1], ["anchor", "civilian", 1, 1], ["anchor", "guard", 1, 1]]},
			{"role": "bedroom", "w": [4.0, 5.0], "d": [4.0, 5.0], "prog": [["wall", "bed", 1, 1, "back"], ["wall", "side_table", 1, 2, "any"], ["wall", "locker", 1, 2, "right"], ["free", "desk", 1, 1], ["wall", "bookcase", 1, 1, "any"], ["hostage"], ["anchor", "guard", 1, 1]]},
			{"role": "stash", "w": [3.2, 3.8], "d": [3.2, 3.8], "prog": [["safe"], ["free", "crate", 1, 2], ["anchor", "guard", 1, 1], ["anchor", "civilian", 1, 1]]},
		],
	},
	&"checkpoint": {
		"name": "AUTHORITY CHECKPOINT", "ceil": [3.4, 3.8], "windows": 0.4, "hostile": true,
		"pal": {"wall": Color(0.08, 0.12, 0.12), "wall2": Color(0.06, 0.09, 0.10), "floor": Color(0.07, 0.09, 0.09), "ceil": Color(0.05, 0.07, 0.07), "trim": Color(0.2, 0.4, 0.38),
			"neon": [Color(0.3, 1.0, 0.45), Color(0.2, 0.9, 0.9), Color(1.0, 0.25, 0.2)], "key": Color(0.55, 1.0, 0.8), "amb": Color(0.05, 0.075, 0.07)},
		"rooms": [
			{"role": "gate", "w": [9.0, 12.0], "d": [7.0, 9.0], "prog": [["wall", "gate", 1, 2, "back"], ["wall", "counter", 1, 2, "right"], ["terminal"], ["free", "crate", 3, 5], ["wm", "screen", 3, 4, "any"], ["wm", "poster", 1, 2, "any"],
				["pipes", 3], ["detail", "crate_small", 2, 4], ["anchor", "guard", 4, 6]]},
			{"role": "holding", "w": [5.0, 6.0], "d": [5.0, 6.0], "prog": [["wall", "bunk", 2, 3, "back"], ["free", "crate", 1, 2], ["wm", "screen", 1, 1, "any"], ["anchor", "guard", 1, 2]]},
			{"role": "office", "w": [4.0, 5.0], "d": [4.0, 5.0], "prog": [["free", "desk", 1, 1], ["wall", "locker", 1, 2, "any"], ["wm", "screen", 1, 2, "any"], ["anchor", "guard", 1, 2]]},
		],
	},
	&"bodega": {
		"name": "CORNER BODEGA", "ceil": [2.9, 3.2], "windows": 1.0, "hostile": false, "style": 1, "styles": {"stock": 2}, "fstyle": 1, "fstyles": {"stock": 3},
		"pal": {"wall": Color(0.15, 0.30, 0.25), "wall2": Color(0.34, 0.27, 0.17), "floor": Color(0.2, 0.2, 0.17), "ceil": Color(0.16, 0.16, 0.15), "trim": Color(0.55, 0.45, 0.2),
			"neon": [Color(0.25, 0.95, 0.9), Color(1.0, 0.75, 0.15), Color(1.0, 0.2, 0.4)], "key": Color(1.0, 0.92, 0.75), "amb": Color(0.11, 0.105, 0.095)},
		"rooms": [
			{"role": "shop", "w": [7.0, 9.0], "d": [6.0, 8.0], "prog": [["counter", "counter"], ["aisles", "shelf", 3, 5], ["wall", "fridge", 2, 3, "right"], ["wall", "vending", 1, 1, "left"],
				["free", "crate", 1, 2], ["free", "box_pile", 1, 2], ["free", "plant", 1, 1], ["wm", "poster", 2, 4, "any"], ["detail", "bin", 1, 2], ["detail", "crate_small", 2, 5], ["anchor", "civilian", 4, 5]]},
			{"role": "stock", "w": [4.0, 5.0], "d": [4.0, 5.0], "prog": [["free", "box_pile", 2, 3], ["free", "crate", 1, 2], ["wall", "rack_tall", 1, 1, "back"], ["pipes", 2], ["detail", "crate_small", 2, 4], ["anchor", "civilian", 1, 2]]},
		],
	},
	&"warehouse": {
		"name": "VAEL FREIGHT WAREHOUSE", "ceil": [5.2, 6.0], "windows": 0.2, "hostile": true, "style": 2, "styles": {"office": 0}, "fstyle": 3, "fstyles": {"office": 0},
		"pal": {"wall": Color(0.24, 0.23, 0.21), "wall2": Color(0.15, 0.19, 0.24), "floor": Color(0.13, 0.13, 0.12), "ceil": Color(0.10, 0.10, 0.11), "trim": Color(0.45, 0.36, 0.1),
			"neon": [Color(1.0, 0.68, 0.12), Color(1.0, 0.3, 0.12), Color(0.25, 0.85, 1.0)], "key": Color(1.0, 0.85, 0.6), "amb": Color(0.145, 0.135, 0.125)},
		"rooms": [
			{"role": "floor", "w": [14.0, 18.0], "d": [12.0, 16.0], "prog": [["aisles", "rack_tall", 4, 6], ["free", "crate_stack", 3, 5], ["free", "box_pile", 3, 5], ["free", "pallet", 2, 4], ["free", "barrel", 2, 4], ["pipes", 5], ["hang", 4],
				["wm", "poster", 1, 2, "any"], ["detail", "crate_small", 4, 8], ["detail", "bin", 1, 3], ["anchor", "civilian", 4, 5], ["anchor", "guard", 4, 6]]},
			{"role": "office", "w": [4.0, 5.0], "d": [4.0, 5.0], "prog": [["terminal"], ["free", "desk", 1, 1], ["wall", "cabinet", 1, 2, "any"], ["wall", "bookcase", 1, 1, "any"], ["detail", "coat_rack", 1, 1], ["detail", "bin", 1, 1], ["wm", "screen", 1, 2, "any"], ["anchor", "guard", 1, 2], ["anchor", "civilian", 1, 1]]},
		],
	},
	# --- interior kit layouts (Quaternius pieces, quantum-realism film in assets/shaders/interior_surface.gdshader) ---
	&"corridor_lab": {
		"name": "CORRIDOR LAB", "ceil": [3.0, 3.3], "windows": 0.5, "hostile": false,
		"pal": {"wall": Color(0.13, 0.15, 0.18), "wall2": Color(0.09, 0.11, 0.14), "floor": Color(0.09, 0.10, 0.12), "ceil": Color(0.08, 0.09, 0.11), "trim": Color(0.25, 0.4, 0.5),
			"neon": [Color(0.2, 0.9, 1.0), Color(0.8, 0.3, 1.0), Color(0.3, 1.0, 0.7)], "key": Color(0.6, 0.9, 1.0), "amb": Color(0.06, 0.08, 0.10)},
		"rooms": [
			{"role": "corridor", "w": [9.0, 12.0], "d": [4.5, 5.5], "prog": [["wall", "kit_shelf", 1, 2, "back"], ["wall", "kit_server", 2, 3, "left"], ["wall", "kit_console", 1, 2, "right"], ["free", "kit_vessel", 1, 2],
				["wm", "screen", 1, 2, "any"], ["wm", "kit_pipes", 2, 3, "any"], ["detail", "kit_crate", 1, 2], ["anchor", "civilian", 3, 4], ["anchor", "guard", 2, 3]]},
			{"role": "lab", "w": [6.0, 7.0], "d": [5.0, 6.0], "prog": [["wall", "kit_console", 2, 3, "back"], ["free", "kit_capsule", 1, 2], ["free", "workbench", 1, 1], ["wall", "kit_shelf_tall", 1, 1, "left"],
				["wm", "screen", 1, 2, "any"], ["wm", "kit_pipes", 1, 2, "any"], ["anchor", "guard", 2, 3], ["anchor", "civilian", 1, 2]]},
			{"role": "store", "w": [4.0, 5.0], "d": [4.0, 5.0], "prog": [["wall", "kit_shelf", 1, 2, "back"], ["free", "kit_crate", 1, 2], ["free", "kit_crate_long", 1, 1], ["anchor", "civilian", 1, 1], ["anchor", "guard", 1, 1]]},
		],
	},
	&"teleporter_hall": {
		"name": "TELEPORTER HALL", "ceil": [4.4, 5.0], "windows": 0.3, "hostile": false,
		"pal": {"wall": Color(0.10, 0.11, 0.16), "wall2": Color(0.07, 0.08, 0.13), "floor": Color(0.07, 0.07, 0.10), "ceil": Color(0.05, 0.05, 0.08), "trim": Color(0.3, 0.25, 0.5),
			"neon": [Color(0.55, 0.35, 1.0), Color(0.2, 0.85, 1.0), Color(1.0, 0.3, 0.8)], "key": Color(0.7, 0.6, 1.0), "amb": Color(0.07, 0.065, 0.11)},
		"rooms": [
			{"role": "hall", "w": [10.0, 13.0], "d": [8.0, 10.0], "prog": [["free", "kit_teleporter", 2, 3], ["free", "kit_pad", 1, 2], ["wall", "kit_pod", 2, 3, "back"], ["wall", "kit_console", 1, 2, "left"],
				["wm", "screen", 2, 3, "right"], ["wm", "kit_pipes", 2, 3, "any"], ["detail", "kit_vessel", 1, 3], ["hang", 3], ["anchor", "civilian", 3, 4], ["anchor", "guard", 2, 3]]},
			{"role": "prep", "w": [5.0, 6.0], "d": [4.0, 5.0], "prog": [["wall", "kit_capsule", 2, 3, "back"], ["wall", "locker", 1, 2, "left"], ["free", "kit_crate", 1, 1], ["anchor", "guard", 1, 2], ["anchor", "civilian", 1, 2]]},
		],
	},
	&"server_room": {
		"name": "SERVER ROOM", "ceil": [3.2, 3.6], "windows": 0.2, "hostile": false,
		"pal": {"wall": Color(0.08, 0.10, 0.12), "wall2": Color(0.06, 0.08, 0.10), "floor": Color(0.06, 0.07, 0.08), "ceil": Color(0.05, 0.06, 0.07), "trim": Color(0.15, 0.4, 0.4),
			"neon": [Color(0.1, 1.0, 0.8), Color(0.2, 0.6, 1.0), Color(1.0, 0.3, 0.5)], "key": Color(0.5, 1.0, 0.9), "amb": Color(0.05, 0.07, 0.075)},
		"rooms": [
			{"role": "racks", "w": [9.0, 12.0], "d": [7.0, 9.0], "prog": [["aisles", "kit_server", 4, 6], ["terminal"], ["wall", "kit_console", 1, 2, "back"], ["wm", "screen", 2, 3, "any"], ["wm", "kit_pipes", 3, 4, "any"],
				["pipes", 2], ["anchor", "civilian", 3, 4], ["anchor", "guard", 2, 3]]},
			{"role": "ops", "w": [4.5, 5.5], "d": [4.0, 5.0], "prog": [["free", "desk", 1, 1], ["wall", "kit_server", 1, 2, "back"], ["wm", "screen", 2, 2, "any"], ["anchor", "guard", 2, 3], ["anchor", "civilian", 1, 2]]},
		],
	},
	&"cargo_bay": {
		"name": "CARGO BAY", "ceil": [5.0, 5.8], "windows": 0.2, "hostile": true,
		"pal": {"wall": Color(0.12, 0.12, 0.11), "wall2": Color(0.09, 0.09, 0.10), "floor": Color(0.08, 0.08, 0.08), "ceil": Color(0.06, 0.06, 0.06), "trim": Color(0.35, 0.28, 0.1),
			"neon": [Color(1.0, 0.65, 0.1), Color(0.3, 0.9, 1.0), Color(1.0, 0.3, 0.2)], "key": Color(1.0, 0.85, 0.55), "amb": Color(0.07, 0.065, 0.06)},
		"rooms": [
			{"role": "bay", "w": [13.0, 16.0], "d": [10.0, 13.0], "prog": [["free", "kit_container", 4, 6], ["free", "kit_crate", 4, 6], ["free", "kit_crate_long", 2, 4], ["aisles", "kit_shelf_tall", 2, 3],
				["wm", "kit_pipes", 3, 5, "any"], ["pipes", 3], ["hang", 4], ["wm", "poster", 1, 2, "any"], ["anchor", "civilian", 4, 5], ["anchor", "guard", 4, 6]]},
			{"role": "office", "w": [4.0, 5.0], "d": [4.0, 5.0], "prog": [["free", "desk", 1, 1], ["wall", "kit_console", 1, 1, "back"], ["wall", "cabinet", 1, 2, "any"], ["anchor", "guard", 1, 2], ["anchor", "civilian", 1, 1]]},
		],
	},
	&"med_bay": {
		"name": "MED BAY", "ceil": [3.0, 3.4], "windows": 0.6, "hostile": false,
		"pal": {"wall": Color(0.24, 0.28, 0.30), "wall2": Color(0.14, 0.22, 0.24), "floor": Color(0.18, 0.21, 0.22), "ceil": Color(0.18, 0.20, 0.21), "trim": Color(0.45, 0.6, 0.62),
			"neon": [Color(0.3, 1.0, 0.8), Color(0.4, 0.8, 1.0), Color(1.0, 0.45, 0.6)], "key": Color(0.8, 1.0, 0.95), "amb": Color(0.10, 0.12, 0.125)},
		"rooms": [
			{"role": "ward", "w": [8.0, 10.0], "d": [6.0, 8.0], "prog": [["free", "medbed", 2, 3], ["wall", "kit_capsule", 1, 2, "back"], ["wall", "kit_console", 1, 2, "left"], ["wall", "cabinet", 1, 2, "right"],
				["wm", "screen", 1, 2, "any"], ["detail", "kit_vessel", 2, 3], ["detail", "bin", 1, 2], ["anchor", "civilian", 4, 5], ["anchor", "guard", 1, 2]]},
			{"role": "icu", "w": [5.0, 6.0], "d": [4.0, 5.0], "prog": [["free", "kit_pod", 1, 1], ["wall", "kit_console", 1, 2, "back"], ["wall", "locker", 1, 1, "left"], ["anchor", "civilian", 1, 2], ["anchor", "guard", 1, 2]]},
		],
	},
	&"control_room": {
		"name": "CONTROL ROOM", "ceil": [3.2, 3.6], "windows": 0.3, "hostile": true,
		"pal": {"wall": Color(0.07, 0.09, 0.12), "wall2": Color(0.05, 0.07, 0.10), "floor": Color(0.05, 0.06, 0.08), "ceil": Color(0.04, 0.05, 0.07), "trim": Color(0.2, 0.35, 0.5),
			"neon": [Color(0.2, 0.8, 1.0), Color(1.0, 0.25, 0.3), Color(0.5, 1.0, 0.5)], "key": Color(0.55, 0.85, 1.0), "amb": Color(0.05, 0.065, 0.085)},
		"rooms": [
			{"role": "deck", "w": [9.0, 11.0], "d": [7.0, 9.0], "prog": [["terminal"], ["wall", "kit_console", 3, 4, "back"], ["free", "kit_console", 1, 2], ["wall", "kit_server", 2, 3, "left"], ["wm", "screen", 3, 4, "any"],
				["free", "kit_laser", 1, 1], ["wm", "kit_pipes", 2, 3, "any"], ["hang", 3], ["anchor", "civilian", 3, 4], ["anchor", "guard", 3, 4]]},
			{"role": "armoury", "w": [4.0, 5.0], "d": [4.0, 5.0], "prog": [["wall", "locker", 1, 2, "back"], ["free", "kit_crate", 1, 2], ["wall", "kit_shelf", 1, 1, "left"], ["anchor", "guard", 1, 2], ["anchor", "civilian", 1, 1]]},
		],
	},
}

## Audio hooks (data only: the Interior node plays nothing). Names are `Sfx` names (assets/audio/<name>[_N].wav|ogg); `Sfx.variants_of(name)` is non-empty for every one of them.
## `dedicated` is the name of a loop the audio layer prefers once the file exists (assets/audio/interior_<type>.ogg). `loops` run while inside: [name, volume_db];
## `oneshots` fire at random: [name, min_seconds, max_seconds, volume_db]; `muffle` 0..1 is how far the street ambience (rain, traffic) is closed while inside.
const AMBIENCE := {
	&"weapons": {"dedicated": &"interior_weapons", "loops": [[&"drone_hum", -24.0], [&"rain_awning", -26.0]], "oneshots": [[&"dry_fire", 14.0, 30.0, -22.0], [&"reload", 20.0, 40.0, -24.0]], "muffle": 0.8},
	&"clinic": {"dedicated": &"interior_clinic", "loops": [[&"drone_hum", -22.0], [&"rain_awning", -28.0]], "oneshots": [[&"heartbeat", 12.0, 24.0, -26.0], [&"radio_static", 20.0, 40.0, -28.0]], "muffle": 0.85},
	&"tech": {"dedicated": &"interior_tech", "loops": [[&"drone_hum", -20.0], [&"radio_static", -30.0], [&"rain_awning", -27.0]], "oneshots": [[&"impact_metal", 6.0, 14.0, -26.0], [&"radio_glitch", 10.0, 22.0, -26.0]], "muffle": 0.8},
	&"bar": {"dedicated": &"interior_bar", "loops": [[&"babble", -20.0], [&"rain_awning", -27.0], [&"drone_hum", -28.0]], "oneshots": [[&"impact_glass", 8.0, 18.0, -24.0], [&"reload", 25.0, 50.0, -30.0]], "muffle": 0.75},
	&"club": {"dedicated": &"interior_club", "loops": [[&"music_bass", -9.0], [&"music_perc", -11.0], [&"music_pulse", -13.0], [&"babble", -22.0]], "oneshots": [[&"impact_glass", 12.0, 30.0, -26.0]], "muffle": 0.95},
	&"lobby": {"dedicated": &"interior_lobby", "loops": [[&"city_hum", -26.0], [&"babble", -28.0], [&"rain_awning", -30.0]], "oneshots": [[&"ui_tick", 18.0, 40.0, -28.0]], "muffle": 0.85},
	&"apartment": {"dedicated": &"interior_apartment", "loops": [[&"rain_awning", -20.0], [&"drone_hum", -30.0]], "oneshots": [[&"radio_static", 14.0, 30.0, -26.0], [&"distant_boom", 20.0, 45.0, -26.0]], "muffle": 0.9},
	&"checkpoint": {"dedicated": &"interior_checkpoint", "loops": [[&"drone_hum", -18.0], [&"radio_static", -28.0]], "oneshots": [[&"radio_glitch", 5.0, 12.0, -22.0], [&"drone_alert", 15.0, 30.0, -24.0]], "muffle": 0.85},
	&"bodega": {"dedicated": &"interior_bodega", "loops": [[&"drone_hum", -24.0], [&"rain_awning", -26.0]], "oneshots": [[&"babble", 15.0, 30.0, -26.0], [&"impact_metal", 20.0, 40.0, -28.0]], "muffle": 0.8},
	&"warehouse": {"dedicated": &"interior_warehouse", "loops": [[&"city_hum", -22.0], [&"rain_metal", -22.0]], "oneshots": [[&"impact_metal", 5.0, 12.0, -22.0], [&"distant_boom", 25.0, 50.0, -26.0]], "muffle": 0.6},
	&"corridor_lab": {"dedicated": &"interior_tech", "loops": [[&"drone_hum", -22.0], [&"radio_static", -32.0]], "oneshots": [[&"radio_glitch", 10.0, 22.0, -26.0]], "muffle": 0.85},
	&"teleporter_hall": {"dedicated": &"interior_tech", "loops": [[&"drone_hum", -18.0], [&"city_hum", -28.0]], "oneshots": [[&"radio_glitch", 6.0, 14.0, -24.0], [&"distant_boom", 25.0, 50.0, -28.0]], "muffle": 0.9},
	&"server_room": {"dedicated": &"interior_tech", "loops": [[&"drone_hum", -16.0], [&"radio_static", -30.0]], "oneshots": [[&"ui_tick", 8.0, 18.0, -26.0]], "muffle": 0.9},
	&"cargo_bay": {"dedicated": &"interior_warehouse", "loops": [[&"city_hum", -24.0], [&"rain_metal", -24.0]], "oneshots": [[&"impact_metal", 6.0, 14.0, -22.0]], "muffle": 0.6},
	&"med_bay": {"dedicated": &"interior_clinic", "loops": [[&"drone_hum", -22.0]], "oneshots": [[&"heartbeat", 10.0, 22.0, -26.0]], "muffle": 0.85},
	&"control_room": {"dedicated": &"interior_checkpoint", "loops": [[&"drone_hum", -18.0], [&"radio_static", -28.0]], "oneshots": [[&"radio_glitch", 6.0, 14.0, -24.0], [&"ui_tick", 10.0, 24.0, -28.0]], "muffle": 0.85},
}


static var _dressed := {}


static func spec(type: StringName) -> Dictionary:
	var k: StringName = type if SPECS.has(type) else &"bodega"
	if not _dressed.has(k):
		_dressed[k] = _dress(SPECS[k])
	return _dressed[k]


## Every room behind the street room gets the same dressing floor: a hanging lamp, a rug, a poster and a bin (no collider props: the guaranteed anchors need the floor spots), whatever its recipe already has stays (director review 3 #11:
## the back rooms were an empty grey box). Props are "detail" and wall-mounted pieces, so a lower tier drops them first.
static func _dress(src: Dictionary) -> Dictionary:
	var spec: Dictionary = src.duplicate(true)
	var rooms: Array = spec.get("rooms", [])
	for i in range(1, rooms.size()):
		var prog: Array = (rooms[i] as Dictionary)["prog"]
		var ops := {}
		for st: Array in prog:
			ops[str(st[0]) + ":" + (str(st[1]) if st.size() > 1 and st[1] is String else "")] = true
		var add: Array = []
		if not ops.has("hang:"):
			add.append(["hang", 2])
		if not ops.has("detail:rug"):
			add.append(["detail", "rug", 1, 2])
		if not ops.has("wm:poster"):
			add.append(["wm", "poster", 1, 2, "any"])
		if not ops.has("detail:bin"):
			add.append(["detail", "bin", 1, 2])
		# the anchors stay last: they take the floor spots that are still free
		var anchors: Array = []
		var body: Array = []
		for st: Array in prog:
			(anchors if str(st[0]) == "anchor" else body).append(st)
		(rooms[i] as Dictionary)["prog"] = body + add + anchors
	return spec


static func has_type(type: StringName) -> bool:
	return SPECS.has(type)


static func ambience(type: StringName) -> Dictionary:
	return AMBIENCE.get(type, AMBIENCE[&"bodega"])
