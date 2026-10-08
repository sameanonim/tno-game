class_name TNOLogger
extends Node

##
## GameLogger: Глобальный синглтон структурированного логирования для TNOGame
##
## Обеспечивает единый интерфейс для логирования с уровнями серьёзности (DEBUG, INFO, WARN, ERROR),
## тегами подсистем, выводом в консоль Godot и опциональной записью в файл (user://logs/).
##
## Использование:
##   TNOLogger.info("EconomyEngine", "GDP recalculated: %.2f" % gdp)
##   TNOLogger.warn("ContentLoader", "Legacy manifest used as fallback")
##   TNOLogger.error("TurnManager", "player_state is null at phase: %s" % phase_name)
##

enum Level {
	DEBUG = 0,
	INFO = 1,
	WARN = 2,
	ERROR = 3
}

static var min_level: Level = Level.DEBUG
static var file_logging_enabled: bool = false
static var max_log_file_size: int = 5 * 1024 * 1024

static var _log_file: FileAccess = null
static var _log_file_path: String = ""
static var _log_file_size: int = 0
static var _instance: TNOLogger = null


func _init() -> void:
	if _instance == null:
		_instance = self


func _ready() -> void:
	if file_logging_enabled:
		_open_log_file()


func _exit_tree() -> void:
	_close_log_file()


# ==============================================================================
# PUBLIC API
# ==============================================================================

static func debug(tag: String, message: String) -> void:
	_log(Level.DEBUG, tag, message)


static func info(tag: String, message: String) -> void:
	_log(Level.INFO, tag, message)


static func warn(tag: String, message: String) -> void:
	_log(Level.WARN, tag, message)


static func error(tag: String, message: String) -> void:
	_log(Level.ERROR, tag, message)


static func set_min_level(level: Level) -> void:
	min_level = level


static func set_file_logging(enabled: bool) -> void:
	file_logging_enabled = enabled
	if enabled and _log_file == null:
		_open_log_file()
	elif not enabled and _log_file != null:
		_close_log_file()


# ==============================================================================
# INTERNAL
# ==============================================================================

static func _log(level: Level, tag: String, message: String) -> void:
	if level < min_level:
		return

	var level_str: String = _level_to_string(level)
	var timestamp: String = Time.get_datetime_string_from_system(false, true)
	var formatted: String = "[%s] [%s] [%s] %s" % [timestamp, level_str, tag, message]

	match level:
		Level.DEBUG:
			print(formatted)
		Level.INFO:
			print(formatted)
		Level.WARN:
			push_warning(formatted)
		Level.ERROR:
			push_error(formatted)

	if file_logging_enabled and _log_file != null:
		_write_to_file(formatted)


static func _level_to_string(level: Level) -> String:
	match level:
		Level.DEBUG:
			return "DEBUG"
		Level.INFO:
			return " INFO"
		Level.WARN:
			return " WARN"
		Level.ERROR:
			return "ERROR"
		_:
			return "?????"


static func _open_log_file() -> void:
	var dir_path: String = "user://logs"
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var date_str: String = Time.get_date_string_from_system().replace("-", "")
	_log_file_path = "%s/game_%s.log" % [dir_path, date_str]

	if FileAccess.file_exists(_log_file_path):
		_log_file = FileAccess.open(_log_file_path, FileAccess.READ_WRITE)
		if _log_file != null:
			_log_file_size = _log_file.get_length()
			_log_file.seek_end()
	else:
		_log_file = FileAccess.open(_log_file_path, FileAccess.WRITE)
		_log_file_size = 0

	if _log_file != null:
		_write_to_file("=== GameLogger session started ===")
	else:
		push_error("[GameLogger] Failed to open log file: %s" % _log_file_path)


static func _close_log_file() -> void:
	if _log_file != null:
		_write_to_file("=== GameLogger session ended ===")
		_log_file.close()
		_log_file = null


static func _write_to_file(line: String) -> void:
	if _log_file == null:
		return

	var data: String = line + "\n"
	_log_file.store_string(data)
	_log_file.flush()
	_log_file_size += data.length()

	if _log_file_size >= max_log_file_size:
		_rotate_log_file()


static func _rotate_log_file() -> void:
	_close_log_file()
	var date_str: String = Time.get_date_string_from_system().replace("-", "")
	var time_str: String = Time.get_time_string_from_system().replace(":", "")
	_log_file_path = "user://logs/game_%s_%s.log" % [date_str, time_str]
	_log_file = FileAccess.open(_log_file_path, FileAccess.WRITE)
	_log_file_size = 0
	if _log_file != null:
		_write_to_file("=== GameLogger rotated ===")
