shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_opaque;
// The far ridge ring (scripts/terrain/terrain_ridges.gd): a silhouette of distant mountain ranges beyond the 6 km world (over the sea), in the haze colour of the horizon,
// darker towards the tops. UV.y = 0 at the foot, 1 at the crest. `haze` follows the environment's fog colour every frame (DayNight), so it sits in the same air as everything else.

uniform vec3 haze : source_color = vec3(0.2, 0.27, 0.34);
uniform float dark = 0.62;
uniform float night = 0.0;

varying float h01;

void vertex() {
	h01 = UV.y;
}

void fragment() {
	vec3 top = haze * dark;
	ALBEDO = mix(haze * 0.96, top, smoothstep(0.0, 0.85, h01));
}
