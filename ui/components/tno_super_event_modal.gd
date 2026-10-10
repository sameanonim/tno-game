class_name TNOSuperEventModal
extends Control

##
## TNOSuperEventModal: Легендарное полноэкранное окно Супер-события TNO
##
## Включает:
## - Широкоформатный атмосферный арт кризиса (assets/gfx/interface/superevents/)
## - Темную виньетку и рамку в стиле TNO_SG_Super_Event
## - Монументальный заголовок аутентичным шрифтом Bombardier
## - Полупрозрачный баннер с исторической цитатой / радиосводкой
## - Фирменную кнопку с культовой нарративной фразой
## - Полноценное воспроизведение оригинального аудио-трека супер-события (OGG)
## - Интеграцию с базой data/events/superevents_catalog.json
##

signal option_selected()

const CATALOG_PATH = "res://data/events/superevents_catalog.json"
const EVENT_PICTURE_SHADER = preload("res://shaders/event_picture_crt.gdshader")

@onready var backdrop: ColorRect = get_node_or_null("Backdrop")
@onready var modal_panel: PanelContainer = get_node_or_null("ModalPanel")
@onready var art_texture: TextureRect = get_node_or_null("ModalPanel/VBox/ArtContainer/ArtTexture")
@onready var lbl_title: Label = get_node_or_null("ModalPanel/VBox/TitleLabel")
@onready var underlay_banner: TextureRect = get_node_or_null("ModalPanel/VBox/UnderlayBanner")
@onready var lbl_quote: RichTextLabel = get_node_or_null("ModalPanel/VBox/UnderlayBanner/QuoteLabel")
@onready var btn_option: Button = get_node_or_null("ModalPanel/VBox/OptionButton")

var audio_player: AudioStreamPlayer = null
var _catalog_cache: Dictionary = {}
var _is_catalog_loaded: bool = false
var _active_event_id: String = ""


func _ready() -> void:
	_ensure_node_references()
	_init_audio_player()
	_apply_tno_styling()
	_load_catalog()

	if btn_option != null and not btn_option.pressed.is_connected(_on_option_button_pressed):
		btn_option.pressed.connect(_on_option_button_pressed)


func _get_active_scene_tree() -> SceneTree:
	if is_inside_tree():
		return get_tree()
	var ml = Engine.get_main_loop()
	if ml is SceneTree:
		return ml
	return null


func _ensure_node_references() -> void:
	if backdrop == null:
		backdrop = get_node_or_null("Backdrop")
	if modal_panel == null:
		modal_panel = get_node_or_null("ModalPanel")
	if art_texture == null:
		art_texture = get_node_or_null("ModalPanel/VBox/ArtContainer/ArtTexture")
	if lbl_title == null:
		lbl_title = get_node_or_null("ModalPanel/VBox/TitleLabel")
	if underlay_banner == null:
		underlay_banner = get_node_or_null("ModalPanel/VBox/UnderlayBanner")
	if lbl_quote == null:
		lbl_quote = get_node_or_null("ModalPanel/VBox/UnderlayBanner/QuoteLabel")
	if btn_option == null:
		btn_option = get_node_or_null("ModalPanel/VBox/OptionButton")


func _init_audio_player() -> void:
	if audio_player == null:
		audio_player = AudioStreamPlayer.new()
		audio_player.name = "SuperEventAudioPlayer"
		audio_player.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
		add_child(audio_player)


func _apply_tno_styling() -> void:
	_ensure_node_references()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.08, 0.98)
	sb.border_color = TNOTheme.COLOR_BORDER_CYAN
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(2)
	sb.shadow_color = Color(0.18, 0.9, 0.84, 0.35)
	sb.shadow_size = 8
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	if modal_panel != null:
		modal_panel.add_theme_stylebox_override("panel", sb)

	var font_bomb = TNOTheme.get_font_bombardier()
	if font_bomb != null:
		if lbl_title != null:
			lbl_title.add_theme_font_override("font", font_bomb)
			lbl_title.add_theme_font_size_override("font_size", 24)
		if btn_option != null:
			btn_option.add_theme_font_override("font", font_bomb)
			btn_option.add_theme_font_size_override("font_size", 18)

	if btn_option != null:
		TNOTheme.apply_button_style(btn_option, TNOTheme.COLOR_BORDER_AMBER, Color(0.12, 0.16, 0.20, 0.95))


func _load_catalog() -> void:
	if _is_catalog_loaded:
		return
	if not FileAccess.file_exists(CATALOG_PATH):
		push_warning("[TNOSuperEventModal] Superevents catalog file not found: %s" % CATALOG_PATH)
		return

	var file = FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		return
	var text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var err = json.parse(text)
	if err == OK and json.data is Dictionary:
		_catalog_cache = json.data
		_is_catalog_loaded = true
		print("[TNOSuperEventModal] Loaded catalog with %d superevents." % _catalog_cache.size())


## Показ супер-события по идентификатору из каталога (например, "SE_GERMAN_CIVIL_WAR" или "german_civil_war")
func show_super_event_by_id(super_event_id: String) -> bool:
	_ensure_node_references()
	_load_catalog()
	_active_event_id = super_event_id

	var entry = _find_catalog_entry(super_event_id)
	if entry.is_empty():
		push_warning("[TNOSuperEventModal] Super event ID not found in catalog: %s" % super_event_id)
		show_super_event(
			super_event_id.replace("_", " ").to_upper(),
			"The winds of change are sweeping across the world.",
			"SO IT BEGINS",
			"res://assets/gfx/interface/superevents/russian_reunification.png",
			""
		)
		return false

	var is_ru := true
	var tree = _get_active_scene_tree()
	var root_node = tree.root if tree != null else null
	if root_node != null and root_node.has_node("LocalizationManager"):
		var loc = root_node.get_node("LocalizationManager")
		if loc.has_method("get_current_locale"):
			is_ru = (loc.get_current_locale() == "ru")
		elif loc.get("current_locale") != null:
			is_ru = (str(loc.get("current_locale")) == "ru")

	var title = str(entry.get("title_ru" if is_ru else "title_en", ""))
	if title.is_empty():
		title = str(entry.get("title_en", super_event_id))

	var quote = str(entry.get("quote_ru" if is_ru else "quote_en", ""))
	if quote.is_empty():
		quote = str(entry.get("quote_en", ""))

	var option_txt = str(entry.get("option_ru" if is_ru else "option_en", ""))
	if option_txt.is_empty():
		option_txt = str(entry.get("option_en", "ОСТАЕТСЯ ТОЛЬКО НАДЕЖДА."))

	var art_path = str(entry.get("art_path", ""))
	var audio_path = str(entry.get("audio_path", ""))

	show_super_event(title, quote, option_txt, art_path, audio_path)
	return true


func _find_catalog_entry(query_id: String) -> Dictionary:
	if _catalog_cache.has(query_id):
		return _catalog_cache[query_id]

	var norm = query_id.to_upper().strip_edges()
	if _catalog_cache.has(norm):
		return _catalog_cache[norm]

	var candidates = [
		norm,
		"SE_" + norm.trim_prefix("SE_").trim_prefix("TNO_SE_"),
		"TNO_SE_" + norm.trim_prefix("SE_").trim_prefix("TNO_SE_")
	]

	for c in candidates:
		if _catalog_cache.has(c):
			return _catalog_cache[c]

	var low = query_id.to_lower()
	for k in _catalog_cache.keys():
		if k.to_lower() == low or k.to_lower().contains(low):
			return _catalog_cache[k]

	return {}


## Основной метод визуализации и воспроизведения аудио супер-события
func show_super_event(title_text: String, quote_text: String, option_text: String, art_path: String = "", audio_path: String = "") -> void:
	_ensure_node_references()
	_init_audio_player()

	if lbl_title != null:
		lbl_title.text = title_text.to_upper()
	if lbl_quote != null:
		lbl_quote.text = "[center][i]%s[/i][/center]" % quote_text
	if btn_option != null:
		btn_option.text = option_text.to_upper()

	# 1. Загрузка атмосферного арта
	var loaded_art: Texture2D = null
	if not art_path.is_empty():
		if ResourceLoader.exists(art_path):
			loaded_art = load(art_path) as Texture2D
		elif has_node("/root/AssetRegistry"):
			loaded_art = get_node("/root/AssetRegistry").get_texture(art_path)

	if loaded_art == null and has_node("/root/AssetRegistry"):
		var ar = get_node("/root/AssetRegistry")
		var fn = art_path.get_file()
		if not fn.is_empty():
			loaded_art = ar.get_texture("res://assets/gfx/interface/superevents/" + fn)

	if loaded_art == null:
		loaded_art = TNOTheme.get_texture("res://assets/gfx/interface/superevents/russian_reunification.png")

	if art_texture != null and loaded_art != null:
		art_texture.texture = loaded_art
		if art_texture.material == null or not (art_texture.material is ShaderMaterial):
			var mat := ShaderMaterial.new()
			mat.shader = EVENT_PICTURE_SHADER
			mat.set_shader_parameter("phosphor_tint", Color(0.95, 0.85, 0.55, 1.0))
			mat.set_shader_parameter("tint_mix", 0.30)
			mat.set_shader_parameter("scanline_intensity", 0.18)
			mat.set_shader_parameter("vignette_strength", 0.45)
			mat.set_shader_parameter("reveal_progress", 1.0)
			art_texture.material = mat
		if art_texture.material is ShaderMaterial:
			var smat = art_texture.material as ShaderMaterial
			smat.set_shader_parameter("reveal_progress", 0.0)
			var tw = art_texture.create_tween()
			tw.tween_method(func(v: float): smat.set_shader_parameter("reveal_progress", v), 0.0, 1.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 2. Приостановка фонового радио для воспроизведения трека супер-события
	var tree = _get_active_scene_tree()
	var root_node = tree.root if tree != null else null
	if root_node != null and root_node.has_node("AudioManager"):
		var am = root_node.get_node("AudioManager")
		if am.has_method("pause_music_for_super_event"):
			am.pause_music_for_super_event()

	# 3. Воспроизведение звуковой дорожки супер-события
	if not audio_path.is_empty():
		var stream: AudioStream = null
		if ResourceLoader.exists(audio_path):
			stream = load(audio_path)
		elif FileAccess.file_exists(audio_path):
			stream = AudioStreamOggVorbis.load_from_file(audio_path)

		if stream != null and audio_player != null:
			if stream is AudioStreamOggVorbis:
				(stream as AudioStreamOggVorbis).loop = false
			audio_player.stop()
			audio_player.stream = stream
			audio_player.volume_db = 0.0
			if is_inside_tree():
				audio_player.play()
			print("[TNOSuperEventModal] Playing authentic track: %s" % audio_path)

	# 4. Анимация появления в стиле CRT
	modulate.a = 0.0
	visible = true
	if is_inside_tree():
		var tw = create_tween()
		tw.tween_property(self, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		modulate.a = 1.0


func _on_option_button_pressed() -> void:
	option_selected.emit()

	# Плавное затухание звука супер-события и возобновление радио
	if audio_player != null and audio_player.playing:
		if is_inside_tree():
			var tw_audio = create_tween()
			tw_audio.tween_property(audio_player, "volume_db", -30.0, 0.35)
			tw_audio.tween_callback(func():
				if audio_player != null:
					audio_player.stop()
			)
		else:
			audio_player.stop()

	var tree = _get_active_scene_tree()
	var root_node = tree.root if tree != null else null
	if root_node != null and root_node.has_node("AudioManager"):
		var am = root_node.get_node("AudioManager")
		if am.has_method("play_sfx"):
			am.play_sfx("window_close")
		if am.has_method("resume_music_after_super_event"):
			am.resume_music_after_super_event()

	# Анимация скрытия окна
	if is_inside_tree():
		var tw = create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.25)
		tw.tween_callback(func():
			visible = false
		)
	else:
		visible = false
