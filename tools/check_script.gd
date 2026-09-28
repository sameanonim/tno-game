extends SceneTree

func _init() -> void:
	var scripts = [
		"res://core/data/directive_resource.gd",
		"res://ui/components/decisions_panel.gd",
		"res://ui/screens/gcw_operations_panel.gd",
		"res://ui/components/russian_smuta_panel.gd",
		"res://ui/screens/tno_economy_screen.gd",
		"res://ui/components/region_management_panel.gd"
	]
	for path in scripts:
		var script = load(path)
		if script == null:
			print("FAILED to load script: ", path)
			quit(1)
			return
		print("Loaded script: ", path)
		var inst = script.new()
		print("Instantiated: ", inst.get_class())
	print("ALL SCRIPTS LOADED AND INSTANTIATED SUCCESSFULLY")
	quit(0)
