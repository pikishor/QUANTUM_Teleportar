extends Node3D
func _ready() -> void:
	for id in [&"battle", &"carbine", &"mpistol", &"lmg", &"rocket", &"bolt"]:
		var m := WeaponModels.mesh(id)
		print(id, " mesh ", m, " aabb ", m.get_aabb() if m != null else "-", " spec ", WeaponModels.spec(id).get("reach"), " shift ", WeaponModels.muzzle_shift(id))
		var ps := FoeArms.pieces(id, 5)
		var t := 0
		var lo := Vector3(1e9, 1e9, 1e9)
		var hi := Vector3(-1e9, -1e9, -1e9)
		for c in ps:
			t += (c["idx"] as PackedInt32Array).size() / 3
			for p in (c["v"] as PackedVector3Array):
				lo = lo.min(p)
				hi = hi.max(p)
		print("   pieces ", ps.size(), " tris ", t, " kit range ", lo, hi)
	get_tree().quit()
