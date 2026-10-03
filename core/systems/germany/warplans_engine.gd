class_name WarPlansEngine
extends RefCounted

##
## WarPlansEngine: Подсистема «Планы Войны и Экономика Грабежа» Германа Гёринга
## Симулирует агрессивную внешнеполитическую спираль Вермахта под давлением
## милитаристов Шёрнера, захват золотых запасов Европы и риск ядерной эскалации.
##

signal war_plan_launched(plan_tier: String, target_tag: String)
signal conquest_plundered(target_tag: String, gold_amount: float)
signal militarist_tension_spiked(new_tension: float)
signal militarist_coup_warning()

static func get_plan_targets(plan_tier: String) -> Array[String]:
	match plan_tier:
		"A":
			return ["SWI", "DEN", "SWE", "OST", "SER"]
		"B":
			return ["IBR", "ITA", "ENG", "RUS", "TUR"]
		"C":
			return ["USA", "JAP", "BRG"]
		_:
			return ["SWI"]


static func process_turn_step(state: Resource, turn_seed: int) -> Dictionary:
	var result: Dictionary = {
		"tension_delta": 0.0,
		"plunder_drain": 0.0,
		"risk_of_coup": false,
		"log_message": ""
	}
	
	if state == null:
		return result
		
	var wpd: Dictionary = state.goering_warplans_data
	var tension: float = float(wpd.get("militarist_tension", 30.0))
	var completed: Array = wpd.get("completed_targets", [])
	
	# Если нет активной экспансии, напряжение генералов растет каждый ход (+2.5%)
	var delta: float = 2.5 + (float((turn_seed ^ 778899) % 20) / 10.0)
	tension = clampf(tension + delta, 0.0, 100.0)
	wpd["militarist_tension"] = tension
	result["tension_delta"] = delta
	
	if tension >= 80.0:
		result["risk_of_coup"] = true
		result["log_message"] = "ТРЕВОГА: Генералы Вермахта во главе с Шёрнером открыто саботируют приказы! Угроза военного переворота!"
	else:
		result["log_message"] = "ОКВ готовит эшелоны вторжения. Напряженность милитаристов: %0.1f%%." % tension
		
	return result


static func execute_campaign_victory(state: Resource, target_tag: String) -> Dictionary:
	var res: Dictionary = {"success": false, "gold_plundered": 0.0, "tension_relief": 0.0}
	if state == null:
		return res
		
	var wpd: Dictionary = state.goering_warplans_data
	var completed: Array = wpd.get("completed_targets", [])
	if not completed.has(target_tag):
		completed.append(target_tag)
		wpd["completed_targets"] = completed
		
		# Сброс напряжения милитаристов и пополнение казны
		var gold: float = 12.5
		if target_tag in ["SWI", "IBR", "ENG"]:
			gold = 35.0
		elif target_tag in ["USA", "JAP"]:
			gold = 80.0
			
		var relief: float = 35.0
		wpd["militarist_tension"] = maxf(5.0, float(wpd.get("militarist_tension", 30.0)) - relief)
		wpd["plundered_gold_billions"] = float(wpd.get("plundered_gold_billions", 0.0)) + gold
		
		res["success"] = true
		res["gold_plundered"] = gold
		res["tension_relief"] = relief
		
	return res
