shader_type spatial;
render_mode cull_disabled;     // double sided since wave 113: the inside of a popped hood and of the shell shows (dark liner), see the end of fragment()
// Cars v2 paint: lacquer over metallic flake, a baked ambient occlusion in the vertex colour (R), a fresnel clear coat that reflects a procedural street (street_env), dirt that
// climbs the lower body, scuffs and soot with damage, dents from the vertex stage (car_common.gdshaderinc) and procedural liveries (stripes, a taxi checker band, two-tone doors).
// Model space: nose -Z, origin on the ground. Vertex uv2.x = body part id / 32 (0 = the shell, 1 front bumper ... see part_lost).
#include "res://assets/shaders/car_common.gdshaderinc"

uniform vec4 paint : source_color = vec4(0.5, 0.1, 0.1, 1.0);
uniform vec4 flake_tint : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float flake = 0.45;             // 0 flat colour .. 1 coarse metallic flake
uniform float metal = 0.3;
uniform float rough = 0.3;
uniform float coat = 1.0;               // strength of the clear coat reflection
uniform float pearl = 0.0;              // colour that shifts towards pearl_tint at grazing angles
uniform vec4 pearl_tint : source_color = vec4(0.4, 0.2, 0.9, 1.0);
uniform float dirt = 0.0;               // road film climbing the doors
uniform float scuff = 0.0;              // 0 .. 1 damage: soot, duller coat, scratches
uniform float wet = 0.0;                // 0 .. 1 rain on the body
uniform float glow = 0.18;              // paint emission floor so a car keeps its colour at night
uniform float spec = 0.9;               // dielectric specular of the lacquer (default 0.5): street lamps and neon leave a visible highlight
uniform float rim = 0.6;                // grazing angle sheen of the paint
uniform int livery = 0;                 // 0 none, 1 dual stripes, 2 side stripe, 3 checker band (taxi), 4 two-tone doors, 5 hood and roof stripe, 6 emergency band
uniform vec4 livery_color : source_color = vec4(1.0);
uniform vec4 livery_color2 : source_color = vec4(0.02, 0.02, 0.03, 1.0);
uniform sampler2D flake_tex : hint_normal, filter_linear_mipmap, repeat_enable;

void vertex() {
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	v_dent = car_vertex(v, n, UV2.x * 32.0);
	v_obj = v;
	v_nobj = n;
	VERTEX = v;
	NORMAL = n;
}

vec4 livery_at(vec3 p, vec3 n) {
	// returns (colour rgb, weight)
	float side = step(0.6, abs(n.x));
	float top = step(0.5, n.y);
	float w = 0.0;
	vec3 c = livery_color.rgb;
	if (livery == 1) {
		float ax = abs(p.x);
		w = top * (step(0.06, ax) * step(ax, 0.17) + step(0.21, ax) * step(ax, 0.27));
	} else if (livery == 2) {
		w = side * step(0.50, p.y) * step(p.y, 0.58);
	} else if (livery == 3) {
		float chk = mod(floor(p.z / 0.11) + floor((p.y - 0.60) / 0.055), 2.0);
		w = side * step(0.60, p.y) * step(p.y, 0.715) * chk;
		c = vec3(0.02, 0.02, 0.02);
	} else if (livery == 4) {
		float door = step(-1.05, p.z) * step(p.z, 0.95) * step(p.y, 0.86) * step(0.30, p.y);
		w = side * door;
		c = livery_color.rgb;
	} else if (livery == 5) {
		w = top * step(abs(p.x), 0.20);
	} else if (livery == 6) {
		float band = step(0.58, p.y) * step(p.y, 0.76) + step(0.40, p.y) * step(p.y, 0.45);
		w = side * band;
	}
	return vec4(c, w);
}

void fragment() {
	vec3 base = paint.rgb;
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	base = mix(base, pearl_tint.rgb, pearl * pow(1.0 - ndv, 2.5));
	vec4 lv = livery_at(v_obj, v_nobj);
	base = mix(base, lv.rgb, lv.a);
	// flake: a normal map sampled in model space along the dominant axis of the normal, fading out with distance (sub pixel anyway)
	float dist = length(VERTEX);
	vec3 an = abs(v_nobj);
	vec2 uv = an.y > max(an.x, an.z) ? v_obj.xz : (an.x > an.z ? v_obj.zy : v_obj.xy);
	float amp = flake * (1.0 - smoothstep(2.0, 9.0, dist)) * (1.0 - lv.a);
	vec3 fn = texture(flake_tex, uv * 7.0).xyz * 2.0 - 1.0;
	vec3 t_axis = an.y > max(an.x, an.z) ? vec3(1.0, 0.0, 0.0) : (an.x > an.z ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0));
	vec3 b_axis = an.y > max(an.x, an.z) ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
	vec3 tv = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(t_axis, 0.0)).xyz);
	vec3 bv = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(b_axis, 0.0)).xyz);
	vec3 n_smooth = normalize(NORMAL);                                      // the street reflection uses the clean normal (flake only breaks up the lights)
	vec3 nrm = normalize(NORMAL + (tv * fn.x + bv * fn.y) * amp * 0.28);
	NORMAL = nrm;
	float ao = mix(1.0, COLOR.r, 0.9);
	// dirt: a film on the lower body (more in the arches, none on the roof), damage soot
	float low = 1.0 - smoothstep(0.2, 0.75, v_obj.y);
	float dmask = clamp(dirt * (0.12 + 0.88 * low) + (1.0 - COLOR.r) * dirt * 0.5, 0.0, 1.0);
	vec3 dcol = vec3(0.11, 0.095, 0.08);
	base = mix(base, dcol, dmask * 0.8);
	float sc = clamp(scuff + v_dent * 0.9, 0.0, 1.0);
	base = mix(base, base * 0.35 + vec3(0.03), sc * 0.65);
	vec3 hm = hole_mask(v_obj, v_nobj);
	base = mix(base, base * 0.3 + vec3(0.01), hm.z * 0.6 * (1.0 - hm.x));           // a soot halo round every hole
	base = mix(base, vec3(0.52, 0.54, 0.58), hm.y * 0.55);                           // the torn edge: bare grey metal, not white
	base = mix(base, vec3(0.004), hm.x);                                             // the hole itself
	float spark = pow(max(fn.z * 2.0 - 1.0, 0.0), 8.0) * (1.0 - smoothstep(2.0, 9.0, dist));                    // rare bright flakes, only close up
	base *= mix(0.80, 1.0, smoothstep(0.22, 0.95, v_obj.y));                           // a lighter shoulder and a darker sill: the body has a form, not a flat colour
	ALBEDO = base * ao;
	METALLIC = clamp(metal * (1.0 - dmask) + flake * 0.1 * spark, 0.0, 1.0);
	ROUGHNESS = clamp(mix(rough, 0.8, dmask) + sc * 0.4 - wet * 0.14 + v_dent * 0.25 + hm.z * 0.3, 0.08, 1.0);
	SPECULAR = spec;
	RIM = rim;
	RIM_TINT = 0.6;
	// clear coat: fresnel reflection of the street, and the paint's own light
	vec3 rv = reflect(-VIEW, n_smooth);
	vec3 rw = (INV_VIEW_MATRIX * vec4(rv, 0.0)).xyz;
	float fres = 0.04 + 0.96 * pow(1.0 - ndv, 5.0);
	float shine = coat * (1.0 - sc * 0.8) * (1.0 - dmask * 0.8) * mix(1.0, 1.35, wet);
	vec3 env = street_env(rw, mix(rough, 0.05, wet) * 0.8);
	float lum = dot(base, vec3(0.33));
	vec3 refl = env * (fres * 1.6 * shine + metal * 0.40 * (1.0 - rough * 0.6)) * mix(vec3(1.0), flake_tint.rgb * base * 2.0, metal) * mix(1.0, 0.62, clamp(lum * 1.3, 0.0, 1.0));      // a bright paint reflects less in relation to itself: no white wash by day
	EMISSION = (base * glow + refl) * ao;
	if (!FRONT_FACING) {                       // the inside of the shell (an opened hood, a wheel arch): a dark liner, not lit paint
		ALBEDO = vec3(0.012, 0.012, 0.014);
		EMISSION = vec3(0.0);
		METALLIC = 0.0;
		ROUGHNESS = 0.9;
	}
}
