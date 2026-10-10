class_name EventPopup
extends DraggableWindow

##
## EventPopup: Модульное перетаскиваемое окно нарративных событий TNO
## ==============================================================================
## Предоставляет:
## 1. Свободное перемещение по экрану мышью за заголовок (Drag & Drop).
## 2. Поддержку сворачивания (Minimize) в компактную плашку для обзора карты.
## 3. Встроенный CRT-шейдер для исторической иллюстрации события.
## 4. Богатый BBCode-текст с локализацией и тултипами эффектов опций.
## 5. Аутентичное оформление Cold War Terminal в стилистике TNO.
## ==============================================================================

signal option_chosen(option_index: int)
signal minimized_changed(is_minimized: bool)

const EVENT_PICTURE_SHADER = preload("res://shaders/event_picture_crt.gdshader")

@onready var header_bar: HBoxContainer = $VBox/HeaderHBox
@onready var lbl_classification: Label = $VBox/HeaderHBox/ClassificationLabel
@onready var lbl_title: Label = $VBox/HeaderHBox/TitleLabel
@onready var btn_minimize: Button = $VBox/HeaderHBox/ActionsHBox/BtnMinimize
@onready var btn_center: Button = $VBox/HeaderHBox/ActionsHBox/BtnCenter

@onready var content_scroll: ScrollContainer = $VBox/ContentScroll
@onready var event_picture_rect: TextureRect = $VBox/ContentScroll/ContentVBox/EventPictureRect
@onready var body_text: RichTextLabel = $VBox/ContentScroll/ContentVBox/BodyText
@onready var options_container: VBoxContainer = $VBox/OptionsContainer
@onready var main_vbox: VBoxContainer = $VBox

var current_event: GameEvent = null
var is_minimized: bool = false
var _normal_min_size: Vector2 = Vector2(660, 420)


func _ready() -> void:
	super._ready()
	_apply_styling()
	_connect_internal_signals()


"""Применяет аутентичную терминальную палитру TNO.
"""
func _apply_styling() -> void:
	custom_minimum_size = _normal_min_size
	TNOTheme.apply_box_style(self, TNOTheme.COLOR_BORDER_AMBER, TNOTheme.COLOR_BG_DARK, 2)
	
	if btn_minimize != null:
		TNOTheme.apply_button_style(btn_minimize, TNOTheme.COLOR_BORDER_DIM, Color(0.08, 0.10, 0.12, 0.9))
	if btn_center != null:
		TNOTheme.apply_button_style(btn_center, TNOTheme.COLOR_BORDER_DIM, Color(0.08, 0.10, 0.12, 0.9))


"""Подключает сигналы управляющих кнопок окна.
"""
func _connect_internal_signals() -> void:
	if btn_minimize != null and not btn_minimize.pressed.is_connected(toggle_minimize):
		btn_minimize.pressed.connect(toggle_minimize)
	if btn_center != null and not btn_center.pressed.is_connected(center_in_viewport):
		btn_center.pressed.connect(center_in_viewport)


"""Отображает переданное игровое событие с валидацией опций и локализацией.
"""
func display_event(ev: GameEvent, player_state: CountryState) -> void:
	current_event = ev
	if ev == null:
		visible = false
		return

	# Гарантия наличия хотя бы одного выбора
	if ev.options.is_empty():
		ev.options.append({
			"name": "ПРИНЯТЬ К СВЕДЕНИЮ",
			"text": "ПРИНЯТЬ К СВЕДЕНИЮ",
			"name_key": "OK",
			"effects": {}
		})

	# 1. Заголовок и классификация
	if lbl_classification != null:
		lbl_classification.text = ev.classification if not ev.classification.is_empty() else "[TOP SECRET // PREKAS]"
	
	if lbl_title != null:
		var raw_title: String = ev.title
		var tr_title: String = raw_title
		if has_node("/root/LocalizationManager"):
			tr_title = get_node("/root/LocalizationManager").tr_key(raw_title, {}, raw_title)
		elif TranslationServer.translate(raw_title) != raw_title:
			tr_title = TranslationServer.translate(raw_title)
		lbl_title.text = tr_title

	# 2. Тело события
	if body_text != null:
		var raw_desc: String = ev.description
		var tr_desc: String = raw_desc
		if has_node("/root/LocalizationManager"):
			tr_desc = get_node("/root/LocalizationManager").tr_key(raw_desc, {}, raw_desc)
		elif TranslationServer.translate(raw_desc) != raw_desc:
			tr_desc = TranslationServer.translate(raw_desc)
		body_text.text = tr_desc

	# 3. Историческая иллюстрация
	_setup_picture(ev)

	# 4. Генерация кнопок вариантов решений
	_populate_options(ev, player_state)

	# 5. Разворачивание и плавное появление
	if is_minimized:
		toggle_minimize()

	visible = true
	bring_to_front()
	_animate_appearance()

	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("event_popup")


"""Настраивает и анимирует картинку события.
"""
func _setup_picture(ev: GameEvent) -> void:
	if event_picture_rect == null:
		return

	var ev_tex: Texture2D = null
	if has_node("/root/AssetRegistry"):
		var ar = get_node("/root/AssetRegistry")
		if not ev.portrait_path.is_empty():
			ev_tex = ar.get_event_picture(ev.portrait_path)
		if ev_tex == null:
			ev_tex = ar.get_event_picture(ev.event_id)

	if ev_tex != null:
		event_picture_rect.texture = ev_tex
		event_picture_rect.visible = true
		
		var mat := event_picture_rect.material as ShaderMaterial
		if mat == null:
			mat = ShaderMaterial.new()
			mat.shader = EVENT_PICTURE_SHADER
			event_picture_rect.material = mat
		
		mat.set_shader_parameter("phosphor_tint", Color(0.20, 0.90, 0.65, 1.0))
		mat.set_shader_parameter("tint_mix", 0.35)
		mat.set_shader_parameter("scanline_intensity", 0.20)
		mat.set_shader_parameter("vignette_strength", 0.30)
		mat.set_shader_parameter("reveal_progress", 0.0)
		
		var tw := create_tween()
		tw.tween_method(func(v: float): mat.set_shader_parameter("reveal_progress", v), 0.0, 1.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		event_picture_rect.visible = false


"""Создает интерактивные кнопки решений с тултипами эффектов.
"""
func _populate_options(ev: GameEvent, player_state: CountryState) -> void:
	if options_container == null:
		return

	for child in options_container.get_children():
		child.queue_free()

	for i in range(ev.options.size()):
		var opt_idx: int = i
		var opt: Dictionary = ev.options[i]
		var opt_text: String = str(opt.get("text", opt.get("name", "")))
		if opt_text.is_empty():
			var n_key: String = str(opt.get("name_key", ""))
			if not n_key.is_empty():
				if has_node("/root/LocalizationManager"):
					opt_text = get_node("/root/LocalizationManager").tr_key(n_key, {}, n_key)
				else:
					var tr_opt: String = TranslationServer.translate(n_key)
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
			_on_option_pressed(opt_idx)
		)
		options_container.add_child(btn)


"""Обработка выбора опции игроком.
"""
func _on_option_pressed(idx: int) -> void:
	visible = false
	option_chosen.emit(idx)


"""Переключает свернутое/развернутое состояние окна для обзора карты.
"""
func toggle_minimize() -> void:
	is_minimized = not is_minimized
	
	if content_scroll != null:
		content_scroll.visible = not is_minimized
	if options_container != null:
		options_container.visible = not is_minimized
	
	if is_minimized:
		custom_minimum_size = Vector2(_normal_min_size.x, 48)
		size = custom_minimum_size
		if btn_minimize != null:
			btn_minimize.text = "[+]"
			btn_minimize.tooltip_text = tr("Развернуть окно события")
	else:
		custom_minimum_size = _normal_min_size
		size = custom_minimum_size
		if btn_minimize != null:
			btn_minimize.text = "[_]"
			btn_minimize.tooltip_text = tr("Свернуть для обзора карты")

	minimized_changed.emit(is_minimized)


"""Плавная терминальная анимация появления окна.
"""
func _animate_appearance() -> void:
	modulate.a = 0.0
	scale = Vector2(0.97, 0.97)
	pivot_offset = size * 0.5
	
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
