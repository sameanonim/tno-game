class_name SettingsTerminal
extends Control

##
## SettingsTerminal: Полнофункциональный ретро-терминал калибровки видеосистемы,
## CRT-эффектов, звукового тракта и языка (TNO 1960-70s military bunker style)
##

signal closed()
signal settings_saved()

const COLOR_PHOSPHOR_BRIGHT = Color(0.2, 0.95, 0.65)
const COLOR_PHOSPHOR_MUTED  = Color(0.35, 0.6, 0.45)
const COLOR_PHOSPHOR_ACTIVE = Color(0.3, 1.0, 0.8)
const COLOR_FRAME_LINE      = Color(0.18, 0.45, 0.3)
const COLOR_ALERT_RED       = Color(0.95, 0.3, 0.3)

# Вкладки
enum TabIndex {
	DISPLAY = 0,
	CRT = 1,
	AUDIO = 2,
	LANGUAGE = 3
}

var _current_tab: TabIndex = TabIndex.DISPLAY

# Узлы верхней панели
@onready var header_title: Label = $VBox/HeaderPanel/VBox/TitleLabel
@onready var header_sub: Label = $VBox/HeaderPanel/VBox/SubLabel

# Кнопки вкладок
@onready var tab_btn_display: Button = $VBox/TabBar/BtnDisplay
@onready var tab_btn_crt: Button = $VBox/TabBar/BtnCRT
@onready var tab_btn_audio: Button = $VBox/TabBar/BtnAudio
@onready var tab_btn_language: Button = $VBox/TabBar/BtnLanguage

# Контейнеры вкладок
@onready var tab_display_panel: Control = $VBox/ContentPanel/TabDisplay
@onready var tab_crt_panel: Control = $VBox/ContentPanel/TabCRT
@onready var tab_audio_panel: Control = $VBox/ContentPanel/TabAudio
@onready var tab_lang_panel: Control = $VBox/ContentPanel/TabLanguage

# Элементы вкладки Display
@onready var opt_resolution: OptionButton = $VBox/ContentPanel/TabDisplay/Grid/OptResolution
@onready var opt_window_mode: OptionButton = $VBox/ContentPanel/TabDisplay/Grid/OptWindowMode
@onready var opt_vsync: OptionButton = $VBox/ContentPanel/TabDisplay/Grid/OptVSync
@onready var opt_ui_scale: OptionButton = $VBox/ContentPanel/TabDisplay/Grid/OptUIScale
@onready var btn_apply_display: Button = $VBox/ContentPanel/TabDisplay/Actions/ApplyDisplayButton
@onready var lbl_display_info: Label = $VBox/ContentPanel/TabDisplay/InfoLabel

# Элементы вкладки CRT
@onready var chk_crt_enable: CheckBox = $VBox/ContentPanel/TabCRT/Grid/ChkCRTEnable
@onready var slider_curvature: HSlider = $VBox/ContentPanel/TabCRT/Grid/CurvatureSlider
@onready var val_curvature: Label = $VBox/ContentPanel/TabCRT/Grid/ValCurvature
@onready var slider_scanlines: HSlider = $VBox/ContentPanel/TabCRT/Grid/ScanlinesSlider
@onready var val_scanlines: Label = $VBox/ContentPanel/TabCRT/Grid/ValScanlines
@onready var chk_auto_scanlines: CheckBox = $VBox/ContentPanel/TabCRT/Grid/ChkAutoScanlines
@onready var slider_glow: HSlider = $VBox/ContentPanel/TabCRT/Grid/GlowSlider
@onready var val_glow: Label = $VBox/ContentPanel/TabCRT/Grid/ValGlow
@onready var slider_aberration: HSlider = $VBox/ContentPanel/TabCRT/Grid/AberrationSlider
@onready var val_aberration: Label = $VBox/ContentPanel/TabCRT/Grid/ValAberration

# Элементы вкладки Audio
@onready var slider_master: HSlider = $VBox/ContentPanel/TabAudio/Grid/MasterSlider
@onready var val_master: Label = $VBox/ContentPanel/TabAudio/Grid/ValMaster
@onready var slider_sfx: HSlider = $VBox/ContentPanel/TabAudio/Grid/SFXSlider
@onready var val_sfx: Label = $VBox/ContentPanel/TabAudio/Grid/ValSFX
@onready var slider_ambient: HSlider = $VBox/ContentPanel/TabAudio/Grid/AmbientSlider
@onready var val_ambient: Label = $VBox/ContentPanel/TabAudio/Grid/ValAmbient
@onready var btn_test_sfx: Button = $VBox/ContentPanel/TabAudio/Actions/TestSFXButton

# Элементы вкладки Языки
@onready var lang_buttons_container: VBoxContainer = $VBox/ContentPanel/TabLanguage/LangListPanel/VBox/LangList
@onready var lang_info_label: Label = $VBox/ContentPanel/TabLanguage/LangInfoLabel

# Нижняя панель действий
@onready var status_bar_label: Label = $VBox/BottomBar/StatusLabel
@onready var btn_save_bios: Button = $VBox/BottomBar/HBox/SaveBiosButton
@onready var btn_back: Button = $VBox/BottomBar/HBox/BackButton
@onready var btn_save_game: Button = get_node_or_null("VBox/BottomBar/HBox/SaveGameButton")
@onready var btn_load_game: Button = get_node_or_null("VBox/BottomBar/HBox/LoadGameButton")

# Модальный диалог подтверждения смены разрешения (Safety Revert)
@onready var revert_dialog: PanelContainer = $RevertModalOverlay/RevertPanel
@onready var revert_overlay: Control = $RevertModalOverlay
@onready var revert_msg_label: Label = $RevertModalOverlay/RevertPanel/VBox/MessageLabel
@onready var btn_confirm_res: Button = $RevertModalOverlay/RevertPanel/VBox/HBox/ConfirmButton
@onready var btn_revert_res: Button = $RevertModalOverlay/RevertPanel/VBox/HBox/RevertButton

# Оверлей CRT
@onready var crt_overlay: ColorRect = $CRTOverlay

# Звуковой синтезатор
var _sfx_player: AudioStreamPlayer = null
var _audio_gen: AudioStreamGenerator = null
var _settings_mgr: Node = null
var _loc_mgr: Node = null

var _cached_resolutions: Array[Vector2i] = []
var _lang_radio_buttons: Array[Button] = []


func _ready() -> void:
	_init_managers()
	_init_audio_synth()
	_connect_events()
	_populate_options()
	_populate_languages()
	_switch_tab(TabIndex.DISPLAY)
	_sync_ui_with_settings()
	_update_localized_texts()
	_apply_crt()
	revert_overlay.visible = false


func _init_managers() -> void:
	if has_node("/root/SettingsManager"):
		_settings_mgr = get_node("/root/SettingsManager")
	else:
		var script = load("res://core/systems/settings_manager.gd")
		if script != null:
			_settings_mgr = script.new()
			_settings_mgr.name = "SettingsManager"
			get_tree().root.add_child(_settings_mgr)

	if has_node("/root/LocalizationManager"):
		_loc_mgr = get_node("/root/LocalizationManager")


func _connect_events() -> void:
	# Вкладки
	tab_btn_display.pressed.connect(func(): _switch_tab(TabIndex.DISPLAY))
	tab_btn_crt.pressed.connect(func(): _switch_tab(TabIndex.CRT))
	tab_btn_audio.pressed.connect(func(): _switch_tab(TabIndex.AUDIO))
	tab_btn_language.pressed.connect(func(): _switch_tab(TabIndex.LANGUAGE))

	# Дисплей
	btn_apply_display.pressed.connect(_on_apply_display_pressed)
	opt_ui_scale.item_selected.connect(_on_ui_scale_selected)

	# CRT
	chk_crt_enable.toggled.connect(_on_crt_toggled)
	slider_curvature.value_changed.connect(func(v):
		_settings_mgr.set_crt_param("curvature", v)
		val_curvature.text = "%.3f" % v
		_apply_crt()
	)
	slider_scanlines.value_changed.connect(func(v):
		_settings_mgr.set_crt_param("scanline_intensity", v)
		val_scanlines.text = "%.2f" % v
		_apply_crt()
	)
	chk_auto_scanlines.toggled.connect(func(toggled):
		_settings_mgr.set_crt_param("scanline_auto_density", toggled)
		_settings_mgr.update_crt_scanline_density()
		_apply_crt()
	)
	slider_glow.value_changed.connect(func(v):
		_settings_mgr.set_crt_param("brightness_boost", v)
		val_glow.text = "%.2f" % v
		_apply_crt()
	)
	slider_aberration.value_changed.connect(func(v):
		_settings_mgr.set_crt_param("chromatic_aberration", v)
		val_aberration.text = "%.4f" % v
		_apply_crt()
	)

	# Audio
	slider_master.value_changed.connect(func(v):
		_settings_mgr.audio_settings["master_volume"] = v
		val_master.text = "%d%%" % int(v * 100)
		_settings_mgr.apply_audio_volumes()
	)
	slider_sfx.value_changed.connect(func(v):
		_settings_mgr.audio_settings["sfx_volume"] = v
		val_sfx.text = "%d%%" % int(v * 100)
		_settings_mgr.apply_audio_volumes()
	)
	slider_ambient.value_changed.connect(func(v):
		_settings_mgr.audio_settings["ambient_volume"] = v
		val_ambient.text = "%d%%" % int(v * 100)
		_settings_mgr.apply_audio_volumes()
	)
	btn_test_sfx.pressed.connect(func(): _play_relay_click(1050.0, 0.05))

	# Revert dialog
	btn_confirm_res.pressed.connect(_on_confirm_resolution_pressed)
	btn_revert_res.pressed.connect(_on_revert_resolution_pressed)

	if _settings_mgr != null:
		_settings_mgr.revert_countdown_tick.connect(_on_revert_tick)
		_settings_mgr.revert_cancelled.connect(_on_revert_cancelled)

	# Нижняя панель
	btn_save_bios.pressed.connect(_on_save_bios_pressed)
	btn_back.pressed.connect(_on_back_pressed)
	if btn_save_game != null:
		btn_save_game.pressed.connect(_on_save_game_pressed)
	if btn_load_game != null:
		btn_load_game.pressed.connect(_on_load_game_pressed)

	if _loc_mgr != null and not _loc_mgr.locale_changed.is_connected(_on_locale_changed):
		_loc_mgr.locale_changed.connect(_on_locale_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if revert_overlay.visible:
			_on_revert_resolution_pressed()
			get_viewport().set_input_as_handled()
		else:
			_on_back_pressed()
			get_viewport().set_input_as_handled()


# ==============================================================================
# ПЕРЕКЛЮЧЕНИЕ ВКЛАДОК
# ==============================================================================

func _switch_tab(tab: TabIndex) -> void:
	_current_tab = tab
	tab_display_panel.visible = (tab == TabIndex.DISPLAY)
	tab_crt_panel.visible = (tab == TabIndex.CRT)
	tab_audio_panel.visible = (tab == TabIndex.AUDIO)
	tab_lang_panel.visible = (tab == TabIndex.LANGUAGE)

	_style_tab_btn(tab_btn_display, tab == TabIndex.DISPLAY)
	_style_tab_btn(tab_btn_crt, tab == TabIndex.CRT)
	_style_tab_btn(tab_btn_audio, tab == TabIndex.AUDIO)
	_style_tab_btn(tab_btn_language, tab == TabIndex.LANGUAGE)

	_play_relay_click(800.0 + int(tab) * 100.0, 0.03)


func _style_tab_btn(btn: Button, is_active: bool) -> void:
	if is_active:
		btn.add_theme_color_override("font_color", COLOR_PHOSPHOR_ACTIVE)
	else:
		btn.add_theme_color_override("font_color", COLOR_PHOSPHOR_MUTED)


# ==============================================================================
# ЗАПОЛНЕНИЕ ВЫПАДАЮЩИХ СПИСКОВ
# ==============================================================================

func _populate_options() -> void:
	# 1. Разрешения
	opt_resolution.clear()
	_cached_resolutions = _settings_mgr.get_available_resolutions()
	var curr_res = _settings_mgr.current_resolution
	var selected_idx = 0

	for i in range(_cached_resolutions.size()):
		var r = _cached_resolutions[i]
		var label = _settings_mgr.get_resolution_label(r)
		opt_resolution.add_item(label, i)
		if r == curr_res:
			selected_idx = i

	opt_resolution.select(selected_idx)

	# 2. Режим окна
	opt_window_mode.clear()
	opt_window_mode.add_item(_tr("SETTINGS_MODE_WINDOWED", "ОКОННЫЙ"), 0)
	opt_window_mode.add_item(_tr("SETTINGS_MODE_BORDERLESS", "ОКНО БЕЗ РАМОК"), 1)
	opt_window_mode.add_item(_tr("SETTINGS_MODE_FULLSCREEN", "ПОЛНЫЙ ЭКРАН"), 2)
	opt_window_mode.add_item(_tr("SETTINGS_MODE_EXCLUSIVE", "ЭКСКЛЮЗИВНЫЙ ПОЛНЫЙ"), 3)
	opt_window_mode.select(_settings_mgr.current_window_mode)

	# 3. V-Sync
	opt_vsync.clear()
	opt_vsync.add_item(_tr("SETTINGS_VSYNC_OFF", "ВЫКЛ"), 0)
	opt_vsync.add_item(_tr("SETTINGS_VSYNC_ON", "ВКЛ"), 1)
	opt_vsync.add_item(_tr("SETTINGS_VSYNC_ADAPTIVE", "АДАПТИВНАЯ"), 2)
	opt_vsync.select(_settings_mgr.current_vsync)

	# 4. Масштаб интерфейса
	opt_ui_scale.clear()
	var scales = _settings_mgr.UI_SCALES if _settings_mgr != null else [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
	var scale_idx = 1
	for i in range(scales.size()):
		var s = scales[i]
		opt_ui_scale.add_item("%d%%" % int(s * 100), i)
		if is_equal_approx(s, _settings_mgr.current_ui_scale):
			scale_idx = i
	opt_ui_scale.select(scale_idx)


func _populate_languages() -> void:
	for c in lang_buttons_container.get_children():
		c.queue_free()
	_lang_radio_buttons.clear()

	if _loc_mgr == null:
		return

	var locales = _loc_mgr.get_available_locales()
	for item in locales:
		var btn = Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_ALL
		btn.custom_minimum_size = Vector2(0, 38)
		var code = str(item.get("code", "ru"))
		btn.set_meta("locale_code", code)
		_lang_radio_buttons.append(btn)
		lang_buttons_container.add_child(btn)
		btn.pressed.connect(_on_language_selected.bind(code))

	_refresh_lang_buttons()


func _refresh_lang_buttons() -> void:
	var active_code = _loc_mgr.get_locale() if _loc_mgr != null else "ru"
	for btn in _lang_radio_buttons:
		var code = str(btn.get_meta("locale_code", ""))
		var is_active = (code == active_code)
		var radio_glyph = "(•)" if is_active else "( )"
		var badge = "[ACTIVE]" if is_active else "[READY]"

		var loc_name = code.to_upper()
		if _loc_mgr != null:
			for l in _loc_mgr.get_available_locales():
				if l["code"] == code:
					loc_name = l.get("name", loc_name)
					break

		btn.text = " %s %-22s %s" % [radio_glyph, loc_name.to_upper(), badge]
		if is_active:
			btn.add_theme_color_override("font_color", COLOR_PHOSPHOR_ACTIVE)
		else:
			btn.add_theme_color_override("font_color", COLOR_PHOSPHOR_MUTED)


# ==============================================================================
# СИНХРОНИЗАЦИЯ UI И НАСТРОЕК
# ==============================================================================

func _sync_ui_with_settings() -> void:
	var crt = _settings_mgr.crt_settings
	chk_crt_enable.button_pressed = crt.get("enabled", true)
	slider_curvature.value = crt.get("curvature", 0.03)
	val_curvature.text = "%.3f" % slider_curvature.value
	slider_scanlines.value = crt.get("scanline_intensity", 0.16)
	val_scanlines.text = "%.2f" % slider_scanlines.value
	chk_auto_scanlines.button_pressed = crt.get("scanline_auto_density", true)
	slider_glow.value = crt.get("brightness_boost", 1.05)
	val_glow.text = "%.2f" % slider_glow.value
	slider_aberration.value = crt.get("chromatic_aberration", 0.002)
	val_aberration.text = "%.4f" % slider_aberration.value

	var audio = _settings_mgr.audio_settings
	slider_master.value = audio.get("master_volume", 0.8)
	val_master.text = "%d%%" % int(slider_master.value * 100)
	slider_sfx.value = audio.get("sfx_volume", 0.85)
	val_sfx.text = "%d%%" % int(slider_sfx.value * 100)
	slider_ambient.value = audio.get("ambient_volume", 0.7)
	val_ambient.text = "%d%%" % int(slider_ambient.value * 100)

	_update_display_info_label()


func _update_display_info_label() -> void:
	var scr = DisplayServer.window_get_current_screen()
	var scr_sz = DisplayServer.screen_get_size(scr)
	var win_sz = DisplayServer.window_get_size()
	var aspect = float(win_sz.x) / float(maxi(1, win_sz.y))
	lbl_display_info.text = "ФИЗИЧЕСКИЙ ЭКРАН: %dx%d // ОКНО ТЕРМИНАЛА: %dx%d (АСПЕКТ: %.2f:1)" % [
		scr_sz.x, scr_sz.y, win_sz.x, win_sz.y, aspect
	]


# ==============================================================================
# ДЕЙСТВИЯ: ПРИМЕНЕНИЕ И ТЕСТИРОВАНИЕ РАЗРЕШЕНИЯ
# ==============================================================================

func _on_apply_display_pressed() -> void:
	var res_idx = opt_resolution.get_selected_id()
	if res_idx < 0 or res_idx >= _cached_resolutions.size():
		return
	var target_res = _cached_resolutions[res_idx]
	var target_mode = opt_window_mode.get_selected_id()
	var target_vsync = opt_vsync.get_selected_id()

	_play_relay_click(1100.0, 0.05)
	_settings_mgr.apply_vsync(target_vsync)

	# Если меняется режим на полноэкранный или другое разрешение, запускаем защитный таймер
	if target_mode != _settings_mgr.current_window_mode or target_res != _settings_mgr.current_resolution:
		revert_overlay.visible = true
		_settings_mgr.test_display_mode(target_res, target_mode, 15)
	else:
		_settings_mgr.apply_window_mode(target_mode)
		_settings_mgr.apply_resolution(target_res)
		_update_display_info_label()
		_apply_crt()


func _on_ui_scale_selected(idx: int) -> void:
	var scales = _settings_mgr.UI_SCALES if _settings_mgr != null else [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
	if idx >= 0 and idx < scales.size():
		var scale_val = scales[idx]
		_settings_mgr.apply_ui_scale(scale_val)
		_play_relay_click(950.0, 0.03)


func _on_confirm_resolution_pressed() -> void:
	revert_overlay.visible = false
	_settings_mgr.confirm_display_mode()
	_play_relay_click(1250.0, 0.06)
	_update_display_info_label()
	_apply_crt()
	status_bar_label.text = "[ ВИДЕОРЕЖИМ УСПЕШНО ЗАФИКСИРОВАН ]"


func _on_revert_resolution_pressed() -> void:
	revert_overlay.visible = false
	_settings_mgr.revert_display_mode()
	_play_relay_click(600.0, 0.04)
	_populate_options()
	_update_display_info_label()
	_apply_crt()
	status_bar_label.text = "[ ИЗМЕНЕНИЯ ВИДЕОРЕЖИМА ОТМЕНЕНЫ ]"


func _on_revert_tick(seconds_left: int) -> void:
	revert_msg_label.text = _tr("SETTINGS_REVERT_COUNTDOWN", "СОХРАНИТЬ НОВОЕ РАЗРЕШЕНИЕ? АВТООТКАТ ЧЕРЕЗ: %d СЕК") % seconds_left


func _on_revert_cancelled() -> void:
	revert_overlay.visible = false


func _on_crt_toggled(toggled: bool) -> void:
	_settings_mgr.set_crt_enabled(toggled)
	_apply_crt()
	_play_relay_click(1000.0 if toggled else 500.0, 0.03)


func _on_language_selected(code: String) -> void:
	if _loc_mgr != null:
		_loc_mgr.set_locale(code, false)
		_refresh_lang_buttons()
		_update_localized_texts()
		_populate_options()
		_play_relay_click(900.0, 0.04)
		status_bar_label.text = "[ СИСТЕМНЫЙ ЯЗЫК: %s ]" % code.to_upper()


func _on_save_bios_pressed() -> void:
	_play_relay_click(1300.0, 0.07)
	_settings_mgr.save_settings()
	if _loc_mgr != null:
		_loc_mgr.save_to_config()
	status_bar_label.text = _tr("SETTINGS_SAVED_SUCCESS", "ПАРАМЕТРЫ ДИСПЛЕЯ И ЗВУКА УСПЕШНО ЗАПИСАНЫ В EEPROM BIOS")
	settings_saved.emit()


func _on_back_pressed() -> void:
	_play_relay_click(550.0, 0.03)
	_settings_mgr.save_settings()
	if _loc_mgr != null:
		_loc_mgr.save_to_config()
	closed.emit()


func _on_save_game_pressed() -> void:
	var tm = _find_turn_manager()
	if tm != null and tm.has_method("save_game"):
		var ok = tm.save_game("user://savegame.json")
		if ok:
			_play_relay_click(1200.0, 0.08)
			status_bar_label.text = "[ СИСТЕМА: ИГРА УСПЕШНО СОХРАНЕНА (ХОД %d) -> user://savegame.json ]" % tm.get("current_turn")
		else:
			_play_relay_click(300.0, 0.15)
			status_bar_label.text = "[ ОШИБКА: НЕ УДАЛОСЬ СОХРАНИТЬ ИГРУ ]"
	else:
		_play_relay_click(300.0, 0.15)
		status_bar_label.text = "[ ВНИМАНИЕ: АКТИВНАЯ ИГРОВАЯ СЕССИЯ НЕ НАЙДЕНА ]"


func _on_load_game_pressed() -> void:
	var tm = _find_turn_manager()
	if tm != null and tm.has_method("load_game"):
		var ok = tm.load_game("user://savegame.json")
		if ok:
			_play_relay_click(900.0, 0.08)
			status_bar_label.text = "[ СИСТЕМА: ИГРА УСПЕШНО ЗАГРУЖЕНА (ХОД %d) ]" % tm.get("current_turn")
			await get_tree().create_timer(0.3).timeout
			_on_back_pressed()
		else:
			_play_relay_click(300.0, 0.15)
			status_bar_label.text = "[ ОШИБКА: АРХИВ user://savegame.json НЕ НАЙДЕН ]"
	else:
		_play_relay_click(300.0, 0.15)
		status_bar_label.text = "[ ВНИМАНИЕ: АКТИВНАЯ ИГРОВАЯ СЕССИЯ НЕ НАЙДЕНА ]"


func _find_turn_manager() -> Node:
	var p = get_parent()
	while p != null:
		if p.has_node("TurnManager"):
			return p.get_node("TurnManager")
		if "turn_manager" in p and p.turn_manager != null:
			return p.turn_manager
		p = p.get_parent()
	var root_node = get_tree().root
	return root_node.find_child("TurnManager", true, false)


func _on_locale_changed(_locale_code: String) -> void:
	_update_localized_texts()
	_populate_options()
	_refresh_lang_buttons()


func _apply_crt() -> void:
	if crt_overlay != null and crt_overlay.material is ShaderMaterial:
		_settings_mgr.apply_crt_to_material(crt_overlay.material as ShaderMaterial)


# ==============================================================================
# ОБНОВЛЕНИЕ ТЕКСТОВ
# ==============================================================================

func _update_localized_texts() -> void:
	header_title.text = _tr("SETTINGS_TITLE", "=== КОНФИГУРАЦИЯ СИСТЕМЫ И ПАРАМЕТРЫ ДИСПЛЕЯ ===")
	header_sub.text = _tr("SETTINGS_SUBTITLE", "МОДУЛЬ УПРАВЛЕНИЯ ВИДЕОСИСТЕМОЙ, CRT-ТЕРМИНАЛОМ И ЗВУКОМ")

	tab_btn_display.text = "[ %s ]" % _tr("SETTINGS_TAB_DISPLAY", "1. ДИСПЛЕЙ")
	tab_btn_crt.text = "[ %s ]" % _tr("SETTINGS_TAB_CRT", "2. ЭЛТ / CRT")
	tab_btn_audio.text = "[ %s ]" % _tr("SETTINGS_TAB_AUDIO", "3. ЗВУК")
	tab_btn_language.text = "[ %s ]" % _tr("SETTINGS_TAB_LANGUAGE", "4. ЯЗЫКИ")

	btn_apply_display.text = _tr("SETTINGS_APPLY", "[ ПРИМЕНИТЬ ]")
	btn_save_bios.text = _tr("SETTINGS_SAVE_BIOS", "[ ЗАПИСАТЬ В EEPROM BIOS ]")
	btn_back.text = _tr("SETTINGS_BACK", "[ < ВЕРНУТЬСЯ ]")

	btn_confirm_res.text = _tr("SETTINGS_BTN_KEEP", "[ СОХРАНИТЬ ]")
	btn_revert_res.text = _tr("SETTINGS_BTN_REVERT", "[ ОТМЕНИТЬ ]")


func _tr(key: String, fallback: String = "") -> String:
	if _loc_mgr != null:
		return _loc_mgr.tr_key(key, fallback)
	return fallback if not fallback.is_empty() else key


# ==============================================================================
# ЗВУКОВОЙ СИНТЕЗАТОР РЕЛЕ
# ==============================================================================

func _init_audio_synth() -> void:
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.name = "TerminalRelayPlayer"
	_audio_gen = AudioStreamGenerator.new()
	_audio_gen.mix_rate = 22050
	_audio_gen.buffer_length = 0.1
	_sfx_player.stream = _audio_gen
	_sfx_player.volume_db = -6.0
	add_child(_sfx_player)
	_sfx_player.play()


func _play_relay_click(pitch_hz: float = 880.0, duration_sec: float = 0.035) -> void:
	if _sfx_player == null or not _sfx_player.playing:
		return

	var playback: AudioStreamGeneratorPlayback = _sfx_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return

	var sample_rate = _audio_gen.mix_rate
	var total_frames = int(duration_sec * sample_rate)
	var available = playback.get_frames_available()
	var frames_to_push = mini(total_frames, available)

	for i in range(frames_to_push):
		var t = float(i) / float(sample_rate)
		var decay = exp(-t * 95.0)
		var tone = sin(2.0 * PI * pitch_hz * t)
		var contact_noise = (randf() * 2.0 - 1.0) * exp(-t * 220.0) * 0.4
		var sample = (tone * 0.6 + contact_noise) * decay
		playback.push_frame(Vector2(sample, sample))
