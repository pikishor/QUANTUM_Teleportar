shader_type spatial;
render_mode cull_back;
// The street kit window and the district landmarks (city_kit.gd, city_landmarks.gd): same look as the props (prop_core.gdshaderinc) with the per-prop seed as a
// vertex attribute instead of per-instance data.
#define KIT 1
#include "res://assets/shaders/prop_core.gdshaderinc"
