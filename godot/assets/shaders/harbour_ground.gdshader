shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, depth_draw_opaque;
// The quay apron of the harbour (scripts/world/harbour_kit.gd): concrete slabs with joints every 6 m, oil stains, tyre-worn lanes, a yellow safety line along every quay edge and
// white bay marks. World position only, no textures. `basin` = the water rect (x0, z0, x1, z1): the safety line follows its edge.

uniform vec4 basin = vec4(-100.0, 1400.0, 160.0, 1740.0);
global uniform float wetness;
global uniform float night;

varying vec3 wpos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 slab = floor(p / 6.0);
	float tone = hash21(slab);
	vec3 col = mix(vec3(0.42, 0.42, 0.41), vec3(0.5, 0.49, 0.47), tone);
	float grain = vnoise(p * 1.7) * 0.55 + vnoise(p * 7.0) * 0.45;
	col *= 0.8 + 0.34 * grain;
	vec2 f = abs(fract(p / 6.0) - 0.5) * 6.0;
	float joint = smoothstep(2.88, 2.97, max(f.x, f.y));
	col *= 1.0 - 0.45 * joint;
	float oil = smoothstep(0.62, 0.8, vnoise(p * 0.18 + 5.0));
	col = mix(col, col * vec3(0.5, 0.5, 0.55), oil * 0.7);
	// distance to the basin edge on the land side
	float dx = max(max(basin.x - p.x, p.x - basin.z), 0.0);
	float dz = max(basin.y - p.y, 0.0);
	float d = sqrt(dx * dx + dz * dz);
	bool inside = p.x > basin.x && p.x < basin.z && p.y > basin.y;
	float line = inside ? 0.0 : smoothstep(0.25, 0.15, abs(d - 1.8));
	col = mix(col, vec3(0.86, 0.68, 0.1), line * 0.9);
	// bay marks: white dashes every 12 m along x on the container yard lanes
	float lane = smoothstep(0.14, 0.08, abs(fract(p.y / 24.0) - 0.5) * 24.0 - 11.5) * step(fract(p.x / 12.0), 0.5);
	col = mix(col, vec3(0.8, 0.8, 0.78), lane * 0.35);
	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.45, wetness);
}
