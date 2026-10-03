class_name KartenhausEngine
extends RefCounted

##
## KartenhausEngine: Подсистема «Карточный Домик» Мартина Бормана
## Симулирует подковерную борьбу за контроль над гауляйтерами, партийными
## ячейками НСДАП и устранение оппозиционных фракций милитаристов и реформаторов.
##

signal kartenhaus_district_secured(district_id: String, success: bool)
signal faction_purged(faction_key: String, penalty_stability: float)
signal bormann_status_updated(control_percent: float, stability_delta: float)

const TOTAL_DISTRICTS: int = 24

static func process_turn_step(state: Resource, turn_seed: int) -> Dictionary:
	var result: Dictionary = {
		"control_drift": 0.0,
		"risk_of_dissent": false,
		"log_message": ""
	}
	
	if state == null:
		return result
		
	var kd: Dictionary = state.kartenhaus_data
	var bureau: float = float(kd.get("bureaucrats_control", 65.0))
	var mil: float = float(kd.get("militarists_control", 45.0))
	var ref: float = float(kd.get("reformers_control", 35.0))
	
	# Детерминированный дрейф лояльности
	var factor: float = float((turn_seed ^ 987654) % 100) / 100.0
	var drift: float = (factor - 0.48) * 2.0
	
	bureau = clampf(bureau + drift, 10.0, 100.0)
	mil = clampf(mil - (drift * 0.5), 0.0, 100.0)
	ref = clampf(ref - (drift * 0.5), 0.0, 100.0)
	
	kd["bureaucrats_control"] = bureau
	kd["militarists_control"] = mil
	kd["reformers_control"] = ref
	
	if mil > 65.0 or ref > 65.0:
		result["risk_of_dissent"] = true
		result["log_message"] = "Опасность заговора: оппозиционные фракции набирают опасный вес в аппарате партии."
	else:
		result["log_message"] = "Партийный контроль стабилен. Канцелярия держит руку на пульсе Рейха."
		
	result["control_drift"] = drift
	return result


static func secure_gauleiter(state: Resource, district_id: String, turn_seed: int) -> bool:
	if state == null:
		return false
	var kd: Dictionary = state.kartenhaus_data
	var secured: int = int(kd.get("districts_secured", 12))
	if secured >= TOTAL_DISTRICTS:
		return false
		
	# Детерминированная проверка успешности операции
	var roll: int = (turn_seed ^ 554433) % 100
	var chance: int = int(float(kd.get("bureaucrats_control", 60.0)))
	var success: bool = roll < chance
	
	if success:
		kd["districts_secured"] = mini(TOTAL_DISTRICTS, secured + 1)
		kd["bureaucrats_control"] = clampf(float(kd.get("bureaucrats_control", 60.0)) + 2.5, 0.0, 100.0)
	else:
		kd["bureaucrats_control"] = clampf(float(kd.get("bureaucrats_control", 60.0)) - 1.5, 0.0, 100.0)
		
	return success


static func purge_faction(state: Resource, faction_key: String) -> Dictionary:
	var res: Dictionary = {"success": false, "purged_name": faction_key, "stability_loss": 0.05}
	if state == null:
		return res
		
	var kd: Dictionary = state.kartenhaus_data
	var dismantled: Array = kd.get("dismantled_factions", [])
	if not dismantled.has(faction_key):
		dismantled.append(faction_key)
		kd["dismantled_factions"] = dismantled
		if faction_key == "militarists":
			kd["militarists_control"] = 15.0
			kd["bureaucrats_control"] = clampf(float(kd.get("bureaucrats_control", 60.0)) + 10.0, 0.0, 100.0)
		elif faction_key == "reformers":
			kd["reformers_control"] = 10.0
			kd["bureaucrats_control"] = clampf(float(kd.get("bureaucrats_control", 60.0)) + 10.0, 0.0, 100.0)
		res["success"] = true
	return res
