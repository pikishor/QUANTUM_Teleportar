class_name HeroClipData
extends Resource
## The baked locomotion clips of the hero (tools/hero/build_clips.py + tools/hero/bake_clips.gd): Quaternius Universal Animation Library (CC0) retargeted onto the hero skeleton.
## `data` = {bones: [names], fps, pelvis_rest_y, clips: {name: {n, loop, dur, speed, stride, q: PackedFloat32Array (n x bones x 4, x y z w), hips: PackedFloat32Array (n x 3)}}}.

@export var data: Dictionary = {}
