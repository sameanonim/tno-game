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

const MINISTERS_DATA_PATH: String = "res://data/dossier/ministers.json"
const SPIRITS_DATA_PATH: String = "res://data/dossier/national_spirits.json"
const PARTIES_DATA_PATH: String = "res://data/dossier/parties_metadata.json"

static var _cached_ministers_db: Dictionary = {}
static var _cached_spirits_registry: Dictionary = {}
static var _cached_parties_meta: Dictionary = {}


"""Формирует распределение политических партий и легенду идеологий.
"""
static func build_parties_breakdown(
	_screen: Control,
	tag: String,
	parties_list: Array[Dictionary],
	legend_container: Control
) -> void:
	parties_list.clear()
	if legend_container != null:
		for c: Node in legend_container.get_children():
			c.queue_free()

	var clean_tag: String = tag.to_upper().strip_edges()
	var pop_dict: Dictionary = {}

	# 1. Чтение популярностей из country.json
	var c_path: String = "res://data/countries/%s/country.json" % clean_tag
	var c_data: Dictionary = JSONFileHelper.load_json_dict(c_path)
	if c_data.has("popularities") and c_data["popularities"] is Dictionary:
		pop_dict = c_data["popularities"]

	# 2. Если пусто, попытка из CountryDataImporter
	if pop_dict.is_empty():
		var state: CountryState = CountryDataImporter.load_country(clean_tag)
		if state != null and not state.initial_parties.is_empty():
			for p: PartyData in state.initial_parties:
				pop_dict[p.party_name] = p.popularity

	_ensure_parties_metadata()
	var ideologies: Dictionary = _cached_parties_meta.get("ideologies", {})
	var specific_party_names: Dictionary = _cached_parties_meta.get("party_names", {})
	var specific_party_descs: Dictionary = _cached_parties_meta.get("party_descs", {})

	var party_items: Array[Dictionary] = []
	for k: String in pop_dict:
		var val: float = float(pop_dict[k])
		if val <= 0.001:
			continue

		var default_col: Color = ColorUtils.tag_to_color(k)
		var base_info: Dictionary = ideologies.get(k, {
			"name": k.capitalize(),
			"color": default_col,
			"desc": "Политическая фракция державы."
		})

		var p_color: Color = default_col
		if base_info.has("color"):
			var raw_c: Variant = base_info["color"]
			if raw_c is Array and raw_c.size() >= 3:
				p_color = Color(float(raw_c[0]), float(raw_c[1]), float(raw_c[2]))
			elif raw_c is Color:
				p_color = raw_c
			elif raw_c is String:
				p_color = ColorUtils.hex_to_color(raw_c)

		var p_name: String = str(base_info.get("name", k.capitalize()))
		if specific_party_names.has(clean_tag) and specific_party_names[clean_tag].has(k):
			p_name = specific_party_names[clean_tag][k]

		var p_desc: String = str(base_info.get("desc", "Политическая фракция державы."))
		if specific_party_descs.has(clean_tag) and specific_party_descs[clean_tag].has(k):
			p_desc = specific_party_descs[clean_tag][k]

		party_items.append({
			"id": k,
			"name": p_name,
			"popularity": val,
			"color": p_color,
			"desc": p_desc
		})

	party_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["popularity"] > b["popularity"])

	if party_items.is_empty():
		party_items = [
			{"id": "ruling", "name": "Правящая партия", "popularity": 62.0, "color": Color(0.2, 0.85, 0.75), "desc": "Основная политическая опора действующего режима."},
			{"id": "opposition", "name": "Лояльная оппозиция", "popularity": 24.0, "color": Color(0.35, 0.60, 0.75), "desc": "Легальные фракции, участвующие в распределении мандатов."},
			{"id": "radicals", "name": "Радикальные диссиденты", "popularity": 14.0, "color": Color(0.75, 0.35, 0.35), "desc": "Внесистемные движения и подпольные ячейки."}
		]

	for item: Dictionary in party_items:
		parties_list.append(item)

		if legend_container != null:
			var chip: PanelContainer = PanelContainer.new()
			var sb: StyleBoxFlat = StyleBoxFlat.new()
			sb.bg_color = Color(0.04, 0.08, 0.10, 0.90)
			var item_col: Color = item["color"]
			sb.border_color = Color(item_col.r * 0.7, item_col.g * 0.7, item_col.b * 0.7, 0.8)
			sb.border_width_left = 1
			sb.border_width_top = 1
			sb.border_width_right = 1
			sb.border_width_bottom = 1
			sb.corner_radius_top_left = 2
			sb.corner_radius_top_right = 2
			sb.corner_radius_bottom_left = 2
			sb.corner_radius_bottom_right = 2
			chip.add_theme_stylebox_override("panel", sb)

			var hbox: HBoxContainer = HBoxContainer.new()
			hbox.add_theme_constant_override("separation", 5)

			var dot: ColorRect = ColorRect.new()
			dot.custom_minimum_size = Vector2(8, 8)
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			dot.color = item_col
			hbox.add_child(dot)

			var lbl: Label = Label.new()
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

	var center: Vector2 = chart_control.size / 2.0
	var radius: float = minf(center.x, center.y) - 2.0
	var start_angle: float = -PI / 2.0

	for p: Dictionary in parties_list:
		var share: float = float(p.get("popularity", 0.0)) / 100.0
		if share <= 0.001:
			continue

		var end_angle: float = start_angle + (share * TAU)
		var points: PackedVector2Array = PackedVector2Array([center])
		var segments: int = maxi(8, int(share * 36))
		for i: int in range(segments + 1):
			var a: float = start_angle + (float(i) / float(segments)) * (end_angle - start_angle)
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

	for c: Node in ministers_grid.get_children():
		c.queue_free()

	var role_meta: Dictionary = {
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

	var canonical: Dictionary = get_canonical_ministers(tag)
	var roles: Array[String] = ["hog", "for", "eco", "sec"]

	for r: String in roles:
		var r_data: Dictionary = role_meta[r]
		var found_name: String = ""
		var minister_portrait_tex: Texture2D = null
		var effects_text: String = r_data["effects"]
		var dep_text: String = r_data["dep"]
		var full_title: String = r_data["full"]

		if canonical.has(r):
			var cm: Dictionary = canonical[r]
			found_name = cm.get("name", "")
			if cm.has("full"): full_title = cm["full"]
			if cm.has("dep"): dep_text = cm["dep"]
			if cm.has("effects"): effects_text = cm["effects"]
			if cm.has("portrait") and not str(cm["portrait"]).is_empty():
				minister_portrait_tex = TNOTheme.get_texture(str(cm["portrait"]))

		if found_name.is_empty():
			found_name = "Штабной специалист"

		if minister_portrait_tex == null:
			minister_portrait_tex = TNOTheme.get_texture(r_data["icon"])

		var card: PanelContainer = PanelContainer.new()
		card.custom_minimum_size = Vector2(0, 44)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var sb: StyleBoxFlat = StyleBoxFlat.new()
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

		var hbox: HBoxContainer = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 6)
		card.add_child(hbox)

		var icon_rect: TextureRect = TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(26, 34)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture = minister_portrait_tex
		hbox.add_child(icon_rect)

		var vbox: VBoxContainer = VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var role_lbl: Label = Label.new()
		role_lbl.text = "%s %s" % [r_data["abbr"], full_title]
		role_lbl.add_theme_font_size_override("font_size", 9)
		role_lbl.add_theme_color_override("font_color", Color(0.3, 0.85, 0.75))
		vbox.add_child(role_lbl)

		var name_lbl: Label = Label.new()
		name_lbl.text = found_name
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", Color(0.95, 1.0, 0.98))
		vbox.add_child(name_lbl)

		hbox.add_child(vbox)

		card.tooltip_text = "┌── [КАБИНЕТ МИНИСТРОВ // CABINET OF MINISTERS] ──\n│ ДОЛЖНОСТЬ: %s\n│ МИНИСТР: %s\n│ ВЕДОМСТВО: %s\n├─────────────────────────────────────────\n│ СТРАТЕГИЧЕСКИЕ ЭФФЕКТЫ ВЕДОМСТВА:\n%s" % [full_title, found_name, dep_text, effects_text]
		ministers_grid.add_child(card)


"""Заполняет сетку национальных духов и кризисов державы.
"""
static func populate_national_spirits_grid(spirits_grid: Control, tag: String, _dossier: Dictionary) -> void:
	if spirits_grid == null:
		return

	for c: Node in spirits_grid.get_children():
		c.queue_free()

	var clean_tag: String = tag.to_upper().strip_edges()
	var c_path: String = "res://data/countries/%s/country.json" % clean_tag
	var c_data: Dictionary = JSONFileHelper.load_json_dict(c_path)
	var raw_ideas: Array = c_data.get("ideas", [])

	var spirit_ids: Array[String] = []
	for id_item: Variant in raw_ideas:
		var sid: String = str(id_item)
		if sid.ends_with("_hog") or sid.ends_with("_for") or sid.ends_with("_eco") or sid.ends_with("_sec"):
			continue
		if sid.ends_with("_high_command") or sid.ends_with("_army_chief") or sid.ends_with("_navy_chief") or sid.ends_with("_air_chief") or sid.ends_with("_theorist"):
			continue
		if sid.begins_with("tno_"):
			continue
		spirit_ids.append(sid)

	_ensure_spirits_registry()

	if spirit_ids.is_empty():
		match clean_tag:
			"GER":
				spirit_ids = ["Pakt_Leader", "to_banish_want", "the_two_principles", "endsieg", "gone_over"]
			"USA":
				spirit_ids = ["OFN_Leader_of_The_Free_World", "USA_last_bastion_of_liberty", "USA_the_american_depression_4", "USA_jim_crow", "USA_OFN_Buffs_4"]
			"JAP":
				spirit_ids = ["Sphere_Leader", "JAP_showa_emperor", "JAP_zaibatsu_question", "JAP_legacy_guarded_pearl_exercises"]
			"ITA":
				spirit_ids = ["TRI_Founder_IT", "ITA_declining_trade", "ITA_fading_fascism", "ITA_navy_strengthened", "ITA_king_umberto"]
			"OMS":
				spirit_ids = ["SIB_terror_bombing", "RUS_warlord_manpower", "OMS_fueled_by_revenge", "OMS_nothing_left_to_lose"]
			"WRS":
				spirit_ids = ["RUS_terror_bombing", "RUS_warlord_manpower", "WRS_veterans_of_the_long_war"]
			"KOM":
				spirit_ids = ["RUS_terror_bombing", "RUS_warlord_manpower", "KOM_syvtyvkartsi", "KOM_clash_of_shadows_c_1"]
			"SVR":
				spirit_ids = ["SIB_terror_bombing", "RUS_warlord_manpower", "SVR_notso_redarmy"]
			_:
				spirit_ids = ["RUS_terror_bombing", "RUS_warlord_manpower"]

	for s_id: String in spirit_ids:
		var sp_name: String = ""
		var sp_icon: String = ""
		var sp_desc: String = ""
		var sp_effects: String = ""

		if _cached_spirits_registry.has(s_id):
			var data: Dictionary = _cached_spirits_registry[s_id]
			sp_name = data.get("name", "")
			sp_icon = data.get("icon", "")
			sp_desc = data.get("desc", "")
			sp_effects = data.get("effects", "")
		else:
			sp_name = s_id.replace("_", " ").capitalize()
			sp_icon = "res://assets/gfx/interface/war_support_icon.png"
			sp_desc = "Национальный дух и системный фактор, формирующий положение державы."
			sp_effects = "• Влияние на боеспособность и экономику нации."

		var card: PanelContainer = PanelContainer.new()
		card.custom_minimum_size = Vector2(46, 46)

		var sb: StyleBoxFlat = StyleBoxFlat.new()
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

		var icon_rect: TextureRect = TextureRect.new()
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.custom_minimum_size = Vector2(36, 36)

		var tex: Texture2D = null
		var main_loop: MainLoop = Engine.get_main_loop()
		if main_loop is SceneTree and main_loop.root != null and main_loop.root.has_node("AssetRegistry"):
			var ar: Node = main_loop.root.get_node("AssetRegistry")
			if ar != null and ar.has_method("get_idea_icon"):
				tex = ar.call("get_idea_icon", s_id)
				if tex == null and not sp_icon.is_empty() and ar.has_method("get_texture"):
					tex = ar.call("get_texture", sp_icon)

		if tex == null and not sp_icon.is_empty():
			tex = TNOTheme.get_texture(sp_icon)
		if tex == null:
			tex = TNOTheme.get_texture("res://assets/gfx/interface/war_support_icon.png")
		icon_rect.texture = tex

		card.add_child(icon_rect)
		card.tooltip_text = "┌── [%s] ──\n│ ТИП: Стартовый национальный дух // Кризис\n│ СТАТУС: Действует с 1 января 1962 г.\n├─────────────────────────────────────────\n│ ОПИСАНИЕ:\n│ %s\n├─────────────────────────────────────────\n│ СТРАТЕГИЧЕСКИЕ ЭФФЕКТЫ:\n%s" % [sp_name, sp_desc, sp_effects]

		spirits_grid.add_child(card)


"""Возвращает аутентичный состав кабинета министров для державы.
"""
static func get_canonical_ministers(tag: String) -> Dictionary:
	var clean_tag: String = tag.to_upper().strip_edges()
	_ensure_ministers_db()

	if _cached_ministers_db.has(clean_tag):
		return _cached_ministers_db[clean_tag]

	return _get_fallback_ministers()


static func _get_fallback_ministers() -> Dictionary:
	return {
		"hog": {"name": "Председатель Правительства", "full": "Глава исполнительной власти", "dep": "Канцелярия правительства", "portrait": "", "effects": "• Политический капитал: +0.25/ход\n• Стабильность: +5.0%"},
		"for": {"name": "Министр Иностранных Дел", "full": "Глава дипломатического ведомства", "dep": "Министерство иностранных дел", "portrait": "", "effects": "• Дипломатический вес: +15.0%"},
		"eco": {"name": "Министр Финансов и Экономики", "full": "Куратор государственного бюджета", "dep": "Министерство финансов", "portrait": "", "effects": "• Рост ВВП: +0.2%\n• Доходы фабрик: +10.0%"},
		"sec": {"name": "Министр Обороны и Безопасности", "full": "Командующий силами правопорядка", "dep": "Министерство обороны", "portrait": "", "effects": "• Боеготовность войск: +10.0%\n• Общественный порядок: +15.0%"}
	}


static func _ensure_ministers_db() -> void:
	if _cached_ministers_db.is_empty():
		_cached_ministers_db = JSONFileHelper.load_json_dict(MINISTERS_DATA_PATH)


static func _ensure_spirits_registry() -> void:
	if _cached_spirits_registry.is_empty():
		_cached_spirits_registry = JSONFileHelper.load_json_dict(SPIRITS_DATA_PATH)


static func _ensure_parties_metadata() -> void:
	if _cached_parties_meta.is_empty():
		_cached_parties_meta = JSONFileHelper.load_json_dict(PARTIES_DATA_PATH)
