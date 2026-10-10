extends SceneTree

func _init() -> void:
	var scripts = [
		"res://tests/test_utils.gd",
		"res://tests/test_parliament_engine.gd",
		"res://tests/test_societal_laws.gd"
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
