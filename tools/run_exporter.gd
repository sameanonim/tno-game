extends SceneTree

##
## Godot Headless Runner: Запуск экспортёра TNO данных из консоли Godot
## Использование:
##   godot --headless -s tools/run_exporter.gd -- --clean
##   godot --headless -s tools/run_exporter.gd -- --all
##   godot --headless -s tools/run_exporter.gd -- --package-countries
##

const PipelineExporterBridge = preload("res://core/systems/pipeline_exporter_bridge.gd")

func _init() -> void:
	print("==================================================================")
	print("  TNO GODOT EXPORTER RUNNER")
	print("==================================================================")

	var user_args = OS.get_cmdline_user_args()
	if user_args.is_empty():
		print("Usage flags: --clean, --all, --package-countries, --map, --status")
		print("Defaulting to: --clean (clean duplicate files)")
		user_args = ["--clean"]

	var clean_only = user_args.has("--clean") or user_args.has("--clean-duplicates")
	var run_all = user_args.has("--all")
	var package_countries = user_args.has("--package-countries")
	var map_only = user_args.has("--map")
	var status_only = user_args.has("--status")

	if status_only:
		var report = PipelineExporterBridge.get_integrity_report()
		print("Integrity report:")
		print(JSON.stringify(report, "  "))
		quit(0)
		return

	var res: Dictionary = {}
	if clean_only:
		print("Starting clean duplicate files...")
		res = PipelineExporterBridge.clean_duplicates()
	elif run_all:
		print("Starting full pipeline export...")
		res = PipelineExporterBridge.export_all()
	elif package_countries:
		print("Starting country packaging...")
		res = PipelineExporterBridge.export_country_packages()
	elif map_only:
		print("Starting map extraction...")
		res = PipelineExporterBridge.export_map()
	else:
		print("Executing custom arguments: %s" % str(user_args))
		res = PipelineExporterBridge.run_command(user_args)

	print("Exit Code: %d" % int(res.get("exit_code", -1)))
	print("Output:")
	print(str(res.get("output", "")))

	if bool(res.get("success", false)):
		print(">>> TNO GODOT EXPORTER RUNNER FINISHED SUCCESSFULLY.")
		quit(0)
	else:
		printerr(">>> TNO GODOT EXPORTER RUNNER FAILED WITH EXIT CODE: %d" % int(res.get("exit_code", 1)))
		quit(int(res.get("exit_code", 1)))
