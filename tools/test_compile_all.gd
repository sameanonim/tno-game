extends SceneTree

func _init() -> void:
	print("--- BEGINNING COMPILATION CHECK FOR ALL GD SCRIPTS ---")
	var dirs_to_check = ["res://core", "res://scripts", "res://ui"]
	var total_checked = 0
	var errors = 0
	
	for d in dirs_to_check:
		var files_to_scan = []
		_collect_gd_files(d, files_to_scan)
		
		for fpath in files_to_scan:
			total_checked += 1
			var scr: GDScript = load(fpath)
			if scr == null:
				print("ERROR: Failed to load: ", fpath)
				errors += 1
				continue
			var err = scr.reload()
			if err != OK:
				print("ERROR: Parse/compile error in ", fpath, " (code ", err, ")")
				errors += 1
	
	print("--- COMPILATION CHECK COMPLETE ---")
	print("Total scripts checked: ", total_checked)
	print("Total parse errors: ", errors)
	if errors > 0:
		print("FAILED with errors!")
		quit(1)
	else:
		print("SUCCESS: 0 parse errors across all scripts.")
		quit(0)

func _collect_gd_files(path: String, out_list: Array) -> void:
	var dir = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not file_name.begins_with("."):
			var full_path = path + "/" + file_name
			if dir.current_is_dir():
				_collect_gd_files(full_path, out_list)
			elif file_name.ends_with(".gd"):
				out_list.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()
