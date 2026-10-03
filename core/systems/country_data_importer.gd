class_name CountryDataImporter
extends RefCounted

##
## CountryDataImporter: Загрузчик стран, политических лидеров и партий TNO в Godot 4
## -------------------------------------------------------------------------------
## Считывает профили стран (data/countries/<TAG>/country_profile.json) и мастер-индекс
## (data/countries_index.json). Собирает экземпляры CountryState, LeaderResource и PartyData.
##

const COUNTRIES_INDEX_PATH: String = "res://data/countries_index.json"
const COUNTRIES_INDEX_FALLBACK: String = "res://data/countries/index.json"
const COUNTRY_PROFILE_TEMPLATE: String = "res://data/countries/%s/country_profile.json"
const COUNTRY_FALLBACK_TEMPLATE: String = "res://data/countries/%s/country.json"
const STARTING_COUNTRIES_PATH: String = "res://data/starting_countries_state.json"


## Загружает профиль страны, собирает лидерские ресурсы и возвращает CountryState
static func load_country(tag: String) -> CountryState:
	var clean_tag = tag.strip_edges().to_upper()
	var profile_path = COUNTRY_PROFILE_TEMPLATE % clean_tag

	var profile_data: Dictionary = {}

	# 1. Попытка загрузить country_profile.json
	if FileAccess.file_exists(profile_path):
		profile_data = _read_json_file(profile_path)
	elif FileAccess.file_exists(COUNTRY_FALLBACK_TEMPLATE % clean_tag):
		profile_data = _read_json_file(COUNTRY_FALLBACK_TEMPLATE % clean_tag)

	# 2. Если профиля нет на диске, пробуем starting_countries_state.json
	if profile_data.is_empty() and FileAccess.file_exists(STARTING_COUNTRIES_PATH):
		var all_start = _read_json_file(STARTING_COUNTRIES_PATH)
		if all_start.has(clean_tag):
			profile_data = all_start[clean_tag]

	# 3. Сборка объекта CountryState
	var state = CountryState.new()
	state.country_tag = clean_tag

	if profile_data.is_empty():
		push_warning("CountryDataImporter: Профиль для страны '%s' не найден. Возвращен базовый стейт." % clean_tag)
		state.country_name = clean_tag
		return state

	# Идентичность и локализованные имена
	var ident = profile_data.get("identity", profile_data)
	state.country_name = ident.get("country_name_ru", ident.get("country_name", ident.get("name", clean_tag)))
	state.ruling_ideology = ident.get("ruling_ideology", ident.get("ideology", "Neutral"))
	state.sub_ideology = ident.get("sub_ideology", "")
	state.leader_name = ident.get("leader_name", ident.get("leader", ""))
	state.leader_portrait_path = ident.get("leader_portrait_path", ident.get("portrait", "res://icon.svg"))

	# Цвет державы
	var col_raw = ident.get("country_color", ident.get("color", [0.5, 0.5, 0.5, 1.0]))
	if col_raw is Array and col_raw.size() >= 3:
		var a = float(col_raw[3]) if col_raw.size() >= 4 else 1.0
		state.country_color = Color(float(col_raw[0]), float(col_raw[1]), float(col_raw[2]), a)
	elif col_raw is Color:
		state.country_color = col_raw

	# Политические параметры и баланс легитимности
	var pol = profile_data.get("politics", profile_data)
	state.political_capital = float(pol.get("political_capital", 100.0))
	state.pc_gain_per_turn = float(pol.get("pc_gain_per_turn", 5.0))
	state.max_cap = int(pol.get("max_cap", 5))
	state.current_cap = int(pol.get("current_cap", 5))
	state.legitimacy = float(pol.get("legitimacy", 65.0))
	state.radicalization = float(pol.get("radicalization", 25.0))
	state.factions_loyalty = pol.get("factions_loyalty", state.factions_loyalty).duplicate(true)
	state.parliament_seats = pol.get("parliament_seats", state.parliament_seats).duplicate(true)
	state.total_parliament_seats = int(pol.get("total_parliament_seats", 400))

	# Сборка политических партий (PartyData)
	var parties_raw = pol.get("parties", profile_data.get("parties", []))
	state.initial_parties.clear()

	if parties_raw is Array:
		for p_info in parties_raw:
			if p_info is Dictionary:
				var p_obj = PartyData.from_dict(p_info)
				state.initial_parties.append(p_obj)
	elif parties_raw is Dictionary:
		for ideo_key in parties_raw.keys():
			var p_val = parties_raw[ideo_key]
			var p_dict = {
				"ideology_key": ideo_key,
				"party_name": ideo_key,
				"popularity": float(p_val) if (p_val is float or p_val is int) else 0.0,
				"is_ruling": (ideo_key == state.ruling_ideology)
			}
			if p_val is Dictionary:
				p_dict.merge(p_val, true)
			state.initial_parties.append(PartyData.from_dict(p_dict))

	# Сборка главы государства (Head of State)
	var hos_data = profile_data.get("head_of_state", ident.get("head_of_state", {}))
	if hos_data is Dictionary and not hos_data.is_empty():
		state.head_of_state = LeaderResource.from_dict(hos_data)
		if state.leader_name.is_empty():
			state.leader_name = state.head_of_state.leader_name
		if state.leader_portrait_path == "res://icon.svg":
			state.leader_portrait_path = state.head_of_state.portrait_path

	# Сборка членов кабинета министров
	var ministers_raw = profile_data.get("ministers", profile_data.get("cabinet_members", []))
	state.cabinet_members.clear()
	if ministers_raw is Array:
		for m_info in ministers_raw:
			if m_info is Dictionary:
				state.cabinet_members.append(LeaderResource.from_dict(m_info))

	# Сборка военачальников
	var commanders_raw = profile_data.get("commanders", profile_data.get("military_commanders", []))
	state.military_commanders.clear()
	if commanders_raw is Array:
		for c_info in commanders_raw:
			if c_info is Dictionary:
				state.military_commanders.append(LeaderResource.from_dict(c_info))

	# Экономика (Toolbox Theory)
	var eco = profile_data.get("economy", {})
	if not eco.is_empty():
		state.gdp_billions = float(eco.get("gdp_billions", state.gdp_billions))
		state.real_gdp_growth = float(eco.get("real_gdp_growth", state.real_gdp_growth))
		state.liquid_reserves_billions = float(eco.get("liquid_reserves_billions", state.liquid_reserves_billions))
		state.national_debt_billions = float(eco.get("national_debt_billions", state.national_debt_billions))
		state.central_bank_rate = float(eco.get("central_bank_rate", state.central_bank_rate))
		state.inflation_rate = float(eco.get("inflation_rate", state.inflation_rate))
		state.tax_rate = float(eco.get("tax_rate", state.tax_rate))
		state.military_spending_share = float(eco.get("military_spending_share", state.military_spending_share))
		state.civilian_spending_share = float(eco.get("civilian_spending_share", state.civilian_spending_share))
		state.admin_spending_share = float(eco.get("admin_spending_share", state.admin_spending_share))

	# Военные склады и промышленность
	var mil = profile_data.get("military", {})
	if not mil.is_empty():
		state.civilian_factories = int(mil.get("civilian_factories", state.civilian_factories))
		state.military_factories = int(mil.get("military_factories", state.military_factories))
		state.consumer_goods_ratio = float(mil.get("consumer_goods_ratio", state.consumer_goods_ratio))
		state.manpower_pool = int(mil.get("manpower_pool", state.manpower_pool))
		state.infantry_weapons_stockpile = int(mil.get("infantry_weapons_stockpile", state.infantry_weapons_stockpile))
		state.heavy_equipment_stockpile = int(mil.get("heavy_equipment_stockpile", state.heavy_equipment_stockpile))
		state.army_readiness = float(mil.get("army_readiness", state.army_readiness))
		state.army_morale = float(mil.get("army_morale", state.army_morale))
		state.war_support_percent = float(mil.get("war_support_percent", mil.get("war_support", state.war_support_percent)))

	# Нарратив
	var narr = profile_data.get("narrative", {})
	if not narr.is_empty():
		var acts = narr.get("active_directives", [])
		for a in acts: state.active_directives.append(str(a))
		var comps = narr.get("completed_directives", [])
		for c in comps: state.completed_directives.append(str(c))
		state.story_flags = narr.get("story_flags", state.story_flags).duplicate(true)

	# Национальные духи и идеи
	var raw_spirits = pol.get("national_spirits", profile_data.get("national_spirits", profile_data.get("ideas", [])))
	state.national_spirits.clear()
	if raw_spirits is Array:
		for sp in raw_spirits:
			if sp is Dictionary:
				state.national_spirits.append(sp.duplicate(true))

	# Матрица законов общества
	var raw_laws = pol.get("societal_laws", profile_data.get("societal_laws", profile_data.get("laws", [])))
	state.societal_laws.clear()
	if raw_laws is Array:
		for lw in raw_laws:
			if lw is Dictionary:
				state.societal_laws.append(lw.duplicate(true))

	_ensure_authentic_tno_politics(state)

	return state


static func _ensure_authentic_tno_politics(state: CountryState) -> void:
	var tag = state.country_tag.to_upper()
	
	# 1. Национальные духи
	if state.national_spirits.is_empty():
		if tag in ["GER", "SPE", "BOR", "GOR", "HEY", "BGR", "SGR", "GGR", "HGR"]:
			state.national_spirits = [
				{
					"id": "spirit_erhard_miracle",
					"name": "Экономическое Чудо Эрхарда",
					"icon": "res://assets/gfx/interface/industrial_capacity_icon.png",
					"desc": "Послевоенный инвестиционный бум сменился застоем, мегапроектами и рабским трудом.\nВВП: $148.5 млрд\nЭффективность фабрик: +10%\nИнфляция: 4.8%"
				},
				{
					"id": "spirit_succession_crisis",
					"name": "Агония и Кризис Престолонаследия",
					"icon": "res://assets/gfx/interface/war_support_icon.png",
					"desc": "Фюрер дряхлеет на глазах. Четыре фракции готовят армии к неизбежной бойне за Рейхсканцелярию.\nПолитический капитал: -15%\nСтабильность: -20%"
				},
				{
					"id": "spirit_fractured_wehrmacht",
					"name": "Расколотый Офицерский Корпус",
					"icon": "res://assets/gfx/interface/manpower_icon.png",
					"desc": "Генералитет расколот между прусскими консерваторами, фанатиками НСДАП и реформаторами фон Трескова.\nБоеготовность: 75%\nСтоимость армейских директив: +10%"
				},
				{
					"id": "spirit_shadow_of_slavery",
					"name": "Тень Рабского Труда",
					"icon": "res://assets/gfx/interface/war_support_icon.png",
					"desc": "Миллионы подневольных рабочих из оккупированного востока сковывают модернизацию Рейха.\nОбщественное недовольство: +15%\nСтоимость ТНП: -10%"
				}
			]
		elif tag in ["USA"]:
			state.national_spirits = [
				{
					"id": "spirit_bastion_of_liberty",
					"name": "Бастион Свободного Мира (OFN)",
					"icon": "res://assets/gfx/interface/war_support_icon.png",
					"desc": "Соединенные Штаты возглавляют альянс демократий против нацистского и японского империализма.\nЛегитимность: 85%\nПриток дипломатического влияния: +15%"
				},
				{
					"id": "spirit_jim_crow",
					"name": "Сегрегация и Законы Джима Кроу",
					"icon": "res://assets/gfx/interface/manpower_icon.png",
					"desc": "Глубокий раскол нации по вопросу расовой сегрегации. Борьба за Закон о гражданских правах сотрясает Сенат.\nОбщественная радикализация: +20%"
				},
				{
					"id": "spirit_rd_coalition",
					"name": "Двухпартийная Коалиция R-D",
					"icon": "res://assets/gfx/interface/industrial_capacity_icon.png",
					"desc": "Хрупкий альянс республиканцев и демократов противостоит националистической коалиции NPP.\nПолитический капитал: +5/ход"
				}
			]
		elif tag in ["WRS", "KOM", "OMS", "SVR", "SAM", "NOV", "TYU", "IRK", "CHT", "MAG", "KEM", "VYT", "BRY", "SBA", "ONE", "ORE", "ZLT", "DRL", "MGN"]:
			state.national_spirits = [
				{
					"id": "spirit_terror_bombings",
					"name": "Шрамы Налетов Люфтваффе",
					"icon": "res://assets/gfx/interface/war_support_icon.png",
					"desc": "Периодические бомбардировки с рейхскомиссариатов сковывают тыловое производство, но закаляют дух защитников.\nЭффективность фабрик: -15%\nОпыт дивизий: +10%"
				},
				{
					"id": "spirit_smuta_law",
					"name": "Законы Русской Смуты",
					"icon": "res://assets/gfx/interface/industrial_capacity_icon.png",
					"desc": "Границы зыбки, рейды за оружием и пленными — норма выживания региональных варлордов.\nДоступ к оперативным набегам открыт\nЗатраты на мобилизацию: -20%"
				},
				{
					"id": "spirit_black_market_weapons",
					"name": "Черный Рынок Оружия и Контрабанда",
					"icon": "res://assets/gfx/interface/manpower_icon.png",
					"desc": "Трофейные карабины Вермахта и американские винтовки OFN стекаются на арсеналы через границу.\nПриток снаряжения: +400/ход"
				}
			]
		else:
			# Общие аутентичные духи эпохи Холодной войны
			state.national_spirits = [
				{
					"id": "spirit_cold_war_tension",
					"name": "Эхо Глобальной Холодной Войны",
					"icon": "res://assets/gfx/interface/war_support_icon.png",
					"desc": "Держава лавирует между блоками сверхдержав в тени ядерного противостояния.\nНапряженность DEFCON влияет на торговлю."
				},
				{
					"id": "spirit_economic_reconstruction",
					"name": "Структурное Развитие Экономики",
					"icon": "res://assets/gfx/interface/industrial_capacity_icon.png",
					"desc": "Промышленный сектор требует постоянных государственных субсидий и сбалансированного бюджета."
				}
			]

	# 2. Законы и развитие общества (Societal Development)
	if state.societal_laws.is_empty():
		if tag in ["GER", "SPE", "BOR", "GOR", "HEY", "BGR", "SGR", "GGR", "HGR"]:
			state.societal_laws = [
				{"name": "Трудовые отношения", "value": "Подневольный / рабский труд", "tier": 1, "max_tier": 5},
				{"name": "Свобода печати", "value": "Тотальная цензура Рейхспрессы", "tier": 1, "max_tier": 5},
				{"name": "Политическая система", "value": "Однопартийная диктатура НСДАП", "tier": 1, "max_tier": 5},
				{"name": "Военная повинность", "value": "Всеобщий призыв Рейха", "tier": 4, "max_tier": 5},
				{"name": "Права меньшинств", "value": "Нюрнбергское расовое право", "tier": 1, "max_tier": 5},
				{"name": "Медицинское обеспечение", "value": "Расовая селективная медицина", "tier": 2, "max_tier": 5}
			]
		elif tag in ["USA"]:
			state.societal_laws = [
				{"name": "Трудовое законодательство", "value": "Защищенные профсоюзы (AFL-CIO)", "tier": 4, "max_tier": 5},
				{"name": "Свобода печати", "value": "Свободная пресса (Первая поправка)", "tier": 5, "max_tier": 5},
				{"name": "Политическая система", "value": "Двухпартийная демократия", "tier": 5, "max_tier": 5},
				{"name": "Военная повинность", "value": "Селективная служба / Призыв", "tier": 3, "max_tier": 5},
				{"name": "Гражданские права", "value": "Сегрегация в процессе реформ", "tier": 2, "max_tier": 5},
				{"name": "Медицинское обеспечение", "value": "Страховая частная медицина", "tier": 3, "max_tier": 5}
			]
		else:
			# Для варлордов и остальных стран
			state.societal_laws = [
				{"name": "Военная мобилизация", "value": "Всеобщая милитаризация", "tier": 4, "max_tier": 5},
				{"name": "Экономическая модель", "value": "Военный социализм / Госплан", "tier": 4, "max_tier": 5},
				{"name": "Политический контроль", "value": "Чрезвычайные тройки госбезопасности", "tier": 5, "max_tier": 5},
				{"name": "Свобода печати", "value": "Фронтовая агитация и цензура", "tier": 1, "max_tier": 5},
				{"name": "Торговый режим", "value": "Черный рынок и бартерный обмен", "tier": 2, "max_tier": 5},
				{"name": "Права трудящихся", "value": "Трудовая повинность фронта", "tier": 2, "max_tier": 5}
			]



## Возвращает локализованный список всех доступных стран для экрана выбора нации
static func get_available_nations() -> Array[Dictionary]:
	var nations: Array[Dictionary] = []
	var index_data: Array = []

	var target_index_path = COUNTRIES_INDEX_PATH
	if not FileAccess.file_exists(target_index_path):
		if FileAccess.file_exists(COUNTRIES_INDEX_FALLBACK):
			target_index_path = COUNTRIES_INDEX_FALLBACK
		else:
			push_warning("CountryDataImporter: Индекс стран не найден!")
			return nations

	var raw_data = _read_json_file(target_index_path)
	if raw_data is Array:
		index_data = raw_data
	elif raw_data is Dictionary:
		index_data = raw_data.get("countries", raw_data.values())

	for item in index_data:
		if not (item is Dictionary):
			continue

		var tag = item.get("tag", item.get("country_tag", "")).to_upper()
		if tag.is_empty():
			continue

		var name_ru = item.get("name_ru", item.get("country_name_ru", item.get("name", tag)))
		var name_en = item.get("name_en", item.get("country_name_en", item.get("name", tag)))
		var ideology = item.get("ruling_ideology", item.get("ideology", "Neutral"))
		var leader = item.get("leader_name", item.get("leader", "Unknown Leader"))
		var portrait = item.get("leader_portrait_path", item.get("portrait", "res://icon.svg"))
		var has_content = bool(item.get("has_content", true))

		var col := Color(0.6, 0.6, 0.6, 1.0)
		var c_arr = item.get("country_color", item.get("color", []))
		if c_arr is Array and c_arr.size() >= 3:
			col = Color(float(c_arr[0]), float(c_arr[1]), float(c_arr[2]), 1.0)
		elif c_arr is Color:
			col = c_arr

		var flag_path = item.get("flag_path", "res://assets/gfx/flags/%s.png" % tag)

		nations.append({
			"tag": tag,
			"name": name_ru,
			"name_en": name_en,
			"ruling_ideology": ideology,
			"leader_name": leader,
			"leader_portrait_path": portrait,
			"color": col,
			"has_content": has_content,
			"flag_path": flag_path
		})

	# Сортировка: сначала страны с уникальным контентом (tno_playable_country)
	nations.sort_custom(func(a, b):
		if a["has_content"] != b["has_content"]:
			return int(a["has_content"]) > int(b["has_content"])
		return a["name"].naturalnocasecmp_to(b["name"]) < 0
	)

	return nations


static func _read_json_file(path: String) -> Variant:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text = f.get_as_text()
	f.close()
	var json = JSON.new()
	if json.parse(text) == OK:
		return json.data
	return {}
