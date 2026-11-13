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

// HERO STYLE (wave 112, hero look v3): 1 for the player's hero (suit kit, graphite bodysuit, glow circuits), 0 for NPCs and enemies (the jacket / trousers zones below, unchanged).
uniform float hero_style : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D gear_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;     // the armour kit atlas (tools/blender/model_hero_suit.py): neutral baked albedo with wear
uniform sampler2D gear_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gear_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;  // R ambient occlusion, G roughness, B metallic
uniform float gear_tex : hint_range(0.0, 1.0) = 0.0;                      // 1 when the atlas textures are loaded (0: flat colours per kind)
uniform vec3 plate_col : source_color = vec3(0.5, 0.54, 0.62);           // multiplier of the neutral armour plates (the suit preset and scheme)
uniform vec3 trim_paint : source_color = vec3(0.1, 0.5, 0.58);           // painted accent plates
uniform vec3 cloth_col : source_color = vec3(0.045, 0.05, 0.065);        // the bodysuit
uniform vec3 cloth_col2 : source_color = vec3(0.1, 0.11, 0.14);          // belt and straps
uniform vec3 gold_col : source_color = vec3(0.78, 0.6, 0.28);
uniform float plate_metal : hint_range(0.0, 1.5) = 1.0;                   // scales the baked metallic of the plates
uniform float plate_rough : hint_range(-0.5, 0.5) = 0.0;                  // added to the baked roughness
// The glow of the circuits (HeroGlow): colour, intensity per zone (core, arms, hands, legs | wings, head), the travelling wave (x front 0..1.5, y strength)
uniform vec3 glow_rgb : source_color = vec3(0.2, 0.95, 1.0);
uniform vec4 gz_a = vec4(1.0, 0.6, 0.55, 0.5);
uniform vec2 gz_b = vec2(0.7, 0.35);
uniform vec2 gflow = vec2(-1.0, 0.0);
uniform float glow_gain : hint_range(0.0, 4.0) = 1.0;                     // overall brightness of the circuits (LOW / Compatibility tame it)
uniform vec3 hair_color : source_color = vec3(0.16, 0.11, 0.085);
uniform vec3 suit_color : source_color = vec3(0.2, 0.22, 0.27);
uniform vec3 jacket_color : source_color = vec3(0.43, 0.55, 0.69);     // the outfit: jacket and trousers (the hero's own, NPCs and enemies set theirs in HumanoidVariants.tint)
uniform vec3 pants_color : source_color = vec3(0.25, 0.28, 0.36);
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
// Enemy readability at 20-40 m (real-fight wave): Drone.update_lod sets this per instance from the camera distance (0 up to 10 m, 1 from 30 m). A body-wide glow in the trim colour, strongest on
// the edges, so a thin dark figure keeps its colour and outline against a dark street. Instance uniform: the mid-LOD mesh and its material are shared by every trooper of a look.
instance uniform float far_k : hint_range(0.0, 1.0) = 0.0;
// Hit flash of an enemy (Operative._hit_effect): the whole body flashes white-hot for ~0.12 s when a round lands, so a hit reads at 20 m (0 = off).
instance uniform float hit_k : hint_range(0.0, 1.0) = 0.0;

varying flat float v_mode;
varying flat float v_kindf;
varying flat float v_zone;
varying float v_path;
varying float v_suit;
varying vec3 v_pos;
varying vec3 v_nrm;

float h11(float x) { return fract(sin(x * 127.1) * 43758.5453); }

void vertex() {
	v_mode = floor(COLOR.r * 4.0 + 0.5);
	v_suit = COLOR.g;
	v_kindf = COLOR.b * 16.0;
	v_zone = COLOR.a;
	v_path = UV2.x;
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
		rough = mix(rough, 0.75, crown);
		suit = smoothstep(0.35, 0.65, v_suit);
		float ndv0 = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
		// subsurface-lite skin: a warm red grazing falloff, back-scatter for lights behind (BACKLIGHT) and a little sheen
		float sk = 1.0 - suit;
		alb *= 1.0 + sk * pow(1.0 - ndv0, 2.2) * vec3(0.3, 0.16, 0.1);          // (was 0.55, 0.2, 0.08: in a lamp-lit room the neck and the head glowed orange-red, director review 3 #5)
		BACKLIGHT = sk * alb * vec3(0.32, 0.2, 0.15);
		emis += sk * alb * 0.26 * (0.6 + 0.4 * v_nrm.y);                       // a skin fill: the face reads in a dark street instead of going black
		if (hero_style < 0.5 && suit > 0.001) {
			float lum = dot(alb, vec3(0.299, 0.587, 0.114));
			float ndv = ndv0;
			float rim = pow(1.0 - ndv, 2.6);
			// fabric micro-normal: the skin normal map sampled at a high frequency reads as a knit; gloss varies with a low-frequency cloud (worn / stretched)
			vec3 weave = texture(skin_normal, UV * 7.0).rgb;
			nm = mix(nm, vec3((nm.xy - 0.5) * 0.7 + (weave.xy - 0.5) * 0.22 + 0.5, nm.z), suit);
			float cloud = texture(skin_rough, UV * 2.3).r;
			float fw = max(fwidth(v_pos.y), 0.0015);
			float ay = abs(v_pos.y);
			float ax = abs(v_pos.x);
			// armour panels (secondary material, glossier and metallic): shoulder caps, chest plate, forearm bracers, knee pads, shins, belt
			float shoulder = smoothstep(0.14, 0.2, ax) * smoothstep(1.36, 1.4, ay) * (1.0 - smoothstep(1.52, 1.56, ay));
			float chest = (1.0 - smoothstep(0.15, 0.19, ax)) * smoothstep(1.15, 1.19, ay) * (1.0 - smoothstep(1.38, 1.42, ay)) * step(0.25, abs(v_nrm.z));
			float belt = smoothstep(0.96, 0.98, ay) * (1.0 - smoothstep(1.04, 1.06, ay));
			float knee = smoothstep(0.4, 0.43, ay) * (1.0 - smoothstep(0.54, 0.57, ay)) * step(0.2, v_nrm.z);
			float shin = smoothstep(0.1, 0.13, ay) * (1.0 - smoothstep(0.36, 0.39, ay));
			float arm = smoothstep(0.44, 0.5, ax) * smoothstep(1.0, 1.04, ay) * (1.0 - smoothstep(1.36, 1.4, ay));
			float panel = clamp(shoulder + chest + belt + knee + shin * 0.7 + arm * 0.8, 0.0, 1.0);
			// panel lines: dark grooves at ribs, waist, thigh, knee and down the chest and back
			float gy = 0.0;
			gy += 1.0 - smoothstep(0.0, fw * 1.6 + 0.004, abs(ay - 1.12));
			gy += 1.0 - smoothstep(0.0, fw * 1.6 + 0.004, abs(ay - 0.93));
			gy += 1.0 - smoothstep(0.0, fw * 1.6 + 0.004, abs(ay - 0.76));
			gy += 1.0 - smoothstep(0.0, fw * 1.6 + 0.004, abs(ay - 0.58));
			gy += 1.0 - smoothstep(0.0, fw * 1.6 + 0.004, abs(ay - 0.3));
			float gx = (1.0 - smoothstep(0.0, 0.004 + fw, abs(ax - 0.105))) * smoothstep(0.95, 1.1, ay) * (1.0 - smoothstep(1.35, 1.42, ay));
			float groove = clamp(gy + gx, 0.0, 1.0);
			// palette: a warm graphite base, panels toward the complement of the accent (cyan gives bronze, ember gives slate): never one blue
			vec3 comp = normalize(vec3(1.0) - accent * 0.8 + 0.001);
			vec3 panel_col = mix(suit_color * 1.6, comp * 0.2 + suit_color * 0.8, 0.5) * look_tint;
			// CLOTHES (director review: the hero read as a bare black mannequin): a light steel-grey field jacket (long enough to cover the hips) with a dark yoke, a dark belt with a buckle, charcoal trousers
			// with a lighter thigh pocket panel, black boots with a pale sole line, and a rucksack plate with an accent stripe on the back. Zones follow the model height (the suit covers head-to-ankle).
			float shade = clamp(0.8 + 0.55 * lum, 0.7, 1.25) * (0.88 + 0.24 * cloud);
			float jacket = smoothstep(0.8, 0.83, ay);
			vec3 cloth = mix(pants_color, jacket_color, jacket);
			float pocket = (1.0 - smoothstep(0.0, 0.01, abs(ax - 0.17) - 0.045)) * smoothstep(0.52, 0.55, ay) * (1.0 - smoothstep(0.7, 0.73, ay)) * (1.0 - jacket);
			cloth = mix(cloth, pants_color * 1.5 + 0.03, pocket * 0.8);
			float yoke = smoothstep(1.5, 1.53, ay) * jacket;
			cloth = mix(cloth, jacket_color * 0.35, yoke * 0.8);
			float boot = 1.0 - smoothstep(0.17, 0.2, ay);
			cloth = mix(cloth, vec3(0.045, 0.045, 0.05), boot);
			float sole = (1.0 - smoothstep(0.0, 0.012, abs(ay - 0.055))) * boot;
			cloth = mix(cloth, vec3(0.55, 0.55, 0.5), sole * 0.8);
			float beltb = smoothstep(0.93, 0.95, ay) * (1.0 - smoothstep(1.01, 1.03, ay)) * smoothstep(-0.1, 0.3, v_nrm.z);
			float hem = (1.0 - smoothstep(0.0, 0.012, abs(ay - 0.815)));
			cloth = mix(cloth, vec3(0.12, 0.13, 0.16), hem * 0.9);
			cloth = mix(cloth, vec3(0.07, 0.06, 0.05), beltb);
			float buckle = beltb * (1.0 - smoothstep(0.035, 0.05, ax)) * step(0.4, v_nrm.z);
			cloth = mix(cloth, vec3(0.75, 0.62, 0.3), buckle);
			float pack = (1.0 - smoothstep(0.085, 0.1, ax)) * smoothstep(1.15, 1.18, ay) * (1.0 - smoothstep(1.36, 1.39, ay)) * smoothstep(0.2, 0.45, -v_nrm.z);
			cloth = mix(cloth, jacket_color * 0.3 + 0.04, pack);
			float packline = pack * (1.0 - smoothstep(0.0, 0.012, abs(ax - 0.055)));
			float front = smoothstep(0.3, 0.6, v_nrm.z);
			float zip = (1.0 - smoothstep(0.0, 0.008, ax)) * front * jacket * (1.0 - smoothstep(1.46, 1.5, ay));
			float flap = (1.0 - smoothstep(0.0, 0.01, abs(ax - 0.095) - 0.04)) * smoothstep(1.17, 1.19, ay) * (1.0 - smoothstep(1.27, 1.29, ay)) * front * jacket;
			cloth = mix(cloth, cloth * 0.55, max(zip, flap * 0.7));
			vec3 fabric = cloth * look_tint * shade;
			fabric = mix(fabric, accent * 0.8, packline * 0.7);
			fabric = mix(fabric, panel_col * (0.7 + 0.8 * lum), panel * 0.2);
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
			fabric *= 1.0 - 0.6 * groove * (1.0 - 0.5 * panel);
			alb = mix(alb, fabric, suit);
			alb = mix(alb, film * 0.35, suit * rim * 0.2);
			// hemisphere fill (no light needed): the suit never goes black from behind or below
			float hemi = 0.55 + 0.45 * v_nrm.y;
			emis += suit * (film * (seam * 0.6 * k + rim * 0.16 * k + flick * 0.18) + fabric * 0.34 * hemi);
			rough = mix(rough, clamp(0.74 - 0.25 * panel + 0.2 * (cloud - 0.5), 0.12, 0.95), suit);
			metal = suit * (0.04 + 0.2 * panel + 0.1 * rim);
			nd = mix(1.0, 0.45, suit);
		} else if (suit > 0.001) {
			// HERO STYLE: a graphite bodysuit. The baked muscle shading of the skin map gives the form, a knit micro-normal the cloth, a cool sheen the rim; the gloves (the end of the
			// arm circuit) are darker and glossier. The armour sits on top of it (the suit kit), the circuits glow in the kit parts, not on the cloth.
			float lum = dot(alb, vec3(0.299, 0.587, 0.114));
			float rim = pow(1.0 - ndv0, 2.4);
			vec3 weave = texture(skin_normal, UV * 7.0).rgb;
			nm = mix(nm, vec3((nm.xy - 0.5) * 0.7 + (weave.xy - 0.5) * 0.3 + 0.5, nm.z), suit);
			float cloud = texture(skin_rough, UV * 2.3).r;
			float glove = smoothstep(0.62, 0.70, v_path);
			float shade = clamp(0.55 + 1.0 * lum, 0.6, 1.35) * (0.9 + 0.2 * cloud);
			vec3 cloth = mix(cloth_col, cloth_col * 0.6 + vec3(0.012), glove) * shade;
			float ph = (0.7 + 1.3 * film_seed) * (1.0 - 0.55 * ndv0) * 12.566;
			vec3 film = 0.5 + 0.5 * cos(vec3(0.0, 2.094, 4.188) + ph * vec3(1.0, 1.13, 1.27));
			film = mix(film, trim_color, 0.6);
			film = mix(film, accent, accent_mix);
			float k2 = (0.35 + 0.65 * ready_k) * (1.0 + 0.9 * charge + 0.6 * excite) * glow;
			alb = mix(alb, cloth, suit);
			emis += suit * (film * rim * 0.20 * k2 + cloth * (0.20 + 0.15 * v_nrm.y));
			rough = mix(rough, clamp(0.58 - 0.16 * glove + 0.2 * (cloud - 0.5), 0.2, 0.9), suit);
			metal = suit * 0.04;
			spec = mix(spec, 0.55, suit);
			nd = mix(1.0, 0.5, suit);
		}
	} else if (v_mode < 1.5) {
		alb = texture(eye_albedo, UV).rgb;
		nm = texture(eye_normal, UV).rgb;
		rough = 0.12;
		spec = 0.9;
		if (hero_style > 0.5) {                            // the iris carries the quantum glow (centre of the eye map), strongest while a power is charged
			float de = length(UV - vec2(0.495, 0.505));
			float iris = 1.0 - smoothstep(0.07, 0.10, de);
			emis += glow_rgb * iris * smoothstep(0.03, 0.07, de) * gz_b.y * 1.1;
		}
	} else if (v_mode < 2.5) {
		alb = texture(hair1_albedo, UV).rgb * hair_color * 2.6;
		nm = texture(hair1_normal, UV).rgb;
		float hr = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
		alb += hair_color * vec3(1.4, 1.2, 1.0) * hr * 0.9;
		rough = 0.5;
		spec = 0.5;
		BACKLIGHT = alb * 0.3;
	} else if (v_mode < 3.5) {
		alb = texture(hair2_albedo, UV).rgb * hair_color * 2.6;
		nm = texture(hair2_normal, UV).rgb;
		float hr2 = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
		alb += hair_color * vec3(1.4, 1.2, 1.0) * hr2 * 0.9;
		rough = 0.5;
		spec = 0.5;
		BACKLIGHT = alb * 0.3;
	} else {
		float fk = v_kindf;
		float kind = floor(fk + 0.5);
		float cape = step(0.02, abs(fk - kind));
		float ndv2 = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
		float hemi2 = 0.55 + 0.45 * v_nrm.y;
		float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
		if (hero_style > 0.5 && kind > 5.5) {
			// THE SUIT KIT (HeroSuit): kinds 6 plate, 7 accent paint, 8 dark metal, 9 fabric, 10 glow, 11 canvas, 12 gold, 13 cloth. The atlas carries the wear (neutral colours), the kind picks the palette.
			float zid = floor(v_zone * 8.0);
			float zv = zid < 0.5 ? gz_a.x : (zid < 1.5 ? gz_a.y : (zid < 2.5 ? gz_a.z : (zid < 3.5 ? gz_a.w : (zid < 4.5 ? gz_b.x : gz_b.y))));
			float wave = gflow.y * (exp(-pow((v_path - gflow.x) / 0.11, 2.0)) + 0.4 * (1.0 - smoothstep(0.0, 0.5, gflow.x - v_path)) * step(v_path, gflow.x));
			if (kind > 9.5 && kind < 10.5) {
				alb = vec3(0.012);
				rough = 0.35;
				emis = glow_rgb * (zv + wave) * glow * glow_gain * 1.1;
			} else {
				vec3 t = vec3(1.0 / 2.2);                         // no atlas loaded: flat colours per kind
				vec3 o = vec3(1.0, 0.45, 0.45);
				vec3 tint = kind < 6.5 ? plate_col : (kind < 7.5 ? trim_paint : (kind < 8.5 ? vec3(0.07, 0.075, 0.085) : (kind < 9.5 ? cloth_col2 : (kind < 11.5 ? vec3(0.2, 0.17, 0.13) : (kind < 12.5 ? gold_col : cloth_col2 * 1.4)))));
				if (gear_tex > 0.5) {
					t = texture(gear_albedo, UV).rgb;
					o = texture(gear_orm, UV).rgb;
					nm = texture(gear_normal, UV).rgb;
					if (kind > 7.5 && kind < 8.5 || kind > 10.5 && kind < 11.5) {
						tint = vec3(0.45);                        // dark metal and canvas keep the colours they were baked with
					}
				}
				float mt = kind < 8.5 ? plate_metal : 1.0;
				alb = t * tint * 2.2;
				rough = clamp(o.g + (kind < 8.5 ? plate_rough : 0.0), 0.08, 1.0);
				metal = clamp(o.b * mt, 0.0, 1.0);
				if (kind > 11.5 && kind < 12.5) {
					metal = 0.95;
					rough = clamp(rough * 0.7, 0.15, 0.6);
				}
				if (kind > 8.5 && kind < 9.5 || kind > 12.5) {
					metal = 0.0;
					rough = clamp(rough + 0.25, 0.5, 0.95);
				}
				if (kind > 10.5 && kind < 11.5) {
					metal = 0.0;
					rough = 0.85;
				}
				AO = o.r;
				AO_LIGHT_AFFECT = 0.65;
				emis = alb * 0.2 * (0.55 + 0.45 * v_nrm.y);
				nd = 1.0;
			}
		} else if (kind < 0.5) {
			alb = vec3(0.13, 0.14, 0.155);
			rough = 0.42;
			metal = 0.55;
			emis = trim_color * (pow(1.0 - ndv2, 3.0) * 0.18 + step(0.5, v_suit) * 1.1) * (0.4 + 0.6 * ready_k) * glow;
		} else if (kind < 1.5) {
			// armour plate: a warm bronze-slate (the complement of the accent), a dark groove at the edge and a bright bevel inside it
			vec3 comp2 = normalize(vec3(1.0) - accent * 0.8 + 0.001);
			vec3 base = mix(vec3(0.27, 0.31, 0.38), comp2 * 0.4, 0.14) * look_tint;
			float groove = 1.0 - smoothstep(0.0, 0.1, edge);
			float bevel = smoothstep(0.1, 0.15, edge) * (1.0 - smoothstep(0.15, 0.24, edge));
			alb = base * (1.0 - 0.6 * groove) * (0.92 + 0.5 * bevel) + accent * bevel * 0.05;
			rough = 0.38;
			metal = 0.5;
			emis = alb * (0.4 * hemi2 + 0.3 * bevel) + accent * (pow(1.0 - ndv2, 3.0) * 0.14 + bevel * 0.1) * glow;
		} else if (kind < 2.5 || kind > 4.5) {
			// fabric: the rucksack, belt, pouches, boots and the cape (cape = darker steel-blue with folds and an accent hem)
			float fold = 0.5 + 0.5 * sin(UV.x * 18.0 + sin(UV.y * 5.0) * 1.5);
			vec3 cloth2 = mix(pants_color * 0.8 + vec3(0.02, 0.022, 0.025), vec3(0.14, 0.22, 0.36), cape);
			cloth2 = mix(cloth2, vec3(0.2, 0.17, 0.13), step(4.5, kind));                       // coyote canvas: rucksack and pouches (a weave, never one flat bright face)
			cloth2 *= 1.0 + step(4.5, kind) * (0.2 * sin(UV.x * 140.0) * sin(UV.y * 140.0) - 0.08 * smoothstep(0.1, 0.5, 1.0 - abs(UV.y - 0.5) * 2.0));
			cloth2 *= mix(0.8, 1.15, mix(0.5, fold, cape));
			float groove2 = (1.0 - smoothstep(0.0, 0.07, edge)) * (1.0 - cape);
			cloth2 *= 1.0 - 0.45 * groove2;
			float hem2 = cape * smoothstep(0.955, 0.97, UV.y);
			alb = mix(cloth2 * look_tint, accent * 0.7, hem2 * 0.8);
			rough = 0.78;
			metal = 0.05;
			emis = alb * 0.42 * hemi2 + accent * hem2 * 0.3 * glow;
		} else if (kind < 3.5) {
			alb = vec3(0.05);
			rough = 0.3;
			emis = trim_color * 0.9 * (0.45 + 0.55 * ready_k) * glow;
		} else {
			alb = vec3(0.72, 0.55, 0.25);
			rough = 0.32;
			metal = 0.85;
			emis = alb * 0.18 * hemi2;
		}
	}
	ALBEDO = alb * brightness;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = nd;
	float far_rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 1.4);
	EMISSION = emis + far_k * (trim_color * (0.3 + 1.4 * far_rim) + alb * 0.35) + hit_k * vec3(1.6, 1.4, 1.2);
}
