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

const CountryDossierProviderScript = preload("res://core/systems/country_dossier_provider.gd")
const FocusTreeIndexerScript = preload("res://core/systems/focus_tree_indexer.gd")

static var instance = null

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

	if not index_data.is_empty():
		is_ready = true
		_build_dossiers_cache()
		TNOLogger.info("ContentLoader", "Successfully initialized modular index: %d packages available." % index_data.size())
		content_loaded.emit(index_data.size(), 0)
		return true

	# Fallback to legacy manifest only if index.json is missing
	if FileAccess.file_exists(LEGACY_MANIFEST_PATH):
		manifest_data = _read_json_file(LEGACY_MANIFEST_PATH)
	if FileAccess.file_exists(LEGACY_TREES_PATH):
		directives_data = _read_json_file(LEGACY_TREES_PATH)

	var countries = manifest_data.get("countries", {})
	var trees = directives_data.get("trees_by_tag", {})

	if not countries.is_empty():
		is_ready = true
		_build_dossiers_cache()
		TNOLogger.info("ContentLoader", "Initialized from legacy manifest: %d countries, %d trees." % [countries.size(), trees.size()])
		content_loaded.emit(countries.size(), trees.size())
		return true
	else:
		TNOLogger.warn("ContentLoader", "Notice: Neither index.json nor legacy manifest found. Using defaults.")
		is_ready = false
		return false


func has_extracted_data() -> bool:
	return is_ready and (not index_data.is_empty() or not manifest_data.get("countries", {}).is_empty())


# ==============================================================================
# МОДУЛЬНЫЕ СТРАНОВЫЕ ПАКЕТЫ (COUNTRY PACKAGES API)
# ==============================================================================

## Загружает данные державы из изолированной SQLite базы данных, если доступен GDExtension
func load_country_package_sqlite(country_tag: String) -> CountryState:
	if not ClassDB.class_exists("SQLite"):
		return null
	var tag = country_tag.to_upper().strip_edges()
	var db_path = COUNTRIES_BASE_DIR.path_join(tag).path_join("country.sqlite")
	if not FileAccess.file_exists(db_path):
		return null
	var db = ClassDB.instantiate("SQLite")
	if db == null:
		return null
	db.set("path", db_path)
	if not db.has_method("open_db") or not db.call("open_db"):
		return null

	db.call("query", "SELECT key, value FROM profile;")
	var res = db.get("query_result")
	if res is Array and not res.is_empty():
		var dict: Dictionary = {}
		for row in res:
			var k = str(row.get("key", ""))
			var v = str(row.get("value", ""))
			var p = JSON.new()
			if p.parse(v) == OK:
				dict[k] = p.data
			else:
				dict[k] = v
		if not dict.is_empty():
			var state = CountryState.from_dict(dict)
			state.country_tag = tag
			return state
	return null


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

	# 0. Попытка быстрой загрузки из изолированной базы данных country.sqlite
	var sqlite_state = load_country_package_sqlite(tag)
	if sqlite_state != null:
		_cached_country_states[tag] = sqlite_state
		country_package_loaded.emit(tag, sqlite_state)
		return sqlite_state

	var target_json_path := ""
	if FileAccess.file_exists(country_json_path):
		target_json_path = country_json_path
	elif FileAccess.file_exists(profile_json_path):
		target_json_path = profile_json_path
	else:
		TNOLogger.warn("ContentLoader", "Package not found at %s. Attempting CountryDataImporter fallback." % country_json_path)
		var imp_state = CountryDataImporter.load_country(tag)
		if imp_state != null and not imp_state.country_name.is_empty():
			_cached_country_states[tag] = imp_state
			return imp_state
		return _fallback_create_country_state(tag)

	# 1. Загрузка профиля страны (country.json / country_profile.json)
	var country_dict = _read_json_file(target_json_path)
	var state = CountryState.from_dict(country_dict)
	state.country_tag = tag

	# 2. Загрузка лидеров кабинета (leaders/*.json + country.json)
	var leaders_dir = pkg_dir.path_join("leaders")
	var loaded_leaders = _load_package_leaders(tag, leaders_dir)
	_cached_leaders[tag] = loaded_leaders

	# Назначение Главы Государства (Head of State)
	if state.head_of_state == null and not loaded_leaders.is_empty():
		var found_hos: LeaderResource = null
		if not state.leader_name.is_empty():
			for l in loaded_leaders:
				if l.leader_name == state.leader_name or l.leader_id == state.leader_name:
					found_hos = l
					break
		if found_hos == null:
			for l in loaded_leaders:
				if l.is_head_of_state:
					found_hos = l
					break
		if found_hos == null:
			found_hos = loaded_leaders[0]

		state.head_of_state = found_hos
		state.leader_name = found_hos.leader_name
		if state.leader_portrait_path.is_empty() or state.leader_portrait_path == "res://icon.svg":
			state.leader_portrait_path = found_hos.portrait_path
		if state.leader_title.is_empty() or state.leader_title == "Глава государства":
			state.leader_title = found_hos.title
		if state.leader_description.is_empty() and not found_hos.description.is_empty():
			state.leader_description = found_hos.description

	# Синхронизация министров кабинета (cabinet_members)
	if state.cabinet_members.is_empty() and not loaded_leaders.is_empty():
		var raw_ideas = country_dict.get("ideas", [])
		var assigned_ids: Dictionary = {}
		if state.head_of_state != null:
			assigned_ids[state.head_of_state.leader_id] = true

		# 1) Сначала активные министры из списка national ideas (например, WRS_Nikolay_Baibakov_eco)
		if raw_ideas is Array:
			for idea_token in raw_ideas:
				var tok = str(idea_token)
				for l in loaded_leaders:
					if assigned_ids.has(l.leader_id):
						continue
					if tok.begins_with(l.leader_id) or l.leader_id in tok:
						state.cabinet_members.append(l)
						assigned_ids[l.leader_id] = true
						break

		# 2) Добавляем всех остальных министров по ролям
		for l in loaded_leaders:
			if assigned_ids.has(l.leader_id):
				continue
			if l.role in ["PRIME_MINISTER", "ECONOMY", "FOREIGN_AFFAIRS", "SECURITY", "DEFENSE", "MINISTER"]:
				state.cabinet_members.append(l)
				assigned_ids[l.leader_id] = true
			elif not l.is_head_of_state and not l.is_military_commander:
				state.cabinet_members.append(l)
				assigned_ids[l.leader_id] = true

	# Синхронизация военачальников (military_commanders)
	if state.military_commanders.is_empty() and not loaded_leaders.is_empty():
		for l in loaded_leaders:
			if l.is_military_commander or l.role in ["THEATER_COMMANDER", "DEFENSE"]:
				if state.head_of_state == null or l.leader_id != state.head_of_state.leader_id:
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
	TNOLogger.info("ContentLoader", "Loaded modular package [%s]: %d leaders, %d directives, %d events." % [
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
## Возвращает всех лидеров и министров страны (Data-Driven API)
##
func get_leaders_for_country(tag: String) -> Array[LeaderResource]:
	var clean_tag = tag.to_upper().strip_edges()
	if _cached_leaders.has(clean_tag):
		return _cached_leaders[clean_tag]
	var pkg_dir = COUNTRIES_BASE_DIR.path_join(clean_tag)
	var leaders_dir = pkg_dir.path_join("leaders")
	var loaded = _load_package_leaders(clean_tag, leaders_dir)
	_cached_leaders[clean_tag] = loaded
	return loaded


##
## Возвращает только министров кабинета страны (Data-Driven API)
##
func get_ministers_for_country(tag: String) -> Array[LeaderResource]:
	var all_leaders = get_leaders_for_country(tag)
	var ministers: Array[LeaderResource] = []
	for l in all_leaders:
		if l.role in ["PRIME_MINISTER", "ECONOMY", "FOREIGN_AFFAIRS", "SECURITY", "DEFENSE", "MINISTER"]:
			ministers.append(l)
		elif not l.is_head_of_state and not l.is_military_commander:
			ministers.append(l)
	return ministers


##
## Возвращает главу государства (Data-Driven API)
##
func get_head_of_state_for_country(tag: String) -> LeaderResource:
	var clean_tag = tag.to_upper().strip_edges()
	if _cached_country_states.has(clean_tag):
		var st = _cached_country_states[clean_tag]
		if st.head_of_state != null:
			return st.head_of_state
	var all_leaders = get_leaders_for_country(clean_tag)
	for l in all_leaders:
		if l.is_head_of_state:
			return l
	return all_leaders[0] if not all_leaders.is_empty() else null


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
			if l != null and (l.leader_id == clean_id or l.leader_name == clean_id):
				return l

	# 2. Прямая загрузка из JSON-файла пакета
	var leader_file = COUNTRIES_BASE_DIR.path_join(clean_tag).path_join("leaders").path_join("%s.json" % clean_id)
	if FileAccess.file_exists(leader_file):
		var l_dict = _read_json_file(leader_file)
		if not l_dict.is_empty():
			return LeaderResource.from_dict(l_dict)

	# 3. Поиск в country.json ("leaders")
	var c_file = COUNTRIES_BASE_DIR.path_join(clean_tag).path_join("country.json")
	if FileAccess.file_exists(c_file):
		var c_data = _read_json_file(c_file)
		if c_data.has("leaders") and c_data["leaders"] is Array:
			for lead in c_data["leaders"]:
				if lead is Dictionary:
					var lid = str(lead.get("id", lead.get("leader_id", "")))
					if lid == clean_id or str(lead.get("name_text", "")) == clean_id:
						return LeaderResource.from_dict(lead)

	# 4. Fallback: поиск в родительских пакетах (например GER для фракций GCW)
	for fallback_tag in ["GER", "WRS", "SOV"]:
		if fallback_tag != clean_tag:
			var fb_file = COUNTRIES_BASE_DIR.path_join(fallback_tag).path_join("leaders").path_join("%s.json" % clean_id)
			if FileAccess.file_exists(fb_file):
				var fb_dict = _read_json_file(fb_file)
				if not fb_dict.is_empty():
					return LeaderResource.from_dict(fb_dict)

	# 5. Fallback: поиск среди cabinet_members или military_commanders загруженного профиля
	if _cached_country_states.has(clean_tag):
		var st = _cached_country_states[clean_tag]
		if st.head_of_state != null and (st.head_of_state.leader_id == clean_id or st.head_of_state.leader_name == clean_id):
			return st.head_of_state
		for m in st.cabinet_members:
			if m != null and (m.leader_id == clean_id or m.leader_name == clean_id):
				return m
		for c in st.military_commanders:
			if c != null and (c.leader_id == clean_id or c.leader_name == clean_id):
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
	return CountryDossierProviderScript.get_theaters(get_tags_with_focus_trees())


func get_playable_countries(theater_id: String = "") -> Array[Dictionary]:
	return CountryDossierProviderScript.get_playable_countries(get_available_countries_manifest(), theater_id)


func get_country_dossier(tag: String) -> Dictionary:
	return CountryDossierProviderScript.get_country_dossier(tag, manifest_data, _cached_dossiers)



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
		var chosen_path := ""
		if idx_data is Array and not idx_data.is_empty():
			for t_info in idx_data:
				if bool(t_info.get("is_starting_tree", false)):
					chosen_path = str(t_info.get("path", ""))
					break
				var tid = str(t_info.get("tree_id", "")).to_lower()
				if tid.contains("game_start") or tid.contains("intro") or tid.contains("base") or tid.contains("initial") or tid.contains("1962") or tid.contains("pre_election"):
					chosen_path = str(t_info.get("path", ""))
					break
			if chosen_path.is_empty():
				chosen_path = str(idx_data[0].get("path", ""))

		if not chosen_path.is_empty():
			var alt_path = chosen_path
			if not FileAccess.file_exists(alt_path) and "/directives/tree_" in alt_path:
				alt_path = alt_path.replace("/directives/tree_", "/directives/trees/")
			if FileAccess.file_exists(alt_path):
				var directives = _load_package_directives(tag, alt_path)
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
	return FocusTreeIndexerScript.get_tags_with_focus_trees(directives_data)


func has_focus_tree(tag: String) -> bool:
	return FocusTreeIndexerScript.has_focus_tree(tag, directives_data)


func get_focus_tree_summary(tag: String) -> Dictionary:
	return FocusTreeIndexerScript.get_focus_tree_summary(tag, directives_data)



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
	if json.parse(text) == OK:
		if json.data is Array:
			for item in json.data:
				if item is Dictionary:
					index_data.append(item as Dictionary)
		elif json.data is Dictionary:
			for k in json.data.keys():
				var item = json.data[k]
				if item is Dictionary:
					if not item.has("tag"):
						item["tag"] = str(k)
					index_data.append(item as Dictionary)


func _load_package_leaders(tag: String, leaders_dir: String) -> Array[LeaderResource]:
	var result: Array[LeaderResource] = []
	var loaded_ids: Dictionary = {}

	# 1. Загрузка из директории leaders/*.json
	if DirAccess.dir_exists_absolute(leaders_dir):
		var dir = DirAccess.open(leaders_dir)
		if dir != null:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while not file_name.is_empty():
				if not dir.current_is_dir() and file_name.ends_with(".json") and file_name != "index.json":
					var full_path = leaders_dir.path_join(file_name)
					var l_dict = _read_json_file(full_path)
					if not l_dict.is_empty():
						var leader_res = LeaderResource.from_dict(l_dict)
						var l_id = leader_res.leader_id
						if l_id.is_empty():
							l_id = file_name.trim_suffix(".json")
							leader_res.leader_id = l_id
						if not loaded_ids.has(l_id):
							loaded_ids[l_id] = true
							result.append(leader_res)
				file_name = dir.get_next()
			dir.list_dir_end()

	# 2. Загрузка из country.json ("leaders": [...])
	var country_json_path = COUNTRIES_BASE_DIR.path_join(tag).path_join("country.json")
	if FileAccess.file_exists(country_json_path):
		var c_data = _read_json_file(country_json_path)
		if c_data.has("leaders") and c_data["leaders"] is Array:
			for lead in c_data["leaders"]:
				if lead is Dictionary:
					var l_id = str(lead.get("id", lead.get("leader_id", "")))
					if not l_id.is_empty() and loaded_ids.has(l_id):
						continue
					var leader_res = LeaderResource.from_dict(lead)
					if not leader_res.leader_id.is_empty():
						loaded_ids[leader_res.leader_id] = true
					result.append(leader_res)

	# 3. Загрузка из legacy manifest (если есть)
	var manifest_c = manifest_data.get("countries", {}).get(tag, {})
	var manifest_leads = manifest_c.get("leaders", [])
	if manifest_leads is Array:
		for ml in manifest_leads:
			if ml is Dictionary:
				var ml_id = str(ml.get("id", ml.get("leader_id", "")))
				if not ml_id.is_empty() and loaded_ids.has(ml_id):
					continue
				var leader_res = LeaderResource.from_dict(ml)
				if not leader_res.leader_id.is_empty():
					loaded_ids[leader_res.leader_id] = true
				result.append(leader_res)

	# 4. Fallback на теги-алиасы (TYU <-> TYM, SVE <-> SVR, WRS <-> WRRF, SAM <-> ROA)
	if result.size() < 2:
		var aliases = {
			"TYU": "TYM", "TYM": "TYU",
			"SVE": "SVR", "SVR": "SVE",
			"WRS": "WRRF", "WRRF": "WRS",
			"SAM": "ROA", "ROA": "SAM"
		}
		if aliases.has(tag):
			var alias_tag = aliases[tag]
			var alias_dir = COUNTRIES_BASE_DIR.path_join(alias_tag).path_join("leaders")
			var alias_leaders = _load_package_leaders(alias_tag, alias_dir)
			for al in alias_leaders:
				if not loaded_ids.has(al.leader_id):
					loaded_ids[al.leader_id] = true
					result.append(al)

	return result


func _load_package_directives(_tag: String, tree_path: String) -> Array[DirectiveResource]:
	var result: Array[DirectiveResource] = []
	var tree_data = _read_json_file(tree_path)
	var dir_list := []
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
	state.leader_title = dossier.get("leader_title", "Глава государства")
	state.leader_description = dossier.get("lore", dossier.get("briefing", ""))
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
		TNOLogger.warn("ContentLoader", "JSON file does not exist: %s" % res_path)
		return null

	var file = FileAccess.open(res_path, FileAccess.READ)
	if file == null:
		TNOLogger.error("ContentLoader", "Cannot open JSON file (code %d): %s" % [FileAccess.get_open_error(), res_path])
		return null

	var text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var err = json.parse(text)
	if err == OK:
		return json.data
	TNOLogger.error("ContentLoader", "Failed to parse JSON (%s at line %d): %s" % [json.get_error_message(), json.get_error_line(), res_path])
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
			if not tags.is_empty():
				if tags.has(clean_tag):
					result.append(d)
				continue

			if is_russian and d.get("requires_russia", false):
				result.append(d)
			elif is_german and d.get("requires_germany", false):
				result.append(d)
			elif is_usa and d.get("requires_usa", false):
				result.append(d)
			elif d.get("requires_general", false):
				result.append(d)

	# Добавляем универсальные декреты из generic_decisions, если они еще не добавлены
	var generic_path := "res://data/decisions/generic_decisions.json"
	if FileAccess.file_exists(generic_path):
		var gen_raw = _read_json(generic_path)
		if gen_raw is Array:
			var existing_ids := {}
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

	var master_path := "res://data/extracted/decisions_master.json"
	if FileAccess.file_exists(master_path):
		var raw = _read_json(master_path)
		if raw is Array:
			for item in raw:
				if item is Dictionary:
					_master_decisions_cache.append(item)

	return _master_decisions_cache
