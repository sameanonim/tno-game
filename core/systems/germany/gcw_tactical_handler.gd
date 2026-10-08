class_name GCWTacticalHandler
extends RefCounted

##
## GCWTacticalHandler: Развертывание оперативных фронтов и исполнение тактических приказов GCW
## ==============================================================================
## Отвечает за:
## 1. Регистрацию стартовых фронтов и оперативных осей в MilitaryEngine при взрыве войны.
## 2. Исполнение тактических приказов главнокомандующего (танковый прорыв, оборона, авиаудар, диверсия СС).
## ==============================================================================

const BERLIN_PROVINCE_ID: int = 6521
const TAG_SPEER = "SPE"
const TAG_BORMANN = "BOR"
const TAG_GOERING = "GOR"
const TAG_HEYDRICH = "HEY"
const TAG_BERLIN_NEUTRAL = "SPN"


"""Регистрирует стартовые фронты 4 претендентов в MilitaryEngine.
"""
static func spawn_gcw_frontlines(map_controller_ref: MapController = null) -> void:
	MilitaryEngine.clear_frontlines()

	# 1. Фронт Шпеер -> Берлин (Ось Рур - Берлин)
	var front_speer = Frontline.new()
	front_speer.front_id = "front_gcw_speer_berlin"
	front_speer.name = "Рурско-Берлинский Оперативный Театр"
	front_speer.attacker_tag = TAG_SPEER
	front_speer.defender_tag = TAG_BERLIN_NEUTRAL

	var axis_speer = OperationalAxis.new()
	axis_speer.axis_id = "axis_ruhr_berlin"
	axis_speer.name = "Направление: Рур -> Ганновер -> Берлин"
	axis_speer.target_region_ids = [3271, BERLIN_PROVINCE_ID]
	axis_speer.assigned_manpower = 65000
	axis_speer.assigned_equipment = {"infantry_weapons": 30000, "heavy_equipment": 450}
	axis_speer.posture = OperationalAxis.Posture.BALANCED
	front_speer.add_axis(axis_speer)
	MilitaryEngine.register_frontline(front_speer)

	# 2. Фронт Борман -> Берлин (Ось Бавария - Лейпциг - Берлин)
	var front_bormann = Frontline.new()
	front_bormann.front_id = "front_gcw_bormann_berlin"
	front_bormann.name = "Южногерманский Театр (Партийный Вал)"
	front_bormann.attacker_tag = TAG_BORMANN
	front_bormann.defender_tag = TAG_BERLIN_NEUTRAL

	var axis_bormann = OperationalAxis.new()
	axis_bormann.axis_id = "axis_bavaria_berlin"
	axis_bormann.name = "Направление: Мюнхен -> Франкен -> Берлин"
	axis_bormann.target_region_ids = [3299, BERLIN_PROVINCE_ID]
	axis_bormann.assigned_manpower = 85000
	axis_bormann.assigned_equipment = {"infantry_weapons": 42000, "heavy_equipment": 380}
	axis_bormann.posture = OperationalAxis.Posture.AGGRESSIVE_BREAKTHROUGH
	front_bormann.add_axis(axis_bormann)
	MilitaryEngine.register_frontline(front_bormann)

	# 3. Фронт Геринг -> Берлин (Ось Пруссия - Померания - Берлин)
	var front_goering = Frontline.new()
	front_goering.front_id = "front_gcw_goering_berlin"
	front_goering.name = "Северо-Восточный Театр Люфтваффе"
	front_goering.attacker_tag = TAG_GOERING
	front_goering.defender_tag = TAG_BERLIN_NEUTRAL

	var axis_goering = OperationalAxis.new()
	axis_goering.axis_id = "axis_prussia_berlin"
	axis_goering.name = "Направление: Кёнигсберг -> Штеттин -> Берлин"
	axis_goering.target_region_ids = [6309, BERLIN_PROVINCE_ID]
	axis_goering.assigned_manpower = 95000
	axis_goering.assigned_equipment = {"infantry_weapons": 48000, "heavy_equipment": 600}
	axis_goering.posture = OperationalAxis.Posture.AGGRESSIVE_BREAKTHROUGH
	front_goering.add_axis(axis_goering)
	MilitaryEngine.register_frontline(front_goering)

	# 4. Фронт Гейдрих -> Франкфурт (Ось Эльзас - Бавария)
	var front_heydrich = Frontline.new()
	front_heydrich.front_id = "front_gcw_heydrich_central"
	front_heydrich.name = "Рейнский Театр СС-Орденштадта"
	front_heydrich.attacker_tag = TAG_HEYDRICH
	front_heydrich.defender_tag = TAG_BORMANN

	var axis_heydrich = OperationalAxis.new()
	axis_heydrich.axis_id = "axis_alsace_frankfurt"
	axis_heydrich.name = "Направление: Штутгарт -> Франкфурт"
	axis_heydrich.target_region_ids = [3679, 707]
	axis_heydrich.assigned_manpower = 45000
	axis_heydrich.assigned_equipment = {"infantry_weapons": 25000, "heavy_equipment": 280}
	axis_heydrich.posture = OperationalAxis.Posture.AGGRESSIVE_BREAKTHROUGH
	front_heydrich.add_axis(axis_heydrich)
	MilitaryEngine.register_frontline(front_heydrich)

	if map_controller_ref != null:
		map_controller_ref.refresh_tactical_frontlines()


"""Исполнение тактического приказа главнокомандующего (требует 1 CAP).
"""
static func execute_tactical_order(manager: GermanCivilWarManager, order_type: String, target_axis_id: String = "") -> Dictionary:
	var result = {"success": false, "order_type": order_type, "message": ""}
	var player_state: CountryState = manager.player_state_ref
	if player_state == null or player_state.current_cap < 1:
		result["message"] = "Отказ: Недостаточно очков кабинета (требуется 1 CAP)!"
		return result

	var axis: OperationalAxis = null
	for front in MilitaryEngine.get_active_frontlines():
		for ax in front.axes:
			if ax.axis_id == target_axis_id or target_axis_id.is_empty():
				axis = ax
				break
		if axis != null:
			break

	player_state.current_cap -= 1

	match order_type:
		"panzer_breakthrough":
			if player_state.heavy_equipment_stockpile >= 100:
				player_state.heavy_equipment_stockpile -= 100
				if axis != null:
					axis.progress = clampf(axis.progress + 15.0, 0.0, 100.0)
					axis.posture = OperationalAxis.Posture.AGGRESSIVE_BREAKTHROUGH
				result["success"] = true
				result["message"] = "ПРИКАЗ ИСПОЛНЕН: Танковые клинья взломали оборону (+15% прогресс, -100 танков)."
			else:
				result["message"] = "Срыв атаки: нехватка тяжелой бронетехники на складах!"

		"entrenched_defense":
			if axis != null:
				axis.posture = OperationalAxis.Posture.DEFENSIVE
			player_state.army_readiness = clampf(player_state.army_readiness + 5.0, 0.0, 100.0)
			result["success"] = true
			result["message"] = "ПРИКАЗ ИСПОЛНЕН: Войска окопались на рубежах. Боеготовность +5%, потери снижены."

		"luftwaffe_strike":
			if player_state.liquid_reserves_billions >= 0.15:
				player_state.liquid_reserves_billions -= 0.15
				if axis != null:
					axis.progress = clampf(axis.progress + 10.0, 0.0, 100.0)
					axis.is_stalled = false
				result["success"] = true
				result["message"] = "ПРИКАЗ ИСПОЛНЕН: Штуки и бомбардировщики смели укрепления врага (-$0.15B, +10% прогресс)."
			else:
				result["message"] = "Отказ: Казна истощена для закупки авиатоплива!"

		"ss_sabotage":
			if player_state.political_capital >= 15.0:
				player_state.political_capital -= 15.0
				if axis != null:
					axis.is_stalled = true
				result["success"] = true
				result["message"] = "ПРИКАЗ ИСПОЛНЕН: Спецгруппы подорвали мосты и эшелоны врага. Наступление врага сорвано."
			else:
				result["message"] = "Отказ: Недостаточно политического капитала для санкционирования спецоперации!"

	manager.tactical_order_resolved.emit(order_type, result)
	return result
