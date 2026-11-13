class_name VendorLogic
extends RefCounted
## What a vendor sells and how a purchase works. Pure rules on top of Progress (credits, upgrades, weapons, reputation discount) and the player: no nodes, no UI.
## `rows(type)` gives one Dictionary per stock item for the screen: {id, name, kind, price, state, label, sub}: state is "buy" (affordable), "poor" (not enough credits), "done"
## (owned / maxed / full), "locked" (ammo for a weapon you do not own). `buy(type, id)` returns {ok, msg}.

const DRINK_HP := 25.0
const RUMOUR_HEALTH_NEED := 0.0
const Dlg := preload("res://scripts/npc/npc_dialogue.gd")
const DlgData := preload("res://scripts/npc/npc_dialogue_data.gd")
const SPECIAL_ID := &"special"


static func _prog() -> Progress:
	return Game.progress as Progress


static func discount_price(base: int) -> int:
	var p := _prog()
	var disc := Progress.rep_discount(p.reputation) if p != null else 0.0
	return maxi(5, int(roundf(float(base) * (1.0 - disc) / 5.0)) * 5)


static func rows(type: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var p := _prog()
	var credits := p.credits if p != null else 0
	for it: Dictionary in InteriorData.stock(type):
		var row := {"id": it["id"], "name": it["name"], "kind": it["kind"], "price": 0, "state": "buy", "label": "", "sub": ""}
		match str(it["kind"]):
			"upgrade":
				var id: StringName = it["id"]
				var lvl := p.level(id) if p != null else 0
				if lvl >= Upgrades.MAX_LEVEL:
					row["state"] = "done"
					row["label"] = "MAX"
				else:
					row["price"] = p.price(id) if p != null else 0
				row["sub"] = Upgrades.effect_text(id, lvl)
			"weapon":
				var wid: StringName = it["id"]
				if WeaponDefs.is_unlocked(wid):
					row["state"] = "done"
					row["label"] = "OWNED"
				else:
					row["price"] = p.weapon_price(wid) if p != null else 0
				row["sub"] = "%d ROUND MAG" % int(WeaponDefs.def(wid)["mag"])
			"ammo":
				var wid: StringName = it["weapon"]
				row["price"] = discount_price(int(it["price"]))
				if not WeaponDefs.is_unlocked(wid):
					row["state"] = "locked"
					row["label"] = "NO WEAPON"
				elif _reserve_full(wid):
					row["state"] = "done"
					row["label"] = "FULL"
				row["sub"] = "RESERVE %d" % _reserve(wid)
			"parts":
				row["price"] = discount_price(Crafting.part_price(&"scrap", null) + Crafting.part_price(&"alloy", null))
				row["sub"] = "SCRAP %d  ALLOY %d" % [Crafting.part_count(&"scrap"), Crafting.part_count(&"alloy")]
			"blueprint":
				var nb := _next_blueprint()
				if nb == &"":
					row["state"] = "done"
					row["label"] = "ALL KNOWN"
				else:
					row["price"] = discount_price(Economy.blueprint_price(nb))
					row["name"] = "BLUEPRINT  %s" % Crafting.bp_title(nb)
				row["sub"] = "WORKBENCH RECIPE"
			"heal", "energy", "drink", "rumour":
				row["price"] = discount_price(int(it["price"]))
				row["sub"] = _sub_of(str(it["kind"]))
		if row["state"] == "buy" and int(row["price"]) > credits:
			row["state"] = "poor"
		if row["label"] == "":
			row["label"] = "BUY  %d" % int(row["price"])
		out.append(row)
	var sp := special(type)
	if not sp.is_empty():
		var price := discount_price(int(sp["price"]))
		var st := "buy" if price <= credits else "poor"
		out.append({"id": SPECIAL_ID, "name": sp["name"], "kind": "drink", "price": price, "state": st, "label": "BUY  %d" % price, "sub": "RESTORES %d HP" % int(sp["hp"]), "hp": int(sp["hp"])})
	return out


## The rotating special on the shelf of `type` (changes with every door the hero walks through): {name, hp, price}, empty for a type without one.
static func special(type: StringName) -> Dictionary:
	if not DlgData.ROTATION.has(type):
		return {}
	var e: Dictionary = (DlgData.ROTATION[type] as Array)[Dlg.rotation_index(type)]
	return {"name": (e["name"] as Array)[0], "hp": e["hp"], "price": e["price"]}


static func _sub_of(kind: String) -> String:
	var pl := Game.player as Player
	match kind:
		"heal": return "HP %d / %d" % [int(pl.hp), int(pl.max_hp)] if pl != null else ""
		"energy": return "COHERENCE %d / %d" % [int(pl.energy), int(pl.max_energy)] if pl != null else ""
		"drink": return "RESTORES %d HP" % int(DRINK_HP)
		"rumour": return "STORY OR A CONTRACT HINT"
	return ""


## The blueprint a tech vendor sells next: the cheapest one you do not know yet (&"" when you know them all).
static func _next_blueprint() -> StringName:
	var best: StringName = &""
	var best_p := 1 << 30
	for bp: StringName in Crafting.unknown_bps():
		var pr := Economy.blueprint_price(bp)
		if pr < best_p:
			best_p = pr
			best = bp
	return best


static func _weapon_node() -> PlayerWeapon:
	var pl := Game.player
	if is_instance_valid(pl) and pl.get(&"weapon") is PlayerWeapon:
		return pl.get(&"weapon") as PlayerWeapon
	return null


static func _reserve(wid: StringName) -> int:
	var w := _weapon_node()
	return w.reserve_of(wid) if w != null else 0


static func _reserve_full(wid: StringName) -> bool:
	return _reserve(wid) >= int(WeaponDefs.def(wid)["reserve"]) * 2


## Buy `id` from a vendor of `type`. Never throws: a bad id or a missing module returns {ok: false}.
static func buy(type: StringName, id: StringName) -> Dictionary:
	var p := _prog()
	var row := {}
	for r: Dictionary in rows(type):
		if r["id"] == id:
			row = r
			break
	if row.is_empty() or p == null:
		return {"ok": false, "msg": "NOT FOR SALE"}
	match str(row["state"]):
		"done":
			return {"ok": false, "msg": str(row["label"])}
		"locked":
			return {"ok": false, "msg": "YOU DO NOT OWN THAT WEAPON"}
		"poor":
			Sfx.play(&"ui_deny")
			return {"ok": false, "msg": "NOT ENOUGH CREDITS"}
	var price := int(row["price"])
	var pl := Game.player as Player
	match str(row["kind"]):
		"parts":
			if not p.spend(price):
				return {"ok": false, "msg": "NOT ENOUGH CREDITS"}
			Crafting.add_part(&"scrap", int(Economy.CRAFT_PART_BUNDLE[&"scrap"]))
			Crafting.add_part(&"alloy", int(Economy.CRAFT_PART_BUNDLE[&"alloy"]))
			p.changed.emit()
		"blueprint":
			var nb := _next_blueprint()
			if nb == &"" or not p.spend(price):
				return {"ok": false, "msg": "NOT ENOUGH CREDITS"}
			Crafting.learn(nb)
			p.changed.emit()
		"upgrade":
			if not p.buy(id):
				return {"ok": false, "msg": "NOT ENOUGH CREDITS"}
		"weapon":
			if not p.buy_weapon(id):
				return {"ok": false, "msg": "NOT ENOUGH CREDITS"}
		"ammo":
			var wid: StringName = InteriorData.stock(type)[_index_of(type, id)]["weapon"]
			if not p.spend(price):
				return {"ok": false, "msg": "NOT ENOUGH CREDITS"}
			var w := _weapon_node()
			if w != null:
				w.grant(wid)
		"heal":
			if pl == null or not p.spend(price):
				return {"ok": false, "msg": "NOT ENOUGH CREDITS"}
			pl.hp = pl.max_hp
		"energy":
			if pl == null or not p.spend(price):
				return {"ok": false, "msg": "NOT ENOUGH CREDITS"}
			pl.energy = pl.max_energy
		"drink":
			if pl == null or not p.spend(price):
				return {"ok": false, "msg": "NOT ENOUGH CREDITS"}
			pl.heal(float(row.get("hp", DRINK_HP)))
		"rumour":
			if not p.spend(price):
				return {"ok": false, "msg": "NOT ENOUGH CREDITS"}
			var ig := InteriorGameplay.instance
			var text := ig.tell_rumour() if ig != null else InteriorData.RUMOURS[0]
			Sfx.play(&"ui_purchase")
			return {"ok": true, "msg": "RUMOUR  BOUGHT", "rumour": text}
	Sfx.play(&"ui_purchase")
	return {"ok": true, "msg": "BOUGHT  %s" % str(row["name"])}


static func _index_of(type: StringName, id: StringName) -> int:
	var arr: Array = InteriorData.stock(type)
	for i in arr.size():
		if arr[i]["id"] == id:
			return i
	return 0
