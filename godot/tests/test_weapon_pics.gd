extends RefCounted
## The weapon pictures (wave 114, tools/icons/weapon_pics.sh, scripts/ui/weapon_pics.gd): every weapon of WeaponDefs.all_ids() has a thumb and a card picture in the atlas pages, the pages are VRAM-compressed
## textures of at most 1024 x 1024, a picture is a full-frame AtlasTexture (256 x 128 / 512 x 256) over its cropped rectangle, the pages are an LRU (a handful in memory, never all 37), ItemIcons hands them out,
## and a picture is NOT stale: the md5 of the weapon's model file is the one the picture was rendered from (a model changed without `tools/icons/weapon_pics.sh` fails here). No scene, about 10 s.
## Run: tools/test.sh tests/test_weapon_pics.gd


func run(_host: Node) -> void:
	var ids := WeaponDefs.all_ids()
	TestLib.check(FileAccess.file_exists(WeaponPics.MANIFEST), "the picture manifest exists (assets/icons/wp/manifest.json)")
	TestLib.check(WeaponPics.count() == ids.size(), "every weapon has an entry: %d of %d" % [WeaponPics.count(), ids.size()])
	var stale := WeaponPics.stale_ids()
	TestLib.check(stale.is_empty(), "no picture is older than its model (run tools/icons/weapon_pics.sh): %s" % str(stale.slice(0, 8)))
	var missing_t: Array[String] = []
	var bad_size: Array[String] = []
	var bad_rect: Array[String] = []
	var cells := {}
	var dup: Array[String] = []
	for id in ids:
		for kind: String in ["t", "c"]:
			var pl := WeaponPics.place(kind, id)
			if pl.is_empty():
				missing_t.append("%s/%s" % [id, kind])
				continue
			var tex: Texture2D = WeaponPics.thumb(id) if kind == "t" else WeaponPics.card(id)
			if tex == null:
				missing_t.append("%s/%s load" % [id, kind])
				continue
			var want := Vector2(256, 128) if kind == "t" else Vector2(512, 256)
			if tex.get_size() != want:
				bad_size.append("%s/%s %s" % [id, kind, tex.get_size()])
			var reg: Rect2 = pl["region"]
			var mg: Rect2 = pl["margin"]
			var at := tex as AtlasTexture
			if at == null or not Rect2(Vector2.ZERO, at.atlas.get_size()).encloses(reg) or reg.size.x < 8.0 or reg.size.y < 8.0 or mg.position.x + reg.size.x > want.x + 0.5 or mg.position.y + reg.size.y > want.y + 0.5:
				bad_rect.append("%s/%s" % [id, kind])
			var key := "%s|%s" % [pl["path"], reg]
			if cells.has(key):
				dup.append("%s = %s" % [id, cells[key]])
			cells[key] = id
	TestLib.check(missing_t.is_empty(), "every weapon has a thumb and a card picture in the pages (%s)" % str(missing_t.slice(0, 6)))
	TestLib.check(bad_size.is_empty(), "a picture is a full frame: 256 x 128 (thumb) or 512 x 256 (card) (%s)" % str(bad_size.slice(0, 4)))
	TestLib.check(bad_rect.is_empty(), "every cropped sprite lies inside its page and its frame (%s)" % str(bad_rect.slice(0, 6)))
	TestLib.check(dup.is_empty(), "no two weapons share a cell of a page (%s)" % str(dup.slice(0, 4)))
	# the pages: textures of at most 1024 x 1024, VRAM compressed
	var big: Array[String] = []
	var n_pages := 0
	for cls: StringName in WeaponDefs.CLASS_ORDER:
		for k: String in ["t", "c"]:
			var pg := 0
			while ResourceLoader.exists("%s%s_%s_%d.webp" % [WeaponPics.DIR, k, cls, pg]):
				var t := load("%s%s_%s_%d.webp" % [WeaponPics.DIR, k, cls, pg]) as Texture2D
				n_pages += 1
				if t == null or t.get_width() > 1024 or t.get_height() > 1024:
					big.append("%s_%s_%d" % [k, cls, pg])
				pg += 1
	TestLib.check(n_pages >= 20 and big.is_empty(), "%d pages, none larger than 1024 x 1024 (%s)" % [n_pages, str(big)])
	# the LRU: ask for pictures of every class and the pages in memory stay few; an evicted picture comes back
	WeaponPics.unload()
	var first: StringName = ids[0]
	var t0 := WeaponPics.card(first)
	var loads0 := WeaponPics.page_loads
	for id in ids:
		WeaponPics.card(id)
		WeaponPics.thumb(id)
	TestLib.check(WeaponPics.pages_loaded() <= WeaponPics.MAX_PAGES and WeaponPics._card_pages() <= WeaponPics.MAX_CARD_PAGES, "browsing all %d weapons keeps at most %d pages in memory (%d), at most %d of them card pages (%d)" % [ids.size(), WeaponPics.MAX_PAGES, WeaponPics.pages_loaded(), WeaponPics.MAX_CARD_PAGES, WeaponPics._card_pages()])
	# the wheel shows one weapon of every class at once, with the HUD's own pictures: that must not load a page per picture, every frame
	WeaponPics.unload()
	var before := WeaponPics.page_loads
	for round in 3:
		for cls: StringName in WeaponDefs.CLASS_ORDER:
			WeaponPics.thumb(WeaponDefs.in_class(cls)[0])
	var wheel_loads := WeaponPics.page_loads - before
	for round in 3:
		for cls: StringName in WeaponDefs.CLASS_ORDER:
			WeaponPics.thumb(WeaponDefs.in_class(cls)[0])
	TestLib.check(WeaponPics.page_loads - before == wheel_loads and wheel_loads <= WeaponDefs.CLASS_ORDER.size(), "the thumbs of a wheel (one weapon of each of the %d classes) load %d pages once and then none (a wheel drawn every frame must not thrash)" % [WeaponDefs.CLASS_ORDER.size(), wheel_loads])
	TestLib.check(WeaponPics.page_loads > loads0, "pages were loaded on demand (%d loads)" % (WeaponPics.page_loads - loads0))
	TestLib.check(t0 != null and WeaponPics.card(first) != null and WeaponPics.card(first).get_size() == Vector2(512, 256), "a picture whose page was dropped comes back")
	# ItemIcons hands the atlas pictures out
	var item_t := ItemIcons.weapon(&"a_pillar")
	var item_c := ItemIcons.weapon_large(&"a_pillar")
	TestLib.check(item_t is AtlasTexture and item_t.get_size() == Vector2(256, 128) and item_c is AtlasTexture and item_c.get_size() == Vector2(512, 256), "ItemIcons.weapon / weapon_large return the thumb and the card of the atlas")
	TestLib.check(ItemIcons.texture("w", &"railgun") is AtlasTexture, "a button picture (texture w) is the thumb too")
	# the visible sprite helper and the backdrops
	var tg := WeaponPics.tight("c", &"m_arcsabre")
	TestLib.check(not tg.is_empty() and (tg["size"] as Vector2).x / (tg["size"] as Vector2).y > 3.0, "a blade's sprite is long and thin (%s)" % str(tg.get("size")))
	var tp := WeaponPics.tight("c", &"pistol")
	TestLib.check(not tp.is_empty() and (tp["size"] as Vector2).x / (tp["size"] as Vector2).y < 2.6, "a pistol's sprite is compact (%s)" % str(tp.get("size")))
	for cls: StringName in WeaponDefs.CLASS_ORDER:
		TestLib.check(WeaponPics.glow_texture(cls) != null, "class %s has its backdrop glow" % cls)
	# texture memory: one card page is 1 MB, the whole LRU a few MB; the manifest weighs a little
	var manifest_kb := float(FileAccess.get_file_as_bytes(WeaponPics.MANIFEST).size()) / 1024.0
	TestLib.check(manifest_kb < 120.0, "the manifest is small (%.0f KB)" % manifest_kb)
	# unknown ids are no crash
	TestLib.check(WeaponPics.thumb(&"no_such_weapon") == null and not WeaponPics.has(&"no_such_weapon"), "an unknown weapon has no picture and no error")
