class_name ContentLoader
extends Node

##
## ContentLoader: Синглтон динамической загрузки и кэширования контента TNO
##
## Десериализует изолированные модульные пакеты стран (res://data/countries/<TAG>/)
## и монолитные JSON-манифесты, созданные Python-пайплайном. Генерирует
## типизированные ресурсы CountryState, LeaderResource и DirectiveResource,
## а также регистрирует локализацию страны в реальном времени.
##

signal content_loaded(total_countries: int, total_trees: int)
signal country_package_loaded(tag: String, state: CountryState)

const COUNTRIES_BASE_DIR = "res://data/countries"
const COUNTRIES_INDEX_PATH = "res://data/countries/index.json"
const LEGACY_MANIFEST_PATH = "res://data/extracted/countries_manifest.json"
const LEGACY_TREES_PATH = "res://data/extracted/directives_trees.json"

static var instance: ContentLoader = null

var is_ready: bool = false
var manifest_data: Dictionary = {}
var directives_data: Dictionary = {}
var index_data: Array[Dictionary] = []

# In-memory caches
var _cached_country_states: Dictionary = {} # tag -> CountryState
var _cached_leaders: Dictionary = {}        # tag -> Array[LeaderResource]
var _cached_directives: Dictionary = {}     # tag -> Array[DirectiveResource]
var _cached_events: Dictionary = {}         # tag -> Array[GameEvent]
var _cached_dossiers: Dictionary = {}       # tag -> Dictionary
var _cached_decisions: Dictionary = {}      # tag -> Array[Dictionary]
var _master_decisions_cache: Array[Dictionary] = []


func _init() -> void:
	if instance == null:
		instance = self


func _ready() -> void:
	load_all()


static func get_instance() -> ContentLoader:
	return instance


func load_all() -> bool:
	_load_index_manifest()
	manifest_data = _read_json_file(LEGACY_MANIFEST_PATH)
	directives_data = _read_json_file(LEGACY_TREES_PATH)

	var countries = manifest_data.get("countries", {})
	var trees = directives_data.get("trees_by_tag", {})

	if not index_data.is_empty():
		is_ready = true
		_build_dossiers_cache()
		print("[ContentLoader] Successfully initialized modular index: %d packages available." % index_data.size())
		content_loaded.emit(index_data.size(), trees.size())
		return true
	elif not countries.is_empty():
		is_ready = true
		_build_dossiers_cache()
		print("[ContentLoader] Initialized from legacy manifest: %d countries, %d trees." % [countries.size(), trees.size()])
		content_loaded.emit(countries.size(), trees.size())
		return true
	else:
		print("[ContentLoader] Notice: Neither index.json nor legacy manifest found. Using defaults.")
		is_ready = false
		return false


func has_extracted_data() -> bool:
	return is_ready and (not index_data.is_empty() or not manifest_data.get("countries", {}).is_empty())


# ==============================================================================
# МОДУЛЬНЫЕ СТРАНОВЫЕ ПАКЕТЫ (COUNTRY PACKAGES API)
# ==============================================================================

##
## Загружает изолированный пакет страны:
## 1. country.json -> объект CountryState
## 2. leaders/*.json -> массив LeaderResource
## 3. directives/tree.json -> массив DirectiveResource
## 4. localisation/ru.json и en.json -> регистрация в LocalizationManager
##
func load_country_package(country_tag: String) -> CountryState:
	var tag = country_tag.to_upper().strip_edges()

	# Возврат из кэша, если уже загружен
	if _cached_country_states.has(tag):
		return _cached_country_states[tag]

	var pkg_dir = COUNTRIES_BASE_DIR.path_join(tag)
	var country_json_path = pkg_dir.path_join("country.json")
	var profile_json_path = pkg_dir.path_join("country_profile.json")

	var target_json_path = ""
	if FileAccess.file_exists(country_json_path):
		target_json_path = country_json_path
	elif FileAccess.file_exists(profile_json_path):
		target_json_path = profile_json_path
	else:
		print("[ContentLoader] Package not found at %s. Attempting CountryDataImporter fallback." % country_json_path)
		var imp_state = CountryDataImporter.load_country(tag)
		if imp_state != null and not imp_state.country_name.is_empty():
			_cached_country_states[tag] = imp_state
			return imp_state
		return _fallback_create_country_state(tag)

	# 1. Загрузка профиля страны (country.json / country_profile.json)
	var country_dict = _read_json_file(target_json_path)
	var state = CountryState.from_dict(country_dict)
	state.country_tag = tag

	# 2. Загрузка лидеров кабинета (leaders/*.json)
	var leaders_dir = pkg_dir.path_join("leaders")
	var loaded_leaders = _load_package_leaders(tag, leaders_dir)
	_cached_leaders[tag] = loaded_leaders

	# Если лидер не назначен в state, назначаем главу государства из кабинета
	if state.leader_name.is_empty() and not loaded_leaders.is_empty():
		for l in loaded_leaders:
			if l.is_head_of_state:
				state.leader_name = l.leader_name
				state.leader_portrait_path = l.portrait_path
				state.head_of_state = l
				break

	# Синхронизация cabinet_members и military_commanders если они не были в JSON
	if state.cabinet_members.is_empty():
		for l in loaded_leaders:
			if not l.is_head_of_state and not l.is_military_commander:
				state.cabinet_members.append(l)

	if state.military_commanders.is_empty():
		for l in loaded_leaders:
			if l.is_military_commander:
				state.military_commanders.append(l)

	# 3. Загрузка дерева национальных директив (directives/tree.json)
	var tree_json_path = pkg_dir.path_join("directives").path_join("tree.json")
	var loaded_directives = _load_package_directives(tag, tree_json_path)
	_cached_directives[tag] = loaded_directives

	# 4. Регистрация изолированной локализации (localisation/ru.json, en.json)
	_register_package_localization(tag, pkg_dir.path_join("localisation"))

	# 5. Загрузка нарративных событий (events.json)
	var events_json_path = pkg_dir.path_join("events.json")
	var loaded_events = _load_package_events(tag, events_json_path)
	_cached_events[tag] = loaded_events

	# Сохраняем в кэш
	_cached_country_states[tag] = state
	print("[ContentLoader] Loaded modular package [%s]: %d leaders, %d directives, %d events." % [
		tag, loaded_leaders.size(), loaded_directives.size(), loaded_events.size()
	])

	country_package_loaded.emit(tag, state)
	return state


##
## Динамическая загрузка состояния страны по ее тегу (Data-Driven API)
##
func load_country_by_tag(tag: String) -> CountryState:
	return load_country_package(tag)


##
## Загружает конкретный ресурс лидера (LeaderResource) для указанной страны (Data-Driven API)
##
func load_leader_resource(tag: String, leader_id: String) -> LeaderResource:
	var clean_tag = tag.to_upper().strip_edges()
	var clean_id = leader_id.strip_edges()

	# 1. Поиск в кэше лидеров страны, если страна уже загружена
	if _cached_leaders.has(clean_tag):
		var leaders: Array[LeaderResource] = _cached_leaders[clean_tag]
		for l in leaders:
			if l != null and l.leader_id == clean_id:
				return l

	# 2. Прямая загрузка из JSON-файла пакета
	var leader_file = COUNTRIES_BASE_DIR.path_join(clean_tag).path_join("leaders").path_join("%s.json" % clean_id)
	if FileAccess.file_exists(leader_file):
		var l_dict = _read_json_file(leader_file)
		if not l_dict.is_empty():
			return LeaderResource.from_dict(l_dict)

	# 3. Fallback: поиск в родительских пакетах (например GER для фракций GCW)
	for fallback_tag in ["GER", "WRS", "SOV"]:
		if fallback_tag != clean_tag:
			var fb_file = COUNTRIES_BASE_DIR.path_join(fallback_tag).path_join("leaders").path_join("%s.json" % clean_id)
			if FileAccess.file_exists(fb_file):
				var fb_dict = _read_json_file(fb_file)
				if not fb_dict.is_empty():
					return LeaderResource.from_dict(fb_dict)

	# 4. Fallback: поиск среди cabinet_members или military_commanders загруженного профиля
	if _cached_country_states.has(clean_tag):
		var st = _cached_country_states[clean_tag]
		if st.head_of_state != null and st.head_of_state.leader_id == clean_id:
			return st.head_of_state
		for m in st.cabinet_members:
			if m != null and m.leader_id == clean_id:
				return m
		for c in st.military_commanders:
			if c != null and c.leader_id == clean_id:
				return c

	return null


##
## Возвращает список всех зарегистрированных стран из data/countries/index.json (Data-Driven API)
##
func get_available_countries_list() -> Array[Dictionary]:
	return get_available_countries_manifest()


##
## Быстрое чтение списка доступных стран из data/countries/index.json для главного меню
##
func get_available_countries_manifest() -> Array[Dictionary]:
	if not index_data.is_empty():
		return index_data

	_load_index_manifest()
	if not index_data.is_empty():
		return index_data

	# Fallback на генерацию из legacy manifest
	var result: Array[Dictionary] = []
	var countries = manifest_data.get("countries", {})
	for tag in countries:
		var c = countries[tag]
		var lead = c.get("primary_leader", {})
		result.append({
			"tag": tag,
			"name": c.get("name", tag),
			"name_ru": c.get("name", tag),
			"theater": c.get("theater", "theater_smuta"),
			"ruling_ideology": c.get("ruling_ideology", "Neutral"),
			"sub_ideology": c.get("sub_ideology", ""),
			"primary_leader_name": lead.get("leader_name", "Unknown"),
			"primary_leader_portrait": lead.get("portrait_path", "res://icon.svg"),
			"country_file": COUNTRIES_BASE_DIR.path_join(tag).path_join("country.json"),
			"is_selectable": true,
			"difficulty_rating": c.get("difficulty_rating", "●●●○○ (СРЕДНЯЯ)"),
			"starting_gdp": float(c.get("starting_gdp", 15.0)),
			"starting_factories": int(c.get("starting_factories", 25))
		})

	index_data = result
	return index_data


# ==============================================================================
# ПУБЛИЧНЫЙ API: ТЕАТРЫ И СТРАНЫ
# ==============================================================================

func get_theaters() -> Array[Dictionary]:
	var focus_tags = get_tags_with_focus_trees()

	var result: Array[Dictionary] = [
		{
			"id": "theater_superpowers",
			"name": "СВЕРХДЕРЖАВЫ ХОЛОДНОЙ ВОЙНЫ",
			"name_en": "COLD WAR SUPERPOWERS",
			"description": "Глобальное геополитическое противостояние трех ядерных блоков: Вашингтон (ОФН), Берлин (Пакт Единства) и Токио (Сфера Сопроцветания).",
			"tags": ["USA", "GER", "JAP"]
		},
		{
			"id": "theater_smuta",
			"name": "РУССКАЯ СМУТА // ЭПОХА ВАРЛОРДОВ",
			"name_en": "RUSSIAN ANARCHY // WARLORDS",
			"description": "Осколки павшего Союза ведут бескомпромиссную борьбу за воссоединение Родины среди руин и немецких бомбардировок.",
			"tags": ["WRS", "KOM", "VYT", "SAM", "PRM", "TYU", "SVR", "OMS", "TOM", "NOV", "KEM", "SBA", "IRK", "BRY", "CHT", "MAG", "AMR"]
		},
		{
			"id": "theater_gcw",
			"name": "ПРЕТЕНДЕНТЫ РЕЙХА // КРИЗИС",
			"name_en": "GERMAN CIVIL WAR CONTENDERS",
			"description": "Агония фюрера поджигает гражданскую войну между четырьмя фракциями нацистской элиты: Шпеер, Борман, Геринг и Гейдрих.",
			"tags": ["SPE", "BOR", "GOR", "HEY"]
		},
		{
			"id": "theater_europe",
			"name": "ЕВРОПА И ТРИУМВИРАТ",
			"name_en": "EUROPE & THE TRIUMVIRATE",
			"description": "Средиземноморский союз Италии и Иберии, расколотая Британия и зловещая тайна Бургундии Генриха Гиммлера.",
			"tags": ["ITA", "IBR", "ENG", "BRG", "FRD", "TUR", "SCO", "WAL", "IRE"]
		},
		{
			"id": "theater_sphere",
			"name": "СФЕРА СОПРОЦВЕТАНИЯ И АЗИЯ",
			"name_en": "CO-PROSPERITY SPHERE & ASIA",
			"description": "Киберпанк-эксперимент мегакорпораций Гуандуна, японское ярмо Маньчжоу-Го и национальное возрождение Китая.",
			"tags": ["GNG", "MAN", "CHI", "THA", "YUN"]
		},
		{
			"id": "theater_focus_trees",
			"name": "★ ВСЕ СТРАНЫ С ФОКУСАМИ",
			"name_en": "★ ALL NATIONS WITH FOCUS TREES",
			"description": "Полный каталог всех государств мира, обладающих уникальными древами национальных директив TNO.",
			"tags": focus_tags
		}
	]
	return result



func get_playable_countries(theater_id: String = "") -> Array[Dictionary]:
	var manifest = get_available_countries_manifest()
	var result: Array[Dictionary] = []
	for c in manifest:
		if theater_id.is_empty() or c.get("theater", "") == theater_id:
			result.append(c)
	return result


func get_country_dossier(tag: String) -> Dictionary:
	if _cached_dossiers.has(tag):
		return _cached_dossiers[tag]

	# 1. Попытка чтения из country.json
	var country_json_path = COUNTRIES_BASE_DIR.path_join(tag).path_join("country.json")
	if FileAccess.file_exists(country_json_path):
		var c = _read_json_file(country_json_path)
		var ident = c.get("identity", {})
		var _pol = c.get("politics", {})
		var econ = c.get("economy", {})
		var mil = c.get("military", {})

		var col_arr = ident.get("country_color", [0.75, 0.25, 0.25, 1.0])
		var color = Color(0.75, 0.25, 0.25)
		if col_arr is Array and col_arr.size() >= 3:
			color = Color(col_arr[0], col_arr[1], col_arr[2])

		# Извлечение черт (traits) лидера
		var traits_list: Array = []
		var manifest_c = manifest_data.get("countries", {}).get(tag, {})
		var manifest_lead = manifest_c.get("primary_leader", {})
		if manifest_lead.has("traits") and manifest_lead["traits"] is Array and not manifest_lead["traits"].is_empty():
			traits_list = manifest_lead["traits"]
		elif ident.has("traits") and ident["traits"] is Array:
			traits_list = ident["traits"]

		# Извлечение лора (Lore)
		var lore_text = str(ident.get("lore", ""))
		if lore_text.is_empty():
			lore_text = str(c.get("narrative", {}).get("lore", ""))
		if lore_text.is_empty():
			lore_text = str(manifest_c.get("lore", manifest_lead.get("lore", "")))
		if lore_text.is_empty():
			var loc_mgr = get_node_or_null("/root/LocalizationManager")
			if loc_mgr != null:
				var l_val = loc_mgr.tr_key(tag + "_lore", "")
				if not l_val.is_empty() and not l_val.begins_with("[MISSING"):
					lore_text = l_val
				else:
					var tno_val = loc_mgr.tr_key(tag + "_THENEWORDER_DESC", "")
					if not tno_val.is_empty() and not tno_val.begins_with("[MISSING"):
						lore_text = tno_val

		var portrait_p = ident.get("leader_portrait_path", "res://icon.svg")
		if (portrait_p.is_empty() or portrait_p == "res://icon.svg") and manifest_lead.has("portrait_path"):
			var mp = str(manifest_lead["portrait_path"])
			if not mp.is_empty() and FileAccess.file_exists(mp):
				portrait_p = mp

		var dossier = {
			"tag": tag,
			"name": ident.get("country_name", tag),
			"name_ru": ident.get("country_name_ru", ident.get("country_name", tag)),
			"leader_name": ident.get("leader_name", manifest_lead.get("leader_name", "UNKNOWN")),
			"leader_title": ident.get("leader_title", manifest_lead.get("title", "Глава государства")),
			"ideology": ident.get("ruling_ideology", manifest_c.get("ruling_ideology", "Neutral")),
			"sub_ideology": ident.get("sub_ideology", manifest_c.get("sub_ideology", "")),
			"theater": ident.get("theater", manifest_c.get("theater", "theater_smuta")),
			"color": color,
			"portrait_path": portrait_p,
			"difficulty_rating": manifest_c.get("difficulty_rating", "●●●○○ (СРЕДНЯЯ)"),
			"starting_gdp": float(econ.get("gdp_billions", manifest_c.get("starting_gdp", 15.0))),
			"starting_manpower": int(mil.get("manpower_pool", manifest_c.get("starting_manpower", 50000))),
			"starting_factories": int(mil.get("civilian_factories", 15)) + int(mil.get("military_factories", 15)),
			"geopolitical_bloc": ident.get("geopolitical_bloc", "Non-Aligned"),
			"traits": traits_list,
			"lore": lore_text
		}

		if tag == "USA":
			dossier["name"] = "the United States of America"
			dossier["name_ru"] = "Соединённые Штаты Америки"
			dossier["leader_name"] = "Ричард Никсон"
			dossier["leader_title"] = "Президент США"
			dossier["portrait_path"] = "res://assets/gfx/leaders/USA/USA_Richard_Nixon.png"
			dossier["color"] = Color(0.20, 0.40, 0.85)
			dossier["theater"] = "theater_superpowers"
			dossier["difficulty_rating"] = "●●○○○ (УМЕРЕННАЯ)"
			dossier["starting_gdp"] = 280.0
			dossier["starting_manpower"] = 650000
			dossier["starting_factories"] = 310
			dossier["traits"] = ["Мастер кулуаров", "Альянс ОФН", "Расколотый конгресс", "Борьба за гражданские права"]
			dossier["lore"] = "Оплот свободного мира после поражения во Второй мировой войне. Под руководством Никсона страна противостоит Рейху и Японии в прокси-конфликтах (Южная Африка), пока в Конгрессе разгорается ожесточенная битва коалиции R-D и пакта NPP за гражданские права и будущее нации."
			dossier["geopolitical_bloc"] = "ОФН (Организация Свободных Наций)"
		elif tag == "SPE":
			dossier["name"] = "Reich of Albert Speer (Reformists)"
			dossier["name_ru"] = "Германия (Альберт Шпеер / Реформаторы)"
			dossier["leader_name"] = "Альберт Шпеер"
			dossier["leader_title"] = "Рейхсминистр вооружений / Лидер Реформаторов"
			dossier["portrait_path"] = "res://data/countries/GER/leaders/portraits/GER_albert_speer.png"
			dossier["color"] = Color(0.85, 0.65, 0.20)
			dossier["theater"] = "theater_gcw"
			dossier["difficulty_rating"] = "●●●○○ (СРЕДНЯЯ)"
			dossier["starting_gdp"] = 85.0
			dossier["starting_manpower"] = 250000
			dossier["starting_factories"] = 110
			dossier["traits"] = ["Архитектор Рейха", "Либерализация рынка", "Поддержка студенчества"]
			dossier["geopolitical_bloc"] = "Einheitspakt (Реформаторы)"
		elif tag == "BOR":
			dossier["name"] = "Reich of Martin Bormann (Party Bureaucracy)"
			dossier["name_ru"] = "Германия (Мартин Борман / Партократы)"
			dossier["leader_name"] = "Мартин Борман"
			dossier["leader_title"] = "Партийный Секретарь НСДАП / Коричневое Преосвященство"
			dossier["portrait_path"] = "res://data/countries/GER/leaders/portraits/GER_martin_bormann.png"
			dossier["color"] = Color(0.60, 0.45, 0.25)
			dossier["theater"] = "theater_gcw"
			dossier["difficulty_rating"] = "●●○○○ (НИЗКАЯ)"
			dossier["starting_gdp"] = 95.0
			dossier["starting_manpower"] = 380000
			dossier["starting_factories"] = 140
			dossier["traits"] = ["Коричневое преосвященство", "Аппаратная паутина", "Консервация статуса-кво"]
			dossier["geopolitical_bloc"] = "Einheitspakt (Партократы)"
		elif tag == "GOR":
			dossier["name"] = "Reich of Hermann Göring (Militarist Junta)"
			dossier["name_ru"] = "Германия (Герман Геринг / Милитаристы)"
			dossier["leader_name"] = "Герман Геринг"
			dossier["leader_title"] = "Рейхсмаршал Великогермании / Глава Люфтваффе"
			dossier["portrait_path"] = "res://data/countries/GER/leaders/portraits/GER_hermann_goring.png"
			dossier["color"] = Color(0.48, 0.52, 0.58)
			dossier["theater"] = "theater_gcw"
			dossier["difficulty_rating"] = "●●●●○ (ВЫСОКАЯ)"
			dossier["starting_gdp"] = 90.0
			dossier["starting_manpower"] = 420000
			dossier["starting_factories"] = 150
			dossier["traits"] = ["Марионетка Шёрнера", "Экономика непрерывного грабежа", "Воздушный триумф"]
			dossier["geopolitical_bloc"] = "Einheitspakt (Милитаристы)"
		elif tag == "HEY":
			dossier["name"] = "SS-Reich of Reinhard Heydrich"
			dossier["name_ru"] = "Германия (Рейнхард Гейдрих / Черный Орден СС)"
			dossier["leader_name"] = "Рейнхард Гейдрих"
			dossier["leader_title"] = "Обергруппенфюрер СС / Пражский Мясник"
			dossier["portrait_path"] = "res://data/countries/GER/leaders/portraits/GER_reinhard_heydrich.png"
			dossier["color"] = Color(0.18, 0.18, 0.24)
			dossier["theater"] = "theater_gcw"
			dossier["difficulty_rating"] = "●●●●● (ЭКСТРЕМАЛЬНАЯ)"
			dossier["starting_gdp"] = 70.0
			dossier["starting_manpower"] = 180000
			dossier["starting_factories"] = 95
			dossier["traits"] = ["Пражский мясник", "Орудие Гиммлера", "Черный орден"]
			dossier["geopolitical_bloc"] = "Burgundian Sphere (Черный Орден СС)"

		_cached_dossiers[tag] = dossier
		return dossier

	# 2. Legacy fallback
	var countries = manifest_data.get("countries", {})
	if countries.has(tag):
		var c = countries[tag]
		var lead = c.get("primary_leader", {})
		var dossier = {
			"tag": tag,
			"name": c.get("name", tag),
			"leader_name": lead.get("leader_name", "UNKNOWN"),
			"leader_title": lead.get("title", ""),
			"ideology": c.get("ruling_ideology", "Neutral"),
			"sub_ideology": c.get("sub_ideology", lead.get("sub_ideology", "")),
			"theater": c.get("theater", "theater_smuta"),
			"color": Color(0.75, 0.25, 0.25),
			"portrait_path": lead.get("portrait_path", "res://icon.svg"),
			"difficulty_rating": c.get("difficulty_rating", "●●●○○ (СРЕДНЯЯ)"),
			"starting_gdp": float(c.get("starting_gdp", 15.0)),
			"starting_manpower": int(c.get("starting_manpower", 50000)),
			"starting_factories": int(c.get("starting_factories", 25)),
			"traits": lead.get("traits", []),
			"lore": c.get("lore", lead.get("lore", ""))
		}
		_cached_dossiers[tag] = dossier
		return dossier

	return {}


func get_country_leaders(tag: String) -> Array[LeaderResource]:
	if _cached_leaders.has(tag):
		return _cached_leaders[tag]

	# Проверяем модульный пакет
	var pkg_leaders_dir = COUNTRIES_BASE_DIR.path_join(tag).path_join("leaders")
	if DirAccess.dir_exists_absolute(pkg_leaders_dir):
		var leaders = _load_package_leaders(tag, pkg_leaders_dir)
		if not leaders.is_empty():
			_cached_leaders[tag] = leaders
			return leaders

	# Legacy fallback
	var result: Array[LeaderResource] = []
	var countries = manifest_data.get("countries", {})
	if countries.has(tag):
		var c = countries[tag]
		var cabinet = c.get("cabinet_and_commanders", [])
		for char_dict in cabinet:
			var res = LeaderResource.from_dict(char_dict)
			result.append(res)

	_cached_leaders[tag] = result
	return result


func get_directives_for_country(tag: String) -> Array[DirectiveResource]:
	if _cached_directives.has(tag):
		return _cached_directives[tag]

	# 1. Проверяем trees_index.json для выбора оптимального стартового древа 1962 года
	var pkg_index_path = COUNTRIES_BASE_DIR.path_join(tag).path_join("directives").path_join("trees_index.json")
	if FileAccess.file_exists(pkg_index_path):
		var idx_data = _read_json(pkg_index_path)
		var chosen_path = ""
		if idx_data is Array and not idx_data.is_empty():
			for t_info in idx_data:
				var tid = str(t_info.get("tree_id", "")).to_lower()
				if tid.contains("base") or tid.contains("initial") or tid.contains("1962"):
					chosen_path = str(t_info.get("path", ""))
					break
			if chosen_path.is_empty():
				chosen_path = str(idx_data[0].get("path", ""))

		if not chosen_path.is_empty() and FileAccess.file_exists(chosen_path):
			var directives = _load_package_directives(tag, chosen_path)
			if not directives.is_empty():
				_cached_directives[tag] = directives
				return directives

	# 2. Проверяем модульный пакет tree.json
	var pkg_tree_path = COUNTRIES_BASE_DIR.path_join(tag).path_join("directives").path_join("tree.json")
	if FileAccess.file_exists(pkg_tree_path):
		var directives = _load_package_directives(tag, pkg_tree_path)
		if not directives.is_empty():
			_cached_directives[tag] = directives
			return directives

	# Legacy fallback
	var result: Array[DirectiveResource] = []
	var trees_by_tag = directives_data.get("trees_by_tag", {})

	if trees_by_tag.has(tag):
		var country_trees = trees_by_tag[tag].get("trees", {})
		var primary_tree_id = trees_by_tag[tag].get("primary_tree_id", "")
		var target_tree = country_trees.get(primary_tree_id)
		if target_tree == null and not country_trees.is_empty():
			target_tree = country_trees.values()[0]

		if target_tree != null:
			var dir_list = target_tree.get("directives", [])
			for d_data in dir_list:
				var d_res = DirectiveResource.from_dict(d_data)
				result.append(d_res)

	_cached_directives[tag] = result
	return result


func get_events_for_country(tag: String) -> Array[GameEvent]:
	if _cached_events.has(tag):
		return _cached_events[tag]

	var pkg_events_path = COUNTRIES_BASE_DIR.path_join(tag).path_join("events.json")
	if FileAccess.file_exists(pkg_events_path):
		var events = _load_package_events(tag, pkg_events_path)
		_cached_events[tag] = events
		return events

	return []


# ==============================================================================
# ПУБЛИЧНЫЙ API: ПРОВЕРКА И ПРЕВЬЮ ФОКУСНЫХ ДРЕВ
# ==============================================================================

##
## Возвращает список тегов всех стран, обладающих древами фокусов
##
func get_tags_with_focus_trees() -> Array[String]:
	var tags_set: Dictionary = {}

	# 1. Канонические державы с богатым контентом TNO
	var canonical_powers = [
		"USA", "GER", "JAP", "WRS", "KOM", "VYT", "SAM", "PRM", "TYU", "SVR",
		"OMS", "TOM", "NOV", "KEM", "SBA", "IRK", "BRY", "CHT", "MAG", "AMR",
		"SPE", "BOR", "GOR", "HEY", "ITA", "IBR", "ENG", "BRG", "FRD", "TUR",
		"GNG", "MAN", "CHI", "THA", "SCO", "WAL", "IRE", "YUN", "BRA", "MEX", "NIC", "BUL", "UKR"
	]
	for c in canonical_powers:
		tags_set[c] = true

	# 2. Модульные пакеты с trees_index.json или существенным tree.json
	if DirAccess.dir_exists_absolute(COUNTRIES_BASE_DIR):
		var dir = DirAccess.open(COUNTRIES_BASE_DIR)
		if dir != null:
			dir.list_dir_begin()
			var fn = dir.get_next()
			while not fn.is_empty():
				if dir.current_is_dir() and not fn.begins_with("."):
					var c_tag = fn.to_upper()
					var idx_path = COUNTRIES_BASE_DIR.path_join(fn).path_join("directives").path_join("trees_index.json")
					var tree_path = COUNTRIES_BASE_DIR.path_join(fn).path_join("directives").path_join("tree.json")
					if FileAccess.file_exists(idx_path):
						tags_set[c_tag] = true
					elif FileAccess.file_exists(tree_path):
						var f = FileAccess.open(tree_path, FileAccess.READ)
						if f != null:
							var txt = f.get_as_text()
							f.close()
							if txt.length() > 500:
								tags_set[c_tag] = true
				fn = dir.get_next()
			dir.list_dir_end()

	# 3. Из directives_data (манифест extracted)
	var trees_by_tag = directives_data.get("trees_by_tag", {})
	for t in trees_by_tag.keys():
		tags_set[str(t).to_upper()] = true

	var priority_list: Array[String] = []
	var other_list: Array[String] = []
	for t in tags_set.keys():
		if t in canonical_powers:
			priority_list.append(t)
		else:
			other_list.append(t)

	priority_list.sort_custom(func(a, b): return canonical_powers.find(a) < canonical_powers.find(b))
	other_list.sort()

	var result: Array[String] = []
	result.append_array(priority_list)
	result.append_array(other_list)
	return result


##
## Проверяет, обладает ли конкретная страна уникальным древом фокусов
##
func has_focus_tree(tag: String) -> bool:
	var clean_tag = tag.to_upper().strip_edges()
	if clean_tag.is_empty():
		return false

	var pkg_idx = COUNTRIES_BASE_DIR.path_join(clean_tag).path_join("directives").path_join("trees_index.json")
	if FileAccess.file_exists(pkg_idx):
		return true

	var pkg_tree = COUNTRIES_BASE_DIR.path_join(clean_tag).path_join("directives").path_join("tree.json")
	if FileAccess.file_exists(pkg_tree):
		return true

	var trees_by_tag = directives_data.get("trees_by_tag", {})
	return trees_by_tag.has(clean_tag)


##
## Извлекает структурированное резюме древа фокусов (название, число директив, стартовые цели)
##
func get_focus_tree_summary(tag: String) -> Dictionary:
	var clean_tag = tag.to_upper().strip_edges()
	var summary: Dictionary = {
		"has_tree": false,
		"tree_id": "",
		"tree_title": "",
		"total_trees": 1,
		"total_directives": 0,
		"categories": [],
		"starting_directives": []
	}

	if clean_tag.is_empty():
		return summary

	# 1. Попытка чтения из модульного пакета: directives/trees_index.json
	var pkg_index_path = COUNTRIES_BASE_DIR.path_join(clean_tag).path_join("directives").path_join("trees_index.json")
	if FileAccess.file_exists(pkg_index_path):
		var idx_data = _read_json(pkg_index_path)
		if idx_data is Array and not idx_data.is_empty():
			summary["has_tree"] = true
			summary["total_trees"] = idx_data.size()

			var chosen_tree_path = ""
			var chosen_tree_id = ""
			var total_all_dirs = 0
			for t_info in idx_data:
				var tid = str(t_info.get("tree_id", ""))
				total_all_dirs += int(t_info.get("total_directives", 0))
				if chosen_tree_path.is_empty() and (tid.contains("base") or tid.contains("initial") or tid.contains("shared") or tid.contains("1962")):
					chosen_tree_path = str(t_info.get("path", ""))
					chosen_tree_id = tid

			if chosen_tree_path.is_empty():
				chosen_tree_path = str(idx_data[0].get("path", ""))
				chosen_tree_id = str(idx_data[0].get("tree_id", ""))

			summary["tree_id"] = chosen_tree_id
			summary["tree_title"] = chosen_tree_id.replace("_", " ").to_upper()
			summary["total_directives"] = total_all_dirs if total_all_dirs > 0 else 50

			if FileAccess.file_exists(chosen_tree_path):
				var tree_data = _read_json_file(chosen_tree_path)
				var raw_title = str(tree_data.get("title", ""))
				if not raw_title.is_empty():
					summary["tree_title"] = raw_title

				var raw_nodes = tree_data.get("nodes", tree_data.get("directives", []))
				var dirs: Array = []
				if raw_nodes is Dictionary:
					dirs = raw_nodes.values()
				elif raw_nodes is Array:
					dirs = raw_nodes

				var cat_set: Dictionary = {}
				var starters: Array[Dictionary] = []
				for d in dirs:
					var cat = str(d.get("category", ""))
					if cat.is_empty():
						var d_id = str(d.get("id", d.get("directive_id", ""))).to_lower()
						if d_id.contains("saw") or d_id.contains("mil") or d_id.contains("army") or d_id.contains("navy"):
							cat = "military"
						elif d_id.contains("pol") or d_id.contains("pres") or d_id.contains("senate") or d_id.contains("bill"):
							cat = "politics"
						elif d_id.contains("econ") or d_id.contains("tax") or d_id.contains("ind"):
							cat = "economy"
						else:
							cat = "doctrine"
					cat_set[cat] = true

					var prereqs = d.get("prerequisites", [])
					if prereqs is Array and prereqs.is_empty() and starters.size() < 4:
						starters.append({
							"id": d.get("id", d.get("directive_id", "")),
							"title": d.get("title", ""),
							"description": d.get("description", ""),
							"icon_path": d.get("icon_path", ""),
							"icon_symbol": d.get("icon_symbol", "[★]"),
							"turns_required": d.get("turns_to_complete", d.get("turns_required", 1)),
							"cost_cap": d.get("cost_initial_cap", 0)
						})

				if cat_set.is_empty():
					cat_set["doctrine"] = true
				summary["categories"] = cat_set.keys()
				summary["starting_directives"] = starters
			return summary

	# 2. Попытка чтения из модульного пакета: directives/tree.json
	var pkg_tree_path = COUNTRIES_BASE_DIR.path_join(clean_tag).path_join("directives").path_join("tree.json")
	if FileAccess.file_exists(pkg_tree_path):
		var tree_data = _read_json_file(pkg_tree_path)
		var raw_nodes = tree_data.get("nodes", tree_data.get("directives", []))
		var dirs: Array = []
		if raw_nodes is Dictionary:
			dirs = raw_nodes.values()
		elif raw_nodes is Array:
			dirs = raw_nodes

		if not dirs.is_empty():
			summary["has_tree"] = true
			summary["total_trees"] = 1
			summary["total_directives"] = dirs.size()
			var tree_id = str(tree_data.get("tree_id", clean_tag + "_tree"))
			var raw_title = str(tree_data.get("title", ""))
			if raw_title.is_empty():
				raw_title = tree_id.replace("_", " ").to_upper()
			summary["tree_id"] = tree_id
			summary["tree_title"] = raw_title
			var cat_set: Dictionary = {}
			var starters: Array[Dictionary] = []
			for d in dirs:
				var cat = str(d.get("category", ""))
				if cat.is_empty():
					var d_id = str(d.get("id", d.get("directive_id", ""))).to_lower()
					if d_id.contains("saw") or d_id.contains("mil") or d_id.contains("army"):
						cat = "military"
					elif d_id.contains("pol") or d_id.contains("pres"):
						cat = "politics"
					elif d_id.contains("econ") or d_id.contains("ind"):
						cat = "economy"
					else:
						cat = "doctrine"
				cat_set[cat] = true
				var prereqs = d.get("prerequisites", [])
				if prereqs is Array and prereqs.is_empty() and starters.size() < 4:
					starters.append({
						"id": d.get("id", d.get("directive_id", "")),
						"title": d.get("title", ""),
						"description": d.get("description", ""),
						"icon_path": d.get("icon_path", ""),
						"icon_symbol": d.get("icon_symbol", "[★]"),
						"turns_required": d.get("turns_to_complete", d.get("turns_required", 1)),
						"cost_cap": d.get("cost_initial_cap", 0)
					})
			if cat_set.is_empty():
				cat_set["doctrine"] = true
			summary["categories"] = cat_set.keys()
			summary["starting_directives"] = starters
			return summary

	# 3. Legacy fallback (из directives_data)
	var trees_by_tag = directives_data.get("trees_by_tag", {})
	if trees_by_tag.has(clean_tag):
		var data = trees_by_tag[clean_tag]
		var c_trees = data.get("trees", {})
		var primary_id = data.get("primary_tree_id", "")
		var target_tree = c_trees.get(primary_id)
		if target_tree == null and not c_trees.is_empty():
			target_tree = c_trees.values()[0]
			if c_trees.keys().size() > 0:
				primary_id = c_trees.keys()[0]

		if target_tree != null:
			summary["has_tree"] = true
			summary["tree_id"] = primary_id
			var raw_title = target_tree.get("title", "")
			if raw_title.is_empty():
				raw_title = primary_id.replace("_", " ").to_upper()
			summary["tree_title"] = raw_title
			summary["total_trees"] = c_trees.size()

			var all_dirs = target_tree.get("directives", [])
			summary["total_directives"] = all_dirs.size()

			var cat_set: Dictionary = {}
			var starters: Array[Dictionary] = []
			for d in all_dirs:
				var cat = d.get("category", "doctrine")
				cat_set[cat] = true
				var prereqs = d.get("prerequisites", [])
				if prereqs is Array and prereqs.is_empty() and starters.size() < 4:
					starters.append({
						"id": d.get("directive_id", ""),
						"title": d.get("title", ""),
						"description": d.get("description", ""),
						"icon_path": d.get("icon_path", ""),
						"icon_symbol": d.get("icon_symbol", "[★]"),
						"turns_required": d.get("turns_required", 1),
						"cost_cap": d.get("cost_initial_cap", 0)
					})
			summary["categories"] = cat_set.keys()
			summary["starting_directives"] = starters
			return summary

	return summary



# ==============================================================================
# ВНУТРЕННИЕ МЕТОДЫ ДЛЯ ПАКЕТОВ
# ==============================================================================

func _load_index_manifest() -> void:
	index_data.clear()
	if not FileAccess.file_exists(COUNTRIES_INDEX_PATH):
		return

	var file = FileAccess.open(COUNTRIES_INDEX_PATH, FileAccess.READ)
	if file == null:
		return

	var text = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(text) == OK and json.data is Array:
		for item in json.data:
			if item is Dictionary:
				index_data.append(item as Dictionary)


func _load_package_leaders(_tag: String, leaders_dir: String) -> Array[LeaderResource]:
	var result: Array[LeaderResource] = []
	var dir = DirAccess.open(leaders_dir)
	if dir == null:
		return result

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var full_path = leaders_dir.path_join(file_name)
			var l_dict = _read_json_file(full_path)
			if not l_dict.is_empty():
				var leader_res = LeaderResource.from_dict(l_dict)
				result.append(leader_res)
		file_name = dir.get_next()
	dir.list_dir_end()

	return result


func _load_package_directives(_tag: String, tree_path: String) -> Array[DirectiveResource]:
	var result: Array[DirectiveResource] = []
	var tree_data = _read_json_file(tree_path)
	var dir_list = []
	if tree_data.has("directives"):
		var raw = tree_data["directives"]
		if raw is Array:
			dir_list = raw
		elif raw is Dictionary:
			dir_list = raw.values()
	elif tree_data.has("nodes"):
		var raw = tree_data["nodes"]
		if raw is Array:
			dir_list = raw
		elif raw is Dictionary:
			dir_list = raw.values()

	for d_dict in dir_list:
		if d_dict is Dictionary:
			var d_res = DirectiveResource.from_dict(d_dict)
			result.append(d_res)

	return result


func _load_package_events(_tag: String, events_path: String) -> Array[GameEvent]:
	var result: Array[GameEvent] = []
	if not FileAccess.file_exists(events_path):
		return result
	var file = FileAccess.open(events_path, FileAccess.READ)
	if file == null:
		return result
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(text) != OK:
		return result
	var events_data = json.data
	if events_data is Array:
		for raw in events_data:
			if raw is Dictionary:
				result.append(GameEvent.from_dict(raw))
	elif events_data is Dictionary:
		for ev_id in events_data.keys():
			var raw = events_data[ev_id]
			if raw is Dictionary:
				result.append(GameEvent.from_dict(raw))
	return result


func _register_package_localization(_tag: String, loc_dir: String) -> void:
	var loc_mgr = null
	var main_loop = Engine.get_main_loop()
	if main_loop is SceneTree and main_loop.root != null:
		loc_mgr = main_loop.root.get_node_or_null("LocalizationManager")

	for lang in ["ru", "en"]:
		var file_path = loc_dir.path_join("%s.json" % lang)
		if FileAccess.file_exists(file_path):
			var data = _read_json_file(file_path)
			var strings_map = data.get("strings", {})
			if strings_map is Dictionary and not strings_map.is_empty():
				if loc_mgr != null and loc_mgr.has_method("register_custom_strings"):
					loc_mgr.register_custom_strings(lang, strings_map)
				else:
					# Регистрация напрямую в TranslationServer
					var tr = Translation.new()
					tr.locale = lang
					for k in strings_map:
						tr.add_message(k, str(strings_map[k]))
					TranslationServer.add_translation(tr)



func _fallback_create_country_state(tag: String) -> CountryState:
	var dossier = get_country_dossier(tag)
	var state = CountryState.new()
	state.country_tag = tag
	state.country_name = dossier.get("name", tag)
	state.leader_name = dossier.get("leader_name", "")
	state.leader_portrait_path = dossier.get("portrait_path", "res://icon.svg")
	state.ruling_ideology = dossier.get("ideology", "Authoritarian Socialism")
	state.sub_ideology = dossier.get("sub_ideology", "")
	state.gdp_billions = dossier.get("starting_gdp", 18.0)
	state.manpower_pool = dossier.get("starting_manpower", 75000)
	state.civilian_factories = int(dossier.get("starting_factories", 25) * 0.4)
	state.military_factories = int(dossier.get("starting_factories", 25) * 0.6)
	_cached_country_states[tag] = state
	return state


func _build_dossiers_cache() -> void:
	_cached_dossiers.clear()
	var manifest = get_available_countries_manifest()
	for item in manifest:
		var tag = item.get("tag", "")
		if not tag.is_empty():
			get_country_dossier(tag)


func _read_json(res_path: String) -> Variant:
	if not FileAccess.file_exists(res_path):
		return null

	var file = FileAccess.open(res_path, FileAccess.READ)
	if file == null:
		return null

	var text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var err = json.parse(text)
	if err == OK:
		return json.data
	return null


func _read_json_file(res_path: String) -> Dictionary:
	var data = _read_json(res_path)
	if data is Dictionary:
		return data
	return {}


##
## Загрузка оперативных решений (Decisions) для указанной державы
##
func load_country_decisions(tag: String) -> Array[Dictionary]:
	var clean_tag = tag.to_upper().strip_edges()
	if _cached_decisions.has(clean_tag):
		return _cached_decisions[clean_tag]

	var result: Array[Dictionary] = []
	var pkg_path = COUNTRIES_BASE_DIR.path_join(clean_tag).path_join("decisions.json")
	if FileAccess.file_exists(pkg_path):
		var raw = _read_json(pkg_path)
		if raw is Array:
			for item in raw:
				if item is Dictionary:
					var req_tags = item.get("requires_tags", [])
					if not req_tags.is_empty() and not req_tags.has(clean_tag):
						continue
					result.append(item)

	# Если для страны нет отдельного пакета или список пуст — ищем релевантные в master_decisions
	if result.is_empty():
		var master = get_master_decisions()
		var is_russian = clean_tag in ["KOM", "WRRF", "WRS", "SAM", "OMS", "VYT", "SVR", "TYM", "IRK", "BRY", "TOM", "NOV", "KEM", "MAG", "AMR", "CHT", "YAK", "ZLT", "ORE", "MGN", "DRL", "BKR", "TAR", "YGR", "VOR", "KAZ", "AKT", "ARL", "KOK", "PAV", "NPL", "KRK", "ALT", "KMC", "TYU", "MIR", "KHA", "VLG", "KOS", "ONE", "ONG"]
		var is_german = clean_tag in ["GER", "BOR", "SPE", "GOR", "HEY", "BGR", "SGR", "GGR", "HGR"]
		var is_usa = (clean_tag == "USA")

		for d in master:
			var tags = d.get("requires_tags", [])
			if tags.has(clean_tag):
				result.append(d)
			elif is_russian and d.get("requires_russia", false):
				result.append(d)
			elif is_german and d.get("requires_germany", false):
				result.append(d)
			elif is_usa and d.get("requires_usa", false):
				result.append(d)
			elif d.get("requires_general", false):
				result.append(d)

	# Добавляем универсальные декреты из generic_decisions, если они еще не добавлены
	var generic_path = "res://data/decisions/generic_decisions.json"
	if FileAccess.file_exists(generic_path):
		var gen_raw = _read_json(generic_path)
		if gen_raw is Array:
			var existing_ids = {}
			for r in result:
				existing_ids[r.get("id", "")] = true
			for g in gen_raw:
				if g is Dictionary and not existing_ids.has(g.get("id", "")):
					result.append(g)

	_cached_decisions[clean_tag] = result
	return result


##
## Загрузка полного каталога всех доступных оперативных решений
##
func get_master_decisions() -> Array[Dictionary]:
	if not _master_decisions_cache.is_empty():
		return _master_decisions_cache

	var master_path = "res://data/extracted/decisions_master.json"
	if FileAccess.file_exists(master_path):
		var raw = _read_json(master_path)
		if raw is Array:
			for item in raw:
				if item is Dictionary:
					_master_decisions_cache.append(item)

	return _master_decisions_cache
