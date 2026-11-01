class_name VendorLogic
extends RefCounted
## What a vendor sells and how a purchase works. Pure rules on top of Progress (credits, upgrades, weapons, reputation discount) and the player: no nodes, no UI.
## `rows(type)` gives one Dictionary per stock item for the screen: {id, name, kind, price, state, label, sub}: state is "buy" (affordable), "poor" (not enough credits), "done"
## (owned / maxed / full), "locked" (ammo for a weapon you do not own). `buy(type, id)` returns {ok, msg}.

const DRINK_HP := 25.0
const RUMOUR_HEALTH_NEED := 0.0


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
	for it: Dictionary in InteriorData.STOCK.get(type, []):
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
			"heal", "energy", "drink", "rumour":
				row["price"] = discount_price(int(it["price"]))
				row["sub"] = _sub_of(str(it["kind"]))
		if row["state"] == "buy" and int(row["price"]) > credits:
			row["state"] = "poor"
		if row["label"] == "":
			row["label"] = "BUY  %d" % int(row["price"])
		out.append(row)
	return out


static func _sub_of(kind: String) -> String:
	var pl := Game.player as Player
	match kind:
		"heal": return "HP %d / %d" % [int(pl.hp), int(pl.max_hp)] if pl != null else ""
		"energy": return "COHERENCE %d / %d" % [int(pl.energy), int(pl.max_energy)] if pl != null else ""
		"drink": return "RESTORES %d HP" % int(DRINK_HP)
		"rumour": return "STORY OR A CONTRACT HINT"
	return ""


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
		"upgrade":
			if not p.buy(id):
				return {"ok": false, "msg": "NOT ENOUGH CREDITS"}
		"weapon":
			if not p.buy_weapon(id):
				return {"ok": false, "msg": "NOT ENOUGH CREDITS"}
		"ammo":
			var wid: StringName = (InteriorData.STOCK[type] as Array)[_index_of(type, id)]["weapon"]
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
			pl.heal(DRINK_HP)
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
	var arr: Array = InteriorData.STOCK[type]
	for i in arr.size():
		if arr[i]["id"] == id:
			return i
	return 0
