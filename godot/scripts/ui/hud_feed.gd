class_name HudFeed
extends RefCounted
## The two small feeds of the HUD (wave 109b): WHO WENT DOWN (kills, wrecked vehicles) and WHAT WAS PICKED UP (ammo, health, coherence, weapons, mods). Both share one corner stack under the wanted
## stars, at most MAX_LINES short lines, each lives LIFE seconds and fades; equal lines merge into "x2". They replace the pickup toasts (`take_message`) so the one toast channel keeps
## the important things only. Kills are SEEN by polling the `enemy` and `vehicle` groups a few times a second (no hook in the enemy scripts): a tracked body that turns `dead` is one line.
## Pure logic with an explicit clock (`now`), so tests drive it without frames: `push`, `visible_lines`, `poll`.

const MAX_LINES := 4
const LIFE := 4.2
const FADE := 0.8
const POLL_EVERY := 0.25
const NEAR := 220.0                    ## metres: bodies further away are not tracked
const KILL := &"kill"
const PICKUP := &"pickup"
const WRECK := &"wreck"
const KIND_COL := {&"kill": Color(1.0, 0.4, 0.4), &"pickup": Color(0.5, 1.0, 0.7), &"wreck": Color(1.0, 0.72, 0.3)}
const KIND_SPRITE := {&"kill": &"diamond", &"pickup": &"disc", &"wreck": &"ring"}
const PICKUP_STARTS: Array[String] = ["NEW WEAPON", "NEW MOD", "ALIEN TECH", "AMMO RESTOCK", "AMMO FULL", "HEALTH PACK"]

var lines: Array[Dictionary] = []      ## {kind, text, t0, n}
var kills := 0                         ## all-time counters (tests, stats)
var pickups := 0
var wrecks := 0
var _alive := {}                       ## instance id -> name of a tracked living enemy
var _cars := {}                        ## instance id -> name of a tracked intact vehicle
var _poll_t := 0.0


## What a pickup message looks like: "+30 INTEGRITY", "+6 CARBINE", "NEW WEAPON  RAILGUN", "NEW MOD  SCOPE". Completion lines ("COURIER RUN COMPLETE  +200 CREDITS") are not pickups.
static func classify(text: String) -> StringName:
	var u := text.strip_edges().to_upper()
	if u == "" or u.contains("COMPLETE") or u.contains("FAILED"):
		return &""
	if u.begins_with("+") and u.length() > 2 and u.length() <= 26 and u.substr(1, 1).is_valid_int() and not u.contains("CREDIT"):       # short "+30 INTEGRITY" lines; money and long messages stay toasts
		return PICKUP
	for st in PICKUP_STARTS:
		if u.begins_with(st):
			return PICKUP
	return &""


## Offers a Game.say line: a pickup line goes to the feed. Returns true when the toast should skip it (the "+N WORD" lines; weapon and mod news stays a toast too).
func take_message(text: String, now: float) -> bool:
	if classify(text) != PICKUP:
		return false
	var u := text.strip_edges().to_upper().replace("  (LOADOUT TO EQUIP)", "")
	push(PICKUP, u, now)
	return u.begins_with("+") or u.begins_with("AMMO") or u.begins_with("HEALTH PACK")


func push(kind: StringName, text: String, now: float) -> void:
	match kind:
		KILL:
			kills += 1
		PICKUP:
			pickups += 1
		WRECK:
			wrecks += 1
	for l: Dictionary in lines:
		if l["text"] == text and now - float(l["t0"]) < LIFE:                      # the same line while it is still up: one line, a count (two equal lines would also be a repeat on screen)
			l["n"] = int(l["n"]) + 1
			l["t0"] = now
			return
	lines.append({"kind": kind, "text": text, "t0": now, "n": 1})
	while lines.size() > MAX_LINES:
		lines.remove_at(0)


## The lines still alive at `now`, newest last: {kind, text, alpha, n, label} (label = the line as drawn).
func visible_lines(now: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var keep: Array[Dictionary] = []
	for l: Dictionary in lines:
		var age := now - float(l["t0"])
		if age >= LIFE:
			continue
		keep.append(l)
		var a := clampf((LIFE - age) / FADE, 0.0, 1.0)
		var label := String(l["text"]) + ("  x%d" % int(l["n"]) if int(l["n"]) > 1 else "")
		out.append({"kind": l["kind"], "text": l["text"], "alpha": a, "n": l["n"], "label": label})
	lines = keep
	return out


func clear() -> void:
	lines.clear()
	_alive.clear()
	_cars.clear()


func active(now: float) -> bool:
	for l: Dictionary in lines:
		if now - float(l["t0"]) < LIFE:
			return true
	return false


## The name of an enemy for its line: the species title, else the drone type, else ENEMY.
static func enemy_name(n: Node) -> String:
	var sid: Variant = n.get("id")
	if sid is StringName and sid != &"":
		return AlienSpecies.title(sid).to_upper()
	var t: Variant = n.get("type")
	if t is StringName and t != &"":
		return String(t).replace("_", " ").to_upper()
	return "ENEMY"


## Looks at the bodies near `origin`: a tracked enemy that is `dead` now is a DOWN line, a tracked vehicle that is `dead` is a WRECK line. Call it often; it samples every POLL_EVERY seconds.
func poll(tree: SceneTree, origin: Vector3, now: float, delta: float) -> void:
	_poll_t -= delta
	if _poll_t > 0.0 or tree == null:
		return
	_poll_t = POLL_EVERY
	_track(tree.get_nodes_in_group(&"enemy"), _alive, KILL, origin, now, "")
	_track(tree.get_nodes_in_group(&"vehicle"), _cars, WRECK, origin, now, "")


func _track(nodes: Array[Node], seen: Dictionary, kind: StringName, origin: Vector3, now: float, _unused: String) -> void:
	var live := {}
	for n: Node in nodes:
		var n3 := n as Node3D
		if n3 == null:
			continue
		var id := n3.get_instance_id()
		var near := Vector2(n3.global_position.x - origin.x, n3.global_position.z - origin.z).length() < NEAR
		var dead: bool = n3.get("dead") == true
		if kind == WRECK:
			dead = dead or n3.get("wreck") == true
		if dead:
			if seen.has(id):
				push(kind, ("DOWN  " if kind == KILL else "WRECKED  ") + String(seen[id]), now)
				seen.erase(id)
			continue
		if near and n3.visible:
			live[id] = true
			if not seen.has(id):
				seen[id] = enemy_name(n3) if kind == KILL else _vehicle_name(n3)
	for id in seen.keys():                                    # freed or recycled bodies drop out silently
		if not live.has(id):
			var o := instance_from_id(id)
			if o == null or not is_instance_valid(o) or (o as Node3D).get("dead") != true:
				seen.erase(id)


static func _vehicle_name(n: Node) -> String:
	var k: Variant = n.get("kind")
	return VehicleSpecs.name_of(k).to_upper() if k is StringName else "VEHICLE"


## Draws the feed right-aligned, its first line at (right, y); returns the bottom. Uses the Hud's queued primitives so it adds no draw call of its own.
func draw(hud: Hud, c: Control, font: Font, right: float, y: float, s: float, now: float) -> float:
	var vis := visible_lines(now)
	if vis.is_empty():
		return y
	var size := int(UiUtil.BAR_LABEL * s * 0.8)
	var lh := 30.0 * s
	for l: Dictionary in vis:
		var col: Color = KIND_COL.get(l["kind"], Color.WHITE)
		var a: float = l["alpha"]
		var label := String(l["label"])
		var w := minf(font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 46.0 * s, 330.0 * s)
		var r := Rect2(right - w, y, w, lh - 4.0 * s)
		hud._rect(c, r, Color(UiUtil.PLATE, 0.7 * a))
		hud._rect(c, Rect2(r.position.x, r.position.y, 3.0 * s, r.size.y), Color(col, a))
		hud._sprite(c, KIND_SPRITE.get(l["kind"], &"disc"), Rect2(r.position.x + 9.0 * s, r.position.y + r.size.y * 0.5 - 6.0 * s, 12.0 * s, 12.0 * s), Color(col, a))        # the kind is a small shape, not a word (a second "GOT" per frame would be a repeat)
		hud._text(c, font, Vector2(r.position.x + 28.0 * s, r.position.y + r.size.y - 6.0 * s), label, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 32.0 * s, UiUtil.fit_size(font, label, r.size.x - 34.0 * s, size), Color(1, 1, 1, 0.97 * a), 0.0)
		y += lh
	return y
