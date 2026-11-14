shader_type spatial;
render_mode cull_back;
// The weapon kit's material (wave 114, godot/tools/blender/weapon_kit.py): ONE material for every kit weapon, ONE draw call per weapon. Textures are texture arrays of 32 tileable material swatches
// (assets/models/weapons/weapon_atlas_*.png: albedo / ORM / normal), each swatch wraps on its own layer. The mesh carries what makes a weapon distinct:
//   COLOR  rgb = base albedo (the swatch only adds grain, streaks, stipple), a = how much of the surface glows (energy cores, coils, screens)
//   UV     x = swatch layer / 255, y = moving part id / 255 (0 static, 1 slide, 2 magazine, 3 pump, 4 hammer, 5 rotor, 6 lever, 7 pulse)
//   UV2    x = baked ambient occlusion, y = edge wear (0..1, from the angle between the faces)
// No UV unwrap: the swatches are projected along the dominant axis of the object-space normal (u runs along the barrel on the sides and the top, so brushed metal and wood grain follow the gun).
// The hero's own copy of the material moves the parts (slide travel, magazine, pump, hammer, rotor) by uniforms; nothing else changes, the whole weapon stays one mesh.
//   albedo = swatch * 2 * vertex colour (relative swatches are authored around 0.5; camo, hazard stripes and labels around their own colours with a vertex colour of 0.5).

uniform sampler2DArray tex_alb : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray tex_orm : filter_linear_mipmap, repeat_enable;
uniform sampler2DArray tex_nrm : filter_linear_mipmap, repeat_enable;
uniform float glow : hint_range(0.0, 4.0) = 1.0;               // rises on every shot (PlayerBody.fire_flash): the trim kicks light
uniform float wear_k : hint_range(0.0, 2.0) = 1.0;
uniform float nrm_k : hint_range(0.0, 2.0) = 1.0;
uniform float pulse : hint_range(0.0, 4.0) = 0.0;              // energy coils: part 7 glows brighter
uniform vec3 anim_slide = vec3(0.0);                           // object space (Godot frame: the shooter is toward +Z)
uniform vec3 anim_mag = vec3(0.0);
uniform vec3 anim_pump = vec3(0.0);
uniform vec3 anim_lever = vec3(0.0);
uniform float hammer_angle = 0.0;
uniform vec3 hammer_hinge = vec3(0.0, 0.03, 0.2);
uniform float rotor_angle = 0.0;
uniform vec3 rotor_center = vec3(0.0);

const float TILE[32] = float[32](0.05, 0.035, 0.06, 0.08, 0.08, 0.08, 0.07, 0.14, 0.14, 0.12, 0.1, 0.3, 0.3, 0.3, 0.05, 0.05, 0.06, 0.1, 0.06, 0.04, 0.12, 0.06, 0.04, 0.1, 0.08, 0.05, 0.1, 0.06, 0.1, 0.1, 0.1, 0.1);

varying vec3 v_pos;
varying vec3 v_nobj;
varying vec4 v_col;
varying vec2 v_aw;
flat varying float v_layer;
flat varying float v_part;

void vertex() {
	v_pos = VERTEX;
	v_nobj = NORMAL;
	v_col = COLOR;
	v_aw = UV2;
	v_layer = floor(UV.x * 255.0 + 0.5);
	v_part = floor(UV.y * 255.0 + 0.5);
	vec3 p = VERTEX;
	vec3 n = NORMAL;
	if (v_part > 0.5) {
		if (v_part < 1.5) {
			p += anim_slide;
		} else if (v_part < 2.5) {
			p += anim_mag;
		} else if (v_part < 3.5) {
			p += anim_pump;
		} else if (v_part < 4.5) {
			float c = cos(hammer_angle);
			float s = sin(hammer_angle);
			vec3 q = p - hammer_hinge;
			p = hammer_hinge + vec3(q.x, q.y * c - q.z * s, q.y * s + q.z * c);
			n = vec3(n.x, n.y * c - n.z * s, n.y * s + n.z * c);
		} else if (v_part < 5.5) {
			float c = cos(rotor_angle);
			float s = sin(rotor_angle);
			vec3 q = p - rotor_center;
			p = rotor_center + vec3(q.x * c - q.y * s, q.x * s + q.y * c, q.z);
			n = vec3(n.x * c - n.y * s, n.x * s + n.y * c, n.z);
		} else if (v_part < 6.5) {
			p += anim_lever;
		}
	}
	VERTEX = p;
	NORMAL = n;
}

void fragment() {
	vec3 no = normalize(v_nobj);
	vec3 an = abs(no);
	vec3 P = v_pos;
	vec3 dx = dFdx(P);
	vec3 dy = dFdy(P);
	vec2 uv;
	vec2 ddx;
	vec2 ddy;
	vec3 T;
	vec3 B;
	if (an.x >= an.y && an.x >= an.z) {
		uv = P.zy; ddx = dx.zy; ddy = dy.zy; T = vec3(0.0, 0.0, 1.0); B = vec3(0.0, 1.0, 0.0);
	} else if (an.y >= an.z) {
		uv = P.zx; ddx = dx.zx; ddy = dy.zx; T = vec3(0.0, 0.0, 1.0); B = vec3(1.0, 0.0, 0.0);
	} else {
		uv = P.xy; ddx = dx.xy; ddy = dy.xy; T = vec3(1.0, 0.0, 0.0); B = vec3(0.0, 1.0, 0.0);
	}
	int li = clamp(int(v_layer + 0.5), 0, 31);
	float k = 1.0 / TILE[li];
	vec3 coord = vec3(uv * k, float(li));
	vec4 alb = textureGrad(tex_alb, coord, ddx * k, ddy * k);
	vec4 orm = textureGrad(tex_orm, coord, ddx * k, ddy * k);
	vec3 nm = textureGrad(tex_nrm, coord, ddx * k, ddy * k).xyz * 2.0 - 1.0;

	float glow_share = v_col.a;
	vec3 base = alb.rgb * 2.0 * v_col.rgb;
	float rough = orm.g;
	float metal = orm.b;
	// edge wear: paint and polymer chip down to bare steel at the edges (the swatch's chip mask breaks the line up); bare metal only polishes
	float wmask = clamp(v_aw.y * wear_k, 0.0, 1.0);
	float chip = smoothstep(0.42, 0.68, wmask + (orm.r - 0.5) * 0.75);
	float is_metal = step(0.5, metal);
	vec3 bare = vec3(0.36, 0.37, 0.4);
	base = mix(base, bare, chip * mix(0.85, 0.25, is_metal) * (1.0 - glow_share));
	rough = mix(rough, 0.3, chip * mix(0.8, 0.5, is_metal));
	metal = mix(metal, 1.0, chip * (1.0 - is_metal) * 0.9);
	// grime in the cavities
	float cav = 1.0 - v_aw.x;
	base *= 1.0 - 0.35 * cav;
	vec3 tv = normalize((MODELVIEW_MATRIX * vec4(T, 0.0)).xyz);
	vec3 bv = normalize((MODELVIEW_MATRIX * vec4(B, 0.0)).xyz);
	float nz = sqrt(max(0.0, 1.0 - dot(nm.xy, nm.xy)));
	vec3 pert = normalize(tv * nm.x * nrm_k + bv * nm.y * nrm_k + NORMAL * nz);
	NORMAL = normalize(mix(NORMAL, pert, 0.9));
	ALBEDO = base * (1.0 - glow_share * 0.7);
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	METALLIC = metal;
	SPECULAR = 0.5;
	RIM = 0.25;
	RIM_TINT = 0.5;
	AO = mix(1.0, v_aw.x, 0.9);
	AO_LIGHT_AFFECT = 0.45;
	float pw = (v_part > 6.5 && v_part < 7.5) ? pulse : 0.0;
	// a small self-lit floor (a gun is never a black cut-out in a dark street) plus the glowing parts (pattern from the swatch)
	EMISSION = base * 0.035 + v_col.rgb * glow_share * (alb.r * 2.0) * (0.25 + 0.55 * glow + pw);
}
