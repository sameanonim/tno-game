class_name MapManifestLoader
extends RefCounted

##
## MapManifestLoader: Загрузчик топологических манифестов, регионов и центроидов карты
## ==============================================================================
## Отвечает за:
## 1. Парсинг map_manifest.json (провинции, штаты, связи провинция-штат).
## 2. Загрузку дополнительных данных: starting_countries_state.json, starting_regions_state.json,
##    province_features.json.
## 3. Вычисление геометрических центроидов провинций из растровой маски.
## ==============================================================================


"""Загружает базовый манифест карты: провинции, штаты и их ассоциации.
"""
static func load_manifest(path: String) -> Dictionary:
	var result = {
		"manifest_data": {},
		"max_province_id": 0,
		"states_data": {},
		"provinces_data": {},
		"province_to_state": {},
		"state_to_provinces": {}
	}

	if not FileAccess.file_exists(path):
		return result

	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return result
	var text = f.get_as_text()
	f.close()

	var json = JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return result

	var manifest_data: Dictionary = json.data
	result["manifest_data"] = manifest_data
	var meta = manifest_data.get("metadata", {})
	result["max_province_id"] = int(meta.get("max_province_id", 0))

	# 1. Загрузка штатов и привязка провинций
	var states: Dictionary = manifest_data.get("states", {})
	var states_data: Dictionary = result["states_data"]
	var provinces_data: Dictionary = result["provinces_data"]
	var province_to_state: Dictionary = result["province_to_state"]
	var state_to_provinces: Dictionary = result["state_to_provinces"]

	for k in states.keys():
		var sid = int(k)
		var s_info: Dictionary = states[k]
		states_data[sid] = s_info
		var s_owner = str(s_info.get("owner", ""))
		var s_name = str(s_info.get("name", "Регион %d" % sid))
		var s_provs = s_info.get("provinces", [])
		for pid_raw in s_provs:
			var pid = int(pid_raw)
			province_to_state[pid] = sid
			if not provinces_data.has(pid):
				provinces_data[pid] = {"id": pid, "state_id": sid, "owner": s_owner, "state_name": s_name}
			else:
				provinces_data[pid]["state_id"] = sid
				if not s_owner.is_empty():
					provinces_data[pid]["owner"] = s_owner
				provinces_data[pid]["state_name"] = s_name
			if not state_to_provinces.has(sid):
				state_to_provinces[sid] = []
			if not state_to_provinces[sid].has(pid):
				state_to_provinces[sid].append(pid)

	# 2. Загрузка метаданных провинций
	var provs: Dictionary = manifest_data.get("provinces", {})
	for k in provs.keys():
		var pid = int(k)
		var p_info: Dictionary = provs[k]
		if not provinces_data.has(pid):
			provinces_data[pid] = p_info
		else:
			for pk in p_info.keys():
				provinces_data[pid][pk] = p_info[pk]
		if p_info.has("state_id") and p_info["state_id"] != null:
			var sid = int(p_info["state_id"])
			province_to_state[pid] = sid
			if not state_to_provinces.has(sid):
				state_to_provinces[sid] = []
			if not state_to_provinces[sid].has(pid):
				state_to_provinces[sid].append(pid)

	return result


"""Загружает дополнительную геополитическую информацию, цвета стран и особенности провинций.
"""
static func load_supplementary_data(
	countries_path: String,
	regions_path: String,
	features_path: String,
	provinces_data: Dictionary,
	states_data: Dictionary,
	province_to_state: Dictionary,
	state_to_provinces: Dictionary
) -> Dictionary:
	var result = {
		"country_tag_to_id": {},
		"country_id_to_tag": {},
		"country_colors": {},
		"country_spheres": {},
		"country_factions": {},
		"starting_regions_data": {},
		"province_features_data": {}
	}

	var country_tag_to_id: Dictionary = result["country_tag_to_id"]
	var country_id_to_tag: Dictionary = result["country_id_to_tag"]
	var country_colors: Dictionary = result["country_colors"]
	var country_spheres: Dictionary = result["country_spheres"]
	var country_factions: Dictionary = result["country_factions"]
	var starting_regions_data: Dictionary = result["starting_regions_data"]
	var province_features_data: Dictionary = result["province_features_data"]

	if FileAccess.file_exists(countries_path):
		var f = FileAccess.open(countries_path, FileAccess.READ)
		if f != null:
			var text = f.get_as_text()
			f.close()
			var json = JSON.new()
			if json.parse(text) == OK and json.data is Dictionary:
				var cid := 1
				for tag in json.data.keys():
					var c_info = json.data[tag]
					country_tag_to_id[tag] = cid
					country_id_to_tag[cid] = tag
					cid += 1
					if c_info is Dictionary:
						var c_arr = c_info.get("country_color", c_info.get("color", []))
						if c_arr is Array and c_arr.size() >= 3:
							var a = c_arr[3] if c_arr.size() >= 4 else 1.0
							country_colors[tag] = Color(float(c_arr[0]), float(c_arr[1]), float(c_arr[2]), a)
						if c_info.has("sphere_code"):
							country_spheres[tag] = float(c_info["sphere_code"])
						if c_info.has("faction"):
							country_factions[tag] = str(c_info["faction"])
						if c_info.has("owned_states") and c_info["owned_states"] is Array:
							for sid_val in c_info["owned_states"]:
								var sid = int(sid_val)
								states_data[sid] = {
									"id": sid,
									"owner": tag,
									"provinces": state_to_provinces.get(sid, [])
								}

	if FileAccess.file_exists(regions_path):
		var f_r = FileAccess.open(regions_path, FileAccess.READ)
		if f_r != null:
			var r_text = f_r.get_as_text()
			f_r.close()
			var json_r = JSON.new()
			if json_r.parse(r_text) == OK and json_r.data is Dictionary:
				for k in json_r.data.keys():
					var sid = int(k)
					var s_dict: Dictionary = json_r.data[k]
					starting_regions_data[sid] = s_dict
					states_data[sid] = s_dict
					var s_owner = str(s_dict.get("owner", s_dict.get("owner_tag", "")))
					var s_name = str(s_dict.get("name", "Регион %d" % sid))
					for pid_raw in s_dict.get("provinces", []):
						var pid = int(pid_raw)
						province_to_state[pid] = sid
						if not provinces_data.has(pid):
							provinces_data[pid] = {"id": pid, "state_id": sid, "owner": s_owner, "state_name": s_name}
						else:
							provinces_data[pid]["state_id"] = sid
							if not s_owner.is_empty():
								provinces_data[pid]["owner"] = s_owner
							provinces_data[pid]["state_name"] = s_name
						if not state_to_provinces.has(sid):
							state_to_provinces[sid] = []
						if not state_to_provinces[sid].has(pid):
							state_to_provinces[sid].append(pid)

	if FileAccess.file_exists(features_path):
		var f_pf = FileAccess.open(features_path, FileAccess.READ)
		if f_pf != null:
			var pf_text = f_pf.get_as_text()
			f_pf.close()
			var json_pf = JSON.new()
			if json_pf.parse(pf_text) == OK and json_pf.data is Dictionary:
				for k in json_pf.data.keys():
					var feat: Dictionary = json_pf.data[k]
					var pid = int(k)
					if provinces_data.has(pid) and provinces_data[pid].has("owner"):
						feat["owner"] = provinces_data[pid]["owner"]
					province_features_data[pid] = feat
					province_features_data[k] = feat

	return result


"""Вычисляет центроиды провинций из данных манифеста или сканированием маски.
"""
static func compute_province_centroids(
	provinces_data: Dictionary,
	mask_image: Image,
	map_size: Vector2i,
	sample_pixel_func: Callable
) -> Dictionary:
	var centroids: Dictionary = {}
	for pid in provinces_data.keys():
		if provinces_data[pid].has("centroid"):
			var c = provinces_data[pid]["centroid"]
			centroids[pid] = Vector2(c[0], c[1])

	if centroids.is_empty() and mask_image != null:
		var sums: Dictionary = {}
		var counts: Dictionary = {}
		var step = 4 if (map_size.x * map_size.y > 1000000) else 1

		for y in range(0, map_size.y, step):
			for x in range(0, map_size.x, step):
				var pid: int = sample_pixel_func.call(Vector2i(x, y))
				if pid > 0:
					if not sums.has(pid):
						sums[pid] = Vector2(x, y)
						counts[pid] = 1
					else:
						sums[pid] += Vector2(x, y)
						counts[pid] += 1

		for pid in sums.keys():
			centroids[pid] = sums[pid] / float(counts[pid])

	return centroids
