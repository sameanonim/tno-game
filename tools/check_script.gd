extends SceneTree

func _init() -> void:
	var script = load("res://core/data/directive_resource.gd")
	if script == null:
		print("FAILED to load script")
	else:
		print("Loaded script: ", script)
		var inst = script.new()
		print("Instantiated: ", inst)
	quit(0)
