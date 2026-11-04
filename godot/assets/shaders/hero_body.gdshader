shader_type spatial;
render_mode cull_disabled;
// The superhero (HeroCharacter, scripts/characters/hero_character.gd): ONE surface for the whole hero, one draw call.
// The vertex colour picks the material of a triangle: COLOR.r = mode (0 skin / suit, 0.25 eye, 0.5 hair 1, 0.75 hair 2, 1 gear), COLOR.g = suit weight (smooth: the suit covers
// everything except head, neck and hands). Skin, eyes and hair keep their own PBR maps (albedo, Godot / Y+ normal, roughness); the suit is the quantum-realism layer:
// graphite fabric that keeps the baked muscle shading and the normal map, thin-film iridescence on the grazing rim and on the seams (side stripes, centre line, wrist / neck / ankle
// rings), tinted by the hero look (HeroLook) and driven by the abilities: `trim_color` (hue drifts with time, QUANTUM TELEPORT aim pushes it to violet), `charge`, `ready_k`, `excite`.
uniform sampler2D skin_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D skin_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D skin_rough : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D eye_albedo : source_color, filter_linear_mipmap;
uniform sampler2D eye_normal : hint_normal, filter_linear_mipmap;
uniform sampler2D hair1_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D hair1_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D hair2_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D hair2_normal : hint_normal, filter_linear_mipmap, repeat_enable;

uniform vec3 hair_color : source_color = vec3(0.16, 0.11, 0.085);
uniform vec3 suit_color : source_color = vec3(0.2, 0.23, 0.3);
uniform vec3 look_tint : source_color = vec3(1.0);
uniform float suit_metal : hint_range(0.0, 1.0) = 0.3;
uniform float suit_rough : hint_range(0.0, 1.0) = 0.5;
uniform vec3 trim_color : source_color = vec3(0.2, 0.95, 1.0);
uniform vec3 accent : source_color = vec3(0.2, 0.95, 1.0);
uniform float accent_mix : hint_range(0.0, 1.0) = 0.0;
uniform float glow : hint_range(0.0, 4.0) = 1.0;
uniform float ready_k : hint_range(0.0, 1.0) = 1.0;
uniform float charge : hint_range(0.0, 1.0) = 0.0;
uniform float excite : hint_range(0.0, 1.0) = 0.0;
uniform float film_seed : hint_range(0.0, 1.0) = 0.31;
uniform vec3 skin_mult : source_color = vec3(1.0);
uniform float scalp : hint_range(0.0, 1.0) = 0.0;     // 1 with a hair style: the crown above the hair line takes the hair colour (the hair cards cover only the lower part)
uniform float scalp_y = 1.7;
uniform float scalp_z = 0.0;
uniform float brightness : hint_range(0.2, 2.0) = 1.0;

varying flat float v_mode;
varying float v_suit;
varying vec3 v_pos;
varying vec3 v_nrm;

float h11(float x) { return fract(sin(x * 127.1) * 43758.5453); }

void vertex() {
	v_mode = floor(COLOR.r * 4.0 + 0.5);
	v_suit = COLOR.g;
	v_pos = VERTEX;
	v_nrm = NORMAL;
}

void fragment() {
	vec3 nm = vec3(0.5, 0.5, 1.0);
	float nd = 1.0;
	float suit = 0.0;
	vec3 alb;
	float rough;
	float metal = 0.0;
	float spec = 0.5;
	vec3 emis = vec3(0.0);
	if (v_mode < 0.5) {
		alb = texture(skin_albedo, UV).rgb * skin_mult;
		nm = texture(skin_normal, UV).rgb;
		rough = clamp(texture(skin_rough, UV).r * 0.8 + 0.1, 0.12, 1.0);
		spec = 0.45;
		float crown = scalp * smoothstep(0.0, 0.02, v_pos.y - scalp_y - 0.6 * max(v_pos.z - scalp_z, 0.0)) * (1.0 - smoothstep(0.3, 0.6, v_suit));
		alb = mix(alb, hair_color * 0.85, crown);
		rough = mix(rough, 0.6, crown);
		suit = smoothstep(0.35, 0.65, v_suit);
		if (suit > 0.001) {
			float lum = dot(alb, vec3(0.299, 0.587, 0.114));
			vec3 fabric = suit_color * look_tint * (0.55 + 1.5 * lum);
			float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
			float rim = pow(1.0 - ndv, 2.6);
			float ph = (0.7 + 1.3 * film_seed) * (1.0 - 0.55 * ndv) * 12.566;
			vec3 film = 0.5 + 0.5 * cos(vec3(0.0, 2.094, 4.188) + ph * vec3(1.0, 1.13, 1.27));
			film = mix(film, trim_color, 0.55);
			film = mix(film, accent, accent_mix);
			// seams: side stripes where the surface faces sideways, a centre line, rings at the wrists, ankles and neck (the ends of the suit)
			float side = 1.0 - smoothstep(0.0, 0.05, abs(abs(v_nrm.x) - 0.9));
			float centre = (1.0 - smoothstep(0.0, 0.006, abs(v_pos.x))) * step(0.95, abs(v_nrm.z));
			float ends = 1.0 - smoothstep(0.0, 0.1, abs(v_suit - 0.52)) ;
			float seam = clamp(side * 0.8 + centre + ends * 1.2, 0.0, 1.0);
			float slot = floor(TIME * 0.4 + film_seed * 97.0);
			float flick = step(0.975, h11(slot * 1.37 + film_seed * 13.0)) * step(0.5, h11(floor(TIME * 17.0) + film_seed * 5.0));
			float k = (0.35 + 0.65 * ready_k) * (1.0 + 0.9 * charge + 0.6 * excite) * glow;
			alb = mix(alb, fabric, suit);
			alb = mix(alb, film * 0.5, suit * rim * 0.5);
			emis = suit * film * (seam * 0.6 * k + rim * 0.7 * k + flick * 0.18);
			rough = mix(rough, suit_rough, suit);
			metal = suit * (suit_metal + 0.3 * rim);
			nd = mix(1.0, 0.55, suit);
		}
	} else if (v_mode < 1.5) {
		alb = texture(eye_albedo, UV).rgb;
		nm = texture(eye_normal, UV).rgb;
		rough = 0.12;
		spec = 0.9;
	} else if (v_mode < 2.5) {
		alb = texture(hair1_albedo, UV).rgb * hair_color * 2.6;
		nm = texture(hair1_normal, UV).rgb;
		rough = 0.58;
		spec = 0.35;
	} else if (v_mode < 3.5) {
		alb = texture(hair2_albedo, UV).rgb * hair_color * 2.6;
		nm = texture(hair2_normal, UV).rgb;
		rough = 0.58;
		spec = 0.35;
	} else {
		alb = vec3(0.13, 0.14, 0.155);
		rough = 0.42;
		metal = 0.55;
		float ndv2 = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
		emis = trim_color * pow(1.0 - ndv2, 3.0) * 0.18 * (0.4 + 0.6 * ready_k) * glow;
	}
	ALBEDO = alb * brightness;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = nd;
	EMISSION = emis;
}
