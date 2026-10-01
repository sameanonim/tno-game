class_name EspionageTerminalView
extends PanelContainer

##
## EspionageTerminalView: Контроллер экрана шифровального ЭЛТ-терминала разведки
##
## Стилистика: Военный терминал спецслужб Холодной войны (CRT, моноширинный шрифт,
## зеленый фосфор #33ff66, бирюзовый #00e5ff, янтарный #ffb000, псевдографика).
##

signal operation_launched(op: CovertOperationResource)
signal operation_aborted(op_id: String)
signal agent_assigned(agent_id: String, target_tag: String)
signal agent_recalled(agent_id: String)

# ==============================================================================
# УЗЛЫ ИНТЕРФЕЙСА (ONREADY)
# ==============================================================================
@onready var header_title: Label = $VBox/HeaderHBox/TitleLabel
@onready var btn_close: Button = $VBox/HeaderHBox/CloseButton

# --- Статус-панель (Top Status Bar) ---
@onready var label_black_budget: Label = $VBox/TopStatusBar/HBox/BlackBudgetLabel
@onready var label_domestic_security: Label = $VBox/TopStatusBar/HBox/DomesticSecurityLabel
@onready var label_cap: Label = $VBox/TopStatusBar/HBox/CAPLabel
@onready var label_deficit_warning: Label = $VBox/TopStatusBar/HBox/DeficitWarningLabel

# --- Вкладки терминала ---
@onready var btn_tab_networks: Button = $VBox/TabBarHBox/BtnTabNetworks
@onready var btn_tab_operations: Button = $VBox/TabBarHBox/BtnTabOperations
@onready var btn_tab_roster: Button = $VBox/TabBarHBox/BtnTabRoster
@onready var btn_tab_launch: Button = $VBox/TabBarHBox/BtnTabLaunch

# --- Секции контента ---
@onready var section_networks: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionNetworks
@onready var networks_container: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionNetworks/NetworksList

@onready var section_operations: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionOperations
@onready var operations_container: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionOperations/OperationsList

@onready var section_roster: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionRoster
@onready var roster_container: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionRoster/RosterList
@onready var btn_recruit_agent: Button = $VBox/ContentScroll/SectionsVBox/SectionRoster/RecruitHBox/BtnRecruitAgent

@onready var section_launch: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionLaunch
@onready var opt_mission_type: OptionButton = $VBox/ContentScroll/SectionsVBox/SectionLaunch/FormVBox/OpTypeHBox/OptionButton
@onready var opt_target_country: OptionButton = $VBox/ContentScroll/SectionsVBox/SectionLaunch/FormVBox/TargetCountryHBox/OptionButton
@onready var mission_reqs_label: RichTextLabel = $VBox/ContentScroll/SectionsVBox/SectionLaunch/FormVBox/ReqsLabel
@onready var btn_launch_confirm: Button = $VBox/ContentScroll/SectionsVBox/SectionLaunch/FormVBox/BtnLaunchConfirm

# --- Терминальный журнал (Bottom Log) ---
@onready var log_rich_text: RichTextLabel = $VBox/BottomLogBox/LogRichText

# ==============================================================================
# СОСТОЯНИЕ КОНТРОЛЛЕРА
# ==============================================================================
var country_state: CountryState = null
var turn_manager: TurnManager = null
var current_tab: String = "networks"

const COLOR_PHOSPHOR = Color(0.2, 1.0, 0.4, 1.0)
const COLOR_CYAN = Color(0.0, 0.9, 1.0, 1.0)
const COLOR_AMBER = Color(1.0, 0.75, 0.1, 1.0)
const COLOR_RED = Color(1.0, 0.25, 0.25, 1.0)
const COLOR_DIM = Color(0.5, 0.6, 0.55, 0.8)


func _tr(key: String, params: Variant = {}, fallback: String = "") -> String:
	if is_inside_tree():
		var loc = get_node_or_null("/root/LocalizationManager")
		if loc != null and loc.has_method("tr_key"):
			return loc.tr_key(key, params, fallback)
	var fb = fallback
	if fb.is_empty() and params is String:
		fb = params
	var t = tr(key)
	return t if t != key else fb


func _ready() -> void:
	if is_inside_tree():
		var loc = get_node_or_null("/root/LocalizationManager")
		if loc != null and loc.has_signal("locale_changed"):
			if not loc.locale_changed.is_connected(_on_locale_changed):
				loc.locale_changed.connect(_on_locale_changed)
	_connect_events()
	_apply_styling()
	_populate_launch_dropdowns()
	_switch_tab("networks")
	if country_state != null:
		refresh_ui()


func _on_locale_changed(_locale: String) -> void:
	_apply_styling()
	_populate_launch_dropdowns()
	refresh_ui()


## Настройка ссылок на стейт и менеджер хода
func setup(state: CountryState, manager: TurnManager = null) -> void:
	country_state = state
	turn_manager = manager

	if turn_manager != null:
		if not turn_manager.turn_started.is_connected(_on_turn_started):
			turn_manager.turn_started.connect(_on_turn_started)
		if not turn_manager.espionage_processed.is_connected(_on_espionage_processed):
			turn_manager.espionage_processed.connect(_on_espionage_processed)

	refresh_ui()


func _connect_events() -> void:
	if btn_close != null and not btn_close.pressed.is_connected(func(): visible = false):
		btn_close.pressed.connect(func(): visible = false)

	if btn_tab_networks != null:
		btn_tab_networks.pressed.connect(func(): _switch_tab("networks"))
	if btn_tab_operations != null:
		btn_tab_operations.pressed.connect(func(): _switch_tab("operations"))
	if btn_tab_roster != null:
		btn_tab_roster.pressed.connect(func(): _switch_tab("roster"))
	if btn_tab_launch != null:
		btn_tab_launch.pressed.connect(func(): _switch_tab("launch"))

	if btn_recruit_agent != null:
		btn_recruit_agent.pressed.connect(_on_recruit_button_pressed)

	if opt_mission_type != null:
		opt_mission_type.item_selected.connect(func(_idx): _update_launch_preview())
	if opt_target_country != null:
		opt_target_country.item_selected.connect(func(_idx): _update_launch_preview())
	if btn_launch_confirm != null:
		btn_launch_confirm.pressed.connect(_on_launch_confirmed)


func _apply_styling() -> void:
	if header_title != null:
		header_title.text = _tr("ESPIONAGE_TITLE", "=== ТЕРМИНАЛ ОПЕРАТИВНОЙ РАЗВЕДКИ И ШПИОНАЖА ===")
		header_title.modulate = COLOR_CYAN
	if label_black_budget != null:
		label_black_budget.modulate = COLOR_PHOSPHOR
	if label_domestic_security != null:
		label_domestic_security.modulate = COLOR_CYAN
	if btn_tab_networks != null:
		btn_tab_networks.text = _tr("ESPIONAGE_TAB_NETWORKS", "1. АГЕНТУРНЫЕ СЕТИ")
	if btn_tab_operations != null:
		btn_tab_operations.text = _tr("ESPIONAGE_TAB_OPERATIONS", "2. СПЕЦОПЕРАЦИИ")
	if btn_tab_roster != null:
		btn_tab_roster.text = _tr("ESPIONAGE_TAB_ROSTER", "3. ЛИЧНЫЙ СОСТАВ")
	if btn_tab_launch != null:
		btn_tab_launch.text = _tr("ESPIONAGE_TAB_LAUNCH", "4. ПЛАНИРОВАНИЕ")
	if btn_recruit_agent != null:
		btn_recruit_agent.text = _tr("ESPIONAGE_BTN_RECRUIT", "[ + НАБОР АГЕНТА (-$2.0M) ]")


func _switch_tab(tab_name: String) -> void:
	current_tab = tab_name
	if section_networks != null: section_networks.visible = (tab_name == "networks")
	if section_operations != null: section_operations.visible = (tab_name == "operations")
	if section_roster != null: section_roster.visible = (tab_name == "roster")
	if section_launch != null: section_launch.visible = (tab_name == "launch")

	if btn_tab_networks != null: btn_tab_networks.modulate = COLOR_CYAN if tab_name == "networks" else COLOR_DIM
	if btn_tab_operations != null: btn_tab_operations.modulate = COLOR_CYAN if tab_name == "operations" else COLOR_DIM
	if btn_tab_roster != null: btn_tab_roster.modulate = COLOR_CYAN if tab_name == "roster" else COLOR_DIM
	if btn_tab_launch != null: btn_tab_launch.modulate = COLOR_CYAN if tab_name == "launch" else COLOR_DIM

	refresh_ui()


# ==============================================================================
# ОБНОВЛЕНИЕ ДАННЫХ И ОТРИСОВКА (REFRESH UI)
# ==============================================================================

func refresh_ui() -> void:
	if country_state == null:
		return

	_update_status_bar()

	match current_tab:
		"networks":
			_render_networks_list()
		"operations":
			_render_operations_list()
		"roster":
			_render_roster_list()
		"launch":
			_update_launch_preview()


func _update_status_bar() -> void:
	# 1. Черный бюджет
	var budget_str = "$%0.1fM" % country_state.black_budget
	var alloc_str = "+$%0.1fM/ход" % country_state.black_budget_allocation_per_turn
	if label_black_budget != null:
		label_black_budget.text = _tr("ESPIONAGE_BLACK_BUDGET", "ЧЕРНЫЙ БЮДЖЕТ: %s (%s)") % [budget_str, alloc_str]

	# 2. Контрразведка
	if label_domestic_security != null:
		label_domestic_security.text = _tr("ESPIONAGE_DOMESTIC_SECURITY", "КОНТРРАЗВЕДКА: %0.0f%%") % country_state.domestic_security

	# 3. Очки кабинета
	if label_cap != null:
		label_cap.text = _tr("ESPIONAGE_CAP_POOL", "ПУЛ CAP: [%d/%d]") % [country_state.current_cap, country_state.max_cap]

	# 4. Предупреждение о дефиците
	if label_deficit_warning != null:
		if country_state.black_budget < 0.0:
			label_deficit_warning.visible = true
			label_deficit_warning.text = _tr("ESPIONAGE_DEFICIT_WARNING", "[ ВНИМАНИЕ: ДЕФИЦИТ ФОНДА // ОПЕРАЦИИ ЗАМОРОЖЕНЫ ]")
			label_deficit_warning.modulate = COLOR_RED
		else:
			label_deficit_warning.visible = false


# ==============================================================================
# ВКЛАДКА 1: АГЕНТУРНЫЕ СЕТИ (INFILTRATION NETWORKS)
# ==============================================================================

func _render_networks_list() -> void:
	if networks_container == null:
		return

	# Очищаем старые строки
	for child in networks_container.get_children():
		child.queue_free()

	if country_state.infiltration_networks.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = _tr("ESPIONAGE_NO_NETWORKS", ">> Агентурные сети отсутствуют. Направьте агентов в целевые державы.")
		empty_lbl.modulate = COLOR_DIM
		networks_container.add_child(empty_lbl)
		return

	var sorted_tags = country_state.infiltration_networks.keys()
	sorted_tags.sort()

	for tag in sorted_tags:
		var net_data = country_state.infiltration_networks[tag]
		var lvl = float(net_data.get("level", 0.0)) if net_data is Dictionary else float(net_data)
		var status_str = str(net_data.get("network_status", "DORMANT")) if net_data is Dictionary else "ACTIVE"
		var ag_count = int(net_data.get("agents_count", 0)) if net_data is Dictionary else 0

		var panel = PanelContainer.new()
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)

		# Тэг страны
		var tag_lbl = Label.new()
		tag_lbl.custom_minimum_size = Vector2(80, 0)
		tag_lbl.text = "[ %s ]" % tag
		tag_lbl.modulate = COLOR_CYAN
		hbox.add_child(tag_lbl)

		# Прогресс-бар псевдографикой [██████░░░░] 60%
		var bar_lbl = Label.new()
		bar_lbl.custom_minimum_size = Vector2(240, 0)
		bar_lbl.text = _make_ascii_bar(lvl / 100.0, 12) + " %0.1f%%" % lvl
		if lvl >= 70.0:
			bar_lbl.modulate = COLOR_PHOSPHOR
		elif lvl >= 30.0:
			bar_lbl.modulate = COLOR_CYAN
		else:
			bar_lbl.modulate = COLOR_AMBER
		hbox.add_child(bar_lbl)

		# Статус сети
		var stat_lbl = Label.new()
		stat_lbl.custom_minimum_size = Vector2(160, 0)
		stat_lbl.text = status_str
		stat_lbl.modulate = COLOR_DIM
		hbox.add_child(stat_lbl)

		# Количество агентов
		var agents_lbl = Label.new()
		agents_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		agents_lbl.text = _tr("ESPIONAGE_AGENTS_COUNT", "Агентов: %d") % ag_count
		hbox.add_child(agents_lbl)

		# Кнопка отправки агента
		var btn_infiltrate = Button.new()
		btn_infiltrate.text = _tr("ESPIONAGE_BTN_INFILTRATE", "+ Внедрить")
		btn_infiltrate.pressed.connect(func(): _prompt_assign_agent_to_country(tag))
		hbox.add_child(btn_infiltrate)

		panel.add_child(hbox)
		networks_container.add_child(panel)


# ==============================================================================
# ВКЛАДКА 2: АКТИВНЫЕ СПЕЦОПЕРАЦИИ (ACTIVE OPERATIONS)
# ==============================================================================

func _render_operations_list() -> void:
	if operations_container == null:
		return

	for child in operations_container.get_children():
		child.queue_free()

	if country_state.active_covert_operations.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = _tr("ESPIONAGE_NO_OPERATIONS", ">> Нет активных спецопераций. Перейдите во вкладку [ПЛАНИРОВАНИЕ МИССИЙ].")
		empty_lbl.modulate = COLOR_DIM
		operations_container.add_child(empty_lbl)
		return

	for op in country_state.active_covert_operations:
		if op == null:
			continue

		var panel = PanelContainer.new()
		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 6)

		# Заголовок операции
		var top_hbox = HBoxContainer.new()
		var title_lbl = Label.new()
		title_lbl.text = _tr("ESPIONAGE_OP_TARGET", ">> %s [%s] -> Цель: %s") % [op.title, op.get_type_name_ru(), op.target_country_tag]
		title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_lbl.modulate = COLOR_CYAN
		top_hbox.add_child(title_lbl)

		if op.is_frozen:
			var frozen_badge = Label.new()
			frozen_badge.text = _tr("ESPIONAGE_OP_FROZEN", "[ ЗАМОРОЖЕНА ]")
			frozen_badge.modulate = COLOR_RED
			top_hbox.add_child(frozen_badge)

		vbox.add_child(top_hbox)

		# Прогресс и таймер фаз
		var prog_hbox = HBoxContainer.new()
		var prog_lbl = Label.new()
		prog_lbl.custom_minimum_size = Vector2(220, 0)
		prog_lbl.text = _tr("ESPIONAGE_OP_PROGRESS", "Прогресс: %d / %d ходов") % [op.current_turn_progress, op.total_turns_required]
		prog_hbox.add_child(prog_lbl)

		var bar_lbl = Label.new()
		bar_lbl.custom_minimum_size = Vector2(200, 0)
		bar_lbl.text = op.get_progress_bar_string(10)
		bar_lbl.modulate = COLOR_PHOSPHOR
		prog_hbox.add_child(bar_lbl)

		# Текущий риск
		var risk_val = _calculate_op_display_risk(op)
		var risk_lbl = Label.new()
		risk_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		risk_lbl.text = _tr("ESPIONAGE_OP_RISK", "Риск провала: %0.0f%%") % (risk_val * 100.0)
		risk_lbl.modulate = COLOR_RED if risk_val > 0.40 else (COLOR_AMBER if risk_val > 0.20 else COLOR_PHOSPHOR)
		prog_hbox.add_child(risk_lbl)

		# Кнопка Abort Protocol
		var btn_abort = Button.new()
		btn_abort.text = _tr("ESPIONAGE_BTN_ABORT", "[ ABORT PROTOCOL ]")
		btn_abort.modulate = COLOR_RED
		btn_abort.pressed.connect(func(): _on_abort_operation_clicked(op))
		prog_hbox.add_child(btn_abort)

		vbox.add_child(prog_hbox)
		panel.add_child(vbox)
		operations_container.add_child(panel)


func _calculate_op_display_risk(op: CovertOperationResource) -> float:
	var target_sec = 50.0
	var net_lvl = country_state.get_infiltration_level(op.target_country_tag)
	var skill_sum = 0
	for aid in op.assigned_agent_ids:
		var ag = country_state.get_agent_by_id(aid)
		if ag != null:
			skill_sum += ag.competence

	var risk = clampf(op.base_detection_risk + (target_sec - net_lvl) * 0.01 - (float(skill_sum) * 0.03), 0.05, 0.95)
	if country_state.black_budget < 0.0:
		risk = clampf(risk * 2.0, 0.05, 0.98)
	return risk


func _on_abort_operation_clicked(op: CovertOperationResource) -> void:
	op.is_aborted = true
	append_terminal_log(_tr("ESPIONAGE_LOG_ABORT", ">> ПРИКАЗ ПЕРЕДАН: Сворачивание операции [%s] по протоколу Abort Protocol.") % op.title, COLOR_AMBER)
	operation_aborted.emit(op.op_id)
	refresh_ui()


# ==============================================================================
# ВКЛАДКА 3: ЛИЧНЫЙ СОСТАВ (AGENT ROSTER)
# ==============================================================================

func _render_roster_list() -> void:
	if roster_container == null:
		return

	for child in roster_container.get_children():
		child.queue_free()

	if country_state.active_agents.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = _tr("ESPIONAGE_NO_AGENTS", ">> Штат разведотдела пуст. Наймите агентов через кнопку ниже.")
		empty_lbl.modulate = COLOR_DIM
		roster_container.add_child(empty_lbl)
		return

	for ag in country_state.active_agents:
		if ag == null:
			continue

		var panel = PanelContainer.new()
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)

		# Позывной
		var name_lbl = Label.new()
		name_lbl.custom_minimum_size = Vector2(130, 0)
		name_lbl.text = "«%s»" % ag.codename
		name_lbl.modulate = COLOR_CYAN
		hbox.add_child(name_lbl)

		# Навык
		var stars_lbl = Label.new()
		stars_lbl.custom_minimum_size = Vector2(80, 0)
		stars_lbl.text = ag.get_stars_string()
		stars_lbl.modulate = COLOR_AMBER
		hbox.add_child(stars_lbl)

		# Лояльность
		var loy_lbl = Label.new()
		loy_lbl.custom_minimum_size = Vector2(110, 0)
		loy_lbl.text = _tr("ESPIONAGE_LOYALTY", "Лояльность: %0.0f%%") % ag.loyalty
		loy_lbl.modulate = COLOR_RED if ag.loyalty < 30.0 else (COLOR_AMBER if ag.loyalty < 60.0 else COLOR_PHOSPHOR)
		hbox.add_child(loy_lbl)

		# Статус
		var stat_lbl = Label.new()
		stat_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stat_lbl.text = ag.get_status_string_ru()
		stat_lbl.modulate = COLOR_DIM if ag.status == AgentResource.AgentStatus.IDLE else COLOR_PHOSPHOR
		hbox.add_child(stat_lbl)

		# Апkeep
		var cost_lbl = Label.new()
		cost_lbl.custom_minimum_size = Vector2(90, 0)
		cost_lbl.text = _tr("ESPIONAGE_UPKEEP", "$%0.1fM/ход") % ag.upkeep_cost_black_budget
		cost_lbl.modulate = COLOR_DIM
		hbox.add_child(cost_lbl)

		# Кнопка отзыва / переназначения
		if ag.status == AgentResource.AgentStatus.INFILTRATING:
			var btn_recall = Button.new()
			btn_recall.text = _tr("ESPIONAGE_BTN_RECALL", "Отозвать")
			btn_recall.pressed.connect(func(): _recall_agent(ag))
			hbox.add_child(btn_recall)
		elif ag.status == AgentResource.AgentStatus.IDLE:
			var btn_assign = Button.new()
			btn_assign.text = _tr("ESPIONAGE_BTN_ASSIGN", "Назначить...")
			btn_assign.pressed.connect(func(): _prompt_assign_agent(ag))
			hbox.add_child(btn_assign)

		panel.add_child(hbox)
		roster_container.add_child(panel)


func _on_recruit_button_pressed() -> void:
	if country_state == null:
		return

	if country_state.black_budget < 2.0:
		append_terminal_log(_tr("ESPIONAGE_ERR_BUDGET", ">> ОШИБКА: Недостаточно средств черного бюджета для вербовки ($2.0M требуется)."), COLOR_RED)
		return

	country_state.black_budget -= 2.0
	var codenames = ["Призрак", "Сокол", "Коршун", "Беркут", "Ворон", "Спектр", "Мираж", "Сатурн", "Гриф"]
	var chosen_name = codenames[randi() % codenames.size()]
	var comp = randi_range(2, 4)
	var new_ag = EspionageEngine.recruit_agent(chosen_name, comp, "", 0.6)
	country_state.add_agent(new_ag)

	append_terminal_log(_tr("ESPIONAGE_RECRUIT_SUCCESS", ">> ВЕРБОВКА УСПЕШНА: Агент «%s» (навык: %s) зачислен в штат.") % [chosen_name, new_ag.get_stars_string()], COLOR_PHOSPHOR)
	refresh_ui()


func _recall_agent(ag: AgentResource) -> void:
	ag.status = AgentResource.AgentStatus.IDLE
	var old_country = ag.assigned_country_tag
	ag.assigned_country_tag = ""
	append_terminal_log(_tr("ESPIONAGE_AGENT_RECALLED", ">> Агент «%s» отозван из державы [%s] в резерв.") % [ag.codename, old_country], COLOR_CYAN)
	agent_recalled.emit(ag.id)
	refresh_ui()


func _prompt_assign_agent(ag: AgentResource) -> void:
	var target_tag = "GER"
	if opt_target_country != null and opt_target_country.item_count > 0:
		target_tag = opt_target_country.get_item_text(opt_target_country.selected)
	ag.assigned_country_tag = target_tag
	ag.status = AgentResource.AgentStatus.INFILTRATING
	country_state.set_infiltration_level(target_tag, country_state.get_infiltration_level(target_tag))
	append_terminal_log(_tr("ESPIONAGE_AGENT_ASSIGNED", ">> Агент «%s» направлен на развертывание сети в [%s].") % [ag.codename, target_tag], COLOR_PHOSPHOR)
	agent_assigned.emit(ag.id, target_tag)
	refresh_ui()


func _prompt_assign_agent_to_country(target_tag: String) -> void:
	# Ищем свободного агента в резерве
	var idle_agent: AgentResource = null
	for ag in country_state.active_agents:
		if ag != null and ag.status == AgentResource.AgentStatus.IDLE:
			idle_agent = ag
			break

	if idle_agent != null:
		idle_agent.assigned_country_tag = target_tag
		idle_agent.status = AgentResource.AgentStatus.INFILTRATING
		append_terminal_log(_tr("ESPIONAGE_AGENT_REASSIGNED", ">> Агент «%s» переброшен на внедрение в [%s].") % [idle_agent.codename, target_tag], COLOR_PHOSPHOR)
		agent_assigned.emit(idle_agent.id, target_tag)
		refresh_ui()
	else:
		append_terminal_log(_tr("ESPIONAGE_ERR_NO_AGENTS", ">> ОШИБКА: Нет свободных агентов в резерве. Наймите новых сотрудников."), COLOR_AMBER)


# ==============================================================================
# ВКЛАДКА 4: ПЛАНИРОВАНИЕ И ЗАПУСК МИССИЙ (MISSION LAUNCH CONSOLE)
# ==============================================================================

func _populate_launch_dropdowns() -> void:
	if opt_mission_type != null:
		opt_mission_type.clear()
		opt_mission_type.add_item(_tr("ESPIONAGE_OP_STEAL_TECH", "КРАЖА ЧЕРТЕЖЕЙ (НИОКР)"), CovertOperationResource.OpType.STEAL_TECH)
		opt_mission_type.add_item(_tr("ESPIONAGE_OP_SABOTAGE_INDUSTRY", "ДИВЕРСИЯ НА ЗАВОДАХ (IC)"), CovertOperationResource.OpType.SABOTAGE_INDUSTRY)
		opt_mission_type.add_item(_tr("ESPIONAGE_OP_SABOTAGE_MILITARY", "ПОДРЫВ АРМЕЙСКИХ СКЛАДОВ"), CovertOperationResource.OpType.SABOTAGE_MILITARY)
		opt_mission_type.add_item(_tr("ESPIONAGE_OP_FUND_COUP", "ФИНАНСИРОВАНИЕ ПЕРЕВОРОТА"), CovertOperationResource.OpType.FUND_COUP)
		opt_mission_type.add_item(_tr("ESPIONAGE_OP_ARM_REBELS", "СНАБЖЕНИЕ ПАРТИЗАН"), CovertOperationResource.OpType.ARM_REBELS)
		opt_mission_type.add_item(_tr("ESPIONAGE_OP_DISINFORMATION", "ДЕЗИНФОРМАЦИОННАЯ КАМПАНИЯ"), CovertOperationResource.OpType.DISINFORMATION)
		opt_mission_type.add_item(_tr("ESPIONAGE_OP_ASSASSINATION", "ЛИКВИДАЦИЯ КОМАНДОВАНИЯ"), CovertOperationResource.OpType.ASSASSINATION)

	if opt_target_country != null:
		opt_target_country.clear()
		var targets = ["GER", "USA", "JAP", "ITA", "BUR", "OMS", "WRRF", "WRS"]
		for t in targets:
			opt_target_country.add_item(t)


func _update_launch_preview() -> void:
	if opt_mission_type == null or opt_target_country == null or mission_reqs_label == null:
		return

	var op_type = opt_mission_type.get_selected_id() as CovertOperationResource.OpType
	var target_tag = opt_target_country.get_item_text(opt_target_country.selected)

	var temp_op = EspionageEngine.create_covert_operation(op_type, target_tag)
	var cur_inf = country_state.get_infiltration_level(target_tag) if country_state != null else 0.0

	var bbcode = _tr("ESPIONAGE_PLAN_HEADER", "[b]ПАРАМЕТРЫ ПЛАНИРУЕМОЙ ОПЕРАЦИИ:[/b]\n")
	bbcode += _tr("ESPIONAGE_PLAN_TITLE", "• Название: [color=#00e5ff]%s[/color]\n") % temp_op.title
	bbcode += _tr("ESPIONAGE_PLAN_TARGET", "• Целевая держава: [color=#00e5ff]%s[/color]\n") % target_tag
	bbcode += _tr("ESPIONAGE_PLAN_REQ", "• Порог проникновения: %0.0f%% (Текущий: [color=%s]%0.1f%%[/color])\n") % [
		temp_op.required_infiltration,
		"#33ff66" if cur_inf >= temp_op.required_infiltration else "#ff3344",
		cur_inf
	]
	bbcode += _tr("ESPIONAGE_PLAN_DURATION", "• Длительность подготовки: %d ходов\n") % temp_op.total_turns_required
	bbcode += _tr("ESPIONAGE_PLAN_COST", "• Бюджетные затраты: $%0.1fM / ход\n") % temp_op.cost_per_turn
	bbcode += _tr("ESPIONAGE_PLAN_BASE_RISK", "• Базовый риск раскрытия: %0.0f%%\n") % (temp_op.base_detection_risk * 100.0)

	var can_launch = cur_inf >= temp_op.required_infiltration and country_state.black_budget >= temp_op.cost_per_turn

	if not can_launch:
		bbcode += _tr("ESPIONAGE_PLAN_FAIL_REQS", "\n[color=#ff3344]ТРЕБОВАНИЯ НЕ ВЫПОЛНЕНЫ:[/color] Недостаточный уровень сети или дефицит бюджета.")
		if btn_launch_confirm != null: btn_launch_confirm.disabled = true
	else:
		bbcode += _tr("ESPIONAGE_PLAN_READY", "\n[color=#33ff66]ВСЕ УСЛОВИЯ ВЫПОЛНЕНЫ:[/color] Спецоперация готова к утверждению.")
		if btn_launch_confirm != null: btn_launch_confirm.disabled = false

	mission_reqs_label.text = bbcode


func _on_launch_confirmed() -> void:
	if country_state == null or opt_mission_type == null or opt_target_country == null:
		return

	var op_type = opt_mission_type.get_selected_id() as CovertOperationResource.OpType
	var target_tag = opt_target_country.get_item_text(opt_target_country.selected)

	var op = EspionageEngine.create_covert_operation(op_type, target_tag)

	# Назначаем свободных агентов или агентов в этой стране
	var assigned: Array[String] = []
	for ag in country_state.active_agents:
		if ag != null and (ag.assigned_country_tag == target_tag or ag.status == AgentResource.AgentStatus.IDLE):
			assigned.append(ag.id)
			ag.status = AgentResource.AgentStatus.EXECUTING_OP
			if assigned.size() >= 2:
				break

	op.assigned_agent_ids = assigned
	country_state.add_operation(op)

	append_terminal_log(_tr("ESPIONAGE_OP_LAUNCHED", ">> ПРИКАЗ УТВЕРЖДЕН: Начата спецоперация [%s] в державе [%s]!") % [op.title, target_tag], COLOR_PHOSPHOR)
	operation_launched.emit(op)
	_switch_tab("operations")


# ==============================================================================
# ЖУРНАЛ И СИСТЕМНЫЕ СИГНАЛЫ
# ==============================================================================

func append_terminal_log(text: String, col: Color = COLOR_PHOSPHOR) -> void:
	if log_rich_text == null:
		return
	var hex = col.to_html()
	log_rich_text.append_text("[color=#%s]%s[/color]\n" % [hex, text])


func _on_turn_started(_turn: int, date_str: String) -> void:
	append_terminal_log(_tr("ESPIONAGE_LOG_SYNC", "--- СИНХРОНИЗАЦИЯ РАЗВЕДСЕТИ // %s ---") % date_str, COLOR_CYAN)
	refresh_ui()


func _on_espionage_processed(reports: Array[Dictionary]) -> void:
	for rep in reports:
		if country_state != null and rep.get("country_tag", "") == country_state.country_tag:
			for comp_op in rep.get("completed_operations", []):
				var outcome = str(comp_op.get("outcome", ""))
				var desc = str(comp_op.get("description", ""))
				if outcome == "STEALTH_SUCCESS":
					append_terminal_log(">> %s" % desc, COLOR_PHOSPHOR)
				elif outcome == "MESSY_SUCCESS":
					append_terminal_log(">> %s" % desc, COLOR_AMBER)
				else:
					append_terminal_log(">> %s" % desc, COLOR_RED)

			for inc in rep.get("incidents", []):
				append_terminal_log(">> ИНЦИДЕНТ: %s" % str(inc.get("description", "")), COLOR_RED)

	refresh_ui()


func _make_ascii_bar(ratio: float, width: int = 10) -> String:
	var filled = int(round(clampf(ratio, 0.0, 1.0) * width))
	var s = "["
	for i in range(width):
		if i < filled:
			s += "█"
		else:
			s += "░"
	s += "]"
	return s
