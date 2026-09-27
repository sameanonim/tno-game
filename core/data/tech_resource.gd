class_name TechResource
extends Resource

##
## TechResource: Модель научно-исследовательских проектов (НИОКР / R&D)
##
## Реализует технологические ветви TNO: ВПК, Ядерная программа, Промышленность, Доктрины.
##

enum TechCategory {
	INDUSTRY,
	INFANTRY_WEAPONS,
	ARMOR_AND_ARTILLERY,
	AIR_AND_ROCKETRY,
	NUCLEAR_RESEARCH,
	DOCTRINE_AND_CYBERNETICS
}

@export var tech_id: String = "tech_advanced_rifles_1"
@export var tech_name: String = "AKM Pattern Modernization"
@export var category: TechCategory = TechCategory.INFANTRY_WEAPONS
@export_multiline var description: String = "Standardizes assault rifle production with stamped receivers."
@export var icon_path: String = "res://icon.svg"

@export_group("Research Cost & Prerequisites")
## Базовая стоимость исследования в очках НИОКР
@export var research_cost: float = 120.0
## Минимальный год исторического соответствия
@export var historical_year: int = 1962
## Список ID предшествующих обязательных технологий
@export var prerequisite_techs: Array[String] = []

@export_group("Modifiers & Unlocks")
## Пассивные макроэкономические и военные бонусы
@export var state_modifiers: Dictionary = {
	"infantry_combat_bonus": 0.10,
	"production_efficiency_gain": 0.05
}

## Разблокируемые спец-директивы или типы операций
@export var unlocked_directives: Array[String] = []


func can_research(completed_tech_ids: Array[String], current_year: int) -> bool:
	for req in prerequisite_techs:
		if not completed_tech_ids.has(req):
			return false
	return true


func to_dict() -> Dictionary:
	return {
		"tech_id": tech_id,
		"tech_name": tech_name,
		"category": category,
		"description": description,
		"icon_path": icon_path,
		"research_cost": research_cost,
		"historical_year": historical_year,
		"prerequisite_techs": prerequisite_techs.duplicate(),
		"state_modifiers": state_modifiers.duplicate(true),
		"unlocked_directives": unlocked_directives.duplicate()
	}


static func from_dict(data: Dictionary) -> TechResource:
	var res = TechResource.new()
	res.tech_id = data.get("tech_id", "")
	res.tech_name = data.get("tech_name", "Unknown Technology")
	res.category = data.get("category", TechCategory.INDUSTRY)
	res.description = data.get("description", "")
	res.icon_path = data.get("icon_path", "res://icon.svg")
	res.research_cost = float(data.get("research_cost", 100.0))
	res.historical_year = int(data.get("historical_year", 1962))
	res.prerequisite_techs.clear()
	for p in data.get("prerequisite_techs", []):
		res.prerequisite_techs.append(str(p))
	res.state_modifiers = data.get("state_modifiers", {}).duplicate(true)
	res.unlocked_directives.clear()
	for d in data.get("unlocked_directives", []):
		res.unlocked_directives.append(str(d))
	return res
