class_name WorldDataLoader
extends RefCounted

##
## WorldDataLoader: Модуль начальной загрузки глобального мира TNO
## ==============================================================================
## Загружает географические и государственные структуры:
## 1. Страновые состояния (starting_countries_state.json).
## 2. Манифест штатов и привязку провинций (map_manifest.json / border_hierarchy_manifest.json).
## 3. Региональные данные провинций (starting_regions_state.json).
## ==============================================================================

const JSONHelper = preload("res://core/utils/json_file_helper.gd")


"""Загружает мировые данные и заполняет переданные структуры TurnManager.
"""
static func load_world_data(
	turn_manager: TurnManager,
	regions_path: String = "res://map_data/starting_regions_state.json",
	countries_path: String = "res://map_data/starting_countries_state.json",
	manifest_path: String = "res://map_data/map_manifest.json"
) -> void:
	if turn_manager == null:
		return

	# 1. Загрузка стартовых стран
	var countries_dict: Dictionary = JSONHelper.load_json_dict(countries_path)
	for c_tag: String in countries_dict.keys():
		var c_dict: Dictionary = countries_dict[c_tag]
		if turn_manager.player_state != null and c_tag == turn_manager.player_state.country_tag:
			turn_manager.countries_world_state[c_tag] = turn_manager.player_state
			continue
		var c_state: CountryState = CountryState.from_dict(c_dict)
		turn_manager.countries_world_state[c_tag] = c_state

	# Сохраняем стейт игрока во всеобщем справочнике
	if turn_manager.player_state != null:
		turn_manager.countries_world_state[turn_manager.player_state.country_tag] = turn_manager.player_state

	# 2. Загрузка манифеста (штаты и связь с провинциями)
	var loaded_states: bool = false
	var manifest_dict: Dictionary = JSONHelper.load_json_dict(manifest_path)
	if not manifest_dict.is_empty():
		var states_dict: Dictionary = manifest_dict.get("states", {})
		for sid_str: String in states_dict.keys():
			var sid: int = int(sid_str)
			var s_info: Dictionary = states_dict[sid_str]
			var provs: Array = s_info.get("provinces", [])
			var int_provs: Array[int] = []
			for p: Variant in provs:
				var pid: int = int(p)
				int_provs.append(pid)
				turn_manager.province_to_state[pid] = sid
			turn_manager.state_to_provinces[sid] = int_provs

		# Если в манифесте нет секции states, извлекаем штаты из провинций
		if turn_manager.state_to_provinces.is_empty() and manifest_dict.has("provinces"):
			var provs_dict: Dictionary = manifest_dict["provinces"]
			for pid_str: String in provs_dict.keys():
				var pid: int = int(pid_str)
				var p_info: Variant = provs_dict[pid_str]
				if p_info is Dictionary and p_info.has("state_id"):
					var sid: int = int(p_info["state_id"])
					if sid > 0:
						turn_manager.province_to_state[pid] = sid
						if not turn_manager.state_to_provinces.has(sid):
							var new_provs: Array[int] = []
							turn_manager.state_to_provinces[sid] = new_provs
						turn_manager.state_to_provinces[sid].append(pid)

		if not turn_manager.state_to_provinces.is_empty():
			loaded_states = true

	# Дополнительный фоллбек: загрузка штатов из border_hierarchy_manifest.json
	if not loaded_states:
		var hierarchy_dict: Dictionary = JSONHelper.load_json_dict("res://map_data/border_hierarchy_manifest.json")
		if not hierarchy_dict.is_empty():
			var ext_states: Dictionary = hierarchy_dict.get("states", {})
			for sid_str: String in ext_states.keys():
				var sid: int = int(sid_str)
				var s_info: Dictionary = ext_states[sid_str]
				var provs: Array = s_info.get("provinces", [])
				var int_provs: Array[int] = []
				for p: Variant in provs:
					var pid: int = int(p)
					int_provs.append(pid)
					turn_manager.province_to_state[pid] = sid
				turn_manager.state_to_provinces[sid] = int_provs

	# 3. Загрузка стартовых провинций
	var regions_dict: Dictionary = JSONHelper.load_json_dict(regions_path)
	for pid_str: String in regions_dict.keys():
		var pid: int = int(pid_str)
		var r_dict: Dictionary = regions_dict[pid_str]
		var r_data: RegionData = RegionData.from_dict(r_dict)
		turn_manager.regions_world_state[pid] = r_data

	print("[TurnManager] Loaded world data: %d regions, %d countries, %d states." % [
		turn_manager.regions_world_state.size(),
		turn_manager.countries_world_state.size(),
		turn_manager.state_to_provinces.size()
	])
	turn_manager.world_data_loaded.emit(turn_manager.regions_world_state.size(), turn_manager.countries_world_state.size())
