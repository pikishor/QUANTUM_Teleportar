shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// A torn body panel of a wrecked car (scripts/vehicles/car_debris.gd, one MultiMesh of unit boxes scaled per instance; the instance colour is the car's paint). The first version was a plain painted
// slab that read as a black plank when it flew past the lens (wave 113 critic): now the paint is blotched with age and scorch, the edges are scorched dark with a rim of bare metal, the underside is
// raw dark primer and there is a cold rim light so the shape reads against a dark street. No texture, no extra draw.

varying vec3 v_obj;
varying vec3 v_paint;
varying vec3 v_size;
varying vec3 v_nrm;

float h31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float n31(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(h31(i), h31(i + vec3(1.0, 0.0, 0.0)), f.x), mix(h31(i + vec3(0.0, 1.0, 0.0)), h31(i + vec3(1.0, 1.0, 0.0)), f.x), f.y);
	float b = mix(mix(h31(i + vec3(0.0, 0.0, 1.0)), h31(i + vec3(1.0, 0.0, 1.0)), f.x), mix(h31(i + vec3(0.0, 1.0, 1.0)), h31(i + vec3(1.0, 1.0, 1.0)), f.x), f.y);
	return mix(a, b, f.z);
}

void vertex() {
	v_obj = VERTEX;
	v_paint = COLOR.rgb;
	v_size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	v_nrm = NORMAL;
}

void fragment() {
	vec3 pm = v_obj * v_size;                                  // metres on the panel
	vec3 paint = max(v_paint, vec3(0.02));
	vec3 sel = step(v_size, vec3(min(v_size.x, min(v_size.y, v_size.z)) + 0.0001));   // the thin axis of the slab (a bonnet is thin in y, a door in x)
	vec3 big = vec3(1.0) - sel;
	float edge = max(max(abs(v_obj.x) * big.x, abs(v_obj.y) * big.y), abs(v_obj.z) * big.z) * 2.0;        // 0 in the middle .. 1 at the rim
	float blot = n31(pm * vec3(6.0, 6.0, 6.0));
	float fine = n31(pm * 23.0);
	float soot = smoothstep(0.35, 1.0, edge + 0.35 * (blot - 0.5)) * 0.85;
	vec3 col = paint * (0.62 + 0.55 * blot);
	col = mix(col, vec3(0.025, 0.022, 0.02), soot);            // scorched towards the rim
	col = mix(col, vec3(0.5, 0.52, 0.56), smoothstep(0.9, 0.99, edge) * (0.4 + 0.6 * fine));   // bare metal along the torn edge
	col *= 0.85 + 0.3 * fine;                                  // scratches and grit
	float under = step(dot(v_nrm, sel), -0.5);                 // the lower face of the slab: raw primer
	col = mix(col, vec3(0.07, 0.065, 0.06) + 0.05 * fine, under * 0.85);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	ALBEDO = col;
	ROUGHNESS = mix(0.38, 0.8, soot);
	METALLIC = mix(0.35, 0.1, soot);
	SPECULAR = 0.5;
	EMISSION = col * 0.12 + vec3(0.1, 0.12, 0.16) * rim * 0.7;
}
