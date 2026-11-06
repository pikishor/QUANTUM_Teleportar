class_name Freedom
extends Node
## Open-world freedom (GTA / COD style), the director: one node of Main that owns the pieces and the one contextual prompt.
##   Hijack   take any vehicle (traffic, parked, bikes, buses, patrol cars, hover): entry ghost, the driver thrown out on the kerb side (scripts/freedom/hijack.gd)
##   Charges  QUANTUM CHARGES (C4) with a detonator, chained to every other blast (scripts/freedom/charges.gd)
##   Jobs     street races, taxi fares, deliveries, bounties and stunt jumps on markers across the whole map (scripts/freedom/jobs.gd)
## Also here: `Freedom.job_prompt()` / `Freedom.vehicle_prompt()` (the one contextual line the HUD shows: a job marker, a vehicle to take) and `Freedom.markers()` for
## the minimap. Doors are a separate layer (scripts/world/city_doors.gd, scripts/interiors_gameplay/): every lot has one, always glowing, with an ENTER prompt.

static var current: Freedom

var hijack: Hijack
var charges: Charges
var jobs: Jobs
var crates: WeaponCrates
var repairs: RepairStations


func _ready() -> void:
	name = "Freedom"
	current = self
	hijack = Hijack.new()
	add_child(hijack)
	charges = Charges.new()
	add_child(charges)
	jobs = Jobs.new()
	add_child(jobs)
	crates = WeaponCrates.new()
	add_child(crates)
	repairs = RepairStations.new()
	add_child(repairs)


func _exit_tree() -> void:
	if current == self:
		current = null


## The job on this marker ("STREET RACE  SLOW DOWN", ...), "" when none. No key: jobs start by themselves.
static func job_prompt() -> String:
	if current == null or current.jobs == null or not Game.is_playing():
		return ""
	return current.jobs.prompt


## The vehicle the hero could take from here ("HIJACK TAXI", "ENTER BUS"), "" when none or already driving.
static func vehicle_prompt() -> String:
	if current == null or not is_instance_valid(Game.player) or not Game.is_playing() or Game.player.get(&"vehicle") != null:
		return ""
	if is_instance_valid(Game.vehicles) and Game.vehicles.has_method(&"reach_car"):
		var car := Game.vehicles.call(&"reach_car", Game.player.global_position) as Vehicle
		if car != null:
			return ("HIJACK " if (car.ai or car.chasing) else "ENTER ") + Hijack.vehicle_name(car.kind)
	return ""


## Minimap markers {pos, color, radius, goal} of the jobs and stunt rings.
static func markers() -> Array[Dictionary]:
	if current == null or current.jobs == null:
		return []
	var out := current.jobs.markers()
	if current.crates != null:
		out.append_array(current.crates.markers())
	if current.repairs != null:
		out.append_array(current.repairs.markers())
	return out
