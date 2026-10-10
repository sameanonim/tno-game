class_name CountrySelectDossierBuilder
extends Node

##
## CountrySelectDossierBuilder: Построитель досье партий, кабинета министров и национальных духов TNO
## ==============================================================================
## Отвечает за:
## 1. Построение структуры партий, расчет процентных долей и отрисовку круговой диаграммы (Pie Chart).
## 2. Формирование карточек кабинета министров (Глава правительства, МИД, Минфин, Госбезопасность).
## 3. Генерацию сетки национальных духов (National Spirits) с историческими описаниями и модификаторами.
## ==============================================================================


"""Формирует распределение политических партий и легенду идеологий.
"""
static func build_parties_breakdown(
	screen: Control,
	tag: String,
	parties_list: Array[Dictionary],
	legend_container: Control
) -> void:
	parties_list.clear()
	if legend_container != null:
		for c in legend_container.get_children():
			c.queue_free()

	var pop_dict: Dictionary = {}

	# 1. Чтение из country.json
	var c_path = "res://data/countries/%s/country.json" % tag
	if FileAccess.file_exists(c_path):
		var f = FileAccess.open(c_path, FileAccess.READ)
		if f != null:
			var json = JSON.new()
			if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
				var c_data = json.data as Dictionary
				if c_data.has("popularities") and c_data["popularities"] is Dictionary:
					pop_dict = c_data["popularities"]
			f.close()

	# 2. Если пусто, попытка из CountryDataImporter
	if pop_dict.is_empty():
		var state = CountryDataImporter.load_country(tag)
		if state != null and not state.initial_parties.is_empty():
			for p in state.initial_parties:
				pop_dict[p.party_name] = p.popularity

	# 3. Базовый идеологический справочник TNO
	var ideo_meta = {
		"national_socialism": {
			"name": "НСДАП (Ортодоксы)",
			"color": Color(0.48, 0.28, 0.18),
			"desc": "Ортодоксальное крыло национал-социализма. Опирается на партийный аппарат, старую гвардию и культ фюрера."
		},
		"national_socialism_2": {
			"name": "Партократы Бормана",
			"color": Color(0.62, 0.38, 0.22),
			"desc": "Консервативная партийная номенклатура Рейха, стремящаяся законсервировать статус-кво."
		},
		"burgundian_system": {
			"name": "Черный Орден СС",
			"color": Color(0.18, 0.18, 0.26),
			"desc": "Тоталитарно-спартанский эзотерический культ Генриха Гиммлера. Цель — очистительный ядерный армагеддон."
		},
		"ultranationalism": {
			"name": "Ультранационалисты",
			"color": Color(0.32, 0.32, 0.36),
			"desc": "Радикальные милитаристы и фанатики реванша. Полное подчинение общества подготовке к тотальной войне."
		},
		"fascism": {
			"name": "Фашисты",
			"color": Color(0.55, 0.40, 0.20),
			"desc": "Корпоративистский авторитарный режим, жесткая государственная иерархия и культ нации."
		},
		"despotism": {
			"name": "Милитаристы / Деспотия",
			"color": Color(0.42, 0.45, 0.50),
			"desc": "Генеральская хунта и военные прагматики. Управление через армейские приказы и силу оружия."
		},
		"paternalism": {
			"name": "Авторитарные Консерваторы",
			"color": Color(0.20, 0.45, 0.65),
			"desc": "Традиционная элита, монархисты и правые популисты, стремящиеся к порядку и сильной руке."
		},
		"conservatism": {
			"name": "Консерваторы",
			"color": Color(0.20, 0.55, 0.85),
			"desc": "Парламентский консерватизм, рыночная стабильность, верховенство закона и традиционные институты."
		},
		"liberalism": {
			"name": "Либеральные Демократы",
			"color": Color(0.90, 0.65, 0.20),
			"desc": "Гражданские свободы, рыночные реформы, разделение властей и главенство конституции."
		},
		"progressivism": {
			"name": "Прогрессивисты",
			"color": Color(0.20, 0.80, 0.70),
			"desc": "Социальные реформы, гражданское равноправие, борьба с дискриминацией и поддержка трудящихся."
		},
		"socialist": {
			"name": "Демократические Социалисты",
			"color": Color(0.85, 0.30, 0.25),
			"desc": "Рабочая демократия, национализация ключевых монополий и народный суверенитет."
		},
		"communist": {
			"name": "Коммунисты",
			"color": Color(0.70, 0.12, 0.12),
			"desc": "Авангард пролетариата, марксистско-ленинская диктатура и централизованное планирование."
		}
	}

	var specific_party_names = {
		"USA": {
			"liberalism": "Демократы (R-D)",
			"conservatism": "Республиканцы (R-D)",
			"paternalism": "Правые патриоты (NPP-FR)",
			"progressivism": "Прогрессивисты (NPP-C)"
		},
		"GER": {
			"national_socialism": "НСДАП (Ортодоксы Гитлера)",
			"national_socialism_2": "Партократы Бормана",
			"despotism": "Милитаристы Вермахта",
			"liberalism": "Реформаторы Шпеера",
			"paternalism": "Имперские Консерваторы"
		},
		"SPE": {
			"liberalism": "Реформаторы Шпеера / Банда Четырёх",
			"conservatism": "Консервативное студенчество",
			"national_socialism": "Лоялисты Рейха"
		},
		"BOR": {
			"national_socialism_2": "Партийная номенклатура Бормана",
			"national_socialism": "Старая гвардия НСДАП",
			"paternalism": "Государственная канцелярия"
		},
		"GOR": {
			"despotism": "Хунта Вермахта и Люфтваффе",
			"ultranationalism": "Фанатики Шёрнера",
			"national_socialism": "Милитаристы НСДАП"
		},
		"HEY": {
			"burgundian_system": "Черный Орден СС",
			"national_socialism": "Охранные отряды Рейха",
			"ultranationalism": "Эскадроны возмездия"
		},
		"JAP": {
			"fascism": "Ассоциация Помощи Трону (Тайсэй Ёкусанкай)",
			"paternalism": "Фракция Йото (Гражданская бюрократия)",
			"despotism": "Императорская Армия (Клика Кодоха)",
			"conservatism": "Реформаторы Минсэйто"
		},
		"ITA": {
			"fascism": "Национальная Фашистская Партия (PNF)",
			"paternalism": "Монархисты и Сенат Королевства",
			"conservatism": "Христианская Демократия (DC)",
			"liberalism": "Либеральные реформаторы Чиано"
		},
		"IBR": {
			"paternalism": "Национальное Движение (Movimiento Nacional)",
			"fascism": "Испанская Фаланга (FET y de las JONS)",
			"despotism": "Опус Деи и Технократы",
			"socialist": "Республиканское подполье"
		},
		"ENG": {
			"fascism": "Британский союз фашистов (BPP)",
			"paternalism": "Королевские консерваторы Эдварда VIII",
			"liberalism": "Движение Свободной Англии (HMMLR)"
		},
		"BRG": {
			"burgundian_system": "СС-Орденсштаат Бургундия",
			"ultranationalism": "Штурмовые легионы Черного Солнца"
		},
		"TUR": {
			"paternalism": "Республиканская Народная Партия (CHP)",
			"conservatism": "Демократическая Партия (DP)",
			"ultranationalism": "Движение националистов (MHP)"
		},
		"GNG": {
			"paternalism": "Законодательный совет Гуандуна",
			"despotism": "Клика корпораций (Sony & Matsushita)",
			"fascism": "Группа Ясуда и Кэмпэйтай",
			"socialist": "Китайские рабочие профсоюзы"
		},
		"CHI": {
			"paternalism": "Реорганизованный Гоминьдан (Нанкин)",
			"fascism": "Общество Возрождения (Синьминьхуэй)",
			"socialist": "Партизанские ячейки Новой 4-й Армии"
		},
		"MAN": {
			"fascism": "Общество Согласия (Сехэхой)",
			"despotism": "Генералитет Квантунской армии",
			"paternalism": "Императорский двор Пу И"
		},
		"THA": {
			"despotism": "Военный совет Пибунсонграма",
			"paternalism": "Королевские традиционалисты",
			"conservatism": "Демократическая партия Таиланда"
		},
		"YUN": {
			"despotism": "Клика Лу Хана",
			"ultranationalism": "Националисты Лун Юня",
			"paternalism": "Совет старейшин Юньнани"
		},
		"OMS": {
			"ultranationalism": "Всероссийская Чёрная Лига (Великий Суд)",
			"despotism": "Генеральный штаб обороны Омска",
			"communist": "Подпольные солдатские советы"
		},
		"WRS": {
			"socialist": "Революционный Военный Совет РККА",
			"communist": "Политсовет бойцов фронта (Тухачевский)",
			"despotism": "Генеральный штаб Маршала Ворошилова"
		},
		"SVR": {
			"paternalism": "Уральское Военное Правительство (Батов)",
			"despotism": "Штаб Уральского Военного Округа",
			"conservatism": "Гражданский совет Свердловска"
		},
		"TOM": {
			"liberalism": "Салон Декабристов",
			"conservatism": "Салон Модернистов",
			"progressivism": "Салон Бастурмы",
			"paternalism": "Салон Евразийцев"
		},
		"KOM": {
			"progressivism": "Демократический Центр (Вознесенский)",
			"communist": "Левый Фронт (Суслов, Жданов)",
			"socialist": "Демократические коммунисты Бухариной",
			"ultranationalism": "Пассионарии / Правая Коалиция (Гумилёв, Таборицкий)",
			"despotism": "Сыктывкарский гарнизон"
		},
		"NOV": {
			"despotism": "Федерация Покрышкина (Корпорация Сибирь)",
			"conservatism": "Союз Централистов Василия Шукшина",
			"paternalism": "Совет сибирских промышленников"
		},
		"BRY": {
			"socialist": "Саблинский Революционный Военсовет",
			"communist": "Комитет Истинного Ленинизма",
			"paternalism": "Бурятские автономисты"
		},
		"SBA": {
			"socialist": "Вольная Территория (Анархо-коммунисты)",
			"despotism": "Чёрная Гвардия (Военный совет)",
			"progressivism": "Комитет Вольных Синдикатов"
		},
		"SAM": {
			"fascism": "Комитет Освобождения Народов России (Власов)",
			"despotism": "Штаб Русской Освободительной Армии",
			"paternalism": "Гражданское правление КОНР"
		},
		"TYM": {
			"communist": "Тюменский Обком ВКП(б) (Каганович)",
			"socialist": "Реформаторы Никиты Хрущёва",
			"despotism": "Штаб Ударной Армии Реванша"
		},
		"TYU": {
			"communist": "Тюменский Обком ВКП(б) (Каганович)",
			"socialist": "Реформаторы Никиты Хрущёва",
			"despotism": "Штаб Ударной Армии Реванша"
		},
		"VYT": {
			"paternalism": "Монархисты Императора Владимира III",
			"conservatism": "Народно-Трудовой Союз (НТС)",
			"liberalism": "Конституционные демократы"
		},
		"IRK": {
			"communist": "Президиум Верховного Совета СССР (Ягода)",
			"despotism": "Коллегия Госбезопасности НКВД",
			"socialist": "Партийные диссиденты Бессонова"
		},
		"MAG": {
			"fascism": "Российская Фашистская Партия (Матковский)",
			"despotism": "Американские наёмники Митчелла Вербелла",
			"conservatism": "Тихоокеанские купцы"
		},
		"AMR": {
			"national_socialism": "Всероссийская Фашистская Организация (Родзаевский)",
			"ultranationalism": "Чернорубашечники Дальнего Востока",
			"despotism": "Амурский военный штаб"
		},
		"CHT": {
			"paternalism": "Забайкальское Белое Движение (Атаман Семёнов)",
			"despotism": "Казачий круг Читы",
			"conservatism": "Конституционные монархисты"
		},
		"KEM": {
			"paternalism": "Кемеровское Царство (Рюрик II)",
			"socialist": "Народное Вече Царевича Юрия",
			"despotism": "Дружина Царевны Лидии"
		}
	}

	var specific_party_descs = {
		"USA": {
			"liberalism": "Либеральное крыло R-D. Поддерживает социальные реформы 'Великого Общества' и умеренную десегрегацию.",
			"conservatism": "Республиканцы R-D под руководством Никсона. Рыночная стабильность и сдерживание тоталитаризма.",
			"paternalism": "Правые патриоты NPP. Бескомпромиссный реванш против Рейха и Японии, защита традиционных ценностей.",
			"progressivism": "Прогрессивисты NPP. Требуют немедленного принятия жесткого Билля о гражданских правах и социальных гарантий."
		},
		"GER": {
			"national_socialism": "Ортодоксальная элита НСДАП, удерживающая власть в последние месяцы жизни стареющего Фюрера.",
			"national_socialism_2": "Аппаратная партократия Бормана. Консервация существующей системы без опасных реформ.",
			"despotism": "Милитаристы Геринга и Шёрнера. Требуют выхода из стагнации через возобновление внешних завоеваний.",
			"liberalism": "Реформаторы Шпеера. Технократы и студенты, выступающие за отмену рабства и рыночную модернизацию."
		},
		"JAP": {
			"fascism": "Государственная монолитная партия Тэйкоку, балансирующая между аппетитами дзайбацу и армией.",
			"paternalism": "Гражданские чиновники кабинета Икэды, стремящиеся к финансовой стабилизации Сферы Сопроцветания.",
			"despotism": "Клика Императорской Армии, требующая жесткого силового подавления национальных движений в Азии."
		},
		"ITA": {
			"fascism": "Партия Дуче, раздираемая борьбой между консерваторами Скорцы и сторонниками реформ Чиано.",
			"paternalism": "Сторонники Савойской династии короля Умберто II, желающие постепенного демонтажа диктатуры.",
			"conservatism": "Подпольная христианско-демократическая оппозиция, готовая к возвращению парламентаризма."
		},
		"IBR": {
			"paternalism": "Хрупкая коалиция Франко и Салазара, сдерживающая центробежные силы Пиренейского полуострова.",
			"fascism": "Испанская Фаланга, выступающая против любых уступок португальцам и капиталистическим реформам."
		},
		"ENG": {
			"fascism": "Коллаборационистское марионеточное правительство Лондона, слепо выполняющее приказы Берлина.",
			"liberalism": "Подпольное Движение Сопротивления (HMMLR), готовое поднять всеобщее восстание за свободу Британии."
		},
		"GNG": {
			"despotism": "Технократическая олигархия мегакорпораций Sony и Matsushita, правящая ради сверхприбылей.",
			"fascism": "Клика Ясуда и спецслужба Кэмпэйтай, подавляющая недовольство китайских рабочих насилием."
		},
		"CHI": {
			"paternalism": "Правительство Гао Цзунъу: внешняя покорность Токио ради тайной модернизации Китая к Освободительной Войне.",
			"fascism": "Прояпонские коллаборационисты, настаивающие на полной интеграции Поднебесной в Сферу."
		},
		"OMS": {
			"ultranationalism": "Военно-спартанский орден Карбышева и Язова, посвятивший себя подготовке ядерного возмездия Рейху.",
			"despotism": "Офицеры подземных арсеналов и инженеры, возводящие убежища к Дню Суда."
		},
		"WRS": {
			"socialist": "Красная Армия маршалов Тухачевского и Ворошилова. Восстановление СССР огнем и мечом.",
			"communist": "Фронтовые комиссары и рабочие комитеты, готовящие Второй Западный поход на Москву."
		},
		"SVR": {
			"paternalism": "Прагматичный офицерский корпус генерала Батова, ставящий службу Родине выше политических споров.",
			"despotism": "Стальная дисциплина Уральского Военного Округа и мощь оборонных заводов."
		},
		"TOM": {
			"liberalism": "Салон Декабристов: народовластие, просвещение, права человека и парламентская свобода.",
			"conservatism": "Салон Модернистов: технократия, ставка на передовую науку, кибернетику и индустрию.",
			"progressivism": "Салон Бастурмы: социальная справедливость, гуманизм, поэзия и народное счастье.",
			"paternalism": "Салон Евразийцев: сильное традиционное государство и мост между Европой и Азией."
		},
		"KOM": {
			"progressivism": "Демократический Центр Вознесенского, пытающийся спасти шаткую республику от гражданской войны.",
			"communist": "Ортодоксальные марксисты Суслова и визионеры Жданова, готовящие коммунистический реванш.",
			"ultranationalism": "Пассионарии: радикальные реваншисты от евразийства Гумилёва до безумного фашизма Таборицкого."
		}
	}

	var party_items: Array[Dictionary] = []
	for k in pop_dict:
		var val = float(pop_dict[k])
		if val <= 0.001:
			continue
		var base_info = ideo_meta.get(k, {
			"name": k.capitalize(),
			"color": Color(0.5, 0.5, 0.5),
			"desc": "Политическая фракция державы."
		})
		var p_name = str(base_info["name"])
		if specific_party_names.has(tag) and specific_party_names[tag].has(k):
			p_name = specific_party_names[tag][k]

		var p_desc = str(base_info["desc"])
		if specific_party_descs.has(tag) and specific_party_descs[tag].has(k):
			p_desc = specific_party_descs[tag][k]

		party_items.append({
			"id": k,
			"name": p_name,
			"popularity": val,
			"color": base_info["color"],
			"desc": p_desc
		})

	party_items.sort_custom(func(a, b): return a["popularity"] > b["popularity"])

	if party_items.is_empty():
		party_items = [
			{"id": "ruling", "name": "Правящая партия", "popularity": 62.0, "color": Color(0.2, 0.85, 0.75), "desc": "Основная политическая опора действующего режима."},
			{"id": "opposition", "name": "Лояльная оппозиция", "popularity": 24.0, "color": Color(0.35, 0.60, 0.75), "desc": "Легальные фракции, участвующие в распределении мандатов."},
			{"id": "radicals", "name": "Радикальные диссиденты", "popularity": 14.0, "color": Color(0.75, 0.35, 0.35), "desc": "Внесистемные движения и подпольные ячейки."}
		]

	for item in party_items:
		parties_list.append(item)

		if legend_container != null:
			var chip := PanelContainer.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.04, 0.08, 0.10, 0.90)
			sb.border_color = Color(item["color"].r * 0.7, item["color"].g * 0.7, item["color"].b * 0.7, 0.8)
			sb.border_width_left = 1
			sb.border_width_top = 1
			sb.border_width_right = 1
			sb.border_width_bottom = 1
			sb.corner_radius_top_left = 2
			sb.corner_radius_top_right = 2
			sb.corner_radius_bottom_left = 2
			sb.corner_radius_bottom_right = 2
			chip.add_theme_stylebox_override("panel", sb)

			var hbox := HBoxContainer.new()
			hbox.add_theme_constant_override("separation", 5)

			var dot := ColorRect.new()
			dot.custom_minimum_size = Vector2(8, 8)
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			dot.color = item["color"]
			hbox.add_child(dot)

			var lbl := Label.new()
			lbl.text = "%s: %0.1f%%" % [item["name"], item["popularity"]]
			lbl.add_theme_font_size_override("font_size", 9)
			lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 0.9))
			hbox.add_child(lbl)

			chip.add_child(hbox)
			chip.tooltip_text = "┌── [ПОЛИТИЧЕСКАЯ СИЛА // POLITICAL PARTY] ──\n│ Партия: %s\n│ Доля влияния: %0.1f%%\n├─────────────────────────────────────────\n│ Платформа и идеология:\n│ %s" % [item["name"], item["popularity"], item["desc"]]
			legend_container.add_child(chip)


"""Отрисовывает круговую диаграмму популярности политических партий на Control узле.
"""
static func draw_pie_chart(chart_control: Control, parties_list: Array[Dictionary]) -> void:
	if chart_control == null or parties_list.is_empty():
		return

	var center = chart_control.size / 2.0
	var radius = minf(center.x, center.y) - 2.0
	var start_angle = -PI / 2.0

	for p in parties_list:
		var share = float(p.get("popularity", 0.0)) / 100.0
		if share <= 0.001:
			continue

		var end_angle = start_angle + (share * TAU)
		var points = PackedVector2Array([center])
		var segments = maxi(8, int(share * 36))
		for i in range(segments + 1):
			var a = start_angle + (float(i) / segments) * (end_angle - start_angle)
			points.append(center + Vector2(cos(a), sin(a)) * radius)

		var col: Color = p.get("color", Color.WHITE)
		chart_control.draw_colored_polygon(points, col)
		start_angle = end_angle

	chart_control.draw_arc(center, radius, 0.0, TAU, 48, Color(0.1, 0.2, 0.25, 0.8), 1.0)


"""Заполняет сетку министров кабинета правительства державы.
"""
static func populate_cabinet_ministers(ministers_grid: Control, tag: String, _dossier: Dictionary) -> void:
	if ministers_grid == null:
		return

	for c in ministers_grid.get_children():
		c.queue_free()

	var role_meta = {
		"hog": {
			"abbr": "[ГЛАВА ПРАВ.]",
			"full": "Глава правительства",
			"dep": "Исполнительная канцелярия",
			"icon": "res://assets/gfx/interface/pol_power_icon.png",
			"effects": "• Прирост политического капитала: +0.25/ход\n• Стабильность режима: +5.0%\n• Эффективность решений: +10.0%"
		},
		"for": {
			"abbr": "[МИД]",
			"full": "Министр иностранных дел",
			"dep": "Министерство иностранных дел",
			"icon": "res://assets/gfx/interface/ideologies/paternalism_transitioning_democracy_subtype.png",
			"effects": "• Дипломатический вес державы: +15.0%\n• Международная легитимность: +10.0%\n• Скорость торговых сделок: +20.0%"
		},
		"eco": {
			"abbr": "[ЭКОНОМИКА]",
			"full": "Министр экономики",
			"dep": "Министерство финансов и промышленности",
			"icon": "res://assets/gfx/interface/industrial_capacity_icon.png",
			"effects": "• Производительность фабрик: +10.0%\n• Рост ВВП за ход: +0.3%\n• Затраты на потребительские нужды: -5.0%"
		},
		"sec": {
			"abbr": "[БЕЗОПАСНОСТЬ]",
			"full": "Министр безопасности",
			"dep": "Оборонное ведомство и органы безопасности",
			"icon": "res://assets/gfx/interface/war_support_icon.png",
			"effects": "• Поддержка войны: +10.0%\n• Сопротивление в провинциях: -15.0%\n• Скорость мобилизации резервов: +12.0%"
		}
	}

	var canonical = get_canonical_ministers(tag)
	var roles = ["hog", "for", "eco", "sec"]

	for r in roles:
		var r_data = role_meta[r]
		var found_name := ""
		var minister_portrait_tex: Texture2D = null
		var effects_text: String = r_data["effects"]
		var dep_text: String = r_data["dep"]
		var full_title: String = r_data["full"]

		if canonical.has(r):
			var cm = canonical[r]
			found_name = cm["name"]
			if cm.has("full"): full_title = cm["full"]
			if cm.has("dep"): dep_text = cm["dep"]
			if cm.has("effects"): effects_text = cm["effects"]
			if cm.has("portrait") and not str(cm["portrait"]).is_empty():
				minister_portrait_tex = TNOTheme.get_texture(str(cm["portrait"]))

		if found_name.is_empty():
			found_name = "Штабной специалист"

		if minister_portrait_tex == null:
			minister_portrait_tex = TNOTheme.get_texture(r_data["icon"])

		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(0, 44)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.04, 0.08, 0.10, 0.92)
		sb.border_color = Color(0.20, 0.55, 0.50, 0.85)
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.corner_radius_top_left = 2
		sb.corner_radius_top_right = 2
		sb.corner_radius_bottom_left = 2
		sb.corner_radius_bottom_right = 2
		card.add_theme_stylebox_override("panel", sb)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 6)
		card.add_child(hbox)

		var icon_rect := TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(26, 34)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture = minister_portrait_tex
		hbox.add_child(icon_rect)

		var vbox := VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_theme_constant_override("separation", 1)

		var lbl_role := Label.new()
		lbl_role.text = r_data["abbr"]
		lbl_role.add_theme_font_size_override("font_size", 8)
		lbl_role.add_theme_color_override("font_color", Color(0.3, 0.95, 0.85))
		vbox.add_child(lbl_role)

		var lbl_name := Label.new()
		lbl_name.text = found_name
		lbl_name.add_theme_font_size_override("font_size", 9)
		lbl_name.add_theme_color_override("font_color", Color(1.0, 0.88, 0.4))
		lbl_name.clip_text = true
		vbox.add_child(lbl_name)

		hbox.add_child(vbox)

		card.tooltip_text = "┌── [КАБИНЕТ МИНИСТРОВ // CABINET OF MINISTERS] ──\n│ ДОЛЖНОСТЬ: %s\n│ МИНИСТР: %s\n│ ВЕДОМСТВО: %s\n├─────────────────────────────────────────\n│ СТРАТЕГИЧЕСКИЕ ЭФФЕКТЫ ВЕДОМСТВА:\n%s" % [full_title, found_name, dep_text, effects_text]
		ministers_grid.add_child(card)


"""Заполняет сетку национальных духов и кризисов державы.
"""
static func populate_national_spirits_grid(spirits_grid: Control, tag: String, _dossier: Dictionary) -> void:
	if spirits_grid == null:
		return

	for c in spirits_grid.get_children():
		c.queue_free()

	var c_path = "res://data/countries/%s/country.json" % tag
	var raw_ideas: Array = []
	if FileAccess.file_exists(c_path):
		var f = FileAccess.open(c_path, FileAccess.READ)
		if f != null:
			var json = JSON.new()
			if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
				var c_data = json.data as Dictionary
				raw_ideas = c_data.get("ideas", [])
			f.close()

	var spirit_ids: Array[String] = []
	for id_item in raw_ideas:
		var sid = str(id_item)
		if sid.ends_with("_hog") or sid.ends_with("_for") or sid.ends_with("_eco") or sid.ends_with("_sec"):
			continue
		if sid.ends_with("_high_command") or sid.ends_with("_army_chief") or sid.ends_with("_navy_chief") or sid.ends_with("_air_chief") or sid.ends_with("_theorist"):
			continue
		if sid.begins_with("tno_"):
			continue
		spirit_ids.append(sid)

	var spirits_registry = {
		# Германия
		"Pakt_Leader": {
			"name": "Лидер Единства Пакта",
			"icon": "res://assets/gfx/interface/goals/focus_GER_a_common_goal.png",
			"desc": "Великогерманский Рейх возглавляет военный блок в Европе, подавляя неповиновение в рейхскомиссариатах.",
			"effects": "• Приток политического влияния: +15.0%\n• Эффективность торговли с Пактом: +25.0%\n• Напряженность в колониях: Растущая"
		},
		"to_banish_want": {
			"name": "Искоренить нужду",
			"icon": "res://assets/gfx/interface/goals/focus_GER_bormann_army.png",
			"desc": "Огромные инфраструктурные мегапроекты и рабский труд сковывают реальную модернизацию экономики Рейха.",
			"effects": "• Потребление товаров: -10.0%\n• Затраты на рабочую силу: Минимальные\n• Технологическая инерция: -15.0%"
		},
		"the_two_principles": {
			"name": "Два принципа",
			"icon": "res://assets/gfx/interface/goals/focus_GER_a_german_wehrmacht.png",
			"desc": "Раскол и подозрительность между прусским генералитетом Вермахта и идеологическими фанатиками НСДАП.",
			"effects": "• Стоимость армейских директив: +10.0%\n• Боеготовность дивизий: 80.0%\n• Политическое влияние армии: Высокое"
		},
		"endsieg": {
			"name": "Окончательная победа (Endsieg)",
			"icon": "res://assets/gfx/interface/goals/focus_GER_the_second_bormann_ausschuss.png",
			"desc": "Государственная пропаганда твердит о непоколебимом триумфе, пока общество скатывается к гражданской войне.",
			"effects": "• Поддержка войны: +15.0%\n• Общественная стабильность: Хрупкая\n• Смертельный кризис престолонаследия"
		},
		"gone_over": {
			"name": "Тень рабского труда",
			"icon": "res://assets/gfx/interface/war_support_icon.png",
			"desc": "Миллионы подневольных рабочих содержат промышленность Рейха в состоянии постоянного скрытого саботажа.",
			"effects": "• Риск восстаний рабов: Критический\n• Производственный саботаж: 12.0%\n• Моральный дух общества: Упадочный"
		},
		# США
		"OFN_Leader_of_The_Free_World": {
			"name": "Лидер Свободного Мира (ОФН)",
			"icon": "res://assets/gfx/interface/goals/focus_GER_a_common_goal.png",
			"desc": "Соединенные Штаты возглавляют Организацию Свободных Наций — единственный оплот демократии против тирании.",
			"effects": "• Дипломатический вес: +30.0%\n• Ленд-лиз союзникам: +25.0%\n• Общественная легитимность: 85%"
		},
		"USA_last_bastion_of_liberty": {
			"name": "Последний бастион свободы",
			"icon": "res://assets/gfx/interface/pol_power_icon.png",
			"desc": "Американская мечта выстояла после поражения в войне, вдохновляя диссидентов по всей планете.",
			"effects": "• Прирост полит. капитала: +0.25/ход\n• Приток квалифицированных беженцев: +20%\n• Решимость нации: Высокая"
		},
		"USA_the_american_depression_4": {
			"name": "Эхо Великой Депрессии",
			"icon": "res://assets/gfx/interface/industrial_capacity_icon.png",
			"desc": "Потеря рынков Европы и Азии сковывает потенциал американских корпораций и вызывает безработицу.",
			"effects": "• Производительность фабрик: -10.0%\n• Затраты на соцобеспечение: +15.0%\n• Недовольство профсоюзов: Умеренное"
		},
		"USA_jim_crow": {
			"name": "Сегрегация и Законы Джима Кроу",
			"icon": "res://assets/gfx/interface/war_support_icon.png",
			"desc": "Глубокий расовый раскол раскалывает американское общество и ставит под угрозу единство нации.",
			"effects": "• Радикализация в южных штатах: +18.0%\n• Раскол в Конгрессе: Критический\n• Риск массовых протестов: Высокий"
		},
		"USA_OFN_Buffs_4": {
			"name": "Арсенал Демократии",
			"icon": "res://assets/gfx/interface/goals/focus_GER_a_german_wehrmacht.png",
			"desc": "Американская военная промышленность способна оснастить современным оружием любого союзника в прокси-войнах.",
			"effects": "• Производство вооружений: +15.0%\n• Эффективность прокси-конфликтов: +20.0%\n• Готовность флота: 95%"
		},
		# Япония
		"Sphere_Leader": {
			"name": "Гегемон Сферы Сопроцветания",
			"icon": "res://assets/gfx/interface/goals/focus_GER_a_common_goal.png",
			"desc": "Токио контролирует торговые пути и колонии всей Восточной Азии, выкачивая ресурсы из сателлитов.",
			"effects": "• Приток колониального сырья: +35.0%\n• Влияние дзайбацу: Огромное\n• Ненависть порабощенных народов: Скрытая"
		},
		"JAP_showa_emperor": {
			"name": "Непогрешимость Императора Сёва",
			"icon": "res://assets/gfx/interface/pol_power_icon.png",
			"desc": "Божественный авторитет Тэнно объединяет японский народ и сковывает любые попытки открытого мятежа.",
			"effects": "• Стабильность метрополии: 85.0%\n• Фаталистическая преданность: 100%\n• Защита от революций: Абсолютная"
		},
		"JAP_zaibatsu_question": {
			"name": "Засилье кланов Дзайбацу",
			"icon": "res://assets/gfx/interface/industrial_capacity_icon.png",
			"desc": "Финансовые спруты Мицуи, Мицубиси и Ясуда контролируют экономику, подкупая министров и генералов.",
			"effects": "• Коррупция в правительстве: 40.0%\n• Неуязвимость олигархов: Полная\n• Риск финансового кризиса: Критический"
		},
		"JAP_legacy_guarded_pearl_exercises": {
			"name": "Победоносный Императорский Флот",
			"icon": "res://assets/gfx/interface/goals/focus_GER_a_german_wehrmacht.png",
			"desc": "Победа над США в Перл-Харборе закрепила за флотом статус главной ударной силы Империи.",
			"effects": "• Превосходство авианосцев: +25.0%\n• Морской контроль Тихого океана: 90%\n• Соперничество флота и армии: Ожесточенное"
		},
		# Италия
		"TRI_Founder_IT": {
			"name": "Основатель Триумвирата",
			"icon": "res://assets/gfx/interface/goals/focus_GER_a_common_goal.png",
			"desc": "Рим возглавляет Средиземноморский союз, бросая вызов германской гегемонии на континенте.",
			"effects": "• Престиж Рима: +20.0%\n• Сплоченность Триумвирата: 65%\n• Торговый паритет: Активен"
		},
		"ITA_declining_trade": {
			"name": "Удар Атлантропы по Средиземноморью",
			"icon": "res://assets/gfx/interface/industrial_capacity_icon.png",
			"desc": "Пересыхание Адриатики и падение уровня моря уничтожили древние итальянские порты.",
			"effects": "• Морская торговля: -25.0%\n• Расходы на мелиорацию: 18 млн/ход\n• Безработица моряков: Высокая"
		},
		"ITA_fading_fascism": {
			"name": "Увядающий фашизм",
			"icon": "res://assets/gfx/interface/war_support_icon.png",
			"desc": "Энтузиазм первых десятилетий правления Муссолини сменился цинизмом, коррупцией и усталостью народа.",
			"effects": "• Полит. капитал: -15.0%\n• Раскол в Большом фашистском совете: Острый\n• Общественная апатия: 60%"
		},
		"ITA_navy_strengthened": {
			"name": "Гордость Реджа Марина",
			"icon": "res://assets/gfx/interface/goals/focus_GER_a_german_wehrmacht.png",
			"desc": "Мощный средиземноморский флот линкоров и крейсеров надежно охраняет Mare Nostrum.",
			"effects": "• Превосходство на море: +20.0%\n• Стоимость обслуживания флота: +10%\n• Оборона колоний: Высокая"
		},
		"ITA_king_umberto": {
			"name": "Савойская Корона",
			"icon": "res://assets/gfx/interface/pol_power_icon.png",
			"desc": "Король Умберто II остается символом национальной преемственности и надеждой умеренных кругов.",
			"effects": "• Монархическая легитимность: 75%\n• Противовес диктатуре: Умеренный\n• Шанс мирного транзита власти"
		},
		# Русские варлорды
		"RUS_terror_bombing": {
			"name": "Налеты Люфтваффе на Россию",
			"icon": "res://assets/gfx/interface/war_support_icon.png",
			"desc": "Регулярные террористические бомбардировки с рейхскомиссариатов разрушают города и сеют смерть.",
			"effects": "• Производительность фабрик: -15.0%\n• Потери населения: Постоянные\n• Ненависть к Германии: Непримиримая"
		},
		"SIB_terror_bombing": {
			"name": "Эхо налетов Люфтваффе",
			"icon": "res://assets/gfx/interface/war_support_icon.png",
			"desc": "Хотя Сибирь дальше от аэродромов Рейха, немецкие стервятники периодически наносят удары по городам.",
			"effects": "• Уязвимость инфраструктуры: -10.0%\n• Напряженность ПВО: Высокая\n• Опыт зенитчиков: +15%"
		},
		"RUS_warlord_manpower": {
			"name": "Людские ресурсы Варлордов",
			"icon": "res://assets/gfx/interface/manpower_icon.png",
			"desc": "Мужчины и женщины бегут из разоренных деревень в гарнизоны, готовые служить за паек и винтовку.",
			"effects": "• Скорость призыва дивизий: +15.0%\n• Стоимость содержания армии: -10%\n• Беженцы на сборных пунктах"
		},
		"OMS_fueled_by_revenge": {
			"name": "Питаемые жаждой мести",
			"icon": "res://assets/gfx/interface/war_support_icon.png",
			"desc": "Каждый боец Чёрной Лиги живет одной священной мыслью — возмездием за миллионы замученных русских людей.",
			"effects": "• Поддержка войны: 100.0%\n• Мораль в бою: Фанатичная\n• Пощада врагам: Исключена"
		},
		"OMS_nothing_left_to_lose": {
			"name": "Нечего терять",
			"icon": "res://assets/gfx/interface/war_support_icon.png",
			"desc": "Потеряв родину и близких, солдаты Лиги не боятся даже радиоактивного пепла будущего Великого Суда.",
			"effects": "• Стойкость в обороне: +35.0%\n• Дезертирство: 0.0%\n• Страх смерти: Искоренен"
		},
		"WRS_veterans_of_the_long_war": {
			"name": "Ветераны Великой и Западнорусской войн",
			"icon": "res://assets/gfx/interface/goals/focus_GER_a_german_wehrmacht.png",
			"desc": "Опытные красноармейцы и закаленные командиры составляют железный костяк Фронта Тухачевского.",
			"effects": "• Атака пехотных дивизий: +20.0%\n• Скорость восстановления организации: +15%\n• Профессионализм: Максимальный"
		},
		"SVR_notso_redarmy": {
			"name": "Не совсем Красная Армия",
			"icon": "res://assets/gfx/interface/goals/focus_GER_bormann_army.png",
			"desc": "Армия Батова отказалась от политических комиссаров и догм ради боевого братства и защиты Отечества.",
			"effects": "• Солдатская сплоченность: +25.0%\n• Эффективность снабжения: +15%\n• Идеологические споры: Запрещены"
		},
		"KOM_syvtyvkartsi": {
			"name": "Сыктывкарский раскол",
			"icon": "res://assets/gfx/interface/pol_power_icon.png",
			"desc": "Борьба между правыми пассионариями, левыми социалистами и демократами парализует работу парламента.",
			"effects": "• Стабильность режима: -25.0%\n• Прирост капитала: -0.15/ход\n• Риск государственного переворота: 90%"
		},
		"KOM_clash_of_shadows_c_1": {
			"name": "Битва в тенях Коми",
			"icon": "res://assets/gfx/interface/war_support_icon.png",
			"desc": "Вооруженные дружины партийных лидеров делят улицы столицы, ожидая сигнала к захвату власти.",
			"effects": "• Уличная преступность: Высокая\n• Оружие на черном рынке: Доступно\n• Судьба демократии: На волоске"
		},
		"NOV_Disproportionate_Population": {
			"name": "Демографический бум Новосибирска",
			"icon": "res://assets/gfx/interface/manpower_icon.png",
			"desc": "Тысячи беженцев и рабочих стеклись на заводы Оби, создав мощнейший промышленный центр Сибири.",
			"effects": "• Рост населения: +20.0%\n• Рабочая сила на заводах: В избытке\n• Социальное расслоение: Заметное"
		},
		"NOV_The_All_Siberian_Army": {
			"name": "Общесибирская Армия Покрышкина",
			"icon": "res://assets/gfx/interface/goals/focus_GER_a_german_wehrmacht.png",
			"desc": "Моторизованные соединения и эскадрильи штурмовиков, оснащенные по последнему слову техники ВПК.",
			"effects": "• Авиационная поддержка: +30.0%\n• Мобильность бригад: +15%\n• Расход горючего: Высокий"
		},
		"TOM_warlord_of_the_city": {
			"name": "Цитадель Сибирского Просвещения",
			"icon": "res://assets/gfx/interface/pol_power_icon.png",
			"desc": "Томский университет и библиотеки сохранены посреди хаоса Смуты как храм русской мысли.",
			"effects": "• Скорость исследований: +20.0%\n• Моральный дух граждан: Высокий\n• Приток интеллигенции: Постоянный"
		},
		"SBA_anarchist_refuge": {
			"name": "Приют Свободных Анархистов",
			"icon": "res://assets/gfx/interface/pol_power_icon.png",
			"desc": "Вольная Территория принимает каждого, кто готов честно трудиться в коммуне и защищать свободу.",
			"effects": "• Социальное равенство: 100%\n• Бюрократический гнет: Отсутствует\n• Пропаганда добровольчества: +25%"
		},
		"SAM_german_bootlickers": {
			"name": "Тяжкое бремя предательства",
			"icon": "res://assets/gfx/interface/war_support_icon.png",
			"desc": "Клеймо пособников немецких оккупантов преследует РОА, лишая режим искренней поддержки крестьян.",
			"effects": "• Легитимность в народе: 25.0%\n• Партизанский саботаж: 15%\n• Зависимость от немецких поставок: 80%"
		},
		"TYM_revisionist_remnant": {
			"name": "Сталинский осколок ВКП(б)",
			"icon": "res://assets/gfx/interface/goals/focus_GER_bormann_army.png",
			"desc": "Несгибаемый большевистский догматизм и лагерная дисциплина на стройках сибирских пятилеток.",
			"effects": "• Скорость строительства: +25.0%\n• Партийный террор: Высокий\n• Уровень жизни рабочих: Спартанский"
		},
		"VYT_unrepentant_reaction": {
			"name": "Монархическое знамя Вятки",
			"icon": "res://assets/gfx/interface/pol_power_icon.png",
			"desc": "Двуглавый орел и имперский триколор вдохновляют белых офицеров на восстановление Святой Руси.",
			"effects": "• Лояльность дворянства и церкви: 90%\n• Стойкость казачьих сотен: +20%\n• Ненависть красных партизан: Высокая"
		},
		"IRK_bitter_remnant": {
			"name": "Осажденная крепость Госбезопасности",
			"icon": "res://assets/gfx/interface/war_support_icon.png",
			"desc": "Чекистский гарнизон Ягоды контролирует Байкал через систему осведомителей и концлагерей.",
			"effects": "• Контрразведывательный контроль: 95%\n• Ненависть заключенных: Критическая\n• Угроза мятежа на флоте: Активна"
		},
		"MAG_gateway_into_russia": {
			"name": "Ворота в Россию через Охотск",
			"icon": "res://assets/gfx/interface/industrial_capacity_icon.png",
			"desc": "Магаданский порт принимает караваны американских судов с оружием, грузовиками и долларами ОФН.",
			"effects": "• Поставки оружия из США: +30.0%\n• Рост бюджета за счет торговли: +15%\n• Зависимость от Вашингтона: Высокая"
		},
		"AMR_rusfascist_stronghold": {
			"name": "Цитадель Чернорубашечников Родзаевского",
			"icon": "res://assets/gfx/interface/war_support_icon.png",
			"desc": "Фанатичные фашистские штурмовики маршируют по улицам Харбина и Приамурья с нацистской символикой.",
			"effects": "• Расовая ненависть: Тотальная\n• Жестокость в карательных рейдах: +35%\n• Паранойя руководства: Разрушительная"
		},
		"CHT_sunset_of_white_chivalry": {
			"name": "Закат Белого рыцарства",
			"icon": "res://assets/gfx/interface/goals/focus_GER_a_german_wehrmacht.png",
			"desc": "Старые белые офицеры и казаки грабят забайкальские села, пока марионеточный Царь тоскует во дворце.",
			"effects": "• Разложение дисциплины: 20.0%\n• Боевой опыт казаков: Высокий\n• Авторитет власти: Падающий"
		},
		"KEM_esoteric_kingdom": {
			"name": "Языческое Царство Рюриковичей",
			"icon": "res://assets/gfx/interface/pol_power_icon.png",
			"desc": "Причудливый сплав древнерусского неоязычества, монархии и социалистических крестьянских общин.",
			"effects": "• Преданность дружины Царю: 95%\n• Празднества и пиры: Регулярные\n• Династический раскол наследников: Опасный"
		}
	}

	if spirit_ids.is_empty():
		if tag == "GER":
			spirit_ids = ["Pakt_Leader", "to_banish_want", "the_two_principles", "endsieg", "gone_over"]
		elif tag == "USA":
			spirit_ids = ["OFN_Leader_of_The_Free_World", "USA_last_bastion_of_liberty", "USA_the_american_depression_4", "USA_jim_crow", "USA_OFN_Buffs_4"]
		elif tag == "JAP":
			spirit_ids = ["Sphere_Leader", "JAP_showa_emperor", "JAP_zaibatsu_question", "JAP_legacy_guarded_pearl_exercises"]
		elif tag == "ITA":
			spirit_ids = ["TRI_Founder_IT", "ITA_declining_trade", "ITA_fading_fascism", "ITA_navy_strengthened", "ITA_king_umberto"]
		elif tag == "OMS":
			spirit_ids = ["SIB_terror_bombing", "RUS_warlord_manpower", "OMS_fueled_by_revenge", "OMS_nothing_left_to_lose"]
		elif tag == "WRS":
			spirit_ids = ["RUS_terror_bombing", "RUS_warlord_manpower", "WRS_veterans_of_the_long_war"]
		elif tag == "KOM":
			spirit_ids = ["RUS_terror_bombing", "RUS_warlord_manpower", "KOM_syvtyvkartsi", "KOM_clash_of_shadows_c_1"]
		elif tag == "SVR":
			spirit_ids = ["SIB_terror_bombing", "RUS_warlord_manpower", "SVR_notso_redarmy"]
		else:
			spirit_ids = ["RUS_terror_bombing", "RUS_warlord_manpower"]

	for s_id in spirit_ids:
		var sp_name := ""
		var sp_icon := ""
		var sp_desc := ""
		var sp_effects := ""

		if spirits_registry.has(s_id):
			var data = spirits_registry[s_id]
			sp_name = data["name"]
			sp_icon = data["icon"]
			sp_desc = data["desc"]
			sp_effects = data["effects"]
		else:
			sp_name = s_id.replace("_", " ").capitalize()
			sp_icon = "res://assets/gfx/interface/war_support_icon.png"
			sp_desc = "Национальный дух и системный фактор, формирующий положение державы."
			sp_effects = "• Влияние на боеспособность и экономику нации."

		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(46, 46)

		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.04, 0.08, 0.10, 0.90)
		sb.border_color = Color(0.18, 0.50, 0.45, 0.85)
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.corner_radius_top_left = 2
		sb.corner_radius_top_right = 2
		sb.corner_radius_bottom_left = 2
		sb.corner_radius_bottom_right = 2
		card.add_theme_stylebox_override("panel", sb)

		var icon_rect := TextureRect.new()
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.custom_minimum_size = Vector2(36, 36)

		var tex: Texture2D = null
		var ar = AssetRegistryClass.get_instance()
		if ar != null:
			tex = ar.get_idea_icon(s_id)
			if tex == null and not sp_icon.is_empty():
				tex = ar.get_texture(sp_icon)
		if tex == null and not sp_icon.is_empty():
			tex = TNOTheme.get_texture(sp_icon)
		if tex == null:
			tex = TNOTheme.get_texture("res://assets/gfx/interface/war_support_icon.png")
		icon_rect.texture = tex

		card.add_child(icon_rect)
		card.tooltip_text = "┌── [%s] ──\n│ ТИП: Стартовый национальный дух // Кризис\n│ СТАТУС: Действует с 1 января 1962 г.\n├─────────────────────────────────────────\n│ ОПИСАНИЕ:\n│ %s\n├─────────────────────────────────────────\n│ СТРАТЕГИЧЕСКИЕ ЭФФЕКТЫ:\n%s" % [sp_name, sp_desc, sp_effects]

		spirits_grid.add_child(card)


"""Возвращает аутентичный состав кабинета министров для державы.
Включает должности:
- hog: Глава правительства
- for: Министр иностранных дел
- eco: Министр экономики и финансов
- sec: Министр безопасности и обороны
"""
static func get_canonical_ministers(tag: String) -> Dictionary:
	var clean_tag = tag.to_upper().strip_edges()
	
	# Справочник каноничных кабинетов TNO
	var ministers_db = {
		"GER": {
			"hog": {"name": "Мартин Борман", "full": "Рейхсляйтер и Секретарь Фюрера", "dep": "Партийная канцелярия НСДАП", "portrait": "res://assets/gfx/leaders/GER/GER_martin_bormann.png", "effects": "• Прирост политического капитала: +0.30/ход\n• Стабильность партократии: +8.0%\n• Контроль номенклатуры: Высокий"},
			"for": {"name": "Вальтер Хевель", "full": "Спецпредставитель МИД", "dep": "Рейхсминистерство иностранных дел", "portrait": "res://assets/gfx/leaders/GER/GER_kurt_georg_kiesinger.png", "effects": "• Дипломатический вес в Пакте: +20.0%\n• Сдерживание распада колоний: +15.0%"},
			"eco": {"name": "Альберт Шпеер", "full": "Рейхсминистр вооружения и промышленности", "dep": "Министерство военной промышленности", "portrait": "res://assets/gfx/leaders/GER/GER_albert_speer.png", "effects": "• Производительность фабрик: +12.0%\n• Эффективность конверсии ВПК: +15.0%\n• Стоимость проектов: -10.0%"},
			"sec": {"name": "Герман Геринг", "full": "Рейхсмаршал и Шеф Люфтваффе", "dep": "Имперское министерство авиации", "portrait": "res://assets/gfx/leaders/GER/GER_hermann_goring.png", "effects": "• Превосходство в воздухе: +25.0%\n• Поддержка армии: +12.0%\n• Готовность дивизий: +10.0%"}
		},
		"BOR": {
			"hog": {"name": "Мартин Борман", "full": "Рейхсканцлер Великогермании", "dep": "Партийная канцелярия НСДАП", "portrait": "res://assets/gfx/leaders/GER/GER_martin_bormann.png", "effects": "• Политический капитал: +0.35/ход\n• Доминирование партийного аппарата: +15.0%"},
			"for": {"name": "Курт Георг Кизингер", "full": "Рейхсминистр иностранных дел", "dep": "Рейхсминистерство иностранных дел", "portrait": "res://assets/gfx/leaders/GER/GER_kurt_georg_kiesinger.png", "effects": "• Дипломатический авторитет: +15.0%\n• Снижение изоляции: +10.0%"},
			"eco": {"name": "Карл Шиллер", "full": "Рейхсминистр экономики", "dep": "Министерство имперской экономики", "portrait": "", "effects": "• Рост ВВП: +0.4%\n• Снижение госдолга: +8.0%"},
			"sec": {"name": "Эрих Кох", "full": "Имперский министр безопасности", "dep": "Имперское управление безопасности", "portrait": "", "effects": "• Подавление мятежей: +20.0%\n• Лояльность гауляйтеров: +15.0%"}
		},
		"GOR": {
			"hog": {"name": "Герман Геринг", "full": "Рейхсканцлер Милитаристов", "dep": "Рейхсканцелярия милитаристов", "portrait": "res://assets/gfx/leaders/GER/GER_hermann_goring.png", "effects": "• Мобилизация промышленности: +20.0%\n• Военный дух: +15.0%"},
			"for": {"name": "Франц фон Папен", "full": "Министр иностранных сношений", "dep": "Дипломатический корпус Вермахта", "portrait": "", "effects": "• Военное давление на соседей: +25.0%"},
			"eco": {"name": "Ялмар Шахт", "full": "Президент Рейхсбанка", "dep": "Финансовый директорат ВПК", "portrait": "", "effects": "• Финансирование блицкригов: +25.0%\n• Военные кредиты: +15.0%"},
			"sec": {"name": "Фердинанд Шёрнер", "full": "Фельдмаршал Сухопутных Сил", "dep": "Верховное командование Вермахта", "portrait": "res://assets/gfx/leaders/GER/GER_ferdinand_schorner.png", "effects": "• Атака сухопутных дивизий: +15.0%\n• Потери в наступлении: -10.0%"}
		},
		"SPE": {
			"hog": {"name": "Альберт Шпеер", "full": "Рейхсканцлер-реформатор", "dep": "Канцелярия модернизации", "portrait": "res://assets/gfx/leaders/GER/GER_albert_speer.png", "effects": "• Эффективность реформ: +25.0%\n• Снижение коррупции: +15.0%"},
			"for": {"name": "Марион Дёнхоф", "full": "Министр внешних связей", "dep": "Министерство европейской интеграции", "portrait": "", "effects": "• Оттепель с США и ОФН: +30.0%\n• Международная торговля: +25.0%"},
			"eco": {"name": "Людвиг Эрхард", "full": "Министр свободного рынка", "dep": "Министерство экономики и финансов", "portrait": "", "effects": "• Реальный рост ВВП: +0.6%\n• Демонтаж картелей: +15.0%"},
			"sec": {"name": "Хеннинг фон Тресков", "full": "Шеф Реформированного Вермахта", "dep": "Министерство обороны", "portrait": "res://assets/gfx/leaders/GER/GER_henning_von_tresckow.png", "effects": "• Профессионализм армии: +20.0%\n• Искоренение эсэсовских пережитков: +30.0%"}
		},
		"HEY": {
			"hog": {"name": "Рейнхард Гейдрих", "full": "Рейхсфюрер и Протектор", "dep": "Штаб Черного Ордена", "portrait": "res://assets/gfx/leaders/GER/GER_reinhard_heydrich.png", "effects": "• Тотальный надзор: +35.0%\n• Безжалостность: +50.0%"},
			"for": {"name": "Вальтер Шелленберг", "full": "Шеф внешней разведки СД", "dep": "Внешняя служба РСХА", "portrait": "", "effects": "• Эффективность шпионажа: +40.0%"},
			"eco": {"name": "Освальд Поль", "full": "Начальник ВФХА СС", "dep": "Главное административно-хозяйственное управление", "portrait": "", "effects": "• Выработка рабского труда: +25.0%\n• Гуманитарные издержки: Игнорируются"},
			"sec": {"name": "Карл Вольф", "full": "Командующий Войсками СС", "dep": "Главное оперативное управление СС", "portrait": "", "effects": "• Боеготовность дивизий СС: +20.0%\n• Подавление восстаний: Жестокое"}
		},
		"USA": {
			"hog": {"name": "Джон Ф. Кеннеди", "full": "Вице-президент США", "dep": "Исполнительный офис Президента", "portrait": "res://assets/gfx/leaders/USA/USA_John_F_Kennedy.png", "effects": "• Общественное единство: +10.0%\n• Политический капитал: +0.25/ход\n• Принятие законов в Сенате: +15.0%"},
			"for": {"name": "Уильям Роджерс", "full": "Государственный секретарь", "dep": "Государственный департамент США", "portrait": "", "effects": "• Дипломатический вес ОФН: +25.0%\n• Эффективность альянсов: +15.0%"},
			"eco": {"name": "Роберт Макнамара", "full": "Министр планирования и бюджета", "dep": "Министерство финансов и снабжения", "portrait": "res://assets/gfx/leaders/USA/USA_Robert_McNamara.png", "effects": "• Бюджетная эффективность: +15.0%\n• Военные закупки: -10.0%\n• Промышленный индекс: +8.0%"},
			"sec": {"name": "Мелвин Лэрд", "full": "Министр обороны США", "dep": "Пентагон / Департамент обороны", "portrait": "", "effects": "• Готовность дивизий ОФН: +15.0%\n• Зарубежные военные базы: +20.0%"}
		},
		"JAP": {
			"hog": {"name": "Икэда Хаято", "full": "Премьер-министр Японии", "dep": "Канцелярия Кабинета Министров", "portrait": "", "effects": "• Экономический рост 'Плана удвоения': +0.5%\n• Стабильность правящей коалиции: +10.0%"},
			"for": {"name": "Фудзияма Айитиро", "full": "Министр иностранных дел", "dep": "Министерство иностранных дел", "portrait": "", "effects": "• Торговое влияние в Азии: +25.0%\n• Сдерживание американского флота: +10.0%"},
			"eco": {"name": "Канэмару Син", "full": "Министр финансов", "dep": "Министерство финансов Японии", "portrait": "", "effects": "• Налоговые поступления от дзайбацу: +12.0%\n• Снижение инфляции: +10.0%"},
			"sec": {"name": "Масаносукэ Икэда", "full": "Шеф Общественной Безопасности", "dep": "Национальное полицейское агентство", "portrait": "", "effects": "• Контрразведывательный контроль: +20.0%\n• Подавление студенческих волнений: +15.0%"}
		},
		"ITA": {
			"hog": {"name": "Карло Скорца", "full": "Секретарь Фашистской Партии", "dep": "Национальная фашистская партия", "portrait": "", "effects": "• Контроль над партийным аппаратом: +15.0%\n• Стабильность режима: +8.0%"},
			"for": {"name": "Дино Гранди", "full": "Министр иностранных дел", "dep": "Палаццо Киджи / МИД", "portrait": "", "effects": "• Влияние Триумвирата в Средиземноморье: +20.0%\n• Защита нефтяных концессий: +15.0%"},
			"eco": {"name": "Джакомо Ачербо", "full": "Министр корпоративной экономики", "dep": "Министерство корпораций", "portrait": "", "effects": "• Доходы от средиземноморской торговли: +15.0%\n• Развитие Юга Италии: +8.0%"},
			"sec": {"name": "Джованни Де Лоренцо", "full": "Командующий Корпусом Карабинеров", "dep": "Генеральное командование Карабинеров", "portrait": "", "effects": "• Внутренняя безопасность: +18.0%\n• Предотвращение военных заговоров: +25.0%"}
		},
		"IBR": {
			"hog": {"name": "Антониу ди Оливейра Салазар", "full": "Со-правитель Иберийского Союза", "dep": "Лиссабонский Президиум Союза", "portrait": "", "effects": "• Финансовая дисциплина Союза: +15.0%\n• Политический баланс Испании и Португалии: Стабильный"},
			"for": {"name": "Фернандо Мария Кастиэлья", "full": "Министр иностранных дел", "dep": "Дипломатический директорат Иберии", "portrait": "", "effects": "• Переговоры с США и Рейхом: +20.0%\n• Статус Гибралтара: Защищен"},
			"eco": {"name": "Жозе Феррейра Диаш", "full": "Министр экономики и развития", "dep": "Министерство промышленности и торговли", "portrait": "", "effects": "• Электрификация и индустрия: +12.0%\n• Приток иностранных инвестиций: +15.0%"},
			"sec": {"name": "Антонио Барросо Санчес", "full": "Министр армии и обороны", "dep": "Объединенный генеральный штаб", "portrait": "", "effects": "• Подавление баскского и каталонского подполья: +25.0%\n• Единство вооруженных сил: +15.0%"}
		},
		"BRG": {
			"hog": {"name": "Готтлоб Бергер", "full": "Начальник Главного Управления СС", "dep": "Главный штаб Орденсштадта", "portrait": "", "effects": "• Мобилизация верных эсэсовцев: +30.0%\n• Дисциплина Черного Солнца: 100%"},
			"for": {"name": "Иоахим фон Риббентроп", "full": "Эмиссар Внешних Провокаций", "dep": "Дипломатическая секция СД", "portrait": "", "effects": "• Разжигание глобальных конфликтов: +35.0%\n• Тайные операции: +25.0%"},
			"eco": {"name": "Освальд Поль", "full": "Шеф ВФХА Бургундии", "dep": "Концлагерная экономика Ордена", "portrait": "", "effects": "• Подземное строительство бункеров: +40.0%\n• Изъятие ресурсов у населения: Тотальное"},
			"sec": {"name": "Зепп Дитрих", "full": "Оберстгруппенфюрер СС", "dep": "Войска СС Орденсштадта", "portrait": "", "effects": "• Беспощадность к саботажникам: +50.0%\n• Охрана ядерных объектов: Максимальная"}
		},
		"ENG": {
			"hog": {"name": "Эндрю Фаунтен", "full": "Премьер-министр Коллаборационистов", "dep": "Правительство Лондона", "portrait": "res://assets/gfx/leaders/ENG/ENG_Andrew_Fountaine.png", "effects": "• Лояльность пакту с Берлином: +20.0%\n• Политический вес: +0.2/ход"},
			"for": {"name": "Рональд Нолл-Кейн", "full": "Министр иностранных дел", "dep": "Форин-офис Лондона", "portrait": "", "effects": "• Торговля с Великогерманией: +20.0%"},
			"eco": {"name": "Рэб Батлер", "full": "Канцлер Казначейства", "dep": "Казначейство Его Величества", "portrait": "", "effects": "• Сбор налогов: +10.0%\n• Промышленное восстановление: +8.0%"},
			"sec": {"name": "Эдмунд Веезенмайер", "full": "Имперский уполномоченный безопасности", "dep": "Немецкий надзорный корпус", "portrait": "", "effects": "• Подавление Сопротивления (HMMLR): +25.0%\n• Контроль гарнизонов: +15.0%"}
		},
		"TUR": {
			"hog": {"name": "Фахри Корутюрк", "full": "Премьер-министр Турции", "dep": "Совет Министров Республики", "portrait": "", "effects": "• Стабильность кемалистского строя: +12.0%\n• Контроль Проливов: +20.0%"},
			"for": {"name": "Феридун Джемаль Эркин", "full": "Министр иностранных дел", "dep": "Министерство иностранных дел Турции", "portrait": "", "effects": "• Дипломатический баланс между блоками: +18.0%"},
			"eco": {"name": "Ферит Мелен", "full": "Министр финансов", "dep": "Министерство финансов", "portrait": "", "effects": "• Промышленное развитие Анатолии: +10.0%"},
			"sec": {"name": "Джемаль Гюрсель", "full": "Начальник Генерального Штаба", "dep": "Генеральный штаб вооруженных сил", "portrait": "", "effects": "• Боеготовность сухопутной армии: +15.0%\n• Охрана границ Кавказа и Леванта: +20.0%"}
		},
		"GNG": {
			"hog": {"name": "Мацудзава Такудзи", "full": "Главный Исполнительный Директор", "dep": "Исполнительный Совет Корпораций", "portrait": "", "effects": "• Прибыль мегакорпораций: +25.0%\n• Технократическое планирование: +15.0%"},
			"for": {"name": "Ибука Масару", "full": "Президент Sony, посол технологий", "dep": "Внешнеторговая дирекция Гуандуна", "portrait": "res://assets/gfx/leaders/GNG/GNG_ibuka_masaru.png", "effects": "• Экспорт передовой электроники: +30.0%\n• Связи с Токио и Гонконгом: +20.0%"},
			"eco": {"name": "Мацусита Масахару", "full": "Президент Matsushita Electric", "dep": "Министерство тяжелой индустрии", "portrait": "", "effects": "• Производительность сборочных линий: +20.0%\n• Доходы от бытовой техники: +18.0%"},
			"sec": {"name": "Миядзаки Киётака", "full": "Шеф Полиции Кэмпэйтай", "dep": "Гарнизон Особой Охраны", "portrait": "", "effects": "• Предотвращение забастовок рабочих: +35.0%\n• Безопасность заводских анклавов: +25.0%"}
		},
		"CHI": {
			"hog": {"name": "Чжоу Фохай", "full": "Председатель Исполнительного Юаня", "dep": "Исполнительный Юань Нанкина", "portrait": "", "effects": "• Административная реформа Китая: +15.0%\n• Политический капитал: +0.25/ход"},
			"for": {"name": "Тао Сишэн", "full": "Министр иностранных дел", "dep": "Министерство иностранных дел", "portrait": "", "effects": "• Дипломатическое маневрирование в Сфере: +20.0%"},
			"eco": {"name": "Чжан Жэньли", "full": "Министр финансов Поднебесной", "dep": "Министерство финансов", "portrait": "", "effects": "• Возрождение национальной валюты: +12.0%\n• Тайное финансирование ВПК: +15.0%"},
			"sec": {"name": "Сяо Шусюань", "full": "Министр военной безопасности", "dep": "Министерство обороны Нанкина", "portrait": "", "effects": "• Тайная подготовка дивизий к Войне: +20.0%\n• Контршпионаж против Квантунцев: +15.0%"}
		},
		"MAN": {
			"hog": {"name": "Жуань Чжэньдо", "full": "Премьер-министр Маньчжоу-Го", "dep": "Государственный совет Синьцзина", "portrait": "", "effects": "• Покорность Императорскому Двору: +15.0%"},
			"for": {"name": "Гу Цичэн", "full": "Министр иностранных дел", "dep": "Министерство внешних сношений", "portrait": "", "effects": "• Интеграция с Квантунской армией: +25.0%"},
			"eco": {"name": "Юй Цзинъюань", "full": "Министр экономики и недр", "dep": "Министерство угольной и стальной индустрии", "portrait": "", "effects": "• Вывоз сырья в Японию: +30.0%\n• Продукция шахт Аньшаня: +20.0%"},
			"sec": {"name": "Юй Цзинтао", "full": "Шеф Корпуса Безопасности", "dep": "Имперская полиция и жандармерия", "portrait": "", "effects": "• Подавление партизан в тайге: +25.0%"}
		},
		"THA": {
			"hog": {"name": "Луанг Вичитватхакан", "full": "Глава правительства Сиама", "dep": "Канцелярия Фельдмаршала", "portrait": "", "effects": "• Националистическая пропаганда: +18.0%"},
			"for": {"name": "Санг Пхатанотхай", "full": "Министр иностранных дел", "dep": "Министерство иностранных дел", "portrait": "", "effects": "• Паназиатская солидарность: +15.0%"},
			"eco": {"name": "Сукич Нимманхеминда", "full": "Министр финансов", "dep": "Королевское казначейство", "portrait": "", "effects": "• Доходы от рисового экспорта: +15.0%"},
			"sec": {"name": "Прамарн Адирексарн", "full": "Министр внутренних дел", "dep": "Королевская полиция Сиама", "portrait": "", "effects": "• Безопасность Бангкока: +20.0%"}
		},
		"YUN": {
			"hog": {"name": "Лу Хан", "full": "Военный Губернатор Юньнани", "dep": "Штаб Губернатора в Куньмине", "portrait": "", "effects": "• Сплочение юньнаньских ополченцев: +20.0%"},
			"for": {"name": "Лун Цзэхуэй", "full": "Комиссар внешних связей", "dep": "Дипломатический стол Куньмина", "portrait": "", "effects": "• Контакты с бирманскими и тибетскими повстанцами: +25.0%"},
			"eco": {"name": "Ван Шаоюань", "full": "Казначей провинции", "dep": "Финансовый совет Юньнани", "portrait": "", "effects": "• Сбор оловянной и чайной подати: +15.0%"},
			"sec": {"name": "Цзэн Ваньчжун", "full": "Командующий гарнизоном", "dep": "Оборонный комитет Куньмина", "portrait": "", "effects": "• Защита горных перевалов: +30.0%"}
		},
		"OMS": {
			"hog": {"name": "Дмитрий Язов", "full": "Начальник Генштаба Черной Лиги", "dep": "Центральный штаб Великого Суда", "portrait": "res://assets/gfx/leaders/OMS/OMS_Dmitry_Yazov.png", "effects": "• Непреклонная дисциплина Лиги: +25.0%\n• Скорость подготовки ополчения: +20.0%\n• Готовность к Последней Войне: 99%"},
			"for": {"name": "Виктор Абакумов", "full": "Начальник СМЕРШ Черной Лиги", "dep": "Управление внешней агентуры и возмездия", "portrait": "", "effects": "• Разведка позиций Рейха за Уралом: +30.0%\n• Ликвидация вражеских лазутчиков: +40.0%"},
			"eco": {"name": "Александр Хархардин", "full": "Председатель ВПК Черной Лиги", "dep": "Подземные арсеналы Омска", "portrait": "", "effects": "• Выпуск стрелкового оружия и снарядов: +25.0%\n• Скорость возведения бункеров: +35.0%"},
			"sec": {"name": "Константин Валухин", "full": "Комендант Оборонительных Рубежей", "dep": "Комендатура Железного Порядка", "portrait": "", "effects": "• Защита от немецких бомбардировок: +25.0%\n• Искоренение пораженчества: Беспощадное"}
		},
		"WRS": {
			"hog": {"name": "Семён Тимошенко", "full": "Зам. Председателя Реввоенсовета", "dep": "Ставка Западнорусского Фронта", "portrait": "", "effects": "• Боевой дух ветеранов РККА: +20.0%\n• Политический капитал: +0.25/ход"},
			"for": {"name": "Андрей Гречко", "full": "Комиссар по внешним делам Фронта", "dep": "Дипломатический отдел Штаба", "portrait": "", "effects": "• Переговоры с партизанами Московии: +25.0%\n• Авторитет среди левых движений: +20.0%"},
			"eco": {"name": "Николай Байбаков", "full": "Нарком нефти и снабжения армии", "dep": "Наркомат снабжения и логистики", "portrait": "", "effects": "• Топливное снабжение танковых частей: +30.0%\n• Восстановление разрушенных заводов: +15.0%"},
			"sec": {"name": "Александр Алтунин", "full": "Комендант фронтовой контрразведки", "dep": "Управление военной контрразведки", "portrait": "res://assets/gfx/leaders/WRS/WRS_Alexander_Altunin.png", "effects": "• Искоренение немецких диверсантов: +35.0%\n• Стойкость гарнизонов Архангельска: +20.0%"}
		},
		"SVR": {
			"hog": {"name": "Павел Батов", "full": "Командующий Войсками УрВО", "dep": "Штаб Уральского Военного Округа", "portrait": "res://assets/gfx/leaders/SVR/SVR_Pavel_Batov.png", "effects": "• Сплоченность уральских батальонов: +20.0%\n• Прагматизм в управлении: Высокий"},
			"for": {"name": "Анатолий Добрынин", "full": "Дипломатический комиссар округа", "dep": "Отдел внешних сношений Свердловска", "portrait": "", "effects": "• Дипломатическое влияние на соседей: +20.0%"},
			"eco": {"name": "Фарман Салманов", "full": "Главный геолог и куратор недр", "dep": "Урало-Сибирский геологоразведочный трест", "portrait": "", "effects": "• Добыча нефти и стратегических руд: +25.0%\n• Промышленный потенциал заводов Урала: +18.0%"},
			"sec": {"name": "Иван Баграмян", "full": "Начальник штаба обороны Урала", "dep": "Оперативное управление штаба", "portrait": "", "effects": "• Организация танковых прорывов: +20.0%\n• Защита от налетов Люфтваффе: +20.0%"}
		},
		"TOM": {
			"hog": {"name": "Андрей Синявский", "full": "Спикер Думы Республики Томск", "dep": "Совет Четырех Салонов", "portrait": "", "effects": "• Свобода слова и мысли: +30.0%\n• Интеллектуальный приток: +25.0%"},
			"for": {"name": "Дмитрий Лихачёв", "full": "Министр просвещения и культуры", "dep": "Министерство гуманитарных связей", "portrait": "", "effects": "• Моральный авторитет Республики: +35.0%\n• Международное признание: +20.0%"},
			"eco": {"name": "Александр Есенин-Вольпин", "full": "Председатель Плановой Комиссии", "dep": "Госплан Салона Модернистов", "portrait": "", "effects": "• Развитие науки и кибернетики: +25.0%\n• Эффективность университетских лабораторий: +30.0%"},
			"sec": {"name": "Матвей Шапошников", "full": "Генерал Гражданской Гвардии", "dep": "Министерство защиты граждан", "portrait": "", "effects": "• Народная милиция Томска: +20.0%\n• Отказ от применения силы против народа: Полный"}
		},
		"KOM": {
			"hog": {"name": "Михаил Родионов", "full": "Глава кабинета министров Коми", "dep": "Правительство Сыктывкара", "portrait": "", "effects": "• Баланс парламентских сил: Хрупкий\n• Политический капитал: +0.20/ход"},
			"for": {"name": "Вячеслав Малышев", "full": "Комиссар внешнеэкономических связей", "dep": "Внешнеторговая комиссия", "portrait": "", "effects": "• Торговля лесом и рудами: +15.0%"},
			"eco": {"name": "Леонид Канторович", "full": "Главный экономист-математик", "dep": "Институт оптимального планирования", "portrait": "", "effects": "• Математическая оптимизация ресурсов: +20.0%\n• Рост ВВП: +0.4%"},
			"sec": {"name": "Егор Лигачёв", "full": "Шеф Республиканской Милиции", "dep": "Министерство внутренних дел Коми", "portrait": "", "effects": "• Сдерживание уличных беспорядков: +25.0%\n• Борьба с экстремистами: +20.0%"}
		},
		"NOV": {
			"hog": {"name": "Василий Шукшин", "full": "Председатель Сибирской Думы", "dep": "Гражданский Совет Новосибирска", "portrait": "", "effects": "• Доверие сибирских крестьян и рабочих: +25.0%\n• Политический капитал: +0.25/ход"},
			"for": {"name": "Николай Скоморохов", "full": "Внешнеторговый комиссар", "dep": "Торговый департамент Корпорации Сибирь", "portrait": "", "effects": "• Продажа сибирской стали и станков: +25.0%"},
			"eco": {"name": "Георгий Лангемак", "full": "Генеральный конструктор ВПК", "dep": "Научно-производственный трест", "portrait": "", "effects": "• Модернизация авиационных и ракетных заводов: +30.0%\n• Рост ВВП: +0.5%"},
			"sec": {"name": "Дмитрий Глинка", "full": "Командир Авиационной Охраны", "dep": "Воздушный патруль Новосибирска", "portrait": "", "effects": "• Очистка неба от вражеских разведчиков: +30.0%\n• Безопасность транспортных узлов: +20.0%"}
		},
		"BRY": {
			"hog": {"name": "Сусанна Печуро", "full": "Председатель Комитета Младоленинцев", "dep": "Революционный Исполком Бурятии", "portrait": "", "effects": "• Революционный энтузиазм молодежи: +30.0%\n• Искоренение партийного бюрократизма: +25.0%"},
			"for": {"name": "Отто Браун", "full": "Эмиссар Интернациональной Солидарности", "dep": "Комиссариат внешних связей", "portrait": "", "effects": "• Связи с партизанами Китая и Кореи: +25.0%"},
			"eco": {"name": "Майя Улановская", "full": "Куратор Кооперативной Экономики", "dep": "Совет рабочих синдикатов", "portrait": "", "effects": "• Справедливое распределение благ: +20.0%\n• Рост благосостояния рабочих: +15.0%"},
			"sec": {"name": "Михаил Мархеев", "full": "Начальник Революционной Стражи", "dep": "Ополчение защитников Октября", "portrait": "", "effects": "• Идейная стойкость бойцов: +25.0%\n• Защита от чекистских провокаций: +30.0%"}
		},
		"SBA": {
			"hog": {"name": "Пётр Сиуда", "full": "Делегат Общесибирского Схода", "dep": "Вольное Вече Канска", "portrait": "", "effects": "• Прямое народовластие без чиновников: 100%\n• Самоорганизация общин: +30.0%"},
			"for": {"name": "Евгения Таратута", "full": "Координатор Свободных Связей", "dep": "Комитет братской взаимопомощи", "portrait": "", "effects": "• Распространение анархических идей: +35.0%"},
			"eco": {"name": "Михаил Кильчичаков", "full": "Куратор Взаимопомощи и Артелей", "dep": "Совет вольных артелей", "portrait": "", "effects": "• Ликвидация денежного гнета: Полная\n• Производство товаров для жизни: +20.0%"},
			"sec": {"name": "Степан Валентеев", "full": "Командир Чёрной Гвардии", "dep": "Штаб Чёрных Партизан", "portrait": "", "effects": "• Добровольческая армия анархистов: +25.0%\n• Защита вольных коммун: Самоотверженная"}
		},
		"SAM": {
			"hog": {"name": "Михаил Меандров", "full": "Председатель Президиума КОНР", "dep": "Гражданское управление Самары", "portrait": "", "effects": "• Административное управление Поволжьем: +15.0%"},
			"for": {"name": "Василий Малышкин", "full": "Главный дипломат РОА", "dep": "Отдел внешних связей КОНР", "portrait": "", "effects": "• Поставки медикаментов и оружия из Рейха: +20.0%"},
			"eco": {"name": "Дмитрий Закутный", "full": "Начальник Гражданского Снабжения", "dep": "Комитет хозяйственного возрождения", "portrait": "", "effects": "• Сбор продовольствия с волжских деревень: +18.0%"},
			"sec": {"name": "Фёдор Трухин", "full": "Начальник Штаба Вооруженных Сил КОНР", "dep": "Генеральный штаб РОА", "portrait": "", "effects": "• Выучка дивизий РОА: +18.0%\n• Подавление советского подполья: +25.0%"}
		},
		"TYM": {
			"hog": {"name": "Никита Хрущёв", "full": "Второй секретарь Обкома партии", "dep": "Тюменский Партийный Комитет", "portrait": "", "effects": "• Партийная дисциплина: +15.0%\n• Ускорение пятилеток: +12.0%"},
			"for": {"name": "Вячеслав Молотов", "full": "Нарком иностранных дел СССР", "dep": "Дипломатическая миссия большевиков", "portrait": "", "effects": "• Догматическая верность марксизму-ленинизму: 100%"},
			"eco": {"name": "Михаил Каганович", "full": "Нарком тяжелой промышленности", "dep": "Тюменский индустриальный главк", "portrait": "", "effects": "• Выплавка чугуна и стали: +25.0%\n• Стахановское движение: +20.0%"},
			"sec": {"name": "Иван Конев", "full": "Командующий Армией Реванша", "dep": "Реввоенсовет Тюмени", "portrait": "", "effects": "• Мощь артиллерийских ударов: +25.0%\n• Наступление стальных колонн: +18.0%"}
		},
		"TYU": {
			"hog": {"name": "Никита Хрущёв", "full": "Второй секретарь Обкома партии", "dep": "Тюменский Партийный Комитет", "portrait": "", "effects": "• Партийная дисциплина: +15.0%\n• Ускорение пятилеток: +12.0%"},
			"for": {"name": "Вячеслав Молотов", "full": "Нарком иностранных дел СССР", "dep": "Дипломатическая миссия большевиков", "portrait": "", "effects": "• Догматическая верность марксизму-ленинизму: 100%"},
			"eco": {"name": "Михаил Каганович", "full": "Нарком тяжелой промышленности", "dep": "Тюменский индустриальный главк", "portrait": "", "effects": "• Выплавка чугуна и стали: +25.0%\n• Стахановское движение: +20.0%"},
			"sec": {"name": "Иван Конев", "full": "Командующий Армией Реванша", "dep": "Реввоенсовет Тюмени", "portrait": "", "effects": "• Мощь артиллерийских ударов: +25.0%\n• Наступление стальных колонн: +18.0%"}
		},
		"VYT": {
			"hog": {"name": "Владимир Харжевский", "full": "Генерал-майор, Премьер-министр", "dep": "Правительство Российской Империи", "portrait": "", "effects": "• Монархический порядок: +18.0%\n• Политический капитал: +0.25/ход"},
			"for": {"name": "Роман Гуль", "full": "Министр внешних сношений и идеолог НТС", "dep": "Министерство иностранных дел", "portrait": "", "effects": "• Связи с белой эмиграцией в Париже и Нью-Йорке: +30.0%"},
			"eco": {"name": "Глеб Рар", "full": "Управляющий Имперским Казначейством", "dep": "Министерство финансов Вятки", "portrait": "", "effects": "• Приток золотых пожертвований монархистов: +20.0%"},
			"sec": {"name": "Евгений Месснер", "full": "Начальник Имперской Контрразведки", "dep": "Особый отдел мятежевойны", "portrait": "", "effects": "• Стратегия асимметричной войны: +25.0%\n• Охрана Государя Императора: Надежная"}
		},
		"IRK": {
			"hog": {"name": "Яков Агранов", "full": "Зам. Председателя Президиума", "dep": "Президиум Верховного Совета в Иркутске", "portrait": "", "effects": "• Чекистский контроль над регионом: +25.0%"},
			"for": {"name": "Сергей Бессонов", "full": "Нарком иностранных дел", "dep": "Наркомат иностранных дел", "portrait": "", "effects": "• Международные контакты в Азии: +15.0%"},
			"eco": {"name": "Григорий Гринько", "full": "Нарком финансов СССР", "dep": "Финансово-бюджетный главк", "portrait": "", "effects": "• Конфискация и распределение ресурсов: +20.0%"},
			"sec": {"name": "Павел Буланов", "full": "Секретарь Особого Отдела НКВД", "dep": "Коллегия органов госбезопасности", "portrait": "", "effects": "• Беспощадное подавление диссидентов: +35.0%\n• Надзор над Байкальской флотилией: +25.0%"}
		},
		"MAG": {
			"hog": {"name": "Владимир Кибардин", "full": "Председатель Совета Министров", "dep": "Правительство Магадана", "portrait": "", "effects": "• Политический баланс РФП: +15.0%"},
			"for": {"name": "Николай Петлин", "full": "Эмиссар по связям с США и ОФН", "dep": "Внешнеполитическое бюро", "portrait": "", "effects": "• Приток американских инвестиций и долларов: +35.0%"},
			"eco": {"name": "Владимир Гольцов", "full": "Куратор Портовой Коммерции", "dep": "Таможенно-промышленный комитет", "portrait": "", "effects": "• Доходы от тихоокеанских конвоев: +25.0%"},
			"sec": {"name": "Александр Павлов", "full": "Шеф Магаданской Милиции", "dep": "Управление охраны правопорядка", "portrait": "res://assets/gfx/leaders/MAG/MAG_Alexander_Pavlov.png", "effects": "• Охрана американских советников: +25.0%\n• Подавление коммунистических ячеек: +20.0%"}
		},
		"AMR": {
			"hog": {"name": "Лев Охотин", "full": "Член Верховного Совета ВФО", "dep": "Центральный комитет Всероссийской Фашистской Организации", "portrait": "", "effects": "• Идеологическая чистота партии: +25.0%"},
			"for": {"name": "Михаил Спасовский", "full": "Эмиссар фашистской пропаганды", "dep": "Отдел внешних связей ВФО", "portrait": "", "effects": "• Пропаганда расового крестового похода: +30.0%"},
			"eco": {"name": "Константин Стеклов", "full": "Главный казначей партии", "dep": "Финансовый отдел ВФО", "portrait": "", "effects": "• Экспроприация имущества врагов нации: +25.0%"},
			"sec": {"name": "Александр Болотов", "full": "Командир Чернорубашечников", "dep": "Штаб фашистских штурмовых отрядов", "portrait": "res://assets/gfx/leaders/AMR/AMR_Alexander_Bolotov.png", "effects": "• Террор против инакомыслящих: +35.0%\n• Фанатизм штурмовых рот: Высокий"}
		},
		"CHT": {
			"hog": {"name": "Григорий Семёнов", "full": "Атаман Забайкальского Войска", "dep": "Войсковой штаб в Чите", "portrait": "", "effects": "• Казачья преданность: +25.0%\n• Военная власть атамана: Абсолютная"},
			"for": {"name": "Николай Ухтомский", "full": "Дипломатический советник князя", "dep": "Канцелярия монархических связей", "portrait": "", "effects": "• Поддержка японской Квантунской армии: +25.0%"},
			"eco": {"name": "Иван Михайлов", "full": "Казначей Белой Армии", "dep": "Войсковая казна Забайкалья", "portrait": "", "effects": "• Сбор податей с золотых приисков: +20.0%"},
			"sec": {"name": "Борис Шепунов", "full": "Командир Особого Дивизиона", "dep": "Атаманская казачья сотня", "portrait": "res://assets/gfx/leaders/CHT/CHT_Boris_Shepunov.png", "effects": "• Жестокие рейды против партизан: +30.0%"}
		},
		"KEM": {
			"hog": {"name": "Юрий Крылов", "full": "Царевич и Престолонаследник", "dep": "Княжеская Дума Кемерово", "portrait": "", "effects": "• Народная любовь к Царевичу: +25.0%\n• Баланс интересов общин: +15.0%"},
			"for": {"name": "Пётр Барановский", "full": "Хранитель Древностей и Посол", "dep": "Посольский приказ Кемерово", "portrait": "", "effects": "• Возрождение древнерусской славы: +25.0%"},
			"eco": {"name": "Лев Вознесенский", "full": "Казначей Кемеровских Общин", "dep": "Царская казна и амбары", "portrait": "", "effects": "• Развитие кузбасских угольных копей: +20.0%"},
			"sec": {"name": "Иван Яковлев", "full": "Воевода Княжеской Дружины", "dep": "Царская дружина Рюриковичей", "portrait": "", "effects": "• Верность дружинников Царю: 100%\n• Стойкость в обороне сибирских рубежей: +20.0%"}
		}
	}
	
	if ministers_db.has(clean_tag):
		return ministers_db[clean_tag]
		
	# Fallback по умолчанию для любого неизвестного тэга
	return {
		"hog": {"name": "Председатель Правительства", "full": "Глава исполнительной власти", "dep": "Канцелярия правительства", "portrait": "", "effects": "• Политический капитал: +0.25/ход\n• Стабильность: +5.0%"},
		"for": {"name": "Министр Иностранных Дел", "full": "Глава дипломатического ведомства", "dep": "Министерство иностранных дел", "portrait": "", "effects": "• Дипломатический вес: +15.0%"},
		"eco": {"name": "Министр Финансов и Экономики", "full": "Куратор государственного бюджета", "dep": "Министерство финансов", "portrait": "", "effects": "• Рост ВВП: +0.2%\n• Доходы фабрик: +10.0%"},
		"sec": {"name": "Министр Обороны и Безопасности", "full": "Командующий силами правопорядка", "dep": "Министерство обороны", "portrait": "", "effects": "• Боеготовность войск: +10.0%\n• Общественный порядок: +15.0%"}
	}
