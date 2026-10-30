shader_type spatial;
render_mode cull_back, unshaded;
// Emission-only copy of the distant towers for the mirrored city under the wet ground.

#define FAR 1
#define MIRROR 1
#include "res://assets/shaders/building_core.gdshaderinc"
