class_name ResearchManager
extends Node

##
## ResearchManager: Главный управляющий модуль научно-технического прогресса (НИОКР / R&D)
##
## Обеспечивает:
## 1. Загрузку и валидацию древа технологий (TechResource) по 6 категориям.
## 2. Управление слотами исследований и пошаговый расчет прогресса.
## 3. Применение пассивных макроэкономических и военных модификаторов к державе.
## 4. Разведку и кражу технологий (Blueprints / Tech Theft).
##

signal research_started(tech_id: String, slot_index: int)
signal research_advanced(tech_id: String, current_progress: float, total_cost: float)
signal tech_researched(tech_id: String, tech: TechResource)
signal research_cancelled(tech_id: String)
signal research_boosted(tech_id: String, bonus_percent: float)

## Кэш всех зарегистрированных технологий: tech_id -> TechResource
var all_technologies: Dictionary = {}

## Категоризированный индекс: TechCategory (int) -> Array[TechResource]
var techs_by_category: Dictionary = {}


func _init() -> void:
	load_technologies()


func _ready() -> void:
	if all_technologies.is_empty():
		load_technologies()


## Загрузка технологий из JSON базы данных
func load_technologies(json_path: String = "res://data/technologies/technologies_master.json") -> void:
	all_technologies.clear()
	techs_by_category.clear()

	for cat_idx in range(6):
		techs_by_category[cat_idx] = []

	if not FileAccess.file_exists(json_path):
		_generate_default_technologies()
		return

	var file = FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		_generate_default_technologies()
		return

	var text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var err = json.parse(text)
	if err != OK or not (json.data is Array):
		_generate_default_technologies()
		return

	for item in json.data:
		if item is Dictionary:
			var tech = TechResource.from_dict(item)
			all_technologies[tech.tech_id] = tech
			var c_idx = int(tech.category)
			if techs_by_category.has(c_idx):
				techs_by_category[c_idx].append(tech)
			else:
				techs_by_category[c_idx] = [tech]

	print("[ResearchManager] Успешно загружено %d технологий по %d категориям." % [
		all_technologies.size(),
		techs_by_category.size()
	])


## Получить объект технологии по ID
func get_tech(tech_id: String) -> TechResource:
	return all_technologies.get(tech_id, null)


## Получить список технологий для выбранной категории (TechCategory 0..5)
func get_techs_by_category(category_int: int) -> Array[TechResource]:
	var res: Array[TechResource] = []
	if techs_by_category.has(category_int):
		for t in techs_by_category[category_int]:
			if t is TechResource:
				res.append(t)
	return res


## Проверка доступности технологии к исследованию
func can_research(state: CountryState, tech_id: String) -> Dictionary:
	if state == null:
		return {"allowed": false, "reason": "Ошибка стейта державы"}

	var tech = get_tech(tech_id)
	if tech == null:
		return {"allowed": false, "reason": "Технология не найдена в реестре"}

	if state.is_tech_researched(tech_id):
		return {"allowed": false, "reason": "Технология уже освоена"}

	if state.active_researches.has(tech_id):
		return {"allowed": false, "reason": "Проект уже находится в разработке"}

	if not state.has_available_research_slot():
		return {"allowed": false, "reason": "Все слоты НИОКР заняты (%d/%d)" % [
			state.active_researches.size(),
			state.get_total_research_slots()
		]}

	# Проверка предшествующих технологий
	for prereq in tech.prerequisite_techs:
		if not state.is_tech_researched(prereq):
			var pr_obj = get_tech(prereq)
			var pr_name = pr_obj.tech_name if pr_obj != null else prereq
			return {"allowed": false, "reason": "Требуется изучить: %s" % pr_name}

	var cost_mult := 1.0
	var blueprint_flag = "blueprint_" + tech_id
	if state.has_flag(blueprint_flag):
		var bp_val = float(state.story_flags.get(blueprint_flag, 35.0))
		cost_mult = maxf(1.0 - (bp_val / 100.0), 0.35)

	var final_cost = tech.research_cost * cost_mult

	return {
		"allowed": true,
		"reason": "Доступно для исследования",
		"cost_mult": cost_mult,
		"final_cost": final_cost
	}


## Старт исследования технологии в свободный слот
func start_research(state: CountryState, tech_id: String, requested_slot: int = -1) -> Dictionary:
	var check = can_research(state, tech_id)
	if not check.get("allowed", false):
		return {"success": false, "message": check.get("reason", "Заблокировано")}

	var tech = get_tech(tech_id)
	var max_slots = state.get_total_research_slots()

	# Определение свободного индекса слота
	var used_slots: Array[int] = []
	for active_id in state.active_researches.keys():
		var info = state.active_researches[active_id]
		used_slots.append(int(info.get("slot", 0)))

	var slot_to_assign = requested_slot
	if slot_to_assign < 0 or used_slots.has(slot_to_assign):
		slot_to_assign = -1
		for i in range(max_slots):
			if not used_slots.has(i):
				slot_to_assign = i
				break

	if slot_to_assign < 0:
		return {"success": false, "message": "Нет свободных слотов НИОКР"}

	# Проверка бонуса чертежей (от шпионажа / кражи технологий)
	var cost_mult := 1.0
	var blueprint_flag = "blueprint_" + tech_id
	if state.has_flag(blueprint_flag):
		var bp_val = float(state.story_flags.get(blueprint_flag, 35.0))
		cost_mult = maxf(1.0 - (bp_val / 100.0), 0.35)
		state.story_flags.erase(blueprint_flag)

	var final_cost = tech.research_cost * cost_mult

	state.active_researches[tech_id] = {
		"slot": slot_to_assign,
		"progress": 0.0,
		"cost": final_cost,
		"turns_remaining": maxi(int(ceil(final_cost / maxf(state.research_points_per_turn, 1.0))), 1)
	}

	research_started.emit(tech_id, slot_to_assign)
	return {
		"success": true,
		"message": "Проект «%s» запущен в работу (Слот #%d)" % [tech.tech_name, slot_to_assign + 1]
	}


## Отмена активного исследования
func cancel_research(state: CountryState, tech_id: String) -> bool:
	if state != null and state.active_researches.has(tech_id):
		state.active_researches.erase(tech_id)
		research_cancelled.emit(tech_id)
		return true
	return false


## Пошаговый расчет прогресса исследований (вызывается из TurnManager)
func process_turn(turn: int, state: CountryState) -> Array[Dictionary]:
	var completed_reports: Array[Dictionary] = []
	if state == null:
		return completed_reports

	# Если активных проектов нет — часть очков откладывается в научный резерв (до 100 очков)
	if state.active_researches.is_empty():
		state.research_points_pool = minf(
			state.research_points_pool + (state.research_points_per_turn * 0.40),
			120.0
		)
		return completed_reports

	var active_keys = state.active_researches.keys()
	var total_active = active_keys.size()

	# Распределение очков за ход поровну + 25% траты резерва
	var pool_boost = state.research_points_pool * 0.25
	state.research_points_pool = maxf(state.research_points_pool - pool_boost, 0.0)

	var total_available = state.research_points_per_turn + pool_boost
	var points_per_project = total_available / float(total_active)

	var to_complete: Array[String] = []

	for t_id in active_keys:
		var info: Dictionary = state.active_researches[t_id]
		var cur_prog = float(info.get("progress", 0.0)) + points_per_project
		var cost = float(info.get("cost", 100.0))

		info["progress"] = cur_prog
		var remaining = maxf(cost - cur_prog, 0.0)
		info["turns_remaining"] = maxi(int(ceil(remaining / maxf(points_per_project, 0.1))), 1)
		state.active_researches[t_id] = info

		research_advanced.emit(t_id, cur_prog, cost)

		if cur_prog >= cost:
			to_complete.append(t_id)

	# Завершение исследований
	for comp_id in to_complete:
		var tech = get_tech(comp_id)
		if tech != null:
			if not state.researched_techs.has(comp_id):
				state.researched_techs.append(comp_id)

			# Применение пассивных макро-бонусов
			state.apply_tech_modifiers(tech.state_modifiers)

			# Освобождение слота
			state.active_researches.erase(comp_id)

			var report = {
				"tech_id": comp_id,
				"tech_name": tech.tech_name,
				"category": tech.category,
				"modifiers": tech.state_modifiers,
				"summary": "РАЗРАБОТКА ЗАВЕРШЕНА: Технология «%s» принята на вооружение!" % tech.tech_name
			}
			completed_reports.append(report)
			tech_researched.emit(comp_id, tech)
			print("[ResearchManager] [ХОД %d] Изучена технология: %s" % [turn, tech.tech_name])

	return completed_reports


## Ускорение исследований (от шпионажа, кражи чертежей или директив)
func boost_research(state: CountryState, target_tech_id: String, bonus_percent: float) -> Dictionary:
	if state == null:
		return {"success": false, "message": "Стейт не задан"}

	var tech = get_tech(target_tech_id)
	var t_name = tech.tech_name if tech != null else target_tech_id

	# Если проект уже активен в лабораториях — начисляем прогресс напрямую
	if state.active_researches.has(target_tech_id):
		var info: Dictionary = state.active_researches[target_tech_id]
		var cost = float(info.get("cost", 100.0))
		var bonus_points = cost * (bonus_percent / 100.0)
		info["progress"] = float(info.get("progress", 0.0)) + bonus_points
		state.active_researches[target_tech_id] = info
		research_boosted.emit(target_tech_id, bonus_percent)

		# Если перевалило за 100% — мгновенное завершение
		if float(info["progress"]) >= cost:
			if not state.researched_techs.has(target_tech_id):
				state.researched_techs.append(target_tech_id)
			if tech != null:
				state.apply_tech_modifiers(tech.state_modifiers)
			state.active_researches.erase(target_tech_id)
			tech_researched.emit(target_tech_id, tech)
			return {
				"success": true,
				"completed": true,
				"message": "Чертежи позволили МГНОВЕННО завершить разработку темы «%s»!" % t_name
			}

		return {
			"success": true,
			"completed": false,
			"message": "Чертежи ускорили активный проект «%s» на +%0.1f%%!" % [t_name, bonus_percent]
		}
	else:
		# Если проект еще не начат — сохраняем чертеж как постоянный бонус к удешевлению темы
		var flag = "blueprint_" + target_tech_id
		state.set_flag(flag, bonus_percent)
		research_boosted.emit(target_tech_id, bonus_percent)
		return {
			"success": true,
			"completed": false,
			"message": "Захвачен комплект конструкторской документации по теме «%s» (-%0.1f%% к затратам)." % [t_name, bonus_percent]
		}


## Резервная генерация технологий при отсутствии JSON файла
func _generate_default_technologies() -> void:
	var def_techs = [
		{"id": "tech_industry_mechanization_1", "name": "Механизация Сборочных Линий", "cat": 0, "cost": 80.0, "pre": []},
		{"id": "tech_infantry_akm_pattern", "name": "Штампованные Автоматы АКМ", "cat": 1, "cost": 75.0, "pre": []},
		{"id": "tech_armor_first_gen_mbt", "name": "Основные Боевые Танки I Поколения", "cat": 2, "cost": 110.0, "pre": []},
		{"id": "tech_air_supersonic_fighters", "name": "Сверхзвуковые Перехватчики", "cat": 3, "cost": 130.0, "pre": []},
		{"id": "tech_nuke_heavy_water_reactor", "name": "Тяжеловодный Промышленный Реактор", "cat": 4, "cost": 180.0, "pre": []},
		{"id": "tech_doctrine_deep_battle", "name": "Теория Глубокой Наступательной Операции", "cat": 5, "cost": 90.0, "pre": []}
	]

	for dt in def_techs:
		var tr = TechResource.new()
		tr.tech_id = dt["id"]
		tr.tech_name = dt["name"]
		tr.category = dt["cat"]
		tr.research_cost = dt["cost"]
		tr.prerequisite_techs = dt["pre"]
		all_technologies[tr.tech_id] = tr
		techs_by_category[tr.category].append(tr)
