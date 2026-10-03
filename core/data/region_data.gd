class_name RegionData
extends Resource

##
## RegionData: Модель региона / провинции карты
## Содержит демографию, экономический потенциал, инфраструктуру и контроль.
##

@export var province_id: int = 1
@export var province_name: String = "Vologda"
@export var owner_tag: String = "KOM"
@export var core_tags: Array[String] = ["KOM"]

@export_group("Demographics & Industry")
@export var population: int = 420000
@export var industrial_capacity: int = 3
@export_range(0, 10, 1) var civilian_infrastructure: int = 4
@export var resource_deposits: Dictionary = {
	"steel": 12,
	"oil": 0,
	"rubber": 0,
	"rare_alloys": 2
}

@export_group("Security & Control")
@export_range(0.0, 100.0, 1.0) var unrest: float = 15.0
@export_range(0.0, 100.0, 1.0) var garrison_strength: float = 70.0
@export var terrain_type: String = "forest" # plains, forest, urban, marsh, mountains, tundra
@export var is_demilitarized: bool = false
@export var is_border_region: bool = true
@export var story_flags: Dictionary = {}
@export var is_dirty: bool = true


func mark_dirty() -> void:
	is_dirty = true


func is_core_of(country_tag: String) -> bool:
	return core_tags.has(country_tag)


func get_effective_tax_yield() -> float:
	var control_factor = (100.0 - unrest) / 100.0
	var infra_mult = 1.0 + (float(civilian_infrastructure) * 0.08)
	var core_mult = 1.0 if is_core_of(owner_tag) else 0.65
	return float(industrial_capacity) * control_factor * infra_mult * core_mult


func to_dict() -> Dictionary:
	return {
		"province_id": province_id,
		"province_name": province_name,
		"owner_tag": owner_tag,
		"core_tags": core_tags.duplicate(),
		"population": population,
		"industrial_capacity": industrial_capacity,
		"civilian_infrastructure": civilian_infrastructure,
		"resource_deposits": resource_deposits.duplicate(true),
		"unrest": unrest,
		"garrison_strength": garrison_strength,
		"terrain_type": terrain_type,
		"is_demilitarized": is_demilitarized,
		"is_border_region": is_border_region,
		"story_flags": story_flags.duplicate(true),
		"is_dirty": false
	}


static func from_dict(data: Dictionary) -> RegionData:
	var res := RegionData.new()
	res.province_id = int(data.get("province_id", 1))
	res.province_name = data.get("province_name", "")
	res.owner_tag = data.get("owner_tag", "")
	res.core_tags.clear()
	for ct in data.get("core_tags", []):
		res.core_tags.append(str(ct))
	res.population = int(data.get("population", 0))
	res.industrial_capacity = int(data.get("industrial_capacity", 0))
	res.civilian_infrastructure = int(data.get("civilian_infrastructure", 0))
	res.resource_deposits = data.get("resource_deposits", {}).duplicate(true)
	res.unrest = float(data.get("unrest", 0.0))
	res.garrison_strength = float(data.get("garrison_strength", 50.0))
	res.terrain_type = data.get("terrain_type", "plains")
	res.is_demilitarized = bool(data.get("is_demilitarized", false))
	res.is_border_region = bool(data.get("is_border_region", false))
	res.is_dirty = bool(data.get("is_dirty", false))
	if data.has("story_flags") and data["story_flags"] is Dictionary:
		res.story_flags = data["story_flags"].duplicate(true)
	return res
