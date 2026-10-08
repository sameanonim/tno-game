class_name PipelineExporterBridge
extends RefCounted

##
## PipelineExporterBridge: Мост между Godot 4 и автономной утилитой экспорта (tno_exporter.exe)
## ----------------------------------------------------------------------------------------
## Предоставляет API для запуска инкрементального экспорта данных, очистки дубликатов,
## упаковки данных стран и валидации целостности через OS.execute().
##

const EXPORTER_EXE_PROJECT: String = "tno_exporter.exe"
const EXPORTER_EXE_PIPELINE: String = "pipeline/tno_exporter.exe"
const LAUNCHER_PY: String = "pipeline/launcher.py"
const INTEGRITY_REPORT_PATH: String = "pipeline/db/integrity_report.json"


## Возвращает путь к исполняемому файлу или интерпретатору python
static func get_executable_command() -> Dictionary:
	var root_dir = ProjectSettings.globalize_path("res://")
	var exe_root = root_dir.path_join(EXPORTER_EXE_PROJECT)
	if FileAccess.file_exists("res://" + EXPORTER_EXE_PROJECT):
		return {"cmd": exe_root, "prefix_args": []}

	var exe_pipeline = root_dir.path_join(EXPORTER_EXE_PIPELINE)
	if FileAccess.file_exists("res://" + EXPORTER_EXE_PIPELINE):
		return {"cmd": exe_pipeline, "prefix_args": []}

	# Fallback на python интерпретатор
	var script_path = root_dir.path_join(LAUNCHER_PY)
	return {"cmd": "python", "prefix_args": [script_path]}


## Запускает команду экспортера с заданными аргументами
static func run_command(args: Array[String]) -> Dictionary:
	var exec_info = get_executable_command()
	var full_args: Array[String] = []
	for p in exec_info["prefix_args"]:
		full_args.append(str(p))
	for a in args:
		full_args.append(str(a))

	var output: Array = []
	print("[PipelineExporterBridge] Executing: %s %s" % [exec_info["cmd"], " ".join(full_args)])
	var exit_code = OS.execute(exec_info["cmd"], full_args, output, true)

	var output_text = output[0] if not output.is_empty() else ""
	return {
		"exit_code": exit_code,
		"output": output_text,
		"success": (exit_code == 0)
	}


## Очистка всех дублирующихся файлов
static func clean_duplicates() -> Dictionary:
	return run_command(["--clean-duplicates"])


## Экспорт изолированных пакетов стран (country.json, country.sqlite, directives, events, decisions)
static func export_country_packages(tags: Array[String] = []) -> Dictionary:
	var args: Array[String] = ["--package-countries"]
	if not tags.is_empty():
		args.append("--tags")
		args.append(",".join(tags))
	return run_command(args)


## Экспорт данных карты и LUT палитры
static func export_map() -> Dictionary:
	return run_command(["--map"])


## Экспорт только нарративных событий и суперсобытий
static func export_events() -> Dictionary:
	return run_command(["--events"])


## Экспорт только деревьев директив
static func export_directives() -> Dictionary:
	return run_command(["--directives"])


## Полный цикл экспорта всех подсистем
static func export_all() -> Dictionary:
	return run_command(["--all"])


## Загружает отчет целостности данных
static func get_integrity_report() -> Dictionary:
	if not FileAccess.file_exists("res://" + INTEGRITY_REPORT_PATH):
		return {}
	var file = FileAccess.open("res://" + INTEGRITY_REPORT_PATH, FileAccess.READ)
	if file == null:
		return {}
	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
		return json.data
	return {}
