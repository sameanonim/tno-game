class_name LeaderPortraitFrame
extends Control

##
## LeaderPortraitFrame: Стилизованная рамка фотопортрета лидера TNO
##
## Обеспечивает:
## 1. Загрузку и кэширование текстур лидеров (DDS/PNG) без фризов UI.
## 2. Процедурную генерацию fallback-силуэта «ЛИЧНОСТЬ ЗАСЕКРЕЧЕНА».
## 3. Шейдерную стилизацию: монохромный люминофор, дизеринг Bayer 4x4, сканлайны.
## 4. Анимацию построчной распечатки телетайпа (Print Progress) и CRT-помех.
## 5. Обработку состояний (NORMAL, HOVER, SELECTED, DISABLED).
##

signal portrait_clicked()

enum FrameMode {
	THUMBNAIL, # Компактная карточка (72x92)
	DOSSIER    # Большое досье режима (156x210)
}

const PORTRAIT_SHADER = preload("res://shaders/leader_portrait.gdshader")
const FALLBACK_ICON = preload("res://icon.svg")

# Статический кэш текстур в памяти для исключения повторных чтений с диска
static var _texture_cache: Dictionary = {}
static var _classified_texture: ImageTexture = null

# Цвета люминофора по идеологиям
const PHOSPHOR_CYAN   = Color(0.1, 0.9, 1.0)    # Демократия / Свободный мир
const PHOSPHOR_GREEN  = Color(0.25, 0.95, 0.5)  # Социализм / Советский канон
const PHOSPHOR_AMBER  = Color(1.0, 0.72, 0.15)  # Деспотизм / Авторитаризм
const PHOSPHOR_RED    = Color(0.95, 0.28, 0.22)  # Фашизм / Бургундская система
const PHOSPHOR_OLIVE  = Color(0.65, 0.85, 0.45)  # Военная хунта / Варлорды

@export var mode: FrameMode = FrameMode.DOSSIER:
	set(val):
		mode = val
		_apply_mode_dimensions()

@export var show_border: bool = true
@export var is_interactive: bool = true

@onready var texture_rect: TextureRect = $PortraitRect
@onready var border_rect: ReferenceRect = get_node_or_null("BorderRect")
@onready var ascii_tag_label: Label = get_node_or_null("AsciiTagLabel")
@onready var status_badge: Label = get_node_or_null("StatusBadge")

var _shader_mat: ShaderMaterial = null
var _current_tween: Tween = null
var _is_selected: bool = false
var _is_hovered: bool = false
var _is_disabled: bool = false
var _current_leader_id: String = ""


func _ready() -> void:
	_setup_shader()
	_apply_mode_dimensions()
	if is_interactive:
		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)
		gui_input.connect(_on_gui_input)


func _setup_shader() -> void:
	if texture_rect != null:
		if texture_rect.material is ShaderMaterial:
			_shader_mat = (texture_rect.material as ShaderMaterial).duplicate()
		else:
			_shader_mat = ShaderMaterial.new()
			_shader_mat.shader = PORTRAIT_SHADER
		texture_rect.material = _shader_mat
		_shader_mat.set_shader_parameter("phosphor_color", PHOSPHOR_GREEN)
		_shader_mat.set_shader_parameter("print_progress", 1.0)
		_shader_mat.set_shader_parameter("glitch_amount", 0.0)


func _apply_mode_dimensions() -> void:
	if mode == FrameMode.THUMBNAIL:
		custom_minimum_size = Vector2(72, 92)
		if texture_rect != null:
			texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		if _shader_mat != null:
			_shader_mat.set_shader_parameter("scanline_density", 90.0)
			_shader_mat.set_shader_parameter("dither_scale", 1.5)
	else:
		custom_minimum_size = Vector2(156, 210)
		if texture_rect != null:
			texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		if _shader_mat != null:
			_shader_mat.set_shader_parameter("scanline_density", 180.0)
			_shader_mat.set_shader_parameter("dither_scale", 2.0)


# ==============================================================================
# ПУБЛИЧНЫЙ API ОТОБРАЖЕНИЯ ЛИДЕРА
# ==============================================================================

func display_leader(leader_data: Variant, country_tag: String = "", animate_teletype: bool = true) -> void:
	var l_id = ""
	var l_name = ""
	var l_portrait_path = ""
	var l_ideology = ""
	var direct_texture: Texture2D = null

	if leader_data is LeaderResource:
		var res = leader_data as LeaderResource
		l_id = res.leader_id
		l_name = res.leader_name
		l_portrait_path = res.portrait_path
		l_ideology = res.ideology
		if "portrait" in res and res.get("portrait") is Texture2D and res.get("portrait") != null:
			direct_texture = res.get("portrait")
	elif leader_data is Dictionary:
		var d = leader_data as Dictionary
		l_id = str(d.get("leader_id", d.get("tag", "")))
		l_name = str(d.get("leader_name", d.get("name", "UNKNOWN")))
		l_portrait_path = str(d.get("portrait_path", ""))
		l_ideology = str(d.get("ideology", d.get("sub_ideology", "")))
		if d.get("portrait") is Texture2D:
			direct_texture = d.get("portrait")
	elif leader_data is CountryState:
		var cs = leader_data as CountryState
		l_id = cs.leader_portrait_id if not cs.leader_portrait_id.is_empty() else cs.country_tag
		l_name = cs.leader_name
		l_portrait_path = cs.leader_portrait_path
		l_ideology = cs.ruling_party if not cs.ruling_party.is_empty() else cs.ruling_ideology
		if cs.head_of_state != null:
			if not cs.head_of_state.leader_name.is_empty():
				l_name = cs.head_of_state.leader_name
			if not cs.head_of_state.portrait_path.is_empty() and cs.head_of_state.portrait_path != "res://icon.svg":
				l_portrait_path = cs.head_of_state.portrait_path
			if cs.head_of_state.portrait != null:
				direct_texture = cs.head_of_state.portrait
	else:
		_set_classified_state()
		return

	_current_leader_id = l_id

	# Настройка цвета люминофора по идеологии
	var tint = _get_ideology_phosphor_color(l_ideology)
	set_phosphor_color(tint)

	# Загрузка и кэширование текстуры
	var tex = direct_texture
	if tex == null:
		tex = _resolve_portrait_texture(l_portrait_path, country_tag, l_name)

	if tex != null:
		texture_rect.texture = tex
		if _shader_mat != null:
			_shader_mat.set_shader_parameter("is_classified", false)
	else:
		_set_classified_state()

	# Обновление бейджей
	if ascii_tag_label != null:
		ascii_tag_label.text = "[%s]" % (country_tag if not country_tag.is_empty() else "TNO")
	if status_badge != null:
		status_badge.text = "SECRET" if tex == null else "IDENTIFIED"

	# Анимация распечатки телетайпа
	if animate_teletype:
		play_teletype_scan(0.4)


func set_phosphor_color(color: Color) -> void:
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("phosphor_color", color)


func set_selected(selected: bool) -> void:
	_is_selected = selected
	_update_frame_visuals()


func set_hovered(hovered: bool) -> void:
	_is_hovered = hovered
	_update_frame_visuals()


func set_disabled(disabled: bool) -> void:
	_is_disabled = disabled
	mouse_filter = Control.MOUSE_FILTER_IGNORE if disabled else (Control.MOUSE_FILTER_STOP if is_interactive else Control.MOUSE_FILTER_PASS)
	_update_frame_visuals()


# ==============================================================================
# АНИМАЦИИ ТЕЛЕТАЙПА И CRT-ГЛИТЧА
# ==============================================================================

func play_teletype_scan(duration: float = 0.45) -> void:
	if _shader_mat == null:
		return

	if _current_tween != null and _current_tween.is_valid():
		_current_tween.kill()

	_shader_mat.set_shader_parameter("print_progress", 0.0)
	_shader_mat.set_shader_parameter("glitch_amount", 0.35)

	_current_tween = create_tween().set_parallel(true)
	# Развертка сверху вниз
	_current_tween.tween_method(func(val: float):
		if _shader_mat != null:
			_shader_mat.set_shader_parameter("print_progress", val)
	, 0.0, 1.0, duration).set_trans(Tween.TRANS_LINEAR)

	# Затухание помех каретки
	_current_tween.tween_method(func(val: float):
		if _shader_mat != null:
			_shader_mat.set_shader_parameter("glitch_amount", val)
	, 0.35, 0.0, duration * 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func play_glitch_burst(intensity: float = 0.25, duration: float = 0.2) -> void:
	if _shader_mat == null:
		return
	var tw = create_tween()
	tw.tween_method(func(v: float):
		if _shader_mat != null:
			_shader_mat.set_shader_parameter("glitch_amount", v)
	, intensity, 0.0, duration).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


# ==============================================================================
# ПОИСК, ЗАГРУЗКА И КЭШИРОВАНИЕ ТЕКСТУР
# ==============================================================================

func _resolve_portrait_texture(path: String, tag: String, leader_name: String) -> Texture2D:
	var cache_key = "%s_%s_%s" % [tag, leader_name, path]
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]

	var loaded_tex: Texture2D = null

	# 1. Прямой путь, если указан корректный ресурс
	if not path.is_empty() and path != "res://icon.svg":
		loaded_tex = _load_portrait_file(path)

	# 2. Поиск в каталоге ui/assets/portraits/
	if loaded_tex == null:
		loaded_tex = _find_in_portraits_directory(tag, leader_name)

	# 3. Сохранение в кэш
	if loaded_tex != null:
		_texture_cache[cache_key] = loaded_tex
		return loaded_tex

	return null


func _load_portrait_file(p_path: String) -> Texture2D:
	if ResourceLoader.exists(p_path):
		return load(p_path) as Texture2D
	elif FileAccess.file_exists(p_path):
		var img = Image.load_from_file(p_path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


func _find_in_portraits_directory(tag: String, leader_name: String) -> Texture2D:
	var search_dir = "res://ui/assets/portraits"
	if not DirAccess.dir_exists_absolute(search_dir):
		return null

	var clean_name = leader_name.replace(" ", "_").replace(".", "").to_lower()
	var tag_lower = tag.to_lower()

	# Кандидаты имен файлов
	var potential_names = [
		"Portrait_%s_%s.png" % [tag, leader_name.replace(" ", "_")],
		"Portrait_%s_%s.png" % [tag.to_upper(), leader_name.replace(" ", "_")],
		"%s_%s.png" % [tag, leader_name.replace(" ", "_")],
		"%s.png" % leader_name.replace(" ", "_"),
		"Portrait_%s.png" % leader_name.replace(" ", "_")
	]

	for p_name in potential_names:
		var full_p = search_dir.path_join(p_name)
		var tex = _load_portrait_file(full_p)
		if tex != null:
			return tex

	# Быстрый перебор по совпадению подстроки
	var dir = DirAccess.open(search_dir)
	if dir != null:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		var count = 0
		while not file_name.is_empty() and count < 250:
			count += 1
			if not dir.current_is_dir() and file_name.ends_with(".png"):
				var fn_low = file_name.to_lower()
				if not clean_name.is_empty() and clean_name in fn_low:
					var full_p = search_dir.path_join(file_name)
					var tex = _load_portrait_file(full_p)
					if tex != null:
						dir.list_dir_end()
						return tex
				elif not tag_lower.is_empty() and ("portrait_" + tag_lower) in fn_low:
					var full_p = search_dir.path_join(file_name)
					var tex = _load_portrait_file(full_p)
					if tex != null:
						dir.list_dir_end()
						return tex
			file_name = dir.get_next()
		dir.list_dir_end()

	return null


func _set_classified_state() -> void:
	if _classified_texture == null:
		_classified_texture = _generate_classified_placeholder()

	if texture_rect != null:
		texture_rect.texture = _classified_texture
		if _shader_mat != null:
			_shader_mat.set_shader_parameter("is_classified", true)
			_shader_mat.set_shader_parameter("phosphor_color", Color(0.75, 0.7, 0.4))

	if status_badge != null:
		status_badge.text = "[CLASSIFIED]"


func _generate_classified_placeholder() -> ImageTexture:
	var w = 156
	var h = 210
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.04, 0.06, 0.05, 1.0))

	# Рисование процедурного контура засекреченного досье
	for y in range(h):
		for x in range(w):
			var uv_x = float(x) / float(w)
			var uv_y = float(y) / float(h)
			# Силуэт головы и плеч
			var head_dist = Vector2(uv_x - 0.5, (uv_y - 0.38) * 1.3).length()
			var shoulder_dist = Vector2((uv_x - 0.5) * 0.7, (uv_y - 0.85) * 1.8).length()
			if head_dist < 0.22 or shoulder_dist < 0.45:
				var shade = 0.45 + (sin(float(x * 4 + y * 2)) * 0.1)
				img.set_pixel(x, y, Color(shade, shade, shade, 1.0))
			elif (x + y) % 12 == 0:
				img.set_pixel(x, y, Color(0.2, 0.25, 0.22, 1.0))

	return ImageTexture.create_from_image(img)


# ==============================================================================
# ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ И ИДЕОЛОГИИ
# ==============================================================================

func _get_ideology_phosphor_color(ideology: String) -> Color:
	var ideo_low = ideology.to_lower()
	if "social" in ideo_low or "communist" in ideo_low or "bolshevik" in ideo_low:
		return PHOSPHOR_GREEN
	elif "democrat" in ideo_low or "liberal" in ideo_low or "republic" in ideo_low:
		return PHOSPHOR_CYAN
	elif "burgund" in ideo_low or "national social" in ideo_low or "fascis" in ideo_low:
		return PHOSPHOR_RED
	elif "military" in ideo_low or "stratocra" in ideo_low or "junta" in ideo_low:
		return PHOSPHOR_OLIVE
	else:
		return PHOSPHOR_AMBER


func _update_frame_visuals() -> void:
	if _shader_mat != null:
		if _is_disabled:
			_shader_mat.set_shader_parameter("brightness", 0.6)
			_shader_mat.set_shader_parameter("contrast", 0.9)
		elif _is_selected:
			_shader_mat.set_shader_parameter("brightness", 1.25)
			_shader_mat.set_shader_parameter("contrast", 1.4)
		elif _is_hovered:
			_shader_mat.set_shader_parameter("brightness", 1.18)
			_shader_mat.set_shader_parameter("contrast", 1.35)
		else:
			_shader_mat.set_shader_parameter("brightness", 1.1)
			_shader_mat.set_shader_parameter("contrast", 1.3)

	if border_rect != null:
		border_rect.editor_only = false
		if _is_disabled:
			border_rect.border_color = Color(0.12, 0.15, 0.14, 0.4)
			border_rect.border_width = 1.0
		elif _is_selected:
			border_rect.border_color = Color(0.3, 1.0, 0.85, 1.0)
			border_rect.border_width = 2.0
		elif _is_hovered:
			border_rect.border_color = Color(0.2, 0.8, 0.6, 0.8)
			border_rect.border_width = 1.0
		else:
			border_rect.border_color = Color(0.15, 0.35, 0.25, 0.6)
			border_rect.border_width = 1.0


func _on_mouse_entered() -> void:
	if _is_disabled:
		return
	set_hovered(true)
	play_glitch_burst(0.12, 0.15)


func _on_mouse_exited() -> void:
	set_hovered(false)


func _on_gui_input(event: InputEvent) -> void:
	if _is_disabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		portrait_clicked.emit()
