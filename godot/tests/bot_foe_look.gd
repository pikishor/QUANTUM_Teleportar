extends RefCounted
## Look-dev bot for the enemy roster look (wave 113; a copy of bot_alien.gd that also prints the state of the FoeHuman bodies): tools/bot.sh res://tests/bot_foe_look.gd OUT EVERY COUNT   (EVERY = frames per view, COUNT = views)
##   QUALITY=0|1|2 picks the tier, BOT_RES=2400x1080 the resolution, ENGINE_ARGS="--fixed-fps 12" makes game seconds per frame fixed.
## env OUT_VIEWS  semicolon list, one per shot slot:
##     "x,z,yaw,id:n[,id:n ...][,front=22][,dist=6][,lift=0][,aggro=1][,state=<state>][,hurt=0.6]"   the real hero at (x, z) looking along yaw (radians, 0 = -Z north), groups `front` m ahead
##     "@site,dist,angle_deg[,id:n ...][,aggro=1][,state=..][,run=secs][,front=..]"        the hero `dist` m from a site (angle round it), looking at it; the garrison / boss is populated
##   OUT_HOUR (default 12), OUT_HUD=0 hides the HUD layer, OUT_GOD=1 (default) keeps the hero alive
var _views: Array[String] = []
var _i := 0
var _f := 0
var _hud: CanvasItem = null
var _dumped := {}


func _init() -> void:
	for s in OS.get_environment("OUT_VIEWS").split(";", false):
		_views.append(s.strip_edges())


func step(_t: float, _d: float) -> bool:
	var p := Game.player as Player
	if p == null:
		return false
	var wait: int = int(Dev.get(&"_args").get("every", "20")) if Dev.get(&"_args") is Dictionary else 20
	if _f == 2:
		Game.state = &"play"
		p.max_hp = 1.0e6
		p.hp = p.max_hp
		if Game.enemies != null:
			(Game.enemies as EnemyManager).clear()
		if Encounters.current != null:
			Encounters.current.enabled = false
		var city := Game.world as City
		var hour := float(OS.get_environment("OUT_HOUR")) if OS.get_environment("OUT_HOUR") != "" else 12.0
		if city != null and city.day_night != null:
			city.day_night.frozen = true
			city.day_night.set_hour(hour)
		if OS.get_environment("OUT_HUD") == "0":
			_hud = Game.get_tree().root.find_child("Hud", true, false) as CanvasItem
			if _hud != null:
				_hud.visible = false
	if _f >= 3 and _i < _views.size():
		_apply(p, _views[_i], (_f - 3) % maxi(wait, 1))
		if (_f - 3) % maxi(wait, 1) == wait - 1:
			var w := AlienWorld.instance
			if w != null:
				print("ALIEN shot ", _i, " ", w.stats(), " ", w.census(p.global_position, 150.0))
				var cam0 := Game.camera as Camera3D
				for c in w.creatures:
					var rf := c as RosterFoe
					if rf != null:
						var hd := rf.hum
						var extra := " hum EMPTY (procedural or creature)"
						if not hd.is_empty():
							var bd := hd["body"] as MeshInstance3D
							var tris := 0
							var am := bd.mesh as ArrayMesh
							if am != null and am.get_surface_count() > 0:
								tris = am.surface_get_array_index_len(0) / 3
							extra = " hum lod %d tris %d far_k %s tele %s hit %s pulse %s mat %s" % [int(hd["lod"]), tris, str(bd.get_instance_shader_parameter(&"far_k")), str(bd.get_instance_shader_parameter(&"tele")), str(bd.get_instance_shader_parameter(&"hit_k")), str(rf._pulse), str((rf.mat as ShaderMaterial).shader.resource_path.get_file()) if rf.mat is ShaderMaterial else "?"]
						print("   FOE ", rf.id, " d ", snappedf(rf.flat_dist(), 0.1), extra)
						if not hd.is_empty() and rf.id == &"auth_drone" and not _dumped.has(&"params"):
							_dumped[&"params"] = true
							var sm := rf.mat as ShaderMaterial
							var parts: Array[String] = []
							for u in sm.shader.get_shader_uniform_list():
								var nm := String(u["name"])
								parts.append("%s=%s" % [nm, str(sm.get_shader_parameter(nm))])
							print("      PARAMS ", " ".join(parts))
							var bb := hd["body"] as MeshInstance3D
							print("      BODY override ", bb.material_override != null, " surf_mat ", bb.mesh.surface_get_material(0) if bb.mesh != null else null, " visible ", bb.is_visible_in_tree(), " layers ", bb.layers, " scale ", bb.global_transform.basis.get_scale())
							var kids := (hd["root"] as Node).find_children("*", "MeshInstance3D", true, false)
							for k in kids:
								var mk := k as MeshInstance3D
								print("      MI ", mk.name, " vis ", mk.is_visible_in_tree(), " cast ", mk.cast_shadow, " tris ", FoeHuman.tris(mk.mesh) if mk.mesh != null else -1, " ovr ", mk.material_override)
						if not hd.is_empty() and not _dumped.has(rf.id):
							_dumped[rf.id] = true
							var pr := hd["proto"] as Dictionary
							for which in ["near", "mid", "far"]:
								var mm := pr[which] as ArrayMesh
								if mm == null:
									continue
								var arr := mm.surface_get_arrays(0)
								var cols := arr[Mesh.ARRAY_COLOR] as PackedColorArray
								var hist := {}
								for cc in cols:
									var kk := int(round(cc.b * 16.0))
									hist[kk] = int(hist.get(kk, 0)) + 1
								print("      COLORS ", rf.id, " ", which, " verts ", cols.size(), " kinds ", hist)
				for c in w.creatures.slice(0, 4):
					print("   creature ", c.id, " pos ", c.global_position, " vis ", c.is_visible_in_tree(), " frustum ", cam0.is_position_in_frustum(c.center()) if cam0 != null else "?", " state ", c.state, " model ", c.model != null, " scale ", c.scale)
				for k in w.sites:
					var nd: Variant = (w.sites[k] as Dictionary).get("node")
					if nd != null and is_instance_valid(nd):
						var mi := nd as MeshInstance3D
						var cam := Game.camera as Camera3D
						print("   site mesh ", k, " pos ", mi.global_position, " aabb ", mi.get_aabb(), " visible ", mi.is_visible_in_tree(), " in frustum ", cam.is_position_in_frustum(mi.global_position + Vector3(0, 6, 0)) if cam != null else "?", " hero ", p.global_position, " cam ", cam.global_position if cam != null else "?")
	_f += 1
	if _f >= 3 and (_f - 3) % maxi(wait, 1) == 0 and _f > 3:
		_i += 1
	return _i >= _views.size()


func _apply(p: Player, v: String, k: int) -> void:
	var city := Game.world as City
	var w := AlienWorld.instance
	if city == null or w == null:
		return
	var parts := v.split(",")
	var site := ""
	var x := 0.0
	var z := 0.0
	var yaw := 0.0
	var first_group := 3
	var front := 22.0
	var dist := -1.0
	var lift := 0.0
	var aggro := false
	var state := ""
	var hurt := 0.0
	var groups: Array = []
	if parts[0].begins_with("@"):
		site = parts[0].substr(1)
		var s := AlienSites.by_id(StringName(site))
		var sp: Vector3 = s["pos"]
		var ang := deg_to_rad(float(parts[2]))
		var d := float(parts[1])
		x = sp.x + sin(ang) * d
		z = sp.z + cos(ang) * d
		yaw = atan2(-(sp.x - x), -(sp.z - z))
		first_group = 3
	else:
		x = float(parts[0])
		z = float(parts[1])
		yaw = float(parts[2])
	for i in range(3, parts.size()):
		var s2 := parts[i]
		if s2.begins_with("front="):
			front = float(s2.substr(6))
		elif s2.begins_with("dist="):
			dist = float(s2.substr(5))
		elif s2.begins_with("lift="):
			lift = float(s2.substr(5))
		elif s2.begins_with("aggro="):
			aggro = s2.substr(6) == "1"
		elif s2.begins_with("state="):
			state = s2.substr(6)
		elif s2.begins_with("hurt="):
			hurt = float(s2.substr(5))
		elif ":" in s2:
			groups.append(s2)
	if k == 0:
		var pos := Vector3(x, TerrainHeight.height_at(x, z) + 0.8, z)
		p.camera_rig.cine_clear()
		p.global_position = pos
		p.velocity = Vector3.ZERO
		p.camera_rig.yaw = yaw
		if city.terrain != null:
			city.terrain.settle(pos)
		if city.vegetation != null:
			city.vegetation.settle(pos)
		if city.sites != null and city.sites.has_method(&"settle"):
			city.sites.call(&"settle", pos)
		p.teleport_to(pos)
		p.camera_rig.yaw = yaw
		if dist > 0.0 and "distance" in p.camera_rig:
			p.camera_rig.set("distance", dist)
		w.force_active = true
		w.ambient_enabled = false
		w.clear_all()
		w.sites.clear()
		var made: Array[AlienCreature] = []
		if site != "":
			AlienSites.reset_all()
			made = w.populate(StringName(site))
			w._site_t = 0.0
		var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var side := Vector3(fwd.z, 0.0, -fwd.x)
		var n_groups := groups.size()
		for gi in n_groups:
			var gs := String(groups[gi]).split(":")
			var id := StringName(gs[0])
			var n := int(gs[1])
			var fan := (float(gi) - float(n_groups - 1) * 0.5) * 9.0
			var at := pos + fwd * (front + float(gi) * 3.0) + side * fan
			at.y = TerrainHeight.height_at(at.x, at.z)
			made.append_array(w.spawn_group(id, at, n, &"", 4.0, aggro))
		if state != "":
			for c in made:
				c._go(StringName(state))
		if hurt > 0.0:                                                       # hurt=0.5: the health pips of the foes show 30-70 % of their health lost
			var hi := 0
			for c in made:
				c.hp = c.max_hp * clampf(1.0 - hurt * (0.3 + 0.35 * float(hi % 3)), 0.05, 1.0)
				hi += 1
		print("ALIEN ", v, " -> ", w.stats())
