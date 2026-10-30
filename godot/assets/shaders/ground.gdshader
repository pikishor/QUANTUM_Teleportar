shader_type spatial;
render_mode depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;
// The whole ground of the city in one analytic shader (see ground_core.gdshaderinc). Wet reflections are real geometry: a mirrored
// copy of the city is drawn *under* this plane (city.gd, node "Mirror") and this shader reads it back from the screen with a
// roughness-dependent smear.

#include "res://assets/shaders/ground_core.gdshaderinc"
