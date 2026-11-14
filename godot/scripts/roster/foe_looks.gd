class_name FoeLooks
extends RefCounted
## The LOOKS of the humanoid roster enemies (wave 113, enemy look v3): 13 armoured humans in two camps, each with its own head, shoulders, back and hands so the threat reads at 40 m, a weapon
## id (resolved through FoeArms / the weapon registry), a body scale and three colour variants. Pure data and static functions; the geometry is the Blender kit (FoeKit).
##   CONTRACT   mercenaries (warm tan / olive / charcoal paint, orange tape, amber lenses): RIFLEMAN (boonie, goggles), SHOTGUNNER (skull mask, shell bandolier), ROCKETEER (launcher tube over the shoulder),
##              MEDIC (white pack with a green cross), OFFICER (peaked cap, long coat, radio whip), MARKSMAN (scarf, cape, boonie).
##   AUTHORITY  troopers in hive-grade armour (graphite and navy plates, a white-blue stripe, a lit visor): TROOPER, RIOT (shield), HEAVY (wide, power cell on the back), BREACHER (gas mask, charges),
##              GHOST (hooded ghillie cloak, one lens), DRONE OPERATOR (antenna, drone rack, wrist screen), ENGINEER (hard hat, turret pack with a tripod).
## Variants: CONTRACT desert / woodland / urban, AUTHORITY graphite / navy / black. The role glow (visor, lenses, weak point) is the colour of the look.

const SHADER := preload("res://assets/shaders/foe_body.gdshader")
const CONTRACT := &"contract"
const AUTHORITY := &"authority"

const TABLE := {
	&"merc_rifle": {"name": "MERC RIFLEMAN", "faction": CONTRACT, "weapon": &"battle", "glow": Color(1.0, 0.72, 0.2), "scale": Vector3(1.0, 1.0, 1.0), "skin": Color(0.62, 0.45, 0.36)},
	&"merc_shotgun": {"name": "MERC SHOTGUNNER", "faction": CONTRACT, "weapon": &"scatter", "glow": Color(1.0, 0.25, 0.15), "scale": Vector3(1.12, 1.0, 1.12), "skin": Color(0.5, 0.36, 0.28)},
	&"merc_rocket": {"name": "MERC ROCKETEER", "faction": CONTRACT, "weapon": &"rocket", "glow": Color(1.0, 0.42, 0.1), "scale": Vector3(1.08, 1.02, 1.08), "skin": Color(0.66, 0.48, 0.38)},
	&"merc_medic": {"name": "FIELD MEDIC", "faction": CONTRACT, "weapon": &"vector", "glow": Color(0.3, 1.0, 0.5), "scale": Vector3(0.98, 1.0, 0.98), "skin": Color(0.7, 0.52, 0.42)},
	&"merc_officer": {"name": "MERC OFFICER", "faction": CONTRACT, "weapon": &"magnum", "glow": Color(1.0, 0.85, 0.3), "scale": Vector3(1.02, 1.04, 1.02), "skin": Color(0.6, 0.43, 0.35)},
	&"merc_sniper": {"name": "MERC MARKSMAN", "faction": CONTRACT, "weapon": &"bolt", "glow": Color(0.4, 1.0, 1.0), "scale": Vector3(0.96, 1.03, 0.96), "skin": Color(0.55, 0.4, 0.32)},
	&"auth_rifle": {"name": "AUTHORITY TROOPER", "faction": AUTHORITY, "weapon": &"carbine", "glow": Color(1.0, 0.2, 0.22), "scale": Vector3(1.0, 1.04, 1.0), "skin": Color(0.5, 0.36, 0.3)},
	&"auth_riot": {"name": "RIOT TROOPER", "faction": AUTHORITY, "weapon": &"mpistol", "glow": Color(0.3, 0.9, 1.0), "scale": Vector3(1.1, 1.04, 1.1), "skin": Color(0.5, 0.36, 0.3)},
	&"auth_heavy": {"name": "HEAVY GUNNER", "faction": AUTHORITY, "weapon": &"lmg", "glow": Color(1.0, 0.14, 0.1), "scale": Vector3(1.22, 1.1, 1.2), "skin": Color(0.5, 0.36, 0.3)},
	&"auth_breacher": {"name": "BREACHER", "faction": AUTHORITY, "weapon": &"breacher", "glow": Color(1.0, 0.5, 0.1), "scale": Vector3(1.04, 1.0, 1.04), "skin": Color(0.5, 0.36, 0.3)},
	&"auth_ghost": {"name": "GHOST SNIPER", "faction": AUTHORITY, "weapon": &"amr", "glow": Color(0.2, 1.0, 0.9), "scale": Vector3(0.96, 1.02, 0.96), "skin": Color(0.5, 0.36, 0.3)},
	&"auth_drone": {"name": "DRONE OPERATOR", "faction": AUTHORITY, "weapon": &"swarm", "glow": Color(1.0, 0.3, 0.9), "scale": Vector3(0.96, 1.02, 0.96), "skin": Color(0.5, 0.36, 0.3)},
	&"auth_engineer": {"name": "ENGINEER", "faction": AUTHORITY, "weapon": &"flux", "glow": Color(1.0, 0.82, 0.1), "scale": Vector3(1.06, 1.0, 1.06), "skin": Color(0.5, 0.36, 0.3)},
}
const IDS: Array[StringName] = [&"merc_rifle", &"merc_shotgun", &"merc_rocket", &"merc_medic", &"merc_officer", &"merc_sniper",
	&"auth_rifle", &"auth_riot", &"auth_heavy", &"auth_breacher", &"auth_ghost", &"auth_drone", &"auth_engineer"]

## Palette per camp and variant: plate_a, plate_b, trim, fabric_a, fabric_b, jacket, pants (and cloth for the ghillie).
const PALETTES := {
	&"contract": [
		{"plate_a": Color(0.4, 0.33, 0.21), "plate_b": Color(0.24, 0.18, 0.12), "trim": Color(1.0, 0.5, 0.1), "fabric_a": Color(0.42, 0.37, 0.25), "fabric_b": Color(0.17, 0.17, 0.11),
			"jacket": Color(0.36, 0.33, 0.22), "pants": Color(0.22, 0.21, 0.15), "cloth": Color(0.3, 0.3, 0.18)},
		{"plate_a": Color(0.23, 0.28, 0.15), "plate_b": Color(0.08, 0.09, 0.08), "trim": Color(0.95, 0.8, 0.15), "fabric_a": Color(0.19, 0.24, 0.13), "fabric_b": Color(0.1, 0.12, 0.08),
			"jacket": Color(0.17, 0.21, 0.11), "pants": Color(0.12, 0.14, 0.09), "cloth": Color(0.16, 0.22, 0.1)},
		{"plate_a": Color(0.17, 0.18, 0.2), "plate_b": Color(0.42, 0.08, 0.07), "trim": Color(0.95, 0.15, 0.1), "fabric_a": Color(0.22, 0.22, 0.24), "fabric_b": Color(0.07, 0.07, 0.08),
			"jacket": Color(0.14, 0.14, 0.16), "pants": Color(0.09, 0.09, 0.1), "cloth": Color(0.2, 0.2, 0.22)},
	],
	&"authority": [
		{"plate_a": Color(0.2, 0.23, 0.3), "plate_b": Color(0.1, 0.11, 0.15), "trim": Color(0.25, 0.85, 1.0), "fabric_a": Color(0.12, 0.13, 0.16), "fabric_b": Color(0.07, 0.08, 0.1),
			"jacket": Color(0.11, 0.12, 0.16), "pants": Color(0.07, 0.08, 0.1), "cloth": Color(0.12, 0.14, 0.16)},
		{"plate_a": Color(0.1, 0.19, 0.4), "plate_b": Color(0.72, 0.76, 0.82), "trim": Color(0.3, 0.6, 1.0), "fabric_a": Color(0.08, 0.12, 0.24), "fabric_b": Color(0.05, 0.07, 0.14),
			"jacket": Color(0.07, 0.11, 0.24), "pants": Color(0.05, 0.07, 0.14), "cloth": Color(0.1, 0.14, 0.2)},
		{"plate_a": Color(0.07, 0.07, 0.08), "plate_b": Color(0.22, 0.22, 0.24), "trim": Color(1.0, 0.62, 0.1), "fabric_a": Color(0.1, 0.1, 0.11), "fabric_b": Color(0.05, 0.05, 0.06),
			"jacket": Color(0.08, 0.08, 0.09), "pants": Color(0.05, 0.05, 0.06), "cloth": Color(0.1, 0.1, 0.1)},
	],
}
## Role glow of a variant: the third variant of an authority look glows amber, the second blue-white (a squad does not look like one paint job); contract looks keep their role colour.
const AUTH_GLOW := [Color(1.0, 0.2, 0.22), Color(0.35, 0.75, 1.0), Color(1.0, 0.55, 0.12)]


static func has(id: StringName) -> bool:
	return TABLE.has(id)


static func data(id: StringName) -> Dictionary:
	return TABLE[id] if TABLE.has(id) else {}


static func faction_of(id: StringName) -> StringName:
	return StringName(TABLE[id]["faction"]) if TABLE.has(id) else &""


static func title(id: StringName) -> String:
	return String(TABLE[id]["name"]) if TABLE.has(id) else ""


static func weapon_of(id: StringName) -> StringName:
	return StringName(TABLE[id]["weapon"]) if TABLE.has(id) else &"carbine"


static func variants() -> int:
	return 3


## The palette dictionary of a look and variant (colours, glow).
static func palette(id: StringName, variant: int) -> Dictionary:
	var d := data(id)
	if d.is_empty():
		return {}
	var fac: StringName = d["faction"]
	var v := clampi(variant, 0, 2)
	var p: Dictionary = (PALETTES[fac] as Array)[v].duplicate()
	var glow: Color = d["glow"]
	if fac == AUTHORITY and id != &"auth_riot" and id != &"auth_ghost" and id != &"auth_drone" and id != &"auth_engineer" and id != &"auth_breacher":
		glow = AUTH_GLOW[v]
	elif fac == AUTHORITY and v > 0:
		glow = glow.lerp(AUTH_GLOW[v], 0.35)
	p["glow"] = glow
	p["weak"] = Color(1.0, 0.62, 0.12)
	p["skin"] = d["skin"]
	return p


static func make_material(id: StringName, variant: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.resource_name = "FoeBody"
	apply_palette(m, id, variant)
	return m


static func apply_palette(m: ShaderMaterial, id: StringName, variant: int) -> void:
	var p := palette(id, variant)
	if p.is_empty():
		return
	m.set_shader_parameter(&"plate_a", p["plate_a"])
	m.set_shader_parameter(&"plate_b", p["plate_b"])
	m.set_shader_parameter(&"trim", p["trim"])
	m.set_shader_parameter(&"fabric_a", p["fabric_a"])
	m.set_shader_parameter(&"fabric_b", p["fabric_b"])
	m.set_shader_parameter(&"cloth_g", p["cloth"])
	m.set_shader_parameter(&"jacket", p["jacket"])
	m.set_shader_parameter(&"pants", p["pants"])
	m.set_shader_parameter(&"skin", p["skin"])
	m.set_shader_parameter(&"glow_col", p["glow"])
	m.set_shader_parameter(&"weak_col", p["weak"])
	var g := p["glow"] as Color
	m.set_shader_parameter(&"dust", Vector3(g.r, g.g, g.b))
	m.set_shader_parameter(&"body_h", 1.95)
