shader_type spatial;
// Scanned PBR surface: triplanar (world space, no UVs needed), packed ORM, curvature grime, wet-edge variation.
uniform sampler2D alb : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm : filter_linear_mipmap, repeat_enable;
uniform float tile_m = 2.0;
uniform float metal_k = 0.0;
uniform float grime = 0.5;
uniform float wet = 0.0;
varying vec3 wpos;
varying vec3 wnor;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnor = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec4 tri(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy) * w.x + texture(t, p.xz) * w.y + texture(t, p.xy) * w.z;
}

void fragment() {
	vec3 w = pow(abs(wnor), vec3(4.0));
	w /= (w.x + w.y + w.z + 1e-5);
	vec3 p = wpos / tile_m;
	vec3 a = tri(alb, p, w).rgb;
	vec3 o = tri(orm, p, w).rgb;
	vec3 n = tri(nrm, p, w).xyz;
	// curvature proxy: how fast the interpolated normal changes per pixel
	float curv = clamp(length(fwidth(wnor)) * 12.0, 0.0, 1.0);
	float cav = (1.0 - curv) * (1.0 - o.r);
	float g = clamp(grime * (0.35 + cav * 1.2), 0.0, 1.0);
	a *= 1.0 - 0.55 * g;
	float edge = curv * 0.6 + sin(wpos.x * 0.7 + wpos.z * 0.9) * 0.2 + 0.2;
	float wm = clamp(wet * (0.6 + edge) , 0.0, 1.0) * (1.0 - g * 0.5);
	ALBEDO = a * (1.0 - 0.35 * wm);
	ROUGHNESS = mix(o.g, 0.08, wm);
	METALLIC = o.b * metal_k;
	AO = o.r;
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = 1.0;
}
