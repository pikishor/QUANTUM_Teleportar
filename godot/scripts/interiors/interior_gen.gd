class_name InteriorGen
extends RefCounted
## Entry point of the procedural interiors (contract: docs/interiors_interface.md).
##   var interior := InteriorGen.build(&"club", 7, Vector3(900, 600, 900), Game.quality)   # an Interior node, NOT yet in the tree
##   parent.add_child(interior) ... interior.queue_free()                                  # freeing releases everything it made
## The same (type, seed) always gives the same rooms, props, anchors and colliders whatever the tier. Plans and mesh sets of the last few interiors are kept in two small LRU caches
## (re-entering the shop you just left costs milliseconds; at most CACHE_PLANS plans and CACHE_MESHES mesh sets stay alive, `clear_cache()` drops them).

const TYPES: Array[StringName] = [&"weapons", &"clinic", &"tech", &"bar", &"club", &"lobby", &"apartment", &"checkpoint", &"bodega", &"warehouse"]
const CACHE_PLANS := 6
const CACHE_MESHES := 3

static var _plans: Dictionary = {}          ## "type:seed" -> InteriorPlan
static var _plan_order: Array[String] = []
static var _meshes: Dictionary = {}         ## "type:seed:tier" -> mesh set
static var _mesh_order: Array[String] = []


static func build(type: StringName, seed: int, origin: Vector3, quality: int) -> Node3D:
	var t: StringName = type if InteriorKinds.has_type(type) else &"bodega"
	var plan := plan_for(t, seed)
	var node := Interior.new()
	node.setup(plan, origin, quality, mesh_set(plan, quality))
	return node


## The (cached) plan of a type and seed.
static func plan_for(type: StringName, seed: int) -> InteriorPlan:
	var key := "%s:%d" % [String(type), seed]
	if _plans.has(key):
		_plan_order.erase(key)
		_plan_order.append(key)
		return _plans[key]
	var plan := InteriorPlan.generate(type, seed)
	_plans[key] = plan
	_plan_order.append(key)
	while _plan_order.size() > CACHE_PLANS:
		_plans.erase(_plan_order.pop_front())
	return plan


static func mesh_set(plan: InteriorPlan, quality: int) -> Dictionary:
	var key := "%s:%d:%d" % [String(plan.type), plan.seed_value, clampi(quality, 0, 2)]
	if _meshes.has(key):
		_mesh_order.erase(key)
		_mesh_order.append(key)
		return _meshes[key]
	var ms := InteriorMesher.build(plan, quality)
	_meshes[key] = ms
	_mesh_order.append(key)
	while _mesh_order.size() > CACHE_MESHES:
		_meshes.erase(_mesh_order.pop_front())
	return ms


static func clear_cache() -> void:
	_plans.clear()
	_plan_order.clear()
	_meshes.clear()
	_mesh_order.clear()


## The type for a door id (a stable hash), for street doors that only know a number.
static func type_for_id(id: int) -> StringName:
	return TYPES[absi(id) % TYPES.size()]
