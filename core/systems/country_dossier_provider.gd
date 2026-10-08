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


"""Возвращает список каноничных театров военных действий TNO.
"""
static func get_theaters(focus_tags: Array[String] = []) -> Array[Dictionary]:
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


"""Возвращает список играбельных наций для заданного театра (или всех театров).
"""
static func get_playable_countries(manifest: Array[Dictionary], theater_id: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for c in manifest:
		if theater_id.is_empty() or c.get("theater", "") == theater_id:
			result.append(c)
	return result



"""Формирует и кэширует тактическое досье державы.
"""
static func get_country_dossier(tag: String, manifest_data: Dictionary = {}, cached_dossiers: Dictionary = {}) -> Dictionary:
	if cached_dossiers.has(tag):
		return cached_dossiers[tag]

	# 1. Попытка чтения из country.json
	var country_json_path = COUNTRIES_BASE_DIR.path_join(tag).path_join("country.json")
	if FileAccess.file_exists(country_json_path):
		var file = FileAccess.open(country_json_path, FileAccess.READ)
		var c: Dictionary = {}
		if file != null:
			var txt = file.get_as_text()
			file.close()
			var json = JSON.new()
			if json.parse(txt) == OK and json.data is Dictionary:
				c = json.data

		var ident: Dictionary = c.get("identity", {})
		var econ: Dictionary = c.get("economy", {})
		var mil: Dictionary = c.get("military", {})

		var col_arr = ident.get("country_color", [0.75, 0.25, 0.25, 1.0])
		var color := Color(0.75, 0.25, 0.25)
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
			var loc_mgr = null
			var main_loop = Engine.get_main_loop()
			if main_loop is SceneTree and main_loop.root != null and main_loop.root.has_node("LocalizationManager"):
				loc_mgr = main_loop.root.get_node("LocalizationManager")
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

		var c_name = ident.get("country_name", c.get("name_text", tag))
		var c_name_ru = ident.get("country_name_ru", c.get("name_text", c_name))

		var l_name = ident.get("leader_name", manifest_lead.get("leader_name", ""))
		var l_title = ident.get("leader_title", manifest_lead.get("title", "Глава государства"))
		var l_ideology = ident.get("ruling_ideology", manifest_c.get("ruling_ideology", c.get("ruling_party", "Neutral")))
		var l_portrait = portrait_p

		# Поиск портрета среди лидеров
		if (l_portrait.is_empty() or l_portrait == "res://icon.svg") and c.has("leaders") and c["leaders"] is Array:
			for lead in c["leaders"]:
				if lead is Dictionary:
					if l_name.is_empty() or l_name == "UNKNOWN":
						l_name = str(lead.get("name", lead.get("id", "UNKNOWN")))
					if l_title.is_empty():
						l_title = str(lead.get("desc", "Лидер державы"))

					var p_large := ""
					if lead.has("picture"):
						p_large = str(lead["picture"])
					elif lead.has("country_leader"):
						var cl = lead["country_leader"]
						if cl is Dictionary:
							p_large = str(cl.get("picture", ""))
						elif cl is Array and not cl.is_empty() and cl[0] is Dictionary:
							p_large = str(cl[0].get("picture", ""))

					if p_large.is_empty() and lead.has("civilian"):
						var civ_val = lead["civilian"]
						if civ_val is Dictionary:
							p_large = str(civ_val.get("large", ""))
						elif civ_val is Array and not civ_val.is_empty() and civ_val[0] is Dictionary:
							p_large = str(civ_val[0].get("large", ""))

					if not p_large.is_empty() and p_large != "GFX_leader_unknown":
						var valid_p = p_large
						var check_paths: Array[String] = [
							"res://" + valid_p,
							"res://assets/" + valid_p,
							"res://assets/gfx/leaders/" + valid_p
						]
						var lead_id = str(lead.get("id", lead.get("name_key", "")))
						if not lead_id.is_empty():
							check_paths.append("res://assets/gfx/leaders/%s/%s.png" % [tag, lead_id])
							check_paths.append("res://assets/gfx/leaders/%s/%s.png" % [tag, lead_id.to_lower()])

						var base_fn = valid_p.get_file()
						var cleaned_fn = base_fn.replace("Portrait_", "").replace("_TNO", "").replace("_tno", "")
						check_paths.append("res://assets/gfx/leaders/%s/%s" % [tag, cleaned_fn])
						check_paths.append("res://assets/gfx/leaders/%s/%s" % [tag, cleaned_fn.to_lower()])

						var found_valid := false
						for cp in check_paths:
							if ResourceLoader.exists(cp) or FileAccess.file_exists(cp):
								l_portrait = cp
								found_valid = true
								break

						if not found_valid:
							l_portrait = p_large

					var cl_val = lead.get("country_leader")
					var lead_ideo := ""
					if cl_val is Dictionary:
						lead_ideo = str(cl_val.get("ideology", ""))
					elif cl_val is Array and not cl_val.is_empty() and cl_val[0] is Dictionary:
						lead_ideo = str(cl_val[0].get("ideology", ""))

					if not lead_ideo.is_empty() and l_ideology == "Neutral":
						l_ideology = lead_ideo
					break

		if l_name.is_empty():
			l_name = "UNKNOWN"

		var dossier = {
			"tag": tag,
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

		cached_dossiers[tag] = dossier
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
		cached_dossiers[tag] = dossier
		return dossier

	return {}
