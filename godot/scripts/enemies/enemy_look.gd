class_name EnemyLook
extends RefCounted
## Enemy readability (D7): one colour code per role shared by troopers, specialists and drones, a rim light on the body for distance (strongest on LOW, where
## there is no shadow or post glow to separate a dark figure from the street) and the telegraph boost of the glowing weak points. No new draw calls: the rim is a
## material parameter of the per-enemy override materials, the boost scales and fades the shared tell mesh instance.
##   shield cyan, sniper magenta, brute orange, flanker amber, trooper red, drones by their cfg colour (sentinel rose, striker amber, heavy violet).

const ROLE_COLORS := {
	&"shield": Color(0.25, 0.8, 1.0),
	&"sniper": Color(1.0, 0.2, 0.8),
	&"brute": Color(1.0, 0.5, 0.1),
	&"flanker": Color(1.0, 0.62, 0.15),
	&"overseer": Color(0.72, 0.3, 1.0),
}
## Rim strength per graphics tier (LOW, MED, HIGH).
const RIM_BY_TIER: Array[float] = [1.0, 0.7, 0.5]


## The colour code of an enemy cfg (its role, else its own colour).
static func code_color(cfg: Dictionary) -> Color:
	var role: StringName = cfg.get("role", &"")
	if ROLE_COLORS.has(role):
		return ROLE_COLORS[role]
	return cfg.get("color", Color(1.0, 0.22, 0.2))


static func rim_strength(tier: int) -> float:
	return RIM_BY_TIER[clampi(tier, 0, RIM_BY_TIER.size() - 1)]


## Rim light in the role colour on every override material of `root` (returns how many materials were set).
static func apply_rim(root: Node, col: Color, tier: int) -> int:
	var n := 0
	for mi: MeshInstance3D in DynamicFill._meshes(root):
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var ov := mi.get_surface_override_material(si) as BaseMaterial3D
			if ov == null:
				continue
			ov.rim_enabled = true
			ov.rim = rim_strength(tier)
			ov.rim_tint = 0.8
			# rim takes the albedo tint; keep the code colour readable on dark armour by lifting the emission floor slightly
			if not ov.emission_enabled:
				ov.emission_enabled = true
				ov.emission = col
				ov.emission_energy_multiplier = 0.06
			n += 1
	return n


## Telegraph boost of a tell mesh: charge 0..1 grows and brightens it (idle is dimmer, a charged attack is the brightest thing on the enemy).
static func boost_tell(tell: GeometryInstance3D, charge: float) -> void:
	var c := clampf(charge, 0.0, 1.0)
	tell.transparency = 0.35 * (1.0 - c)
	var s := 1.0 + 0.3 * c
	tell.scale = Vector3(s, s, s)


## Brightness of the shield plate: calm 1.25, up to 3 while the wearer charges a shot.
static func plate_glow(charge: float) -> float:
	return 1.25 + 1.0 * clampf(charge, 0.0, 1.0)
