shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// LOW tier ground: same analytic surface, no mirrored geometry, no screen-texture copy, opaque.

#define LITE 1
#include "res://assets/shaders/ground_core.gdshaderinc"
