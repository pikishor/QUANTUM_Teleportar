class_name MenuFlags
extends RefCounted
## Feature flags of the default menus (docs/DESIGN.md "Cut or hide from the default experience"). The code of every cut screen stays; the default menus simply do not offer it:
##   title:  PLAY / CONTINUE, OPTIONS, EXTRAS            pause:  RESUME, MISSIONS, MAP, LOADOUT, UPGRADES, OPTIONS, EXTRAS
## EXTRAS is the one page for everything else. It lists SUIT, PHOTO, CHAPTERS, NEW GAME, DEMO and (debug builds) TEST by default; the CUT screens below show up only while `all_extras`
## is on (Options > GAME > ALL EXTRAS, saved in settings.cfg), in the DEMO and in the TEST menu's full-menu mode. Tests and tools can still press any button id directly: the flag
## changes what is OFFERED, not what exists.

## Screens that are cut from the default menus, by the button id that opens them (and the HERO hub tabs).
const CUT: Array[StringName] = [&"side_open", &"heist_open", &"sh_open", &"ach", &"arena_open", &"hero_tab_skills", &"hero_tab_craft", &"skills_open"]
## What the cut screens are called in the owner's list (crafting, factions, safehouse management, photo mode, heists planning, boss rush, achievements, collectibles, skill depth,
## companion commands) and where each one went: either behind the flag (a screen) or into a toast / the HUD (no screen at all).
const CUT_NOTES := {
	&"crafting": "HERO hub CRAFT tab, flag",
	&"factions": "no screen; the territory plate shows only while wanted",
	&"safehouse": "EXTRAS > SAFEHOUSE, flag",
	&"photo": "EXTRAS > PHOTO (kept: one small camera card)",
	&"heists": "EXTRAS > HEISTS, flag; heists are Mission Board types",
	&"boss_rush": "EXTRAS > ARENA, flag; boss fights are Mission Board types",
	&"achievements": "EXTRAS > ACHIEVEMENTS, flag; medals arrive as toasts",
	&"collectibles": "no screen; pickups are toasts",
	&"skills": "HERO hub SKILLS tab, flag; UPGRADES is the flat list",
	&"companion": "MORE drawer ally orders only while an ally is with you",
}

## Mirrors UiSettings.all_extras (UiSettings.apply writes it).
static var all_extras := false


## True when the cut screens are offered: the saved option, the DEMO (Upgrades.show_all) or a test that sets the option.
static func show_cut() -> bool:
	return all_extras or Upgrades.show_all


## Is the button id offered in the menus right now?
static func offered(id: StringName) -> bool:
	return show_cut() or not CUT.has(id)
