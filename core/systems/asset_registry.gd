class_name AssetRegistryClass
extends Node

##
## AssetRegistry: Централизованный менеджер игровых ассетов TNO (Autoload)
##
## Отвечает за:
## 1. Разрешение символических Clausewitz-спрайтов (GFX_...) в Godot Texture2D
## 2. Поиск и кэширование иллюстраций событий (Event Pictures)
## 3. Поиск и кэширование иконок законов, реформ и национальных духов (Ideas)
## 4. Поиск и кэширование иконок решений и кризисов (Decisions)
## 5. Предоставление экранов загрузки и фонов Холодной войны (Loading Screens)
## 6. Автоматический fallback на стилизованные заглушки ЭЛТ-терминала
##

signal texture_loaded(key: String, texture: Texture2D)

static var instance: AssetRegistryClass = null

const SPRITE_INDEX_PATH: String = "res://data/sprite_index.json"
const EVENT_PICTURES_MANIFEST_PATH: String = "res://data/event_pictures_manifest.json"
const IDEAS_MANIFEST_PATH: String = "res://data/ideas_manifest.json"
const DECISIONS_MANIFEST_PATH: String = "res://data/decisions_manifest.json"
const LOADINGSCREENS_MANIFEST_PATH: String = "res://data/loadingscreens_manifest.json"

# In-memory manifests
var _sprite_index: Dictionary = {}
var _event_pictures: Dictionary = {}
var _ideas: Dictionary = {}
var _decisions: Dictionary = {}
var _loadingscreens: Array[String] = []

# Texture Cache (LRU/Dictionary)
var _texture_cache: Dictionary = {}
const MAX_CACHE_SIZE: int = 256


func _init() -> void:
	if instance == null:
		instance = self


func _enter_tree() -> void:
	if instance == null:
		instance = self


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_all_manifests()


static func get_instance() -> AssetRegistryClass:
	return instance


## Загружает все индексные манифесты при запуске игры
func _load_all_manifests() -> void:
	_sprite_index = _load_json_dict(SPRITE_INDEX_PATH)
	_event_pictures = _load_json_dict(EVENT_PICTURES_MANIFEST_PATH)
	_ideas = _load_json_dict(IDEAS_MANIFEST_PATH)
	_decisions = _load_json_dict(DECISIONS_MANIFEST_PATH)

	var ls_data: Variant = _load_json_raw(LOADINGSCREENS_MANIFEST_PATH)
	if ls_data is Array:
		_loadingscreens.clear()
		for item in ls_data:
			if item is String:
				_loadingscreens.append(item)


## Возвращает путь ресурса (res://...) для GFX-спрайта
func resolve_sprite_path(sprite_name: String) -> String:
	if sprite_name.is_empty():
		return ""

	# 0. Проверка в глобальном индексном манифесте спрайтов (_sprite_index)
	if _sprite_index.has(sprite_name):
		var p_idx = str(_sprite_index[sprite_name])
		if ResourceLoader.exists(p_idx):
			return p_idx

	var clean_name: String = sprite_name.replace("GFX_", "")
	if _sprite_index.has(clean_name):
		var p_idx_clean = str(_sprite_index[clean_name])
		if ResourceLoader.exists(p_idx_clean):
			return p_idx_clean

	# 1. Прямая проверка в манифестах событий/идей/решений
	if _event_pictures.has(sprite_name):
		return str(_event_pictures[sprite_name])
	if _ideas.has(sprite_name):
		return str(_ideas[sprite_name])
	if _decisions.has(sprite_name):
		return str(_decisions[sprite_name])

	# 2. Проверка альтернативных префиксов
	if _ideas.has(clean_name):
		return str(_ideas[clean_name])
	if _decisions.has(clean_name):
		return str(_decisions[clean_name])
	if _event_pictures.has(clean_name):
		return str(_event_pictures[clean_name])

	# 3. Проверка прямого файла в event_pictures / ideas
	var direct_ev: String = "res://assets/gfx/event_pictures/%s.png" % sprite_name
	if ResourceLoader.exists(direct_ev):
		return direct_ev
	var direct_ev_clean: String = "res://assets/gfx/event_pictures/%s.png" % clean_name
	if ResourceLoader.exists(direct_ev_clean):
		return direct_ev_clean

	var direct_idea: String = "res://assets/gfx/interface/ideas/%s.png" % sprite_name
	if ResourceLoader.exists(direct_idea):
		return direct_idea
	var direct_idea_clean: String = "res://assets/gfx/interface/ideas/%s.png" % clean_name
	if ResourceLoader.exists(direct_idea_clean):
		return direct_idea_clean

	# 4. Проверка иконок директив (goals)
	var direct_goal: String = "res://assets/gfx/interface/goals/%s.png" % sprite_name
	if ResourceLoader.exists(direct_goal):
		return direct_goal
	var direct_goal_clean: String = "res://assets/gfx/interface/goals/%s.png" % clean_name
	if ResourceLoader.exists(direct_goal_clean):
		return direct_goal_clean

	var ui_goal: String = "res://ui/assets/goals/%s.png" % sprite_name
	if ResourceLoader.exists(ui_goal):
		return ui_goal
	var ui_goal_clean: String = "res://ui/assets/goals/%s.png" % clean_name
	if ResourceLoader.exists(ui_goal_clean):
		return ui_goal_clean
	var ui_goal_focus: String = "res://ui/assets/goals/focus_%s.png" % clean_name.replace("focus_", "")
	if ResourceLoader.exists(ui_goal_focus):
		return ui_goal_focus

	return ""


## Получает текстуру по имени спрайта или id
func get_texture(sprite_name: String) -> Texture2D:
	if sprite_name.is_empty():
		return null

	if _texture_cache.has(sprite_name):
		return _texture_cache[sprite_name] as Texture2D

	var path: String = resolve_sprite_path(sprite_name)
	if path.is_empty():
		# Если передали прямой путь
		if sprite_name.begins_with("res://") and ResourceLoader.exists(sprite_name):
			path = sprite_name

	if not path.is_empty() and ResourceLoader.exists(path):
		var tex: Texture2D = load(path) as Texture2D
		if tex != null:
			_store_in_cache(sprite_name, tex)
			texture_loaded.emit(sprite_name, tex)
			return tex

	return null


## Получает иллюстрацию для события
func get_event_picture(picture_id: String) -> Texture2D:
	if not picture_id.is_empty():
		var tex: Texture2D = get_texture(picture_id)
		if tex != null:
			return tex
		if not picture_id.begins_with("GFX_"):
			var p_prefixed = get_texture("GFX_" + picture_id)
			if p_prefixed != null:
				return p_prefixed

	# Fallback на дефолтные арты TNO, если специфический арт события отсутствует
	var fallback_candidates: Array[String] = [
		"report_event_generic_sign_treaty2",
		"GFX_report_event_RUS_soldiers_generic_1",
		"GFX_report_event_USA_election_generic",
		"GFX_report_event_JAP_generic_diplomats"
	]
	for fb in fallback_candidates:
		var fb_tex: Texture2D = get_texture(fb)
		if fb_tex != null:
			return fb_tex

	return null



## Получает иконку национального духа / реформы (Idea)
func get_idea_icon(idea_id: String) -> Texture2D:
	if idea_id.is_empty():
		return null

	# Прямая проверка
	var tex: Texture2D = get_texture(idea_id)
	if tex != null:
		return tex

	var prefixed: String = "GFX_idea_%s" % idea_id
	tex = get_texture(prefixed)
	if tex != null:
		return tex

	return null


## Получает иконку решения (Decision)
func get_decision_icon(decision_id: String) -> Texture2D:
	if decision_id.is_empty():
		return null

	var tex: Texture2D = get_texture(decision_id)
	if tex != null:
		return tex

	var prefixed: String = "GFX_decision_%s" % decision_id
	tex = get_texture(prefixed)
	if tex != null:
		return tex

	return null


## Возвращает случайный или индексированный экран загрузки
func get_random_loading_screen() -> Texture2D:
	if _loadingscreens.is_empty():
		return null
	var idx: int = randi() % _loadingscreens.size()
	var path: String = _loadingscreens[idx]
	return get_texture(path)


func _store_in_cache(key: String, tex: Texture2D) -> void:
	if _texture_cache.size() >= MAX_CACHE_SIZE:
		# Очистить старейшие записи при переполнении кэша
		var keys_to_remove: Array = _texture_cache.keys().slice(0, 32)
		for k in keys_to_remove:
			_texture_cache.erase(k)
	_texture_cache[key] = tex


func _load_json_dict(file_path: String) -> Dictionary:
	var raw: Variant = _load_json_raw(file_path)
	if raw is Dictionary:
		return raw as Dictionary
	return {}


func _load_json_raw(file_path: String) -> Variant:
	if not FileAccess.file_exists(file_path):
		return null
	var fa: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if fa == null:
		return null
	var content: String = fa.get_as_text()
	fa.close()
	var json: JSON = JSON.new()
	var err: Error = json.parse(content)
	if err == OK:
		return json.data
	return null
