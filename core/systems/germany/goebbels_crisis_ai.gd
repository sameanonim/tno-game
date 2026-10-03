class_name GoebbelsCrisisAI
extends Node

##
## GoebbelsCrisisAI: AI-контроллер неиграбельной угрозы (Босс-кризис Анархии GCW)
##
## Реализует логику Йозефа Геббельса и реваншистских гарнизонов Одера:
## 1. Принудительная мобилизация фольксштурма за ход без траты резервов.
## 2. Приоритетный выбор самых слабых смежных участков фронта для прорыва.
## 3. Тактика выжженной земли: on_sector_lost(region) полностью обнуляет IC и инфраструктуру.
## 4. Блокированная дипломатия и бескомпромиссная агрессия.
##

signal sector_scorched(province_id: int, province_name: String)
signal fanatic_offensive_launched(target_axis_id: String, combat_bonus: float)

const TAG_GOEBBELS = "GOB"

var turn_manager_ref: TurnManager = null
var map_controller_ref: MapController = null
var state_ref: CountryState = null

# Настройки фанатизма и волн фольксштурма
@export var volkssturm_per_turn: int = 15000
@export var synthesized_weapons_per_turn: int = 8000
@export var fanaticism_attack_bonus: float = 1.35
@export var scorched_earth_unrest: float = 85.0

var turns_active: int = 0


func setup(tm: TurnManager, mc: MapController, state: CountryState) -> void:
	turn_manager_ref = tm
	map_controller_ref = mc
	state_ref = state
	print("[GoebbelsCrisisAI] Revanchist Volkssturm AI online. Total War doctrine engaged.")


## Вызывается каждый ход из GermanCivilWarManager или TurnManager
func process_turn() -> void:
	turns_active += 1
	if state_ref == null or turn_manager_ref == null:
		return

	# 1. Принудительная мобилизация фанатиков без ограничений резервов
	_mobilize_fanatical_reinforcements()

	# 2. Анализ и нанесение удара по наиболее слабому вражескому сектору
	_execute_ai_offensive()


func _mobilize_fanatical_reinforcements() -> void:
	state_ref.manpower_pool += volkssturm_per_turn
	state_ref.infantry_weapons_stockpile += synthesized_weapons_per_turn
	state_ref.army_morale = 100.0 # Фанатичный дух не колеблется
	state_ref.army_readiness = clampf(state_ref.army_readiness + 2.0, 70.0, 95.0)

	print("[GoebbelsCrisisAI] Volkssturm wave mobilized: +%d fanatics, +%d weapons." % [volkssturm_per_turn, synthesized_weapons_per_turn])


func _execute_ai_offensive() -> void:
	var frontlines = MilitaryEngine.get_active_frontlines()
	var weakest_axis: OperationalAxis = null
	var lowest_defense: float = 999999.0

	for front in frontlines:
		if front.attacker_tag == TAG_GOEBBELS:
			for axis in front.axes:
				# Усиливаем силы на оси
				axis.assigned_manpower += int(volkssturm_per_turn * 0.7)
				axis.assigned_equipment["infantry_weapons"] = axis.assigned_equipment.get("infantry_weapons", 0) + int(synthesized_weapons_per_turn * 0.7)
				axis.posture = OperationalAxis.Posture.AGGRESSIVE_BREAKTHROUGH

				# Оценка обороны цели
				if not axis.target_region_ids.is_empty():
					var target_id = axis.target_region_ids[0]
					var target_reg: RegionData = turn_manager_ref.regions_world_state.get(target_id, null)
					var def_rating := 50.0
					if target_reg != null:
						def_rating = target_reg.garrison_strength + float(target_reg.civilian_infrastructure) * 5.0

					if def_rating < lowest_defense:
						lowest_defense = def_rating
						weakest_axis = axis

	# Направление яростного прорыва
	if weakest_axis != null:
		var turn_num: int = turn_manager_ref.current_turn if turn_manager_ref != null else 1
		var atk_seed: int = turn_num * 8831 + str(weakest_axis.axis_id).hash() + turns_active * 137
		var gain: float = _get_deterministic_factor(atk_seed, 8.0, 16.0)
		weakest_axis.progress = clampf(weakest_axis.progress + gain * fanaticism_attack_bonus, 0.0, 100.0)
		weakest_axis.is_stalled = false
		fanatic_offensive_launched.emit(weakest_axis.axis_id, fanaticism_attack_bonus)
		print("[GoebbelsCrisisAI] Launching suicidal fanatic spearhead along axis [%s]! Progress: %.1f%%" % [weakest_axis.name, weakest_axis.progress])


##
## Вызывается при потере сектора войсками Геббельса
## Реализует тактику тотальной выжженной земли (Scorched Earth Policy)
##
func on_sector_lost(region: RegionData) -> void:
	if region == null:
		return

	print("[GoebbelsCrisisAI] SCORCHED EARTH ORDER: Region #%d (%s) detonated by retreating fanatics!" % [region.province_id, region.province_name])

	# 1. Полное уничтожение промышленного потенциала (IC = 0)
	region.industrial_capacity = 0

	# 2. Полное уничтожение инфраструктуры (разрушены мосты, водопровод, ж/д узлы)
	region.civilian_infrastructure = 0

	# 3. Всплеск хаоса и пожаров
	region.unrest = clampf(scorched_earth_unrest, 0.0, 100.0)
	region.garrison_strength = 5.0

	# 4. Установка метки разрушенной провинции
	region.story_flags["scorched_earth"] = true
	region.story_flags["scorch_turn"] = turn_manager_ref.current_turn if turn_manager_ref != null else 0

	# 5. Обновление в Data-LUT карты
	if map_controller_ref != null:
		map_controller_ref.update_region_all_data(
			region.province_id,
			0.0, # IC = 0
			region.unrest / 100.0, # Unrest
			0.0, # Infra = 0
			0.50 # Sphere
		)
		map_controller_ref.add_combat_incident_ping(region.province_id, "scorched")

	sector_scorched.emit(region.province_id, region.province_name)


static func _get_deterministic_factor(seed_val: int, min_val: float, max_val: float) -> float:
	var x: int = (seed_val ^ 0x5DEECE66D) & 0xFFFFFFFF
	x = (x * 1103515245 + 12345) & 0x7FFFFFFF
	var t: float = float(x) / float(0x7FFFFFFF)
	return lerpf(min_val, max_val, t)
