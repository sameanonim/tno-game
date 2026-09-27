extends Node

##
## SettingsManager: Централизованный менеджер графики, дисплея, звука и BIOS-конфигурации (Autoload)
##
## Обеспечивает:
## 1. Смену экранных разрешений (1280x720 -> 4K UHD) и нативного разрешения монитора
## 2. Режимы окна: Оконный, Без рамок, Полноэкранный, Эксклюзивный полный экран
## 3. Вертикальную синхронизацию (V-Sync): Выкл, Вкл, Адаптивная
## 4. Динамическое масштабирование интерфейса (UI Scale / content_scale_factor)
## 5. Коррекцию параметров CRT-постпроцессинга под соотношение сторон и вертикальное разрешение
## 6. Защищенный таймер отката разрешения при нестабильных видеорежимах (Safety Revert Timer)
## 7. Чтение и запись в энергонезависимую память BIOS (user://settings.cfg)
##

signal resolution_changed(new_res: Vector2i)
signal window_mode_changed(new_mode: int)
signal vsync_mode_changed(new_mode: int)
signal ui_scale_changed(new_scale: float)
signal crt_param_changed(param_name: String, value: Variant)
signal crt_enabled_changed(is_enabled: bool)
signal audio_volume_changed(bus_name: String, volume_linear: float)
signal settings_saved()
signal revert_countdown_tick(seconds_left: int)
signal revert_cancelled()

const CONFIG_PATH: String = "user://settings.cfg"

# Стандартный банк разрешений для геополитического терминала
const PRESET_RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),   # 16:9 HD
	Vector2i(1366, 768),   # 16:9 WXGA
	Vector2i(1600, 900),   # 16:9 HD+
	Vector2i(1920, 1080),  # 16:9 Full HD (Стандарт)
	Vector2i(1920, 1200),  # 16:10 WUXGA
	Vector2i(2560, 1080),  # 21:9 UltraWide FHD
	Vector2i(2560, 1440),  # 16:9 2K QHD
	Vector2i(3440, 1440),  # 21:9 UltraWide QHD
	Vector2i(3840, 2160)   # 16:9 4K UHD
]

const UI_SCALES: Array[float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

enum WindowModeType {
	WINDOWED = 0,
	BORDERLESS_WINDOWED = 1,
	FULLSCREEN = 2,
	EXCLUSIVE_FULLSCREEN = 3
}

enum VSyncType {
	DISABLED = 0,
	ENABLED = 1,
	ADAPTIVE = 2
}

static var instance = null

# --- ТЕКУЩИЕ ДЕЙСТВУЮЩИЕ НАСТРОЙКИ ---
var current_resolution: Vector2i = Vector2i(1920, 1080)
var current_window_mode: int = WindowModeType.WINDOWED
var current_vsync: int = VSyncType.ENABLED
var current_ui_scale: float = 1.0
var max_fps: int = 0 # 0 = Unlimited

var crt_settings: Dictionary = {
	"enabled": true,
	"curvature": 0.03,
	"vignette_strength": 0.85,
	"scanline_intensity": 0.16,
	"scanline_auto_density": true,
	"scanline_count": 540.0,
	"chromatic_aberration": 0.002,
	"phosphor_tint": Color(0.95, 1.0, 0.98, 1.0),
	"brightness_boost": 1.05
}

var audio_settings: Dictionary = {
	"master_volume": 0.8,
	"sfx_volume": 0.85,
	"ambient_volume": 0.7
}

# --- МЕХАНИЗМ БЕЗОПАСНОГО ОТКАТА (REVERT TIMER) ---
var _backup_resolution: Vector2i = Vector2i(1920, 1080)
var _backup_window_mode: int = WindowModeType.WINDOWED
var _revert_timer: Timer = null
var _revert_seconds_left: int = 0
var _is_testing_display_mode: bool = false


func _init() -> void:
	if instance == null:
		instance = self


func _enter_tree() -> void:
	if instance == null:
		instance = self


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_revert_timer()
	load_settings()
	apply_all_settings()


static func get_instance() -> Node:
	return instance


# ==============================================================================
# ЗАГРУЗКА И СОХРАНЕНИЕ В CONFIGFILE (user://settings.cfg)
# ==============================================================================

func load_settings() -> void:
	var cfg = ConfigFile.new()
	if not FileAccess.file_exists(CONFIG_PATH) or cfg.load(CONFIG_PATH) != OK:
		print("[SettingsManager] Config file not found. Setting defaults based on monitor.")
		_detect_default_display_settings()
		return

	# 1. Дисплей
	var res_w = int(cfg.get_value("display", "resolution_width", 1920))
	var res_h = int(cfg.get_value("display", "resolution_height", 1080))
	current_resolution = Vector2i(maxi(800, res_w), maxi(600, res_h))
	current_window_mode = clampi(int(cfg.get_value("display", "window_mode", WindowModeType.WINDOWED)), 0, 3)
	current_vsync = clampi(int(cfg.get_value("display", "vsync_mode", VSyncType.ENABLED)), 0, 2)
	current_ui_scale = clampf(float(cfg.get_value("display", "ui_scale", 1.0)), 0.5, 3.0)
	max_fps = int(cfg.get_value("display", "max_fps", 0))

	# 2. CRT-шейдер
	crt_settings["enabled"] = bool(cfg.get_value("crt", "enabled", true))
	crt_settings["curvature"] = float(cfg.get_value("crt", "curvature", 0.03))
	crt_settings["vignette_strength"] = float(cfg.get_value("crt", "vignette_strength", 0.85))
	crt_settings["scanline_intensity"] = float(cfg.get_value("crt", "scanline_intensity", 0.16))
	crt_settings["scanline_auto_density"] = bool(cfg.get_value("crt", "scanline_auto_density", true))
	crt_settings["scanline_count"] = float(cfg.get_value("crt", "scanline_count", 540.0))
	crt_settings["chromatic_aberration"] = float(cfg.get_value("crt", "chromatic_aberration", 0.002))
	crt_settings["brightness_boost"] = float(cfg.get_value("crt", "brightness_boost", 1.05))

	# 3. Аудио
	audio_settings["master_volume"] = clampf(float(cfg.get_value("audio", "master_volume", 0.8)), 0.0, 1.0)
	audio_settings["sfx_volume"] = clampf(float(cfg.get_value("audio", "sfx_volume", 0.85)), 0.0, 1.0)
	audio_settings["ambient_volume"] = clampf(float(cfg.get_value("audio", "ambient_volume", 0.7)), 0.0, 1.0)

	print("[SettingsManager] Loaded configuration from BIOS: Res=%dx%d, Mode=%d, VSync=%d, UIScale=%.2f" % [
		current_resolution.x, current_resolution.y, current_window_mode, current_vsync, current_ui_scale
	])


func save_settings() -> void:
	var cfg = ConfigFile.new()
	if FileAccess.file_exists(CONFIG_PATH):
		var _load_err = cfg.load(CONFIG_PATH)

	# Сохраняем дисплей
	cfg.set_value("display", "resolution_width", current_resolution.x)
	cfg.set_value("display", "resolution_height", current_resolution.y)
	cfg.set_value("display", "window_mode", current_window_mode)
	cfg.set_value("display", "vsync_mode", current_vsync)
	cfg.set_value("display", "ui_scale", current_ui_scale)
	cfg.set_value("display", "max_fps", max_fps)

	# Сохраняем CRT
	for k in crt_settings.keys():
		cfg.set_value("crt", k, crt_settings[k])

	# Сохраняем аудио
	for k in audio_settings.keys():
		cfg.set_value("audio", k, audio_settings[k])

	cfg.set_value("system", "last_saved_unix", Time.get_unix_time_from_system())

	var err = cfg.save(CONFIG_PATH)
	if err == OK:
		print("[SettingsManager] Configuration written to EEPROM BIOS: %s" % CONFIG_PATH)
		settings_saved.emit()
	else:
		push_error("[SettingsManager] Failed to write settings to %s (Error %d)" % [CONFIG_PATH, err])


func _detect_default_display_settings() -> void:
	var screen_idx = DisplayServer.window_get_current_screen()
	var scr_size = DisplayServer.screen_get_size(screen_idx)
	if scr_size.x > 0 and scr_size.y > 0:
		# Если экран 1080p или выше, предлагаем 1920x1080 оконный или нативный
		if scr_size.x >= 1920 and scr_size.y >= 1080:
			current_resolution = Vector2i(1920, 1080)
		else:
			current_resolution = scr_size
	else:
		current_resolution = Vector2i(1920, 1080)
	current_window_mode = WindowModeType.WINDOWED
	current_vsync = VSyncType.ENABLED
	current_ui_scale = 1.0


# ==============================================================================
# ПРИМЕНЕНИЕ НАСТРОЕК
# ==============================================================================

func apply_all_settings() -> void:
	apply_window_mode(current_window_mode, false)
	apply_resolution(current_resolution, false)
	apply_vsync(current_vsync, false)
	apply_ui_scale(current_ui_scale, false)
	apply_audio_volumes()
	update_crt_scanline_density()


func apply_resolution(res: Vector2i, emit_signal: bool = true) -> void:
	current_resolution = res
	var screen_idx = DisplayServer.window_get_current_screen()
	var screen_rect = DisplayServer.screen_get_usable_rect(screen_idx)

	if current_window_mode == WindowModeType.WINDOWED:
		DisplayServer.window_set_size(current_resolution)
		# Центрируем окно на доступной области экрана
		var centered_pos = screen_rect.position + (screen_rect.size - current_resolution) / 2
		# Ограничиваем сверху, чтобы шапка окна не вылезла за экран
		centered_pos.y = maxi(centered_pos.y, screen_rect.position.y)
		DisplayServer.window_set_position(centered_pos)
	elif current_window_mode == WindowModeType.BORDERLESS_WINDOWED:
		DisplayServer.window_set_size(current_resolution)
		var centered_pos = screen_rect.position + (screen_rect.size - current_resolution) / 2
		DisplayServer.window_set_position(centered_pos)

	update_crt_scanline_density()
	if emit_signal:
		resolution_changed.emit(current_resolution)


func apply_window_mode(mode: int, emit_signal: bool = true) -> void:
	current_window_mode = mode
	match mode:
		WindowModeType.WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			apply_resolution(current_resolution, false)
		WindowModeType.BORDERLESS_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			var scr_size = DisplayServer.screen_get_size()
			DisplayServer.window_set_size(scr_size)
			DisplayServer.window_set_position(Vector2i.ZERO)
		WindowModeType.FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		WindowModeType.EXCLUSIVE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

	update_crt_scanline_density()
	if emit_signal:
		window_mode_changed.emit(current_window_mode)


func apply_vsync(mode: int, emit_signal: bool = true) -> void:
	current_vsync = mode
	match mode:
		VSyncType.DISABLED:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		VSyncType.ENABLED:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		VSyncType.ADAPTIVE:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)
	if emit_signal:
		vsync_mode_changed.emit(current_vsync)


func apply_ui_scale(scale_val: float, emit_signal: bool = true) -> void:
	current_ui_scale = clampf(scale_val, 0.5, 3.0)
	var root_viewport = get_tree().root
	if root_viewport != null:
		root_viewport.content_scale_factor = current_ui_scale
	if emit_signal:
		ui_scale_changed.emit(current_ui_scale)


func apply_audio_volumes() -> void:
	_set_bus_volume_linear("Master", audio_settings.get("master_volume", 0.8))
	_set_bus_volume_linear("SFX", audio_settings.get("sfx_volume", 0.85))
	_set_bus_volume_linear("Music", audio_settings.get("ambient_volume", 0.7))


func _set_bus_volume_linear(bus_name: String, vol_linear: float) -> void:
	var idx = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		var db = linear_to_db(clampf(vol_linear, 0.0001, 1.0))
		AudioServer.set_bus_volume_db(idx, db)
		AudioServer.set_bus_mute(idx, vol_linear <= 0.001)
	audio_volume_changed.emit(bus_name, vol_linear)


# ==============================================================================
# БЕЗОПАСНЫЙ ТАЙМЕР ОТКАТА РАЗРЕШЕНИЯ (SAFETY REVERT TIMER)
# ==============================================================================

func _setup_revert_timer() -> void:
	_revert_timer = Timer.new()
	_revert_timer.name = "SafetyRevertTimer"
	_revert_timer.one_shot = false
	_revert_timer.wait_time = 1.0
	_revert_timer.timeout.connect(_on_revert_timer_tick)
	add_child(_revert_timer)


func test_display_mode(target_res: Vector2i, target_mode: int, countdown_seconds: int = 15) -> void:
	if not _is_testing_display_mode:
		_backup_resolution = current_resolution
		_backup_window_mode = current_window_mode

	_is_testing_display_mode = true
	_revert_seconds_left = countdown_seconds

	apply_window_mode(target_mode)
	apply_resolution(target_res)

	_revert_timer.start()
	revert_countdown_tick.emit(_revert_seconds_left)


func confirm_display_mode() -> void:
	if _is_testing_display_mode:
		_revert_timer.stop()
		_is_testing_display_mode = false
		_backup_resolution = current_resolution
		_backup_window_mode = current_window_mode
		revert_cancelled.emit()
		save_settings()


func revert_display_mode() -> void:
	if _is_testing_display_mode:
		_revert_timer.stop()
		_is_testing_display_mode = false
		apply_window_mode(_backup_window_mode)
		apply_resolution(_backup_resolution)
		revert_cancelled.emit()


func is_testing_display_mode() -> bool:
	return _is_testing_display_mode


func _on_revert_timer_tick() -> void:
	_revert_seconds_left -= 1
	revert_countdown_tick.emit(_revert_seconds_left)
	if _revert_seconds_left <= 0:
		revert_display_mode()


# ==============================================================================
# УПРАВЛЕНИЕ CRT-ТЕРМИНАЛОМ И АВТО-ПЛОТНОСТЬЮ СКАНЛАЙНОВ
# ==============================================================================

func set_crt_param(param_name: String, value: Variant) -> void:
	crt_settings[param_name] = value
	crt_param_changed.emit(param_name, value)


func set_crt_enabled(enabled: bool) -> void:
	crt_settings["enabled"] = enabled
	crt_enabled_changed.emit(enabled)


func update_crt_scanline_density() -> void:
	if not crt_settings.get("scanline_auto_density", true):
		return

	# В 1080p эталоне 540 линий (1 линия через 2 пикселя)
	var h = float(current_resolution.y)
	var auto_scanlines = maxf(240.0, round(h * 0.5))
	crt_settings["scanline_count"] = auto_scanlines
	crt_param_changed.emit("scanline_count", auto_scanlines)


func apply_crt_to_material(mat: ShaderMaterial) -> void:
	if mat == null:
		return

	var is_on = crt_settings.get("enabled", true)
	if not is_on:
		mat.set_shader_parameter("curvature", 0.0)
		mat.set_shader_parameter("vignette_strength", 0.0)
		mat.set_shader_parameter("scanline_intensity", 0.0)
		mat.set_shader_parameter("chromatic_aberration", 0.0)
		mat.set_shader_parameter("flicker_strength", 0.0)
		mat.set_shader_parameter("brightness_boost", 1.0)
		return

	for k in crt_settings.keys():
		if k == "enabled" or k == "scanline_auto_density":
			continue
		mat.set_shader_parameter(k, crt_settings[k])

	# Передаем динамический аспект экрана для сохранения круглой линзы
	var aspect = float(current_resolution.x) / float(maxi(1, current_resolution.y))
	mat.set_shader_parameter("aspect_ratio", aspect)


# ==============================================================================
# ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ПОЛУЧЕНИЯ СПИСКА РАЗРЕШЕНИЙ
# ==============================================================================

func get_available_resolutions() -> Array[Vector2i]:
	var list: Array[Vector2i] = []
	var native_size = DisplayServer.screen_get_size()

	for res in PRESET_RESOLUTIONS:
		if res.x <= native_size.x and res.y <= native_size.y:
			list.append(res)

	# Добавляем нативное разрешение, если его нет в списке пресетов
	if not list.has(native_size) and native_size.x >= 800 and native_size.y >= 600:
		list.append(native_size)

	# Если монитор меньше 1280x720 (редкий случай), добавляем хотя бы его нативное
	if list.is_empty():
		list.append(native_size if native_size.x > 0 else Vector2i(1280, 720))

	# Сортировка по возрастанию пикселей
	list.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.x == b.x:
			return a.y < b.y
		return a.x < b.x
	)
	return list


func get_resolution_label(res: Vector2i) -> String:
	var aspect_str = _calculate_aspect_ratio_str(res.x, res.y)
	return "%d x %d [%s]" % [res.x, res.y, aspect_str]


func _calculate_aspect_ratio_str(w: int, h: int) -> String:
	var ratio = float(w) / float(maxi(1, h))
	if is_equal_approx(ratio, 16.0 / 9.0) or absf(ratio - 16.0/9.0) < 0.04:
		return "16:9"
	elif is_equal_approx(ratio, 16.0 / 10.0) or absf(ratio - 1.6) < 0.04:
		return "16:10"
	elif is_equal_approx(ratio, 21.0 / 9.0) or ratio > 2.2:
		return "21:9 ULTRAWIDE"
	elif is_equal_approx(ratio, 4.0 / 3.0) or absf(ratio - 4.0/3.0) < 0.04:
		return "4:3 CRT"
	elif is_equal_approx(ratio, 5.0 / 4.0):
		return "5:4"
	return "%.2f:1" % ratio
