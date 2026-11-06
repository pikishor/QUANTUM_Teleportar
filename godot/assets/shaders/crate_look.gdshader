shader_type spatial;
render_mode cull_back;
// Weapon / ammo crates (scripts/freedom/weapon_crates.gd): the crate mesh of WeaponModels.crate_mesh() (vertex colour rgb = the part, alpha = glow). The body stays dark metal; only the glow
// parts take the per-instance tint (INSTANCE_CUSTOM.rgb), pink for a weapon crate, amber for ammo.

varying vec4 vc;
varying vec3 tint;

void vertex() {
	vc = COLOR;
	tint = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	vec3 glow_col = tint;
	ALBEDO = mix(vc.rgb, glow_col * 0.35, vc.a);
	METALLIC = 0.4;
	ROUGHNESS = 0.55;
	RIM = 0.2;
	EMISSION = glow_col * vc.a * 1.1;
}
