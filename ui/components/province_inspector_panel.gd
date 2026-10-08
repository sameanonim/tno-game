class_name ProvinceInspectorPanel
extends PanelContainer

##
## ProvinceInspectorPanel: Интерактивный тактический инспектор провинций
## Детальный военный терминал данных по любой выбранной точке мира:
## - Рельеф и боевые модификаторы (Защита, Штрафы атаки, Рейдовая уязвимость).
## - Победные очки, статус столицы и историческое название города.
## - Военная инфраструктура (Порты, Аэродромы, Укрепления, Склады).
## - Ресурсы, демография и ВПК региона.
##

signal open_region_management_requested(region_id: int)
signal plan_raid_target_requested(province_id: int)
signal inspector_closed()

@onready var title_label: Label = $VBox/HeaderHBox/TitleLabel
@onready var close_button: Button = $VBox/HeaderHBox/CloseButton
@onready var content_text: RichTextLabel = $VBox/Scroll/ContentText
@onready var btn_manage: Button = $VBox/ActionsHBox/BtnManage
@onready var btn_raid: Button = $VBox/ActionsHBox/BtnRaid

var current_province_id: int = 0
var current_feature_data: Dictionary = {}
var player_tag: String = "KOM"


func _ensure_nodes() -> void:
	if title_label == null and has_node("VBox/HeaderHBox/TitleLabel"):
		title_label = get_node("VBox/HeaderHBox/TitleLabel") as Label
	if close_button == null and has_node("VBox/HeaderHBox/CloseButton"):
		close_button = get_node("VBox/HeaderHBox/CloseButton") as Button
	if content_text == null and has_node("VBox/Scroll/ContentText"):
		content_text = get_node("VBox/Scroll/ContentText") as RichTextLabel
	if btn_manage == null and has_node("VBox/ActionsHBox/BtnManage"):
		btn_manage = get_node("VBox/ActionsHBox/BtnManage") as Button
	if btn_raid == null and has_node("VBox/ActionsHBox/BtnRaid"):
		btn_raid = get_node("VBox/ActionsHBox/BtnRaid") as Button


func _ready() -> void:
	_ensure_nodes()
	if close_button != null and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)
	if btn_manage != null and not btn_manage.pressed.is_connected(_on_manage_pressed):
		btn_manage.pressed.connect(_on_manage_pressed)
	if btn_raid != null and not btn_raid.pressed.is_connected(_on_raid_pressed):
		btn_raid.pressed.connect(_on_raid_pressed)


static var country_names_cache: Dictionary = {}


func _get_country_display_name(tag: String) -> String:
	var clean = tag.to_upper().strip_edges()
	if clean.is_empty() or clean in ["WST", "WASTE", "NONE", "NEU", "NEUTRAL"]:
		return tr("Нейтральная территория")

	if country_names_cache.is_empty():
		var path := "res://map_data/starting_countries_state.json"
		if FileAccess.file_exists(path):
			var f = FileAccess.open(path, FileAccess.READ)
			if f != null:
				var text = f.get_as_text()
				f.close()
				var json = JSON.new()
				if json.parse(text) == OK and json.data is Dictionary:
					for t in json.data.keys():
						var c_info = json.data[t]
						var name_ru = str(c_info.get("country_name_ru", c_info.get("country_name", t)))
						country_names_cache[t] = name_ru

	return country_names_cache.get(clean, clean)


var current_region_data: RegionData = null


func inspect_province(
	province_id: int,
	features_dict: Dictionary = {},
	current_player_tag: String = "KOM",
	region_data: RegionData = null
) -> void:
	current_province_id = province_id
	player_tag = current_player_tag
	current_region_data = region_data

	var p_key = str(province_id)
	if features_dict.has(p_key):
		current_feature_data = features_dict[p_key]
	elif features_dict.has(province_id):
		current_feature_data = features_dict[province_id]
	else:
		current_feature_data = {
			"id": province_id,
			"state_name": "Регион #%d" % province_id,
			"owner": "NEU",
			"terrain": "plains",
			"terrain_name_ru": "Равнины",
			"vp": 0,
			"buildings": {}
		}

	# Синхронизация актуальных данных из RegionData если передан
	if current_region_data != null:
		if not current_region_data.owner_tag.is_empty():
			current_feature_data["owner"] = current_region_data.owner_tag
		if not current_region_data.province_name.is_empty():
			current_feature_data["state_name"] = current_region_data.province_name
		current_feature_data["core_tags"] = current_region_data.core_tags
		current_feature_data["ic"] = current_region_data.industrial_capacity
		current_feature_data["population"] = current_region_data.population
		current_feature_data["infrastructure"] = current_region_data.civilian_infrastructure
		current_feature_data["unrest"] = current_region_data.unrest
		current_feature_data["garrison"] = current_region_data.garrison_strength
		if not current_region_data.resource_deposits.is_empty():
			current_feature_data["state_resources"] = current_region_data.resource_deposits

	_update_display()
	_animate_open()


func _animate_open() -> void:
	visible = true
	modulate.a = 0.0
	offset_left = -320.0
	if is_inside_tree():
		var tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "offset_left", -400.0, 0.22)
		tw.tween_property(self, "modulate:a", 1.0, 0.20)
		if has_node("/root/AudioManager"):
			get_node("/root/AudioManager").play_sfx("click_default")
	else:
		offset_left = -400.0
		modulate.a = 1.0


func _animate_close() -> void:
	if is_inside_tree():
		var tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_property(self, "offset_left", -320.0, 0.18)
		tw.tween_property(self, "modulate:a", 0.0, 0.18)
		tw.chain().tween_callback(func():
			visible = false
			offset_left = -400.0
			inspector_closed.emit()
		)
	else:
		visible = false
		offset_left = -400.0
		inspector_closed.emit()


func _update_display() -> void:
	_ensure_nodes()
	var pid = current_province_id
	var f = current_feature_data
	var reg = current_region_data

	var city_name = f.get("city_name_ru", "")
	if city_name.is_empty():
		city_name = f.get("city_name_en", "")

	var owner = str(reg.owner_tag if (reg != null and not reg.owner_tag.is_empty()) else f.get("owner", "NEU"))
	var state_name = reg.province_name if (reg != null and not reg.province_name.is_empty()) else f.get("state_name", "Регион %d" % f.get("state_id", pid))
	var vp = int(f.get("vp", 0))
	var is_cap = bool(f.get("is_capital", false))

	# Шапка панели
	if title_label != null:
		var display_title = city_name.to_upper() if not city_name.is_empty() else state_name.to_upper()
		var inspector_fmt = tr("ИНСПЕКТОР // %s [PID: %d]")
		title_label.text = inspector_fmt % [display_title, pid]

	# Формирование информационного текста CRT
	var text := ""

	# 1. Политический суверенитет и Победные очки
	var owner_color = "#33ff66" if owner == player_tag else "#ffcc00"
	var owner_display_name = _get_country_display_name(owner)
	text += "[b][color=#88ccff]══ ГЕОПОЛИТИЧЕСКИЙ СТАТУС ══[/color][/b]\n"
	if owner != "NEU" and owner != "WST":
		text += "[color=#aaaaaa]ДЕРЖАВА-ВЛАДЕЛЕЦ:[/color] [color=%s]%s [%s][/color] | [color=#aaaaaa]РЕГИОН:[/color] %s\n" % [owner_color, owner_display_name, owner, state_name]
	else:
		text += "[color=#aaaaaa]ДЕРЖАВА-ВЛАДЕЛЕЦ:[/color] [color=#888888]%s[/color] | [color=#aaaaaa]РЕГИОН:[/color] %s\n" % [owner_display_name, state_name]

	# Национальные корки (Cores)
	var cores: Array = reg.core_tags if (reg != null and not reg.core_tags.is_empty()) else f.get("core_tags", [owner])
	var core_strs: Array[String] = []
	for c_tag in cores:
		var c_str = str(c_tag).to_upper()
		if c_str == player_tag:
			core_strs.append("[color=#33ff66]%s★[/color]" % c_str)
		else:
			core_strs.append("[color=#66bbff]%s[/color]" % c_str)
	text += "[color=#aaaaaa]НАЦИОНАЛЬНЫЕ КОРКИ (CORES):[/color] %s\n" % (", ".join(core_strs) if not core_strs.is_empty() else "[color=#667788]ОТСУТСТВУЮТ[/color]")

	if is_cap:
		text += "[color=#ffdd44]★ НАЦИОНАЛЬНАЯ СТОЛИЦА // СТРАТЕГИЧЕСКИЙ ЦЕНТР (%d VP)[/color]\n" % vp
	elif vp > 0:
		text += "[color=#00e5ff]◆ СТРАТЕГИЧЕСКИЙ ПУНКТ // ПОБЕДНЫЕ ОЧКИ: %d VP[/color]\n" % vp
	else:
		text += "[color=#667788]• Локальная тактическая зона[/color]\n"

	text += "\n"

	# 2. Безопасность, Инфраструктура и Гарнизон
	var infra_val = reg.civilian_infrastructure if reg != null else int(f.get("infrastructure", f.get("civilian_infrastructure", 2)))
	infra_val = clampi(infra_val, 0, 10)
	var unrest_val = reg.unrest if reg != null else float(f.get("unrest", 0.0))
	unrest_val = clampf(unrest_val, 0.0, 100.0)
	var garrison_val = reg.garrison_strength if reg != null else float(f.get("garrison", f.get("garrison_strength", 50.0)))
	garrison_val = clampf(garrison_val, 0.0, 100.0)

	var unrest_col = "#33ff66" if unrest_val < 30.0 else ("#ffcc00" if unrest_val < 60.0 else "#ff4444")
	var infra_bar = _generate_ascii_bar(float(infra_val) / 10.0, 8)
	var unrest_bar = _generate_ascii_bar(unrest_val / 100.0, 8)
	var garrison_bar = _generate_ascii_bar(garrison_val / 100.0, 8)

	text += "[b][color=#88ccff]══ УПРАВЛЕНИЕ И БЕЗОПАСНОСТЬ ══[/color][/b]\n"
	text += "[color=#aaaaaa]ИНФРАСТРУКТУРА:[/color] [color=#00e5ff][%s] %d/10[/color]\n" % [infra_bar, infra_val]
	text += "[color=#aaaaaa]НАПРЯЖЕННОСТЬ (UNREST):[/color] [color=%s][%s] %d%%[/color]\n" % [unrest_col, unrest_bar, int(unrest_val)]
	text += "[color=#aaaaaa]ГОТОВНОСТЬ ГАРНИЗОНА:[/color] [color=#ffaa00][%s] %d%%[/color]\n" % [garrison_bar, int(garrison_val)]

	text += "\n"

	# 3. Тактический рельеф и свойства местности
	var terrain_ru = f.get("terrain_name_ru", "")
	if terrain_ru.is_empty():
		var t_type = reg.terrain_type if reg != null else f.get("terrain", "plains")
		match t_type.to_lower():
			"forest": terrain_ru = "Лесистая местность"
			"marsh": terrain_ru = "Болота и топи"
			"mountains": terrain_ru = "Горный хребет"
			"urban": terrain_ru = "Городская агломерация"
			"tundra": terrain_ru = "Тундра"
			_: terrain_ru = "Равнины"
	var def_bonus = int(f.get("defense_bonus", 0))
	var atk_pen = int(f.get("attack_penalty", 0))
	var mov_cost = float(f.get("movement_cost", 1.0))
	var raid_vuln = float(f.get("raid_vulnerability", 1.0))

	text += "[b][color=#88ccff]══ ТАКТИЧЕСКИЙ ЛАНДШАФТ ══[/color][/b]\n"
	text += "[color=#aaaaaa]МЕСТНОСТЬ:[/color] [color=#ffffff]%s[/color]\n" % [terrain_ru]

	var def_str = ("[color=#33ff66]+%d%%[/color]" % def_bonus) if def_bonus > 0 else "0%"
	var atk_str = ("[color=#ff5555]%d%%[/color]" % atk_pen) if atk_pen < 0 else "0%"
	text += "[color=#aaaaaa]БОНУС ОБОРОНЫ:[/color] %s | [color=#aaaaaa]ШТРАФ АТАКИ:[/color] %s\n" % [def_str, atk_str]
	text += "[color=#aaaaaa]СТОИМОСТЬ ДВИЖЕНИЯ:[/color] %.1fx | [color=#aaaaaa]УЯЗВИМОСТЬ К РЕЙДУ:[/color] %.1fx\n" % [mov_cost, raid_vuln]

	if f.get("is_coastal", false):
		text += "[color=#00ccff]⚓ ПРИБРЕЖНАЯ ЗОНА (Доступ к морским операциям)[/color]\n"

	text += "\n"

	# 4. Инфраструктура и военные комплексы
	var b = f.get("buildings", {})
	text += "[b][color=#88ccff]══ ВОЕННО-СТРАТЕГИЧЕСКИЕ ОБЪЕКТЫ ══[/color][/b]\n"

	var has_buildings := false
	if b.get("naval_base", 0) > 0:
		has_buildings = true
		text += "[color=#00e5ff]⚓ Военно-морская база:[/color] Уровень %d\n" % b["naval_base"]
	if b.get("air_base", 0) > 0:
		has_buildings = true
		text += "[color=#66bbff]✈ Авиабаза / Аэродром:[/color] Уровень %d\n" % b["air_base"]
	if b.get("bunker", 0) > 0 or b.get("coastal_bunker", 0) > 0:
		has_buildings = true
		var bunker_lvl = b.get("bunker", 0) + b.get("coastal_bunker", 0)
		text += "[color=#ffaa33]🛡 Укрепления и бункеры:[/color] Уровень %d\n" % bunker_lvl
	if b.get("supply_node", 0) > 0:
		has_buildings = true
		text += "[color=#33ff88]📦 Опорный узел логистики / Склад снабжения[/color]\n"
	if b.get("nuclear_reactor", 0) > 0:
		has_buildings = true
		text += "[color=#ff3333]☢ Ядерный исследовательский комплекс / Реактор[/color]\n"
	if b.get("radar_station", 0) > 0:
		has_buildings = true
		text += "[color=#33ffff]📡 Радиолокационная станция раннего обнаружения[/color]\n"

	if not has_buildings:
		text += "[color=#667788]Специализированных военных объектов не развернуто.[/color]\n"

	text += "\n"

	# 5. Экономика и ресурсы региона
	var res = reg.resource_deposits if (reg != null and not reg.resource_deposits.is_empty()) else f.get("state_resources", {})
	var ic = float(reg.industrial_capacity if reg != null else f.get("ic", f.get("state_ic", 1.0)))
	var manpower = int(reg.population if reg != null else f.get("population", f.get("state_manpower", 45000)))
	var category = f.get("state_category", "rural")

	text += "[b][color=#88ccff]══ ЭКОНОМИКА И СЫРЬЕ РЕГИОНА ══[/color][/b]\n"
	text += "[color=#aaaaaa]КАТЕГОРИЯ:[/color] %s | [color=#aaaaaa]НАСЕЛЕНИЕ:[/color] %s чел.\n" % [category.to_upper(), _format_number(manpower)]
	text += "[color=#aaaaaa]ПРОМЫШЛЕННЫЙ ИНДЕКС (IC):[/color] [color=#33ff66]%.1f[/color]\n" % ic

	if not res.is_empty():
		text += "[color=#aaaaaa]ДОБЫЧА РЕСУРСОВ:[/color] "
		var res_parts: Array[String] = []
		for r_name in res.keys():
			res_parts.append("%s: %s" % [r_name.capitalize(), str(res[r_name])])
		text += "[color=#ffcc33]" + ", ".join(res_parts) + "[/color]\n"
	else:
		text += "[color=#667788]Значимых месторождений сырья не обнаружено.[/color]\n"

	if content_text != null:
		content_text.text = text

	# Конфигурация кнопок действий
	var is_player_province = (owner == player_tag)
	if btn_manage != null:
		btn_manage.visible = is_player_province
		btn_manage.text = tr("[ ПРЯМОЕ УПРАВЛЕНИЕ РЕГИОНОМ ]")
	if btn_raid != null:
		btn_raid.visible = (not is_player_province and owner not in ["WST", "WASTE", "NONE", "NEU", ""])
		btn_raid.text = tr("[ ОРГАНИЗОВАТЬ НАБЕГ / РЕЙД ]")


func _generate_ascii_bar(fraction: float, total_chars: int = 8) -> String:
	var filled = clampi(int(round(clampf(fraction, 0.0, 1.0) * float(total_chars))), 0, total_chars)
	var empty = total_chars - filled
	var bar := ""
	for i in range(filled): bar += "█"
	for i in range(empty): bar += "░"
	return bar


func _format_number(num: int) -> String:
	var s = str(num)
	var res := ""
	var cnt := 0
	for i in range(s.length() - 1, -1, -1):
		res = s[i] + res
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			res = " " + res
	return res


func _on_close_pressed() -> void:
	_animate_close()


func _on_manage_pressed() -> void:
	var sid = int(current_feature_data.get("state_id", current_province_id))
	open_region_management_requested.emit(sid)


func _on_raid_pressed() -> void:
	plan_raid_target_requested.emit(current_province_id)
