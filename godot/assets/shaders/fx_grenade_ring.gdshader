shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
// Landing ring of an enemy grenade (scripts/enemies/enemy_grenades.gd): a flat quad on the street as wide as the blast. A thin bright rim, a soft red fill that swells towards the
// rim as the fuse burns down (k 0..1) and a pulse that speeds up, so a player on a phone reads WHERE it lands, HOW WIDE the blast is and HOW SOON.
uniform vec3 col : source_color = vec3(1.0, 0.3, 0.12);
uniform float k : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float pulse = 0.75 + 0.25 * sin(TIME * (8.0 + 22.0 * k));
	float rim = smoothstep(0.86, 0.93, r) * (1.0 - smoothstep(0.97, 1.0, r));
	float fill = (1.0 - smoothstep(0.0, 0.93, r)) * 0.18 + smoothstep(0.0, 0.93, r) * step(r, 0.93) * 0.1;
	float sweep = smoothstep(k - 0.02, k, r) * 0.0 + (1.0 - smoothstep(0.0, 0.03, abs(r - k * 0.93))) * 0.5;
	float a = (rim * 1.2 + fill * (0.5 + k) + sweep) * pulse * step(r, 1.0);
	ALBEDO = col * a;
	ALPHA = a;
}
