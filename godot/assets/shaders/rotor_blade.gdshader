shader_type spatial;
// w129-machanim: the blades of a helicopter rotor (scripts/vehicles/mach_anim.gd): lit like the craft's trim, but each vertex rises with its distance from the hub, so the
// blades cone up under lift and droop at rest, and flap with the azimuth in forward flight (the advancing blade climbs, the retreating one falls). Per instance:
//   cone  rad of coning (negative = droop)   flap  rad of the once-per-turn flap   azim  the rotor's turn angle (rad), so the flap stays fixed to the airframe
uniform vec3 albedo : source_color = vec3(0.045, 0.047, 0.052);
uniform float metallic = 0.3;
uniform float roughness = 0.6;
instance uniform float cone = 0.0;
instance uniform float flap = 0.0;
instance uniform float azim = 0.0;

void vertex() {
	float r = length(VERTEX.xz);
	float lift = max(r - 0.25, 0.0);
	float a = atan(VERTEX.z, VERTEX.x) + azim;
	VERTEX.y += lift * (cone + flap * sin(a));
}

void fragment() {
	ALBEDO = albedo;
	METALLIC = metallic;
	ROUGHNESS = roughness;
}
