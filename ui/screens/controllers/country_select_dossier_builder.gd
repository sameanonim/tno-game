class_name CountrySelectDossierBuilder
extends Node

##
## CountrySelectDossierBuilder: Построитель досье партий, кабинета министров и национальных духов
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
		"OMS": {
			"ultranationalism": "Черная Лига (Великий Суд)",
			"despotism": "Военный штаб Лиги",
			"communist": "Подпольные советы"
		},
		"WRS": {
			"socialist": "Революционный Военсовет",
			"communist": "Политсовет РККА",
			"despotism": "Штаб фронта"
		},
		"SVR": {
			"paternalism": "Уральская Администрация",
			"despotism": "Генералитет Батова",
			"conservatism": "Гражданские инженеры"
		},
		"JAP": {
			"fascism": "Ассоциация Помощи Трону",
			"paternalism": "Бюрократическая фракция",
			"despotism": "Императорская Армия"
		},
		"ITA": {
			"fascism": "Фашистская Партия (PNF)",
			"paternalism": "Монархисты и Сенат",
			"conservatism": "Христианские демократы"
		},
		"TOM": {
			"liberalism": "Салон Декабристов",
			"conservatism": "Салон Модернистов",
			"progressivism": "Салон Бастурмы",
			"paternalism": "Салон Евразийцев"
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

		party_items.append({
			"id": k,
			"name": p_name,
			"popularity": val,
			"color": base_info["color"],
			"desc": base_info["desc"]
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

	var c_path = "res://data/countries/%s/country.json" % tag
	var found_ideas: Array = []
	if FileAccess.file_exists(c_path):
		var f = FileAccess.open(c_path, FileAccess.READ)
		if f != null:
			var json = JSON.new()
			if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
				var c_data = json.data as Dictionary
				found_ideas = c_data.get("ideas", [])
			f.close()

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

	var known_names = {
		"Martin_Bormann": "Мартин Борман",
		"Albert_Speer": "Альберт Шпеер",
		"Walther_Hewel": "Вальтер Хевель",
		"Hermann_Goring": "Герман Геринг",
		"John_F_Kennedy": "Джон Ф. Кеннеди",
		"William_P_Rogers": "Уильям Роджерс",
		"Robert_McNamara": "Роберт Макнамара",
		"Melvin_Laird": "Мелвин Лэйрд",
		"Dmitry_Yazov": "Дмитрий Язов",
		"Viktor_Abakumov": "Виктор Абакумов",
		"Alexander_Kharkhardin": "Александр Хархардин",
		"Konstantin_Valukhin": "Константин Валухин",
		"Semyon_Timoshenko": "Семён Тимошенко",
		"Nikolay_Baibakov": "Николай Байбаков",
		"Andrey_Grechko": "Андрей Гречко",
		"Alexander_Altunin": "Александр Алтунин",
		"Mikhail_Rodionov": "Михаил Родионов",
		"Vyacheslav_Malyshev": "Вячеслав Малышев",
		"Yegor_Ligachev": "Егор Лигачев",
		"Leonid_Kantorovich": "Леонид Канторович",
		"Pavel_Batov": "Павел Батов",
		"Anatoly_Dobrynin": "Анатолий Добрынин",
		"Farman_Salmanov": "Фарман Салманов",
		"Ivan_Bagramyan": "Иван Баграмян",
		"Carlo_Scorza": "Карло Скорца",
		"Dino_Grandi": "Дино Гранди",
		"Giacomo_Acerbo": "Джакомо Ачербо",
		"Giovanni_De_Lorenzo": "Джованни Де Лоренцо",
		"Ikeda_Hayato": "Хаято Икэда",
		"Fujiyama_Aiichiro": "Аиитиро Фудзияма",
		"Kanemaru_Shin": "Син Канэмару",
		"Masanosuke_Ikeda": "Масаносукэ Икэда"
	}

	var roles = ["hog", "for", "eco", "sec"]
	for r in roles:
		var r_data = role_meta[r]
		var found_name := ""
		var minister_portrait_tex: Texture2D = null

		for id_item in found_ideas:
			var sid = str(id_item)
			if sid.ends_with("_" + r):
				var parts = sid.split("_")
				if parts.size() >= 3:
					var raw_name = sid.substr(parts[0].length() + 1, sid.length() - parts[0].length() - parts[parts.size() - 1].length() - 2)
					found_name = known_names.get(raw_name, raw_name.replace("_", " "))

					var target_lower = ("%s_%s.png" % [tag, raw_name]).to_lower()
					var alt_lower = ("%s.png" % raw_name).to_lower()
					var tag_dir = "res://assets/gfx/leaders/%s" % tag
					if DirAccess.dir_exists_absolute(tag_dir):
						var da = DirAccess.open(tag_dir)
						if da != null:
							da.list_dir_begin()
							var fn = da.get_next()
							while not fn.is_empty():
								if not da.current_is_dir() and fn.ends_with(".png"):
									var fn_l = fn.to_lower()
									if fn_l == target_lower or fn_l == alt_lower:
										var exact_p = tag_dir.path_join(fn)
										var res = load(exact_p)
										if res is Texture2D:
											minister_portrait_tex = res
											break
								fn = da.get_next()
							da.list_dir_end()
				break

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

		card.tooltip_text = "┌── [КАБИНЕТ МИНИСТРОВ // CABINET OF MINISTERS] ──\n│ ДОЛЖНОСТЬ: %s\n│ МИНИСТР: %s\n│ ВЕДОМСТВО: %s\n├─────────────────────────────────────────\n│ СТРАТЕГИЧЕСКИЕ ЭФФЕКТЫ ВЕДОМСТВА:\n%s" % [r_data["full"], found_name, r_data["dep"], r_data["effects"]]
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
		"USA_segregation": {
			"name": "Тень сегрегации Джима Кроу",
			"icon": "res://assets/gfx/interface/war_support_icon.png",
			"desc": "Глубокий расовый раскол раскалывает американское общество и ставит под угрозу единство нации.",
			"effects": "• Радикализация в южных штатах: +18.0%\n• Общественная напряженность: Высокая\n• Риск массовых беспорядков"
		},
		"USA_civil_rights": {
			"name": "Борьба за Гражданские Права",
			"icon": "res://assets/gfx/interface/pol_power_icon.png",
			"desc": "Марши протеста и ожесточенные дебаты в Конгрессе о будущем равноправия всех граждан Америки.",
			"effects": "• Раскол в Сенате: Острый\n• Приток политического капитала: -0.15/ход\n• Шанс принятия исторического Билля"
		},
		"USA_hawaii_shame": {
			"name": "Позор Гавайского Договора",
			"icon": "res://assets/gfx/interface/war_support_icon.png",
			"desc": "Утрата Гаваев и баз на Тихом океане остается незаживающей раной национального самосознания США.",
			"effects": "• Военная решимость нации: Высокая\n• Жажда геополитического реванша: +25.0%\n• Штраф к легитимности президента"
		},
		"USA_ofn_leader": {
			"name": "Флагман Свободного Мира (ОФН)",
			"icon": "res://assets/gfx/interface/goals/focus_GER_a_common_goal.png",
			"desc": "Организация Свободных Наций — главный оплот демократии против германского и японского тоталитаризма.",
			"effects": "• Влияние в блоке ОФН: Абсолютное\n• Ленд-лиз союзникам: +30.0%\n• Глобальное дипломатическое лидерство"
		},
		"OMS_the_great_trial": {
			"name": "Великий Суд над Тевтонами",
			"icon": "res://assets/gfx/interface/war_support_icon.png",
			"desc": "Единственная цель существования Омска — тотальное уничтожение Германии любой ценой, включая ядерный пепел.",
			"effects": "• Поддержка войны: 100.0%\n• Мобилизация: Тотальная\n• Общество: Военный лагерь"
		},
		"WRS_red_army_cadres": {
			"name": "Костяк Непобедимой РККА",
			"icon": "res://assets/gfx/interface/goals/focus_GER_a_german_wehrmacht.png",
			"desc": "Опытные маршалы и командиры, прошедшие горнило Второй мировой и отразившие бомбардировки люфтваффе.",
			"effects": "• Мораль армии: +20.0%\n• Стоимость призыва дивизий: -15.0%\n• Профессиональная военная выучка"
		},
		"SVR_batov_discipline": {
			"name": "Служить России (Генерал Батов)",
			"icon": "res://assets/gfx/interface/goals/focus_GER_bormann_army.png",
			"desc": "Железный уральский прагматизм и преданность долгу перед русским народом без пустой идеологической демагогии.",
			"effects": "• Дисциплина дивизий: Железная\n• Стабильность фронта: +15.0%\n• Эффективность снабжения: +20.0%"
		},
		"JAP_yasuda_shadow": {
			"name": "Тень краха банка Ясуда",
			"icon": "res://assets/gfx/interface/industrial_capacity_icon.png",
			"desc": "Скрытые финансовые махинации и долги дзайбацу угрожают обвалить Токийскую биржу и экономику Империи.",
			"effects": "• Коррупция в министерствах: 45.0%\n• Уязвимость Токийской биржи: Критическая\n• Риск падения кабинета министров"
		},
		"ITA_battle_for_med": {
			"name": "Битва за Средиземноморье",
			"icon": "res://assets/gfx/interface/war_support_icon.png",
			"desc": "Итальянская империя стремится удержать господство над Mare Nostrum в противостоянии с Иберией и Турцией.",
			"effects": "• Морской контроль: Оспариваемый\n• Стоимость флота: +10.0%\n• Имперский престиж Савойского дома"
		}
	}

	if spirit_ids.is_empty():
		spirit_ids = ["generic_standing_spirit", "generic_economy_factor"]

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

		var tex = TNOTheme.get_texture(sp_icon)
		if tex == null:
			tex = TNOTheme.get_texture("res://assets/gfx/interface/war_support_icon.png")
		icon_rect.texture = tex

		card.add_child(icon_rect)
		card.tooltip_text = "┌── [%s] ──\n│ ТИП: Стартовый национальный дух // Кризис\n│ СТАТУС: Действует с 1 января 1962 г.\n├─────────────────────────────────────────\n│ ОПИСАНИЕ:\n│ %s\n├─────────────────────────────────────────\n│ СТРАТЕГИЧЕСКИЕ ЭФФЕКТЫ:\n%s" % [sp_name, sp_desc, sp_effects]

		spirits_grid.add_child(card)
