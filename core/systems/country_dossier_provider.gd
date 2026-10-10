class_name CountryDossierProvider
extends RefCounted

##
## CountryDossierProvider: Поставщик тактических досье стран, лора и театров военных действий
## ==============================================================================
## Отвечает за:
## 1. Предоставление списка театров боевых действий (Theaters / Bookmarks).
## 2. Формирование тактического досье державы для экрана выбора (Lobby) и терминала.
## 3. Разрешение стартовых параметров: ВВП, людские резервы, фабрики, лидеры, черты характера.
## ==============================================================================

const COUNTRIES_BASE_DIR: String = "res://data/countries"
const THEATERS_JSON_PATH: String = "res://data/theaters.json"
const CANONICAL_OVERRIDES_PATH: String = "res://data/canonical_overrides.json"

static var _cached_overrides: Dictionary = {}
static var _cached_theaters_template: Array[Dictionary] = []


"""Возвращает список каноничных театров военных действий TNO.
"""
static func get_theaters(focus_tags: Array[String] = []) -> Array[Dictionary]:
	if _cached_theaters_template.is_empty():
		var raw_list: Array = JSONFileHelper.load_json_array(THEATERS_JSON_PATH)
		for item: Variant in raw_list:
			if item is Dictionary:
				_cached_theaters_template.append(item.duplicate(true))

	var result: Array[Dictionary] = []
	for th: Dictionary in _cached_theaters_template:
		var copy_th: Dictionary = th.duplicate(true)
		if copy_th.get("id", "") == "theater_focus_trees":
			copy_th["tags"] = focus_tags
		result.append(copy_th)

	return result


"""Возвращает список играбельных наций для заданного театра (или всех театров).
"""
static func get_playable_countries(manifest: Array[Dictionary], theater_id: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for c: Dictionary in manifest:
		if theater_id.is_empty() or c.get("theater", "") == theater_id:
			result.append(c)
	return result


"""Формирует и кэширует тактическое досье державы.
"""
static func get_country_dossier(tag: String, manifest_data: Dictionary = {}, cached_dossiers: Dictionary = {}) -> Dictionary:
	var clean_tag: String = tag.to_upper().strip_edges()
	if cached_dossiers.has(clean_tag):
		return cached_dossiers[clean_tag]
	if cached_dossiers.has(tag):
		return cached_dossiers[tag]

	# 1. Попытка чтения из country.json
	var country_json_path: String = COUNTRIES_BASE_DIR.path_join(clean_tag).path_join("country.json")
	if FileAccess.file_exists(country_json_path):
		var c: Dictionary = JSONFileHelper.load_json_dict(country_json_path)
		var ident: Dictionary = c.get("identity", {})
		var econ: Dictionary = c.get("economy", {})
		var mil: Dictionary = c.get("military", {})

		var col_arr: Variant = ident.get("country_color", [0.75, 0.25, 0.25, 1.0])
		var color := Color(0.75, 0.25, 0.25)
		if col_arr is Array and col_arr.size() >= 3:
			color = Color(col_arr[0], col_arr[1], col_arr[2])

		# Извлечение черт (traits) лидера
		var traits_list: Array = []
		var manifest_c: Dictionary = manifest_data.get("countries", {}).get(clean_tag, {})
		var manifest_lead: Dictionary = manifest_c.get("primary_leader", {})
		if manifest_lead.has("traits") and manifest_lead["traits"] is Array and not manifest_lead["traits"].is_empty():
			traits_list = manifest_lead["traits"]
		elif ident.has("traits") and ident["traits"] is Array:
			traits_list = ident["traits"]

		# Извлечение лора (Lore)
		var lore_text: String = str(ident.get("lore", ""))
		if lore_text.is_empty():
			lore_text = str(c.get("narrative", {}).get("lore", ""))
		if lore_text.is_empty():
			lore_text = str(manifest_c.get("lore", manifest_lead.get("lore", "")))
		if lore_text.is_empty():
			var loc_mgr: Object = null
			var main_loop: MainLoop = Engine.get_main_loop()
			if main_loop is SceneTree and main_loop.root != null and main_loop.root.has_node("LocalizationManager"):
				loc_mgr = main_loop.root.get_node("LocalizationManager")
			if loc_mgr != null:
				var l_val: String = loc_mgr.tr_key(clean_tag + "_lore", "")
				if not l_val.is_empty() and not l_val.begins_with("[MISSING"):
					lore_text = l_val
				else:
					var tno_val: String = loc_mgr.tr_key(clean_tag + "_THENEWORDER_DESC", "")
					if not tno_val.is_empty() and not tno_val.begins_with("[MISSING"):
						lore_text = tno_val

		var portrait_p: String = ident.get("leader_portrait_path", "res://icon.svg")
		if (portrait_p.is_empty() or portrait_p == "res://icon.svg") and manifest_lead.has("portrait_path"):
			var mp: String = str(manifest_lead["portrait_path"])
			if not mp.is_empty() and FileAccess.file_exists(mp):
				portrait_p = mp

		var c_name: String = ident.get("country_name", c.get("name_text", clean_tag))
		var c_name_ru: String = ident.get("country_name_ru", c.get("name_text", c_name))

		var l_name: String = ident.get("leader_name", manifest_lead.get("leader_name", ""))
		var l_title: String = ident.get("leader_title", manifest_lead.get("title", "Глава государства"))
		var l_ideology: String = ident.get("ruling_ideology", manifest_c.get("ruling_ideology", c.get("ruling_party", "Neutral")))
		var l_portrait: String = portrait_p

		# Поиск портрета среди лидеров
		if (l_portrait.is_empty() or l_portrait == "res://icon.svg") and c.has("leaders") and c["leaders"] is Array:
			for lead: Variant in c["leaders"]:
				if lead is Dictionary:
					if l_name.is_empty() or l_name == "UNKNOWN":
						l_name = str(lead.get("name_text", lead.get("name", lead.get("id", "UNKNOWN"))))
					if l_title.is_empty():
						l_title = str(lead.get("desc", "Лидер державы"))

					var p_large: String = ""
					if lead.has("portraits") and lead["portraits"] is Dictionary:
						var pts: Dictionary = lead["portraits"]
						if pts.has("civilian") and pts["civilian"] is Dictionary:
							p_large = str(pts["civilian"].get("large", ""))
						elif pts.has("army") and pts["army"] is Dictionary:
							p_large = str(pts["army"].get("large", ""))

					if p_large.is_empty() and lead.has("picture"):
						p_large = str(lead["picture"])
					elif p_large.is_empty() and lead.has("country_leader"):
						var cl: Variant = lead["country_leader"]
						if cl is Dictionary:
							p_large = str(cl.get("picture", ""))
						elif cl is Array and not cl.is_empty() and cl[0] is Dictionary:
							p_large = str(cl[0].get("picture", ""))

					if p_large.is_empty() and lead.has("civilian"):
						var civ_val: Variant = lead["civilian"]
						if civ_val is Dictionary:
							p_large = str(civ_val.get("large", ""))
						elif civ_val is Array and not civ_val.is_empty() and civ_val[0] is Dictionary:
							p_large = str(civ_val[0].get("large", ""))

					var lead_id: String = str(lead.get("id", lead.get("name_key", "")))
					l_portrait = PortraitResolver.resolve_leader_portrait(clean_tag, p_large, lead_id)

					var cl_val: Variant = lead.get("country_leader")
					var lead_ideo: String = ""
					if cl_val is Dictionary:
						lead_ideo = str(cl_val.get("ideology", ""))
					elif cl_val is Array and not cl_val.is_empty() and cl_val[0] is Dictionary:
						lead_ideo = str(cl_val[0].get("ideology", ""))

					if not lead_ideo.is_empty() and l_ideology == "Neutral":
						l_ideology = lead_ideo
					break

		if l_name.is_empty():
			l_name = "UNKNOWN"

		var dossier: Dictionary = {
			"tag": clean_tag,
			"name": c_name,
			"name_ru": c_name_ru,
			"leader_name": l_name,
			"leader_title": l_title,
			"ideology": l_ideology,
			"sub_ideology": ident.get("sub_ideology", manifest_c.get("sub_ideology", "")),
			"theater": ident.get("theater", manifest_c.get("theater", "theater_smuta")),
			"color": color,
			"portrait_path": l_portrait,
			"difficulty_rating": manifest_c.get("difficulty_rating", "●●●○○ (СРЕДНЯЯ)"),
			"starting_gdp": float(econ.get("gdp_billions", manifest_c.get("starting_gdp", 15.0))),
			"starting_manpower": int(mil.get("manpower_pool", manifest_c.get("starting_manpower", 50000))),
			"starting_factories": int(mil.get("civilian_factories", 15)) + int(mil.get("military_factories", 15)),
			"geopolitical_bloc": ident.get("geopolitical_bloc", "Non-Aligned"),
			"traits": traits_list,
			"lore": lore_text
		}

		var overrides: Dictionary = _get_canonical_overrides(clean_tag)
		if not overrides.is_empty():
			for k: String in overrides:
				dossier[k] = overrides[k]

		cached_dossiers[clean_tag] = dossier
		cached_dossiers[tag] = dossier
		return dossier

	# 2. Legacy fallback
	var countries: Dictionary = manifest_data.get("countries", {})
	if countries.has(clean_tag):
		var c: Dictionary = countries[clean_tag]
		var lead: Dictionary = c.get("primary_leader", {})
		var dossier: Dictionary = {
			"tag": clean_tag,
			"name": c.get("name", clean_tag),
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
		cached_dossiers[clean_tag] = dossier
		cached_dossiers[tag] = dossier
		return dossier

	# 3. Детерминированный фоллбэк для малых наций без country.json (DEF-17)
	var generated: Dictionary = _generate_fallback_dossier(clean_tag, manifest_data)
	if not generated.is_empty():
		cached_dossiers[clean_tag] = generated
		cached_dossiers[tag] = generated
		return generated

	return {}


"""Генерирует детерминированное досье для малой нации при отсутствии файла country.json.
Сканирует папку лидеров тега (res://assets/gfx/leaders/<tag>), извлекает локализацию и настраивает параметры.
"""
static func _generate_fallback_dossier(tag: String, _manifest_data: Dictionary = {}) -> Dictionary:
	var clean_tag: String = tag.to_upper().strip_edges()
	if clean_tag.is_empty():
		return {}

	# 1. Поиск локализованного названия страны
	var c_name: String = clean_tag
	var c_name_ru: String = clean_tag
	var loc_mgr: Object = null
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree and main_loop.root != null and main_loop.root.has_node("LocalizationManager"):
		loc_mgr = main_loop.root.get_node("LocalizationManager")
	if loc_mgr != null:
		var n_ru: String = loc_mgr.tr_key(clean_tag, "")
		if not n_ru.is_empty() and not n_ru.begins_with("[MISSING"):
			c_name_ru = n_ru
			c_name = n_ru
		else:
			var n_def: String = loc_mgr.tr_key(clean_tag + "_DEF", "")
			if not n_def.is_empty() and not n_def.begins_with("[MISSING"):
				c_name_ru = n_def
				c_name = n_def

	# 2. Поиск портрета и имени лидера в директории лидеров страны
	var l_name: String = "UNKNOWN"
	var l_portrait: String = PortraitResolver.find_portrait_in_tag_dir(clean_tag)

	if not l_portrait.is_empty():
		var chosen_file: String = l_portrait.get_file()
		var raw_lead: String = chosen_file.trim_suffix(".png")
		if raw_lead.begins_with(clean_tag + "_"):
			raw_lead = raw_lead.trim_prefix(clean_tag + "_")
		elif raw_lead.begins_with("Portrait_" + clean_tag + "_"):
			raw_lead = raw_lead.trim_prefix("Portrait_" + clean_tag + "_")
		elif raw_lead.begins_with("Portrait_"):
			raw_lead = raw_lead.trim_prefix("Portrait_")

		raw_lead = raw_lead.replace("_TNO", "").replace("_tno", "").replace("_", " ").strip_edges()
		if not raw_lead.is_empty():
			l_name = raw_lead
	else:
		l_portrait = PortraitResolver.resolve_leader_portrait(clean_tag)

	if l_name == "UNKNOWN":
		l_name = "%s Временное Руководство" % c_name_ru

	# 3. Детерминированный цвет и стартовые параметры на основе хэша тега
	var color: Color = ColorUtils.tag_to_color(clean_tag)
	var h_seed: int = abs(clean_tag.hash())
	var gdp: float = 2.0 + float(h_seed % 15)
	var manpower: int = 15000 + (h_seed % 35000)
	var factories: int = 3 + (h_seed % 8)

	return {
		"tag": clean_tag,
		"name": c_name,
		"name_ru": c_name_ru,
		"leader_name": l_name,
		"leader_title": "Глава государства",
		"ideology": "Authoritarian Democracy",
		"sub_ideology": "Despotism",
		"theater": "theater_global",
		"color": color,
		"portrait_path": l_portrait,
		"leader_portrait": l_portrait,
		"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
		"starting_gdp": gdp,
		"starting_manpower": manpower,
		"starting_factories": factories,
		"geopolitical_bloc": "Non-Aligned",
		"traits": ["Суверенное правительство", "Локальный нейтралитет"],
		"lore": "Суверенное государство, сохраняющее нейтралитет и балансирующее между великими державами в эпоху Холодной Войны."
	}


"""Загружает и преобразует каноничные переопределения для нации из data/canonical_overrides.json.
"""
static func _get_canonical_overrides(tag: String) -> Dictionary:
	var clean_tag: String = tag.to_upper().strip_edges()
	if _cached_overrides.is_empty():
		_cached_overrides = JSONFileHelper.load_json_dict(CANONICAL_OVERRIDES_PATH)

	if not _cached_overrides.has(clean_tag):
		return {}

	var raw_override: Dictionary = _cached_overrides[clean_tag]
	var result: Dictionary = raw_override.duplicate(true)

	# Гарантия преобразования [r, g, b] в Color
	if result.has("color"):
		var col_val: Variant = result["color"]
		if col_val is Array and col_val.size() >= 3:
			result["color"] = Color(float(col_val[0]), float(col_val[1]), float(col_val[2]))
		elif col_val is String:
			result["color"] = ColorUtils.hex_to_color(col_val)

	return result
