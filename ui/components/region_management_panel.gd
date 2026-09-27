class_name RegionManagementPanel
extends PanelContainer

##
## RegionManagementPanel: Консоль прямого управления регионом правителя
## Позволяет осуществлять инвестиции, подавление подполья, конверсию ВПК и мобилизацию гарнизона.
##

signal invest_infrastructure_requested(region_id: int)
signal suppress_unrest_requested(region_id: int)
signal convert_military_requested(region_id: int)
signal garrison_reinforce_requested(region_id: int)
signal panel_closed()

@onready var title_label: Label = $VBox/HeaderHBox/TitleLabel
@onready var close_button: Button = $VBox/HeaderHBox/CloseButton
@onready var stats_text: RichTextLabel = $VBox/StatsRichText
@onready var btn_invest_infra: Button = $VBox/ActionsVBox/BtnInvestInfra
@onready var btn_suppress: Button = $VBox/ActionsVBox/BtnSuppress
@onready var btn_mobilize: Button = $VBox/ActionsVBox/BtnMobilize
@onready var btn_garrison: Button = $VBox/ActionsVBox/BtnGarrison
@onready var status_label: Label = $VBox/StatusLabel

var current_region: RegionData
var current_player: CountryState


func _ready() -> void:
	if close_button != null and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)
	if btn_invest_infra != null and not btn_invest_infra.pressed.is_connected(_on_invest_infra_pressed):
		btn_invest_infra.pressed.connect(_on_invest_infra_pressed)
	if btn_suppress != null and not btn_suppress.pressed.is_connected(_on_suppress_pressed):
		btn_suppress.pressed.connect(_on_suppress_pressed)
	if btn_mobilize != null and not btn_mobilize.pressed.is_connected(_on_mobilize_pressed):
		btn_mobilize.pressed.connect(_on_mobilize_pressed)
	if btn_garrison != null and not btn_garrison.pressed.is_connected(_on_garrison_pressed):
		btn_garrison.pressed.connect(_on_garrison_pressed)


func setup_for_region(region: RegionData, player_state: CountryState) -> void:
	current_region = region
	current_player = player_state
	refresh_display()
	visible = true


func refresh_display() -> void:
	if current_region == null or current_player == null:
		return

	if title_label != null:
		title_label.text = "РЕГИОН // %s [ID: %d]" % [current_region.province_name.to_upper(), current_region.province_id]

	# Формирование псевдографических шкал
	var infra_level = clampi(current_region.civilian_infrastructure, 0, 10)
	var infra_bar = _generate_ascii_bar(float(infra_level) / 10.0, 10)

	var unrest_val = clampf(current_region.unrest, 0.0, 100.0)
	var unrest_bar = _generate_ascii_bar(unrest_val / 100.0, 10)

	var garrison_val = clampf(current_region.garrison_strength, 0.0, 100.0)
	var garrison_bar = _generate_ascii_bar(garrison_val / 100.0, 10)

	var unrest_color = "#33ff66" if unrest_val < 30.0 else ("#ffcc00" if unrest_val < 60.0 else "#ff4444")
	var infra_color = "#00e5ff"

	var text = ""
	text += "[color=#aaaaaa]СТАТУС СУВЕРЕНИТЕТА:[/color] [color=#00e5ff]ПРЯМОЙ КОНТРОЛЬ ПРАВИТЕЛЯ[/color]\n"
	text += "[color=#aaaaaa]ТИП МЕСТНОСТИ:[/color] %s\n\n" % current_region.terrain_type.to_upper()
	text += "[color=#aaaaaa]ИНДУСТРИАЛЬНЫЙ ПОТЕНЦИАЛ (IC):[/color] [color=#33ff66]%d ФАБРИК[/color]\n" % current_region.industrial_capacity
	text += "[color=%s]ИНФРАСТРУКТУРА:[/color] [%s] %d/10\n" % [infra_color, infra_bar, infra_level]
	text += "[color=%s]СОЦИАЛЬНАЯ НАПРЯЖЕННОСТЬ:[/color] [%s] %d%%\n" % [unrest_color, unrest_bar, int(unrest_val)]
	text += "[color=#ffaa00]БОЕГОТОВНОСТЬ ГАРНИЗОНА:[/color] [%s] %d%%\n" % [garrison_bar, int(garrison_val)]

	if unrest_val >= 50.0:
		text += "\n[color=#ff4444]⚠ ВНИМАНИЕ: Высокий риск забастовок и подпольного саботажа![/color]"

	if stats_text != null:
		stats_text.text = text

	# Валидация доступности кнопок по ресурсам игрока
	if btn_invest_infra != null:
		var can_invest = current_player.liquid_reserves_billions >= 0.15 and current_region.civilian_infrastructure < 10
		btn_invest_infra.disabled = not can_invest
		btn_invest_infra.text = "ИНВЕСТИРОВАТЬ В ИНФРАСТРУКТУРУ (-$0.15B, +1)" if current_region.civilian_infrastructure < 10 else "ИНФРАСТРУКТУРА НА МАКСИМУМЕ"

	if btn_suppress != null:
		var can_suppress = current_player.current_cap >= 1 and current_region.unrest > 0.0
		btn_suppress.disabled = not can_suppress
		btn_suppress.text = "ЧРЕЗВЫЧАЙНОЕ ПОЛОЖЕНИЕ (-1 CAP, -20% БУНТ)"

	if btn_mobilize != null:
		var can_mobilize = current_player.liquid_reserves_billions >= 0.10 and current_region.industrial_capacity < 12
		btn_mobilize.disabled = not can_mobilize
		btn_mobilize.text = "МОБИЛИЗАЦИЯ ВПК (+1 ЗАВОД, -$0.10B)"

	if btn_garrison != null:
		var can_garrison = current_player.manpower_pool >= 500 and current_region.garrison_strength < 100.0
		btn_garrison.disabled = not can_garrison
		btn_garrison.text = "УСИЛИТЬ ГАРНИЗОН (-500 ЧЕЛ., +25% ОБОРОНА)"

	if status_label != null:
		status_label.text = "РЕГИСТРЫ ТЕРМИНАЛА ОБНОВЛЕНЫ"


func _on_invest_infra_pressed() -> void:
	if current_region == null or current_player == null:
		return
	if current_player.liquid_reserves_billions >= 0.15 and current_region.civilian_infrastructure < 10:
		current_player.liquid_reserves_billions -= 0.15
		current_region.civilian_infrastructure += 1
		invest_infrastructure_requested.emit(current_region.province_id)
		refresh_display()
		if status_label != null:
			status_label.text = "ИНВЕСТИЦИЯ УСПЕШНА: +1 ИНФРАСТРУКТУРА"


func _on_suppress_pressed() -> void:
	if current_region == null or current_player == null:
		return
	if current_player.current_cap >= 1 and current_region.unrest > 0.0:
		current_player.current_cap -= 1
		current_region.unrest = maxf(0.0, current_region.unrest - 20.0)
		suppress_unrest_requested.emit(current_region.province_id)
		refresh_display()
		if status_label != null:
			status_label.text = "СИЛЫ БЕЗОПАСНОСТИ РАЗВЕРНУТЫ: -20% НАПРЯЖЕННОСТЬ"


func _on_mobilize_pressed() -> void:
	if current_region == null or current_player == null:
		return
	if current_player.liquid_reserves_billions >= 0.10:
		current_player.liquid_reserves_billions -= 0.10
		current_region.industrial_capacity += 1
		current_player.military_factories += 1
		convert_military_requested.emit(current_region.province_id)
		refresh_display()
		if status_label != null:
			status_label.text = "ПРОМЫШЛЕННОСТЬ ПЕРЕВЕДЕНА НА ВОЕННЫЕ РЕЛЬСЫ: +1 IC"


func _on_garrison_pressed() -> void:
	if current_region == null or current_player == null:
		return
	if current_player.manpower_pool >= 500 and current_region.garrison_strength < 100.0:
		current_player.manpower_pool -= 500
		current_region.garrison_strength = minf(100.0, current_region.garrison_strength + 25.0)
		garrison_reinforce_requested.emit(current_region.province_id)
		refresh_display()
		if status_label != null:
			status_label.text = "ГАРНИЗОН ПОПОЛНЕН: +25% БОЕГОТОВНОСТЬ"


func _on_close_pressed() -> void:
	visible = false
	panel_closed.emit()


func _generate_ascii_bar(fraction: float, total_chars: int = 10) -> String:
	var filled = clampi(int(round(clampf(fraction, 0.0, 1.0) * float(total_chars))), 0, total_chars)
	var empty = total_chars - filled
	var bar = ""
	for i in range(filled): bar += "█"
	for i in range(empty): bar += "░"
	return bar
