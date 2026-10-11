class_name TestUtils
extends TNOSimpleTest

##
## TestUtils: Юнит-тесты для базовых вспомогательных модулей core/utils/
## ==============================================================================


func test_json_file_helper_dict() -> void:
	var overrides: Dictionary = JSONFileHelper.load_json_dict("res://data/canonical_overrides.json")
	assert_false(overrides.is_empty(), "canonical_overrides.json должен загружаться в Dictionary")
	assert_true(overrides.has("USA"), "В overrides должен присутствовать тег USA")
	assert_true(overrides.has("GER"), "В overrides должен присутствовать тег GER")

	var missing: Dictionary = JSONFileHelper.load_json_dict("res://non_existent_file.json")
	assert_true(missing.is_empty(), "Несуществующий файл должен возвращать пустой Dictionary")


func test_json_file_helper_array() -> void:
	var theaters: Array = JSONFileHelper.load_json_array("res://data/theaters.json")
	assert_false(theaters.is_empty(), "theaters.json должен загружаться в Array")
	assert_true(theaters.size() >= 5, "theaters.json должен содержать как минимум 5 театров")


func test_color_utils_deterministic() -> void:
	var col_usa_1: Color = ColorUtils.tag_to_color("USA")
	var col_usa_2: Color = ColorUtils.tag_to_color("usa")
	assert_eq(col_usa_1, col_usa_2, "Генерация цвета должна быть регистронезависимой и детерминированной")

	var col_ger: Color = ColorUtils.tag_to_color("GER")
	assert_ne(col_usa_1, col_ger, "Разные теги должны давать разные цвета")

	var hex_col: Color = ColorUtils.hex_to_color("#FF8800")
	assert_approx_eq(hex_col.r, 1.0, 0.01, "Красный канал hex должен соответствовать 1.0")
	assert_approx_eq(hex_col.g, 0.533, 0.01, "Зеленый канал hex должен соответствовать ~0.533")

	var blended: Color = ColorUtils.blend_colors(Color.BLACK, Color.WHITE, 0.5)
	assert_approx_eq(blended.r, 0.5, 0.01, "Смешение черного и белого 50/50 должно давать 0.5")


func test_portrait_resolver() -> void:
	var usa_portrait: String = PortraitResolver.resolve_leader_portrait("USA", "res://assets/gfx/leaders/USA/USA_Richard_Nixon.png")
	assert_true(usa_portrait.ends_with(".png"), "Путь портрета должен оканчиваться на .png")
	assert_true(ResourceLoader.exists(usa_portrait) or FileAccess.file_exists(usa_portrait), "Портрет США должен существовать")

	var fallback_portrait: String = PortraitResolver.resolve_leader_portrait("XYZ")
	assert_false(fallback_portrait.is_empty(), "Фоллбэк портрет не должен быть пустым")
	assert_true(fallback_portrait.ends_with(".png") or fallback_portrait.ends_with(".svg"), "Фоллбэк должен быть валидным изображением")


func test_math_utils_safe_calculations() -> void:
	assert_approx_eq(MathUtils.safe_clampf(15.0, 0.0, 10.0), 10.0, 0.001, "safe_clampf с нормальными границами")
	assert_approx_eq(MathUtils.safe_clampf(15.0, 10.0, 0.0), 10.0, 0.001, "safe_clampf с перевернутыми границами min/max")

	assert_approx_eq(MathUtils.safe_ratio(10.0, 0.0, 99.0), 99.0, 0.001, "safe_ratio с нулем в знаменателе")
	assert_approx_eq(MathUtils.safe_ratio(10.0, 2.0), 5.0, 0.001, "safe_ratio нормальное деление")

	assert_approx_eq(MathUtils.round_to_decimals(3.14159, 2), 3.14, 0.001, "round_to_decimals 2 знака")
	assert_approx_eq(MathUtils.smooth_step(0.0, 1.0, 0.5), 0.5, 0.001, "smooth_step середина")


func test_logger_suppression() -> void:
	var prev_state = TNOLogger.is_console_logging_enabled()
	TNOLogger.set_console_logging(false)
	assert_false(TNOLogger.is_console_logging_enabled(), "Консольный вывод должен быть отключен")
	TNOLogger.mute()
	assert_eq(TNOLogger.min_level, TNOLogger.Level.NONE, "Уровень логера должен быть NONE при mute()")
	TNOLogger.unmute(TNOLogger.Level.WARN)
	assert_eq(TNOLogger.min_level, TNOLogger.Level.WARN, "Уровень логера должен восстанавливаться при unmute()")
	TNOLogger.set_console_logging(prev_state)


func test_leader_portrait_authentic_mode() -> void:
	var frame := LeaderPortraitFrame.new()
	frame._apply_mode_dimensions()
	assert_true(frame.authentic_portrait_mode, "По умолчанию портрет лидера должен отображаться в аутентичном режиме без искажений")
	assert_eq(frame.custom_minimum_size, Vector2(156, 210), "Размер рамки досье должен соответствовать каноничному 156x210")
	frame.free()


func test_focus_widget_enlarged_dimensions() -> void:
	var widget := FocusNodeWidget.new()
	widget._ready()
	assert_eq(widget.custom_minimum_size, Vector2(160, 145), "Размер виджета фокуса должен быть увеличен до 160x145")
	assert_not_null(widget.icon_rect, "icon_rect должен быть инициализирован")
	assert_eq(widget.icon_rect.custom_minimum_size, Vector2(80, 80), "Иконка фокуса должна иметь увеличенный размер 80x80")
	widget.free()


func test_map_globe_projection_properties() -> void:
	var map_ctrl := MapController.new()
	assert_true(map_ctrl.enable_globe_view, "Режим глобуса планеты должен быть включен по умолчанию")
	assert_approx_eq(map_ctrl.globe_zoom_threshold, 0.85, 0.01, "Порог начала перехода в глобус 0.85")
	assert_approx_eq(map_ctrl.globe_full_threshold, 0.38, 0.01, "Порог полного перехода в глобус 0.38")
	map_ctrl.free()
