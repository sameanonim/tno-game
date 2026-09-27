class_name LeaderResource
extends Resource

##
## LeaderResource: Модель государственного лидера, военачальника или министра TNO
##
## Отражает идеологический уклон, влияние в кабинете и персональные трейты.
##

@export var leader_id: String = "leader_mikhail_tukhachevsky"
@export var leader_name: String = "Mikhail Tukhachevsky"
@export var title: String = "Marshal of the Soviet Union"
@export var portrait_path: String = "res://icon.svg"

@export_group("Ideology & Alignment")
@export var ideology: String = "Authoritarian Socialism"
@export var faction_affiliation: String = "military"
@export_range(0.0, 100.0, 1.0) var popularity: float = 78.0
@export_range(0.0, 100.0, 1.0) var cabinet_influence: float = 85.0

@export_group("Role & Mechanics")
@export var role: String = "HEAD_OF_STATE" # HEAD_OF_STATE, PRIME_MINISTER, DEFENSE, ECONOMY, THEATER_COMMANDER
@export var is_head_of_state: bool = true
@export var is_military_commander: bool = true
@export_range(1, 5, 1) var competence: int = 3
@export_range(0.0, 100.0, 1.0) var loyalty: float = 75.0
@export var traits: Array = [
	"red_napoleon",
	"deep_battle_theorist",
	"uncompromising_stratocrat"
]

## Статистика командования (если является военачальником)
@export_range(1, 10, 1) var attack_skill: int = 6
@export_range(1, 10, 1) var defense_skill: int = 4
@export_range(1, 10, 1) var logistics_skill: int = 5

## Персональные модификаторы государства, применяемые при нахождении в кабинете
@export var passive_modifiers: Dictionary = {
	"army_readiness_gain": 0.05,
	"military_spending_cost": 0.08,
	"war_support": 0.10
}


func to_dict() -> Dictionary:
	return {
		"leader_id": leader_id,
		"leader_name": leader_name,
		"title": title,
		"portrait_path": portrait_path,
		"ideology": ideology,
		"faction_affiliation": faction_affiliation,
		"popularity": popularity,
		"cabinet_influence": cabinet_influence,
		"role": role,
		"competence": competence,
		"loyalty": loyalty,
		"is_head_of_state": is_head_of_state,
		"is_military_commander": is_military_commander,
		"traits": traits.duplicate(),
		"attack_skill": attack_skill,
		"defense_skill": defense_skill,
		"logistics_skill": logistics_skill,
		"passive_modifiers": passive_modifiers.duplicate(true)
	}


static func from_dict(data: Dictionary) -> LeaderResource:
	var res = LeaderResource.new()
	res.leader_id = data.get("leader_id", "")
	res.leader_name = data.get("leader_name", "Unknown Leader")
	res.title = data.get("title", "")
	res.portrait_path = data.get("portrait_path", "res://icon.svg")
	res.ideology = data.get("ideology", "Neutral")
	res.faction_affiliation = data.get("faction_affiliation", data.get("ideological_faction", "bureaucracy"))
	res.popularity = float(data.get("popularity", 50.0))
	res.cabinet_influence = float(data.get("cabinet_influence", 50.0))
	res.role = str(data.get("role", "HEAD_OF_STATE" if bool(data.get("is_head_of_state", false)) else "THEATER_COMMANDER"))
	res.competence = int(data.get("competence", 3))
	res.loyalty = float(data.get("loyalty", 75.0))
	res.is_head_of_state = bool(data.get("is_head_of_state", res.role == "HEAD_OF_STATE"))
	res.is_military_commander = bool(data.get("is_military_commander", res.role in ["THEATER_COMMANDER", "DEFENSE"]))
	res.traits = []
	for t in data.get("traits", []):
		res.traits.append(str(t))
	res.attack_skill = int(data.get("attack_skill", res.competence))
	res.defense_skill = int(data.get("defense_skill", res.competence))
	res.logistics_skill = int(data.get("logistics_skill", res.competence))
	res.passive_modifiers = data.get("passive_modifiers", {}).duplicate(true)
	return res

