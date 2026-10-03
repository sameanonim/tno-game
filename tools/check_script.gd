extends SceneTree

func _init() -> void:
	var scripts = [
		"res://core/data/directive_resource.gd",
		"res://core/data/germany/germany_campaign_state.gd",
		"res://core/systems/germany/kartenhaus_engine.gd",
		"res://core/systems/germany/zollverein_engine.gd",
		"res://core/systems/germany/warplans_engine.gd",
		"res://core/systems/germany/nuclear_custody_engine.gd",
		"res://core/systems/germany/germany_campaign_manager.gd",
		"res://ui/screens/germany/germany_terminal_screen.gd",
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
	
	# Test Germany Terminal Scene loading
	var scene = load("res://ui/screens/germany/germany_terminal_screen.tscn")
	if scene == null:
		print("FAILED to load scene: res://ui/screens/germany/germany_terminal_screen.tscn")
		quit(1)
		return
	var scene_inst = scene.instantiate()
	print("Loaded and instantiated scene: ", scene_inst.get_class())
	
	print("ALL SCRIPTS AND SCENES LOADED AND INSTANTIATED SUCCESSFULLY")
	quit(0)
