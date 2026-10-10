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
						l_name = str(lead.get("name_text", lead.get("name", lead.get("id", "UNKNOWN"))))
					if l_title.is_empty():
						l_title = str(lead.get("desc", "Лидер державы"))

					var p_large := ""
					if lead.has("portraits") and lead["portraits"] is Dictionary:
						var pts = lead["portraits"]
						if pts.has("civilian") and pts["civilian"] is Dictionary:
							p_large = str(pts["civilian"].get("large", ""))
						elif pts.has("army") and pts["army"] is Dictionary:
							p_large = str(pts["army"].get("large", ""))

					if p_large.is_empty() and lead.has("picture"):
						p_large = str(lead["picture"])
					elif p_large.is_empty() and lead.has("country_leader"):
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

		var overrides = _get_canonical_overrides(tag)
		if not overrides.is_empty():
			for k in overrides:
				dossier[k] = overrides[k]

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

	# 3. Детерминированный фоллбэк для малых наций без country.json (DEF-17)
	var generated = _generate_fallback_dossier(tag, manifest_data)
	if not generated.is_empty():
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
	var loc_mgr = null
	var main_loop = Engine.get_main_loop()
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
	var l_portrait: String = ""
	var leader_dir_path: String = "res://assets/gfx/leaders/%s" % clean_tag

	if DirAccess.dir_exists_absolute(leader_dir_path):
		var dir = DirAccess.open(leader_dir_path)
		if dir != null:
			dir.list_dir_begin()
			var fn = dir.get_next()
			var candidates: Array[String] = []
			while fn != "":
				if not dir.current_is_dir() and fn.ends_with(".png") and not fn.ends_with(".import"):
					candidates.append(fn)
				fn = dir.get_next()

			if not candidates.is_empty():
				candidates.sort()
				var idx = abs(clean_tag.hash()) % candidates.size()
				var chosen_file = candidates[idx]
				l_portrait = leader_dir_path.path_join(chosen_file)

				var raw_lead = chosen_file.trim_suffix(".png")
				if raw_lead.begins_with(clean_tag + "_"):
					raw_lead = raw_lead.trim_prefix(clean_tag + "_")
				elif raw_lead.begins_with("Portrait_" + clean_tag + "_"):
					raw_lead = raw_lead.trim_prefix("Portrait_" + clean_tag + "_")
				elif raw_lead.begins_with("Portrait_"):
					raw_lead = raw_lead.trim_prefix("Portrait_")

				raw_lead = raw_lead.replace("_TNO", "").replace("_tno", "").replace("_", " ").strip_edges()
				if not raw_lead.is_empty():
					l_name = raw_lead

	if l_portrait.is_empty():
		var fallback_portraits = [
			"res://assets/gfx/leaders/USA/USA_Richard_Nixon.png",
			"res://assets/gfx/leaders/GER/Portrait_Germany_Adolf_Hitler.png",
			"res://assets/gfx/leaders/JAP/Portrait_Japan_Ino_Hiroya.png",
			"res://assets/gfx/leaders/ITA/ITA_Gian_Galeazzo_Ciano.png"
		]
		for fp in fallback_portraits:
			if ResourceLoader.exists(fp) or FileAccess.file_exists(fp):
				l_portrait = fp
				break
		if l_portrait.is_empty():
			l_portrait = "res://icon.svg"

	if l_name == "UNKNOWN":
		l_name = "%s Временное Руководство" % c_name_ru

	# 3. Детерминированный цвет на основе хэша тега
	var h = abs(clean_tag.hash())
	var col_r = float((h & 0xFF)) / 255.0 * 0.6 + 0.2
	var col_g = float(((h >> 8) & 0xFF)) / 255.0 * 0.6 + 0.2
	var col_b = float(((h >> 16) & 0xFF)) / 255.0 * 0.6 + 0.2
	var color = Color(col_r, col_g, col_b)

	var h_seed = abs(clean_tag.hash())
	var gdp = 2.0 + float(h_seed % 15)
	var manpower = 15000 + (h_seed % 35000)
	var factories = 3 + (h_seed % 8)

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


static func _get_canonical_overrides(tag: String) -> Dictionary:
	match tag:
		"USA":
			return {
				"name": "the United States of America",
				"name_ru": "Соединённые Штаты Америки",
				"leader_name": "Ричард Никсон",
				"leader_title": "37-й Президент Соединённых Штатов",
				"portrait_path": "res://assets/gfx/leaders/USA/USA_Richard_Nixon.png",
				"color": Color(0.20, 0.40, 0.85),
				"theater": "theater_superpowers",
				"difficulty_rating": "●●○○○ (УМЕРЕННАЯ)",
				"starting_gdp": 280.0,
				"starting_manpower": 650000,
				"starting_factories": 310,
				"traits": ["Мастер кулуарных интриг", "Альянс ОФН", "Расколотый конгресс", "Борьба за гражданские права"],
				"lore": "Оплот свободного мира после горького поражения во Второй мировой войне. Под руководством Никсона Америка сдерживает экспансию Германии и Японии в прокси-войнах (Южная Африка), пока в Вашингтоне разгорается ожесточенная битва коалиции R-D и пакта NPP за Закон о гражданских правах и будущее демократии.",
				"geopolitical_bloc": "ОФН (Организация Свободных Наций)"
			}
		"GER":
			return {
				"name": "Greater German Reich",
				"name_ru": "Великогерманский Рейх",
				"leader_name": "Адольф Гитлер",
				"leader_title": "Фюрер Великогерманского Рейха",
				"portrait_path": "res://assets/gfx/leaders/GER/GER_adolf_hitler.png",
				"color": Color(0.48, 0.28, 0.18),
				"theater": "theater_superpowers",
				"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
				"starting_gdp": 148.5,
				"starting_manpower": 850000,
				"starting_factories": 240,
				"traits": ["Дряхлеющий диктатор", "Культ Вождя", "Архитектор Нового Порядка", "Смертельный кризис престолонаследия"],
				"lore": "Январь 1962 года. Адольф Гитлер слабеет с каждым днем в сумрачных залах Зала Народа в столице мира Германии. За его спиной четыре могущественные клики — бюрократы Бормана, милитаристы Геринга, реформаторы Шпеера и фанатики Гейдриха — делят власть и готовят дивизии к неизбежной Немецкой Гражданской Войне. Экономика Рейха скована миллионами рабов и провалом гигантских проектов Атлантропы.",
				"geopolitical_bloc": "Einheitspakt (Пакт Единства)"
			}
		"JAP":
			return {
				"name": "Empire of Japan",
				"name_ru": "Великая Японская Империя",
				"leader_name": "Ино Хироя",
				"leader_title": "Премьер-министр Японской Империи",
				"portrait_path": "res://assets/gfx/leaders/JAP/JAP_Ino_Hiroya.png",
				"color": Color(0.85, 0.25, 0.25),
				"theater": "theater_superpowers",
				"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
				"starting_gdp": 195.0,
				"starting_manpower": 720000,
				"starting_factories": 210,
				"traits": ["Ставленник дзайбацу", "Императорская лояльность", "Азиатская гегемония", "Уязвимость биржи Ясуда"],
				"lore": "Владычица Восточной Азии и Тихого океана. Японская Империя держит сотни миллионов людей в колониальной Сфере Сопроцветания. Однако хрупкое благополучие Токио держится на коррупционной паутине кланов дзайбацу. Неизбежное банкротство банка Ясуда грозит обрушить экономику державы, спровоцировать падение кабинета министров и открыть путь к борьбе между гражданскими бюрократами и фанатичной армией.",
				"geopolitical_bloc": "Дайтоа Кёэйкэн (Сфера Сопроцветания)"
			}
		"ITA":
			return {
				"name": "Italian Empire",
				"name_ru": "Итальянская Империя",
				"leader_name": "Галеаццо Чиано",
				"leader_title": "Министр иностранных дел / Преемник Дуче",
				"portrait_path": "res://assets/gfx/leaders/ITA/ITA_Galeazzo_Ciano.png",
				"color": Color(0.18, 0.55, 0.35),
				"theater": "theater_europe",
				"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
				"starting_gdp": 68.0,
				"starting_manpower": 320000,
				"starting_factories": 85,
				"traits": ["Зять Дуче", "Архитектор Триумвирата", "Тайный реформатор", "Битва за Средиземноморье"],
				"lore": "Победительница во Второй мировой войне, Римская Империя Муссолини объединила Средиземноморье в блок Триумвирата с Иберией и Турцией. Но проект Атлантропы превратил Адриатику в солончак, уничтожил морскую торговлю, а фашистская партия разрывается между консерваторами Скорцы и реформаторами Чиано. Скорая смерть дряхлого Муссолини поставит Италию на грань демократической революции или военного путча.",
				"geopolitical_bloc": "Триумвират (Средиземноморский пакт)"
			}
		"IBR":
			return {
				"name": "Iberian Union",
				"name_ru": "Иберийский Союз",
				"leader_name": "Франсиско Франко",
				"leader_title": "Каудильо Иберийского Союза",
				"portrait_path": "res://assets/gfx/leaders/IBR/IBR_Francisco_Franco.png",
				"color": Color(0.75, 0.60, 0.20),
				"theater": "theater_europe",
				"difficulty_rating": "●●●●○ (ВЫСОКАЯ)",
				"starting_gdp": 45.0,
				"starting_manpower": 280000,
				"starting_factories": 55,
				"traits": ["Каудильо Пиренеев", "Неустойчивый дуумвират", "Борьба с террором ETA", "Ядерная программа Иберии"],
				"lore": "Шаткий конфедеративный союз Испании и Португалии, скрепленный соглашением генерала Франко и премьера Салазара. Страну сотрясают этнические волнения басков и каталонцев, террористические акты ETA и экономическая изоляция. В случае смерти одного из лидеров Союз рискует распасться в пламени Иберийской Гражданской Войны.",
				"geopolitical_bloc": "Триумвират (Иберо-Итальянский пакт)"
			}
		"ENG":
			return {
				"name": "Kingdom of England",
				"name_ru": "Королевство Англия (Коллаборационисты)",
				"leader_name": "Эндрю Фаунтейн",
				"leader_title": "Премьер-министр Королевства Англия",
				"portrait_path": "res://assets/gfx/leaders/ENG/ENG_Andrew_Fountaine.png",
				"color": Color(0.70, 0.20, 0.20),
				"theater": "theater_europe",
				"difficulty_rating": "●●●●○ (ВЫСОКАЯ)",
				"starting_gdp": 38.0,
				"starting_manpower": 140000,
				"starting_factories": 48,
				"traits": ["Лондонский коллаборационист", "Марионетка Пакта", "Тень восстания HMMLR", "Расколотая Британия"],
				"lore": "После вторжения сил Оси во время операции 'Морской лев' Великобритания была расчленена. В Лондоне правит коллаборационистский режим под скипетром лояльного немцам короля Эдварда VIII. Однако на севере и западе зреет подпольное пламя Сопротивления Её Величества (HMMLR), готовое поднять всеобщее восстание при первом же кризисе в Германии.",
				"geopolitical_bloc": "Einheitspakt (Британский протекторат)"
			}
		"BRG":
			return {
				"name": "SS-Ordensstaat Burgund",
				"name_ru": "Орденсштаат Бургундия (СС)",
				"leader_name": "Генрих Гиммлер",
				"leader_title": "Рейхсфюрер СС / Правитель Орденсштаата",
				"portrait_path": "res://assets/gfx/leaders/BRG/BRG_Heinrich_Himmler.png",
				"color": Color(0.12, 0.12, 0.18),
				"theater": "theater_europe",
				"difficulty_rating": "●●●●● (ЭКСТРЕМАЛЬНАЯ)",
				"starting_gdp": 25.0,
				"starting_manpower": 120000,
				"starting_factories": 60,
				"traits": ["Архитектор Черного Ордена", "Спартанский тоталитаризм", "План атомного апокалипсиса", "Тайные бункеры"],
				"lore": "Самое мрачное тоталитарное государство на планете. Выделенная Гитлером земля превращена Гиммлером в циклопический концлагерь спартанского типа. Под прикрытием жесточайшей дисциплины Бургундия ведет глобальные подрывные операции во всех сверхдержавах с единственной целью: спровоцировать глобальную ядерную войну ради 'очищения арийской расы'.",
				"geopolitical_bloc": "Бургундская Система (Черное Солнце)"
			}
		"TUR":
			return {
				"name": "Republic of Turkey",
				"name_ru": "Турецкая Республика",
				"leader_name": "Исмет Инёню",
				"leader_title": "Президент Турецкой Республики",
				"portrait_path": "res://assets/gfx/leaders/TUR/TUR_Ismet_Inonu.png",
				"color": Color(0.65, 0.25, 0.25),
				"theater": "theater_europe",
				"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
				"starting_gdp": 32.0,
				"starting_manpower": 260000,
				"starting_factories": 42,
				"traits": ["Второй человек Республики", "Средиземноморские амбиции", "Кемалистский порядок", "Итало-турецкое соперничество"],
				"lore": "Участник Триумвирата, получивший земли в Леванте и Закавказье после падения союзников. Но Анкара недовольна итальянским доминированием в Средиземноморье. Стареющий Инёню сталкивается с растущим давлением военных ультранационалистов Алпарслана Тюркеша и кризисом на Ближнем Востоке.",
				"geopolitical_bloc": "Триумвират (Средиземноморский пакт)"
			}
		"GNG":
			return {
				"name": "State of Guangdong",
				"name_ru": "Государство Гуандун (Корпорации)",
				"leader_name": "Масахару Мацусита",
				"leader_title": "Глава Совета Директоров / Президент Matsushita",
				"portrait_path": "res://assets/gfx/leaders/GNG/GNG_matsushita_masaharu.png",
				"color": Color(0.25, 0.75, 0.65),
				"theater": "theater_sphere",
				"difficulty_rating": "●●●●○ (ВЫСОКАЯ)",
				"starting_gdp": 28.5,
				"starting_manpower": 95000,
				"starting_factories": 68,
				"traits": ["Корпоративный олигарх", "Высокотехнологичный анклав", "Кэмпэйтай против триад", "Жажда сверхприбыли"],
				"lore": "Уникальный полигон корпоративного капитализма в Южном Китае. Вся власть разделена между электронными мегакорпорациями: Sony (Морита), Matsushita, Yasuda и Cheung Kong. Под неоновыми вывесками Гонконга и Гуанчжоу кипит жестокая эксплуатация рабочих, постоянные войны триад и интриги японского надзора.",
				"geopolitical_bloc": "Сфера Сопроцветания (Корпоративный доминион)"
			}
		"CHI":
			return {
				"name": "Republic of China",
				"name_ru": "Китайская Республика (Реорганизованная)",
				"leader_name": "Гао Цзунъу",
				"leader_title": "Президент Китайской Республики",
				"portrait_path": "res://assets/gfx/leaders/CHI/CHI_gao_zongwu.png",
				"color": Color(0.85, 0.70, 0.25),
				"theater": "theater_sphere",
				"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
				"starting_gdp": 72.0,
				"starting_manpower": 1200000,
				"starting_factories": 90,
				"traits": ["Осторожный реформатор", "Японское ярмо", "Тайная модернизация", "Грядущая Война за Освобождение"],
				"lore": "Нанкинское правительство внешне демонстрирует полную покорность Токио. Но президент Гао Цзунъу ведет величайшую в истории конспиративную игру: втайне модернизирует промышленность, копит оружие и объединяет китайский народ ради неминуемой Войны за Освобождение Китая против японских захватчиков.",
				"geopolitical_bloc": "Сфера Сопроцветания (Поднебесная)"
			}
		"MAN":
			return {
				"name": "Empire of Manchuria",
				"name_ru": "Маньчжоу-Го (Империя Маньчжурия)",
				"leader_name": "Айсиньгёро Пу И",
				"leader_title": "Император Маньчжурии (Кандэ)",
				"portrait_path": "res://assets/gfx/leaders/MAN/MAN_aisin_gioro_puyi.png",
				"color": Color(0.80, 0.65, 0.15),
				"theater": "theater_sphere",
				"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
				"starting_gdp": 34.0,
				"starting_manpower": 350000,
				"starting_factories": 72,
				"traits": ["Последний император", "Заложник Квантунской армии", "Индустриальное сердце Сферы", "Подавленный ропот"],
				"lore": "Индустриальная цитадель Японской Империи на материке. Император Пу И правит лишь номинально — реальная власть принадлежит командующему Квантунской армией и корпорациям Мансинь. Страна скована железной военной дисциплиной и страхом перед восстанием сибирских варлордов.",
				"geopolitical_bloc": "Сфера Сопроцветания (Квантунский протекторат)"
			}
		"THA":
			return {
				"name": "Kingdom of Thailand",
				"name_ru": "Королевство Таиланд",
				"leader_name": "Плек Пибунсонграм",
				"leader_title": "Премьер-министр и фельдмаршал",
				"portrait_path": "res://assets/gfx/leaders/THA/THA_Plaek_Phibunsongkhram.png",
				"color": Color(0.30, 0.55, 0.70),
				"theater": "theater_sphere",
				"difficulty_rating": "●●○○○ (НИЗКАЯ)",
				"starting_gdp": 18.0,
				"starting_manpower": 160000,
				"starting_factories": 28,
				"traits": ["Тайский модернизатор", "Равноправный союзник Токио", "Милитаристская рулетка", "Королевский баланс"],
				"lore": "Единственное суверенное королевство Юго-Восточной Азии, добровольно вступившее в союз с Японией. Фельдмаршал Пибун проводит политику национальной гордости и модернизации, лавируя между японским диктатом и армейскими заговорами.",
				"geopolitical_bloc": "Сфера Сопроцветания (Суверенный союзник)"
			}
		"YUN":
			return {
				"name": "Yunnan",
				"name_ru": "Юньнань (Юго-Западный Варлорд)",
				"leader_name": "Лу Хан",
				"leader_title": "Губернатор провинции Юньнань",
				"portrait_path": "res://assets/gfx/leaders/YUN/YUN_lu_han.png",
				"color": Color(0.45, 0.60, 0.40),
				"theater": "theater_sphere",
				"difficulty_rating": "●●●●○ (ВЫСОКАЯ)",
				"starting_gdp": 12.0,
				"starting_manpower": 180000,
				"starting_factories": 18,
				"traits": ["Горный варлорд", "Опиумная казна", "Угроза возвращения Лун Юня", "Оружейные арсеналы Бирмы"],
				"lore": "Труднодоступная горная провинция Китая. Генерал Лу Хан поддерживает формальный мир с Нанкином и Японией, однако в домашнем заключении томится свергнутый тиран Лун Юнь — бескомпромиссный националист, мечтающий поднять Великое Азиатское Восстание и утопить оккупантов в крови.",
				"geopolitical_bloc": "Сфера Сопроцветания (Китайский варлорд)"
			}
		"SPE":
			return {
				"name": "Reich of Albert Speer (Reformists)",
				"name_ru": "Германия (Альберт Шпеер / Реформаторы)",
				"leader_name": "Альберт Шпеер",
				"leader_title": "Рейхсминистр вооружений / Лидер Реформаторов",
				"portrait_path": "res://data/countries/GER/leaders/portraits/GER_albert_speer.png",
				"color": Color(0.85, 0.65, 0.20),
				"theater": "theater_gcw",
				"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
				"starting_gdp": 85.0,
				"starting_manpower": 250000,
				"starting_factories": 110,
				"traits": ["Архитектор Рейха", "Либерализация рынка", "Поддержка студенчества", "Банда Четырёх"],
				"lore": "Главный архитектор Рейха, осознавший экономический тупик национал-социализма. Опираясь на прогрессивное студенчество, технократов и либеральных заговорщиков фон Трескова ('Банду Четырёх'), Шпеер обещает демонтировать рабство и спасти Рейх через модернизацию.",
				"geopolitical_bloc": "Einheitspakt (Реформаторы)"
			}
		"BOR":
			return {
				"name": "Reich of Martin Bormann (Party Bureaucracy)",
				"name_ru": "Германия (Мартин Борман / Партократы)",
				"leader_name": "Мартин Борман",
				"leader_title": "Партийный Секретарь НСДАП / Коричневое Преосвященство",
				"portrait_path": "res://data/countries/GER/leaders/portraits/GER_martin_bormann.png",
				"color": Color(0.60, 0.45, 0.25),
				"theater": "theater_gcw",
				"difficulty_rating": "●●○○○ (НИЗКАЯ)",
				"starting_gdp": 95.0,
				"starting_manpower": 380000,
				"starting_factories": 140,
				"traits": ["Коричневое преосвященство", "Аппаратная паутина", "Консервация статуса-кво", "Партийный фаворит"],
				"lore": "Теневой хозяин партийной канцелярии НСДАП. Борман контролирует партийных функционеров и гауляйтеров по всей Европе. Его программа — консервация наследия Гитлера, медленные умеренные корректировки и безжалостная зачистка политических конкурентов.",
				"geopolitical_bloc": "Einheitspakt (Партократы)"
			}
		"GOR":
			return {
				"name": "Reich of Hermann Göring (Militarist Junta)",
				"name_ru": "Германия (Герман Геринг / Милитаристы)",
				"leader_name": "Герман Геринг",
				"leader_title": "Рейхсмаршал Великогермании / Глава Люфтваффе",
				"portrait_path": "res://data/countries/GER/leaders/portraits/GER_hermann_goring.png",
				"color": Color(0.48, 0.52, 0.58),
				"theater": "theater_gcw",
				"difficulty_rating": "●●●●○ (ВЫСОКАЯ)",
				"starting_gdp": 90.0,
				"starting_manpower": 420000,
				"starting_factories": 150,
				"traits": ["Марионетка Шёрнера", "Экономика непрерывного грабежа", "Воздушный триумф", "Военная хунта"],
				"lore": "Рейхсмаршал опирается на генералитет Вермахта и фанатиков фельдмаршала Шёрнера. Милитаристы предлагают радикальный выход из кризиса: возобновление тотальной захватнической войны, аннексию Швейцарии, Швеции и восточных земель ради тотального грабежа ресурсов.",
				"geopolitical_bloc": "Einheitspakt (Милитаристы)"
			}
		"HEY":
			return {
				"name": "SS-Reich of Reinhard Heydrich",
				"name_ru": "Германия (Рейнхард Гейдрих / Черный Орден СС)",
				"leader_name": "Рейнхард Гейдрих",
				"leader_title": "Обергруппенфюрер СС / Пражский Мясник",
				"portrait_path": "res://data/countries/GER/leaders/portraits/GER_reinhard_heydrich.png",
				"color": Color(0.18, 0.18, 0.24),
				"theater": "theater_gcw",
				"difficulty_rating": "●●●●● (ЭКСТРЕМАЛЬНАЯ)",
				"starting_gdp": 70.0,
				"starting_manpower": 180000,
				"starting_factories": 95,
				"traits": ["Пражский мясник", "Орудие Гиммлера", "Черный орден", "Тайный бунт против Бургундии"],
				"lore": "Шеф РСХА и безжалостный палач Чехии. Номинально Гейдрих действует как марионетка Бургундии, однако осознав, что цель Гиммлера — уничтожение Германии в ядерном пламени, он оказывается перед мучительным выбором между верностью Ордену и спасением немецкой нации.",
				"geopolitical_bloc": "Burgundian Sphere (Черный Орден СС)"
			}
		"KOM":
			return {
				"name": "Komi Republic",
				"name_ru": "Республика Коми (Сыктывкар)",
				"leader_name": "Николай Вознесенский",
				"leader_title": "Президент Республики Коми",
				"portrait_path": "res://assets/gfx/leaders/KOM/KOM_Nikolai_Voznesensky.png",
				"color": Color(0.20, 0.75, 0.70),
				"theater": "theater_smuta",
				"difficulty_rating": "●●●●○ (ВЫСОКАЯ)",
				"starting_gdp": 16.5,
				"starting_manpower": 45000,
				"starting_factories": 22,
				"traits": ["Демократический экономист", "Расколотый Сыктывкарский парламент", "Осада радикалами", "Налеты Люфтваффе"],
				"lore": "Хрупкий островок демократии на северо-востоке европейской России. Президент Вознесенский пытается удержать республику от гражданской войны, пока левые социалисты (Суслов, Жданов) и правые фанатики-пассионарии (Гумилёв, Серов, Шафаревич, Таборицкий) открыто готовят вооруженные перевороты.",
				"geopolitical_bloc": "Демократический Центр (Россия)"
			}
		"WRS":
			return {
				"name": "West Russian Revolutionary Front",
				"name_ru": "Западнорусский Революционный Фронт",
				"leader_name": "Михаил Тухачевский",
				"leader_title": "Маршал Советского Союза / Главком Фронта",
				"portrait_path": "res://assets/gfx/leaders/WRS/WRS_Mikhail_Tukhachevsky.png",
				"color": Color(0.85, 0.15, 0.15),
				"theater": "theater_smuta",
				"difficulty_rating": "●●○○○ (УМЕРЕННАЯ)",
				"starting_gdp": 19.0,
				"starting_manpower": 95000,
				"starting_factories": 34,
				"traits": ["Красный Наполеон", "Теория глубокой операции", "Несгибаемая РККА", "Жажда реванша за Москву"],
				"lore": "Наследники непобедимой Красной Армии, удержавшие Архангельск после катастрофы Второй мировой войны и отразившие немецкий натиск во время Западнорусской войны. Маршалы Ворошилов и Тухачевский готовят советских солдат ко Второму Западному Походу ради освобождения Москвы от тевтонского ига.",
				"geopolitical_bloc": "Коминтерн / Красная Армия"
			}
		"OMS":
			return {
				"name": "All-Russian Black League",
				"name_ru": "Омск (Всероссийская Чёрная Лига)",
				"leader_name": "Дмитрий Карбышев",
				"leader_title": "Генералиссимус Чёрной Лиги",
				"portrait_path": "res://assets/gfx/leaders/OMS/OMS_Dmitry_Karbyshev.png",
				"color": Color(0.25, 0.25, 0.28),
				"theater": "theater_smuta",
				"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
				"starting_gdp": 15.0,
				"starting_manpower": 75000,
				"starting_factories": 28,
				"traits": ["Несломленный узник", "Идея Великого Суда", "Черные бригады возмездия", "Подземная крепость Сибири"],
				"lore": "Омск живет лишь одной целью — Великим Судом над Германией. Старый генерал Карбышев и его бескомпромиссный преемник Дмитрий Язов превратили город в тоталитарный военный лагерь. Здесь нет гражданской жизни: все ресурсы направлены на армию, циклопические бункеры и подготовку к тотальной войне на взаимное истребление.",
				"geopolitical_bloc": "Чёрная Лига (Великий Суд)"
			}
		"SVR":
			return {
				"name": "Ural Military District",
				"name_ru": "Свердловск (Уральский Военный Округ)",
				"leader_name": "Павел Батов",
				"leader_title": "Командующий Военным Округом / Генерал Армии",
				"portrait_path": "res://assets/gfx/leaders/SVR/SVR_Pavel_Batov.png",
				"color": Color(0.35, 0.55, 0.35),
				"theater": "theater_smuta",
				"difficulty_rating": "●●○○○ (НИЗКАЯ)",
				"starting_gdp": 21.0,
				"starting_manpower": 85000,
				"starting_factories": 38,
				"traits": ["Солдатский генерал", "Стальная дисциплина", "Служить России", "Уральский оборонный вал"],
				"lore": "Остатки советского генералитета на Урале во главе с легендарным комдивом Павлом Батовым. Здесь отвергли партийную идеологическую демагогию во имя железного принципа: 'Служить России'. Опираясь на заводы Свердловска и выучку офицеров, армия Батова готова железной рукой навести порядок на русской земле.",
				"geopolitical_bloc": "Вооруженные Силы России"
			}
		"TOM":
			return {
				"name": "Tomsk Intellectual Republic",
				"name_ru": "Томск (Город Интеллектуалов и Салонов)",
				"leader_name": "Борис Пастернак",
				"leader_title": "Президент Республики / Глава Салонов",
				"portrait_path": "res://assets/gfx/leaders/TOM/TOM_Boris_Pasternak.png",
				"color": Color(0.40, 0.65, 0.85),
				"theater": "theater_smuta",
				"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
				"starting_gdp": 18.5,
				"starting_manpower": 55000,
				"starting_factories": 30,
				"traits": ["Поэт и философ", "Гуманистическая демократия", "Четыре Салона", "Оазис сибирской культуры"],
				"lore": "Томск стал приютом для спасшейся русской интеллигенции, инженеров, ученых и художников. Под руководством поэта Бориса Пастернака создана уникальная салонная демократия: Декабристы борются за права человека, Модернисты — за технологический прогресс, Бастурма — за социальную справедливость, а Евразийцы — за сильную державу.",
				"geopolitical_bloc": "Сибирский Союз Культуры"
			}
		"NOV":
			return {
				"name": "Central Siberian Federation",
				"name_ru": "Новосибирск (Федерация Центральной Сибири)",
				"leader_name": "Александр Покрышкин",
				"leader_title": "Председатель Федерации / Маршал Авиации",
				"portrait_path": "res://assets/gfx/leaders/NOV/NOV_Alexander_Pokryshkin.png",
				"color": Color(0.30, 0.45, 0.75),
				"theater": "theater_smuta",
				"difficulty_rating": "●●○○○ (НИЗКАЯ)",
				"starting_gdp": 24.0,
				"starting_manpower": 90000,
				"starting_factories": 42,
				"traits": ["Ас и прагматик", "Альянс ВПК и генералов", "Корпорация Сибирь", "Хозяйственный расчет"],
				"lore": "Новосибирск объединил военную элиту маршала Покрышкина и промышленных магнатов ВПК. Вместо пустой идеологии здесь правят холодный расчет, экспорт ресурсов и скупка соседних территорий через экономическое доминирование. Противовесом олигархам выступает народное движение писателя Василия Шукшина.",
				"geopolitical_bloc": "Сибирская Федерация"
			}
		"BRY":
			return {
				"name": "Buryat Soviet Socialist Republic",
				"name_ru": "Бурятская ССР (Саблинский Идеализм)",
				"leader_name": "Валерий Саблин",
				"leader_title": "Председатель Революционного Военсовета",
				"portrait_path": "res://assets/gfx/leaders/BRY/BRY_Valery_Sablin.png",
				"color": Color(0.80, 0.25, 0.25),
				"theater": "theater_smuta",
				"difficulty_rating": "●●●●○ (ВЫСОКАЯ)",
				"starting_gdp": 12.0,
				"starting_manpower": 38000,
				"starting_factories": 18,
				"traits": ["Истинный ленинец", "Чистая революция", "Власть Советам", "Отвержение бюрократии"],
				"lore": "Молодой морской офицер Валерий Саблин поднял восстание против чекистской тирании Ягоды в Иркутске. На берегах Байкала он строит государство подлинного социализма, основанное на власти рабочих советов, свободе слова и вере в идеалы Ленина.",
				"geopolitical_bloc": "Истинный Союз Советов"
			}
		"SBA":
			return {
				"name": "Siberian Black Army",
				"name_ru": "Сибирская Чёрная Армия (Вольная Территория)",
				"leader_name": "Степан Валентеев",
				"leader_title": "Командующий Чёрной Армией",
				"portrait_path": "res://assets/gfx/leaders/SBA/SBA_Stepan_Valenteev.png",
				"color": Color(0.15, 0.15, 0.15),
				"theater": "theater_smuta",
				"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
				"starting_gdp": 14.5,
				"starting_manpower": 60000,
				"starting_factories": 24,
				"traits": ["Безвластие и воля", "Сибирский анархизм", "Черная гвардия советов", "Отказ от государства"],
				"lore": "Канск стал центром крупнейшего анархистского эксперимента в мировой истории. Здесь упразднены государственные институты, деньги и чиновники — вся власть принадлежит коммунам и синдикатам. Безопасность вольной Сибири защищает самоотверженная Чёрная Армия Степана Валентеева.",
				"geopolitical_bloc": "Вольная Федерация Анархистов"
			}
		"SAM":
			return {
				"name": "Committee for the Liberation of the Peoples of Russia",
				"name_ru": "Самара (КОНР / Русская Освободительная Армия)",
				"leader_name": "Андрей Власов",
				"leader_title": "Председатель КОНР / Командующий РОА",
				"portrait_path": "res://assets/gfx/leaders/SAM/SAM_Andrey_Vlasov.png",
				"color": Color(0.65, 0.55, 0.30),
				"theater": "theater_smuta",
				"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
				"starting_gdp": 17.0,
				"starting_manpower": 70000,
				"starting_factories": 26,
				"traits": ["Генерал-власовец", "Клеймо предательства", "Тайный план возмездия", "Тяжелая техника Вермахта"],
				"lore": "Русская Освободительная Армия (РОА) генерала Власова осела в Поволжье. Русские люди презирают власовцев как немецких прислужников, но сам Власов и его штабисты (Трухин, Малышкин) мечтают о дне, когда слабость Рейха позволит повернуть оружие против захватчиков.",
				"geopolitical_bloc": "КОНР (Самара)"
			}
		"TYU", "TYM":
			return {
				"name": "West Siberian People's Republic",
				"name_ru": "Тюмень (Западно-Сибирская Народная Республика)",
				"leader_name": "Лазарь Каганович",
				"leader_title": "Первый Секретарь ВКП(б)",
				"portrait_path": "res://assets/gfx/leaders/TYM/TYM_Lazar_Kaganovich.png",
				"color": Color(0.75, 0.12, 0.12),
				"theater": "theater_smuta",
				"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
				"starting_gdp": 16.0,
				"starting_manpower": 65000,
				"starting_factories": 28,
				"traits": ["Железный нарком", "Непоколебимый сталинист", "Пятилетки любой ценой", "Лагерный индустриальный фронт"],
				"lore": "Последняя цитадель несгибаемого сталинизма. Лазарь Каганович железной рукой проводит форсированную индустриализацию посреди болот и мерзлоты. Ценой жесточайшей дисциплины Тюмень кует сталь и танки для реванша, пока в обкоме назревает конфликт с прагматичным крылом Никиты Хрущёва.",
				"geopolitical_bloc": "ВКП(б) (Тюмень)"
			}
		"VYT":
			return {
				"name": "Russian Empire (Vyatka)",
				"name_ru": "Вятка (Русская Империя Владимира III)",
				"leader_name": "Владимир III",
				"leader_title": "Император и Самодержец Всероссийский",
				"portrait_path": "res://assets/gfx/leaders/VYT/VYT_Vladimir_III.png",
				"color": Color(0.20, 0.40, 0.70),
				"theater": "theater_smuta",
				"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
				"starting_gdp": 16.8,
				"starting_manpower": 58000,
				"starting_factories": 25,
				"traits": ["Законный Государь", "Монархическое возрождение", "Солидаризм НТС", "Раскаяние за сотрудничество"],
				"lore": "Наследник дома Романовых провозгласил возрождение Российской Империи в лесах Вятки. Великий князь Владимир стремится искупить вину за вынужденный союз с Германией и построить современную народную монархию, опираясь на солидаристов НТС и белое офицерство.",
				"geopolitical_bloc": "Российский Императорский Дом"
			}
		"IRK":
			return {
				"name": "Presidium of the Supreme Soviet",
				"name_ru": "Иркутск (Президиум Верховного Совета СССР)",
				"leader_name": "Генрих Ягода",
				"leader_title": "Генеральный Секретарь / Нарком Госбезопасности",
				"portrait_path": "res://assets/gfx/leaders/IRK/IRK_Genrikh_Yagoda.png",
				"color": Color(0.60, 0.15, 0.15),
				"theater": "theater_smuta",
				"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
				"starting_gdp": 15.5,
				"starting_manpower": 62000,
				"starting_factories": 27,
				"traits": ["Чекистский диктатор", "Аппарат террора НКВД", "Остатки советского Госплана", "Осада мятежниками"],
				"lore": "Официальный правопреемник прежнего советского руководства, превратившийся в чекистскую диктатуру. Генрих Ягода держит Восточную Сибирь железной хваткой спецслужб и трудовых лагерей, подавляя мятеж Саблина и готовясь восстановить Союз через тотальный контроль.",
				"geopolitical_bloc": "НКВД / Президиум СССР"
			}
		"MAG":
			return {
				"name": "Russian National Party",
				"name_ru": "Магадан (Русская Национальная Партия)",
				"leader_name": "Михаил Матковский",
				"leader_title": "Вождь РНП / Премьер-министр",
				"portrait_path": "res://assets/gfx/leaders/MAG/MAG_Mikhail_Matkovsky.png",
				"color": Color(0.35, 0.40, 0.50),
				"theater": "theater_smuta",
				"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
				"starting_gdp": 14.0,
				"starting_manpower": 42000,
				"starting_factories": 20,
				"traits": ["Прагматичный фашист", "Американская помощь (ОФН)", "Охотский плацдарм", "Конкуренция наёмников"],
				"lore": "Бывшие русские эмигранты из Харбина захватили порт Магадан. Отказавшись от слепого нацизма, Матковский проводит прагматичный курс, продавая ресурсы американцам и получая в ответ оружие ОФН, пока наёмник Митчелл Вербелл строит планы создания корпоративного государства.",
				"geopolitical_bloc": "Тихоокеанский Союз"
			}
		"AMR":
			return {
				"name": "All-Russian Fascist Party",
				"name_ru": "Амур (Всероссийская Фашистская Партия)",
				"leader_name": "Константин Родзаевский",
				"leader_title": "Верховный Вождь ВФП",
				"portrait_path": "res://assets/gfx/leaders/AMR/AMR_Konstantin_Rodzaevsky.png",
				"color": Color(0.30, 0.25, 0.25),
				"theater": "theater_smuta",
				"difficulty_rating": "●●●●○ (ВЫСОКАЯ)",
				"starting_gdp": 11.5,
				"starting_manpower": 36000,
				"starting_factories": 17,
				"traits": ["Слепой поклонник Рейха", "Чернорубашечники", "Параноидальный антисемитизм", "Дальневосточный фанатизм"],
				"lore": "Константин Родзаевский слепо скопировал худшие черты гитлеровского национал-социализма. В тайге Приамурья его чернорубашечники проводят чистки, надеясь заслужить благосклонность Берлина и Токио, в то время как паранойя Вождя медленно разрушает остатки рассудка.",
				"geopolitical_bloc": "ВФП (Харбинские фашисты)"
			}
		"CHT":
			return {
				"name": "Chita (White Army Junta)",
				"name_ru": "Чита (Забайкальское Белое Княжество)",
				"leader_name": "Михаил II",
				"leader_title": "Царь Всероссийский (Михаил Романов)",
				"portrait_path": "res://assets/gfx/leaders/CHT/CHT_Mikhail_II.png",
				"color": Color(0.60, 0.40, 0.20),
				"theater": "theater_smuta",
				"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
				"starting_gdp": 13.5,
				"starting_manpower": 48000,
				"starting_factories": 21,
				"traits": ["Царь поневоле", "Казачий атаман Семёнов", "Харбинские офицеры", "Тоска по Австралии"],
				"lore": "Австралийский эмигрант князь Михаил Романов был обманом привезен в Читу атаманом Григорием Семёновым и провозглашен марионеточным монархом. Пока Семёнов грабит край с помощью казачьих шашек, несчастный царь ищет способ освободиться от опеки атаманов и служить русскому народу.",
				"geopolitical_bloc": "Забайкальское Казачество"
			}
		"KEM":
			return {
				"name": "Principality of Kemerovo",
				"name_ru": "Кемерово (Княжество Русь / Рюриковичи)",
				"leader_name": "Рюрик II",
				"leader_title": "Великий Князь Всея Руси (Николай Крылов)",
				"portrait_path": "res://assets/gfx/leaders/KEM/KEM_Rurik_II.png",
				"color": Color(0.85, 0.50, 0.20),
				"theater": "theater_smuta",
				"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
				"starting_gdp": 15.0,
				"starting_manpower": 52000,
				"starting_factories": 23,
				"traits": ["Безумный Царь", "Княжеская дружина", "Синтез социализма и монархии", "Династический раскол"],
				"lore": "Бывший советский генерал Николай Крылов сошел с ума от ужасов войны и провозгласил себя прямым наследником Рюрика. В Кузбассе он создал причудливое языческо-социалистическое княжество с народными пирами и верной дружиной, пока его дети — Юрий и Лидия — делят будущую корону.",
				"geopolitical_bloc": "Княжество Рюриковичей"
			}
		_:
			return {}

