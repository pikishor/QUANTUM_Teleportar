class_name WeaponModelsBlast
extends RefCounted
## In-hand models of the 46 hand-carried entries of the blast arsenal (wave 113): one procedural mesh and one draw each (the shared weapon_look shader, boxes and cylinders like WeaponModels), so a player
## tells a pump launcher from a bunker buster, a frag from a fog can and a trip mine from a remote charge by looking at them. Frame: origin = muzzle, barrel toward -Z, body toward +Z, y up. The Blender
## weapon kit of wave 114 replaces these with modelled meshes (same ids, same frame). WeaponModels._procedural calls `build` for every def with a `bid`.

const GUN := WeaponModels.GUN
const POLY := WeaponModels.POLY
const DARK := WeaponModels.DARK
const STEEL := WeaponModels.STEEL
const BRASS := WeaponModels.BRASS
const OLIVE := Color(0.2, 0.24, 0.17)
const RED := Color(0.62, 0.12, 0.1)


static func build(b: WeaponModels._Builder, id: StringName, glow: Color) -> void:
	var d := WeaponDefs.def(id)
	match StringName(d.get("family", &"launcher")):
		&"grenade":
			_grenade(b, id, glow)
		&"mine":
			_mine(b, id, glow)
		&"strike":
			_designator(b, id, glow)
		_:
			_launcher(b, id, glow)


static func _ball(b: WeaponModels._Builder, c: Vector3, r: float, col: Color, g := 0.0) -> void:
	b.cyl(c, r, r * 1.5, col, g, 10)                                                          # a stack of three discs reads as a ball at this size
	b.cyl(c, r * 1.12, r * 0.7, col, g, 10)
	b.cyl(c + Vector3(0.0, 0.0, 0.0), r * 0.8, r * 2.0, col, g, 8)


static func _grenade(b: WeaponModels._Builder, id: StringName, glow: Color) -> void:
	var c := Vector3(0.0, 0.0, 0.16)
	match id:
		&"gr_frag":
			_ball(b, c, 0.062, OLIVE)
			b.box(c + Vector3(0.0, 0.07, 0.0), Vector3(0.03, 0.03, 0.03), STEEL)                    # the fuse head and the lever
			b.box(c + Vector3(0.0, 0.085, 0.03), Vector3(0.012, 0.01, 0.07), STEEL)
			b.cyl(c, 0.066, 0.012, DARK, 0.0, 10)
		&"gr_tick":
			_ball(b, c, 0.058, GUN)
			for k in 8:
				var a := TAU * float(k) / 8.0
				b.box(c + Vector3(cos(a) * 0.065, sin(a) * 0.065, 0.0), Vector3(0.012, 0.012, 0.03), glow, 0.9)
			b.cyl(c, 0.04, 0.12, glow, 0.5, 8)
		&"gr_scatter":
			b.cyl(c, 0.075, 0.2, OLIVE, 0.0, 12)
			for k in 3:
				b.cyl(c + Vector3(0.0, 0.0, -0.06 + 0.06 * float(k)), 0.078, 0.014, DARK, 0.0, 12)
			b.cyl(c + Vector3(0.0, 0.0, -0.11), 0.05, 0.03, glow, 0.8, 10)
		&"gr_ember":
			b.cyl(c, 0.05, 0.16, Color(0.3, 0.2, 0.08), 0.0, 10)                                    # a bottle: body, neck, a burning rag
			b.cyl(c + Vector3(0.0, 0.0, -0.1), 0.025, 0.06, Color(0.3, 0.2, 0.08), 0.0, 8)
			b.cyl(c + Vector3(0.0, 0.0, -0.15), 0.02, 0.05, glow, 1.0, 8)
			b.cyl(c, 0.052, 0.07, glow, 0.5, 10)
		&"gr_blinder":
			b.cyl(c, 0.055, 0.17, STEEL, 0.0, 12)
			b.cyl(c + Vector3(0.0, 0.0, -0.09), 0.045, 0.012, Color(1.0, 1.0, 0.9), 1.0, 12)
			b.cyl(c + Vector3(0.0, 0.0, 0.07), 0.058, 0.014, DARK, 0.0, 12)
		&"gr_fog":
			b.cyl(c, 0.06, 0.2, Color(0.5, 0.52, 0.56), 0.0, 12)
			b.cyl(c + Vector3(0.0, 0.0, -0.1), 0.04, 0.03, DARK, 0.0, 10)
			for k in 4:
				b.box(c + Vector3(cos(TAU * float(k) / 4.0) * 0.06, sin(TAU * float(k) / 4.0) * 0.06, -0.06), Vector3(0.012, 0.012, 0.05), glow, 0.6)
		&"gr_spark":
			_ball(b, c, 0.058, DARK)
			for k in 3:
				b.cyl(c + Vector3(0.0, 0.0, -0.035 + 0.035 * float(k)), 0.066, 0.012, glow, 1.0, 12)
		&"gr_well":
			_ball(b, c, 0.062, POLY)
			_ball(b, c, 0.04, glow, 1.0)
			b.cyl(c, 0.07, 0.01, glow, 0.8, 12)
		&"gr_still":
			b.cyl(c, 0.058, 0.17, Color(0.55, 0.75, 0.85), 0.0, 12)
			b.cyl(c, 0.062, 0.03, glow, 1.0, 12)
			b.cyl(c + Vector3(0.0, 0.0, -0.09), 0.04, 0.02, glow, 0.8, 12)
		&"gr_arc":
			b.cyl(c, 0.05, 0.18, DARK, 0.0, 10)
			for k in 4:
				var a := TAU * float(k) / 4.0
				b.box(c + Vector3(cos(a) * 0.055, sin(a) * 0.055, -0.1), Vector3(0.01, 0.01, 0.05), glow, 1.0)
			b.cyl(c + Vector3(0.0, 0.0, 0.0), 0.056, 0.012, glow, 0.9, 10)
		&"gr_rattle":
			b.cyl(c, 0.052, 0.13, Color(0.7, 0.55, 0.2), 0.0, 10)
			for k in 3:
				b.box(c + Vector3(0.0, 0.0, -0.03 + 0.03 * float(k)), Vector3(0.1, 0.01, 0.01), DARK)
			b.cyl(c + Vector3(0.0, 0.0, -0.075), 0.03, 0.02, glow, 0.8, 8)
		_:                                                                                          # gr_collapse and anything new
			_ball(b, c, 0.064, POLY)
			b.cyl(c, 0.075, 0.012, glow, 1.0, 14)
			b.cyl(c + Vector3(0.0, 0.0, 0.0), 0.012, 0.16, glow, 0.9, 6, Basis.from_euler(Vector3(0.0, 0.0, PI * 0.5)))
	b.box(Vector3(0.0, -0.045, 0.26), Vector3(0.05, 0.03, 0.14), DARK)                             # the fingers' rest and the lanyard


static func _mine(b: WeaponModels._Builder, id: StringName, glow: Color) -> void:
	var c := Vector3(0.0, -0.02, 0.2)
	match id:
		&"mn_prox":
			b.cyl(c, 0.12, 0.05, OLIVE, 0.0, 14, Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)))
			b.cyl(c + Vector3(0.0, 0.03, 0.0), 0.04, 0.02, glow, 1.0, 10, Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)))
		&"mn_trip":
			b.box(c, Vector3(0.09, 0.07, 0.12), GUN)
			b.cyl(c + Vector3(0.0, 0.0, -0.07), 0.018, 0.04, glow, 1.0, 8)
			b.box(c + Vector3(0.0, 0.05, 0.02), Vector3(0.02, 0.02, 0.04), RED)
		&"mn_directional":
			b.box(c, Vector3(0.18, 0.1, 0.03), OLIVE)
			for k in 5:
				b.box(c + Vector3(-0.07 + 0.035 * float(k), 0.0, -0.025), Vector3(0.012, 0.07, 0.02), STEEL)
			b.box(c + Vector3(0.0, -0.06, 0.02), Vector3(0.14, 0.015, 0.03), DARK)
			b.box(c + Vector3(0.0, 0.06, 0.02), Vector3(0.1, 0.02, 0.02), glow, 0.7)
		&"mn_gravity":
			b.cyl(c, 0.1, 0.05, POLY, 0.0, 14, Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)))
			b.cyl(c + Vector3(0.0, 0.03, 0.0), 0.07, 0.012, glow, 1.0, 14, Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)))
			b.cyl(c + Vector3(0.0, 0.04, 0.0), 0.025, 0.02, Color(1.0, 0.9, 1.0), 1.0, 8, Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)))
		&"mn_c4":
			b.box(c, Vector3(0.14, 0.05, 0.1), Color(0.55, 0.52, 0.42))
			b.box(c + Vector3(0.0, 0.03, 0.0), Vector3(0.05, 0.012, 0.03), glow, 1.0)             # the timer
			b.box(c + Vector3(0.05, 0.03, 0.03), Vector3(0.02, 0.012, 0.02), RED, 0.8)
		&"mn_remote":
			b.box(c, Vector3(0.14, 0.05, 0.1), Color(0.5, 0.5, 0.46))
			b.box(c + Vector3(0.0, 0.03, 0.0), Vector3(0.03, 0.012, 0.03), glow, 1.0)
			b.cyl(c + Vector3(0.05, 0.08, 0.03), 0.004, 0.12, STEEL, 0.0, 6, Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)))          # the aerial
		&"mn_satchel":
			b.box(c, Vector3(0.16, 0.11, 0.07), OLIVE)
			b.box(c + Vector3(0.0, 0.0, -0.04), Vector3(0.17, 0.12, 0.012), Color(0.14, 0.17, 0.12))
			b.box(c + Vector3(0.0, 0.065, 0.0), Vector3(0.012, 0.05, 0.075), DARK)
			b.box(c + Vector3(0.05, 0.0, 0.04), Vector3(0.025, 0.025, 0.012), glow, 0.9)
		&"mn_shaped":
			b.cyl(c, 0.075, 0.1, Color(0.55, 0.52, 0.42), 0.0, 12)                                  # a cone behind a copper liner
			b.cyl(c + Vector3(0.0, 0.0, -0.055), 0.065, 0.012, BRASS, 0.0, 12)
			b.box(c + Vector3(0.0, 0.0, 0.07), Vector3(0.05, 0.05, 0.03), DARK)
			b.box(c + Vector3(0.0, 0.0, 0.09), Vector3(0.012, 0.012, 0.012), glow, 1.0)
		&"mn_bounce":
			b.cyl(c, 0.09, 0.05, POLY, 0.0, 14, Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)))
			b.cyl(c + Vector3(0.0, 0.035, 0.0), 0.05, 0.03, STEEL, 0.0, 10, Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)))
			b.cyl(c + Vector3(0.0, 0.06, 0.0), 0.02, 0.02, glow, 1.0, 8, Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)))
		_:                                                                                          # mn_emp
			b.cyl(c, 0.1, 0.045, DARK, 0.0, 14, Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)))
			b.cyl(c + Vector3(0.0, 0.03, 0.0), 0.07, 0.012, glow, 1.0, 14, Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)))
			for k in 4:
				var a := TAU * float(k) / 4.0
				b.box(c + Vector3(cos(a) * 0.09, 0.03, sin(a) * 0.09), Vector3(0.012, 0.02, 0.012), glow, 1.0)
	b.box(Vector3(0.0, -0.065, 0.27), Vector3(0.05, 0.03, 0.14), DARK)


static func _designator(b: WeaponModels._Builder, id: StringName, glow: Color) -> void:
	# a squat marker gun: a tube that throws a smoke canister, a laser sight and a glowing tablet on the side (the colour of the strike)
	b.cyl(Vector3(0.0, 0.0, 0.3), 0.055, 0.6, GUN, 0.0, 10)
	b.cyl(Vector3(0.0, 0.0, 0.02), 0.07, 0.04, STEEL, 0.0, 10)
	b.cyl(Vector3(0.0, 0.0, 0.0), 0.058, 0.012, glow, 1.0, 10)
	b.box(Vector3(0.0, -0.1, 0.4), Vector3(0.04, 0.09, 0.05), DARK, 0.0, -0.3)                      # grip
	b.box(Vector3(0.0, -0.07, 0.2), Vector3(0.036, 0.07, 0.05), POLY)
	b.box(Vector3(0.0, 0.1, 0.38), Vector3(0.1, 0.012, 0.13), POLY)                                  # the tablet on top
	b.box(Vector3(0.0, 0.108, 0.38), Vector3(0.085, 0.006, 0.1), glow, 0.85)
	b.box(Vector3(0.0, 0.07, 0.38), Vector3(0.012, 0.05, 0.012), DARK)
	var slot := String(id).hash() % 5
	for k in 3 + slot % 3:                                                                           # one mark per shell of the pattern on the side
		b.box(Vector3(0.062, 0.0, 0.2 + 0.07 * float(k)), Vector3(0.008, 0.03, 0.04), glow, 0.9)
	if String(id).contains("air") or String(id).contains("carpet"):
		b.box(Vector3(0.0, 0.0, 0.62), Vector3(0.16, 0.012, 0.1), STEEL)                              # a wing on the back: the call goes to an aircraft
	if String(id).contains("smoke") or String(id).contains("supply"):
		b.cyl(Vector3(0.0, 0.0, 0.3), 0.062, 0.1, Color(0.5, 0.52, 0.56), 0.0, 10)


static func _launcher(b: WeaponModels._Builder, id: StringName, glow: Color) -> void:
	match id:
		&"la_pump":
			b.cyl(Vector3(0.0, 0.0, 0.3), 0.06, 0.6, GUN, 0.0, 12)
			b.cyl(Vector3(0.0, -0.075, 0.34), 0.03, 0.46, STEEL, 0.0, 8)                            # the tube magazine under the barrel
			b.box(Vector3(0.0, -0.06, 0.42), Vector3(0.06, 0.06, 0.12), POLY)                       # the pump
			b.cyl(Vector3(0.0, 0.0, 0.01), 0.07, 0.03, STEEL, 0.0, 12)
			b.box(Vector3(0.0, 0.0, 0.7), Vector3(0.08, 0.1, 0.2), POLY)
			b.box(Vector3(0.0, -0.1, 0.66), Vector3(0.04, 0.1, 0.05), DARK, 0.0, -0.3)
		&"la_revolver":
			b.cyl(Vector3(0.0, 0.0, 0.2), 0.05, 0.4, GUN, 0.0, 10)
			b.cyl(Vector3(0.0, 0.0, 0.46), 0.115, 0.26, POLY, 0.0, 12)                              # the drum
			for k in 6:
				var a := TAU * float(k) / 6.0
				b.cyl(Vector3(cos(a) * 0.08, sin(a) * 0.08, 0.46), 0.03, 0.27, STEEL, 0.0, 8)
			b.cyl(Vector3(0.0, 0.0, 0.46), 0.1, 0.02, glow, 0.8, 12)
			b.box(Vector3(0.0, -0.12, 0.66), Vector3(0.04, 0.12, 0.05), DARK, 0.0, -0.3)
			b.box(Vector3(0.0, 0.06, 0.7), Vector3(0.04, 0.04, 0.1), POLY)
		&"la_rotary":
			for k in 6:
				var a := TAU * float(k) / 6.0
				b.cyl(Vector3(cos(a) * 0.05, sin(a) * 0.05, 0.22), 0.026, 0.44, STEEL, 0.0, 8)
			b.cyl(Vector3(0.0, 0.0, 0.03), 0.085, 0.03, DARK, 0.0, 12)
			b.cyl(Vector3(0.0, 0.0, 0.55), 0.11, 0.24, GUN, 0.0, 12)
			b.cyl(Vector3(0.0, 0.0, 0.45), 0.1, 0.02, glow, 0.8, 12)
			b.box(Vector3(0.0, -0.15, 0.6), Vector3(0.14, 0.14, 0.22), POLY)
			b.box(Vector3(0.0, 0.12, 0.55), Vector3(0.03, 0.06, 0.2), POLY)
		&"la_rocket", &"la_laser", &"la_wire", &"la_antiair":
			var seeker := id == &"la_antiair"
			b.cyl(Vector3(0.0, 0.0, 0.5), 0.08, 1.0, GUN, 0.0, 12)
			b.cyl(Vector3(0.0, 0.0, 0.03), 0.1, 0.08, STEEL, 0.0, 12)
			b.cyl(Vector3(0.0, 0.0, 0.0), 0.095, 0.014, glow, 1.0, 12)
			b.cyl(Vector3(0.0, 0.0, 1.02), 0.112, 0.12, STEEL, 0.0, 12)                             # the rear flare
			b.box(Vector3(0.0, 0.13, 0.5), Vector3(0.03, 0.05, 0.2), DARK)
			b.box(Vector3(0.0, -0.13, 0.64), Vector3(0.04, 0.1, 0.05), DARK, 0.0, -0.3)
			b.box(Vector3(0.0, -0.12, 0.32), Vector3(0.036, 0.09, 0.05), POLY)
			if id == &"la_laser":
				b.box(Vector3(0.075, 0.03, 0.34), Vector3(0.05, 0.05, 0.12), POLY)                  # the laser designator pod
				b.cyl(Vector3(0.075, 0.03, 0.27), 0.016, 0.02, glow, 1.0, 8)
			elif id == &"la_wire":
				b.cyl(Vector3(0.1, 0.0, 0.55), 0.05, 0.05, STEEL, 0.0, 12, Basis.from_euler(Vector3(0.0, 0.0, PI * 0.5)))     # the wire reel
				b.cyl(Vector3(0.1, 0.0, 0.55), 0.036, 0.055, glow, 0.7, 12, Basis.from_euler(Vector3(0.0, 0.0, PI * 0.5)))
			elif seeker:
				b.cyl(Vector3(0.0, 0.0, -0.02), 0.075, 0.06, DARK, 0.0, 12)
				b.cyl(Vector3(0.0, 0.0, -0.06), 0.05, 0.04, glow, 1.0, 12)                          # the seeker head
				b.box(Vector3(0.0, 0.2, 0.5), Vector3(0.03, 0.12, 0.14), POLY)                     # an antenna array
			else:
				b.cyl(Vector3(0.0, 0.0, 0.2), 0.086, 0.02, glow, 0.7, 12)
		&"la_swarm":
			for k in 6:
				var ox := (float(k % 3) - 1.0) * 0.065
				var oy := (float(k / 3) - 0.5) * 0.07
				b.cyl(Vector3(ox, oy, 0.35), 0.032, 0.7, GUN, 0.0, 8)
				b.cyl(Vector3(ox, oy, 0.0), 0.034, 0.012, glow, 0.9, 8)
			b.box(Vector3(0.0, 0.0, 0.5), Vector3(0.22, 0.17, 0.16), POLY)
			b.box(Vector3(0.0, 0.11, 0.5), Vector3(0.04, 0.04, 0.16), DARK)
			b.box(Vector3(0.0, -0.14, 0.58), Vector3(0.04, 0.1, 0.05), DARK, 0.0, -0.3)
		&"la_bunker":
			b.cyl(Vector3(0.0, 0.0, 0.32), 0.1, 0.64, GUN, 0.0, 12)
			b.cyl(Vector3(0.0, 0.0, 0.0), 0.115, 0.1, STEEL, 0.0, 12)                               # the armoured nose
			b.cyl(Vector3(0.0, 0.0, -0.06), 0.08, 0.06, DARK, 0.0, 12)
			b.cyl(Vector3(0.0, 0.0, 0.0), 0.118, 0.012, glow, 1.0, 12)
			b.cyl(Vector3(0.0, 0.0, 0.7), 0.12, 0.1, STEEL, 0.0, 12)
			b.box(Vector3(0.0, -0.15, 0.5), Vector3(0.04, 0.1, 0.05), DARK, 0.0, -0.3)
			b.box(Vector3(0.0, 0.13, 0.36), Vector3(0.04, 0.05, 0.14), POLY)
		&"la_cluster":
			b.cyl(Vector3(0.0, 0.0, 0.46), 0.075, 0.92, GUN, 0.0, 12)
			b.cyl(Vector3(0.0, 0.0, 0.06), 0.115, 0.12, OLIVE, 0.0, 12)                             # the fat warhead
			b.cyl(Vector3(0.0, 0.0, 0.0), 0.095, 0.03, STEEL, 0.0, 12)
			for k in 3:
				b.cyl(Vector3(0.0, 0.0, 0.03 + 0.04 * float(k)), 0.118, 0.01, glow, 0.8, 12)
			b.cyl(Vector3(0.0, 0.0, 0.95), 0.1, 0.09, STEEL, 0.0, 12)
			b.box(Vector3(0.0, -0.13, 0.6), Vector3(0.04, 0.1, 0.05), DARK, 0.0, -0.3)
			b.box(Vector3(0.0, 0.12, 0.5), Vector3(0.03, 0.05, 0.16), DARK)
		&"la_recoilless":
			b.cyl(Vector3(0.0, 0.0, 0.5), 0.06, 1.0, GUN, 0.0, 12)
			b.cyl(Vector3(0.0, 0.0, 0.0), 0.075, 0.05, STEEL, 0.0, 12)
			b.cyl(Vector3(0.0, 0.0, 0.0), 0.07, 0.012, glow, 1.0, 12)
			b.cyl(Vector3(0.0, 0.0, 0.72), 0.095, 0.2, STEEL, 0.0, 12)                              # the breech
			b.cyl(Vector3(0.0, 0.0, 0.98), 0.12, 0.12, DARK, 0.0, 12)                               # the venturi
			b.cyl(Vector3(0.0, 0.0, 1.04), 0.1, 0.03, glow, 0.5, 12)
			b.box(Vector3(0.0, 0.12, 0.45), Vector3(0.04, 0.06, 0.2), POLY)
			b.box(Vector3(0.0, -0.12, 0.62), Vector3(0.04, 0.1, 0.05), DARK, 0.0, -0.3)
		&"la_mortar":
			b.cyl(Vector3(0.0, 0.0, 0.36), 0.075, 0.72, GUN, 0.0, 12)
			b.cyl(Vector3(0.0, 0.0, 0.0), 0.09, 0.05, STEEL, 0.0, 12)
			b.cyl(Vector3(0.0, 0.0, 0.0), 0.085, 0.012, glow, 1.0, 12)
			b.cyl(Vector3(0.0, 0.0, 0.74), 0.11, 0.07, STEEL, 0.0, 12)
			for sx in [-1.0, 1.0]:
				b.box(Vector3(0.09 * sx, -0.1, 0.3), Vector3(0.015, 0.2, 0.015), DARK, 0.0, 0.0)  # the bipod legs
			b.box(Vector3(0.0, 0.1, 0.4), Vector3(0.03, 0.05, 0.1), POLY)
			b.box(Vector3(0.0, -0.12, 0.62), Vector3(0.04, 0.1, 0.05), DARK, 0.0, -0.3)
		&"la_plasma":
			b.cyl(Vector3(0.0, 0.0, 0.3), 0.1, 0.6, Color(0.2, 0.24, 0.3), 0.0, 12)
			b.cyl(Vector3(0.0, 0.0, 0.0), 0.12, 0.05, STEEL, 0.0, 12)
			b.cyl(Vector3(0.0, 0.0, 0.0), 0.105, 0.012, glow, 1.0, 12)
			for k in 3:
				b.cyl(Vector3(0.0, 0.0, 0.14 + 0.14 * float(k)), 0.104, 0.02, glow, 0.9, 12)
			b.cyl(Vector3(0.0, 0.12, 0.5), 0.05, 0.24, glow, 0.8, 10)                               # the plasma cell
			b.cyl(Vector3(0.0, 0.12, 0.5), 0.056, 0.03, STEEL, 0.0, 10)
			b.box(Vector3(0.0, 0.0, 0.7), Vector3(0.16, 0.18, 0.18), POLY)
			b.box(Vector3(0.0, -0.15, 0.62), Vector3(0.04, 0.1, 0.05), DARK, 0.0, -0.3)
		_:                                                                                          # la_thermo and anything new
			b.cyl(Vector3(0.0, 0.0, 0.34), 0.085, 0.68, GUN, 0.0, 12)
			b.cyl(Vector3(0.0, 0.0, 0.03), 0.12, 0.09, DARK, 0.0, 12)                               # the finned nozzle
			for k in 4:
				b.cyl(Vector3(0.0, 0.0, 0.0 + 0.03 * float(k)), 0.125, 0.008, glow, 0.8, 12)
			b.cyl(Vector3(0.0, -0.12, 0.5), 0.07, 0.36, Color(0.5, 0.2, 0.15), 0.0, 10)            # the fuel bottle under the tube
			b.cyl(Vector3(0.0, -0.12, 0.5), 0.073, 0.02, glow, 0.7, 10)
			b.box(Vector3(0.0, 0.12, 0.45), Vector3(0.03, 0.05, 0.16), DARK)
			b.box(Vector3(0.0, -0.17, 0.7), Vector3(0.04, 0.1, 0.05), DARK, 0.0, -0.3)
