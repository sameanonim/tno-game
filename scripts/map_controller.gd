class_name MapController
extends Sprite2D

##
## MapController for Godot 4: 1960-70s CRT Terminal Grand Strategy Map
## ==============================================================================
## Интегрирует CanvasItem-шейдер (shaders/terminal_map.gdshader), векторный оверлей
## (TacticalOverlay & MapMarkersOverlay) и стратегический игровой ввод:
## 1. СТРАТЕГИЧЕСКИЙ УРОВЕНЬ (MACRO VIEW):
##    - Быстрое O(1) считывание ID провинций из маски в RAM (Image.get_pixelv).
##    - Иерархическая шейдерная система границ (национальные, региональные, тактические).
##    - Волюметрический Inner Falloff (края ячеек светятся +35%, центр затемняется на 35%).
##    - Топографические изогипсы из 8-битной карты высот и неоновые речные барьеры.
##    - Динамические 1D/2D LUT-палитры (lut_palette, data_lut_texture, ownership_lut).
##    - Режимы карты (Map Modes): Политический, Экономический (IC), Недовольство, Сферы.
## 2. ТАКТИЧЕСКИЙ УРОВЕНЬ (TACTICAL THEATER VIEW):
##    - Плавное панорамирование (WASD / стрелки, drag СКМ/ПКМ) и зум к курсору мыши.
##    - Автоматическая трансляция LOD и переключение тактического оверлея.
##    - Векторный тактический оверлей (TacticalOverlay): оперативные стрелы NORAD,
##      псевдографика [████░░░░], шевроны столкновений, кольца тревоги рейдов и восстаний.
## ==============================================================================

const MapManifestLoaderScript = preload("res://core/systems/map/map_manifest_loader.gd")
const MapLUTPipelineScript = preload("res://core/systems/map/map_lut_pipeline.gd")
const MapBorderStylerScript = preload("res://core/systems/map/map_border_styler.gd")
const MapNavigationControllerScript = preload("res://core/systems/map/map_navigation_controller.gd")

enum MapMode {
	POLITICAL = 0,
	ECONOMY = 1,
	UNREST = 2,
	SPHERES = 3
}

signal province_hovered(province_id: int, province_data: Dictionary)
signal province_unhovered(province_id: int)
signal province_clicked(province_id: int, province_data: Dictionary, button_index: int)
signal province_selected(province_id: int, province_data: Dictionary)
signal map_mode_changed(new_mode: int)
signal tactical_view_toggled(is_tactical: bool)
signal map_initialized(total_provinces: int, map_size: Vector2i)
signal territory_transferred(province_id: int, state_id: int, old_owner: String, new_owner: String)

# ==============================================================================
# EXPORT PROPERTIES
# ==============================================================================
@export_group("Map Resources")
@export var mask_texture: Texture2D
@export var heightmap_texture: Texture2D
@export var rivers_texture: Texture2D
@export_file("*.json") var manifest_file_path: String = "res://map_data/map_manifest.json"
@export_file("*.json") var starting_regions_file_path: String = "res://map_data/starting_regions_state.json"
@export_file("*.json") var starting_countries_file_path: String = "res://map_data/starting_countries_state.json"

@export_group("Terminal CRT Aesthetics")
@export var base_phosphor_color: Color = Color(0.20, 1.00, 0.40, 1.0) # #33ff66
@export var national_border_color: Color = Color(0.25, 1.00, 0.45, 0.95)
@export var state_border_color: Color = Color(0.15, 0.70, 0.85, 0.65)
@export var province_border_color: Color = Color(0.18, 0.45, 0.38, 0.35)
@export var coastline_color: Color = Color(0.00, 0.90, 1.00, 0.95)
@export var river_color: Color = Color(0.08, 0.85, 1.00, 0.95)
@export var default_province_color: Color = Color(0.12, 0.14, 0.16, 1.0)
@export var water_color: Color = Color(0.02, 0.05, 0.08, 1.0)

@export_group("Border Hierarchy & Demarcation")
@export var show_national_borders: bool = true
@export var show_state_borders: bool = true
@export var show_province_borders: bool = true
@export var show_coastlines: bool = true
@export var national_border_width: float = 2.2
@export var state_border_width: float = 1.2
@export var province_border_width: float = 0.7
@export var coastline_width: float = 1.8
@export var frontline_border_color: Color = Color(1.0, 0.25, 0.12, 1.0)
@export var border_color_mode: int = 1
@export var enable_inner_border_glow: bool = true
@export var inner_border_glow_width: float = 4.0
@export var inner_border_glow_intensity: float = 0.45
@export var inner_border_glow_tint: Color = Color(0.0, 0.0, 0.0, 0.0)
@export var enable_dashed_state_borders: bool = true
@export var state_border_dash_scale: float = 80.0
@export var state_border_dash_ratio: float = 0.55

@export_group("Country Labels & Typography")
@export var show_country_labels: bool = true
@export var show_state_labels: bool = true
@export var use_russian_country_names: bool = true
@export_file("*.json") var country_labels_file_path: String = "res://map_data/country_labels.json"
@export_file("*.json") var state_labels_file_path: String = "res://map_data/state_labels.json"
@export_file("*.json") var province_features_file_path: String = "res://map_data/province_features.json"

@export_group("Navigation & Camera")
@export var enable_camera_control: bool = true
@export var target_camera: Camera2D
@export var pan_speed: float = 750.0
@export var zoom_speed: float = 0.15
@export var min_zoom: float = 0.35
@export var max_zoom: float = 4.5
@export var tactical_zoom_threshold: float = 1.35

# ==============================================================================
# INTERNAL STATE
# ==============================================================================
var current_map_mode: MapMode = MapMode.POLITICAL
var hovered_province_id: int = 0
var selected_province_id: int = 0
var is_tactical_view_active: bool = false

# Topology & Data
var map_size: Vector2i = Vector2i.ZERO
var max_province_id: int = 0
var mask_image: Image
var manifest_data: Dictionary = {}
var provinces_data: Dictionary = {} # pid -> Dict
var states_data: Dictionary = {}    # sid -> Dict
var province_to_state: Dictionary = {}
var state_to_provinces: Dictionary = {}
var province_centroids: Dictionary = {} # pid -> Vector2
var country_colors: Dictionary = {}     # Tag -> Color
var country_tag_to_id: Dictionary = {}  # Tag -> int
var country_id_to_tag: Dictionary = {}  # int -> Tag
var player_country_tag: String = "KOM"

# Dynamic LUT Textures
const LUT_MAX_WIDTH: int = 4096
var lut_size: Vector2i = Vector2i.ZERO
var lut_image: Image
var lut_texture: ImageTexture
var data_lut_image: Image
var data_lut_texture: ImageTexture
var ownership_lut_image: Image
var ownership_lut_texture: ImageTexture

# Dynamic State Flags & Shaders
var contested_provinces: Dictionary = {}
var dmz_provinces: Dictionary = {}
var battle_intensity: float = 0.0
var enable_rebellion_hatching: bool = true
var enable_political_vignette: bool = true
var focused_country_tag: String = ""
var is_ruler_domain_focus: bool = false
var starting_regions_data: Dictionary = {}
var province_features_data: Dictionary = {}
var country_spheres: Dictionary = {}   # Key: String (tag) -> Value: float (sphere_code)
var country_factions: Dictionary = {}  # Key: String (tag) -> Value: String (faction_name)


# Navigation & Subcomponents
var current_zoom: float = 1.0
var is_dragging: bool = false
var drag_start_pos: Vector2 = Vector2.ZERO
var base_position: Vector2 = Vector2.ZERO
var _shader_mat: ShaderMaterial

var tactical_overlay: TacticalOverlay = null
var map_markers_overlay: MapMarkersOverlay = null
var country_labels_overlay: CountryLabelsOverlay = null


# ==============================================================================
# LIFECYCLE
# ==============================================================================
func _ready() -> void:
	base_position = position
	if scale.x != 1.0 and current_zoom == 1.0:
		current_zoom = scale.x

	if target_camera == null:
		target_camera = get_node_or_null("../Camera2D")
	if target_camera == null and get_viewport() != null:
		target_camera = get_viewport().get_camera_2d()

	_initialize_map()
	_setup_tactical_overlay()
	_update_camera_limits()


func _process(delta: float) -> void:
	if not enable_camera_control:
		return
	MapNavigationControllerScript.process_keyboard_pan(self, delta, pan_speed, base_position, map_size, target_camera)


func _unhandled_input(event: InputEvent) -> void:
	if mask_image == null:
		return

	if enable_camera_control:
		if event is InputEventMouseButton:
			if event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
				if event.is_pressed():
					is_dragging = true
					drag_start_pos = event.position
				else:
					is_dragging = false
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.is_pressed():
				_adjust_zoom(1.0 + zoom_speed, event.position)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.is_pressed():
				_adjust_zoom(1.0 - zoom_speed, event.position)

		elif event is InputEventMouseMotion and is_dragging:
			var delta = event.position - drag_start_pos
			drag_start_pos = event.position
			position += delta
			_clamp_map_position()

	if event is InputEventMouseMotion and not is_dragging:
		_process_mouse_motion()
	elif event is InputEventMouseButton and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
		_process_mouse_click(event.button_index)


# ==============================================================================
# LUT COORDINATE HELPERS
# ==============================================================================
func _calculate_lut_size(total_elements: int) -> Vector2i:
	return MapLUTPipelineScript.calculate_lut_size(total_elements)


func _id_to_lut_coords(id: int) -> Vector2i:
	return MapLUTPipelineScript.id_to_lut_coords(id, lut_size)


# ==============================================================================
# INITIALIZATION & PIPELINE SETUP
# ==============================================================================
func _initialize_map() -> void:
	# 1. Загрузка манифеста провинций
	_load_manifest(manifest_file_path)
	_load_supplementary_data()

	# 2. Подготовка растровой маски в RAM для O(1) чтения
	if mask_texture == null:
		var default_mask_path := "res://map_data/provinces_mask.png"
		if ResourceLoader.exists(default_mask_path):
			mask_texture = load(default_mask_path)
		else:
			push_warning("MapController: mask_texture не назначена!")
			return

	mask_image = mask_texture.get_image()
	if mask_image == null:
		push_error("MapController: Не удалось получить Image из mask_texture!")
		return

	map_size = mask_image.get_size()
	texture = mask_texture

	# 3. Шейдерный материал терминала
	if material is ShaderMaterial:
		_shader_mat = material as ShaderMaterial
	else:
		var terminal_shdr = load("res://shaders/terminal_map.gdshader") as Shader
		if terminal_shdr == null:
			terminal_shdr = load("res://shaders/province_map.gdshader") as Shader
		if terminal_shdr != null:
			_shader_mat = ShaderMaterial.new()
			_shader_mat.shader = terminal_shdr
			material = _shader_mat

	# 4. Создание динамических LUT текстур
	lut_size = _calculate_lut_size(max_province_id + 1)

	# Political LUT
	var pol_res: Dictionary = MapLUTPipelineScript.setup_political_lut(lut_size, provinces_data, country_colors, default_province_color)
	lut_image = pol_res.get("image")
	lut_texture = pol_res.get("texture")

	# Scalar Data LUT (R: IC, G: Unrest, B: Terrain/Infra, A: Sphere)
	var dat_res: Dictionary = MapLUTPipelineScript.setup_data_lut(lut_size, provinces_data, starting_regions_data, country_spheres)
	data_lut_image = dat_res.get("image")
	data_lut_texture = dat_res.get("texture")


	# Ownership & Hierarchy LUT
	_setup_ownership_lut()

	# 5. Геометрические центроиды
	_compute_province_centroids()

	# 6. Настройка текстур и параметров шейдера
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("provinces_mask", mask_texture)
		_shader_mat.set_shader_parameter("lut_palette", lut_texture)
		_shader_mat.set_shader_parameter("data_lut_texture", data_lut_texture)
		_shader_mat.set_shader_parameter("ownership_lut", ownership_lut_texture)
		_shader_mat.set_shader_parameter("map_mode", int(current_map_mode))
		_shader_mat.set_shader_parameter("zoom_level", current_zoom)
		_shader_mat.set_shader_parameter("phosphor_color", Vector3(base_phosphor_color.r, base_phosphor_color.g, base_phosphor_color.b))

		# Карта высот
		if heightmap_texture == null:
			var h_path := "res://map_data/height_map.png"
			if ResourceLoader.exists(h_path):
				heightmap_texture = load(h_path)
		if heightmap_texture != null:
			_shader_mat.set_shader_parameter("height_map", heightmap_texture)

		# Реки
		if rivers_texture == null:
			var r_path := "res://map_data/rivers_mask.png"
			if ResourceLoader.exists(r_path):
				rivers_texture = load(r_path)
		if rivers_texture != null:
			_shader_mat.set_shader_parameter("rivers_mask", rivers_texture)

		_shader_mat.set_shader_parameter("national_border_color", national_border_color)
		_shader_mat.set_shader_parameter("state_border_color", state_border_color)
		_shader_mat.set_shader_parameter("province_border_color", province_border_color)
		_shader_mat.set_shader_parameter("coastline_color", coastline_color)
		_shader_mat.set_shader_parameter("river_color", river_color)

	map_initialized.emit(provinces_data.size(), map_size)


func _setup_tactical_overlay() -> void:
	var origin_offset = -Vector2(map_size) * 0.5 if centered else Vector2.ZERO

	if tactical_overlay == null:
		tactical_overlay = TacticalOverlay.new()
		tactical_overlay.name = "TacticalOverlay"
		add_child(tactical_overlay)
		tactical_overlay.position = origin_offset
		tactical_overlay.set_frontlines([], province_centroids)
		tactical_overlay.set_zoom_level(current_zoom)
		if not tactical_overlay.axis_clicked.is_connected(_on_tactical_axis_clicked):
			tactical_overlay.axis_clicked.connect(_on_tactical_axis_clicked)

	if map_markers_overlay == null:
		map_markers_overlay = MapMarkersOverlay.new()
		map_markers_overlay.name = "MapMarkersOverlay"
		add_child(map_markers_overlay)
		map_markers_overlay.position = origin_offset
		map_markers_overlay.set_zoom_level(current_zoom)
		if not map_markers_overlay.frontline_marker_clicked.is_connected(_on_frontline_marker_clicked):
			map_markers_overlay.frontline_marker_clicked.connect(_on_frontline_marker_clicked)
		if not map_markers_overlay.rebellion_hotspot_clicked.is_connected(_on_rebellion_hotspot_clicked):
			map_markers_overlay.rebellion_hotspot_clicked.connect(_on_rebellion_hotspot_clicked)

	if country_labels_overlay == null:
		country_labels_overlay = CountryLabelsOverlay.new()
		country_labels_overlay.name = "CountryLabelsOverlay"
		add_child(country_labels_overlay)
		country_labels_overlay.position = origin_offset
		country_labels_overlay.set_zoom_level(current_zoom)
		country_labels_overlay.set_labels_visible(show_country_labels)
		country_labels_overlay.set_use_russian(use_russian_country_names)
		country_labels_overlay.set_show_state_names(show_state_labels)
		if country_labels_file_path != "":
			country_labels_overlay.load_labels_manifest(country_labels_file_path)
		if state_labels_file_path != "":
			country_labels_overlay.load_state_labels_manifest(state_labels_file_path)


func _on_tactical_axis_clicked(axis: OperationalAxis) -> void:
	if axis != null and not axis.target_region_ids.is_empty():
		var tid = int(axis.target_region_ids[0])
		focus_on_province(tid)
		if tactical_overlay != null and province_centroids.has(tid):
			tactical_overlay.add_combat_ping(province_centroids[tid], "battle", 3.0, axis.name)


func _on_frontline_marker_clicked(_front: Frontline, axis: OperationalAxis) -> void:
	_on_tactical_axis_clicked(axis)


func _on_rebellion_hotspot_clicked(pid: int, _reg: RegionData) -> void:
	focus_on_province(pid)
	if tactical_overlay != null and province_centroids.has(pid):
		tactical_overlay.add_combat_ping(province_centroids[pid], "danger", 3.0, "ОЧАГ ВОССТАНИЯ")


##
## Фокусировка камеры и плавное центрирование карты на координатах провинции
##
func focus_on_province(province_id: int, smooth: bool = true) -> void:
	if not province_centroids.has(province_id) or map_size == Vector2i.ZERO:
		return
	var centroid: Vector2 = province_centroids[province_id]
	var local_offset = (centroid - Vector2(map_size) * 0.5) if centered else centroid
	var target_pos = base_position - (local_offset * scale.x)
	var scaled_half = (Vector2(map_size) * scale) * 0.5
	var margin := Vector2(300.0, 300.0)
	target_pos.x = clampf(target_pos.x, base_position.x - scaled_half.x - margin.x, base_position.x + scaled_half.x + margin.x)
	target_pos.y = clampf(target_pos.y, base_position.y - scaled_half.y - margin.y, base_position.y + scaled_half.y + margin.y)

	if smooth and is_inside_tree():
		var tw = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "position", target_pos, 0.35)
	else:
		position = target_pos
	_update_camera_limits()


# ==============================================================================
# DYNAMIC LUT UPDATES (MODULE D SPECIFICATION)
# ==============================================================================

##
## Точечное обновление владельца провинции и цвета в ImageTexture без перезагрузки сцены
## Поддерживает передачу как owner_id (int), так и country_tag (String)
##
func update_province_owner(province_id: int, owner_val: Variant, color: Color = Color.TRANSPARENT) -> void:
	if province_id <= 0 or province_id > max_province_id:
		return

	var owner_id: int = 0
	var clean_owner: String = ""
	if owner_val is int:
		owner_id = int(owner_val)
		clean_owner = country_id_to_tag.get(owner_id, "TAG_%d" % owner_id)
	elif owner_val is String:
		clean_owner = str(owner_val).to_upper().strip_edges()
		owner_id = _get_or_register_country_id(clean_owner)

	var col: Color = color
	if col == Color.TRANSPARENT:
		col = country_colors.get(clean_owner, default_province_color)

	var old_owner: String = ""
	if provinces_data.has(province_id):
		old_owner = str(provinces_data[province_id].get("owner", ""))
		provinces_data[province_id]["owner"] = clean_owner

	var coord = _id_to_lut_coords(province_id)

	# 1. Запись байт в политическую палитру
	if lut_image != null:
		lut_image.set_pixel(coord.x, coord.y, col)
		if lut_texture != null:
			lut_texture.update(lut_image)

	# 2. Запись в Ownership-LUT
	if ownership_lut_image != null:
		var state_id = province_to_state.get(province_id, 0)
		if state_id == 0 and provinces_data.has(province_id):
			var raw_sid = provinces_data[province_id].get("state_id", 0)
			if raw_sid != null and (raw_sid is int or raw_sid is float or raw_sid is String):
				state_id = int(raw_sid)
			province_to_state[province_id] = state_id
		var is_frontline = contested_provinces.has(province_id)
		var is_dmz = dmz_provinces.has(province_id)
		var pixel_col = _pack_ownership_pixel(owner_id, state_id, false, is_frontline, is_dmz)
		ownership_lut_image.set_pixel(coord.x, coord.y, pixel_col)
		if ownership_lut_texture != null:
			ownership_lut_texture.update(ownership_lut_image)

	# Обновление владельца в кеше особенностей провинций
	if province_features_data.has(province_id):
		province_features_data[province_id]["owner"] = clean_owner
	if province_features_data.has(str(province_id)):
		province_features_data[str(province_id)]["owner"] = clean_owner

	# 3. Синхронизация сферы влияния в Data-LUT
	var new_owner_tag = country_id_to_tag.get(owner_id, "TAG_%d" % owner_id)
	if data_lut_image != null:
		var sphere_val = _get_sphere_code_for_owner(new_owner_tag)
		var cur_d = data_lut_image.get_pixel(coord.x, coord.y)
		cur_d.a = sphere_val
		data_lut_image.set_pixel(coord.x, coord.y, cur_d)
		if data_lut_texture != null:
			data_lut_texture.update(data_lut_image)

	var sid = province_to_state.get(province_id, 0)
	if sid == 0 and provinces_data.has(province_id):
		var raw_sid2 = provinces_data[province_id].get("state_id", 0)
		if raw_sid2 != null and (raw_sid2 is int or raw_sid2 is float or raw_sid2 is String):
			sid = int(raw_sid2)

	if country_labels_overlay != null:
		country_labels_overlay.on_territory_transferred(province_id, sid, old_owner, clean_owner)

	territory_transferred.emit(province_id, sid, old_owner, new_owner_tag)


##
## Обновление скалярных параметров региона (IC, Unrest, Infra, Sphere)
##
func update_region_scalar_data(region_id: int, value: float, channel: int = 0) -> void:
	if data_lut_image == null or region_id <= 0 or region_id > max_province_id:
		return

	var coord = _id_to_lut_coords(region_id)
	var col = data_lut_image.get_pixel(coord.x, coord.y)
	match channel:
		0: col.r = clampf(value, 0.0, 1.0) # IC
		1: col.g = clampf(value, 0.0, 1.0) # Unrest
		2: col.b = clampf(value, 0.0, 1.0) # Terrain / Infrastructure
		3: col.a = clampf(value, 0.0, 1.0) # Sphere code

	data_lut_image.set_pixel(coord.x, coord.y, col)
	if data_lut_texture != null:
		data_lut_texture.update(data_lut_image)


##
## Переключение режима карты (Политический, Экономика, Недовольство, Сферы)
##
func set_map_mode(mode: int) -> void:
	current_map_mode = clampi(mode, 0, 3) as MapMode
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("map_mode", int(current_map_mode))
	map_mode_changed.emit(int(current_map_mode))


##
## Установка цвета провинции напрямую
##
func set_province_color(province_id: int, color: Color) -> void:
	if lut_image == null or province_id <= 0 or province_id > max_province_id:
		return
	var coord = _id_to_lut_coords(province_id)
	lut_image.set_pixel(coord.x, coord.y, color)
	if lut_texture != null:
		lut_texture.update(lut_image)


# ==============================================================================
# ШЕЙДЕРНЫЕ ПАРАМЕТРЫ (VIGNETTE, STROBE, HATCHING)
# ==============================================================================

func set_political_vignette(enabled: bool, falloff: float = 0.35, glow_boost: float = 1.35) -> void:
	enable_political_vignette = enabled
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("enable_political_vignette", enabled)
		_shader_mat.set_shader_parameter("enable_inner_falloff", enabled)
		_shader_mat.set_shader_parameter("inner_falloff_dim", falloff)
		_shader_mat.set_shader_parameter("border_glow_boost", glow_boost)


func set_battle_intensity(intensity: float) -> void:
	battle_intensity = clampf(intensity, 0.0, 1.0)
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("battle_intensity", battle_intensity)


func set_rebellion_hatching_enabled(enabled: bool) -> void:
	enable_rebellion_hatching = enabled
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("enable_rebellion_hatching", enabled)


# ==============================================================================
# ВОЕННЫЙ МОДУЛЬ И ВЕКТОРНЫЙ ОВЕРЛЕЙ
# ==============================================================================

func sync_military_fronts(frontlines: Array[Frontline]) -> void:
	contested_provinces.clear()
	var active_count := 0
	var max_tension := 0.0

	for f in frontlines:
		if f != null and f.active:
			active_count += 1
			max_tension = maxf(max_tension, f.tension)
			for ax in f.axes:
				if ax != null:
					for tid in ax.target_region_ids:
						contested_provinces[int(tid)] = true

	if active_count > 0:
		set_battle_intensity(clampf((float(active_count) * 0.20) + (max_tension / 100.0) * 0.60, 0.25, 1.0))
	else:
		set_battle_intensity(0.0)

	_refresh_ownership_lut_frontlines()

	if tactical_overlay != null:
		tactical_overlay.set_frontlines(frontlines, province_centroids)
	if map_markers_overlay != null:
		map_markers_overlay.sync_frontlines(frontlines, province_centroids)


func update_rebellion_hotspots(regions: Dictionary, player_tag: String = "") -> void:
	for pid in regions.keys():
		var reg = regions[pid]
		if reg != null and pid > 0 and pid <= max_province_id:
			var unrest_norm := 0.0
			var ic_norm := 0.0
			var infra_norm := 0.0
			var owner_tag := ""

			if reg is RegionData:
				unrest_norm = clampf(reg.unrest / 100.0, 0.0, 1.0)
				ic_norm = clampf(float(reg.industrial_capacity) / 10.0, 0.0, 1.0)
				infra_norm = clampf(float(reg.civilian_infrastructure) / 10.0, 0.0, 1.0)
				owner_tag = reg.owner_tag
			elif reg is Dictionary:
				unrest_norm = clampf(float(reg.get("unrest", 0.0)) / 100.0, 0.0, 1.0)
				ic_norm = clampf(float(reg.get("industrial_capacity", 0)) / 10.0, 0.0, 1.0)
				infra_norm = clampf(float(reg.get("civilian_infrastructure", 0)) / 10.0, 0.0, 1.0)
				owner_tag = str(reg.get("owner_tag", reg.get("owner", "")))

			if owner_tag.is_empty() and provinces_data.has(pid):
				owner_tag = str(provinces_data[pid].get("owner", ""))

			var sphere_val = _get_sphere_code_for_owner(owner_tag, player_tag)

			var coord = _id_to_lut_coords(pid)
			var old_col = data_lut_image.get_pixel(coord.x, coord.y)
			old_col.r = ic_norm
			old_col.g = unrest_norm
			old_col.b = infra_norm
			old_col.a = sphere_val
			data_lut_image.set_pixel(coord.x, coord.y, old_col)

	if data_lut_texture != null and data_lut_image != null:
		data_lut_texture.update(data_lut_image)

	if tactical_overlay != null:
		tactical_overlay.sync_rebellions(regions, province_centroids)
	if map_markers_overlay != null:
		map_markers_overlay.sync_rebellions(regions, province_centroids)


func _get_sphere_code_for_owner(owner_tag: String, _player_tag: String = "") -> float:
	return MapLUTPipelineScript.get_sphere_code_for_owner(owner_tag, country_spheres)



func add_combat_incident_ping(province_id: int, ping_type: String = "battle") -> void:
	if tactical_overlay != null and province_centroids.has(province_id):
		tactical_overlay.add_combat_ping(province_centroids[province_id], ping_type)


func add_raid_corridor(from_province_id: int, to_province_id: int, intensity: String = "recon") -> void:
	if tactical_overlay != null and province_centroids.has(from_province_id) and province_centroids.has(to_province_id):
		tactical_overlay.add_raid_corridor(province_centroids[from_province_id], province_centroids[to_province_id], intensity)


# ==============================================================================
# ФОКУСИРОВКА НАЦИЙ, ТАКТИЧЕСКИЙ РАДАР И ТРАНСФЕР ШТАТОВ
# ==============================================================================

##
## Выбор и подсветка конкретного государства на карте
##
func set_focused_country(tag: String) -> void:
	focused_country_tag = tag.to_upper().strip_edges()
	if _shader_mat != null:
		var c_id = country_tag_to_id.get(focused_country_tag, 0)
		_shader_mat.set_shader_parameter("selected_country_id", c_id)
		_shader_mat.set_shader_parameter("focused_country_id", c_id)


##
## Переключение режима изоляции/подсветки домена правителя (Ruler Domain)
##
func toggle_ruler_domain_focus() -> void:
	is_ruler_domain_focus = not is_ruler_domain_focus
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("is_ruler_domain_focus", is_ruler_domain_focus)


##
## Возвращает центроид провинции в координатах текстуры карты
##
func get_province_centroid(province_id: int) -> Vector2:
	return province_centroids.get(province_id, Vector2.ZERO)


##
## Регистрация или получение числового ID государства (1..255)
##
func _get_or_register_country_id(tag: String) -> int:
	var clean = tag.to_upper().strip_edges()
	if clean.is_empty():
		return 0
	if country_tag_to_id.has(clean):
		return country_tag_to_id[clean]
	var next_id = country_tag_to_id.size() + 1
	country_tag_to_id[clean] = next_id
	country_id_to_tag[next_id] = clean
	return next_id


##
## Установка флага оспариваемых / фронтовых провинций
##
func set_contested_provinces(province_ids: Array, is_contested: bool) -> void:
	MapLUTPipelineScript.update_contested_provinces(
		ownership_lut_image,
		ownership_lut_texture,
		lut_size,
		province_ids,
		is_contested,
		contested_provinces
	)


##
## Установка статуса демилитаризованной зоны (DMZ) для конкретной провинции
##
func set_province_dmz(province_id: int, is_dmz: bool) -> void:
	MapLUTPipelineScript.update_dmz_provinces(
		ownership_lut_image,
		ownership_lut_texture,
		lut_size,
		[province_id],
		is_dmz,
		dmz_provinces
	)


##
## Установка статуса демилитаризованной зоны (DMZ) для целого штата
##
func set_state_dmz(state_id: int, is_dmz: bool) -> void:
	var provs = state_to_provinces.get(state_id, [])
	MapLUTPipelineScript.update_dmz_provinces(
		ownership_lut_image,
		ownership_lut_texture,
		lut_size,
		provs,
		is_dmz,
		dmz_provinces
	)


##
## Динамическая адаптация шейдера карты к уровню международной напряженности DEFCON
##
func update_defcon_visuals(defcon_level: int) -> void:
	MapBorderStylerScript.apply_defcon_visuals(_shader_mat, defcon_level)


##
## Управление видимостью иерархических границ
##
func set_border_visibility(show_nat: bool, show_st: bool, show_prov: bool, show_coast: bool) -> void:
	show_national_borders = show_nat
	show_state_borders = show_st
	show_province_borders = show_prov
	show_coastlines = show_coast
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("show_national_borders", show_nat)
		_shader_mat.set_shader_parameter("show_state_borders", show_st)
		_shader_mat.set_shader_parameter("show_province_borders", show_prov)
		_shader_mat.set_shader_parameter("show_coastlines", show_coast)


##
## Настройка толщины иерархических границ
##
func set_border_widths(nat: float, st: float, prov: float, coast: float) -> void:
	national_border_width = nat
	state_border_width = st
	province_border_width = prov
	coastline_width = coast
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("national_border_width", nat)
		_shader_mat.set_shader_parameter("state_border_width", st)
		_shader_mat.set_shader_parameter("province_border_width", prov)
		_shader_mat.set_shader_parameter("coastline_width", coast)


##
## Цветовая палитра и неоновое свечение границ
##
func set_border_colors(nat: Color, st: Color, prov: Color, coast: Color, front: Color = Color.TRANSPARENT) -> void:
	national_border_color = nat
	state_border_color = st
	province_border_color = prov
	coastline_color = coast
	if front != Color.TRANSPARENT:
		frontline_border_color = front
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("national_border_color", nat)
		_shader_mat.set_shader_parameter("state_border_color", st)
		_shader_mat.set_shader_parameter("province_border_color", prov)
		_shader_mat.set_shader_parameter("coastline_color", coast)
		if front != Color.TRANSPARENT:
			_shader_mat.set_shader_parameter("frontline_border_color", front)


##
## Режим стилизации границ (0: Classic Phosphor, 1: Dual-Hue Ribbon, 2: High-Contrast Dark-Core)
##
func set_border_color_mode(mode: int) -> void:
	border_color_mode = mode
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("border_color_mode", mode)


##
## Внутренний ореол границ (Inner Territorial Glow)
##
func set_inner_border_glow(enabled: bool, width: float, intensity: float, tint: Color = Color.TRANSPARENT) -> void:
	enable_inner_border_glow = enabled
	inner_border_glow_width = width
	inner_border_glow_intensity = intensity
	inner_border_glow_tint = tint
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("enable_inner_border_glow", enabled)
		_shader_mat.set_shader_parameter("inner_border_glow_width", width)
		_shader_mat.set_shader_parameter("inner_border_glow_intensity", intensity)
		_shader_mat.set_shader_parameter("inner_border_glow_tint", tint)


##
## Пунктирные границы внутренних регионов/штатов
##
func set_dashed_state_borders(enabled: bool, scale: float, ratio: float = 0.55) -> void:
	enable_dashed_state_borders = enabled
	state_border_dash_scale = scale
	state_border_dash_ratio = ratio
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("enable_dashed_state_borders", enabled)
		_shader_mat.set_shader_parameter("state_border_dash_scale", scale)
		_shader_mat.set_shader_parameter("state_border_dash_ratio", ratio)


##
## Выбор провинции и синхронизация фокуса суверенитета
##
func select_province(province_id: int) -> void:
	selected_province_id = province_id
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("selected_province_id", province_id)
	if province_id > 0:
		var p_data = provinces_data.get(province_id, {})
		var owner_tag = p_data.get("owner", "")
		if owner_tag.is_empty() and starting_regions_data.has(province_id):
			owner_tag = starting_regions_data[province_id].get("owner_tag", "")
		set_focused_country(owner_tag)
	else:
		set_focused_country("")


##
## Синхронизирует параметры масштаба и границ с шейдерным материалом
##
func _sync_border_uniforms_to_shader() -> void:
	MapBorderStylerScript.sync_border_uniforms(_shader_mat, self)


##
## Заполнение скалярных данных регионов (IC, Unrest, Infra) в Data-LUT
##
func populate_data_lut_from_regions(regions: Dictionary, player_tag: String = "") -> void:
	update_rebellion_hotspots(regions, player_tag)


##
## Перерисовка тактических фронтов
##
func refresh_tactical_frontlines() -> void:
	sync_military_fronts(MilitaryEngine.get_active_frontlines())


##
## Полная передача контроля над штатом и входящими провинциями новому владельцу
##
func transfer_state_ownership(state_id: int, new_owner: String, new_color: Color = Color.TRANSPARENT) -> void:
	var clean_owner = new_owner.to_upper().strip_edges()
	var owner_id = _get_or_register_country_id(clean_owner)
	var col = new_color if new_color != Color.TRANSPARENT else country_colors.get(clean_owner, default_province_color)
	var provs = state_to_provinces.get(state_id, [])
	for pid in provs:
		update_province_owner(int(pid), owner_id, col)


##
## Установка владельца для штата (алиас transfer_state_ownership для совместимости)
##
func set_state_owner(state_id: int, new_owner: String, new_color: Color = Color.TRANSPARENT) -> void:
	transfer_state_ownership(state_id, new_owner, new_color)


##
## Установка владельца для конкретной провинции
##
func set_province_owner(province_id: int, new_owner_tag: String, new_color: Color = Color.TRANSPARENT) -> void:
	var clean_owner = new_owner_tag.to_upper().strip_edges()
	var owner_id = _get_or_register_country_id(clean_owner)
	var col = new_color if new_color != Color.TRANSPARENT else country_colors.get(clean_owner, default_province_color)
	update_province_owner(province_id, owner_id, col)


##
## Управление видимостью меток государств на карте
##
func set_country_labels_visible(visible_state: bool) -> void:
	show_country_labels = visible_state
	if country_labels_overlay != null:
		country_labels_overlay.set_labels_visible(visible_state)


##
## Переключение языка отображения названий государств (Русский / Английский)
##
func set_country_labels_language(use_russian: bool) -> void:
	use_russian_country_names = use_russian
	if country_labels_overlay != null:
		country_labels_overlay.set_use_russian(use_russian)


##
## Управление видимостью тактических меток штатов/регионов
##
func set_state_labels_visible(visible_state: bool) -> void:
	show_state_labels = visible_state
	if country_labels_overlay != null:
		country_labels_overlay.set_show_state_names(visible_state)


##
## Переключение видимости тактических меток штатов
##
func toggle_state_labels() -> bool:
	set_state_labels_visible(not show_state_labels)
	return show_state_labels


##
## Возвращает тактические и географические особенности провинции
##
func get_province_features(province_id: int) -> Dictionary:
	if province_features_data.has(province_id):
		return province_features_data[province_id]
	if province_features_data.has(str(province_id)):
		return province_features_data[str(province_id)]

	var p_data = provinces_data.get(province_id, {})
	var r_data = starting_regions_data.get(province_id, {})
	var sid = province_to_state.get(province_id, int(p_data.get("state_id", 0)))
	var s_info = states_data.get(sid, {})
	var st_name = s_info.get("name", "Регион %d" % sid)
	var owner_tag = str(p_data.get("owner", r_data.get("owner_tag", "")))
	if owner_tag.is_empty():
		owner_tag = s_info.get("owner", "Neutral")

	var feat = {
		"id": province_id,
		"state_id": sid,
		"state_name": st_name,
		"name": p_data.get("name", "Сектор #%d" % province_id),
		"owner": owner_tag,
		"terrain": p_data.get("terrain", r_data.get("terrain_type", "plains")),
		"terrain_name_ru": "Равнины",
		"population": r_data.get("population", 50000),
		"ic": r_data.get("industrial_capacity", 1),
		"infrastructure": r_data.get("civilian_infrastructure", 1),
		"unrest": r_data.get("unrest", 0.0),
		"is_coastal": p_data.get("coastal", false)
	}
	province_features_data[province_id] = feat
	province_features_data[str(province_id)] = feat
	return feat


##
## Установка точки фокуса и подсветки радара театра
##
func set_active_theater_radar(pos: Vector2, _radius: float = 0.22) -> void:
	if tactical_overlay != null:
		tactical_overlay.add_combat_ping(pos, "radar")


# ==============================================================================
# НАВИГАЦИЯ, ЗУМ И ГРАНИЦЫ КАМЕРЫ
# ==============================================================================

func _adjust_zoom(factor: float, pivot_screen_pos: Vector2) -> void:
	var old_zoom = current_zoom
	current_zoom = MapNavigationControllerScript.adjust_zoom(
		self, current_zoom, factor, min_zoom, max_zoom, pivot_screen_pos, base_position, map_size, target_camera
	)
	if is_equal_approx(old_zoom, current_zoom):
		return

	if _shader_mat != null:
		_shader_mat.set_shader_parameter("zoom_level", current_zoom)

	if tactical_overlay != null:
		tactical_overlay.set_zoom_level(current_zoom)
	if map_markers_overlay != null:
		map_markers_overlay.set_zoom_level(current_zoom)
	if country_labels_overlay != null:
		country_labels_overlay.set_zoom_level(current_zoom)

	var should_be_tactical = (current_zoom >= tactical_zoom_threshold)
	if should_be_tactical != is_tactical_view_active:
		is_tactical_view_active = should_be_tactical
		if tactical_overlay != null:
			tactical_overlay.set_tactical_view_active(is_tactical_view_active)
		if map_markers_overlay != null:
			map_markers_overlay.set_tactical_view_active(is_tactical_view_active)
		tactical_view_toggled.emit(is_tactical_view_active)


##
## Принудительное включение/выключение тактического оверлея ТВД
##
func set_tactical_view_active(active: bool) -> void:
	is_tactical_view_active = active
	if tactical_overlay != null:
		tactical_overlay.set_tactical_view_active(active)
	if map_markers_overlay != null:
		map_markers_overlay.set_tactical_view_active(active)
	tactical_view_toggled.emit(active)


##
## Переключение тактического оверлея ТВД
##
func toggle_tactical_view() -> bool:
	set_tactical_view_active(not is_tactical_view_active)
	return is_tactical_view_active


func _clamp_map_position() -> void:
	MapNavigationControllerScript.clamp_map_position(self, base_position, map_size, target_camera)


func _update_camera_limits() -> void:
	MapNavigationControllerScript.update_camera_limits(self, base_position, map_size, target_camera)


# ==============================================================================
# ОБРАБОТКА ВВОДА И СЧИТЫВАНИЕ МАСКИ (RAM O(1))
# ==============================================================================

func _process_mouse_motion() -> void:
	var prov_id = get_province_id_under_cursor()
	if prov_id != hovered_province_id:
		var prev = hovered_province_id
		hovered_province_id = prov_id
		if _shader_mat != null:
			_shader_mat.set_shader_parameter("hovered_province_id", prov_id)
		if prev > 0:
			province_unhovered.emit(prev)
		if prov_id > 0:
			province_hovered.emit(prov_id, get_province_data(prov_id))


func _process_mouse_click(button_index: int) -> void:
	var prov_id = get_province_id_under_cursor()
	if prov_id > 0:
		var p_data = get_province_data(prov_id)
		selected_province_id = prov_id
		if _shader_mat != null:
			_shader_mat.set_shader_parameter("selected_province_id", prov_id)
		province_clicked.emit(prov_id, p_data, button_index)
		province_selected.emit(prov_id, p_data)


func get_province_id_under_cursor() -> int:
	var global_mouse = get_global_mouse_position()
	var local_pos = to_local(global_mouse)
	var pixel_pos = local_pos + (Vector2(map_size) * 0.5) if centered else local_pos
	var pixel = Vector2i(int(floor(pixel_pos.x)), int(floor(pixel_pos.y)))
	return get_province_id_at_pixel(pixel)


func get_province_id_at_pixel(pixel: Vector2i) -> int:
	return MapLUTPipelineScript.get_province_id_at_pixel(mask_image, map_size, pixel, provinces_data)


func _sample_raw_pixel_id(pos: Vector2i) -> int:
	return MapLUTPipelineScript.sample_raw_pixel_id(mask_image, pos)


##
## Безопасное извлечение метаданных провинции без риска генерации фантомных объектов
##
func get_province_data(province_id: int) -> Dictionary:
	if province_id <= 0 or not provinces_data.has(province_id):
		return {}
	return provinces_data[province_id]


# ==============================================================================
# ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ИНИЦИАЛИЗАЦИИ
# ==============================================================================

func _setup_ownership_lut() -> void:
	var result: Dictionary = MapLUTPipelineScript.setup_ownership_lut(
		lut_size,
		max_province_id,
		provinces_data,
		country_tag_to_id,
		province_to_state,
		contested_provinces,
		dmz_provinces
	)
	ownership_lut_image = result.get("image")
	ownership_lut_texture = result.get("texture")


func _refresh_ownership_lut_frontlines() -> void:
	MapLUTPipelineScript.refresh_ownership_lut_frontlines(
		ownership_lut_image,
		ownership_lut_texture,
		lut_size,
		max_province_id,
		provinces_data,
		country_tag_to_id,
		province_to_state,
		contested_provinces,
		dmz_provinces
	)


func _pack_ownership_pixel(owner_id: int, state_id: int, is_water: bool, is_frontline: bool = false, is_dmz: bool = false) -> Color:
	return MapLUTPipelineScript.pack_ownership_pixel(owner_id, state_id, is_water, is_frontline, is_dmz)


func _resolve_initial_province_color(pid: int) -> Color:
	var p_data = provinces_data.get(pid, {})
	var owner = p_data.get("owner", "")
	if country_colors.has(owner):
		return country_colors[owner]
	if p_data.get("type", "") in ["sea", "lake", "ocean"]:
		return water_color
	return default_province_color


func _compute_province_centroids() -> void:
	province_centroids = MapManifestLoaderScript.compute_province_centroids(provinces_data, mask_image, map_size, Callable(self, "get_province_id_at_pixel"))


func _load_manifest(path: String) -> void:
	var res = MapManifestLoaderScript.load_manifest(path)
	manifest_data = res.manifest_data
	max_province_id = res.max_province_id
	states_data = res.states_data
	provinces_data = res.provinces_data
	province_to_state = res.province_to_state
	state_to_provinces = res.state_to_provinces


func _load_supplementary_data() -> void:
	var res = MapManifestLoaderScript.load_supplementary_data(
		starting_countries_file_path,
		starting_regions_file_path,
		province_features_file_path,
		provinces_data,
		states_data,
		province_to_state,
		state_to_provinces
	)
	country_tag_to_id = res.country_tag_to_id
	country_id_to_tag = res.country_id_to_tag
	country_colors = res.country_colors
	country_spheres = res.country_spheres
	country_factions = res.country_factions
	starting_regions_data = res.starting_regions_data
	province_features_data = res.province_features_data
