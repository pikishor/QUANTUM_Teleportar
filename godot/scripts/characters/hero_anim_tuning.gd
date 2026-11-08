class_name HeroAnimTuning
extends RefCounted
## ONE table for every number of the hero's animation polish (HeroAnimPolish reads it; nothing else holds an animation constant of this layer). Angles in radians,
## distances in metres, rates are critically damped spring frequencies (rad/s) or exponential damp rates (1/s). Tune here.

const T := {
	# idle: breathing and weight
	"breath_rate": 1.7, "breath_chest": 0.012, "breath_hips": 0.0035, "breath_calm_speed": 1.6,
	# locomotion blends
	"start_lean": 0.05, "start_spring": 9.0, "stop_rock": 0.045, "stop_spring": 8.0,
	"turn_twist": 0.16, "turn_roll": 0.05, "turn_spring": 8.0, "turn_rate_ref": 4.0,
	# landing
	"land_dip": 0.06, "land_pitch": 0.1, "land_ref_speed": 12.0, "land_spring": 14.0, "land_min_speed": 2.5,
	# head: look-at, blink, saccades
	"look_yaw_max": 0.9, "look_pitch_max": 0.35, "look_spring": 12.0, "look_range": 14.0,
	"blink_every": 3.6, "blink_jitter": 2.4, "blink_time": 0.16, "blink_nod": 0.03,
	"saccade_every": 0.7, "saccade_amp": 0.022, "saccade_spring": 40.0,
	# weapon handling per class: lowering of the torso and pelvis during reload / swap, rifle tilt scale
	"reload_pelvis": {"rifle": 0.015, "shotgun": 0.03, "heavy": 0.05},
	"reload_pitch": {"rifle": 0.05, "shotgun": 0.1, "heavy": 0.14},
	"reload_twist": {"rifle": 0.06, "shotgun": 0.12, "heavy": 0.1},
	"reload_tilt_mul": {"rifle": 1.0, "shotgun": 1.15, "heavy": 0.9},
	"swap_dip": {"rifle": 0.05, "shotgun": 0.07, "heavy": 0.1},
	# cover
	"cover_lean": 0.12, "cover_crouch": 0.22, "cover_roll": 0.2, "cover_twist": 0.25, "cover_spring": 10.0,
	# takedown, slam, glide, wall-run
	"takedown_pitch": 0.3, "takedown_twist": 0.35, "takedown_hips": 0.08,
	"slam_pitch": 0.35, "slam_hips": 0.1, "glide_pitch": -0.28, "glide_roll_sway": 0.06, "glide_spring": 8.0,
	"wall_roll": 0.12, "wall_twist": 0.2, "wall_spring": 9.0,
	# vault / mantle hand placement (offset from the shoulder, torso frame: x outward, y up, z forward is negative)
	"vault_hand_x": 0.04, "vault_hand_y": -0.3, "vault_hand_z": -0.5, "vault_lean": 0.3, "vault_hips": 0.1,
	"mantle_hand_y": 0.12, "mantle_hand_z": -0.45, "mantle_lean": 0.35, "hand_spring": 14.0,
	# gait (Locomotion.apply_tuning): metres per cycle = (cyc0 + cyck * speed) * 1.15, capped; foot contact travel and reach leash; swing height and its peak; run lean; stance give; shoulders
	"gait_cyc0": 0.85, "gait_cyck": 0.40, "gait_cyc_max": 3.9, "gait_step_max": 0.7, "gait_leash": 0.47,
	"swing_h_walk": 0.08, "swing_h_run": 0.40, "swing_peak": 0.6, "swing_skew": 0.5,
	"lean_per_speed": 0.025, "lean_sprint": 0.08, "stance_comp": 0.05, "pelvis_yaw": 0.11, "torso_counter": 0.8, "arm_pump": 1.0, "land_centre": 1.0, "swing_follow": 0.75, "run_crouch": 0.07, "weight_rate": 40.0, "pelvis_rise": 1.8, "pelvis_drop": 2.4,
	# foot IK on slopes and stairs
	"foot_ray_up": 0.45, "foot_ray_down": 0.55, "foot_max_up": 0.28, "foot_max_down": 0.22, "foot_spring": 22.0,
	"slope_pitch_max": 0.6, "slope_pitch_mul": 0.9,
}

const WEAPON_CLASS := {&"carbine": "rifle", &"burst": "rifle", &"rail": "rifle", &"lance": "rifle", &"scatter": "shotgun", &"grenade": "heavy", &"flux": "heavy", &"gravity": "heavy", &"minigun": "heavy", &"akimbo": "rifle", &"arc": "rifle", &"revolver": "rifle", &"whip": "rifle", &"blade": "rifle", &"pistol": "rifle", &"marksman": "rifle", &"breacher": "shotgun", &"rocket": "heavy",
	&"swarm": "rifle", &"vector": "rifle", &"battle": "rifle", &"sawn": "shotgun", &"auto": "shotgun", &"bolt": "rifle", &"dmr": "rifle", &"knife": "rifle"}


static func f(key: String) -> float:
	return float(T[key])


## Weapon class ("rifle", "shotgun", "heavy") of a weapon id.
static func class_of(id: StringName) -> String:
	return String(WEAPON_CLASS.get(id, "rifle"))


## Per-class value of a table row.
static func cls(key: String, id: StringName) -> float:
	return float((T[key] as Dictionary)[class_of(id)])
