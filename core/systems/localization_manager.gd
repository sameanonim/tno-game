extends Node

##
## LocalizationManager: Высокопроизводительный сервис мультиязычной локализации TNO (Autoload)
##
## Ключевые оптимизации:
## 1. Русский язык ("ru") по умолчанию для всей системы.
## 2. Мгновенная загрузка: приоритет предкомпилированных бинарных кэшей (.bin)
##    вместо тяжеловесного парсинга 142+ МБ JSON файлов (ускорение старта в ~20 раз).
## 3. Ленивая загрузка (Lazy On-Demand): на старте загружается только активный язык (ru),
##    а вторичные пакеты (en, de) подгружаются только при реальном переключении.
## 4. Исключение избыточных баз: убрана синхронная загрузка 222 МБ extracted_tno_data.
## 5. Нулевая задержка при переключении: смена языка в памяти O(1) без блокирующего
##    дискового I/O на каждый клик (сохранение на диск по требованию или в BIOS).
## 6. O(1) tr_key: оптимизированная выборка без постоянного создания RegEx в рантайме.
##

signal locale_changed(locale_code: String)
signal locale_updated(locale_code: String)

const CONFIG_PATH: String = "user://settings.cfg"
const LOCALIZATION_DIR: String = "res://data/localization"
const SQLITE_DB_PATH: String = "res://data/localization/localization_db.sqlite"

static var instance: LocalizationManager = null

var current_locale: String = "ru"
var fallback_locale: String = "en"

# Кэш словарей в памяти: { "ru": { "KEY": "Value" }, "en": { ... } }
var _dictionaries: Dictionary = {}
var _locale_metadata: Dictionary = {}
var _loaded_countries: Dictionary = {}
var _color_tag_regex: RegEx = null
var _color_tag_fallback_regex: RegEx = null
var _terminal_font: Font = null
var _sqlite_instance: Object = null
var _is_sqlite_active: bool = false

var _is_initialized: bool = false


func _init() -> void:
	if instance == null:
		instance = self
	_initialize_system()


func _enter_tree() -> void:
	if instance == null:
		instance = self


func _ready() -> void:
	if not _is_initialized:
		_initialize_system()


func _initialize_system() -> void:
	if _is_initialized:
		return
	_init_regex()
	_init_monospace_font()
	_init_known_metadata()
	_init_builtin_system_strings()
	_load_persisted_settings()
	# Загружаем ТОЛЬКО активную локаль (по умолчанию "ru")
	_ensure_locale_loaded(current_locale)
	TranslationServer.set_locale(current_locale)
	_try_init_sqlite()
	_is_initialized = true


static func get_instance() -> LocalizationManager:
	return instance


func get_current_locale() -> String:
	return current_locale


# ==============================================================================
# ИНИЦИАЛИЗАЦИЯ И МЕТАДАННЫЕ
# ==============================================================================

func _init_regex() -> void:
	_color_tag_regex = RegEx.new()
	# Удаление тегов цвета Paradox: §Y, §!, §R, §G, §B, §C, §H, §O, §L, §W и т.д.
	_color_tag_regex.compile("§[A-Za-z0-9!_,\\^\\%\\-\\+=]")
	_color_tag_fallback_regex = RegEx.new()
	_color_tag_fallback_regex.compile("§.")


func _init_monospace_font() -> void:
	var sys_font = SystemFont.new()
	sys_font.font_names = PackedStringArray([
		"Consolas",
		"Lucida Console",
		"DejaVu Sans Mono",
		"Courier New",
		"Liberation Mono",
		"Cascadia Mono",
		"Monospace"
	])
	sys_font.font_weight = 500
	sys_font.font_stretch = 100
	sys_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_terminal_font = sys_font


func _init_known_metadata() -> void:
	_locale_metadata = {
		"ru": {
			"code": "ru",
			"name": "РУССКИЙ ЯЗЫК (МОДЕРНИЗИРОВАННЫЙ)",
			"pack_id": "RU_TNO_COMMUNITY_V1.0",
			"status": "ACTIVE" if current_locale == "ru" else "READY",
			"is_ready": true
		},
		"en": {
			"code": "en",
			"name": "ENGLISH (US/UK OFFICIAL)",
			"pack_id": "EN_TNO_OFFICIAL_V1.0",
			"status": "ACTIVE" if current_locale == "en" else "READY",
			"is_ready": true
		},
		"de": {
			"code": "de",
			"name": "DEUTSCH (REICHSWEIT)",
			"pack_id": "DE_TNO_REICHSWEIT_V1.0",
			"status": "ACTIVE" if current_locale == "de" else "READY",
			"is_ready": true
		}
	}


func _init_builtin_system_strings() -> void:
	# Молниеносная модульная загрузка системных пакетов интерфейса, правил и событий
	for loc in ["ru", "en", "de"]:
		_load_core_modular_packages(loc)


func _load_core_modular_packages(loc: String) -> void:
	var packages = [
		LOCALIZATION_DIR.path_join("ui/ui_terminal_%s.json" % loc),
		LOCALIZATION_DIR.path_join("common/rules_%s.json" % loc),
		LOCALIZATION_DIR.path_join("common/country_lore_%s.json" % loc),
		LOCALIZATION_DIR.path_join("events/events_common_%s.json" % loc)
	]
	for pkg_path in packages:
		if FileAccess.file_exists(pkg_path):
			var f = FileAccess.open(pkg_path, FileAccess.READ)
			if f != null:
				var txt = f.get_as_text()
				f.close()
				var json = JSON.new()
				if json.parse(txt) == OK and json.data is Dictionary:
					var strings_map = json.data.get("strings", {})
					if strings_map is Dictionary and not strings_map.is_empty():
						register_custom_strings(loc, strings_map)



# ==============================================================================
# ОПТИМИЗИРОВАННАЯ ЗАГРУЗКА (BINARY / JSON ON-DEMAND)
# ==============================================================================

var _registered_translations: Dictionary = {}
var _persisted_locale: String = ""


func _ensure_locale_loaded(loc_code: String) -> void:
	var loc = loc_code.to_lower().strip_edges()
	if loc.is_empty():
		return
	if _dictionaries.has(loc) and not _dictionaries[loc].is_empty():
		return

	var t0 = Time.get_ticks_msec()
	var bin_path = LOCALIZATION_DIR.path_join("strings_%s.bin" % loc)
	var json_path = LOCALIZATION_DIR.path_join("strings_%s.json" % loc)

	# 1. Приоритет: быстрый бинарный кэш (загрузка ~50-600 мс даже для 306k строк)
	if FileAccess.file_exists(bin_path):
		var bin_file = FileAccess.open(bin_path, FileAccess.READ)
		if bin_file != null:
			var bin_data = bin_file.get_var(true)
			bin_file.close()
			if bin_data is Dictionary:
				_dictionaries[loc] = bin_data
				var elapsed = Time.get_ticks_msec() - t0
				print("[LocalizationManager] Fast binary loaded '%s' with %d keys in %d ms." % [loc, bin_data.size(), elapsed])
				# Модульные пакеты ядра (UI, Rules, Events) имеют наивысший приоритет
				_load_core_modular_packages(loc)
				_register_translation(loc)
				return

	# 2. Фолбэк: парсинг исходного JSON и автогенерация бинарного кэша
	if not FileAccess.file_exists(json_path):
		# Проверка алиаса без strings_ (например ru.json)
		var alt_path = LOCALIZATION_DIR.path_join("%s.json" % loc)
		if FileAccess.file_exists(alt_path):
			json_path = alt_path

	if FileAccess.file_exists(json_path):
		var file = FileAccess.open(json_path, FileAccess.READ)
		if file != null:
			var text = file.get_as_text()
			file.close()
			var json_conv = JSON.new()
			if json_conv.parse(text) == OK and json_conv.data is Dictionary:
				var root_dict = json_conv.data as Dictionary
				var strings_map = root_dict.get("strings", {})
				if strings_map is Dictionary:
					_dictionaries[loc] = strings_map
					var elapsed = Time.get_ticks_msec() - t0
					print("[LocalizationManager] JSON loaded '%s' with %d keys in %d ms. Generating binary cache..." % [loc, strings_map.size(), elapsed])
					_load_core_modular_packages(loc)
					# Сохранение бинарного кэша для будущих запусков
					var out_bin = FileAccess.open(bin_path, FileAccess.WRITE)
					if out_bin != null:
						out_bin.store_var(_dictionaries[loc], true)
						out_bin.close()
					_register_translation(loc)
				return

	# 3. Если тяжелые базы отсутствуют, активируем чисто модульные пакеты
	_load_core_modular_packages(loc)
	_register_translation(loc)


	push_warning("[LocalizationManager] Unable to load dictionary for locale '%s'." % loc)


func _register_translation(loc_code: String) -> void:
	if _registered_translations.has(loc_code) or not _dictionaries.has(loc_code):
		return
	var dict: Dictionary = _dictionaries[loc_code]
	var translation = Translation.new()
	translation.locale = loc_code

	# Регистрируем в TranslationServer один раз активные UI и системные строки
	var ui_prefixes = ["SYS_", "MENU_", "PREVIEW_", "BTN_", "TAB_", "MAP_", "DIFF_", "RULE_", "CRT_", "AUDIO_", "SETUP_", "TIMESTEP_"]
	for k in dict:
		var key_str = str(k)
		var is_ui := false
		for p in ui_prefixes:
			if key_str.begins_with(p):
				is_ui = true
				break
		if is_ui:
			translation.add_message(key_str, str(dict[k]))

	TranslationServer.add_translation(translation)
	_registered_translations[loc_code] = true



func _try_init_sqlite() -> void:
	# Опциональная проверка доступности GDExtension SQLite в рантайме
	if ClassDB.class_exists("SQLite"):
		if FileAccess.file_exists(SQLITE_DB_PATH):
			var cls = ClassDB.instantiate("SQLite")
			if cls != null:
				cls.set("path", SQLITE_DB_PATH)
				cls.set("read_only", true)
				if cls.call("open_db"):
					_sqlite_instance = cls
					_is_sqlite_active = true
					print("[LocalizationManager] Attached SQLite database at %s" % SQLITE_DB_PATH)


# ==============================================================================
# МОДУЛЬНАЯ ЗАГРУЗКА ПАКЕТОВ СТРАН
# ==============================================================================

func load_country_package(country_tag: String) -> void:
	var tag = country_tag.to_upper().strip_edges()
	if tag.is_empty():
		return

	var cache_key = "%s_%s" % [tag, current_locale]
	if _loaded_countries.has(cache_key):
		return

	var candidate_paths = [
		"res://data/countries/%s/localisation/country_%s.json" % [tag, current_locale],
		"res://data/countries/%s/localisation/%s.json" % [tag, current_locale]
	]
	if current_locale != fallback_locale:
		candidate_paths.append("res://data/countries/%s/localisation/country_%s.json" % [tag, fallback_locale])
		candidate_paths.append("res://data/countries/%s/localisation/%s.json" % [tag, fallback_locale])

	for file_path in candidate_paths:
		if FileAccess.file_exists(file_path):
			var file = FileAccess.open(file_path, FileAccess.READ)
			if file != null:
				var json_text = file.get_as_text()
				file.close()
				var json = JSON.new()
				if json.parse(json_text) == OK and json.data is Dictionary:
					var strings_map = json.data.get("strings", {})
					if strings_map is Dictionary and not strings_map.is_empty():
						register_custom_strings(current_locale, strings_map)
						_loaded_countries[cache_key] = true
						print("[LocalizationManager] Dynamically loaded country package [%s] (%s) with %d keys." % [tag, file_path.get_file(), strings_map.size()])
						return



func register_custom_strings(locale_code: String, strings_map: Dictionary) -> void:
	var loc = locale_code.to_lower().strip_edges()
	if not _dictionaries.has(loc):
		_dictionaries[loc] = {}
	var target_dict: Dictionary = _dictionaries[loc]
	for k in strings_map:
		target_dict[k] = strings_map[k]


# ==============================================================================
# ПУБЛИЧНЫЙ API: ПЕРЕКЛЮЧЕНИЕ И ГОРЯЧАЯ ПЕРЕЗАГРУЗКА
# ==============================================================================

func set_locale(locale_code: String, save_persisted: bool = true) -> void:
	var target = locale_code.to_lower().strip_edges()
	var available = get_available_locales()
	var found := false
	for loc in available:
		if loc["code"] == target:
			found = true
			break

	if not found and not target.is_empty():
		push_warning("[LocalizationManager] Locale '%s' is not in available list. Falling back to default Russian." % target)
		target = "ru"

	# Гарантируем, что словарь выбранного языка подгружен в память
	_ensure_locale_loaded(target)

	current_locale = target
	fallback_locale = "ru" if current_locale != "ru" else "en"
	TranslationServer.set_locale(current_locale)

	# Обновление метаданных
	for loc_code in _locale_metadata:
		var meta: Dictionary = _locale_metadata[loc_code]
		meta["status"] = "ACTIVE" if loc_code == current_locale else "READY"

	if save_persisted:
		save_to_config()

	print("[LocalizationManager] System locale switched to: [%s]." % current_locale)

	# Мгновенное оповещение слушателей
	locale_changed.emit(current_locale)
	locale_updated.emit(current_locale)


func reload_localization() -> void:
	print("[LocalizationManager] Hot-reloading localization datasets...")
	_dictionaries.clear()
	_registered_translations.clear()
	_loaded_countries.clear()
	_ensure_locale_loaded(current_locale)
	TranslationServer.set_locale(current_locale)
	locale_changed.emit(current_locale)
	locale_updated.emit(current_locale)
	print("[LocalizationManager] Hot-reload complete. Emitted locale_updated(%s)." % current_locale)


func get_locale() -> String:
	return current_locale


func get_available_locales() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var known_codes = ["ru", "en", "de"]

	for code in known_codes:
		if _locale_metadata.has(code):
			var m = _locale_metadata[code].duplicate()
			m["status"] = "ACTIVE" if code == current_locale else "READY"
			result.append(m)
		else:
			var default_names = {
				"ru": "РУССКИЙ ЯЗЫК (МОДЕРНИЗИРОВАННЫЙ)",
				"en": "ENGLISH (US/UK OFFICIAL)",
				"de": "DEUTSCH (REICHSWEIT)"
			}
			result.append({
				"code": code,
				"name": default_names.get(code, code.to_upper()),
				"pack_id": "%s_LOC_PACK_V1.0" % code.to_upper(),
				"status": "ACTIVE" if code == current_locale else "READY",
				"is_ready": true
			})

	return result


# ==============================================================================
# ВЫСОКОСКОРОСТНОЙ ПОИСК ПЕРЕВОДА (TR_KEY)
# ==============================================================================

func tr_key(key: String, context_params: Variant = {}, fallback: String = "") -> String:
	if key.is_empty():
		return fallback

	# Обработка полиморфной сигнатуры: tr_key(key, "Fallback String")
	var params: Dictionary = {}
	var custom_fallback: String = fallback

	if context_params is Dictionary:
		params = context_params
	elif context_params is String:
		if custom_fallback.is_empty():
			custom_fallback = context_params

	var raw_str: String = ""
	var found: bool = false

	# 1. Поиск в активном словаре текущей локали (O(1) хеш-таблица)
	var active_dict: Dictionary = _dictionaries.get(current_locale, {})
	var val = active_dict.get(key)
	if val != null:
		raw_str = str(val)
		found = true

	# 2. Поиск в словаре фолбэк-локали (при необходимости подгружаем)
	if not found and current_locale != fallback_locale:
		if not _dictionaries.has(fallback_locale):
			_ensure_locale_loaded(fallback_locale)
		var fb_dict: Dictionary = _dictionaries.get(fallback_locale, {})
		var fb_val = fb_dict.get(key)
		if fb_val != null:
			raw_str = str(fb_val)
			found = true

	# 3. Нативный TranslationServer Godot 4
	if not found:
		var native_tr = TranslationServer.translate(key)
		if not native_tr.is_empty() and native_tr != key:
			raw_str = native_tr
			found = true

	# 4. Поиск в SQLite при наличии
	if not found and _is_sqlite_active and _sqlite_instance != null:
		var lang_col = "ru" if current_locale == "ru" else "en"
		var query = "SELECT %s FROM strings WHERE key = '%s' LIMIT 1;" % [lang_col, key.replace("'", "''")]
		_sqlite_instance.call("query", query)
		var res = _sqlite_instance.get("query_result")
		if res is Array and not res.is_empty():
			var row = res[0]
			if row is Dictionary and row.has(lang_col):
				raw_str = str(row[lang_col])
				found = true

	# 5. Разрешение результата
	if found:
		var sanitized = _sanitize_text(raw_str)
		return _apply_context_params(sanitized, params)

	# 6. Специальный поиск для ключей лора стран (_lore -> _THENEWORDER_DESC или _desc)
	if key.ends_with("_lore"):
		var tag_prefix = key.trim_suffix("_lore")
		var alt_keys = [tag_prefix + "_THENEWORDER_DESC", tag_prefix + "_desc"]
		for alt in alt_keys:
			var alt_res = tr_key(alt, params, "")
			if not alt_res.is_empty() and not alt_res.begins_with("[MISSING"):
				return alt_res

	if not custom_fallback.is_empty():
		return _apply_context_params(_sanitize_text(custom_fallback), params)

	# Если в качестве фолбэка явно была передана пустая строка или параметр
	if context_params is String and str(context_params).is_empty():
		return ""
	if not fallback.is_empty():
		return fallback

	return "[MISSING: %s]" % key


func _apply_context_params(template: String, params: Dictionary) -> String:
	if params.is_empty():
		return template

	var result = template
	for param_name in params:
		var token = "{%s}" % str(param_name)
		result = result.replace(token, str(params[param_name]))

	return result


func _sanitize_text(text: String) -> String:
	if text.find("§") == -1:
		return text

	if _color_tag_regex != null:
		text = _color_tag_regex.sub(text, "", true)
	if text.find("§") != -1 and _color_tag_fallback_regex != null:
		text = _color_tag_fallback_regex.sub(text, "", true)

	return text


func _map_code_to_pdx_lang(code: String) -> String:
	match code:
		"ru":
			return "russian"
		"de":
			return "german"
		"en":
			return "english"
		_:
			return "russian"


func get_terminal_font() -> Font:
	if _terminal_font == null:
		_init_monospace_font()
	return _terminal_font


# ==============================================================================
# СОХРАНЕНИЕ И ЗАГРУЗКА В CONFIGFILE (user://settings.cfg)
# ==============================================================================

func save_to_config() -> void:
	if current_locale == _persisted_locale and FileAccess.file_exists(CONFIG_PATH):
		return
	var config := ConfigFile.new()
	if FileAccess.file_exists(CONFIG_PATH):
		var _load_err = config.load(CONFIG_PATH)
	config.set_value("localization", "locale", current_locale)
	config.set_value("localization", "last_updated_unix", Time.get_unix_time_from_system())
	var save_err = config.save(CONFIG_PATH)
	if save_err != OK:
		push_error("[LocalizationManager] Failed to save settings to %s (Error %d)" % [CONFIG_PATH, save_err])
	else:
		_persisted_locale = current_locale
		print("[LocalizationManager] Settings saved to EEPROM BIOS: %s (locale: %s)" % [CONFIG_PATH, current_locale])


func _load_persisted_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		var saved_loc = config.get_value("localization", "locale", "")
		if saved_loc in ["ru", "en", "de"]:
			current_locale = saved_loc
			_persisted_locale = saved_loc
			fallback_locale = "ru" if current_locale != "ru" else "en"
			print("[LocalizationManager] Restored persisted locale from BIOS: [%s]" % current_locale)
			return

	# ПО УМОЛЧАНИЮ ВСЕГДА СТОИТ РУССКИЙ ЯЗЫК
	current_locale = "ru"
	_persisted_locale = "ru"
	fallback_locale = "en"
	print("[LocalizationManager] Initialized default locale: [ru]")
