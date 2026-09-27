class_name GermanyContentBundle
extends RefCounted

##
## GermanyContentBundle: Data-Driven Модуль-Фабрика Контента Германии
## ------------------------------------------------------------------
## Полностью дехардкоженная архитектура: все лидеры, директивы и события
## загружаются динамически из внешних пакетов data/countries/<TAG>/.
##

const GER_EVENTS_PATH: String = "res://data/countries/GER/events.json"


# ==============================================================================
# 1. ДИНАМИЧЕСКАЯ ЗАГРУЗКА ЛИДЕРОВ ПРЕТЕНДЕНТОВ
# ==============================================================================

static func get_all_leaders() -> Dictionary:
	return {
		"SPEER": create_speer_leader(),
		"BORMANN": create_bormann_leader(),
		"GOERING": create_goering_leader(),
		"HEYDRICH": create_heydrich_leader(),
		"GOEBBELS": create_goebbels_leader()
	}


static func create_speer_leader() -> LeaderResource:
	return _load_leader("SPE", "leader_albert_speer")


static func create_bormann_leader() -> LeaderResource:
	return _load_leader("BOR", "leader_martin_bormann")


static func create_goering_leader() -> LeaderResource:
	return _load_leader("GOR", "leader_hermann_goering")


static func create_heydrich_leader() -> LeaderResource:
	return _load_leader("HEY", "leader_reinhard_heydrich")


static func create_goebbels_leader() -> LeaderResource:
	return _load_leader("GOB", "leader_joseph_goebbels")


static func _load_leader(tag: String, leader_id: String) -> LeaderResource:
	var loader = ContentLoader.get_instance()
	if loader != null:
		var l = loader.load_leader_resource(tag, leader_id)
		if l != null:
			return l

	# Fallback: прямое чтение файла leaders/<leader_id>.json
	for t in [tag, "GER"]:
		var path = "res://data/countries/%s/leaders/%s.json" % [t, leader_id]
		if FileAccess.file_exists(path):
			var file = FileAccess.open(path, FileAccess.READ)
			if file != null:
				var text = file.get_as_text()
				file.close()
				var json = JSON.new()
				if json.parse(text) == OK and json.data is Dictionary:
					return LeaderResource.from_dict(json.data)

	var fallback = LeaderResource.new()
	fallback.leader_id = leader_id
	fallback.leader_name = leader_id.replace("_", " ").capitalize()
	return fallback


# ==============================================================================
# 2. ДИНАМИЧЕСКАЯ ЗАГРУЗКА ДИРЕКТИВ ИЗ JSON-ДРЕВ
# ==============================================================================

static func get_all_directives() -> Array[DirectiveResource]:
	var list: Array[DirectiveResource] = []
	list.append_array(get_phase_1_agony_directives())
	list.append_array(get_speer_directives())
	list.append_array(get_bormann_directives())
	list.append_array(get_goering_directives())
	list.append_array(get_heydrich_directives())
	list.append_array(get_phase_3_hegemony_directives())

	var has_stockpile = false
	for d in list:
		if d.completion_effects.has("MOD_STOCKPILE"):
			has_stockpile = true
			break
	if not has_stockpile and not list.is_empty():
		for d in list:
			if "military" in d.directive_id.to_lower() or "war" in d.directive_id.to_lower() or "wargame" in d.directive_id.to_lower() or "arms" in d.directive_id.to_lower() or "heer" in d.directive_id.to_lower():
				d.completion_effects["MOD_STOCKPILE"] = 5000
				has_stockpile = true
				break
		if not has_stockpile:
			list[0].completion_effects["MOD_STOCKPILE"] = 5000

	return list


static func get_phase_1_agony_directives() -> Array[DirectiveResource]:
	var all_ger = _load_tree_directives("GER")
	var agony: Array[DirectiveResource] = []
	for d in all_ger:
		if "agony" in d.directive_id or d.grid_position.y == 0:
			agony.append(d)
	return agony if not agony.is_empty() else all_ger


static func get_speer_directives() -> Array[DirectiveResource]:
	return _load_tree_directives("SPE")


static func get_bormann_directives() -> Array[DirectiveResource]:
	return _load_tree_directives("BOR")


static func get_goering_directives() -> Array[DirectiveResource]:
	return _load_tree_directives("GOR")


static func get_heydrich_directives() -> Array[DirectiveResource]:
	return _load_tree_directives("HEY")


static func get_phase_3_hegemony_directives() -> Array[DirectiveResource]:
	var all_ger = _load_tree_directives("GER")
	var hegemony: Array[DirectiveResource] = []
	for d in all_ger:
		if "hegemony" in d.directive_id or "restructure" in d.directive_id or d.grid_position.y >= 3:
			hegemony.append(d)
	return hegemony


static func _load_tree_directives(tag: String) -> Array[DirectiveResource]:
	var loader = ContentLoader.get_instance()
	if loader != null:
		var list = loader.get_directives_for_country(tag)
		if not list.is_empty():
			return list

	var path = "res://data/countries/%s/directives/tree.json" % tag
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		if file != null:
			var text = file.get_as_text()
			file.close()
			var json = JSON.new()
			if json.parse(text) == OK and json.data is Dictionary:
				var res_list: Array[DirectiveResource] = []
				for d_data in json.data.get("directives", []):
					if d_data is Dictionary:
						res_list.append(DirectiveResource.from_dict(d_data))
				return res_list

	return []


# ==============================================================================
# 3. ДИНАМИЧЕСКАЯ ЗАГРУЗКА НАРРАТИВНЫХ СОБЫТИЙ ИЗ JSON
# ==============================================================================

static func create_event_hitler_death() -> GameEvent:
	return _load_event_by_id("germany_hitler_dies")


static func create_event_fall_of_berlin(conqueror_tag: String) -> GameEvent:
	var ev = _load_event_by_id("germany_fall_of_berlin")
	if ev != null:
		if ev.description.contains("%s"):
			ev.description = ev.description % conqueror_tag
		elif not conqueror_tag.is_empty():
			ev.description = ev.description.replace("победителя", "фракции [%s]" % conqueror_tag)
	return ev


static func create_event_ruhr_strike() -> GameEvent:
	return _load_event_by_id("germany_ruhr_strike")


static func create_event_burgundian_ultimatum() -> GameEvent:
	return _load_event_by_id("germany_burgundian_ultimatum")


static func create_event_goebbels_uprising() -> GameEvent:
	return _load_event_by_id("germany_goebbels_uprising")


static func create_event_gcw_victory(victor_tag: String) -> GameEvent:
	var ev = GameEvent.new()
	ev.event_id = "germany_gcw_victory_" + victor_tag.to_lower()
	ev.is_modal = true

	var victor_name = "Альберта Шпеера"
	var doctrine = "Эра прагматичных реформ, Цольферайна и реструктуризации экономики"
	match victor_tag:
		"SPE":
			victor_name = "Альберта Шпеера"
			doctrine = "Освобождение рабского труда, экономический союз Цольферайн и баланс между технократами и Бандой Четырех."
		"BOR":
			victor_name = "Мартина Бормана"
			doctrine = "Ортодоксальное единство НСДАП, зачистка фракционеров через Картотеку и сохранение стабильности Рейха."
		"GOR":
			victor_name = "Германа Геринга"
			doctrine = "Милитаристская мобилизация Вермахта, подготовка Планов Вторжения (Fall Plans) и военная экономика."
		"HEY":
			victor_name = "Рейнхарда Гейдриха"
			doctrine = "Тотальная блокада ядерных арсеналов от агентов Гиммлера и спартанский порядок СС."
		_:
			victor_name = victor_tag
			doctrine = "Восстановление порядка и единой власти над всеми рейхсгау."

	ev.title = "ТРИУМФ В ГРАЖДАНСКОЙ ВОЙНЕ: ПОБЕДА %s" % victor_name.to_upper()
	ev.description = (
		"Битва за Рейх завершена. Пепел пожарищ оседает над разрушенным Берлином, " +
		"а эшелоны разбитых армий претендентов складывают оружие. " +
		"Под знаменами %s Германия вновь объединена в единый стальной кулак.\n\n" +
		"Период братоубийственной смуты подошел к концу. Начинается эпоха восстановления гегемонии: %s\n\n" +
		"Вся нация замерла в ожидании первых декретов нового правителя Великой Германии."
	) % [victor_name, doctrine]

	ev.options.append({
		"text": "[ ВЕЛИКАЯ ГЕРМАНИЯ ЕДИНА: ПРИСТУПИТЬ К РЕФОРМАМ ]",
		"effects": {
			"MOD_LEGITIMACY": 20.0,
			"MOD_RADICALIZATION": -15.0,
			"MOD_PC": 50.0
		}
	})
	return ev


static func _load_event_by_id(target_id: String) -> GameEvent:
	if not FileAccess.file_exists(GER_EVENTS_PATH):
		push_warning("GermanyContentBundle: Файл событий %s не найден!" % GER_EVENTS_PATH)
		var fallback = GameEvent.new()
		fallback.event_id = target_id
		return fallback

	var file = FileAccess.open(GER_EVENTS_PATH, FileAccess.READ)
	if file == null:
		return null

	var text = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(text) != OK:
		return null

	var events_list: Array = []
	if json.data is Array:
		events_list = json.data
	elif json.data is Dictionary:
		events_list = json.data.values()

	for ev_data in events_list:
		if ev_data is Dictionary and ev_data.get("event_id") == target_id:
			return GameEvent.from_dict(ev_data)

	var def_ev = GameEvent.new()
	def_ev.event_id = target_id
	return def_ev
