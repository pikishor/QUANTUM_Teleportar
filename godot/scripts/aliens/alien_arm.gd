class_name AlienArm
extends AlienCreature
## One arm of the deep kraken: it lies under the water until the boss wakes, rises (a ripple ring first), follows the hero with its tip, marks a ring on the water where it will slam (jump or
## swim out of it), slams, and rests. It has its own health; while any arm lives the kraken's mantle is shielded.

var boss: AlienBoss = null


func _tick_extra(dt: float, d: float) -> void:
	var base := Vector2(home.x, home.z)
	var hd := _hero2().distance_to(base) if hero_pos().is_finite() else INF
	water_y = TerrainHeight.water_level_for(position.x, position.z, ground)
	match state:
		&"idle":
			set_exposed(false)
			rise = 0.0
			if boss != null and boss._engaged and hd < 55.0:
				if world != null:
					world.fx.ring(Vector3(position.x, water_y + 0.1, position.z), 3.2, 1.0, Color(0.3, 1.0, 0.9))
				_go(&"rising")
		&"rising":
			if st_t < 1.0:
				return
			set_exposed(true)
			rise = clampf((st_t - 1.0) / 0.9, 0.0, 1.0)
			if world != null and rise < 0.1:
				world.fx.splash(Vector3(position.x, water_y, position.z), 3.0)
			if st_t >= 1.9:
				_go(&"up")
		&"up":
			rise = 1.0
			_face(_hero2(), dt, 2.0)
			if cool <= 0.0 and hd <= float(spec["reach"]) + 5.0 and hd > 2.0:
				var p := hero_pos()
				_aim = Vector3(p.x, water_y, p.z)
				if world != null:
					world.fx.ring(_aim + Vector3(0.0, 0.1, 0.0), 4.0, float(spec["windup"]) * _aggr_k(), Color(0.3, 1.0, 0.9))
				_pulse = 1.0
				_go(&"windup")
		&"windup":
			_face(Vector2(_aim.x, _aim.z), dt, 4.0)
			_pulse = clampf(st_t / (float(spec["windup"]) * _aggr_k()), 0.0, 1.0)
			if st_t >= float(spec["windup"]) * _aggr_k():
				if world != null:
					world.fx.splash(_aim, 4.0)
				FX.shake(0.25)
				Sfx.play_at(&"water_splash_big", _aim, -2.0)
				var h := hero_pos()
				if Vector2(h.x - _aim.x, h.z - _aim.z).length() < 4.0 and h.y - _aim.y < 2.2:
					attacks_done += 1
					_hurt_hero(float(spec["dmg"]))
				cool = float(spec["cool"]) * _aggr_k()
				_go(&"up")
