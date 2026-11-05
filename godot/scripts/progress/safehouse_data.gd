class_name SafehouseData
extends RefCounted
## Ids of the safehouses and their upgrades, kept apart from Safehouses so Progress (the save) does not depend on the class that depends on it.

const IDS: Array[StringName] = [&"loft", &"depot", &"penthouse", &"bunker"]
const UPS: Array[StringName] = [&"bed", &"locker", &"bench"]
const MAX_LEVEL := 2
