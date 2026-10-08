class_name FocusTreeIndexer
extends RefCounted

##
## FocusTreeIndexer: Индексация и анализ национальных фокусов и дерев директив
## ==============================================================================
## Отвечает за:
## 1. Поиск стран с деревьями фокусов (модульные пакеты data/countries/TAG/directives, directives_data).
## 2. Проверку наличия уникального дерева директив у державы.
## 3. Сбор структурированного резюме (summary) дерева для UI (экран выбора, терминал).
## ==============================================================================

const COUNTRIES_BASE_DIR: String = "res://data/countries"


"""Возвращает список тегов всех стран, обладающих древами фокусов.
"""
static func get_tags_with_focus_trees(directives_data: Dictionary = {}) -> Array[String]:
	var tags_set: Dictionary = {}

	# 1. Канонические державы с богатым контентом TNO
	var canonical_powers = [
		"USA", "GER", "JAP", "WRS", "KOM", "VYT", "SAM", "PRM", "TYU", "SVR",
		"OMS", "TOM", "NOV", "KEM", "SBA", "IRK", "BRY", "CHT", "MAG", "AMR",
		"SPE", "BOR", "GOR", "HEY", "ITA", "IBR", "ENG", "BRG", "FRD", "TUR",
		"GNG", "MAN", "CHI", "THA", "SCO", "WAL", "IRE", "YUN", "BRA", "MEX", "NIC", "BUL", "UKR"
	]
	for c in canonical_powers:
		tags_set[c] = true

	# 2. Модульные пакеты с trees_index.json или существенным tree.json
	if DirAccess.dir_exists_absolute(COUNTRIES_BASE_DIR):
		var dir = DirAccess.open(COUNTRIES_BASE_DIR)
		if dir != null:
			dir.list_dir_begin()
			var fn = dir.get_next()
			while not fn.is_empty():
				if dir.current_is_dir() and not fn.begins_with("."):
					var c_tag = fn.to_upper()
					var idx_path = COUNTRIES_BASE_DIR.path_join(fn).path_join("directives").path_join("trees_index.json")
					var tree_path = COUNTRIES_BASE_DIR.path_join(fn).path_join("directives").path_join("tree.json")
					if FileAccess.file_exists(idx_path):
						tags_set[c_tag] = true
					elif FileAccess.file_exists(tree_path):
						var f = FileAccess.open(tree_path, FileAccess.READ)
						if f != null:
							var txt = f.get_as_text()
							f.close()
							if txt.length() > 500:
								tags_set[c_tag] = true
				fn = dir.get_next()
			dir.list_dir_end()

	# 3. Из directives_data (манифест extracted)
	var trees_by_tag = directives_data.get("trees_by_tag", {})
	for t in trees_by_tag.keys():
		tags_set[str(t).to_upper()] = true

	var priority_list: Array[String] = []
	var other_list: Array[String] = []
	for t in tags_set.keys():
		if t in canonical_powers:
			priority_list.append(t)
		else:
			other_list.append(t)

	priority_list.sort_custom(func(a, b): return canonical_powers.find(a) < canonical_powers.find(b))
	other_list.sort()

	var result: Array[String] = []
	result.append_array(priority_list)
	result.append_array(other_list)
	return result


"""Проверяет, обладает ли конкретная страна уникальным древом фокусов.
"""
static func has_focus_tree(tag: String, directives_data: Dictionary = {}) -> bool:
	var clean_tag = tag.to_upper().strip_edges()
	if clean_tag.is_empty():
		return false

	var pkg_idx = COUNTRIES_BASE_DIR.path_join(clean_tag).path_join("directives").path_join("trees_index.json")
	if FileAccess.file_exists(pkg_idx):
		return true

	var pkg_tree = COUNTRIES_BASE_DIR.path_join(clean_tag).path_join("directives").path_join("tree.json")
	if FileAccess.file_exists(pkg_tree):
		return true

	var trees_by_tag = directives_data.get("trees_by_tag", {})
	return trees_by_tag.has(clean_tag)


"""Извлекает структурированное резюме древа фокусов (название, число директив, стартовые цели).
"""
static func get_focus_tree_summary(tag: String, directives_data: Dictionary = {}) -> Dictionary:
	var clean_tag = tag.to_upper().strip_edges()
	var summary: Dictionary = {
		"has_tree": false,
		"tree_id": "",
		"tree_title": "",
		"total_trees": 1,
		"total_directives": 0,
		"categories": [],
		"starting_directives": []
	}

	if clean_tag.is_empty():
		return summary

	# 1. Попытка чтения из модульного пакета: directives/trees_index.json
	var pkg_index_path = COUNTRIES_BASE_DIR.path_join(clean_tag).path_join("directives").path_join("trees_index.json")
	if FileAccess.file_exists(pkg_index_path):
		var idx_data = _read_json(pkg_index_path)
		if idx_data is Array and not idx_data.is_empty():
			summary["has_tree"] = true
			summary["total_trees"] = idx_data.size()

			var chosen_tree_path := ""
			var chosen_tree_id := ""
			var total_all_dirs := 0
			for t_info in idx_data:
				var tid = str(t_info.get("tree_id", ""))
				total_all_dirs += int(t_info.get("total_directives", 0))
				if chosen_tree_path.is_empty() and (tid.contains("base") or tid.contains("initial") or tid.contains("shared") or tid.contains("1962")):
					chosen_tree_path = str(t_info.get("path", ""))
					chosen_tree_id = tid

			if chosen_tree_path.is_empty():
				chosen_tree_path = str(idx_data[0].get("path", ""))
				chosen_tree_id = str(idx_data[0].get("tree_id", ""))

			summary["tree_id"] = chosen_tree_id
			summary["tree_title"] = chosen_tree_id.replace("_", " ").to_upper()
			summary["total_directives"] = total_all_dirs if total_all_dirs > 0 else 50

			if FileAccess.file_exists(chosen_tree_path):
				var tree_data = _read_json_file(chosen_tree_path)
				var raw_title = str(tree_data.get("title", ""))
				if not raw_title.is_empty():
					summary["tree_title"] = raw_title

				var raw_nodes = tree_data.get("nodes", tree_data.get("directives", []))
				var dirs: Array = []
				if raw_nodes is Dictionary:
					dirs = raw_nodes.values()
				elif raw_nodes is Array:
					dirs = raw_nodes

				var cat_set: Dictionary = {}
				var starters: Array[Dictionary] = []
				for d in dirs:
					var cat = str(d.get("category", ""))
					if cat.is_empty():
						var d_id = str(d.get("id", d.get("directive_id", ""))).to_lower()
						if d_id.contains("saw") or d_id.contains("mil") or d_id.contains("army") or d_id.contains("navy"):
							cat = "military"
						elif d_id.contains("pol") or d_id.contains("pres") or d_id.contains("senate") or d_id.contains("bill"):
							cat = "politics"
						elif d_id.contains("econ") or d_id.contains("tax") or d_id.contains("ind"):
							cat = "economy"
						else:
							cat = "doctrine"
					cat_set[cat] = true

					var prereqs = d.get("prerequisites", [])
					if prereqs is Array and prereqs.is_empty() and starters.size() < 4:
						starters.append({
							"id": d.get("id", d.get("directive_id", "")),
							"title": d.get("title", ""),
							"description": d.get("description", ""),
							"icon_path": d.get("icon_path", ""),
							"icon_symbol": d.get("icon_symbol", "[★]"),
							"turns_required": d.get("turns_to_complete", d.get("turns_required", 1)),
							"cost_cap": d.get("cost_initial_cap", 0)
						})

				if cat_set.is_empty():
					cat_set["doctrine"] = true
				summary["categories"] = cat_set.keys()
				summary["starting_directives"] = starters
			return summary

	# 2. Попытка чтения из модульного пакета: directives/tree.json
	var pkg_tree_path = COUNTRIES_BASE_DIR.path_join(clean_tag).path_join("directives").path_join("tree.json")
	if FileAccess.file_exists(pkg_tree_path):
		var tree_data = _read_json_file(pkg_tree_path)
		var raw_nodes = tree_data.get("nodes", tree_data.get("directives", []))
		var dirs: Array = []
		if raw_nodes is Dictionary:
			dirs = raw_nodes.values()
		elif raw_nodes is Array:
			dirs = raw_nodes

		if not dirs.is_empty():
			summary["has_tree"] = true
			summary["total_trees"] = 1
			summary["total_directives"] = dirs.size()
			var tree_id = str(tree_data.get("tree_id", clean_tag + "_tree"))
			var raw_title = str(tree_data.get("title", ""))
			if raw_title.is_empty():
				raw_title = tree_id.replace("_", " ").to_upper()
			summary["tree_id"] = tree_id
			summary["tree_title"] = raw_title
			var cat_set: Dictionary = {}
			var starters: Array[Dictionary] = []
			for d in dirs:
				var cat = str(d.get("category", ""))
				if cat.is_empty():
					var d_id = str(d.get("id", d.get("directive_id", ""))).to_lower()
					if d_id.contains("saw") or d_id.contains("mil") or d_id.contains("army"):
						cat = "military"
					elif d_id.contains("pol") or d_id.contains("pres"):
						cat = "politics"
					elif d_id.contains("econ") or d_id.contains("ind"):
						cat = "economy"
					else:
						cat = "doctrine"
				cat_set[cat] = true
				var prereqs = d.get("prerequisites", [])
				if prereqs is Array and prereqs.is_empty() and starters.size() < 4:
					starters.append({
						"id": d.get("id", d.get("directive_id", "")),
						"title": d.get("title", ""),
						"description": d.get("description", ""),
						"icon_path": d.get("icon_path", ""),
						"icon_symbol": d.get("icon_symbol", "[★]"),
						"turns_required": d.get("turns_to_complete", d.get("turns_required", 1)),
						"cost_cap": d.get("cost_initial_cap", 0)
					})
			if cat_set.is_empty():
				cat_set["doctrine"] = true
			summary["categories"] = cat_set.keys()
			summary["starting_directives"] = starters
			return summary

	# 3. Legacy fallback (из directives_data)
	var trees_by_tag = directives_data.get("trees_by_tag", {})
	if trees_by_tag.has(clean_tag):
		var data = trees_by_tag[clean_tag]
		var c_trees = data.get("trees", {})
		var primary_id = data.get("primary_tree_id", "")
		var target_tree = c_trees.get(primary_id)
		if target_tree == null and not c_trees.is_empty():
			target_tree = c_trees.values()[0]
			if c_trees.keys().size() > 0:
				primary_id = c_trees.keys()[0]

		if target_tree != null:
			summary["has_tree"] = true
			summary["tree_id"] = primary_id
			var raw_title = target_tree.get("title", "")
			if raw_title.is_empty():
				raw_title = primary_id.replace("_", " ").to_upper()
			summary["tree_title"] = raw_title
			summary["total_trees"] = c_trees.size()

			var all_dirs = target_tree.get("directives", [])
			summary["total_directives"] = all_dirs.size()

			var cat_set: Dictionary = {}
			var starters: Array[Dictionary] = []
			for d in all_dirs:
				var cat = d.get("category", "doctrine")
				cat_set[cat] = true
				var prereqs = d.get("prerequisites", [])
				if prereqs is Array and prereqs.is_empty() and starters.size() < 4:
					starters.append({
						"id": d.get("directive_id", ""),
						"title": d.get("title", ""),
						"description": d.get("description", ""),
						"icon_path": d.get("icon_path", ""),
						"icon_symbol": d.get("icon_symbol", "[★]"),
						"turns_required": d.get("turns_required", 1),
						"cost_cap": d.get("cost_initial_cap", 0)
					})
			summary["categories"] = cat_set.keys()
			summary["starting_directives"] = starters
			return summary

	return summary


static func _read_json_file(res_path: String) -> Dictionary:
	var data = _read_json(res_path)
	if data is Dictionary:
		return data
	return {}


static func _read_json(res_path: String) -> Variant:
	if not FileAccess.file_exists(res_path):
		return null

	var file = FileAccess.open(res_path, FileAccess.READ)
	if file == null:
		return null

	var text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var err = json.parse(text)
	if err == OK:
		return json.data
	return null
