class_name CountrySelectMapWidget
extends Control

##
## CountrySelectMapWidget: Интерактивный тактический терминал выбора страны TNO
##
## Реализует:
## 1. Автономный SubViewport с фрагментным шейдером и иерархией границ.
## 2. Подсветку стран с древами фокусов и приглушение generic-государств.
## 3. Тактические пины [★ TAG] над государствами с национальным контентом.
## 4. Плавное центрирование и пресеты театров (Россия, Европа, США, Азия, Весь мир).
## 5. Полную синхронизацию с главным меню и досье лидера.
##

signal country_selected(tag: String, dossier: Dictionary)
signal country_hovered(tag: String, data: Dictionary)

const MAP_CONTROLLER_SCRIPT = preload("res://scripts/map_controller.gd")
const PROVINCE_SHADER = preload("res://shaders/province_map.gdshader")

@onready var viewport_container: SubViewportContainer = $ViewportContainer
@onready var sub_viewport: SubViewport = $ViewportContainer/SubViewport
@onready var camera: Camera2D = $ViewportContainer/SubViewport/Camera2D
@onready var map_controller: MapController = $ViewportContainer/SubViewport/MapController
@onready var pins_overlay: Control = $ViewportContainer/SubViewport/PinsOverlay

# HUD Elements
@onready var lbl_hover_info: Label = $HUD/BottomPanel/HoverInfoLabel
@onready var lbl_coords: Label = $HUD/TopBar/CoordsLabel
@onready var btn_filter_focus: Button = $HUD/TopBar/FilterFocusButton
@onready var btn_zoom_in: Button = $HUD/ControlsBar/ZoomInButton
@onready var btn_zoom_out: Button = $HUD/ControlsBar/ZoomOutButton
@onready var btn_view_world: Button = $HUD/PresetsBar/WorldButton
@onready var btn_view_russia: Button = $HUD/PresetsBar/RussiaButton
@onready var btn_view_europe: Button = $HUD/PresetsBar/EuropeButton
@onready var btn_view_usa: Button = $HUD/PresetsBar/USAButton
@onready var btn_view_asia: Button = $HUD/PresetsBar/AsiaButton

var selected_tag: String = ""
var hovered_tag: String = ""
var is_focus_filter_active: bool = true
var country_centroids: Dictionary = {} # Tag -> Vector2 in map texture coords
var tags_with_focus: Dictionary = {}   # Tag -> bool
var is_map_ready: bool = false

# Coordinates presets in map texture space (5632 x 2048)
const PRESETS = {
	"WORLD": {"center": Vector2(2816, 850), "zoom": 0.24},
	"RUSSIA": {"center": Vector2(3500, 380), "zoom": 0.75},
	"EUROPE": {"center": Vector2(2760, 520), "zoom": 0.85},
	"USA": {"center": Vector2(1200, 700), "zoom": 0.65},
	"ASIA": {"center": Vector2(4400, 850), "zoom": 0.70}
}


func _ready() -> void:
	_connect_hud_signals()
	_load_focus_tags_cache()

	if map_controller != null:
		map_controller.enable_camera_control = false # Мы управляем перемещением сами
		map_controller.map_initialized.connect(_on_map_initialized)
		map_controller.province_hovered.connect(_on_province_hovered)
		map_controller.province_clicked.connect(_on_province_clicked)

	# Адаптация размера SubViewport
	resized.connect(_on_resized)
	_on_resized()


func _on_resized() -> void:
	if sub_viewport != null:
		var target_size = Vector2i(int(size.x), int(size.y))
		if target_size.x > 0 and target_size.y > 0:
			if viewport_container == null or not viewport_container.stretch:
				sub_viewport.size = target_size
			if camera != null:
				camera.position = Vector2(target_size) * 0.5


func _connect_hud_signals() -> void:
	if btn_view_world != null: btn_view_world.pressed.connect(func(): focus_preset("WORLD"))
	if btn_view_russia != null: btn_view_russia.pressed.connect(func(): focus_preset("RUSSIA"))
	if btn_view_europe != null: btn_view_europe.pressed.connect(func(): focus_preset("EUROPE"))
	if btn_view_usa != null: btn_view_usa.pressed.connect(func(): focus_preset("USA"))
	if btn_view_asia != null: btn_view_asia.pressed.connect(func(): focus_preset("ASIA"))

	if btn_zoom_in != null: btn_zoom_in.pressed.connect(_zoom_in)
	if btn_zoom_out != null: btn_zoom_out.pressed.connect(_zoom_out)

	if btn_filter_focus != null:
		btn_filter_focus.pressed.connect(_toggle_focus_filter)


func _load_focus_tags_cache() -> void:
	tags_with_focus.clear()
	var session = get_node_or_null("/root/GameSession")
	var tags_list: Array[String] = []
	if session != null and session.has_method("get_tags_with_focus_trees"):
		tags_list = session.get_tags_with_focus_trees()
	else:
		tags_list = ["KOM", "OMS", "SVE", "TYU", "IRK", "CHT", "SAM", "NOV", "TOM", "WRS", "GER", "USA", "JAP", "ITA", "IBR"]

	for t in tags_list:
		tags_with_focus[t.to_upper()] = true


func _on_map_initialized(_provinces_count: int, _map_size: Vector2i) -> void:
	is_map_ready = true
	_calculate_country_centroids()
	apply_focus_highlight(is_focus_filter_active)
	_create_tactical_pins()

	# Стартовая фокусировка на России / Варлордах
	focus_preset("RUSSIA", true)


func _calculate_country_centroids() -> void:
	country_centroids.clear()
	var sums: Dictionary = {}
	var counts: Dictionary = {}

	for pid in map_controller.provinces_data.keys():
		var p_meta = map_controller.provinces_data[pid]
		var owner = p_meta.get("owner", "")
		if owner.is_empty() and map_controller.starting_regions_data.has(pid):
			owner = map_controller.starting_regions_data[pid].get("owner_tag", "")

		if owner.is_empty() or owner in ["WST", "WASTE"]:
			continue

		var c_pos = map_controller.get_province_centroid(pid)
		if not sums.has(owner):
			sums[owner] = Vector2.ZERO
			counts[owner] = 0

		sums[owner] += c_pos
		counts[owner] += 1

	for tag in sums.keys():
		var count = counts[tag]
		if count > 0:
			country_centroids[tag] = sums[tag] / float(count)


##
## Применяет фильтрацию: яркие цвета для стран с фокусами, затемнение для generic
##
func apply_focus_highlight(enabled: bool) -> void:
	is_focus_filter_active = enabled
	if not is_map_ready or map_controller.lut_image == null:
		return

	var dark_dim := Color(0.06, 0.08, 0.09, 1.0)
	var default_color = map_controller.default_province_color

	for pid in map_controller.provinces_data.keys():
		var p_meta = map_controller.provinces_data[pid]
		var owner = p_meta.get("owner", "")
		if owner.is_empty() and map_controller.starting_regions_data.has(pid):
			owner = map_controller.starting_regions_data[pid].get("owner_tag", "")

		var p_type = p_meta.get("type", "land")
		if p_type in ["sea", "lake"]:
			continue

		var has_tree = tags_with_focus.has(owner)
		var coord = map_controller._id_to_lut_coords(pid)

		if enabled:
			if has_tree:
				var col = map_controller._resolve_initial_province_color(pid)
				map_controller.lut_image.set_pixel(coord.x, coord.y, col)
			else:
				map_controller.lut_image.set_pixel(coord.x, coord.y, dark_dim)
		else:
			var col = map_controller._resolve_initial_province_color(pid)
			map_controller.lut_image.set_pixel(coord.x, coord.y, col)

	map_controller.lut_texture.update(map_controller.lut_image)

	if btn_filter_focus != null:
		btn_filter_focus.text = tr("[★ ТОЛЬКО С ФОКУСАМИ: ВКЛ]") if enabled else tr("[★ ТОЛЬКО С ФОКУСАМИ: ВЫКЛ]")
		btn_filter_focus.add_theme_color_override("font_color", Color(0.2, 0.95, 0.85) if enabled else Color(0.5, 0.6, 0.6))

	if pins_overlay != null:
		pins_overlay.visible = true


func _toggle_focus_filter() -> void:
	apply_focus_highlight(not is_focus_filter_active)


##
## Создает визуальные CRT-пины над столицами/центроидами стран с фокусами
##
func _create_tactical_pins() -> void:
	if pins_overlay == null:
		return

	for c in pins_overlay.get_children():
		c.queue_free()

	for tag in country_centroids.keys():
		if not tags_with_focus.has(tag):
			continue

		var pin_btn := Button.new()
		pin_btn.text = "★ %s" % tag
		pin_btn.custom_minimum_size = Vector2(48, 20)
		pin_btn.add_theme_font_size_override("font_size", 9)
		pin_btn.add_theme_color_override("font_color", Color(0.95, 0.90, 0.35, 1.0))

		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.02, 0.05, 0.06, 0.85)
		style.border_width_bottom = 1
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_color = Color(0.2, 0.85, 0.65, 0.8)
		style.content_margin_left = 4
		style.content_margin_right = 4
		style.content_margin_top = 1
		style.content_margin_bottom = 1
		pin_btn.add_theme_stylebox_override("normal", style)

		var captured_tag = tag
		pin_btn.pressed.connect(func(): select_country(captured_tag, true))
		pin_btn.mouse_entered.connect(func(): _on_pin_hovered(captured_tag))

		pin_btn.set_meta("world_pos", country_centroids[tag])
		pins_overlay.add_child(pin_btn)

	_update_pins_positions()


func _process(_delta: float) -> void:
	_update_pins_positions()


func _update_pins_positions() -> void:
	if pins_overlay == null or not is_map_ready:
		return

	var map_origin = map_controller.position - (Vector2(map_controller.map_size) * 0.5 * map_controller.scale)
	var current_scale = map_controller.scale

	for child in pins_overlay.get_children():
		if child is Control and child.has_meta("world_pos"):
			var w_pos: Vector2 = child.get_meta("world_pos")
			var screen_pos = map_origin + (w_pos * current_scale)
			child.position = screen_pos - (child.size * 0.5)

			# Плавная видимость в зависимости от масштаба
			child.visible = (current_scale.x >= 0.35)


func _on_pin_hovered(tag: String) -> void:
	var session = get_node_or_null("/root/GameSession")
	var d = session.get_country_dossier(tag) if session != null else {}
	_display_hover_info(tag, d)


# ==============================================================================
# ПЕРЕМЕЩЕНИЕ И ЗУМ
# ==============================================================================

func focus_preset(preset_key: String, instant: bool = false) -> void:
	if not PRESETS.has(preset_key):
		return
	var p = PRESETS[preset_key]
	focus_coordinates(p["center"], p["zoom"], instant)


func focus_country(tag: String, instant: bool = false) -> void:
	var clean = tag.to_upper().strip_edges()
	if country_centroids.has(clean):
		focus_coordinates(country_centroids[clean], 0.85, instant)


func focus_coordinates(target_map_pos: Vector2, target_zoom: float, instant: bool = false) -> void:
	if not is_map_ready or map_controller == null:
		return

	var viewport_center = sub_viewport.size * 0.5
	var map_half_size = Vector2(map_controller.map_size) * 0.5
	var dest_scale := Vector2(target_zoom, target_zoom)
	var dest_pos = viewport_center - (target_map_pos - map_half_size) * dest_scale

	if instant:
		map_controller.scale = dest_scale
		map_controller.current_zoom = target_zoom
		map_controller.position = dest_pos
		map_controller._sync_border_uniforms_to_shader()
	else:
		var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(map_controller, "scale", dest_scale, 0.45)
		tween.tween_property(map_controller, "position", dest_pos, 0.45)
		tween.tween_property(map_controller, "current_zoom", target_zoom, 0.45)

	if lbl_coords != null:
		var lat = int(round(90.0 - (target_map_pos.y / float(map_controller.map_size.y)) * 180.0))
		var lon = int(round((target_map_pos.x / float(map_controller.map_size.x)) * 360.0 - 180.0))
		lbl_coords.text = tr("КООРДИНАТЫ: %d°%s %d°%s // МАСШТАБ: %0.1fx") % [
			abs(lat), "N" if lat >= 0 else "S",
			abs(lon), "E" if lon >= 0 else "W",
			target_zoom
		]


func _zoom_in() -> void:
	if map_controller == null: return
	var new_z = clampf(map_controller.scale.x * 1.35, 0.20, 3.5)
	var center = _get_current_map_center()
	focus_coordinates(center, new_z)


func _zoom_out() -> void:
	if map_controller == null: return
	var new_z = clampf(map_controller.scale.x * 0.75, 0.20, 3.5)
	var center = _get_current_map_center()
	focus_coordinates(center, new_z)


func _get_current_map_center() -> Vector2:
	var viewport_center = sub_viewport.size * 0.5
	var map_half_size = Vector2(map_controller.map_size) * 0.5
	var current_scale = map_controller.scale
	return ((viewport_center - map_controller.position) / current_scale) + map_half_size


# ==============================================================================
# ОБРАБОТКА МЫШИ И ВЫБОР
# ==============================================================================

var is_panning: bool = false
var pan_drag_start: Vector2 = Vector2.ZERO


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.is_pressed():
			_zoom_in()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.is_pressed():
			_zoom_out()
			accept_event()
		elif (event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT) and event.is_pressed():
			is_panning = true
			pan_drag_start = event.position
			accept_event()
		elif (event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT) and not event.is_pressed():
			is_panning = false
			accept_event()
	elif event is InputEventMouseMotion and is_panning and map_controller != null:
		map_controller.position += event.relative
		_update_pins_positions()
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if map_controller == null or not is_map_ready:
		return
	if event is InputEventKey and event.is_pressed() and not event.echo:
		var pan_step := 50.0
		match event.keycode:
			KEY_W, KEY_UP:
				map_controller.position.y += pan_step
				_update_pins_positions()
			KEY_S, KEY_DOWN:
				map_controller.position.y -= pan_step
				_update_pins_positions()
			KEY_A, KEY_LEFT:
				map_controller.position.x += pan_step
				_update_pins_positions()
			KEY_D, KEY_RIGHT:
				map_controller.position.x -= pan_step
				_update_pins_positions()


func _on_province_hovered(pid: int, data: Dictionary) -> void:
	var owner = data.get("owner", "")
	if owner.is_empty() and map_controller.starting_regions_data.has(pid):
		owner = map_controller.starting_regions_data[pid].get("owner_tag", "")

	if owner != hovered_tag:
		hovered_tag = owner
		var session = get_node_or_null("/root/GameSession")
		var dossier = session.get_country_dossier(owner) if session != null else {}
		_display_hover_info(owner, dossier)
		country_hovered.emit(owner, dossier)


func _on_province_clicked(pid: int, data: Dictionary, button_index: int) -> void:
	if button_index == MOUSE_BUTTON_LEFT:
		var owner = data.get("owner", "")
		if owner.is_empty() and map_controller.starting_regions_data.has(pid):
			owner = map_controller.starting_regions_data[pid].get("owner_tag", "")

		if not owner.is_empty() and owner not in ["WST", "WASTE"]:
			select_country(owner, false)


func select_country(tag: String, center_camera: bool = true) -> void:
	selected_tag = tag.to_upper().strip_edges()
	if map_controller != null:
		map_controller.set_focused_country(selected_tag)

	var session = get_node_or_null("/root/GameSession")
	var dossier = session.get_country_dossier(selected_tag) if session != null else {}

	_display_hover_info(selected_tag, dossier)
	country_selected.emit(selected_tag, dossier)

	if center_camera:
		focus_country(selected_tag)


func _display_hover_info(tag: String, d: Dictionary) -> void:
	if lbl_hover_info == null:
		return

	if tag.is_empty() or tag in ["WST", "WASTE", "Neutral"]:
		lbl_hover_info.text = tr("СЕКТОР: НЕЙТРАЛЬНАЯ / ДЕМАРКИРОВАННАЯ ЗОНА // НАВЕДИТЕ КУРСОР НА ДЕРЖАВУ")
		return

	var loc = get_node_or_null("/root/LocalizationManager")
	var c_name = d.get("name", tag)
	if loc != null:
		c_name = loc.tr_key(tag, c_name)

	var leader = d.get("leader_name", "UNKNOWN")
	if loc != null:
		leader = loc.tr_key(leader, leader)

	var has_tree = tags_with_focus.has(tag)
	var focus_badge := ""
	if has_tree:
		var session = get_node_or_null("/root/GameSession")
		var summary = session.get_focus_tree_summary(tag) if session != null else {}
		var total_dirs = summary.get("total_directives", 0)
		var focus_badge_fmt = tr(" | [⚡ ДРЕВО ФОКУСОВ: %d ДИРЕКТИВ]")
		focus_badge = focus_badge_fmt % total_dirs
	else:
		focus_badge = tr(" | [! БЕЗ УНИКАЛЬНОГО ДРЕВА]")

	var info_fmt = tr("[ %s ] %s // ЛИДЕР: %s%s")
	lbl_hover_info.text = info_fmt % [tag, c_name.to_upper(), leader, focus_badge]
