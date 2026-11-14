shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// The roster enemies (wave 113, enemy look v3; scripts/roster/foe_looks.gd, foe_human.gd): ONE surface, ONE draw call, NO texture. The vertex colour picks the material of a triangle
// (merged by HeroCharacter._merge): COLOR.r = mode (0 body suit / skin, 1 gear), COLOR.g = suit weight of the body (cloth 1, skin 0), COLOR.b = kind / 16 (the palette slot, FoeKit.KIND_*),
// COLOR.a = glow zone (FoeKit.ZONE_*). Gear parts carry baked ambient occlusion in UV.x and convex edge wear in UV.y (tools/blender/enemykit/lib.py), UV2.x = the health pip index.
// The look is a PALETTE (plate A / B, trim, fabric A / B, cloth, jacket, pants, skin, glow colours: three variants per look). Plates read as painted composite with bare edges, glass as a dark
// glossy visor, glow parts shine in the role colour, the health pips light up with `hp_k`, a telegraph (`tele`) makes the weapon, the visor and the charges flare.
// Uniforms with the names of assets/shaders/alien.gdshader (dissolve, cloak, shield, pulse, beat, rage, dust, body_h) so the alien death, the cloak and the shield of AlienCreature work unchanged.

uniform vec3 plate_a : source_color = vec3(0.2, 0.22, 0.27);
uniform vec3 plate_b : source_color = vec3(0.12, 0.13, 0.16);
uniform vec3 trim : source_color = vec3(0.9, 0.9, 0.95);
uniform vec3 fabric_a : source_color = vec3(0.2, 0.2, 0.15);
uniform vec3 fabric_b : source_color = vec3(0.1, 0.1, 0.09);
uniform vec3 cloth_g : source_color = vec3(0.15, 0.17, 0.11);
uniform vec3 jacket : source_color = vec3(0.12, 0.13, 0.16);
uniform vec3 pants : source_color = vec3(0.08, 0.09, 0.11);
uniform vec3 skin : source_color = vec3(0.45, 0.3, 0.24);
uniform vec3 glow_col : source_color = vec3(1.0, 0.2, 0.2);
uniform vec3 weak_col : source_color = vec3(1.0, 0.6, 0.1);
uniform float glow_k = 2.4;
uniform float shell : hint_range(0.0, 1.0) = 0.6;
uniform float wear : hint_range(0.0, 1.0) = 0.7;
uniform float plate_metal : hint_range(0.0, 1.0) = 0.3;
uniform float brightness : hint_range(0.3, 2.0) = 1.0;
// alien-shader compatible state (material parameters: every body owns a material)
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform vec3 dust = vec3(0.35, 0.95, 1.0);
uniform float body_h = 2.0;
uniform float cloak : hint_range(0.0, 1.0) = 0.0;
uniform float shield : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float beat = 1.0;
uniform float rage : hint_range(0.0, 1.0) = 0.0;
// per instance (set through MeshInstance3D.set_instance_shader_parameter: the mid and far meshes and their material are shared by every enemy of a look)
instance uniform float far_k : hint_range(0.0, 1.0) = 0.0;       // readability at 20-80 m: a thin edge glow in the accent colour (see the end of fragment())
instance uniform float hit_k : hint_range(0.0, 1.0) = 0.0;       // white-hot flash of a hit
instance uniform float hp_k : hint_range(0.0, 1.0) = 1.0;        // health 0..1: the pips
instance uniform float tele : hint_range(0.0, 1.0) = 0.0;        // telegraph of a special attack 0..1
instance uniform vec4 dmg_fx = vec4(0.0);                        // scripts/damage/foe_fx.gd: x = state (1 burning, 2 frozen, 3 shocked, 4 dissolving), y = strength

varying flat float v_mode;
varying flat float v_kind;
varying flat float v_zone;
varying float v_suit;
varying float v_pip;
varying vec3 v_pos;
varying float v_up;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	v_mode = floor(COLOR.r * 4.0 + 0.5);
	v_suit = COLOR.g;
	v_kind = floor(COLOR.b * 16.0 + 0.5);
	v_zone = floor(COLOR.a * 8.0);
	v_pip = UV2.x;
	v_pos = VERTEX;
	v_up = clamp(normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y * 0.5 + 0.5, 0.0, 1.0);      // 1 = the face looks up
}

void fragment() {
	if (dissolve > 0.001) {
		float h = clamp(v_pos.y / body_h, 0.0, 1.0);
		float n = hash13(floor(v_pos * (28.0 / body_h * 2.0))) * 0.7 + 0.3 * hash13(floor(v_pos * (8.0 / body_h * 2.0)) + 7.0);
		float edge_t = dissolve * 1.3 - (1.0 - h) * 0.25 + 0.02;
		if (n < edge_t) {
			discard;
		}
		EMISSION = dust * smoothstep(edge_t + 0.2, edge_t, n) * 2.4;
	}
	float drop = 0.0;
	if (cloak > 0.001) {
		vec2 sp = floor(FRAGCOORD.xy * 0.5);
		float d = fract(sin(dot(sp, vec2(12.9898, 78.233))) * 43758.5453);
		drop = cloak;
		if (d < cloak * 0.86) {
			discard;
		}
	}
	float gear = step(0.5, v_mode);
	float ao = mix(1.0, clamp(UV.x, 0.0, 1.0), gear);
	float edge = gear * clamp(UV.y, 0.0, 1.0);
	vec3 alb = vec3(0.1);
	float rough = 0.6;
	float metal = 0.0;
	float spec = 0.5;
	vec3 emis = vec3(0.0);
	float k = v_kind;
	float nz = hash13(floor(v_pos * 34.0));
	if (gear < 0.5) {
		float cl = smoothstep(0.35, 0.65, v_suit);
		vec3 suit = mix(pants, jacket, smoothstep(0.88, 1.0, v_pos.y));
		alb = mix(skin, suit * (0.92 + 0.16 * nz), cl);
		rough = mix(0.55, 0.9, cl);
		spec = mix(0.45, 0.2, cl);
		emis += (1.0 - cl) * skin * 0.16;
	} else if (k < 1.5) {
		alb = plate_a;
		rough = 0.46;
		metal = plate_metal;
	} else if (k < 2.5) {
		alb = plate_b;
		rough = 0.5;
		metal = plate_metal * 0.8;
	} else if (k < 3.5) {
		alb = trim;
		rough = 0.5;
		metal = 0.1;
	} else if (k < 4.5) {
		alb = vec3(0.075, 0.082, 0.095);
		rough = 0.38;
		metal = 0.6;
	} else if (k < 5.5) {
		alb = vec3(0.04, 0.04, 0.044);
		rough = 0.92;
		spec = 0.2;
	} else if (k < 6.5) {
		alb = fabric_a * (0.9 + 0.2 * nz);
		rough = 0.95;
		spec = 0.15;
	} else if (k < 7.5) {
		alb = fabric_b * (0.9 + 0.2 * nz);
		rough = 0.95;
		spec = 0.15;
	} else if (k < 8.5) {
		alb = vec3(0.015, 0.02, 0.03);
		rough = 0.07;
		metal = 0.2;
		spec = 0.9;
		float fr = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.5);
		emis += glow_col * (0.05 + 0.35 * fr);
	} else if (k < 9.5) {
		alb = vec3(0.02);
		float z = v_zone;
		if (z < 1.5) {
			emis = glow_col * glow_k * (0.75 + 0.25 * sin(TIME * 3.0 + v_pos.x * 12.0)) * (1.0 + 2.2 * tele);
		} else if (z < 2.5) {
			emis = weak_col * glow_k * (0.6 + 0.5 * sin(TIME * 4.5));
		} else if (z < 3.5) {
			float lit = step(v_pip, hp_k + 0.001);
			vec3 pc = mix(vec3(1.0, 0.12, 0.08), vec3(0.2, 1.0, 0.4), smoothstep(0.25, 0.75, hp_k));
			emis = pc * 2.2 * lit + vec3(0.02, 0.025, 0.03) * (1.0 - lit);
		} else if (z < 4.5) {
			emis = glow_col * (0.5 + 0.12 * sin(TIME * 5.0)) * glow_k * 0.5 * (1.0 + 3.2 * tele);
		} else if (z < 5.5) {
			emis = trim * 1.4;
		} else {
			emis = vec3(1.0, 0.6, 0.2) * 2.4;
		}
	} else if (k < 10.5) {
		alb = vec3(0.55, 0.42, 0.18);
		rough = 0.4;
		metal = 0.85;
	} else if (k < 11.5) {
		float nz2 = hash13(floor(v_pos * 90.0));
		alb = cloth_g * (0.8 + 0.4 * nz2) * (0.85 + 0.3 * nz);
		rough = 1.0;
		spec = 0.1;
	} else if (k < 12.5) {
		alb = vec3(0.78, 0.8, 0.76);
		rough = 0.55;
	} else if (k < 13.5) {
		float s = step(0.5, fract((v_pos.x + v_pos.y * 1.3 + v_pos.z) * 16.0));
		alb = mix(vec3(0.03), vec3(0.85, 0.65, 0.05), s);
		rough = 0.6;
	} else if (k < 14.5) {
		alb = vec3(0.5, 0.52, 0.55);
		rough = 0.32;
		metal = 0.85;
	} else {
		alb = vec3(0.045, 0.048, 0.055);
		rough = 0.6;
		spec = 0.3;
	}
	// painted plates: the convex edges show worn bare metal
	float plate = step(k, 3.5) * gear + step(13.5, k) * step(k, 14.5) * gear;
	alb = mix(alb, alb * 1.7 + vec3(0.05), edge * wear * plate);
	alb *= (0.55 + 0.45 * ao);
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float edge_l = pow(1.0 - ndv, 4.0);                                      // only the very silhouette: a limb is 10 px wide at 20 m, so a softer falloff would colour the whole limb
	emis += trim * far_k * (0.002 + 0.14 * edge_l);                         // readability at distance: a faint rim light in the accent colour (a limb is only 4-8 px wide at 30 m, the silhouette pixels are all it has), never a body-wide wash
	emis += vec3(1.0, 0.35, 0.25) * pulse * (0.03 + 0.22 * edge_l);         // the roster's wind-up flash: a warm rim light, the kit stays readable (the weapon flares through `tele`)
	emis += glow_col * drop * 0.9;
	emis += vec3(1.0, 0.95, 0.85) * hit_k * 0.9;
	emis += vec3(0.016, 0.018, 0.024) * (0.5 + 0.5 * v_up) * (1.0 - 0.6 * metal);                 // a readability floor: dark armour keeps its forms in overcast, rain and night light (it went black in the real game), faces that look up are lighter
	if (shield > 0.001) {
		float hx = hash13(floor(v_pos * 6.0));
		emis += vec3(0.3, 0.9, 1.0) * shield * (rim * 1.6 + 0.12 + 0.18 * hx * (0.5 + 0.5 * sin(TIME * 3.0 + hx * 6.28)));
	}
	if (dmg_fx.y > 0.001) {
		float flick = 0.5 + 0.5 * sin(TIME * 19.0 + v_pos.y * 43.0 + v_pos.x * 27.0);
		float s = dmg_fx.y;
		if (dmg_fx.x < 1.5) {
			alb = mix(alb, vec3(0.02, 0.017, 0.016), 0.7 * s);
			emis += vec3(1.0, 0.3, 0.04) * s * (0.15 + 0.7 * flick * flick) * (0.35 + 0.65 * (1.0 - clamp(v_pos.y / 1.9, 0.0, 1.0)));
		} else if (dmg_fx.x < 2.5) {
			alb = mix(alb, vec3(0.62, 0.82, 0.96), 0.72 * s);
			rough = mix(rough, 0.1, s);
			emis += vec3(0.12, 0.28, 0.5) * s;
		} else if (dmg_fx.x < 3.5) {
			emis += vec3(0.45, 0.7, 1.0) * s * step(0.5, fract(TIME * 14.0 + v_pos.y * 3.0)) * 1.3;
		} else {
			float dn = hash13(floor(v_pos * 70.0));
			if (dn < s * 0.85) {
				discard;
			}
			emis += vec3(0.6, 0.25, 1.0) * smoothstep(s * 0.85, s * 0.85 + 0.15, dn) * s * 2.0;
		}
	}
	// readability at distance (far_k 0..0.55 from 9 m, set by RosterHuman): beyond 20 m the paint is lifted and a little more saturated, a 20 px figure only has its overall hue and value to say whose it is
	float far_lum = dot(alb, vec3(0.3, 0.59, 0.11));
	alb = max(mix(vec3(far_lum), alb, 1.0 + 0.8 * far_k), vec3(0.0)) * (1.0 + 0.9 * far_k);
	ALBEDO = alb * brightness;
	ROUGHNESS = clamp(rough + 0.0, 0.04, 1.0);
	METALLIC = metal;
	SPECULAR = spec * mix(0.6, 1.0, shell);
	AO = ao;
	AO_LIGHT_AFFECT = 0.4;
	EMISSION += emis;
}
