class_name SettingsLanguage
extends Control

##
## SettingsLanguage: Экран выбора языкового пакета терминала бункера TNO
##
## Реализует интерфейс в ретро-эстетике ЭЛТ-монитора 1960–70-х годов:
## - Псевдографические рамки и радио-кнопки (•) / ( )
## - Мгновенное переключение языка на лету без перезапуска игры
## - Интерактивный предпросмотр кризисной депеши (Live Preview)
## - Синтезатор механического щелчка реле / переключателя
## - Запись конфигурации в BIOS (user://settings.cfg)
##

signal closed()
signal language_applied(locale_code: String)

# Цветовая палитра военного фосфорного ЭЛТ-терминала
const COLOR_PHOSPHOR_BRIGHT = Color(0.2, 0.95, 0.65) # Активный фосфор #33f3a6
const COLOR_PHOSPHOR_MUTED  = Color(0.35, 0.6, 0.45) # Неактивный элемент #599973
const COLOR_PHOSPHOR_ACTIVE = Color(0.3, 1.0, 0.8)   # Бирюзовый акцент #4dffcc
const COLOR_PHOSPHOR_BG     = Color(0.04, 0.08, 0.06, 0.95) # Темный фон экрана
const COLOR_FRAME_LINE      = Color(0.18, 0.45, 0.3) # Линии псевдографики

# --- Ссылки на узлы интерфейса ---
@onready var header_label: Label = $VBox/HeaderPanel/VBox/HeaderLabel
@onready var subheader_label: Label = $VBox/HeaderPanel/VBox/SubheaderLabel
@onready var lang_list_container: VBoxContainer = $VBox/MainSplit/LeftColumn/LangListPanel/VBox/LangList
@onready var bios_info_label: Label = $VBox/MainSplit/LeftColumn/BiosPanel/BiosInfoLabel

# Live Preview узлы
@onready var preview_header: Label = $VBox/MainSplit/RightColumn/PreviewPanel/VBox/PreviewHeader
@onready var preview_class: Label = $VBox/MainSplit/RightColumn/PreviewPanel/VBox/PreviewClass
@onready var preview_title: Label = $VBox/MainSplit/RightColumn/PreviewPanel/VBox/PreviewTitle
@onready var preview_body: RichTextLabel = $VBox/MainSplit/RightColumn/PreviewPanel/VBox/PreviewBody
@onready var preview_btn_a: Button = $VBox/MainSplit/RightColumn/PreviewPanel/VBox/OptionsVBox/OptionABtn
@onready var preview_btn_b: Button = $VBox/MainSplit/RightColumn/PreviewPanel/VBox/OptionsVBox/OptionBBtn

# Нижняя панель действий
@onready var btn_apply_bios: Button = $VBox/BottomBar/HBox/ApplyBiosButton
@onready var btn_back: Button = $VBox/BottomBar/HBox/BackButton
@onready var status_label: Label = $VBox/BottomBar/StatusLabel

@onready var crt_overlay: ColorRect = get_node_or_null("CRTOverlay")

const LocManagerScript = preload("res://core/systems/localization_manager.gd")

# Встроенный синтезатор щелчка реле / клавиши
var _sfx_player: AudioStreamPlayer = null
var _audio_generator: AudioStreamGenerator = null
var _loc_mgr: Node = null
var _radio_buttons: Array[Button] = []
var _selected_locale: String = "ru"


func _ready() -> void:
	_init_localization_manager()
	_init_relay_audio_synthesizer()
	_connect_signals()
	_populate_language_radio_list()
	_update_ui_texts()
	_refresh_live_preview()
	var sm = _get_settings_mgr()
	if sm != null and crt_overlay != null:
		sm.register_crt_overlay(crt_overlay)


func _init_localization_manager() -> void:
	_loc_mgr = _get_loc_mgr()
	_selected_locale = _loc_mgr.get_locale()
	if not _loc_mgr.locale_changed.is_connected(_on_locale_changed):
		_loc_mgr.locale_changed.connect(_on_locale_changed)


func _get_loc_mgr() -> Node:
	if LocManagerScript.instance != null and is_instance_valid(LocManagerScript.instance):
		return LocManagerScript.instance
	if has_node("/root/LocalizationManager"):
		return get_node("/root/LocalizationManager")
	var root_node = get_tree().root if get_tree() != null else null
	if root_node != null:
		var fallback = root_node.get_node_or_null("LocalizationManager")
		if fallback != null:
			return fallback
		var s = LocManagerScript.new()
		s.name = "LocalizationManager"
		root_node.add_child(s)
		return s
	return LocManagerScript.new()


func _connect_signals() -> void:
	btn_apply_bios.pressed.connect(_on_apply_bios_pressed)
	btn_back.pressed.connect(_on_back_pressed)

	preview_btn_a.pressed.connect(func():
		_play_relay_click(800.0, 0.03)
		status_label.text = "[ ВЫБРАНА ОПЦИЯ 'А' // ТЕСТОВЫЙ ПРИКАЗ ПЕРЕДАН В ШТАБ ]"
	)
	preview_btn_b.pressed.connect(func():
		_play_relay_click(650.0, 0.03)
		status_label.text = "[ ВЫБРАНА ОПЦИЯ 'Б' // ТЕСТОВЫЙ ПРИКАЗ ПЕРЕДАН В ШТАБ ]"
	)

	var sm = _get_settings_mgr()
	if sm != null:
		sm.crt_param_changed.connect(func(_p, _v):
			if crt_overlay != null:
				sm.apply_crt_to_overlay(crt_overlay)
		)
		sm.crt_enabled_changed.connect(func(is_enabled):
			if crt_overlay != null:
				crt_overlay.visible = is_enabled
		)


func _get_settings_mgr() -> Node:
	if has_node("/root/SettingsManager"):
		return get_node("/root/SettingsManager")
	var root_node = get_tree().root if get_tree() != null else null
	if root_node != null:
		return root_node.get_node_or_null("SettingsManager")
	return null


# ==============================================================================
# СПИСОК ЯЗЫКОВЫХ ПАКЕТОВ В ПСЕВДОГРАФИКЕ
# ==============================================================================

func _populate_language_radio_list() -> void:
	for c in lang_list_container.get_children():
		c.queue_free()
	_radio_buttons.clear()

	var locales = _loc_mgr.get_available_locales()
	for item in locales:
		var btn = Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_ALL
		btn.custom_minimum_size = Vector2(0, 42)

		var code = str(item.get("code", "ru"))
		btn.set_meta("locale_code", code)

		_style_retro_button(btn)
		_radio_buttons.append(btn)
		lang_list_container.add_child(btn)

		btn.pressed.connect(_on_language_selected.bind(code))

	_refresh_radio_states()


func _style_retro_button(btn: Button) -> void:
	var flat_style = StyleBoxFlat.new()
	flat_style.bg_color = Color(0.06, 0.12, 0.09, 0.85)
	flat_style.border_color = COLOR_FRAME_LINE
	flat_style.set_border_width_all(1)
	flat_style.content_margin_left = 12
	flat_style.content_margin_right = 12
	flat_style.content_margin_top = 8
	flat_style.content_margin_bottom = 8

	var hover_style = flat_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.1, 0.22, 0.15, 0.95)
	hover_style.border_color = COLOR_PHOSPHOR_ACTIVE

	var pressed_style = flat_style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = Color(0.14, 0.3, 0.2, 1.0)
	pressed_style.border_color = COLOR_PHOSPHOR_BRIGHT

	btn.add_theme_stylebox_override("normal", flat_style)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	btn.add_theme_stylebox_override("focus", hover_style)

	var font = _loc_mgr.get_terminal_font()
	if font != null:
		btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", 14)


func _refresh_radio_states() -> void:
	var active_code = _loc_mgr.get_locale() if _loc_mgr != null else _selected_locale
	for btn in _radio_buttons:
		var code = str(btn.get_meta("locale_code", ""))
		var is_active = (code == active_code)
		var locales = _loc_mgr.get_available_locales()
		var pack_id = "%s_LOC_PACK" % code.to_upper()
		var loc_name = code.to_upper()

		for l in locales:
			if l["code"] == code:
				pack_id = l.get("pack_id", pack_id)
				loc_name = l.get("name", loc_name)
				break

		var radio_glyph = "(•)" if is_active else "( )"
		var status_badge = "[ACTIVE]" if is_active else "[READY]"

		btn.text = " %s %-20s [%-18s] %s" % [radio_glyph, loc_name.to_upper(), pack_id, status_badge]

		if is_active:
			btn.add_theme_color_override("font_color", COLOR_PHOSPHOR_ACTIVE)
			btn.add_theme_color_override("font_hover_color", COLOR_PHOSPHOR_BRIGHT)
		else:
			btn.add_theme_color_override("font_color", COLOR_PHOSPHOR_MUTED)
			btn.add_theme_color_override("font_hover_color", COLOR_PHOSPHOR_BRIGHT)


# ==============================================================================
# ОБРАБОТКА ВЫБОРА ЯЗЫКА И НАЖАТИЙ
# ==============================================================================

func _on_language_selected(new_locale: String) -> void:
	if _selected_locale == new_locale:
		return

	_selected_locale = new_locale
	_play_relay_click(920.0, 0.04) # Звук переключения электромеханического реле

	# Мгновенная активация в LocalizationManager на лету (без лишней записи на диск)
	_loc_mgr.set_locale(_selected_locale, false)
	_refresh_radio_states()
	_update_ui_texts()
	_refresh_live_preview()

	status_label.text = "[ ВНИМАНИЕ: СИСТЕМНЫЙ ЯЗЫК ПЕРЕКЛЮЧЕН НА: %s ]" % _selected_locale.to_upper()


func _on_apply_bios_pressed() -> void:
	_play_relay_click(1200.0, 0.06) # Двойной щелчок сохранения
	_loc_mgr.save_to_config()
	status_label.text = _loc_mgr.tr_key("SYS_LANG_SAVED_SUCCESS")
	language_applied.emit(_selected_locale)


func _on_back_pressed() -> void:
	_play_relay_click(550.0, 0.03)
	_loc_mgr.save_to_config()
	closed.emit()


func _on_locale_changed(locale_code: String) -> void:
	_selected_locale = locale_code
	_refresh_radio_states()
	_update_ui_texts()
	_refresh_live_preview()


# ==============================================================================
# ОБНОВЛЕНИЕ ТЕКСТОВ ЭКРАНА И ПРЕДПРОСМОТРА
# ==============================================================================

func _update_ui_texts() -> void:
	header_label.text = _loc_mgr.tr_key("SYS_TITLE")
	subheader_label.text = _loc_mgr.tr_key("SYS_TERMINAL_CONFIG")
	btn_apply_bios.text = _loc_mgr.tr_key("SYS_LANG_SAVE_BIOS")
	btn_back.text = _loc_mgr.tr_key("SYS_BACK")
	bios_info_label.text = _loc_mgr.tr_key("SYS_BIOS_INFO")

	var font = _loc_mgr.get_terminal_font()
	if font != null:
		header_label.add_theme_font_override("font", font)
		subheader_label.add_theme_font_override("font", font)
		preview_title.add_theme_font_override("font", font)
		preview_body.add_theme_font_override("normal_font", font)


func _refresh_live_preview() -> void:
	preview_header.text = _loc_mgr.tr_key("PREVIEW_PANEL_HEADER")
	preview_class.text = _loc_mgr.tr_key("PREVIEW_CRISIS_CLASS")
	preview_title.text = _loc_mgr.tr_key("PREVIEW_CRISIS_TITLE")
	preview_body.text = "[color=#a0ccb8]%s[/color]" % _loc_mgr.tr_key("PREVIEW_CRISIS_BODY")
	preview_btn_a.text = _loc_mgr.tr_key("PREVIEW_CRISIS_OPT_A")
	preview_btn_b.text = _loc_mgr.tr_key("PREVIEW_CRISIS_OPT_B")


# ==============================================================================
# ПРОЦЕДУРНЫЙ СИНТЕЗАТОР ЗВУКА ЩЕЛЧКА РЕЛЕ / ПЕРЕКЛЮЧАТЕЛЯ
# ==============================================================================

func _init_relay_audio_synthesizer() -> void:
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.name = "RelaySFXPlayer"
	_audio_generator = AudioStreamGenerator.new()
	_audio_generator.mix_rate = 22050
	_audio_generator.buffer_length = 0.1
	_sfx_player.stream = _audio_generator
	_sfx_player.volume_db = -6.0
	add_child(_sfx_player)
	_sfx_player.play()


func _play_relay_click(pitch_hz: float = 880.0, duration_sec: float = 0.035) -> void:
	if _sfx_player == null or not _sfx_player.playing:
		return

	var playback: AudioStreamGeneratorPlayback = _sfx_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return

	var sample_rate = _audio_generator.mix_rate
	var total_frames = int(duration_sec * sample_rate)
	var available = playback.get_frames_available()
	var frames_to_push = mini(total_frames, available)

	for i in range(frames_to_push):
		var t = float(i) / float(sample_rate)
		# Быстро затухающая огибающая щелчка контакта реле
		var decay = exp(-t * 95.0)
		var tone = sin(2.0 * PI * pitch_hz * t)
		# Добавление механического высокочастотного шума в момент соприкосновения контактов
		var contact_noise = (randf() * 2.0 - 1.0) * exp(-t * 220.0) * 0.4
		var sample = (tone * 0.6 + contact_noise) * decay
		playback.push_frame(Vector2(sample, sample))
