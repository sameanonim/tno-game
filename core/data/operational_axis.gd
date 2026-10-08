class_name OperationalAxis
extends Resource

##
## OperationalAxis: Оперативное направление / ось наступления (TNO Warlord Campaigns)
##
## Представляет отдельную ось удара на фронте с выделенными силами,
## командиром, боевой стойкой и шкалой прогресса прорыва к целевым регионам.
##

enum Posture {
	DEFENSIVE = 0,
	BALANCED = 1,
	AGGRESSIVE_BREAKTHROUGH = 2
}

@export var axis_id: String = "axis_volga_spearhead"
@export var name: String = "Volga Operational Spearhead"
@export var target_region_ids: Array = []
@export var origin_region_id: int = 0
@export_range(0.0, 100.0, 0.5) var progress: float = 0.0

@export_group("Assigned Forces")
@export var assigned_manpower: int = 25000
@export var assigned_equipment: Dictionary = {
	"infantry_weapons": 12000,
	"heavy_equipment": 350
}

@export_group("Command & Doctrine")
@export var commander: LeaderResource
@export var posture: Posture = Posture.BALANCED

## Текущий боевой статус оси
@export var is_stalled: bool = false
@export var attrition_rate: float = 0.02
## Ход последнего боевого инцидента (для предотвращения спама дилеммами)
@export var last_incident_turn: int = -999


## Вычисляет эффективную наступательную силу оси с учетом генерала и стойки
func get_effective_combat_power(army_readiness: float, army_morale: float) -> float:
	var base_power = (float(assigned_manpower) * 0.01) + (float(assigned_equipment.get("infantry_weapons", 0)) * 0.02)
	base_power += float(assigned_equipment.get("heavy_equipment", 0)) * 0.15

	var training_mult = (army_readiness * 0.6 + army_morale * 0.4) / 100.0
	var commander_mult := 1.0
	if commander != null:
		commander_mult += float(commander.attack_skill) * 0.05
		if commander.traits.has("deep_battle_theorist"):
			commander_mult += 0.15

	var posture_mult := 1.0
	match posture:
		Posture.DEFENSIVE:
			posture_mult = 0.6
		Posture.BALANCED:
			posture_mult = 1.0
		Posture.AGGRESSIVE_BREAKTHROUGH:
			posture_mult = 1.45

	return base_power * training_mult * commander_mult * posture_mult


## Вычисляет оборонительный потенциал оси
func get_effective_defense_power(army_readiness: float) -> float:
	var base_def = (float(assigned_manpower) * 0.012) + (float(assigned_equipment.get("infantry_weapons", 0)) * 0.025)
	base_def += float(assigned_equipment.get("heavy_equipment", 0)) * 0.20

	var training_mult = maxf(army_readiness / 100.0, 0.4)
	var commander_mult := 1.0
	if commander != null:
		commander_mult += float(commander.defense_skill) * 0.06

	var posture_mult := 1.0
	match posture:
		Posture.DEFENSIVE:
			posture_mult = 1.5
		Posture.BALANCED:
			posture_mult = 1.0
		Posture.AGGRESSIVE_BREAKTHROUGH:
			posture_mult = 0.75

	return base_def * training_mult * commander_mult * posture_mult


func to_dict() -> Dictionary:
	var cmd_dict := {}
	if commander != null:
		cmd_dict = commander.to_dict()

	return {
		"axis_id": axis_id,
		"name": name,
		"target_region_ids": target_region_ids.duplicate(),
		"origin_region_id": origin_region_id,
		"progress": progress,
		"assigned_manpower": assigned_manpower,
		"assigned_equipment": assigned_equipment.duplicate(true),
		"commander": cmd_dict,
		"posture": posture,
		"is_stalled": is_stalled,
		"attrition_rate": attrition_rate,
		"last_incident_turn": last_incident_turn
	}


static func from_dict(data: Dictionary) -> OperationalAxis:
	var axis = OperationalAxis.new()
	axis.axis_id = data.get("axis_id", "axis_default")
	axis.name = data.get("name", "Unnamed Axis")
	axis.target_region_ids = []
	for tid in data.get("target_region_ids", []):
		axis.target_region_ids.append(int(tid))
	axis.origin_region_id = int(data.get("origin_region_id", 0))
	axis.progress = float(data.get("progress", 0.0))
	axis.assigned_manpower = int(data.get("assigned_manpower", 0))
	axis.assigned_equipment = data.get("assigned_equipment", {}).duplicate(true)
	axis.posture = int(data.get("posture", Posture.BALANCED)) as Posture
	axis.is_stalled = bool(data.get("is_stalled", false))
	axis.attrition_rate = float(data.get("attrition_rate", 0.02))
	axis.last_incident_turn = int(data.get("last_incident_turn", -999))

	var cmd_data = data.get("commander", {})
	if not cmd_data.is_empty():
		axis.commander = LeaderResource.from_dict(cmd_data)

	return axis
