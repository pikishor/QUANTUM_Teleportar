shader_type spatial;
render_mode cull_back;
// Near traffic (scripts/ambient/near_traffic.gd): ONE MultiMesh of small lit cars (about 160 triangles) that drive the lanes around the hero. They cost one draw call, so the market
// street has a dozen cars moving at real speeds without a VehicleManager node each; a car the hero touches or tries to take is swapped for a real Vehicle.
// Mesh UV.x = surface tag (0 paint, 0.25 glass, 0.45 tyre, 0.47 wheel arch, 0.55 dark trim, 0.65 rim, 0.8 headlamp, 1.0 tail lamp), UV.y = z of the wheel centre (wheels keep their size when the body is stretched).
// MultiMesh INSTANCE_CUSTOM = (paint index, body variant, brake 0..1, lamps 0..1). Variants: 0 sedan, 1 hatch, 2 suv, 3 van, 4 taxi, 5 sport, 6 pickup, 7 box truck, 8 bus, 9 police (flashing roof), 10 ambulance (flashing roof), 11 delivery van.

global uniform float night;
global uniform float wetness;
uniform sampler2D light_map : filter_linear, repeat_disable, hint_default_black;
uniform vec4 light_rect = vec4(-1104.0, -1104.0, 2208.0, 2208.0);

varying flat vec3 v_paint;
varying flat vec3 v_pool;
varying flat float v_brake;
varying flat float v_lamps;
varying float v_tag;
varying float v_y;
varying flat float v_siren;
varying float v_roof;

const vec3 PAINT[8] = vec3[8](vec3(0.56, 0.20, 0.24), vec3(0.30, 0.42, 0.56), vec3(0.78, 0.66, 0.44), vec3(0.30, 0.52, 0.48),
		vec3(0.42, 0.38, 0.60), vec3(0.66, 0.67, 0.71), vec3(0.68, 0.40, 0.26), vec3(0.15, 0.18, 0.30));
// per variant: length scale, height scale, width scale
const vec3 SHAPE[12] = vec3[12](vec3(1.0, 1.0, 1.0), vec3(0.84, 1.04, 0.95), vec3(1.06, 1.24, 1.06), vec3(1.2, 1.55, 1.08), vec3(1.0, 1.0, 1.0), vec3(0.96, 0.84, 1.05),
		vec3(1.08, 1.14, 1.06), vec3(1.4, 1.95, 1.2), vec3(2.05, 1.95, 1.34), vec3(1.02, 1.0, 1.05), vec3(1.17, 1.55, 1.1), vec3(1.26, 1.7, 1.14));

void vertex() {
	int variant = int(INSTANCE_CUSTOM.y + 0.5);
	int pi = int(INSTANCE_CUSTOM.x + 0.5) & 7;
	vec3 sh = SHAPE[variant];
	vec3 v = VERTEX;
	float wheelish = step(0.4, UV.x) * step(UV.x, 0.7) * (1.0 - step(0.5, UV.x) * step(UV.x, 0.6));
	if (wheelish > 0.5) {
		v.z = (v.z - UV.y) + UV.y * sh.x;                 // wheels move with the wheelbase, keep their size
		v.x += sign(v.x) * 0.9 * (sh.z - 1.0);
	} else {
		v *= vec3(sh.z, sh.y, sh.x);
	}
	VERTEX = v;
	v_roof = v.y / max(sh.y, 0.1);
	v_siren = step(8.5, float(variant)) * step(float(variant), 10.5);
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_pool = textureLod(light_map, (o.xz - light_rect.xy) / light_rect.zw, 0.0).rgb;
	vec3 paint = PAINT[pi];
	if (variant == 4) {
		paint = vec3(0.86, 0.62, 0.08);                    // taxi
	} else if (variant == 7) {
		paint = (pi & 1) == 0 ? vec3(0.56, 0.58, 0.6) : vec3(0.68, 0.7, 0.72);      // box truck: grey or white (no blown whites in the rain light)
	} else if (variant == 8) {
		paint = (pi & 1) == 0 ? vec3(0.78, 0.5, 0.18) : vec3(0.28, 0.5, 0.62);      // city bus: amber or teal
	} else if (variant == 9) {
		paint = vec3(0.14, 0.19, 0.34);                    // police patrol
	} else if (variant == 10) {
		paint = vec3(0.74, 0.75, 0.78);                    // ambulance
	} else if (variant == 11) {
		paint = (pi % 3 == 0) ? vec3(0.3, 0.42, 0.56) : vec3(0.7, 0.72, 0.75);      // delivery van: white or blue
	} else if (variant == 6) {
		paint = PAINT[(pi + 2) & 7] * 0.9;                 // pickup
	}
	v_paint = paint;
	v_brake = INSTANCE_CUSTOM.z;
	v_lamps = INSTANCE_CUSTOM.w;
	v_tag = UV.x;
	v_y = VERTEX.y;
}

void fragment() {
	float t = v_tag;
	vec3 col = v_paint;
	float body = 1.0 - step(0.1, t);
	float glass = step(0.15, t) * step(t, 0.35);
	float tyre = step(0.4, t) * step(t, 0.5);
	float trim = step(0.5, t) * step(t, 0.6);
	float rim = step(0.6, t) * step(t, 0.7);
	float head = step(0.7, t) * step(t, 0.9);
	float tail = step(0.9, t);
	col *= mix(0.5, 1.08, smoothstep(0.28, 0.95, v_y));                        // darker sills, lighter shoulders: the flat paint gets a form
	col = mix(col, vec3(0.025, 0.04, 0.055) + vec3(0.02, 0.04, 0.06) * smoothstep(1.0, 1.36, v_y), glass);
	col = mix(col, vec3(0.012, 0.012, 0.014), tyre);
	col = mix(col, vec3(0.03, 0.03, 0.035), trim);
	col = mix(col, vec3(0.26, 0.27, 0.30), rim);
	float wet = clamp(wetness, 0.0, 1.0);
	ALBEDO = col;
	ROUGHNESS = mix(0.34, 0.08, glass) * (1.0 - 0.35 * wet);
	METALLIC = 0.45 * body + 0.7 * rim;
	SPECULAR = 0.6;
	vec3 nv = normalize(NORMAL);
	float rimlight = pow(1.0 - clamp(dot(nv, normalize(VIEW)), 0.0, 1.0), 3.0);
	vec3 up = (INV_VIEW_MATRIX * vec4(nv, 0.0)).xyz;
	vec3 fill = vec3(0.022, 0.032, 0.046) * (0.5 + 0.5 * clamp(up.y * 0.5 + 0.5, 0.0, 1.0));
	vec3 em = col * (v_pool * 0.9 + fill * 7.0) + vec3(0.12, 0.2, 0.3) * rimlight * 0.6;
	em += col * (0.03 + 0.09 * night) * body;                                     // the paint keeps its colour in the dark (a little by day: no blown roofs)
	float flash = step(0.5, fract(TIME * 3.0 + v_tag * 0.0));
	em += v_siren * step(1.28, v_roof) * mix(vec3(0.15, 0.3, 1.0), vec3(1.0, 0.1, 0.08), flash) * 3.2;       // the roof of a patrol car or an ambulance flashes
	em += glass * vec3(0.05, 0.09, 0.14) * (0.7 + 2.4 * rimlight) * (0.6 + 0.4 * smoothstep(0.84, 1.36, v_y));   // the glass reflects a little street and sky: never a flat black hole seen from above
	float lamp_on = mix(0.5, 1.0, night) * v_lamps;
	em += vec3(1.0, 0.92, 0.78) * head * (1.6 + 2.2 * lamp_on);
	em += vec3(1.0, 0.05, 0.03) * tail * (0.9 + 1.2 * lamp_on + 2.6 * v_brake);
	EMISSION = em;
}
