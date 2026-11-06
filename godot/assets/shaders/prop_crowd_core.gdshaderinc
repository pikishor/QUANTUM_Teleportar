// Pedestrian crowd: ONE MultiMesh of ONE low-poly citizen mesh (assets/models/citizen.glb, tools/blender/model_citizen.py, about 850 triangles near, 330 far) that carries every
// optional piece of the thirteen archetypes; the vertex stage shows the pieces an archetype wears (hood or helmet, cowl, long coat tail, backpack, swept crest and visor, scarf, umbrella,
// mantle, cap peak, wide hat, vendor tray, pauldrons, antennae), proportions the body (height, width, depth, neck, head, arm length) and animates it (walk, idle, talk, flee, cower), and
// the fragment stage colours the vertex-colour surfaces from palettes (coat, skin by species, accent, eyes, hi-vis vest with reflective bands, armour).
// Mesh COLOR: r = surface (0 skin, 0.15 visor / glow, 0.3 dark, 0.5 trousers, 0.7 accent, 1.0 coat), g = piece id / 20 (see the model script), b = baked shadow (1 lit),
// a = part tag (0 body, 0.2 left leg, 0.4 right leg, 0.6 left arm, 0.8 right arm, 0.9 coat tail, 1.0 umbrella).
// MultiMesh INSTANCE_CUSTOM = (seed, walk phase, state / stride amplitude, flags):
//   seed       group = floor(seed * 6) (the crowd gives slot i the group i % 6), the fraction of seed * 6 picks the archetype inside the group (ARCH_OPT / ARCH_CUT), other digits pick palettes and habits
//   phase      walk cycle clock (advances with the walk; it stands still while a person stands)
//   z          0 idle (stand, talk, check a wrist device, hands clasped: by the seed, animated with TIME), 0.5..1.2 walking (stride amplitude), > 1.5 fleeing (running, arms up or pumping),
//              < 0 cowering (crouched, hands over the head, trembling)
//   w          bit 0 umbrella (only the human archetypes 0..5 carry one), bit 1 (w >= 2) "talking": an idle person gestures and nods (the crowd may set it for a chatting group)
// The MultiMesh also has a white instance colour: a mesh with vertex colours needs one in the Compatibility renderer. The street's lamp and neon pools (the ground light map) tint each person.

#include "res://assets/shaders/common.gdshaderinc"

global uniform float wetness;
uniform sampler2D light_map : filter_linear, repeat_disable, hint_default_black;
uniform vec4 light_rect = vec4(-704.0, -704.0, 1408.0, 1408.0);
uniform float lod_range_far = 100000.0;                // a person shrinks to nothing at this camera distance (the crowd ring is the real limit)

varying flat vec3 v_pool;
varying flat vec3 v_tint;
varying flat vec3 v_skin;
varying flat vec3 v_eye;
varying flat vec3 v_accent;
varying flat float v_hood;
varying flat float v_arch;
varying flat float v_piece;
varying flat float v_mark;
varying float v_ly;
varying float v_surface;
varying float v_shade;
varying vec3 v_wn;

const vec3 COATS[12] = vec3[12](vec3(0.040, 0.045, 0.060), vec3(0.075, 0.055, 0.045), vec3(0.045, 0.065, 0.085), vec3(0.085, 0.080, 0.070),
		vec3(0.015, 0.20, 0.24), vec3(0.24, 0.035, 0.12), vec3(0.10, 0.10, 0.11), vec3(0.075, 0.045, 0.18),
		vec3(0.19, 0.13, 0.065), vec3(0.075, 0.12, 0.05), vec3(0.14, 0.02, 0.025), vec3(0.03, 0.09, 0.11));
const vec3 SKINS[10] = vec3[10](vec3(0.30, 0.20, 0.16), vec3(0.44, 0.33, 0.27), vec3(0.16, 0.12, 0.10), vec3(0.17, 0.27, 0.33), vec3(0.27, 0.20, 0.36), vec3(0.20, 0.33, 0.28),
		vec3(0.46, 0.46, 0.43), vec3(0.42, 0.27, 0.07), vec3(0.07, 0.08, 0.20), vec3(0.34, 0.09, 0.06));
const vec3 ACCENTS[4] = vec3[4](vec3(0.02, 0.30, 0.36), vec3(0.34, 0.04, 0.17), vec3(0.42, 0.22, 0.02), vec3(0.20, 0.07, 0.40));
const vec3 EYES[3] = vec3[3](vec3(0.1, 0.9, 1.0), vec3(1.0, 0.55, 0.1), vec3(1.0, 0.15, 0.55));
const vec3 HIVIS = vec3(0.95, 0.30, 0.012);
const vec3 HARDHAT = vec3(0.62, 0.50, 0.02);
const vec3 ARMOUR = vec3(0.030, 0.034, 0.042);
const vec3 ARMOUR_TRIM = vec3(0.30, 0.018, 0.035);
const vec3 GUARD_EYE = vec3(1.0, 0.10, 0.06);

// Archetypes (13): 0 commuter (long coat, scarf), 1 hoodie, 2 umbrella carrier, 3 tall hybrid (crest, visor), 4 courier (hood, backpack), 5 heavy (broad, hood, long coat),
// 6 sylph (very tall, long neck, small head, long arms, antennae), 7 stocky porter (short, wide, big head), 8 mantled monk (cape, hood, robe, elongated skull, gliding walk),
// 9 vendor (wide hat, tray of glowing wares carried in front), 10 worker (hi-vis vest with reflective bands, hard hat, tool bag), 11 guard (helmet, pauldrons, visor, armour), 12 child.
// The crowd gives slot i the group i % 6; inside a group the fraction r of seed * 6 picks the archetype: r < CUT.x -> OPT.x, r < CUT.y -> OPT.y, else OPT.z.
const ivec3 ARCH_OPT[6] = ivec3[6](ivec3(0, 9, 11), ivec3(1, 12, 12), ivec3(2, 8, 8), ivec3(3, 6, 6), ivec3(4, 10, 10), ivec3(5, 7, 7));
const vec2 ARCH_CUT[6] = vec2[6](vec2(0.52, 0.85), vec2(0.6, 1.0), vec2(0.76, 1.0), vec2(0.6, 1.0), vec2(0.55, 1.0), vec2(0.5, 1.0));
// pieces worn per archetype (bit k = piece id k: 1 hood / helmet shell, 2 coat tail, 3 backpack, 4 crest, 5 scarf, 6 visor, 7 mantle, 8 cap peak, 9 wide hat, 10 tray, 11 pauldrons, 13 antennae, 14 cowl)
const int WEAR[13] = int[13](4 | 32, 2 | 16384, 4, 4 | 16 | 32 | 64, 2 | 16384 | 8 | 32, 2 | 16384 | 4, 4 | 32 | 8192, 8 | 32, 2 | 16384 | 128 | 4, 512 | 1024 | 32, 2 | 256 | 8, 2 | 64 | 2048 | 4, 2 | 16384 | 8);
// species skins: (first palette index, count), the guard is a Vael (dark indigo)
const ivec2 SKIN_SET[13] = ivec2[13](ivec2(0, 3), ivec2(0, 4), ivec2(0, 3), ivec2(3, 3), ivec2(0, 3), ivec2(2, 2), ivec2(5, 2), ivec2(7, 3), ivec2(8, 2), ivec2(4, 3), ivec2(0, 3), ivec2(8, 1), ivec2(0, 6));
// body build (width, height, depth)
const vec3 BUILD[13] = vec3[13](vec3(1.0, 1.0, 1.0), vec3(1.0, 0.98, 1.0), vec3(1.0, 1.0, 1.0), vec3(0.92, 1.1, 0.92), vec3(0.97, 0.95, 0.97), vec3(1.2, 1.0, 1.15), vec3(0.8, 1.2, 0.82),
		vec3(1.3, 0.8, 1.25), vec3(1.0, 1.08, 1.0), vec3(1.08, 0.96, 1.12), vec3(1.08, 1.02, 1.05), vec3(1.12, 1.06, 1.12), vec3(0.62, 0.62, 0.62));
// head scale (x, y, z) and extra neck length in metres
const vec4 HEADS[13] = vec4[13](vec4(1.0, 1.0, 1.0, 0.0), vec4(1.0, 1.0, 1.0, 0.0), vec4(1.0, 1.0, 1.0, 0.0), vec4(0.95, 1.1, 0.95, 0.04), vec4(1.0, 1.0, 1.0, 0.0), vec4(1.05, 1.0, 1.05, 0.0), vec4(0.82, 0.95, 0.82, 0.3),
		vec4(1.12, 1.0, 1.1, 0.0), vec4(0.9, 1.2, 0.9, 0.05), vec4(1.05, 1.0, 1.05, 0.0), vec4(1.0, 1.0, 1.0, 0.0), vec4(1.0, 1.0, 1.0, 0.0), vec4(1.35, 1.35, 1.3, 0.0));
// limbs: arm length, leg swing, arm swing, bounce
const vec4 LIMBS[13] = vec4[13](vec4(1.0, 1.0, 1.0, 1.0), vec4(1.0, 1.0, 0.3, 0.9), vec4(1.0, 1.0, 1.0, 1.0), vec4(1.12, 1.1, 0.9, 0.8), vec4(1.0, 1.15, 1.2, 1.3), vec4(0.92, 0.9, 0.8, 0.8), vec4(1.3, 1.1, 0.7, 0.6),
		vec4(0.85, 0.8, 1.1, 1.2), vec4(1.0, 0.5, 0.35, 0.3), vec4(1.0, 0.8, 0.0, 0.8), vec4(1.0, 1.05, 1.1, 1.0), vec4(0.95, 0.95, 0.45, 0.7), vec4(1.0, 1.2, 1.3, 1.5));
// gait: stride rate (multiplies the walk phase), forward lean, side roll (waddle), shoulder twist
const vec4 GAIT[13] = vec4[13](vec4(1.0, 0.03, 0.0, 0.03), vec4(1.05, 0.12, 0.0, 0.0), vec4(0.95, 0.0, 0.0, 0.02), vec4(0.9, 0.0, 0.0, 0.05), vec4(1.25, 0.12, 0.0, 0.02), vec4(0.85, 0.02, 0.05, 0.0), vec4(0.7, 0.0, 0.02, 0.08),
		vec4(1.35, 0.0, 0.07, 0.0), vec4(0.75, 0.0, 0.0, 0.0), vec4(0.9, -0.03, 0.03, 0.0), vec4(0.95, 0.05, 0.015, 0.0), vec4(0.95, 0.0, 0.0, 0.04), vec4(1.45, 0.0, 0.05, 0.0));

int archetype_of(float seed) {
	float g = clamp(seed * 6.0, 0.0, 5.999);
	int gi = int(floor(g));
	float r = fract(g);
	return r < ARCH_CUT[gi].x ? ARCH_OPT[gi].x : (r < ARCH_CUT[gi].y ? ARCH_OPT[gi].y : ARCH_OPT[gi].z);
}

vec3 rot_yz(vec3 v, float py, float a) {                // pitch about the x axis through height py (positive = backward at the top)
	float c = cos(a);
	float s = sin(a);
	float y = v.y - py;
	return vec3(v.x, y * c - v.z * s + py, y * s + v.z * c);
}

vec3 rot_xz(vec3 v, float a) {                          // yaw about the vertical axis through the origin
	float c = cos(a);
	float s = sin(a);
	return vec3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

void vertex() {
	float seed = INSTANCE_CUSTOM.x;
	float amp = INSTANCE_CUSTOM.z;
	float flags = INSTANCE_CUSTOM.w;
	int arch = archetype_of(seed);
	float h1 = fract(seed * 37.17 + 0.13);
	float h2 = fract(seed * 91.71 + 0.37);
	float h3 = fract(seed * 13.31 + 0.71);
	float h4 = fract(seed * 53.7 + 0.29);
	float h5 = fract(seed * 23.9 + 0.57);
	v_surface = COLOR.r;
	v_arch = float(arch);
	int piece = int(floor(COLOR.g * 20.0 + 0.5));
	v_piece = float(piece);
	v_ly = VERTEX.y;
	// palettes: coats (vendors and children bright, monks in robe colours), skin by species, accent, eyes
	int ci = int(floor(h1 * 7.99));
	if (arch == 9 || arch == 12) {
		ci = 4 + int(floor(h1 * 3.99));
	} else if (arch == 8) {
		ci = 7 + int(floor(h1 * 4.99));
	}
	v_tint = COATS[ci];
	ivec2 ss = SKIN_SET[arch];
	v_skin = SKINS[ss.x + int(floor(h2 * (float(ss.y) - 0.01)))];
	v_eye = arch == 11 ? GUARD_EYE : EYES[int(floor(h3 * 2.99))];
	v_accent = arch == 10 ? HARDHAT : (arch == 11 ? ARMOUR_TRIM : ACCENTS[int(floor(h2 * 3.99))]);
	v_mark = (arch == 3 || arch == 6 || arch == 8) ? 1.0 : 0.0;
	int mask = WEAR[arch];
	v_hood = (mask & 2) != 0 ? 1.0 : 0.0;
	v_shade = COLOR.b;
	if (abs(COLOR.b - 0.55) < 0.01 && v_hood < 0.5) {
		v_shade = 0.92;                                    // the face patch is only dim under a hood
	}
	vec3 o = MODEL_MATRIX[3].xyz;
	v_pool = textureLod(light_map, (o.xz - light_rect.xy) / light_rect.zw, 0.0).rgb;
	float tag = COLOR.a;
	bool is_umb = tag > 0.95;
	bool is_tail = tag > 0.85 && !is_umb;
	bool is_arm = tag > 0.5 && tag < 0.85;
	bool is_leg = tag > 0.1 && tag < 0.5;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	bool show = true;
	if (is_umb) {
		show = arch <= 5 && fract(flags * 0.5) > 0.25;
	} else if (piece > 0) {
		show = (mask & (1 << piece)) != 0;
	}
	vec4 H = HEADS[arch];
	vec4 L = LIMBS[arch];
	vec4 G = GAIT[arch];
	// ---- state and the pose it asks for
	bool cower = amp < -0.05;
	bool flee = amp > 1.5;
	bool idle = abs(amp) <= 0.05;
	float ph = INSTANCE_CUSTOM.y * G.x;
	float clk = TIME + seed * 97.0;
	float sw = sin(ph) * max(amp, 0.0) * 0.62;
	float aL = 0.0;                                        // arm pitch (positive = raised forward), left / right
	float aR = 0.0;
	float lgL = 0.0;                                       // leg swing
	float lgR = 0.0;
	float lean = 0.0;                                      // upper body forward lean (shear per metre above the hips)
	float roll = 0.0;                                      // upper body sideways sway
	float twist = 0.0;
	float nod = 0.0;                                       // head pitch / yaw
	float yaw = 0.0;
	float bounce = 0.0;
	float fold = 0.0;                                      // arms drawn in towards the midline (clasped hands)
	float crouch = 0.0;
	float breath = 0.0;
	if (cower) {
		crouch = 1.0;
		lean = 0.3;
		aL = 2.1 + 0.1 * sin(clk * 23.0);                  // hands pulled in over the head
		aR = 2.1 + 0.1 * sin(clk * 19.0 + 1.7);
		fold = 0.85;
		nod = 0.4;
		roll = 0.01 * sin(clk * 21.0);
	} else if (idle) {
		float kind = h4;                                   // 0 talk, 1 stand, 2 check a wrist device, 3 hands clasped
		if (arch == 11) {
			kind = h4 < 0.5 ? 0.5 : 0.9;
		}
		if (flags > 1.5) {
			kind = 0.0;
		}
		breath = sin(clk * 1.9);
		roll = 0.012 * sin(clk * 0.6 + h5 * 6.0);
		yaw = 0.3 * sin(clk * 0.45 + h5 * 6.28) * (1.0 + step(0.4, kind));
		aL = 0.04 * sin(clk * 1.1);
		aR = -0.04 * sin(clk * 1.1);
		if (kind < 0.4) {                                  // talk: the right hand gestures, the head nods and turns, the body sways
			aR = 0.9 + 0.45 * sin(clk * 3.1) + 0.25 * sin(clk * 5.3 + 1.0);
			aL = 0.3 + 0.3 * sin(clk * 2.3 + 2.0) * step(0.5, fract(clk * 0.07 + h5));
			nod = 0.05 * sin(clk * 4.1) - 0.02;
			yaw = 0.28 * sin(clk * 0.8 + h5 * 6.0);
			roll = 0.03 * sin(clk * 1.3 + h5 * 6.0);
			twist = 0.1 * sin(clk * 1.1);
		} else if (kind < 0.65) {                          // stand: weight shifts, a slow look around
			roll = 0.02 * sin(clk * 0.5 + h5 * 6.0);
		} else if (kind < 0.85) {                          // a wrist device: the left hand up, the head down
			aL = 0.95 + 0.05 * sin(clk * 1.7);
			nod = 0.2;
			yaw = 0.0;
		} else {                                           // hands clasped in front
			aL = 0.5;
			aR = 0.5;
			fold = 0.7;
		}
	} else {
		lgL = sw * L.y;
		lgR = -sw * L.y;
		aL = -sw * 0.8 * L.z;
		aR = sw * 0.8 * L.z;
		bounce = abs(sin(ph)) * 0.035 * amp * L.w;
		lean = G.y;
		roll = sin(ph) * G.z;
		twist = sin(ph) * G.w;
		if (flee) {
			lean += 0.3;
			nod = 0.12;
			if (h5 < 0.5 || arch == 12) {                  // panic: hands up and flapping
				aL = 2.2 + 0.3 * sin(ph * 2.0);
				aR = 2.2 + 0.3 * sin(ph * 2.0 + 1.3);
			} else if (arch != 11) {                       // sprint: arms pumping wider
				aL *= 1.25;
				aR *= 1.25;
			}
		} else {
			yaw = 0.12 * sin(ph * 0.5 + h5 * 6.0);
		}
	}
	if (arch == 9 && !cower) {                             // the vendor holds the tray out in front of the body
		aL = 1.05 + 0.02 * sin(clk * 1.3);
		aR = 1.05 + 0.02 * sin(clk * 1.3 + 0.8);
		fold = 0.0;
	}
	// ---- head: proportions (scale about the neck, extra neck) and the nod / turn of the head
	float hw = (is_arm || is_umb) ? 0.0 : smoothstep(1.50, 1.58, v.y);
	if (hw > 0.0) {
		v.x *= mix(1.0, H.x, hw);
		v.z *= mix(1.0, H.z, hw);
		v.y = 1.58 + (v.y - 1.58) * mix(1.0, H.y, hw) + H.w * hw;
	}
	// ---- limbs
	vec3 piv = vec3(0.0);
	float ang = 0.0;
	if (is_umb) {
		// umbrella: no animation
	} else if (is_tail) {
		ang = -0.1 - 0.22 * abs(sw) + 0.05 * sin(INSTANCE_CUSTOM.y * 2.0) - (flee ? 0.25 : 0.0); piv = vec3(0.0, 0.93, 0.0);
		v.x += sin(INSTANCE_CUSTOM.y + v.y * 5.0) * 0.025 * (1.0 - clamp((v.y - 0.3) * 1.5, 0.0, 1.0));
		if (idle) {
			ang = -0.08 + 0.02 * sin(clk * 0.9);
		}
	} else if (is_arm) {
		float side = tag > 0.7 ? 1.0 : -1.0;
		piv = vec3(0.27 * side, 1.42, 0.0);
		v.y = piv.y + (v.y - piv.y) * L.x;
		ang = side > 0.0 ? aR : aL;
	} else if (is_leg) {
		float side = tag > 0.3 ? 1.0 : -1.0;
		piv = vec3(0.1 * side, 0.9, 0.0);
		ang = side > 0.0 ? lgR : lgL;
		if (crouch > 0.5) {
			v.y *= 0.62;
			piv.y *= 0.62;
		}
	}
	if (ang != 0.0) {
		float cs = cos(ang);
		float sn = sin(ang);
		v -= piv;
		v = vec3(v.x, v.y * cs - v.z * sn, v.y * sn + v.z * cs) + piv;
		n = vec3(n.x, n.y * cs - n.z * sn, n.y * sn + n.z * cs);
	}
	if (is_arm && fold > 0.0) {
		v.x *= 1.0 - 0.65 * fold;
	}
	// ---- body: crouch, lean, sway, shoulder twist, head, breath, bounce
	if (!is_leg) {
		v.y -= 0.34 * crouch;
		float h = max(VERTEX.y - 0.9, 0.0);
		v.z -= lean * h;
		v.x += roll * h;
		v.y += breath * 0.006 * smoothstep(1.2, 1.5, VERTEX.y);
		if (twist != 0.0) {
			v = rot_xz(v, twist * clamp(h * 2.5, 0.0, 1.0));
		}
		if (hw > 0.0) {
			v = mix(v, rot_xz(rot_yz(v, 1.56 - 0.34 * crouch, -nod), yaw), hw);   // nod > 0 = head forward / down
		}
	}
	v.y += bounce;
	v *= BUILD[arch];
	VERTEX = show ? v * (1.0 - smoothstep(lod_range_far * 0.8, lod_range_far, distance(o.xz, CAMERA_POSITION_WORLD.xz))) : vec3(0.0);
	NORMAL = n;
	v_wn = (MODEL_MATRIX * vec4(n, 0.0)).xyz;
}

void fragment() {
	float s = v_surface;
	int arch = int(v_arch + 0.5);
	int piece = int(v_piece + 0.5);
	vec3 skin = v_skin;
	vec3 coat = v_tint;
	float is_coat = step(0.85, s);
	float armour = 0.0;
	float stripe = 0.0;
	if (arch == 10) {                                                      // worker: hi-vis vest and sleeves, dark work trousers, reflective bands around chest, waist and sleeves
		coat = HIVIS;
		stripe = step(abs(v_ly - 1.055), 0.03) + step(abs(v_ly - 1.30), 0.03);
	} else if (arch == 11) {                                               // guard: gunmetal armour
		coat = ARMOUR;
		armour = is_coat;
	}
	vec3 col = coat;                                                       // 1.0 coat
	col = mix(col, v_accent, step(s, 0.85));                               // 0.7 accent
	col = mix(col, (arch == 10 ? vec3(0.03, 0.04, 0.06) : coat * 0.35), step(s, 0.62));   // 0.5 trousers
	col = mix(col, vec3(0.025, 0.025, 0.03), step(s, 0.4));                // 0.3 dark: hair, shoes, gloves, ribs
	col = mix(col, vec3(0.01), step(s, 0.22));                             // 0.15 visor
	col = mix(col, skin, step(s, 0.07));                                   // 0 skin
	if (piece == 1 && is_coat > 0.5 && (arch == 10 || arch == 11)) {
		col = v_accent;                                                    // the hood shell is a hard hat / helmet on workers and guards
	}
	float band = stripe * is_coat * step(float(piece), 0.0);
	col = mix(col, vec3(0.55, 0.57, 0.60), band);                          // retroreflective band
	col *= v_shade;
	float wet = clamp(wetness, 0.0, 1.0);
	float skin_mask = step(s, 0.07);
	float mark = v_mark * skin_mask * step(0.35, sin(v_ly * 70.0));        // faint glowing stripes on the skin of the tall species
#ifdef MIRROR
	ALBEDO = col * vec3(0.05, 0.07, 0.09) + col * v_pool * 0.6;
#else
	ALBEDO = col;
	ROUGHNESS = mix(0.8, 0.42, wet * is_coat);
	ROUGHNESS = mix(ROUGHNESS, 0.36, armour);
	METALLIC = 0.55 * armour;
	SPECULAR = 0.4;
	// the street lights the passers-by: baked lamp and neon pools plus a cool rim, so a silhouette separates from the wet dark ground
	vec3 nv = normalize(NORMAL);
	float rim = pow(1.0 - clamp(dot(nv, normalize(VIEW)), 0.0, 1.0), 3.0);
	vec3 up = (INV_VIEW_MATRIX * vec4(nv, 0.0)).xyz;
	vec3 fill = vec3(0.020, 0.030, 0.042) * (0.5 + 0.5 * clamp(up.y * 0.5 + 0.5, 0.0, 1.0));
	float visor = step(0.1, s) * step(s, 0.2);
	EMISSION = col * (v_pool * 0.8 + fill * 6.0) + vec3(0.10, 0.20, 0.28) * rim * 0.55 * v_shade + v_eye * visor * 1.6 + v_eye * mark * 0.5 + vec3(0.5, 0.52, 0.55) * band * 0.25;
#endif
}
