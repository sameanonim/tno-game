class_name DirectiveTreeView
extends Control

##
## DirectiveTreeView: Интерактивный терминал национальных директив в ретро-стиле CRT
##
## Реализует направленный граф директив (DAG) с процедурной отрисовкой ортогональных
## соединительных шин, CRT-люминофором, интерактивными узлами с псевдографикой,
## панелью оперативного досье, а также свободным панорамированием (Pan) и масштабированием (Zoom).
##

signal directive_hovered(directive: DirectiveResource)
signal directive_selected(directive: DirectiveResource)
signal directive_initiated(directive: DirectiveResource)

const DirectiveTreeCanvasDrawerScript = preload("res://ui/components/directive_tree_canvas_drawer.gd")
const DirectiveNodeFactoryScript = preload("res://ui/components/directive_node_factory.gd")
const DirectiveInspectorFormatterScript = preload("res://ui/components/directive_inspector_formatter.gd")

# --- Конфигурация сетки и геометрии узлов ---
@export var node_size: Vector2 = Vector2(240, 96)
@export var grid_step: Vector2 = Vector2(280, 140)
@export var origin_offset: Vector2 = Vector2(80, 60)

# --- Палитра CRT люминофора (Military Terminal Green/Amber/Cyan) ---
const COLOR_BG_PANEL = Color(0.02, 0.04, 0.04, 0.96)
const COLOR_CRT_BORDER = Color(0.12, 0.40, 0.32, 0.85)
const COLOR_PHOSPHOR_CYAN = Color(0.0, 0.95, 1.0, 0.95)
const COLOR_PHOSPHOR_GREEN = Color(0.20, 1.0, 0.45, 0.95)
const COLOR_PHOSPHOR_AMBER = Color(1.0, 0.80, 0.20, 0.95)
const COLOR_PHOSPHOR_DIM = Color(0.18, 0.30, 0.26, 0.70)
const COLOR_PHOSPHOR_LOCKED = Color(0.12, 0.18, 0.16, 0.60)
const COLOR_EXCLUSION_RED = Color(0.95, 0.25, 0.25, 0.90)

# --- Состояние и ссылки ---
var player_state: CountryState
var turn_manager: TurnManager
var directive_manager: DirectiveManager
var focus_stage_controller: FocusStageController

var all_directives: Dictionary = {} # Key: String (directive_id), Value: DirectiveResource
var node_controls: Dictionary = {}  # Key: String (directive_id), Value: Control
var selected_directive_id: String = ""

# --- Мульти-древа (Multi-Tree & Stages) ---
var available_trees: Array[Dictionary] = []
var current_tree_path: String = ""
var opt_tree_select: OptionButton = null
var lbl_active_tree_badge: Label = null
var lbl_active_tree_title: Label = null
var lbl_active_tree_count: Label = null
var current_country_tag: String = ""
var stage_manifest_data: Dictionary = {}
var hidden_branch_nodes: Array[String] = []

# --- CRT Reboot Overlay FX ---
var reboot_overlay: Control
var lbl_reboot_log: RichTextLabel
var is_rebooting: bool = false

# --- Управление камерой (Pan & Zoom) ---
var current_zoom: float = 1.0
const MIN_ZOOM: float = 0.4
const MAX_ZOOM: float = 2.0
const ZOOM_STEP: float = 0.1

var is_panning: bool = false
var pan_drag_start: Vector2 = Vector2.ZERO
var pan_canvas_start: Vector2 = Vector2.ZERO

# --- UI Элементы ---
var viewport_container: Control
var camera_rig: Control
var graph_canvas: Control
var inspector_panel: PanelContainer

# Inspector elements
var lbl_insp_class: Label
var lbl_insp_title: Label
var lbl_insp_desc: RichTextLabel
var lbl_insp_cost: Label
var lbl_insp_reqs: RichTextLabel
var lbl_insp_effects: RichTextLabel
var btn_insp_start: Button

# Zoom HUD
var lbl_zoom_info: Label


func _ready() -> void:
	_setup_ui_layout()
	_connect_localization()


func _connect_localization() -> void:
	if has_node("/root/LocalizationManager"):
		var loc = get_node("/root/LocalizationManager")
		if not loc.locale_changed.is_connected(_on_locale_changed):
			loc.locale_changed.connect(_on_locale_changed)


func _on_locale_changed(_locale_code: String) -> void:
	refresh_tree()
	if not selected_directive_id.is_empty() and all_directives.has(selected_directive_id):
		_update_inspector(all_directives[selected_directive_id])


func _get_loc_str(key: String, fallback: String = "") -> String:
	if has_node("/root/LocalizationManager"):
		var loc = get_node("/root/LocalizationManager")
		return loc.tr_key(key, fallback if not fallback.is_empty() else key)
	return fallback if not fallback.is_empty() else key


func setup(state: CountryState, arg2: Variant = null, arg3: Variant = null, arg4: Variant = null) -> void:
	if viewport_container == null:
		_setup_ui_layout()
	player_state = state
	turn_manager = null
	directive_manager = null
	focus_stage_controller = null

	var candidates = [arg2, arg3, arg4]
	for c in candidates:
		if c is TurnManager:
			turn_manager = c
		elif c is DirectiveManager:
			directive_manager = c
		elif c is FocusStageController:
			focus_stage_controller = c

	if focus_stage_controller != null:
		if not focus_stage_controller.tree_loaded.is_connected(_on_tree_loaded):
			focus_stage_controller.tree_loaded.connect(_on_tree_loaded)
		if not focus_stage_controller.focus_tree_switched.is_connected(_on_focus_stage_switched):
			focus_stage_controller.focus_tree_switched.connect(_on_focus_stage_switched)
		if not focus_stage_controller.branches_visibility_changed.is_connected(_on_branches_visibility_changed):
			focus_stage_controller.branches_visibility_changed.connect(_on_branches_visibility_changed)
		if not focus_stage_controller.directive_auto_bypassed.is_connected(_on_directive_auto_bypassed):
			focus_stage_controller.directive_auto_bypassed.connect(_on_directive_auto_bypassed)
		if not focus_stage_controller.directive_force_cancelled.is_connected(_on_directive_force_cancelled):
			focus_stage_controller.directive_force_cancelled.connect(_on_directive_force_cancelled)

	if turn_manager != null:
		if not turn_manager.directive_started.is_connected(_on_directive_started):
			turn_manager.directive_started.connect(_on_directive_started)
		if not turn_manager.directive_completed.is_connected(_on_directive_completed):
			turn_manager.directive_completed.connect(_on_directive_completed)
		if not turn_manager.turn_completed.is_connected(_on_turn_completed):
			turn_manager.turn_completed.connect(_on_turn_completed)

	if directive_manager != null:
		if not directive_manager.directive_started.is_connected(_on_directive_started):
			directive_manager.directive_started.connect(_on_directive_started)
		if not directive_manager.directive_completed.is_connected(_on_directive_completed):
			directive_manager.directive_completed.connect(_on_directive_completed)

	if all_directives.is_empty() and player_state != null and not player_state.country_tag.is_empty():
		load_tree_for_country(player_state.country_tag)
	else:
		refresh_tree()


# ==============================================================================
# ЗАГРУЗКА И НАЗНАЧЕНИЕ ДИРЕКТИВ
# ==============================================================================

## Загружает директивы из скомпилированного странового пакета, выбирая оптимальное стартовое древо 1962 года
func load_tree_for_country(country_tag: String, preferred_tree_id: String = "") -> bool:
	var tag = country_tag.to_upper().strip_edges()
	current_country_tag = tag

	available_trees.clear()
	stage_manifest_data.clear()

	# 1. Приоритетное считывание trees_manifest.json
	var manifest_path = "res://data/countries/%s/directives/trees_manifest.json" % tag
	if FileAccess.file_exists(manifest_path):
		var f_man = FileAccess.open(manifest_path, FileAccess.READ)
		if f_man != null:
			var json_man = JSON.new()
			if json_man.parse(f_man.get_as_text()) == OK and json_man.data is Dictionary:
				stage_manifest_data = json_man.data
				var raw_trees = stage_manifest_data.get("trees", [])
				if raw_trees is Array:
					for t in raw_trees:
						if t is Dictionary:
							available_trees.append({
								"tree_id": str(t.get("tree_id", t.get("id", ""))),
								"stage_category": str(t.get("stage_category", "GENERAL")),
								"is_starting_tree": bool(t.get("is_starting_tree", false)),
								"total_directives": int(t.get("total_directives", t.get("count", 0))),
								"path": str(t.get("file_path", t.get("path", t.get("file", ""))))
							})
				elif raw_trees is Dictionary:
					for tid in raw_trees.keys():
						var t = raw_trees[tid]
						if t is Dictionary:
							available_trees.append({
								"tree_id": str(t.get("id", tid)),
								"stage_category": str(t.get("stage_category", "GENERAL")),
								"is_starting_tree": bool(t.get("is_starting_tree", false)),
								"total_directives": int(t.get("count", t.get("total_directives", 0))),
								"path": str(t.get("file", t.get("file_path", t.get("path", ""))))
							})
			f_man.close()

	# 2. Фоллбэк на trees_index.json если манифест не найден
	if available_trees.is_empty():
		var index_path = "res://data/countries/%s/directives/trees_index.json" % tag
		if FileAccess.file_exists(index_path):
			var f_idx = FileAccess.open(index_path, FileAccess.READ)
			if f_idx != null:
				var json_idx = JSON.new()
				if json_idx.parse(f_idx.get_as_text()) == OK and json_idx.data is Array:
					for t_entry in json_idx.data:
						if t_entry is Dictionary:
							available_trees.append(t_entry)
				f_idx.close()

	_update_tree_selector_options()

	var target_path := ""
	if not preferred_tree_id.is_empty():
		for t in available_trees:
			if t.get("tree_id", "") == preferred_tree_id:
				target_path = t.get("path", "")
				break

	if target_path.is_empty() and stage_manifest_data.has("starting_tree_id"):
		var st_id = str(stage_manifest_data["starting_tree_id"])
		for t in available_trees:
			if t.get("tree_id", "") == st_id:
				target_path = str(t.get("path", ""))
				break

	if target_path.is_empty() and not available_trees.is_empty():
		for t in available_trees:
			var tid = str(t.get("tree_id", "")).to_lower()
			if bool(t.get("is_starting_tree", false)) or tid.contains("base") or tid.contains("initial") or tid.contains("1962") or tid.contains("pre_election"):
				target_path = str(t.get("path", ""))
				break
		if target_path.is_empty():
			target_path = str(available_trees[0].get("path", ""))

	if target_path.is_empty():
		target_path = "res://data/countries/%s/directives/tree.json" % tag

	return load_tree_from_file(target_path)


## Загружает конкретный JSON-файл древа национальных директив
func load_tree_from_file(path: String) -> bool:
	var target_path = path
	if not FileAccess.file_exists(target_path):
		if "/directives/tree_" in target_path:
			var alt_path = target_path.replace("/directives/tree_", "/directives/trees/")
			if FileAccess.file_exists(alt_path):
				target_path = alt_path

	if not FileAccess.file_exists(target_path):
		push_warning("DirectiveTreeView: Файл древа не найден: %s" % target_path)
		return false

	var file = FileAccess.open(target_path, FileAccess.READ)
	if file == null:
		return false

	var text = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		push_error("DirectiveTreeView: Ошибка парсинга JSON: %s" % path)
		return false

	var root_dict: Dictionary = json.data
	all_directives.clear()
	current_tree_path = path

	if root_dict.has("nodes") and root_dict["nodes"] is Dictionary:
		var nodes_dict: Dictionary = root_dict["nodes"]
		for node_id in nodes_dict.keys():
			var raw_node = nodes_dict[node_id]
			if raw_node is Dictionary:
				var res = DirectiveResource.from_dict(raw_node)
				all_directives[res.id] = res

	elif root_dict.has("directives") and root_dict["directives"] is Array:
		for raw_node in root_dict["directives"]:
			if raw_node is Dictionary:
				var res = DirectiveResource.from_dict(raw_node)
				all_directives[res.id] = res

	elif root_dict.has("directives") and root_dict["directives"] is Dictionary:
		var d_dict: Dictionary = root_dict["directives"]
		for k in d_dict.keys():
			var raw_node = d_dict[k]
			if raw_node is Dictionary:
				var res = DirectiveResource.from_dict(raw_node)
				all_directives[res.id] = res

	elif root_dict.has("focuses") and root_dict["focuses"] is Array:
		for raw_node in root_dict["focuses"]:
			if raw_node is Dictionary:
				var res = DirectiveResource.from_dict(raw_node)
				all_directives[res.id] = res

	elif root_dict.has("focus_tree") and root_dict["focus_tree"] is Dictionary:
		var ft: Dictionary = root_dict["focus_tree"]
		var flist = ft.get("focuses", ft.get("directives", []))
		if flist is Array:
			for raw_node in flist:
				if raw_node is Dictionary:
					var res = DirectiveResource.from_dict(raw_node)
					all_directives[res.id] = res

	if directive_manager != null:
		directive_manager.all_directives.clear()
		for d in all_directives.values():
			directive_manager.register_directive(d)
		if player_state != null:
			directive_manager.sync_initial_directives(player_state)

	print("[DirectiveTreeView] Загружено %d директив из [%s]." % [all_directives.size(), path])
	refresh_tree()
	_update_active_tree_hud()
	return true


func _update_tree_selector_options() -> void:
	var active_id := ""
	if focus_stage_controller != null and not focus_stage_controller.current_tree_id.is_empty():
		active_id = focus_stage_controller.current_tree_id
	elif not current_tree_path.is_empty():
		active_id = current_tree_path.get_file().trim_suffix(".json")
	_update_active_tree_hud(active_id)


func _update_active_tree_hud(target_tree_id: String = "") -> void:
	if lbl_active_tree_title == null:
		return

	var display_id = target_tree_id
	if display_id.is_empty() and focus_stage_controller != null:
		display_id = focus_stage_controller.current_tree_id
	if display_id.is_empty() and not current_tree_path.is_empty():
		display_id = current_tree_path.get_file().trim_suffix(".json")
	if display_id.is_empty():
		display_id = tr("СТАРТОВЫЙ КОМПЛЕКС")

	var stage_cat := "GENERAL"
	var total_dirs = all_directives.size()
	var is_start := false

	for t in available_trees:
		if str(t.get("tree_id", "")) == display_id or t.get("path", "") == current_tree_path:
			stage_cat = str(t.get("stage_category", stage_cat))
			if int(t.get("total_directives", 0)) > 0:
				total_dirs = int(t.get("total_directives", total_dirs))
			is_start = bool(t.get("is_starting_tree", is_start))
			break

	if lbl_active_tree_badge != null:
		lbl_active_tree_badge.text = _get_stage_badge(stage_cat, is_start)
	if lbl_active_tree_title != null:
		lbl_active_tree_title.text = "● " + display_id.to_upper()
	if lbl_active_tree_count != null:
		lbl_active_tree_count.text = tr("[ %d ДИРЕКТИВ ]") % total_dirs


func _get_stage_badge(category: String, is_start: bool = false) -> String:
	if is_start:
		return tr("[СТАРТ]")
	match category.to_upper():
		"PROLOGUE": return tr("[ПРОЛОГ]")
		"CRISIS": return tr("[СМУТА]")
		"LEADERSHIP": return tr("[ВЛАСТЬ]")
		"REGIONAL": return tr("[РЕГИОН]")
		"SUPERREGIONAL": return tr("[СУПЕР-Р]")
		"FINAL": return tr("[ЕДИНСТВО]")
		_: return tr("[ПАКЕТ]")


func _on_tree_selected_from_menu(index: int) -> void:
	if index >= 0 and index < available_trees.size():
		var t = available_trees[index]
		var tid = str(t.get("tree_id", ""))
		var stage_cat = str(t.get("stage_category", "GENERAL"))
		var target_path = str(t.get("path", ""))

		if focus_stage_controller != null and not tid.is_empty():
			play_stage_reboot_fx(tid, stage_cat, func():
				focus_stage_controller.switch_focus_tree(tid, true)
			)
		elif not target_path.is_empty():
			play_stage_reboot_fx(tid, stage_cat, func():
				load_tree_from_file(target_path)
			)


func set_directives(directives: Array[DirectiveResource]) -> void:
	all_directives.clear()
	for dir in directives:
		all_directives[dir.id] = dir
	refresh_tree()


func register_directive(dir: DirectiveResource) -> void:
	all_directives[dir.id] = dir
	refresh_tree()


# ==============================================================================
# UI ИНТЕРФЕЙС И РАЗМЕТКА
# ==============================================================================

class GraphCanvasControl extends Control:
	var tree_view: DirectiveTreeView = null
	func _draw() -> void:
		if tree_view != null:
			tree_view._draw_canvas_content(self)


func _setup_ui_layout() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	var hbox := HBoxContainer.new()
	hbox.name = "TreeMainHBox"
	hbox.anchor_right = 1.0
	hbox.anchor_bottom = 1.0
	hbox.add_theme_constant_override("separation", 6)
	add_child(hbox)

	# 1. Левая область: Вьюпорт графа с поддержкой Pan & Zoom
	viewport_container = Control.new()
	viewport_container.name = "ViewportContainer"
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_container.clip_contents = true
	viewport_container.mouse_filter = Control.MOUSE_FILTER_STOP
	viewport_container.gui_input.connect(_on_viewport_gui_input)
	hbox.add_child(viewport_container)

	# Риг камеры (масштабируется и сдвигается)
	camera_rig = Control.new()
	camera_rig.name = "CameraRig"
	camera_rig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport_container.add_child(camera_rig)

	# Холст графа (Custom Drawing соединений и карточек)
	var canvas_ctrl = GraphCanvasControl.new()
	canvas_ctrl.name = "GraphCanvas"
	canvas_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_ctrl.tree_view = self
	graph_canvas = canvas_ctrl
	camera_rig.add_child(graph_canvas)

	# 1.1. CRT Виджет статуса активного древа директив (Tree Status HUD вверху слева)
	var tree_hud_panel := PanelContainer.new()
	tree_hud_panel.name = "TreeStatusHUD"
	tree_hud_panel.offset_left = 12
	tree_hud_panel.offset_top = 10
	tree_hud_panel.offset_right = 520
	tree_hud_panel.offset_bottom = 44
	_apply_terminal_panel_style(tree_hud_panel, Color(0.02, 0.05, 0.05, 0.92), COLOR_CRT_BORDER)
	viewport_container.add_child(tree_hud_panel)

	var tree_hud_hbox := HBoxContainer.new()
	tree_hud_hbox.add_theme_constant_override("separation", 8)
	tree_hud_panel.add_child(tree_hud_hbox)

	var lbl_tree_prefix := Label.new()
	lbl_tree_prefix.text = tr(" НАЦИОНАЛЬНЫЙ ПРОЕКТ:")
	lbl_tree_prefix.add_theme_font_size_override("font_size", 10)
	lbl_tree_prefix.add_theme_color_override("font_color", COLOR_PHOSPHOR_CYAN)
	tree_hud_hbox.add_child(lbl_tree_prefix)

	lbl_active_tree_badge = Label.new()
	lbl_active_tree_badge.text = tr("[ СТАДИЯ ]")
	lbl_active_tree_badge.add_theme_font_size_override("font_size", 10)
	lbl_active_tree_badge.add_theme_color_override("font_color", COLOR_PHOSPHOR_AMBER)
	tree_hud_hbox.add_child(lbl_active_tree_badge)

	lbl_active_tree_title = Label.new()
	lbl_active_tree_title.text = tr("ИНИЦИАЛИЗАЦИЯ...")
	lbl_active_tree_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_active_tree_title.add_theme_font_size_override("font_size", 11)
	lbl_active_tree_title.add_theme_color_override("font_color", COLOR_PHOSPHOR_GREEN)
	tree_hud_hbox.add_child(lbl_active_tree_title)

	lbl_active_tree_count = Label.new()
	lbl_active_tree_count.text = "[ 0 ]"
	lbl_active_tree_count.add_theme_font_size_override("font_size", 10)
	lbl_active_tree_count.add_theme_color_override("font_color", Color(0.6, 0.8, 0.7))
	tree_hud_hbox.add_child(lbl_active_tree_count)

	# 1.2. CRT Виджет управления масштабом (HUD в углу холста)
	var hud_panel := PanelContainer.new()
	hud_panel.name = "ZoomHUD"
	hud_panel.anchor_left = 1.0
	hud_panel.anchor_top = 1.0
	hud_panel.anchor_right = 1.0
	hud_panel.anchor_bottom = 1.0
	hud_panel.offset_left = -160
	hud_panel.offset_top = -46
	hud_panel.offset_right = -12
	hud_panel.offset_bottom = -10
	_apply_terminal_panel_style(hud_panel, Color(0.02, 0.05, 0.05, 0.90), COLOR_CRT_BORDER)
	viewport_container.add_child(hud_panel)

	var hud_hbox := HBoxContainer.new()
	hud_hbox.add_theme_constant_override("separation", 4)
	hud_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hud_panel.add_child(hud_hbox)

	var btn_zoom_out := Button.new()
	btn_zoom_out.text = "[-]"
	btn_zoom_out.custom_minimum_size = Vector2(28, 24)
	btn_zoom_out.pressed.connect(func(): _adjust_zoom(-ZOOM_STEP, viewport_container.size * 0.5))
	hud_hbox.add_child(btn_zoom_out)

	lbl_zoom_info = Label.new()
	lbl_zoom_info.text = "100%"
	lbl_zoom_info.custom_minimum_size = Vector2(46, 0)
	lbl_zoom_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_zoom_info.add_theme_font_size_override("font_size", 11)
	lbl_zoom_info.add_theme_color_override("font_color", COLOR_PHOSPHOR_GREEN)
	hud_hbox.add_child(lbl_zoom_info)

	var btn_zoom_in := Button.new()
	btn_zoom_in.text = "[+]"
	btn_zoom_in.custom_minimum_size = Vector2(28, 24)
	btn_zoom_in.pressed.connect(func(): _adjust_zoom(ZOOM_STEP, viewport_container.size * 0.5))
	hud_hbox.add_child(btn_zoom_in)

	var btn_zoom_reset := Button.new()
	btn_zoom_reset.text = "[R]"
	btn_zoom_reset.tooltip_text = "Сброс камеры (100%)"
	btn_zoom_reset.custom_minimum_size = Vector2(28, 24)
	btn_zoom_reset.pressed.connect(_reset_camera)
	hud_hbox.add_child(btn_zoom_reset)

	# 2. Правая область: Панель телеметрии и досье директивы
	inspector_panel = PanelContainer.new()
	inspector_panel.name = "InspectorPanel"
	inspector_panel.custom_minimum_size = Vector2(360, 0)
	inspector_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_apply_terminal_panel_style(inspector_panel, COLOR_BG_PANEL, COLOR_CRT_BORDER)
	hbox.add_child(inspector_panel)

	var insp_margin := MarginContainer.new()
	insp_margin.add_theme_constant_override("margin_left", 12)
	insp_margin.add_theme_constant_override("margin_top", 12)
	insp_margin.add_theme_constant_override("margin_right", 12)
	insp_margin.add_theme_constant_override("margin_bottom", 12)
	inspector_panel.add_child(insp_margin)

	var insp_vbox := VBoxContainer.new()
	insp_vbox.add_theme_constant_override("separation", 10)
	insp_margin.add_child(insp_vbox)

	lbl_insp_class = Label.new()
	lbl_insp_class.text = tr("ДОСЬЕ ПРОЕКТА // НАЦИОНАЛЬНАЯ ДИРЕКТИВА")
	lbl_insp_class.add_theme_color_override("font_color", Color(0.4, 0.75, 0.65))
	lbl_insp_class.add_theme_font_size_override("font_size", 10)
	insp_vbox.add_child(lbl_insp_class)

	lbl_insp_title = Label.new()
	lbl_insp_title.text = tr("ВЫБЕРИТЕ ДИРЕКТИВУ НА СХЕМЕ")
	lbl_insp_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_insp_title.add_theme_color_override("font_color", COLOR_PHOSPHOR_CYAN)
	lbl_insp_title.add_theme_font_size_override("font_size", 15)
	insp_vbox.add_child(lbl_insp_title)

	var sep1 := HSeparator.new()
	insp_vbox.add_child(sep1)

	var desc_scroll := ScrollContainer.new()
	desc_scroll.custom_minimum_size = Vector2(0, 140)
	desc_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	insp_vbox.add_child(desc_scroll)

	lbl_insp_desc = RichTextLabel.new()
	lbl_insp_desc.bbcode_enabled = true
	lbl_insp_desc.fit_content = true
	lbl_insp_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_insp_desc.text = tr("[color=#779988]Изучите схему стратегических директив государства. Выберите проект для анализа оперативных затрат, требований кабинета и ожидаемых геополитических эффектов.[/color]")
	desc_scroll.add_child(lbl_insp_desc)

	lbl_insp_cost = Label.new()
	lbl_insp_cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_insp_cost.text = tr("ОПЕРАТИВНЫЕ ЗАТРАТЫ: --")
	lbl_insp_cost.add_theme_color_override("font_color", COLOR_PHOSPHOR_AMBER)
	lbl_insp_cost.add_theme_font_size_override("font_size", 11)
	insp_vbox.add_child(lbl_insp_cost)

	var sep_req := HSeparator.new()
	insp_vbox.add_child(sep_req)

	var lbl_req_header := Label.new()
	lbl_req_header.text = tr("ТРЕБОВАНИЯ И СТАТУС ВЕТКИ:")
	lbl_req_header.add_theme_color_override("font_color", Color(0.4, 0.75, 0.65))
	lbl_req_header.add_theme_font_size_override("font_size", 10)
	insp_vbox.add_child(lbl_req_header)

	var req_scroll := ScrollContainer.new()
	req_scroll.custom_minimum_size = Vector2(0, 95)
	req_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	insp_vbox.add_child(req_scroll)

	lbl_insp_reqs = RichTextLabel.new()
	lbl_insp_reqs.bbcode_enabled = true
	lbl_insp_reqs.fit_content = true
	lbl_insp_reqs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_insp_reqs.text = "[color=#668877]--[/color]"
	req_scroll.add_child(lbl_insp_reqs)

	var sep2 := HSeparator.new()
	insp_vbox.add_child(sep2)

	var lbl_eff_header := Label.new()
	lbl_eff_header.text = tr("ОЖИДАЕМЫЕ ПОСЛЕДСТВИЯ И НАГРАДЫ:")
	lbl_eff_header.add_theme_color_override("font_color", Color(0.4, 0.75, 0.65))
	lbl_eff_header.add_theme_font_size_override("font_size", 10)
	insp_vbox.add_child(lbl_eff_header)

	var eff_scroll := ScrollContainer.new()
	eff_scroll.custom_minimum_size = Vector2(0, 120)
	eff_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	insp_vbox.add_child(eff_scroll)

	lbl_insp_effects = RichTextLabel.new()
	lbl_insp_effects.bbcode_enabled = true
	lbl_insp_effects.fit_content = true
	lbl_insp_effects.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_insp_effects.text = "[color=#668877]--[/color]"
	eff_scroll.add_child(lbl_insp_effects)

	btn_insp_start = Button.new()
	btn_insp_start.text = tr("[ УТВЕРДИТЬ ДИРЕКТИВУ ]")
	btn_insp_start.disabled = true
	btn_insp_start.custom_minimum_size = Vector2(0, 42)
	btn_insp_start.pressed.connect(_on_start_button_pressed)
	insp_vbox.add_child(btn_insp_start)

	_setup_reboot_overlay()


# ==============================================================================
# УПРАВЛЕНИЕ КАМЕРОЙ: PANNING & ZOOMING
# ==============================================================================

func _on_viewport_gui_input(event: InputEvent) -> void:
	# 1. Масштабирование колесиком мыши (Zoom)
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.is_pressed():
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_adjust_zoom(ZOOM_STEP, mb.position)
				get_viewport().set_input_as_handled()
				return
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_adjust_zoom(-ZOOM_STEP, mb.position)
				get_viewport().set_input_as_handled()
				return
			# Старт панорамирования (MMB, RMB или Shift+LMB)
			elif mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT or (mb.button_index == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_SHIFT)):
				is_panning = true
				pan_drag_start = mb.global_position
				pan_canvas_start = camera_rig.position
				get_viewport().set_input_as_handled()
				return
		else:
			if mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_LEFT:
				if is_panning:
					is_panning = false
					get_viewport().set_input_as_handled()
					return

	# 2. Панорамирование перемещением мыши (Pan)
	elif event is InputEventMouseMotion and is_panning:
		var mm = event as InputEventMouseMotion
		var delta_pos = mm.global_position - pan_drag_start
		camera_rig.position = pan_canvas_start + delta_pos
		get_viewport().set_input_as_handled()


func _adjust_zoom(step_val: float, pivot_screen_pos: Vector2) -> void:
	var old_zoom = current_zoom
	var new_zoom = clampf(current_zoom + step_val, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(old_zoom, new_zoom):
		return

	# Масштабирование относительно точки под курсором
	var pivot_in_rig = (pivot_screen_pos - camera_rig.position) / old_zoom
	current_zoom = new_zoom
	camera_rig.scale = Vector2(current_zoom, current_zoom)
	camera_rig.position = pivot_screen_pos - (pivot_in_rig * current_zoom)

	if lbl_zoom_info != null:
		lbl_zoom_info.text = "%d%%" % int(round(current_zoom * 100))


func _reset_camera() -> void:
	current_zoom = 1.0
	camera_rig.scale = Vector2.ONE
	camera_rig.position = Vector2.ZERO
	if lbl_zoom_info != null:
		lbl_zoom_info.text = "100%"


# ==============================================================================
# ПОСТРОЕНИЕ И ОБНОВЛЕНИЕ ГРАФА
# ==============================================================================

func refresh_tree() -> void:
	if graph_canvas == null:
		return

	# Очистка старых карточек узлов
	for child in graph_canvas.get_children():
		child.queue_free()
	node_controls.clear()

	var min_gx: float = 0.0
	var min_gy: float = 0.0
	var max_x: float = 1200.0
	var max_y: float = 800.0

	var has_explicit_grid := false
	for dir in all_directives.values():
		if dir.grid_position != Vector2.ZERO:
			has_explicit_grid = true
		min_gx = minf(min_gx, dir.grid_position.x)
		min_gy = minf(min_gy, dir.grid_position.y)

	var offset_x = min_gx if min_gx < 0.0 else 0.0
	var offset_y = min_gy if min_gy < 0.0 else 0.0

	# Создание интерактивных узлов графа
	for dir_id in all_directives.keys():
		var dir: DirectiveResource = all_directives[dir_id]
		var card = _create_directive_node(dir)
		graph_canvas.add_child(card)
		node_controls[dir_id] = card

		var pos = _calculate_node_position(dir, offset_x, offset_y, has_explicit_grid)
		card.position = pos
		max_x = maxf(max_x, pos.x + node_size.x + 120)
		max_y = maxf(max_y, pos.y + node_size.y + 120)

	graph_canvas.custom_minimum_size = Vector2(max_x, max_y)
	graph_canvas.size = Vector2(max_x, max_y)
	graph_canvas.queue_redraw()

	if not selected_directive_id.is_empty() and all_directives.has(selected_directive_id):
		_update_inspector(all_directives[selected_directive_id])
	elif player_state != null and not player_state.active_directives.is_empty() and all_directives.has(str(player_state.active_directives[0])):
		selected_directive_id = str(player_state.active_directives[0])
		_update_inspector(all_directives[selected_directive_id])
	elif not all_directives.is_empty():
		var first_pick: DirectiveResource = null
		for d in all_directives.values():
			if d.status == DirectiveResource.Status.AVAILABLE or (player_state != null and d.can_be_started(player_state)["allowed"]):
				first_pick = d
				break
			elif first_pick == null and d.status != DirectiveResource.Status.COMPLETED and d.status != DirectiveResource.Status.MUTUALLY_BLOCKED:
				first_pick = d
		if first_pick == null:
			first_pick = all_directives.values()[0]
		selected_directive_id = first_pick.id
		_update_inspector(first_pick)


func _calculate_node_position(dir: DirectiveResource, offset_x: float = 0.0, offset_y: float = 0.0, has_explicit_grid: bool = false) -> Vector2:
	if has_explicit_grid or dir.grid_position != Vector2.ZERO:
		var gx = dir.grid_position.x - offset_x
		var gy = dir.grid_position.y - offset_y
		return origin_offset + Vector2(gx * grid_step.x, gy * grid_step.y)

	# Автоматический расчет по глубине предков при отсутствии явной сетки
	var depth = _calculate_prereq_depth(dir)
	var row := 0
	for d in all_directives.values():
		if d.id == dir.id:
			break
		if _calculate_prereq_depth(d) == depth:
			row += 1

	return origin_offset + Vector2(depth * grid_step.x, row * grid_step.y)


func _calculate_prereq_depth(dir: DirectiveResource) -> int:
	if dir.prerequisites.is_empty():
		return 0
	var max_d := 0
	for p_id in dir.prerequisites:
		if all_directives.has(p_id):
			max_d = maxi(max_d, _calculate_prereq_depth(all_directives[p_id]) + 1)
	return max_d


func _format_directive_title(dir: DirectiveResource) -> String:
	if dir == null:
		return ""
	var loc = get_node_or_null("/root/LocalizationManager")
	if loc != null:
		var loc_title = loc.tr_key(dir.id, loc.tr_key(dir.id + "_name", ""))
		if not loc_title.is_empty() and loc_title != dir.id:
			return loc_title
	var raw = dir.title
	if raw.is_empty() or raw == dir.id or raw.begins_with("USA_") or raw.begins_with("GER_") or raw.begins_with("JAP_") or raw.begins_with("RUS_") or raw.contains("_"):
		var clean = raw
		if clean.length() > 4 and clean[3] == "_":
			clean = clean.substr(4)
		var words = clean.split("_")
		var capitalized_words: Array[String] = []
		for w in words:
			if not w.is_empty():
				capitalized_words.append(w.capitalize())
		if not capitalized_words.is_empty():
			return " ".join(capitalized_words)
	return raw


# ==============================================================================
# СОЗДАНИЕ УЗЛА ДИРЕКТИВЫ (RETRO TERMINAL NODE)
# ==============================================================================

func _create_directive_node(dir: DirectiveResource) -> Control:
	var colors = {
		"locked": COLOR_PHOSPHOR_LOCKED,
		"cyan": COLOR_PHOSPHOR_CYAN,
		"amber": COLOR_PHOSPHOR_AMBER,
		"exclusion": COLOR_EXCLUSION_RED,
		"green": COLOR_PHOSPHOR_GREEN
	}
	return DirectiveNodeFactoryScript.create_directive_node(
		dir, node_size, player_state, focus_stage_controller,
		directive_manager, colors, current_country_tag,
		all_directives, _format_directive_title(dir),
		Callable(self, "_on_node_hovered"),
		Callable(self, "_on_node_clicked")
	)


func _build_directive_tooltip(dir: DirectiveResource) -> String:
	return DirectiveNodeFactoryScript.build_directive_tooltip(dir, all_directives, player_state)


func _generate_ascii_bar(current: int, total: int) -> String:
	return DirectiveNodeFactoryScript.generate_ascii_bar(current, total)


# ==============================================================================
# ПРОЦЕДУРНАЯ ОТРИСОВКА СВЯЗЕЙ (CUSTOM DRAWING & DYNAMIC ROUTING)
# ==============================================================================

func _on_graph_canvas_draw() -> void:
	if graph_canvas != null:
		_draw_canvas_content(graph_canvas)


func _draw_canvas_content(canvas: Control) -> void:
	DirectiveTreeCanvasDrawerScript.draw_canvas_content(
		canvas, all_directives, node_controls, node_size,
		player_state, turn_manager,
		COLOR_PHOSPHOR_DIM, COLOR_PHOSPHOR_CYAN, COLOR_PHOSPHOR_AMBER,
		COLOR_PHOSPHOR_GREEN, COLOR_EXCLUSION_RED
	)


func _find_visible_prerequisites(dir_id: String, visited: Array[String] = []) -> Array[String]:
	return DirectiveTreeCanvasDrawerScript.find_visible_prerequisites(dir_id, all_directives, node_controls, visited)


func _get_all_prereq_ids(dir: DirectiveResource) -> Array[String]:
	return DirectiveTreeCanvasDrawerScript.get_all_prereq_ids(dir)


func _draw_orthogonal_bus(canvas: Control, from: Vector2, to: Vector2, col: Color, width: float) -> void:
	DirectiveTreeCanvasDrawerScript.draw_orthogonal_bus(canvas, from, to, col, width)


func _draw_exclusive_link(canvas: Control, a: Vector2, b: Vector2) -> void:
	DirectiveTreeCanvasDrawerScript.draw_exclusive_link(canvas, a, b, COLOR_EXCLUSION_RED)


# ==============================================================================
# ОБРАБОТКА ВЗАИМОДЕЙСТВИЯ И ОБНОВЛЕНИЕ ДОСЬЕ
# ==============================================================================

func _on_node_hovered(dir: DirectiveResource) -> void:
	directive_hovered.emit(dir)


func _on_node_clicked(dir: DirectiveResource) -> void:
	selected_directive_id = dir.id
	_update_inspector(dir)
	directive_selected.emit(dir)


func _update_inspector(dir: DirectiveResource) -> void:
	DirectiveInspectorFormatterScript.update_inspector(
		dir, all_directives, player_state, turn_manager,
		focus_stage_controller, lbl_insp_title, lbl_insp_desc,
		lbl_insp_cost, lbl_insp_reqs, lbl_insp_effects,
		btn_insp_start, _format_directive_title(dir)
	)


func _on_start_button_pressed() -> void:
	if selected_directive_id.is_empty() or not all_directives.has(selected_directive_id):
		return

	var dir: DirectiveResource = all_directives[selected_directive_id]
	var success := false

	if turn_manager != null:
		success = turn_manager.start_directive(dir)
	elif directive_manager != null and player_state != null:
		success = directive_manager.start_directive(dir.id, player_state)

	if success:
		directive_initiated.emit(dir)
		refresh_tree()


func _on_directive_started(_dir: DirectiveResource) -> void:
	refresh_tree()


func _on_directive_completed(_dir: DirectiveResource) -> void:
	refresh_tree()


func _on_turn_completed(_turn: int, _report: EconomyEngine.EconomicTurnReport) -> void:
	refresh_tree()


# ==============================================================================
# СТИЛИЗАЦИЯ CRT ТЕРМИНАЛА
# ==============================================================================

func _apply_terminal_panel_style(panel: PanelContainer, bg: Color, border: Color) -> void:
	DirectiveNodeFactoryScript.apply_terminal_panel_style(panel, bg, border)


func _apply_terminal_card_style(btn: Button, bg: Color, border: Color) -> void:
	DirectiveNodeFactoryScript.apply_terminal_card_style(btn, bg, border)


func _resolve_directive_texture(dir: DirectiveResource) -> Texture2D:
	return DirectiveNodeFactoryScript.resolve_directive_texture(dir, current_country_tag)


# ==============================================================================
# CRT REBOOT OVERLAY & STAGE TRANSITION ANIMATION
# ==============================================================================

func _setup_reboot_overlay() -> void:
	if reboot_overlay != null or viewport_container == null:
		return

	reboot_overlay = Control.new()
	reboot_overlay.name = "CRTRebootOverlay"
	reboot_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	reboot_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reboot_overlay.visible = false

	var bg := ColorRect.new()
	bg.name = "RebootBG"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.01, 0.03, 0.02, 0.90)
	reboot_overlay.add_child(bg)

	var scanlines := ColorRect.new()
	scanlines.name = "Scanlines"
	scanlines.set_anchors_preset(Control.PRESET_FULL_RECT)
	scanlines.color = Color(0.05, 0.25, 0.15, 0.14)
	reboot_overlay.add_child(scanlines)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	reboot_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(580, 240)
	_apply_terminal_panel_style(panel, Color(0.02, 0.05, 0.04, 0.98), COLOR_PHOSPHOR_CYAN)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var header := Label.new()
	header.text = tr("/// ПЕРЕЗАГРУЗКА БАЗЫ ДИРЕКТИВ / СМЕНА СТАДИИ ///")
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", COLOR_PHOSPHOR_CYAN)
	vbox.add_child(header)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	lbl_reboot_log = RichTextLabel.new()
	lbl_reboot_log.bbcode_enabled = true
	lbl_reboot_log.fit_content = true
	lbl_reboot_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl_reboot_log.add_theme_font_size_override("normal_font_size", 12)
	vbox.add_child(lbl_reboot_log)

	viewport_container.add_child(reboot_overlay)


## Запуск визуального эффекта CRT перезагрузки терминала при смене стадии
func play_stage_reboot_fx(new_tree_id: String, stage_name: String, on_midpoint_callback: Callable = Callable()) -> void:
	if viewport_container == null:
		_setup_ui_layout()
	if reboot_overlay == null:
		_setup_reboot_overlay()

	is_rebooting = true
	reboot_overlay.visible = true
	reboot_overlay.modulate.a = 0.0

	var stage_badge = _get_stage_badge(stage_name)
	lbl_reboot_log.text = tr("[color=#ff3344]>>> [СИСТЕМНЫЙ СИГНАЛ] СМЕНА ПОЛИТИЧЕСКОГО КУРСА: ЗАГРУЗКА ПАКЕТА ДИРЕКТИВ [%s]...[/color]\n") % new_tree_id
	lbl_reboot_log.text += tr("[color=#00f2ff]>>> ИНИЦИАЛИЗАЦИЯ CRT-ПРОТОКОЛА ПЕРЕЗАГРУЗКИ ТЕРМИНАЛА...[/color]\n")
	lbl_reboot_log.text += tr("[color=#2bf070]>>> АРХИВАЦИЯ ПРЕДЫДУЩЕГО ПАКЕТА ГОСУДАРСТВЕННЫХ ДИРЕКТИВ... [OK][/color]\n")
	var reboot_load_fmt = tr("[color=#ffe040]>>> ЗАГРУЗКА ПАКЕТА: [%s] | ФАЗА: %s...[/color]\n")
	lbl_reboot_log.text += reboot_load_fmt % [new_tree_id, stage_badge]
	lbl_reboot_log.text += tr("[color=#00f2ff]>>> КАЛИБРОВКА МАТРИЦЫ ПРИОРИТЕТОВ КАБИНЕТА И АКТИВАЦИЯ УЗЛОВ...[/color]")

	# Эффект строчной помехи / глитча кинескопа
	var glitch_tw = create_tween()
	glitch_tw.tween_property(reboot_overlay, "position:x", 3.0, 0.03)
	glitch_tw.tween_property(reboot_overlay, "position:x", -3.0, 0.03)
	glitch_tw.tween_property(reboot_overlay, "position:x", 1.5, 0.03)
	glitch_tw.tween_property(reboot_overlay, "position:x", 0.0, 0.03)

	var tw = create_tween()
	tw.tween_property(reboot_overlay, "modulate:a", 1.0, 0.12)
	tw.tween_interval(0.35)

	tw.tween_callback(func():
		if on_midpoint_callback.is_valid():
			on_midpoint_callback.call()
		refresh_tree()
		_animate_nodes_appearance()
	)

	tw.tween_interval(0.30)
	tw.tween_property(reboot_overlay, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func():
		reboot_overlay.visible = false
		is_rebooting = false
	)


func _animate_nodes_appearance() -> void:
	var visible_nodes: Array[Control] = []
	for dir_id in node_controls.keys():
		var ctrl: Control = node_controls[dir_id]
		if ctrl != null and ctrl.visible:
			visible_nodes.append(ctrl)

	# Сортировка построчно (сверху вниз, затем слева направо)
	visible_nodes.sort_custom(func(a: Control, b: Control) -> bool:
		if absf(a.position.y - b.position.y) > 20.0:
			return a.position.y < b.position.y
		return a.position.x < b.position.x
	)

	for i in range(visible_nodes.size()):
		var ctrl: Control = visible_nodes[i]
		ctrl.modulate.a = 0.0
		var orig_y = ctrl.position.y
		ctrl.position.y += 10.0

		var row_delay = (orig_y / 180.0) * 0.05 + (i * 0.01)
		var tw = create_tween()
		tw.tween_interval(clampf(row_delay, 0.02, 0.35))
		tw.set_parallel(true)
		tw.tween_property(ctrl, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(ctrl, "position:y", orig_y, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ==============================================================================
# ИНТЕГРАЦИЯ С FOCUS_STAGE_CONTROLLER
# ==============================================================================

func _on_tree_loaded(tree_id: String, directives_map: Dictionary) -> void:
	all_directives.clear()
	for k: Variant in directives_map.keys():
		all_directives[str(k)] = directives_map[k]
	refresh_tree()


func _on_focus_stage_switched(tree_id: String, new_directives_graph: Dictionary, stage_meta: Dictionary) -> void:
	all_directives.clear()
	for k in new_directives_graph.keys():
		all_directives[k] = new_directives_graph[k]

	var stage_cat = str(stage_meta.get("stage_category", "GENERAL"))
	play_stage_reboot_fx(tree_id, stage_cat, func():
		refresh_tree()
	)

	# Обновление заголовка активного древа в статус-панели
	_update_active_tree_hud(tree_id)


func _on_branches_visibility_changed(hidden_node_ids: Array[String], visible_node_ids: Array[String]) -> void:
	apply_branch_visibility(hidden_node_ids, visible_node_ids)


## Применение динамической видимости ветвей (allow_branch)
func apply_branch_visibility(hidden_node_ids: Array[String], visible_node_ids: Array[String]) -> void:
	hidden_branch_nodes = hidden_node_ids
	for h_id in hidden_node_ids:
		if node_controls.has(h_id):
			node_controls[h_id].visible = false
	for v_id in visible_node_ids:
		if node_controls.has(v_id):
			node_controls[v_id].visible = true

	if graph_canvas != null:
		graph_canvas.queue_redraw()


func _on_directive_auto_bypassed(_directive: DirectiveResource) -> void:
	refresh_tree()


func _on_directive_force_cancelled(_directive: DirectiveResource, _reason: String) -> void:
	refresh_tree()
