class_name RegionManagementPanel
extends DraggableWindow

##
## RegionManagementPanel: Консоль прямого управления регионом правителя
## Позволяет осуществлять инвестиции, подавление подполья, конверсию ВПК и мобилизацию гарнизона.
##
## Поддерживает свободное перемещение мышью за заголовок (DraggableWindow).
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


func _ensure_nodes() -> void:
	if title_label == null and has_node("VBox/HeaderHBox/TitleLabel"):
		title_label = get_node("VBox/HeaderHBox/TitleLabel") as Label
	if close_button == null and has_node("VBox/HeaderHBox/CloseButton"):
		close_button = get_node("VBox/HeaderHBox/CloseButton") as Button
	if stats_text == null and has_node("VBox/StatsRichText"):
		stats_text = get_node("VBox/StatsRichText") as RichTextLabel
	if btn_invest_infra == null and has_node("VBox/ActionsVBox/BtnInvestInfra"):
		btn_invest_infra = get_node("VBox/ActionsVBox/BtnInvestInfra") as Button
	if btn_suppress == null and has_node("VBox/ActionsVBox/BtnSuppress"):
		btn_suppress = get_node("VBox/ActionsVBox/BtnSuppress") as Button
	if btn_mobilize == null and has_node("VBox/ActionsVBox/BtnMobilize"):
		btn_mobilize = get_node("VBox/ActionsVBox/BtnMobilize") as Button
	if btn_garrison == null and has_node("VBox/ActionsVBox/BtnGarrison"):
		btn_garrison = get_node("VBox/ActionsVBox/BtnGarrison") as Button
	if status_label == null and has_node("VBox/StatusLabel"):
		status_label = get_node("VBox/StatusLabel") as Label


func _ready() -> void:
	super._ready()
	_ensure_nodes()
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
	_ensure_nodes()
	current_region = region
	current_player = player_state
	refresh_display()
	visible = true


func _tr(key: String, default_text: String) -> String:
	if is_inside_tree():
		var loc = get_node_or_null("/root/LocalizationManager")
		if loc != null and loc.has_method("tr_key"):
			return loc.tr_key(key, default_text)
	return tr(key) if tr(key) != key else default_text


func refresh_display() -> void:
	if current_region == null or current_player == null:
		return

	if title_label != null:
		title_label.text = _tr("REG_PANEL_TITLE", "РЕГИОН // {name} [ID: {id}]").replace("{name}", current_region.province_name.to_upper()).replace("{id}", str(current_region.province_id))

	# Формирование псевдографических шкал
	var infra_level = clampi(current_region.civilian_infrastructure, 0, 10)
	var infra_bar = _generate_ascii_bar(float(infra_level) / 10.0, 10)

	var unrest_val = clampf(current_region.unrest, 0.0, 100.0)
	var unrest_bar = _generate_ascii_bar(unrest_val / 100.0, 10)

	var garrison_val = clampf(current_region.garrison_strength, 0.0, 100.0)
	var garrison_bar = _generate_ascii_bar(garrison_val / 100.0, 10)

	var unrest_color = "#33ff66" if unrest_val < 30.0 else ("#ffcc00" if unrest_val < 60.0 else "#ff4444")
	var infra_color := "#00e5ff"

	var text := ""
	text += "[color=#aaaaaa]%s[/color] [color=#00e5ff]%s[/color]\n" % [_tr("REG_SOVEREIGNTY", "СТАТУС СУВЕРЕНИТЕТА:"), _tr("REG_DIRECT_CONTROL", "ПРЯМОЙ КОНТРОЛЬ ПРАВИТЕЛЯ")]
	text += "[color=#aaaaaa]%s[/color] %s\n\n" % [_tr("REG_TERRAIN", "ТИП МЕСТНОСТИ:"), current_region.terrain_type.to_upper()]
	text += "[color=#aaaaaa]%s[/color] [color=#33ff66]%s[/color]\n" % [_tr("REG_IC", "ИНДУСТРИАЛЬНЫЙ ПОТЕНЦИАЛ (IC):"), _tr("REG_FACTORIES_VAL", "{count} ФАБРИК").replace("{count}", str(current_region.industrial_capacity))]
	text += "[color=%s]%s[/color] [%s] %d/10\n" % [infra_color, _tr("REG_INFRA", "ИНФРАСТРУКТУРА:"), infra_bar, infra_level]
	text += "[color=%s]%s[/color] [%s] %d%%\n" % [unrest_color, _tr("REG_UNREST", "СОЦИАЛЬНАЯ НАПРЯЖЕННОСТЬ:"), unrest_bar, int(unrest_val)]
	text += "[color=#ffaa00]%s[/color] [%s] %d%%\n" % [_tr("REG_GARRISON", "БОЕГОТОВНОСТЬ ГАРНИЗОНА:"), garrison_bar, int(garrison_val)]

	if unrest_val >= 50.0:
		text += "\n[color=#ff4444]%s[/color]" % _tr("REG_RISK_WARNING", "⚠ ВНИМАНИЕ: Высокий риск забастовок и подпольного саботажа!")

	if stats_text != null:
		stats_text.text = text

	# Валидация доступности кнопок по ресурсам игрока
	if btn_invest_infra != null:
		var can_invest = current_player.liquid_reserves_billions >= 0.15 and current_region.civilian_infrastructure < 10
		btn_invest_infra.disabled = not can_invest
		btn_invest_infra.text = _tr("REG_BTN_INVEST", "ИНВЕСТИРОВАТЬ В ИНФРАСТРУКТУРУ (-$0.15B, +1)") if current_region.civilian_infrastructure < 10 else _tr("REG_BTN_INFRA_MAX", "ИНФРАСТРУКТУРА НА МАКСИМУМЕ")

	if btn_suppress != null:
		var can_suppress = current_player.current_cap >= 1 and current_region.unrest > 0.0
		btn_suppress.disabled = not can_suppress
		btn_suppress.text = _tr("REG_BTN_SUPPRESS", "ЧРЕЗВЫЧАЙНОЕ ПОЛОЖЕНИЕ (-1 CAP, -20% БУНТ)")

	if btn_mobilize != null:
		var can_mobilize = current_player.liquid_reserves_billions >= 0.10 and current_region.industrial_capacity < 12
		btn_mobilize.disabled = not can_mobilize
		btn_mobilize.text = _tr("REG_BTN_MOBILIZE", "МОБИЛИЗАЦИЯ ВПК (+1 ЗАВОД, -$0.10B)")

	if btn_garrison != null:
		var can_garrison = current_player.manpower_pool >= 500 and current_region.garrison_strength < 100.0
		btn_garrison.disabled = not can_garrison
		btn_garrison.text = _tr("REG_BTN_GARRISON", "УСИЛИТЬ ГАРНИЗОН (-500 ЧЕЛ., +25% ОБОРОНА)")

	if status_label != null:
		status_label.text = _tr("REG_STATUS_UPDATED", "РЕГИСТРЫ ТЕРМИНАЛА ОБНОВЛЕНЫ")


func _on_invest_infra_pressed() -> void:
	if current_region == null or current_player == null:
		return
	if current_player.liquid_reserves_billions >= 0.15 and current_region.civilian_infrastructure < 10:
		current_player.liquid_reserves_billions -= 0.15
		current_region.civilian_infrastructure += 1
		invest_infrastructure_requested.emit(current_region.province_id)
		refresh_display()
		if status_label != null:
			status_label.text = _tr("REG_STATUS_INVEST_OK", "ИНВЕСТИЦИЯ УСПЕШНА: +1 ИНФРАСТРУКТУРА")


func _on_suppress_pressed() -> void:
	if current_region == null or current_player == null:
		return
	if current_player.current_cap >= 1 and current_region.unrest > 0.0:
		current_player.current_cap -= 1
		current_region.unrest = maxf(0.0, current_region.unrest - 20.0)
		suppress_unrest_requested.emit(current_region.province_id)
		refresh_display()
		if status_label != null:
			status_label.text = _tr("REG_STATUS_SUPPRESS_OK", "СИЛЫ БЕЗОПАСНОСТИ РАЗВЕРНУТЫ: -20% НАПРЯЖЕННОСТЬ")


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
			status_label.text = _tr("REG_STATUS_MOBILIZE_OK", "ПРОМЫШЛЕННОСТЬ ПЕРЕВЕДЕНА НА ВОЕННЫЕ РЕЛЬСЫ: +1 IC")


func _on_garrison_pressed() -> void:
	if current_region == null or current_player == null:
		return
	if current_player.manpower_pool >= 500 and current_region.garrison_strength < 100.0:
		current_player.manpower_pool -= 500
		current_region.garrison_strength = minf(100.0, current_region.garrison_strength + 25.0)
		garrison_reinforce_requested.emit(current_region.province_id)
		refresh_display()
		if status_label != null:
			status_label.text = _tr("REG_STATUS_GARRISON_OK", "ГАРНИЗОН ПОПОЛНЕН: +25% БОЕГОТОВНОСТЬ")


func _on_close_pressed() -> void:
	visible = false
	panel_closed.emit()


func _generate_ascii_bar(fraction: float, total_chars: int = 10) -> String:
	var filled = clampi(int(round(clampf(fraction, 0.0, 1.0) * float(total_chars))), 0, total_chars)
	var empty = total_chars - filled
	var bar := ""
	for i in range(filled): bar += "█"
	for i in range(empty): bar += "░"
	return bar
