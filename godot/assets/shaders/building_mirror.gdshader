shader_type spatial;
render_mode cull_back, unshaded;
// Cheap, emission-only copy of the facade for the mirrored city drawn *under* the wet ground (planar reflection by geometry).
// Same code as building.gdshader with the relief, interiors and lighting compiled out.

#define MIRROR 1
#include "res://assets/shaders/building_core.gdshaderinc"
