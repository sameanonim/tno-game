class_name BoundaryManager
extends Node

##
## BoundaryManager: Геополитический диспетчер территорий, границ и суверенитета (TNO Engine)
## ==============================================================================
## Отвечает за:
## 1. Управление территориальными изменениями (передача провинций/штатов).
## 2. Моментальную синхронизацию с шейдерной LUT-палитрой MapController.
## 3. Аудит топологических анклавов (Enclave Check) с наложением дебаффов
##    на снабжение (supply_cutoff) и стабильность (unrest += 25%).
## 4. Демаркацию рубежей (OPEN, FORTIFIED, DMZ, DISPUTED, CLOSED) и синхронизацию
##    военных укреплений (фортификационные засечки на шейдере).
## 5. Автоматический пересчет сопредельных границ и осей фронта для MilitaryEngine.
## ==============================================================================

# ==============================================================================
# ENUMS & SIGNALS
# ==============================================================================
enum BorderStatus {
	OPEN = 0,
	FORTIFIED = 1,
	DMZ = 2,
	CLOSED = 3,
	DISPUTED = 4
}

signal territory_transferred(state_id: int, old_owner: String, new_owner: String, is_enclave: bool)
signal border_status_changed(prov_a: int, prov_b: int, old_status: int, new_status: int)
signal enclave_detected(state_id: int, owner_tag: String, surrounded_by: String)
signal frontlines_recalculated(affected_tags: Array[String])

# ==============================================================================
# EXPORT CONFIGURATION
# ==============================================================================
@export_file("*.json") var borders_manifest_path: String = "res://map_data/borders_manifest.json"
@export_file("*.json") var border_hierarchy_path: String = "res://map_data/border_hierarchy_manifest.json"
@export_file("*.json") var map_manifest_path: String = "res://map_data/map_manifest.json"
@export var auto_sync_map_controller: bool = true
@export var auto_sync_military_engine: bool = true
@export var enclave_unrest_penalty: float = 25.0

# ==============================================================================
# INTERNAL STATE
# ==============================================================================
## Граф смежности провинций: {prov_id: [neighbor_id, ...]}
var province_adjacency: Dictionary = {}

## Граф смежности штатов: {state_id: [neighbor_state_id, ...]}
var state_adjacency: Dictionary = {}

## Привязка штата к провинциям: {state_id: [prov_id, ...]}
var state_to_provinces: Dictionary = {}

## Привязка провинции к штату: {prov_id: state_id}
var province_to_state: Dictionary = {}

## Владелец штата: {state_id: owner_tag}
var state_to_owner: Dictionary = {}

## Владения стран: {owner_tag: [state_id, ...]}
var country_states: Dictionary = {}

## Множество водных провинций: {prov_id: true}
var water_provinces: Dictionary = {}

## Прибрежные провинции: {prov_id: true}
var coastal_provinces: Dictionary = {}

## Геометрические центроиды провинций: {prov_id: Vector2}
var province_centroids: Dictionary = {}

## Статусы границ между парами провинций: {"min_max": BorderStatus}
var border_statuses: Dictionary = {}

## Уровни фортификаций по парам: {"min_max": fort_level}
var border_fortifications: Dictionary = {}

## Демилитаризованные штаты (DMZ): {state_id: bool}
var state_dmz_flags: Dictionary = {}

## Обнаруженные анклавы: {state_id: bool}
var enclave_states: Dictionary = {}

## Ссылка на MapController в сцене
var map_controller: MapController = null

## Локальные кэши моделей данных игры
var regions_db: Dictionary = {}     # Key: int (prov_id), Value: RegionData
var countries_db: Dictionary = {}   # Key: String (tag), Value: CountryState


# ==============================================================================
# LIFECYCLE
# ==============================================================================
func _ready() -> void:
	_discover_map_controller()
	load_manifest_data()


func _discover_map_controller() -> void:
	if map_controller != null:
		return
	var root = get_tree().root
	map_controller = _find_map_controller_recursive(root)


func _find_map_controller_recursive(node: Node) -> MapController:
	if node is MapController:
		return node as MapController
	for child in node.get_children():
		var res = _find_map_controller_recursive(child)
		if res != null:
			return res
	return null


# ==============================================================================
# DATA LOADING & TOPOLOGY GRAPH
# ==============================================================================
func load_manifest_data() -> bool:
	var success := false

	# 1. Загрузка borders_manifest.json (сгенерирован map_sanitizer.py)
	if FileAccess.file_exists(borders_manifest_path):
		var file = FileAccess.open(borders_manifest_path, FileAccess.READ)
		if file != null:
			var json_str = file.get_as_text()
			var parsed = JSON.parse_string(json_str)
			if parsed is Dictionary:
				_parse_borders_manifest(parsed)
				success = true

	# 2. Загрузка иерархии штатов и стран из border_hierarchy_manifest.json
	var hier_path = border_hierarchy_path if FileAccess.file_exists(border_hierarchy_path) else "res://map_data/border_hierarchy_manifest.json"
	if FileAccess.file_exists(hier_path):
		var file = FileAccess.open(hier_path, FileAccess.READ)
		if file != null:
			var json_str = file.get_as_text()
			var parsed = JSON.parse_string(json_str)
			if parsed is Dictionary:
				_parse_map_manifest(parsed)
				success = true

	# 3. Загрузка/дополнение из map_manifest.json (водные провинции)
	if FileAccess.file_exists(map_manifest_path):
		var file = FileAccess.open(map_manifest_path, FileAccess.READ)
		if file != null:
			var json_str = file.get_as_text()
			var parsed = JSON.parse_string(json_str)
			if parsed is Dictionary:
				_parse_map_manifest(parsed)
				success = true

	# 4. Построение графа смежности штатов
	_build_state_adjacency_graph()

	print("[BoundaryManager] Loaded topology: %d provinces, %d states, %d sovereign entities." % [
		province_adjacency.size(),
		state_to_provinces.size(),
		country_states.size()
	])
	return success


func _parse_borders_manifest(manifest: Dictionary) -> void:
	# Центроиды провинций
	var cents = manifest.get("province_centroids", {})
	for pid_str in cents.keys():
		var pid = int(pid_str)
		var arr = cents[pid_str]
		if arr is Array and arr.size() >= 2:
			province_centroids[pid] = Vector2(float(arr[0]), float(arr[1]))

	# Смежность провинций
	var adj = manifest.get("province_adjacency", {})
	for pid_str in adj.keys():
		var pid = int(pid_str)
		var n_list: Array[int] = []
		for n in adj[pid_str]:
			n_list.append(int(n))
		province_adjacency[pid] = n_list

	# Сегменты границ и классификация
	var segments = manifest.get("border_segments", [])
	for seg in segments:
		if seg is Dictionary:
			var pair = seg.get("pair", [])
			if pair.size() == 2:
				var p1 = int(pair[0])
				var p2 = int(pair[1])
				var key = _make_pair_key(p1, p2)
				var b_type = seg.get("type", "PROVINCE_INTERNAL")
				if b_type == "COASTLINE":
					if p1 > 0: coastal_provinces[p1] = true
					if p2 > 0: coastal_provinces[p2] = true
				elif b_type == "DISPUTED_DMZ":
					border_statuses[key] = BorderStatus.DMZ


func _parse_map_manifest(manifest: Dictionary) -> void:
	# Загрузка состояний штатов
	var states = manifest.get("states", {})
	for sid_str in states.keys():
		var sid = int(sid_str)
		var s_info = states[sid_str]
		var owner = str(s_info.get("owner", "")).strip_edges().to_upper()
		state_to_owner[sid] = owner

		var provs: Array[int] = []
		for p in s_info.get("provinces", []):
			var pid = int(p)
			provs.append(pid)
			province_to_state[pid] = sid

		state_to_provinces[sid] = provs

		if not owner.is_empty() and owner not in ["WST", "WASTE"]:
			if not country_states.has(owner):
				country_states[owner] = []
			if not country_states[owner].has(sid):
				country_states[owner].append(sid)

	# Загрузка водных провинций
	var provs_dict = manifest.get("provinces", {})
	for pid_str in provs_dict.keys():
		var pid = int(pid_str)
		var p_type = provs_dict[pid_str].get("type", "land")
		if p_type in ["sea", "lake"]:
			water_provinces[pid] = true


func _build_state_adjacency_graph() -> void:
	state_adjacency.clear()

	for sid in state_to_provinces.keys():
		state_adjacency[sid] = []

	for p1 in province_adjacency.keys():
		var s1 = province_to_state.get(p1, 0)
		if s1 == 0:
			continue

		for p2 in province_adjacency[p1]:
			var s2 = province_to_state.get(p2, 0)
			if s2 != 0 and s2 != s1:
				if not state_adjacency[s1].has(s2):
					state_adjacency[s1].append(s2)
				if state_adjacency.has(s2) and not state_adjacency[s2].has(s1):
					state_adjacency[s2].append(s1)


# ==============================================================================
# TERRITORIAL TRANSFER & DYNAMIC SOVEREIGNTY
# ==============================================================================

##
## Главный метод передачи штата или региона новому суверенному владельцу.
## 1. Обновляет внутренний стейт топологии.
## 2. Моментально перерисовывает шейдерную Ownership-LUT и Political-LUT в MapController.
## 3. Выполняет проверку на возникновение изолированного анклава (Enclave Check).
## 4. Запускает синхронизацию фронтов для MilitaryEngine.
##
func transfer_province_or_state(state_id: int, new_owner_tag: String) -> Dictionary:
	var clean_tag = new_owner_tag.strip_edges().to_upper()
	var old_owner = state_to_owner.get(state_id, "")

	if clean_tag.is_empty():
		push_warning("[BoundaryManager] Refusing to transfer State %d to empty owner tag!" % state_id)
		return {"success": false, "changed": false, "state_id": state_id, "owner": old_owner}

	if old_owner == clean_tag:
		return {"success": true, "changed": false, "state_id": state_id, "owner": clean_tag}

	print("[BoundaryManager] Transferring State %d: %s -> %s" % [state_id, old_owner, clean_tag])

	# 1. Обновляем принадлежность штата
	state_to_owner[state_id] = clean_tag

	# Обновляем списки штатов стран
	if country_states.has(old_owner):
		country_states[old_owner].erase(state_id)
		if country_states[old_owner].is_empty():
			country_states.erase(old_owner)

	if not clean_tag.is_empty() and clean_tag not in ["WST", "WASTE"]:
		if not country_states.has(clean_tag):
			country_states[clean_tag] = []
		if not country_states[clean_tag].has(state_id):
			country_states[clean_tag].append(state_id)

	# 2. Обновляем привязанные провинции в RegionData
	var provs: Array = state_to_provinces.get(state_id, [])
	for p in provs:
		var pid = int(p)
		if regions_db.has(pid):
			var reg = regions_db[pid] as RegionData
			if reg != null:
				reg.owner_tag = clean_tag

	# 3. Моментальное обновление визуализации через MapController
	if auto_sync_map_controller and map_controller != null:
		map_controller.set_state_owner(state_id, clean_tag)

	# 4. Проверка анклавов (Enclave Check)
	var is_enclave = _check_and_apply_enclave_status(state_id, clean_tag)

	# Проверяем также старого владельца (не возник ли анклав у него после потери штата)
	if not old_owner.is_empty() and country_states.has(old_owner):
		for remaining_sid in country_states[old_owner]:
			_check_and_apply_enclave_status(remaining_sid, old_owner)

	# 5. Пересчет границ и сопредельных фронтов для MilitaryEngine
	if auto_sync_military_engine:
		_recalculate_frontlines([old_owner, clean_tag])

	# 6. Эмиссия сигнала
	territory_transferred.emit(state_id, old_owner, clean_tag, is_enclave)

	return {
		"success": true,
		"changed": true,
		"state_id": state_id,
		"old_owner": old_owner,
		"new_owner": clean_tag,
		"is_enclave": is_enclave,
		"provinces_count": provs.size()
	}


## Псевдоним для совместимости с внешними системами
func transfer_state(state_id: int, new_owner_tag: String) -> Dictionary:
	return transfer_province_or_state(state_id, new_owner_tag)


## Передача отдельной провинции новому владельцу с аудитом штата и анклавов
func transfer_province(province_id: int, new_owner_tag: String) -> Dictionary:
	var clean_tag = new_owner_tag.strip_edges().to_upper()
	var state_id = province_to_state.get(province_id, 0)
	var old_owner := ""

	if clean_tag.is_empty():
		push_warning("[BoundaryManager] Refusing to transfer Province %d to empty owner tag!" % province_id)
		return {"success": false, "changed": false, "province_id": province_id, "state_id": state_id}

	if regions_db.has(province_id):
		var reg = regions_db[province_id] as RegionData
		if reg != null:
			old_owner = reg.owner_tag
			reg.owner_tag = clean_tag

	if auto_sync_map_controller and map_controller != null:
		map_controller.update_province_owner(province_id, clean_tag)

	# Если все провинции штата теперь под контролем new_owner_tag, передаем весь штат
	if state_id > 0:
		var provs = state_to_provinces.get(state_id, [])
		var all_transferred := true
		for p in provs:
			var p_owner = clean_tag
			if regions_db.has(int(p)):
				var r = regions_db[int(p)] as RegionData
				if r != null:
					p_owner = r.owner_tag
			if p_owner != clean_tag:
				all_transferred = false
				break
		if all_transferred:
			return transfer_state(state_id, clean_tag)
		else:
			# Частичный захват штата: проверяем анклавы
			_check_and_apply_enclave_status(state_id, clean_tag)

	return {
		"success": true,
		"changed": true,
		"province_id": province_id,
		"state_id": state_id,
		"old_owner": old_owner,
		"new_owner": clean_tag
	}


## Полный аудит топологических анклавов для всех стран и штатов
func audit_enclaves() -> Dictionary:
	var enclaves_found: Dictionary = {}
	for country_tag in country_states.keys():
		var states_list: Array = country_states[country_tag]
		for sid in states_list:
			var is_iso = _check_and_apply_enclave_status(int(sid), country_tag)
			if is_iso:
				enclaves_found[int(sid)] = country_tag
	return enclaves_found


## Ликвидация изолированных анклавов (де-бордергор)
## Передает полностью изолированные не-прибрежные штаты окружающему государству
func cleanup_isolated_enclaves(target_owner_tag: String = "") -> Array[int]:
	var liquidated_states: Array[int] = []
	var tags_to_check: Array[String] = []
	if not target_owner_tag.is_empty():
		tags_to_check.append(target_owner_tag)
	else:
		for t in country_states.keys():
			tags_to_check.append(str(t))

	for tag in tags_to_check:
		if not country_states.has(tag):
			continue
		var states_list = country_states[tag].duplicate()
		for sid in states_list:
			if is_state_enclave(int(sid)):
				var neighbors = state_adjacency.get(int(sid), [])
				var owner_counts: Dictionary = {}
				for n_sid in neighbors:
					var n_owner = state_to_owner.get(int(n_sid), "")
					if n_owner.is_empty() or n_owner == tag or n_owner in ["WST", "WASTE"]:
						continue
					owner_counts[n_owner] = owner_counts.get(n_owner, 0) + 1
				
				var dominant_owner: String = ""
				var max_c: int = 0
				for cand_tag in owner_counts.keys():
					if owner_counts[cand_tag] > max_c:
						max_c = owner_counts[cand_tag]
						dominant_owner = cand_tag
				
				if not dominant_owner.is_empty():
					print("[BoundaryManager] Liquidating enclave state %d from %s to %s" % [int(sid), tag, dominant_owner])
					transfer_state(int(sid), dominant_owner)
					liquidated_states.append(int(sid))

	return liquidated_states



# ==============================================================================
# ENCLAVE DETECTION & DEBUFF APPLICATION
# ==============================================================================

##
## Проверяет, является ли штат изолированным анклавом для указанного владельца.
## Анклав — штат/кластер, не имеющий сухопутного коридора до столичного региона
## державы и не имеющий собственного выхода к морю.
##
func _check_and_apply_enclave_status(state_id: int, owner_tag: String) -> bool:
	if owner_tag.is_empty() or owner_tag in ["WST", "WASTE"]:
		enclave_states.erase(state_id)
		return false

	var is_isolated = is_state_enclave(state_id)
	enclave_states[state_id] = is_isolated

	var provs: Array = state_to_provinces.get(state_id, [])

	if is_isolated:
		# Накладываем штраф на снабжение и стабильность
		for p in provs:
			var pid = int(p)
			if regions_db.has(pid):
				var reg = regions_db[pid] as RegionData
				if reg != null:
					reg.unrest = minf(100.0, reg.unrest + enclave_unrest_penalty)
					reg.story_flags["supply_cutoff"] = true

		var surrounding = get_neighboring_countries_of_state(state_id)
		surrounding.erase(owner_tag)
		var dominant_surround = surrounding[0] if surrounding.size() > 0 else "FOREIGN"

		print("[BoundaryManager] ALERT: Enclave detected! State %d (%s) surrounded by %s. Applied supply cutoff & +%.1f unrest." % [
			state_id, owner_tag, dominant_surround, enclave_unrest_penalty
		])
		enclave_detected.emit(state_id, owner_tag, dominant_surround)
	else:
		# Снимаем дебафф отрезания снабжения, если коридор восстановлен
		for p in provs:
			var pid = int(p)
			if regions_db.has(pid):
				var reg = regions_db[pid] as RegionData
				if reg != null and reg.story_flags.has("supply_cutoff"):
					reg.story_flags.erase("supply_cutoff")

	return is_isolated


func is_state_enclave(state_id: int) -> bool:
	var owner = state_to_owner.get(state_id, "")
	if owner.is_empty() or owner in ["WST", "WASTE"]:
		return false

	var all_states: Array = country_states.get(owner, [])
	if all_states.size() <= 1:
		# Если у государства всего 1 штат, он не считается эксклавом самого себя,
		# но если он сухопутно окружен другой державой без моря — это анклав
		return not _state_has_coast(state_id) and _is_state_completely_surrounded_by_foreigners(state_id, owner)

	# Поиск в ширину (BFS) по дружественным штатам
	var visited: Dictionary = {state_id: true}
	var queue: Array[int] = [state_id]
	var has_coast := false

	# Определяем столичный штат (первый в списке или из CountryState)
	var capital_sid = all_states[0]
	if countries_db.has(owner):
		var cs = countries_db[owner] as CountryState
		if cs != null and cs.story_flags.has("capital_state_id"):
			capital_sid = int(cs.story_flags["capital_state_id"])

	var reaches_capital = (state_id == capital_sid)

	while not queue.is_empty():
		var curr = queue.pop_front()
		if curr == capital_sid:
			reaches_capital = true

		if _state_has_coast(curr):
			has_coast = true

		# Если уже достигли и столицы, и побережья, анклава точно нет
		if reaches_capital and has_coast:
			return false

		for neighbor in state_adjacency.get(curr, []):
			if state_to_owner.get(neighbor, "") == owner:
				if not visited.has(neighbor):
					visited[neighbor] = true
					queue.append(neighbor)

	# Если есть выход к морю (морское снабжение) или связь со столицей — снабжение в порядке
	if reaches_capital or has_coast:
		return false

	return true


func _state_has_coast(state_id: int) -> bool:
	var provs: Array = state_to_provinces.get(state_id, [])
	for p in provs:
		var pid = int(p)
		if coastal_provinces.has(pid):
			return true
		for n in province_adjacency.get(pid, []):
			if water_provinces.has(n) or n == 0:
				coastal_provinces[pid] = true
				return true
	return false


func _is_state_completely_surrounded_by_foreigners(state_id: int, owner: String) -> bool:
	var neighbors: Array = state_adjacency.get(state_id, [])
	if neighbors.is_empty():
		return false
	for n in neighbors:
		var n_owner = state_to_owner.get(n, "")
		if n_owner == owner or n_owner.is_empty() or n_owner in ["WST", "WASTE"]:
			return false
	return true


# ==============================================================================
# DEMARCATION & BORDER CONTROL API
# ==============================================================================

##
## Устанавливает статус фортификации (Укрепрайон / ДОТы) на границе между провинциями.
## Если level > 0, помечает рубеж как FORTIFIED и обновляет шейдерную LUT-палитру.
##
func set_border_fortification(prov_a: int, prov_b: int, fort_level: int) -> void:
	var key = _make_pair_key(prov_a, prov_b)
	border_fortifications[key] = fort_level

	var old_status = border_statuses.get(key, BorderStatus.OPEN)
	var new_status = BorderStatus.FORTIFIED if fort_level > 0 else BorderStatus.OPEN
	border_statuses[key] = new_status

	# Обновление в MapController (активация crenelated fort-teeth в шейдере)
	if auto_sync_map_controller and map_controller != null:
		var is_fort = (fort_level > 0)
		map_controller.set_province_fortified(prov_a, is_fort)
		map_controller.set_province_fortified(prov_b, is_fort)

	border_status_changed.emit(prov_a, prov_b, old_status, new_status)
	print("[BoundaryManager] Fortification updated between %d and %d: level %d (status %d)" % [
		prov_a, prov_b, fort_level, new_status
	])


##
## Демаркация демилитаризованной зоны (DMZ):
## Все границы данного штата переводятся в пульсирующий режим DMZ.
##
func set_dmz_zone(state_id: int, is_dmz: bool) -> void:
	state_dmz_flags[state_id] = is_dmz
	var provs: Array = state_to_provinces.get(state_id, [])

	for p in provs:
		var pid = int(p)
		if regions_db.has(pid):
			var reg = regions_db[pid] as RegionData
			if reg != null:
				reg.is_demilitarized = is_dmz

		if auto_sync_map_controller and map_controller != null:
			map_controller.set_province_dmz(pid, is_dmz)

		for n in province_adjacency.get(pid, []):
			var key = _make_pair_key(pid, n)
			var old_status = border_statuses.get(key, BorderStatus.OPEN)
			var new_status = BorderStatus.DMZ if is_dmz else BorderStatus.OPEN
			border_statuses[key] = new_status
			border_status_changed.emit(pid, n, old_status, new_status)

	print("[BoundaryManager] State %d DMZ status set to: %s" % [state_id, str(is_dmz)])


##
## Переключение глобального режима шейдера:
## 0 = Standard, 1 = Spheres/Blocs, 2 = Smuta/DMZ
##
func set_border_rendering_mode(mode: int) -> void:
	if map_controller != null:
		map_controller.set_border_rendering_mode(mode)


# ==============================================================================
# MILITARY ENGINE FRONTLINE SYNCHRONIZATION
# ==============================================================================
func _recalculate_frontlines(affected_tags: Array[String]) -> void:
	var clean_tags: Array[String] = []
	for t in affected_tags:
		var clean = t.strip_edges().to_upper()
		if not clean.is_empty() and clean not in ["WST", "WASTE"] and not clean_tags.has(clean):
			clean_tags.append(clean)

	if clean_tags.is_empty():
		return

	# Проверяем сопредельные государства для каждого тега
	for tag in clean_tags:
		var neighbors = get_adjacent_countries(tag)
		for neighbor_tag in neighbors:
			var shared_provs = get_shared_border_provinces(tag, neighbor_tag)
			if shared_provs.size() > 0:
				_ensure_strategic_frontline(tag, neighbor_tag, shared_provs)

	frontlines_recalculated.emit(clean_tags)


func _ensure_strategic_frontline(tag_a: String, tag_b: String, shared_provinces: Array[Vector2i]) -> void:
	var front_id = "front_%s_%s" % [tag_a.to_lower(), tag_b.to_lower()]
	var reverse_id = "front_%s_%s" % [tag_b.to_lower(), tag_a.to_lower()]

	# Проверяем, существует ли уже фронт в MilitaryEngine
	var existing = MilitaryEngine.get_frontline(front_id)
	if existing == null:
		existing = MilitaryEngine.get_frontline(reverse_id)

	if existing == null:
		# Создаем новый стратегический фронт
		var front = Frontline.new()
		front.front_id = front_id
		front.name = "%s - %s Strategic Border" % [tag_a, tag_b]
		front.attacker_tag = tag_a
		front.defender_tag = tag_b
		front.active = true
		front.tension = 45.0

		# Создаем базовую оперативную ось
		var axis = OperationalAxis.new()
		axis.axis_id = "axis_%s_%s_main" % [tag_a.to_lower(), tag_b.to_lower()]
		axis.name = "Primary Operational Sector"

		var target_provs: Array = []
		for pair in shared_provinces:
			if not target_provs.has(pair.x): target_provs.append(pair.x)
			if not target_provs.has(pair.y): target_provs.append(pair.y)
			if target_provs.size() >= 8: break

		axis.target_region_ids = target_provs
		axis.progress = 50.0
		front.add_axis(axis)

		MilitaryEngine.register_frontline(front)
		print("[BoundaryManager] Established new strategic frontline: %s with %d border interfaces." % [
			front_id, shared_provinces.size()
		])


# ==============================================================================
# GEOPOLITICAL QUERY API
# ==============================================================================

##
## Возвращает список всех сопредельных государств для указанного тега страны.
##
func get_adjacent_countries(country_tag: String) -> Array[String]:
	var clean = country_tag.strip_edges().to_upper()
	var adjacent_countries: Array[String] = []

	var states: Array = country_states.get(clean, [])
	for sid in states:
		for neighbor_sid in state_adjacency.get(sid, []):
			var n_owner = state_to_owner.get(neighbor_sid, "")
			if not n_owner.is_empty() and n_owner != clean and n_owner not in ["WST", "WASTE"]:
				if not adjacent_countries.has(n_owner):
					adjacent_countries.append(n_owner)

	return adjacent_countries


##
## Возвращает список пар смежных провинций на границе между двумя странами: Vector2i(prov_a, prov_b).
##
func get_shared_border_provinces(tag_a: String, tag_b: String) -> Array[Vector2i]:
	var a = tag_a.strip_edges().to_upper()
	var b = tag_b.strip_edges().to_upper()
	var shared: Array[Vector2i] = []

	var states_a: Array = country_states.get(a, [])
	for sid_a in states_a:
		for sid_b in state_adjacency.get(sid_a, []):
			if state_to_owner.get(sid_b, "") == b:
				for pa in state_to_provinces.get(sid_a, []):
					for pb in province_adjacency.get(int(pa), []):
						if province_to_state.get(int(pb), 0) == sid_b:
							shared.append(Vector2i(int(pa), int(pb)))

	return shared


func get_neighboring_countries_of_state(state_id: int) -> Array[String]:
	var neighbors: Array[String] = []
	for n_sid in state_adjacency.get(state_id, []):
		var n_owner = state_to_owner.get(n_sid, "")
		if not n_owner.is_empty() and not neighbors.has(n_owner):
			neighbors.append(n_owner)
	return neighbors


func get_state_provinces(state_id: int) -> Array[int]:
	return state_to_provinces.get(state_id, [])


func get_border_status(prov_a: int, prov_b: int) -> int:
	var key = _make_pair_key(prov_a, prov_b)
	return border_statuses.get(key, BorderStatus.OPEN)


func _make_pair_key(p1: int, p2: int) -> String:
	return "%d_%d" % [mini(p1, p2), maxi(p1, p2)]
