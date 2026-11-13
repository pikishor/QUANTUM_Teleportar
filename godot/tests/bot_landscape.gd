extends RefCounted
## Look-dev bot for the landscape (trees, undergrowth, shores, waterfalls, mountains, anchors) in the REAL game: tools/bot.sh res://tests/bot_landscape.gd OUT EVERY COUNT
##   QUALITY=0|1|2 picks the tier, BOT_RES=2400x1080 the phone aspect, BOT_USER_ARGS="--touch" draws the phone HUD (default: HUD hidden).
## env: LS_VIEWS  semicolon list, one per shot slot (EVERY = frames per view, COUNT = views):
##        "hero:x,z,yaw[,dist]"                the real hero on the ground at (x, z), the real game camera looking along yaw (radians, 0 = -Z north), optional camera distance
##        "road:NAME,s[,yaw_off[,dist]]"       the real hero at s metres along the named road, the real game camera looking along the road (yaw_off added)
##        "cam:px,ph,pz,tx,th,tz"              a free camera at (px, ground+ph, pz) looking at (tx, ground+th, tz)
##        "abs:px,py,pz,tx,ty,tz"              a free camera at absolute coordinates
##        "fall:i[,lx,ph,lz[,th]]"             a free camera in front of waterfall i (LandscapeSites.falls()): lx across, ph above the pool, lz out from the pool, aimed th above the pool
##        "river:i,at[,ph]"                    a camera on the bank of river i (WaterLayout.paths) at path point `at`, ph above the bank, looking down the river
##        "shore:z[,az,ph]"                    a low camera (ph above the sand, default 1.5 m) at the first dry beach sand of the west coast at z, looking along az degrees (0 east, 90 south, 180 the sea)
##        "fallv:i[,az,r,ph,th]"               like fall: but placed r m from the pool at az degrees off the downstream direction, ph above the ground, raised until the fall is in clear sight
##        "anchor:kind,i[,dist,ph,az]"         a free camera dist m from anchor i of kind turbine / pylon / mast / crane (AnchorSites), seen from azimuth az
##        "strip:i[,dist,ph,az]"               a free camera dist m from airstrip i
##        any view may end with "@hour[,clear|rain|storm|fog|overcast|drizzle]": the time of day (and weather) of that view only
##      LS_HOUR (default 12), LS_WEATHER clear|rain|snow (default clear), LS_HUD=1 keeps the HUD
var _views: Array[String] = []
var _i := 0
var _f := 0
var _hud: CanvasLayer = null
var _wait := 20


func _init() -> void:
	for s in OS.get_environment("LS_VIEWS").split(";", false):
		_views.append(s.strip_edges())


func step(_t: float, _d: float) -> bool:
	var p := Game.player as Player
	if p == null:
		return false
	_wait = int(Dev.get(&"_args").get("every", "20")) if Dev.get(&"_args") is Dictionary else 20
	if _f == 2:
		Game.state = &"play"
		p.max_hp = 1.0e6
		p.hp = p.max_hp
		if Game.enemies != null:
			(Game.enemies as EnemyManager).clear()
		if Encounters.current != null:
			Encounters.current.enabled = false
		var city := Game.world as City
		if city != null and city.terrain != null and OS.get_environment("LS_DEBUG") == "1":
			var tm: ShaderMaterial = city.terrain._mat
			print("LS_DEBUG tex_k=", tm.get_shader_parameter(&"tex_k"), " layers=", tm.get_shader_parameter(&"layers"), " detail=", tm.get_shader_parameter(&"detail"), " quality=", Game.quality)
		var hour := float(OS.get_environment("LS_HOUR")) if OS.get_environment("LS_HOUR") != "" else 12.0
		if city != null and city.day_night != null:
			city.day_night.frozen = true
			city.day_night.set_hour(hour)
		for n in Game.world.get_tree().root.find_children("*", "Weather", true, false):
			var wx := OS.get_environment("LS_WEATHER")
			(n as Weather).set_state(StringName(wx) if wx in ["rain", "snow"] else &"clear", true)
		if OS.get_environment("LS_HUD") != "1":
			_hud = Game.get_tree().root.find_child("Hud", true, false) as CanvasLayer
	if _hud != null and OS.get_environment("LS_HUD") != "1":
		_hud.visible = false                                   # the HUD is a CanvasLayer; it shows itself again on state changes, so hide it every frame
	if _f >= 3 and _i < _views.size():
		_apply(p, _views[_i], (_f - 3) % maxi(_wait, 1))
	_f += 1
	if _f >= 3 and (_f - 3) % maxi(_wait, 1) == 0 and _f > 3:
		_i += 1
	return _i >= _views.size()


func _settle(pos: Vector3) -> void:
	var city := Game.world as City
	if city == null:
		return
	if city.terrain != null:
		city.terrain.settle(pos)
	if city.vegetation != null:
		city.vegetation.settle(pos)
	if city.sites != null and city.sites.has_method(&"settle"):
		city.sites.call(&"settle", pos)
	var ls = city.get_node_or_null("Landscape")
	if ls != null and ls.has_method(&"settle"):
		ls.call(&"settle", pos)


func _free_cam(p: Player, pos: Vector3, tgt: Vector3, k: int, fov := 70.0) -> void:
	if k == 0:
		p.global_position = Vector3(pos.x, TerrainHeight.height_at(pos.x, pos.z) + 1.0, pos.z)
		p.velocity = Vector3.ZERO
		_settle(pos)
	p.camera_rig.cine_set(Transform3D(Basis.IDENTITY, pos).looking_at(tgt, Vector3.UP), fov)


## True when no scattered tree stands within r metres of (x, z).
func _clear_of_trees(x: float, z: float, r: float) -> bool:
	for ci in range(int(floor((x - r) / VegScatter.CELL)), int(floor((x + r) / VegScatter.CELL)) + 1):
		for cj in range(int(floor((z - r) / VegScatter.CELL)), int(floor((z + r) / VegScatter.CELL)) + 1):
			var arr := VegScatter.cell(VegScatter.T_TREES, ci, cj)
			for k in arr.size() / VegScatter.STRIDE:
				if Vector2(arr[k * VegScatter.STRIDE] - x, arr[k * VegScatter.STRIDE + 2] - z).length() < r:
					return false
	return true


func _road_point(name: String, s: float) -> Array:
	for r: Dictionary in TerrainRoads.roads():
		if String(r["name"]) == name:
			var pos: PackedVector2Array = r["pos"]
			var i := clampi(int(s / TerrainRoads.STEP), 0, pos.size() - 2)
			var a := pos[i]
			var b := pos[i + 1]
			var d := (b - a).normalized()
			return [a, d]
	return []


func _apply(p: Player, v: String, k: int) -> void:
	var at := v.rfind("@")                                  # "view@hour[,weather]": the time of day (and weather clear / rain / snow) of this view only
	if at > 0:
		var tail := v.substr(at + 1).split(",")
		v = v.substr(0, at)
		var city := Game.world as City
		if k == 0 and city != null and city.day_night != null:
			city.day_night.set_hour(float(tail[0]))
			if tail.size() > 1:
				for n in Game.world.get_tree().root.find_children("*", "Weather", true, false):
					(n as Weather).set_state(StringName(tail[1]) if tail[1] in ["rain", "snow", "storm", "fog", "overcast", "drizzle"] else &"clear", true)
	if v.begins_with("abs:"):
		var a := v.substr(4).split(",")
		_free_cam(p, Vector3(float(a[0]), float(a[1]), float(a[2])), Vector3(float(a[3]), float(a[4]), float(a[5])), k)
		return
	if v.begins_with("cam:"):
		var a2 := v.substr(4).split(",")
		var pos := Vector3(float(a2[0]), 0.0, float(a2[2]))
		pos.y = TerrainHeight.height_at(pos.x, pos.z) + float(a2[1])
		var tgt := Vector3(float(a2[3]), 0.0, float(a2[5]))
		tgt.y = TerrainHeight.height_at(tgt.x, tgt.z) + float(a2[4])
		_free_cam(p, pos, tgt, k)
		return
	if v.begins_with("river:"):                            # "river:i,at[,ph]": a camera on the bank of river i at path point `at`, ph above the bank, looking down the river
		var ar := v.substr(6).split(",")
		var rpath: Dictionary = WaterLayout.paths[int(ar[0])]
		var rat := clampi(int(ar[1]), 1, (rpath["pos"] as PackedVector2Array).size() - 2)
		var rpos: Vector2 = (rpath["pos"] as PackedVector2Array)[rat]
		var rdir: Vector2 = (rpath["dir"] as PackedVector2Array)[rat]
		var rhw: float = (rpath["hw"] as PackedFloat32Array)[rat]
		var rph := float(ar[2]) if ar.size() > 2 else 2.0
		var rside := Vector2(-rdir.y, rdir.x)
		var rcam := rpos + rside * (rhw + 7.0)
		var rtar := rpos + rdir * 45.0
		_free_cam(p, Vector3(rcam.x, TerrainHeight.height_at(rcam.x, rcam.y) + rph, rcam.y), Vector3(rtar.x, TerrainHeight.height_at(rtar.x, rtar.y) + 1.0, rtar.y), k, 75.0)
		return
	if v.begins_with("shore:"):                            # "shore:z[,az,ph]": a low camera on the west beach at z, 6 m above the waterline's first dry sand, looking along az degrees (0 = east inland, 90 = south, 180 = the sea)
		var as_ := v.substr(6).split(",")
		var sz := float(as_[0])
		var saz := deg_to_rad(float(as_[1])) if as_.size() > 1 else deg_to_rad(90.0)
		var sph := float(as_[2]) if as_.size() > 2 else 1.5
		var sx := -(TerrainHeight.WORLD_HALF - 120.0)                       # from the world's edge inland: the first dry sand (the coast moved out with the 9 km world)
		while sx < -1000.0 and TerrainHeight.height_at(sx, sz) < TerrainHeight.SEA_LEVEL + 1.9:
			sx += 4.0
		var sg := TerrainHeight.height_at(sx, sz)
		var spos := Vector3(sx + 4.0, sg + sph, sz)
		_free_cam(p, spos, spos + Vector3(cos(saz) * 40.0, -sph * 0.9, sin(saz) * 40.0), k, 75.0)
		return
	if v.begins_with("lake:"):                            # "lake:i[,az_deg,ph,out]": a free camera on the shore of lake i (WaterLayout.LAKES) `out` m outside its edge at az degrees, ph above the ground, looking over the water to the middle
		var alk := v.substr(5).split(",")
		var lk: Dictionary = WaterLayout.LAKES[clampi(int(alk[0]), 0, WaterLayout.LAKES.size() - 1)]
		var lc: Vector2 = lk["c"]
		var lr := float(lk["r"])
		var laz := deg_to_rad(float(alk[1])) if alk.size() > 1 else 0.0
		var lph := float(alk[2]) if alk.size() > 2 else 2.0
		var lout := float(alk[3]) if alk.size() > 3 else 14.0
		var lcp := lc + Vector2(cos(laz), sin(laz)) * (lr + lout)
		_free_cam(p, Vector3(lcp.x, TerrainHeight.height_at(lcp.x, lcp.y) + lph, lcp.y), Vector3(lc.x, TerrainHeight.water_level_at(lc.x, lc.y) + 1.0, lc.y), k, 75.0)
		return
	if v.begins_with("foot:"):                            # "foot:i[,ph,th]": a free camera ph m above the ground, at the first clear spot (no tree within 7 m, dry, in sight of the fall's foot) 24-60 m downstream of the pool of fall i, aimed th m above the foot
		var aft := v.substr(5).split(",")
		var flf := LandscapeSites.falls()
		var fif := int(aft[0])
		if fif >= flf.size():
			return
		var ff: Dictionary = flf[fif]
		var phf := float(aft[1]) if aft.size() > 1 else 2.2
		var thf := float(aft[2]) if aft.size() > 2 else 9.0
		var fpc2: Vector2 = ff["pool"]
		var fdir2: Vector2 = ff["dir"]
		var fbase2: Vector2 = ff["base"]
		var aim := Vector3(fbase2.x, float(ff["pool_y"]) + thf, fbase2.y)
		var found := false
		var cpos := Vector3.ZERO
		for rr: float in [32.0, 42.0, 26.0, 55.0, 62.0]:
			for azd: float in [0.0, 22.0, -22.0, 44.0, -44.0, 66.0, -66.0]:
				var cp4: Vector2 = fpc2 + fdir2.rotated(deg_to_rad(azd)) * rr
				var gy4 := TerrainHeight.height_at(cp4.x, cp4.y)
				if gy4 < float(ff["pool_y"]) - 0.2 or TerrainHeight.water_level_for(cp4.x, cp4.y, gy4) != TerrainHeight.NO_WATER or not _clear_of_trees(cp4.x, cp4.y, 7.0):
					continue
				var from4 := Vector3(cp4.x, gy4 + phf, cp4.y)
				var los := true
				for sk in 20:
					var sp4 := from4.lerp(aim, float(sk + 1) / 22.0)
					if TerrainHeight.height_at(sp4.x, sp4.z) > sp4.y - 0.4:
						los = false
						break
				if los:
					cpos = from4
					found = true
					break
			if found:
				break
		if not found:
			cpos = Vector3(fpc2.x + fdir2.x * 40.0, TerrainHeight.height_at(fpc2.x + fdir2.x * 40.0, fpc2.y + fdir2.y * 40.0) + 6.0, fpc2.y + fdir2.y * 40.0)
		_free_cam(p, cpos, aim, k)
		return
	if v.begins_with("fallv:"):                           # "fallv:i[,az,r,ph,th]": a camera r m from the pool centre at az degrees off the downstream direction, at least ph above the ground, raised until the line of sight to the fall is clear
		var af := v.substr(6).split(",")
		var fl := LandscapeSites.falls()
		var fi := int(af[0])
		if fi >= fl.size():
			return
		var fw: Dictionary = fl[fi]
		var faz := deg_to_rad(float(af[1])) if af.size() > 1 else 0.0
		var fr := float(af[2]) if af.size() > 2 else 120.0
		var fph := float(af[3]) if af.size() > 3 else 6.0
		var fth := float(af[4]) if af.size() > 4 else float(fw["drop"]) * 0.45
		var fpc: Vector2 = fw["pool"]
		var fcp: Vector2 = fpc + (fw["dir"] as Vector2).rotated(faz) * fr
		for da: float in [0.0, 7.0, -7.0, 14.0, -14.0, 21.0, -21.0, 28.0, -28.0]:                # the first azimuth near the asked one with no tree within 9 m of the camera
			var trial: Vector2 = fpc + (fw["dir"] as Vector2).rotated(faz + deg_to_rad(da)) * fr
			if _clear_of_trees(trial.x, trial.y, 9.0):
				fcp = trial
				break
		var fmid: Vector2 = (fw["lip"] as Vector2).lerp(fw["base"], 0.5)
		var faim := Vector3(fmid.x, float(fw["pool_y"]) + fth, fmid.y)
		var fcy := TerrainHeight.height_at(fcp.x, fcp.y) + fph
		for _k in 40:
			var clear := true
			for s in 24:
				var sp := Vector3(fcp.x, fcy, fcp.y).lerp(faim, float(s + 1) / 26.0)
				if TerrainHeight.height_at(sp.x, sp.z) > sp.y - 1.0:
					clear = false
					break
			if clear:
				break
			fcy += 4.0
		_free_cam(p, Vector3(fcp.x, fcy, fcp.y), faim, k)
		return
	if v.begins_with("fall:"):                            # "fall:i[,lx,ph,lz[,th]]": a free camera in front of waterfall i: lx across, ph above the pool surface, lz metres out from the pool centre (downstream), aimed th above the pool
		var a3 := v.substr(5).split(",")
		var lst := LandscapeSites.falls()
		var idx := int(a3[0])
		if idx >= lst.size():
			return
		var w: Dictionary = lst[idx]
		var fdir: Vector2 = w["dir"]
		var fside := Vector2(-fdir.y, fdir.x)
		var pc: Vector2 = w["pool"]
		var lx := float(a3[1]) if a3.size() > 1 else 0.0
		var ph := float(a3[2]) if a3.size() > 2 else 4.0
		var lz := float(a3[3]) if a3.size() > 3 else 50.0
		var th := float(a3[4]) if a3.size() > 4 else float(w["drop"]) * 0.45
		var cp := pc + fside * lx + fdir * lz
		var mid: Vector2 = (w["lip"] as Vector2).lerp(w["base"], 0.5)
		_free_cam(p, Vector3(cp.x, float(w["pool_y"]) + ph, cp.y), Vector3(mid.x, float(w["pool_y"]) + th, mid.y), k)
		return
	if v.begins_with("anchor:"):                          # "anchor:kind,i[,dist,ph,az]": a free camera dist m from anchor i of that kind (turbine, pylon, mast, crane), ph above its base, seen from azimuth az (rad)
		var a6 := v.substr(7).split(",")
		var list: Array = []
		for an: Dictionary in AnchorSites.all_anchors():
			if String(an["kind"]) == a6[0]:
				list.append(an)
		var ai := int(a6[1])
		if ai >= list.size():
			return
		var an2: Dictionary = list[ai]
		var ab: Vector3 = an2["base"]
		var ad := float(a6[2]) if a6.size() > 2 else 110.0
		var aph := float(a6[3]) if a6.size() > 3 else 6.0
		var az := float(a6[4]) if a6.size() > 4 else 0.9
		var cp2 := Vector3(ab.x + cos(az) * ad, 0.0, ab.z + sin(az) * ad)
		for da2: float in [0.0, 0.3, -0.3, 0.6, -0.6, 0.9, -0.9, 1.3, -1.3, 1.8, -1.8, 2.4, -2.4, 3.1]:               # the first azimuth near the asked one with no tree within 10 m of the camera
			var tp2 := Vector2(ab.x + cos(az + da2) * ad, ab.z + sin(az + da2) * ad)
			if _clear_of_trees(tp2.x, tp2.y, 10.0):
				cp2 = Vector3(tp2.x, 0.0, tp2.y)
				break
		cp2.y = TerrainHeight.height_at(cp2.x, cp2.z) + aph
		_free_cam(p, cp2, ab + Vector3(0.0, float(an2["height"]) * 0.55, 0.0), k)
		return
	if v.begins_with("strip:"):                           # "strip:i[,dist,ph,az]": a free camera dist m from the centre of airstrip i
		var a7 := v.substr(6).split(",")
		var sl := LandscapeSites.strips()
		var si := int(a7[0])
		if si >= sl.size():
			return
		var st: Dictionary = sl[si]
		var sc: Vector2 = st["c"]
		var sdist := float(a7[1]) if a7.size() > 1 else 150.0
		var sph := float(a7[2]) if a7.size() > 2 else 14.0
		var saz := float(a7[3]) if a7.size() > 3 else 0.7
		var cp3 := Vector3(sc.x + cos(saz) * sdist, 0.0, sc.y + sin(saz) * sdist)
		for da3: float in [0.0, 0.3, -0.3, 0.6, -0.6, 0.9, -0.9, 1.3, -1.3, 1.8, -1.8, 2.4, -2.4, 3.1]:
			var tp3 := Vector2(sc.x + cos(saz + da3) * sdist, sc.y + sin(saz + da3) * sdist)
			if _clear_of_trees(tp3.x, tp3.y, 10.0):
				cp3 = Vector3(tp3.x, 0.0, tp3.y)
				break
		cp3.y = TerrainHeight.height_at(cp3.x, cp3.z) + sph
		_free_cam(p, cp3, Vector3(sc.x, float(st["y"]) + 3.0, sc.y), k)
		return
	var x := 0.0
	var z := 0.0
	var yaw := 0.0
	var dist := -1.0
	if v.begins_with("pool:"):                               # "pool:i[,r,az_deg,cam_dist]": the real hero r m from the plunge pool of waterfall i, az degrees off the downstream direction, facing the fall
		var apl := v.substr(5).split(",")
		var fl2 := LandscapeSites.falls()
		var fi2 := int(apl[0])
		if fi2 >= fl2.size():
			return
		var fw2: Dictionary = fl2[fi2]
		var pr := float(apl[1]) if apl.size() > 1 else 26.0
		var paz := deg_to_rad(float(apl[2])) if apl.size() > 2 else 0.0
		var ppos: Vector2 = (fw2["pool"] as Vector2) + (fw2["dir"] as Vector2).rotated(paz) * pr
		var toward: Vector2 = ((fw2["base"] as Vector2) - ppos).normalized()
		x = ppos.x
		z = ppos.y
		yaw = atan2(-toward.x, -toward.y)
		dist = float(apl[3]) if apl.size() > 3 else -1.0
	elif v.begins_with("airstrip:"):                         # "airstrip:i[,along_m,yaw_off_deg,cam_dist]": the real hero on airstrip i, along_m from its centre along the strip, facing along it (turned by yaw_off)
		var ast := v.substr(9).split(",")
		var sl2 := LandscapeSites.strips()
		var si2 := int(ast[0])
		if si2 >= sl2.size():
			return
		var st2: Dictionary = sl2[si2]
		var su: Vector2 = st2["u"]
		var sp2: Vector2 = (st2["c"] as Vector2) + su * (float(ast[1]) if ast.size() > 1 else -120.0)
		x = sp2.x
		z = sp2.y
		yaw = atan2(-su.x, -su.y) + PI + deg_to_rad(float(ast[2]) if ast.size() > 2 else 0.0)
		dist = float(ast[3]) if ast.size() > 3 else -1.0
	elif v.begins_with("beach:"):                            # "beach:z[,yaw_off_deg,dist[,inland]]": the real hero on the west beach at z, `inland` m above the first dry sand (default 14), facing the sea (west) turned by yaw_off degrees
		var ab := v.substr(6).split(",")
		z = float(ab[0])
		var bx := -(TerrainHeight.WORLD_HALF - 120.0)
		while bx < -1000.0 and TerrainHeight.height_at(bx, z) < TerrainHeight.SEA_LEVEL + 1.2:
			bx += 3.0
		x = bx + (float(ab[3]) if ab.size() > 3 else 14.0)
		yaw = PI * 0.5 + deg_to_rad(float(ab[1]) if ab.size() > 1 else 0.0)
		dist = float(ab[2]) if ab.size() > 2 else -1.0
	elif v.begins_with("road:"):
		var a4 := v.substr(5).split(",")
		var rp := _road_point(a4[0], float(a4[1]))
		if rp.is_empty():
			return
		var q: Vector2 = rp[0]
		var d: Vector2 = rp[1]
		x = q.x
		z = q.y
		yaw = atan2(-d.x, -d.y) + (float(a4[2]) if a4.size() > 2 else 0.0)
		dist = float(a4[3]) if a4.size() > 3 else -1.0
	elif v.begins_with("hero:"):
		var a5 := v.substr(5).split(",")
		x = float(a5[0])
		z = float(a5[1])
		yaw = float(a5[2]) if a5.size() > 2 else 0.0
		dist = float(a5[3]) if a5.size() > 3 else -1.0
	else:
		return
	if k == 0:
		var pos3 := Vector3(x, TerrainHeight.height_at(x, z) + 0.8, z)
		p.camera_rig.cine_clear()
		p.global_position = pos3
		p.velocity = Vector3.ZERO
		p.camera_rig.yaw = yaw
		_settle(pos3)
		p.teleport_to(pos3)
		p.camera_rig.yaw = yaw
		if dist > 0.0 and "distance" in p.camera_rig:
			p.camera_rig.set("distance", dist)
