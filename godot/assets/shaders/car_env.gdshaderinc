// The procedural street the Cars v2 shaders reflect (car_common.gdshaderinc, the near traffic shaders): no reflection probe, no texture.

global uniform float night;
global uniform float wetness;

float car_hash(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

// What the shell reflects: day sky or a night street (dark asphalt below, a sky glow above, vertical neon streaks and lamp spots along the horizon).
vec3 street_env(vec3 r, float rough) {
	float up = r.y;
	vec3 hor = mix(vec3(0.62, 0.72, 0.86), vec3(0.05, 0.06, 0.11), night);
	vec3 zen = mix(vec3(0.20, 0.42, 0.85), vec3(0.012, 0.016, 0.045), night);
	vec3 col = mix(hor, zen, smoothstep(0.0, 0.85, up));
	vec3 ground = mix(vec3(0.11, 0.115, 0.12), vec3(0.012, 0.014, 0.018), night);
	col = mix(col, ground, smoothstep(0.0, -0.25, up));
	float az = (atan(r.x, r.z) + 3.14159265) * 6.0;           // 0 .. 37.7: one cell about every 9.5 degrees
	float cell = floor(az);
	float f = fract(az) - 0.5;
	float h1 = car_hash(cell * 1.7 + 3.0);
	float h2 = car_hash(cell * 2.9 + 11.0);
	float w = mix(0.04, 0.24, h2) + rough * 0.3;
	float streak = smoothstep(w, 0.0, abs(f)) * smoothstep(-0.18, 0.05, up) * smoothstep(0.75, 0.08, up);
	vec3 neon = h1 < 0.3 ? vec3(0.1, 0.9, 1.0) : (h1 < 0.55 ? vec3(1.0, 0.18, 0.75) : (h1 < 0.8 ? vec3(1.0, 0.72, 0.35) : vec3(0.9, 0.95, 1.0)));
	float on = step(0.35, car_hash(cell * 5.3 + 1.0));
	col += neon * streak * on * (0.25 + 1.9 * night) * (1.0 - rough * 0.8);
	float lamp = smoothstep(0.12, 0.0, abs(up - 0.34 + 0.2 * h2)) * smoothstep(0.1, 0.0, abs(f - (h1 - 0.5) * 0.6));
	col += vec3(1.0, 0.92, 0.8) * lamp * night * 1.3 * (1.0 - rough);
	return col;
}
