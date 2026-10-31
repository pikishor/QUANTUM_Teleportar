shader_type spatial;
render_mode cull_back, unshaded;
// Unshaded copy of the crowd for the mirrored city under the wet ground (HIGH tier).
#define MIRROR 1
#include "res://assets/shaders/prop_crowd_core.gdshaderinc"
