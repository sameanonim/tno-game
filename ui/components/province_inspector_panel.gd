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


func _ready() -> void:
	if close_button != null and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)
	if btn_manage != null and not btn_manage.pressed.is_connected(_on_manage_pressed):
		btn_manage.pressed.connect(_on_manage_pressed)
	if btn_raid != null and not btn_raid.pressed.is_connected(_on_raid_pressed):
		btn_raid.pressed.connect(_on_raid_pressed)


func inspect_province(
	province_id: int,
	features_dict: Dictionary,
	current_player_tag: String = "KOM"
) -> void:
	current_province_id = province_id
	player_tag = current_player_tag

	var p_key = str(province_id)
	if features_dict.has(p_key):
		current_feature_data = features_dict[p_key]
	else:
		current_feature_data = {
			"id": province_id,
			"state_name": "Неизвестная территория",
			"owner": "WST",
			"terrain": "plains",
			"terrain_name_ru": "Равнины",
			"vp": 0,
			"buildings": {}
		}

	_update_display()
	visible = true


func _update_display() -> void:
	var pid = current_province_id
	var f = current_feature_data

	var city_name = f.get("city_name_ru", "")
	if city_name.is_empty():
		city_name = f.get("city_name_en", "")

	var owner = f.get("owner", "WST")
	var state_name = f.get("state_name", "Регион %d" % f.get("state_id", 0))
	var vp = int(f.get("vp", 0))
	var is_cap = bool(f.get("is_capital", false))

	# Шапка панели
	if title_label != null:
		var display_title = city_name.to_upper() if not city_name.is_empty() else state_name.to_upper()
		title_label.text = "ИНСПЕКТОР // %s [PID: %d]" % [display_title, pid]

	# Формирование информационного текста CRT
	var text = ""

	# 1. Политический суверенитет и Победные очки
	var owner_color = "#33ff66" if owner == player_tag else "#ffcc00"
	text += "[b][color=#88ccff]══ ГЕОПОЛИТИЧЕСКИЙ СТАТУС ══[/color][/b]\n"
	text += "[color=#aaaaaa]ДЕРЖАВА-ВЛАДЕЛЕЦ:[/color] [color=%s]%s[/color] | [color=#aaaaaa]РЕГИОН:[/color] %s\n" % [owner_color, owner, state_name]

	if is_cap:
		text += "[color=#ffdd44]★ НАЦИОНАЛЬНАЯ СТОЛИЦА // СТРАТЕГИЧЕСКИЙ ЦЕНТР (%d VP)[/color]\n" % vp
	elif vp > 0:
		text += "[color=#00e5ff]◆ СТРАТЕГИЧЕСКИЙ ПУНКТ // ПОБЕДНЫЕ ОЧКИ: %d VP[/color]\n" % vp
	else:
		text += "[color=#667788]• Локальная тактическая зона[/color]\n"

	text += "\n"

	# 2. Тактический рельеф и свойства местности
	var terrain_ru = f.get("terrain_name_ru", "Умеренный ландшафт")
	var terrain_en = f.get("terrain_name_en", "Terrain")
	var def_bonus = int(f.get("defense_bonus", 0))
	var atk_pen = int(f.get("attack_penalty", 0))
	var mov_cost = float(f.get("movement_cost", 1.0))
	var raid_vuln = float(f.get("raid_vulnerability", 1.0))

	text += "[b][color=#88ccff]══ ТАКТИЧЕСКИЙ ЛАНДШАФТ ══[/color][/b]\n"
	text += "[color=#aaaaaa]МЕСТНОСТЬ:[/color] [color=#ffffff]%s[/color] (%s)\n" % [terrain_ru, terrain_en]

	var def_str = ("[color=#33ff66]+%d%%[/color]" % def_bonus) if def_bonus > 0 else "0%"
	var atk_str = ("[color=#ff5555]%d%%[/color]" % atk_pen) if atk_pen < 0 else "0%"
	text += "[color=#aaaaaa]БОНУС ОБОРОНЫ:[/color] %s | [color=#aaaaaa]ШТРАФ АТАКИ:[/color] %s\n" % [def_str, atk_str]
	text += "[color=#aaaaaa]СТОИМОСТЬ ДВИЖЕНИЯ:[/color] %.1fx | [color=#aaaaaa]УЯЗВИМОСТЬ К РЕЙДУ:[/color] %.1fx\n" % [mov_cost, raid_vuln]

	if f.get("is_coastal", false):
		text += "[color=#00ccff]⚓ ПРИБРЕЖНАЯ ЗОНА (Доступ к морским операциям)[/color]\n"

	text += "\n"

	# 3. Инфраструктура и военные комплексы
	var b = f.get("buildings", {})
	text += "[b][color=#88ccff]══ ВОЕННО-СТРАТЕГИЧЕСКИЕ ОБЪЕКТЫ ══[/color][/b]\n"

	var has_buildings = false
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

	# 4. Экономика и ресурсы региона
	var res = f.get("state_resources", {})
	var ic = float(f.get("state_ic", 0.0))
	var manpower = int(f.get("state_manpower", 0))
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
	if btn_raid != null:
		btn_raid.visible = (not is_player_province and owner != "WST")


func _format_number(num: int) -> String:
	var s = str(num)
	var res = ""
	var cnt = 0
	for i in range(s.length() - 1, -1, -1):
		res = s[i] + res
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			res = " " + res
	return res


func _on_close_pressed() -> void:
	visible = false
	inspector_closed.emit()


func _on_manage_pressed() -> void:
	var sid = int(current_feature_data.get("state_id", 0))
	open_region_management_requested.emit(sid)


func _on_raid_pressed() -> void:
	plan_raid_target_requested.emit(current_province_id)
