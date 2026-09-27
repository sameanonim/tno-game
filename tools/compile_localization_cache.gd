extends SceneTree

func _init() -> void:
	print("[CompileLoc] Starting compilation of binary localization caches...")
	var locales = ["ru", "en", "de"]
	
	for loc in locales:
		var json_path = "res://data/localization/strings_%s.json" % loc
		var bin_path = "res://data/localization/strings_%s.bin" % loc
		
		if not FileAccess.file_exists(json_path):
			print("[CompileLoc] Warning: %s does not exist." % json_path)
			continue
			
		var t0 = Time.get_ticks_msec()
		var file = FileAccess.open(json_path, FileAccess.READ)
		var text = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		if json.parse(text) != OK:
			push_error("[CompileLoc] Failed to parse %s: %s" % [json_path, json.get_error_message()])
			continue
			
		var root = json.data as Dictionary
		if root == null:
			continue
			
		var strings = root.get("strings", {})
		var t_parsed = Time.get_ticks_msec()
		print("[CompileLoc] Parsed %s (%d keys) in %d ms" % [loc, strings.size(), (t_parsed - t0)])
		
		# Save binary cache
		var bin_file = FileAccess.open(bin_path, FileAccess.WRITE)
		if bin_file != null:
			bin_file.store_var(strings, true)
			bin_file.close()
			var t_saved = Time.get_ticks_msec()
			print("[CompileLoc] Saved %s in %d ms" % [bin_path, (t_saved - t_parsed)])
			
	print("[CompileLoc] Compilation complete!")
	quit()
