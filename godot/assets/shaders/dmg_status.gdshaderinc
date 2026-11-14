// STATUS LOOKS of a body: burning, frozen, shocked, dissolving (wave 113 critic LOOK). Shared by hero_body.gdshader (the classic operatives), foe_body.gdshader (the armoured roster humans) and
// foe_creature.gdshader (the vael aliens and grid walkers), so every enemy shows the same four states (scripts/damage/foe_fx.gd sets `dmg_fx`).
//   fx.x  1 burning, 2 frozen, 3 shocked, 4 dissolving      fx.y  strength 0..1 (0 = clean)
// Everything is a function of the position ON the body (object space: it follows the pose, skinned bodies included) and of a clock, never of the UV: the first version drew its flicker along the UV
// islands and a burning man became a tiger, a frozen one a zebra. Burning = a charred body with glowing seams that crawl upward and a fire-lit rim; frozen = faceted ice with a cold rim and glints;
// shocked = thin crawling arcs on the body that pulse; dissolving = the body breaks into a field of motes from the feet up.

float dmg_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float dmg_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(dmg_hash(i), dmg_hash(i + vec3(1.0, 0.0, 0.0)), f.x), mix(dmg_hash(i + vec3(0.0, 1.0, 0.0)), dmg_hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y);
	float b = mix(mix(dmg_hash(i + vec3(0.0, 0.0, 1.0)), dmg_hash(i + vec3(1.0, 0.0, 1.0)), f.x), mix(dmg_hash(i + vec3(0.0, 1.0, 1.0)), dmg_hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y);
	return mix(a, b, f.z);
}

// p = position on the body (object space, metres), h = 0 at the feet .. 1 at the head, rim = 0..1 grazing-angle term, t = TIME.
// Returns true when the pixel is gone (dissolve): the caller discards it.
bool dmg_status(vec4 fx, vec3 p, float h, float rim, float t, inout vec3 alb, inout float rough, inout float metal, inout vec3 emis) {
	float s = fx.y;
	if (s <= 0.001) {
		return false;
	}
	if (fx.x < 1.5) {
		// BURNING: char the paint, light seams that crawl upward, more fire low on the body, and a hot rim
		vec3 q = p * 4.5 + vec3(0.0, -t * 2.6, 0.0);
		float n = dmg_noise(q) * 0.62 + dmg_noise(q * 2.3 + vec3(11.0, 3.0, 7.0)) * 0.38;
		float lowk = (0.5 - h) * 0.5;
		float tongue = smoothstep(0.58, 0.8, n + lowk * 0.6);                    // only the high values of the noise glow: a dark body with seams of fire, not a hot-metal silhouette
		float core = smoothstep(0.74, 0.92, n + lowk * 0.5);
		float flick = 0.8 + 0.2 * sin(t * 13.0 + p.y * 7.0 + p.x * 5.0);
		alb = mix(alb, vec3(0.02, 0.016, 0.014), 0.88 * s);
		rough = mix(rough, 0.92, s);
		metal = mix(metal, 0.0, s);
		vec3 fire = mix(vec3(0.85, 0.12, 0.02), vec3(1.0, 0.6, 0.12), core);
		fire = mix(fire, vec3(1.0, 0.9, 0.55), core * core);
		emis += fire * tongue * s * (1.0 + 2.2 * core) * flick;
		emis += vec3(0.16, 0.03, 0.005) * s * (0.3 + 0.7 * (1.0 - h));       // embers under the char: the dark paint never goes pitch black, the legs glow more than the head
		emis += vec3(1.0, 0.32, 0.05) * rim * s * 0.45;
	} else if (fx.x < 2.5) {
		// FROZEN: faceted ice, a cold rim, a few glints
		float fac = dmg_hash(floor(p * 11.0));
		vec3 ice = vec3(0.52, 0.76, 0.96) * (0.8 + 0.4 * fac);
		alb = mix(alb, ice, 0.8 * s);
		rough = mix(rough, 0.07, s);
		metal = mix(metal, 0.2, s);
		float glint = step(0.992 - 0.012 * s, dmg_hash(floor(p * 38.0) + floor(t * 3.0)));
		emis += vec3(0.05, 0.15, 0.3) * s * (0.5 + 1.6 * rim);
		emis += vec3(0.3, 0.55, 0.9) * rim * s * 0.9;
		emis += vec3(0.75, 0.93, 1.0) * glint * s * 1.8;
	} else if (fx.x < 3.5) {
		// SHOCKED: thin arcs that crawl over the body and a pulsing cold rim, the paint a little darker so the lines read
		float pulse = 0.55 + 0.45 * step(0.5, fract(t * 12.0));
		vec3 q = p * vec3(5.0, 3.5, 5.0) + vec3(t * 3.0, t * 17.0, -t * 5.0);
		float l1 = abs(dmg_noise(q) - 0.5);
		float l2 = abs(dmg_noise(q * 1.7 + vec3(5.0, 1.0, 9.0)) - 0.5);
		float arc = max(1.0 - smoothstep(0.0, 0.06, l1), 1.0 - smoothstep(0.0, 0.05, l2));
		alb *= 1.0 - 0.3 * s;
		emis += vec3(0.62, 0.84, 1.0) * arc * s * 3.6 * pulse;
		emis += vec3(0.1, 0.2, 0.5) * s * pulse * 0.5;                          // the whole body flickers cold
		emis += vec3(0.25, 0.45, 1.0) * rim * s * (0.9 + 1.4 * pulse);
	} else {
		// DISSOLVING: the body breaks into a field of motes (the strength is set at once on a death, the model shrinks away over a second), the rest glows violet at the edge
		float n = dmg_hash(floor(p * 70.0));
		float edge_t = s * 0.85;
		if (n < edge_t) {
			return true;
		}
		emis += vec3(0.6, 0.25, 1.0) * smoothstep(edge_t, edge_t + 0.15, n) * s * 2.0;
	}
	return false;
}
