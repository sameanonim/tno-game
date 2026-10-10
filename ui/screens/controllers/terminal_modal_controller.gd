class_name TerminalModalController
extends Node

##
## TerminalModalController: Диспетчер модальных событий, супер-ивентов и эпилогов
## ==============================================================================
## Отвечает за:
## 1. Отображение модальных событий (EventDialog) и создание кнопок выборов.
## 2. Безопасную валидацию (fail-safe auto-resolve при пустых опциях).
## 3. Вызов супер-ивентов (TNOSuperEventModal) и воспроизведение аудиодорожек.
## 4. Окно эпилога игры (Game Over Modal): победа/поражение, выход, режим наблюдателя.
## ==============================================================================

signal modal_choice_resolved(event: GameEvent, option_index: int)
signal super_event_opened(event_id: String)
signal super_event_concluded()
signal game_over_modal_closed()
signal return_to_main_menu_requested()

var event_dialog: PanelContainer = null
var event_overlay: Control = null
var event_title: Label = null
var event_classification: Label = null
var event_body: RichTextLabel = null
var event_options_container: VBoxContainer = null

var super_event_modal: TNOSuperEventModal = null
var current_modal_event: GameEvent = null
var game_over_modal: Control = null

const EVENT_PICTURE_SHADER = preload("res://shaders/event_picture_crt.gdshader")


func setup(
	overlay: Control,
	dialog: PanelContainer,
	lbl_title: Label,
	lbl_class: Label,
	body_text: RichTextLabel,
	options_vbox: VBoxContainer,
	se_modal: TNOSuperEventModal
) -> void:
	event_overlay = overlay
	event_dialog = dialog
	event_title = lbl_title
	event_classification = lbl_class
	event_body = body_text
	event_options_container = options_vbox
	super_event_modal = se_modal

	if super_event_modal != null and not super_event_modal.option_selected.is_connected(_on_super_event_option_selected):
		super_event_modal.option_selected.connect(_on_super_event_option_selected)


func display_modal_event(ev: GameEvent, player_state: CountryState) -> void:
	current_modal_event = ev
	if ev == null or event_overlay == null or event_dialog == null or event_options_container == null:
		return

	# Fail-safe проверка на пустые опции
	if ev.options.is_empty():
		push_warning("TerminalModalController: Modal event '%s' has no options. Auto-resolving." % ev.event_id)
		modal_choice_resolved.emit(ev, 0)
		return

	if event_title != null:
		var raw_title: String = ev.title
		var tr_title: String = raw_title
		if has_node("/root/LocalizationManager"):
			tr_title = get_node("/root/LocalizationManager").tr_key(raw_title, {}, raw_title)
		elif TranslationServer.translate(raw_title) != raw_title:
			tr_title = TranslationServer.translate(raw_title)
		event_title.text = tr_title
	if event_classification != null:
		event_classification.text = ev.classification
	if event_body != null:
		var raw_desc: String = ev.description
		var tr_desc: String = raw_desc
		if has_node("/root/LocalizationManager"):
			tr_desc = get_node("/root/LocalizationManager").tr_key(raw_desc, {}, raw_desc)
		elif TranslationServer.translate(raw_desc) != raw_desc:
			tr_desc = TranslationServer.translate(raw_desc)
		event_body.text = tr_desc

	# Отображение исторической иллюстрации события (Event Picture)
	var vbox: VBoxContainer = event_options_container.get_parent() as VBoxContainer
	if vbox != null:
		var pic_rect: TextureRect = vbox.get_node_or_null("EventPictureRect") as TextureRect
		var ev_tex: Texture2D = null
		if has_node("/root/AssetRegistry"):
			var ar = get_node("/root/AssetRegistry")
			if not ev.portrait_path.is_empty():
				ev_tex = ar.get_event_picture(ev.portrait_path)
			if ev_tex == null:
				ev_tex = ar.get_event_picture(ev.event_id)

		if ev_tex != null:
			if pic_rect == null:
				pic_rect = TextureRect.new()
				pic_rect.name = "EventPictureRect"
				pic_rect.custom_minimum_size = Vector2(0, 180)
				pic_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				pic_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				var mat := ShaderMaterial.new()
				mat.shader = EVENT_PICTURE_SHADER
				mat.set_shader_parameter("phosphor_tint", Color(0.20, 0.90, 0.65, 1.0))
				mat.set_shader_parameter("tint_mix", 0.40)
				mat.set_shader_parameter("scanline_intensity", 0.22)
				mat.set_shader_parameter("vignette_strength", 0.35)
				mat.set_shader_parameter("reveal_progress", 1.0)
				pic_rect.material = mat
				vbox.add_child(pic_rect)
				if event_body != null:
					vbox.move_child(pic_rect, event_body.get_index())
			pic_rect.texture = ev_tex
			pic_rect.visible = true
			if pic_rect.material is ShaderMaterial:
				var smat: ShaderMaterial = pic_rect.material as ShaderMaterial
				smat.set_shader_parameter("reveal_progress", 0.0)
				var tween = pic_rect.create_tween()
				tween.tween_method(func(v: float): smat.set_shader_parameter("reveal_progress", v), 0.0, 1.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		elif pic_rect != null:
			pic_rect.visible = false

	for child in event_options_container.get_children():
		child.queue_free()

	for i in range(ev.options.size()):
		var opt_idx = i
		var opt = ev.options[i]
		var opt_text: String = str(opt.get("text", opt.get("name", "")))
		if opt_text.is_empty():
			var n_key: String = str(opt.get("name_key", ""))
			if not n_key.is_empty():
				if has_node("/root/LocalizationManager"):
					opt_text = get_node("/root/LocalizationManager").tr_key(n_key, {}, n_key)
				else:
					var tr_opt = TranslationServer.translate(n_key)
					opt_text = tr_opt if tr_opt != n_key else n_key
		if opt_text.is_empty():
			opt_text = "ПРИНЯТЬ"

		var eval_res: Dictionary = GameEvent.evaluate_option_availability(opt, player_state)
		var can_afford: bool = bool(eval_res.get("allowed", true))

		var btn := Button.new()
		btn.text = opt_text
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.disabled = not can_afford
		var tip: String = str(eval_res.get("effects_tooltip", ""))
		if not tip.is_empty():
			btn.tooltip_text = tip
		TNOTheme.apply_button_style(btn, TNOTheme.COLOR_BORDER_AMBER, Color(0.12, 0.09, 0.04, 0.95))

		btn.pressed.connect(func():
			if has_node("/root/AudioManager"):
				get_node("/root/AudioManager").play_sfx("click_ok")
			_on_event_option_chosen(opt_idx)
		)
		event_options_container.add_child(btn)

	event_overlay.visible = true
	if event_dialog != null:
		event_dialog.visible = true
	event_overlay.move_to_front()
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("event_popup")


func _on_event_option_chosen(index: int) -> void:
	if event_overlay != null:
		event_overlay.visible = false
	var ev = current_modal_event
	current_modal_event = null
	modal_choice_resolved.emit(ev, index)


func show_super_event(event_id_or_title: String, quote: String = "", option: String = "", art_path: String = "", audio_path: String = "") -> void:
	if super_event_modal == null:
		return

	if quote.is_empty() and option.is_empty():
		super_event_modal.show_super_event_by_id(event_id_or_title)
	else:
		super_event_modal.show_super_event(event_id_or_title, quote, option, art_path, audio_path)

	super_event_opened.emit(event_id_or_title)


func _on_super_event_option_selected() -> void:
	super_event_concluded.emit()


func show_game_over_modal(
	parent_node: Node,
	victory: bool,
	reason: String,
	player_state: CountryState,
	turn_number: int,
	date_str: String
) -> void:
	if game_over_modal != null and is_instance_valid(game_over_modal):
		game_over_modal.visible = true
		return

	game_over_modal = Control.new()
	game_over_modal.name = "GameOverModalOverlay"
	game_over_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_over_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	game_over_modal.z_index = 30

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.04, 0.92)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	game_over_modal.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	game_over_modal.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 460)
	var border_col = Color(0.20, 0.95, 0.50, 0.95) if victory else Color(0.98, 0.22, 0.16, 0.95)
	var bg_col = Color(0.04, 0.07, 0.08, 0.98) if victory else Color(0.08, 0.03, 0.03, 0.98)
	TNOTheme.apply_box_style(panel, border_col, bg_col, 2)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var lbl_top := Label.new()
	lbl_top.text = tr("[ ВЫСШИЙ ВОЕННЫЙ СОВЕТ // СИСТЕМНЫЙ ЭПИЛОГ ]")
	lbl_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_top.add_theme_color_override("font_color", Color(0.5, 0.7, 0.65, 0.8))
	vbox.add_child(lbl_top)

	var lbl_status := Label.new()
	lbl_status.text = tr("★ ВЕЛИКАЯ ПОБЕДА ★") if victory else tr("▲ ГОСУДАРСТВЕННЫЙ КРАХ ▲")
	lbl_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_status.add_theme_color_override("font_color", border_col)
	lbl_status.add_theme_font_size_override("font_size", 24)
	vbox.add_child(lbl_status)

	var hs := HSeparator.new()
	vbox.add_child(hs)

	var lbl_info := Label.new()
	var c_tag = player_state.country_tag if player_state != null else "STATE"
	var c_name = player_state.country_name if player_state != null else "State"
	var l_name = player_state.leader_name if player_state != null else "Leader"
	var info_fmt = tr("ДЕРЖАВА: %s [%s] | ЛИДЕР: %s\nДАТА: %s | ХОДОВ ПРОЙДЕНО: %d")
	lbl_info.text = info_fmt % [c_name, c_tag, l_name, date_str, turn_number]
	lbl_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_info.add_theme_color_override("font_color", Color(0.85, 0.90, 0.88, 1.0))
	vbox.add_child(lbl_info)

	var rtl := RichTextLabel.new()
	rtl.custom_minimum_size = Vector2(650, 160)
	rtl.fit_content = false
	rtl.scroll_active = true
	rtl.text = reason
	rtl.add_theme_color_override("default_color", Color(0.80, 0.85, 0.85, 1.0))
	vbox.add_child(rtl)

	var btn_hbox := HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 24)
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_hbox)

	var btn_menu := Button.new()
	btn_menu.text = tr("[ ВЕРНУТЬСЯ В ГЛАВНОЕ МЕНЮ ]")
	btn_menu.custom_minimum_size = Vector2(240, 42)
	TNOTheme.apply_button_style(btn_menu, border_col, bg_col)
	btn_menu.pressed.connect(func():
		return_to_main_menu_requested.emit()
	)
	btn_hbox.add_child(btn_menu)

	var btn_obs := Button.new()
	btn_obs.text = tr("[ РЕЖИМ НАБЛЮДАТЕЛЯ (ОСМОТР) ]")
	btn_obs.custom_minimum_size = Vector2(240, 42)
	TNOTheme.apply_button_style(btn_obs, Color(0.4, 0.6, 0.7), Color(0.04, 0.08, 0.12))
	btn_obs.pressed.connect(func():
		game_over_modal.visible = false
		game_over_modal_closed.emit()
	)
	btn_hbox.add_child(btn_obs)

	parent_node.add_child(game_over_modal)
