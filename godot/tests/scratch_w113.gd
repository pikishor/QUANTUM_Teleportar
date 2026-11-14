extends RefCounted
func run(_host: Node) -> void:
	print("IDS ", WeaponDefs.IDS.size(), " rifle ", WeaponDefs.in_class(&"rifle").size())
	print("browser pages ", WeaponBrowser.pages(false, 9, false).size())
	print("PAGES ", WeaponsScreen.PAGES)
	TestLib.check(true, "ok")
