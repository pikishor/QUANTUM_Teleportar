shader_type spatial;
render_mode cull_back, unshaded;
// Emission-only copy of the props drawn in the mirrored city under the wet ground.
#define MIRROR 1
#include "res://assets/shaders/prop_core.gdshaderinc"
