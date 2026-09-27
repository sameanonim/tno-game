extends SceneTree

func _init() -> void:
	print("--- TESTING SETTINGS_LANGUAGE SCENE INSTANTIATION ---")
	var packed = load("res://ui/screens/settings_language.tscn") as PackedScene
	if packed == null:
		push_error("Failed to load settings_language.tscn")
		quit(1)
		return
	var instance = packed.instantiate()
	root.add_child(instance)
	print("Instantiated successfully. Selected locale:", instance._selected_locale)
	instance._on_language_selected("en")
	print("Switched to en. Header:", instance.header_label.text)
	instance._on_language_selected("de")
	print("Switched to de. Header:", instance.header_label.text)
	instance._on_language_selected("ru")
	print("Switched to ru. Header:", instance.header_label.text)
	print("--- SCENE TEST PASSED ---")
	quit(0)
