class_name ZollvereinEngine
extends RefCounted

##
## ZollvereinEngine: Подсистема «Цолльферайн и Четвёрка реформаторов» Альберта Шпеера
## Моделирует переход от рабского труда к свободному рынку, интеграцию пакта
## и балансирование между авторитарным фашизмом Шпеера и демократизацией Viererbande.
##

signal regime_alignment_changed(meter_value: float, alignment_name: String)
signal zollverein_member_added(country_tag: String)
signal slave_emancipation_stepped(remaining_slaves_millions: float, gdp_bonus: float)
signal slave_revolt_erupted()

static func get_alignment_title(meter_val: float) -> String:
	if meter_val <= -50.0:
		return "Фашистский Триумф (Автократия Шпеера)"
	elif meter_val < 0.0:
		return "Консервативный Корпоративизм"
	elif meter_val < 50.0:
		return "Авторитарная Демократия (Технократы)"
	else:
		return "Победа Четвёрки (Конституционная Республика)"


static func process_turn_step(state: Resource, turn_seed: int) -> Dictionary:
	var result: Dictionary = {
		"meter_delta": 0.0,
		"gdp_growth_bonus": 0.002,
		"slave_liberation_delta": 0.0,
		"log_message": ""
	}
	
	if state == null:
		return result
		
	var zd: Dictionary = state.zollverein_data
	var go4: Dictionary = zd.get("gang_of_four_influence", {})
	var avg_go4: float = (
		float(go4.get("erhard", 50.0)) +
		float(go4.get("kiesinger", 50.0)) +
		float(go4.get("schmidt", 50.0)) +
		float(go4.get("tresckow", 50.0))
	) / 4.0
	
	var hardliners: float = float(zd.get("fascist_hardliners_pressure", 45.0))
	var drift: float = (avg_go4 - hardliners) * 0.05
	
	state.speer_regime_meter = clampf(state.speer_regime_meter + drift, -100.0, 100.0)
	result["meter_delta"] = drift
	
	# Постепенное освобождение рабов и рост производительности труда
	if state.slaves_count_millions > 1.0 and state.speer_regime_meter > -20.0:
		var freed: float = 0.08 + (float((turn_seed ^ 112233) % 50) / 1000.0)
		state.slaves_count_millions = maxf(0.5, state.slaves_count_millions - freed)
		state.slave_unrest = clampf(state.slave_unrest - 0.02, 0.05, 1.0)
		result["slave_liberation_delta"] = freed
		result["gdp_growth_bonus"] += 0.003
		
	# Проверка взрыва восстания рабов (Sklavenaufstand) при высоком недовольстве
	if state.slave_unrest > 0.80 and not state.slave_revolt_triggered:
		state.slave_revolt_triggered = true
		result["log_message"] = "ТРЕВОГА: Вспыхнуло общенациональное Восстание Рабов под руководством Вилли Брандта!"
	else:
		result["log_message"] = "Цолльферайн расширяет экономические связи. Вектор режима: %s." % get_alignment_title(state.speer_regime_meter)
		
	return result


static func empower_advisor(state: Resource, advisor_key: String, delta: float) -> void:
	if state == null:
		return
	var zd: Dictionary = state.zollverein_data
	var go4: Dictionary = zd.get("gang_of_four_influence", {})
	if go4.has(advisor_key):
		go4[advisor_key] = clampf(float(go4[advisor_key]) + delta, 0.0, 100.0)
		zd["gang_of_four_influence"] = go4
