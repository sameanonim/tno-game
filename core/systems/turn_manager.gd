class_name TurnManager
extends Node

##
## TurnManager: Главный пошаговый цикл игры (Turn Loop Controller)
## Оркестрирует фазы: Экономика -> Директивы -> Кризисы/События -> Синхронизация карты и UI.
##

signal turn_started(turn: int, date_string: String)
signal phase_changed(phase_name: String)
signal modal_event_opened(event: GameEvent)
signal turn_completed(turn: int, report: EconomyEngine.EconomicTurnReport)
signal military_frontlines_processed(reports: Array[Dictionary])
signal region_conquered(province_id: int, new_owner_tag: String, previous_owner_tag: String)
signal state_conquered(state_id: int, new_owner_tag: String)
signal state_transferred(state_id: int, old_owner: String, new_owner: String)
signal world_data_loaded(regions_count: int, countries_count: int)
signal directive_started(directive: DirectiveResource)
signal directive_completed(directive: DirectiveResource)
signal directive_bypassed(directive: DirectiveResource)
signal directive_cancelled(directive: DirectiveResource, reason: String)
signal super_event_requested(super_event_id: String)
signal societal_evolution_completed(evolution_report: Dictionary)
signal espionage_processed(reports: Array[Dictionary])
signal tech_completed(report: Dictionary)
signal autosaved(turn_number: int, save_path: String)
signal game_over(victory: bool, reason: String)

enum TurnState {
	IDLE,
	PROCESSING_ECONOMY,
	PROCESSING_DIRECTIVES,
	PHASE_ESPIONAGE,
	PROCESSING_MILITARY,
	CHECKING_EVENTS,
	WAITING_FOR_MODAL_EVENT,
	TURN_FINISHED
}


signal us_electoral_report_generated(report: Dictionary)

@export var player_state: CountryState:
	get:
		if player_state == null:
			player_state = CountryState.new()
			player_state.country_tag = "KOM"
			player_state.country_name = "Республика Коми (Сыктывкар)"
			player_state.leader_name = "Национальное Собрание"
			player_state.ruling_ideology = "Authoritarian Democracy"
		return player_state
	set(val):
		player_state = val
@export var event_manager: EventManager
@export var directive_manager: DirectiveManager
@export var focus_stage_controller: FocusStageController
@export var german_civil_war_manager: GermanCivilWarManager
@export var russian_unification_manager: RussianUnificationManager:
	get:
		if russian_unification_manager == null:
			russian_unification_manager = RussianUnificationManager.new()
			russian_unification_manager.name = "RussianUnificationManager"
			if is_inside_tree():
				add_child(russian_unification_manager)
		return russian_unification_manager
	set(val):
		russian_unification_manager = val
@export var japan_empire_manager: JapanEmpireManager = null
@export var italy_empire_manager: ItalyEmpireManager = null
@export var research_manager: ResearchManager = null
@export var boundary_manager: BoundaryManager = null
@export var map_controller: Node = null
var espionage_engine: EspionageEngine = null
var us_electoral_engine: USElectoralEngine = null
var last_espionage_reports: Array[Dictionary] = []

## Текущая активная государственная директива игрока
var active_directive: DirectiveResource:
	get:
		if _active_directive != null:
			return _active_directive
		if player_state != null and not player_state.active_directives.is_empty() and directive_manager != null:
			var act_id = player_state.active_directives[0]
			if directive_manager.all_directives.has(act_id):
				return directive_manager.all_directives[act_id]
		return null
	set(val):
		_active_directive = val
var _active_directive: DirectiveResource = null
## Справочники всех государств и провинций мира для глобальной макро-симуляции
var countries_world_state: Dictionary = {} # Key: String (tag), Value: CountryState
var regions_world_state: Dictionary = {}   # Key: int (province_id), Value: RegionData
var state_to_provinces: Dictionary = {}    # Key: int (state_id), Value: Array[int]
var province_to_state: Dictionary = {}     # Key: int (province_id), Value: int (state_id)

var current_turn: int = 1

# Start date: January 1, 1962 (Unix Time)
var start_unix_time: int = 0

var current_state: TurnState = TurnState.IDLE
var pending_modal_events: Array[GameEvent] = []
var last_economic_report: EconomyEngine.EconomicTurnReport
var last_military_reports: Array[Dictionary] = []


func _init() -> void:
	if player_state == null:
		player_state = CountryState.new()


func _ready() -> void:
	start_unix_time = Time.get_unix_time_from_datetime_dict({"year": 1962, "month": 1, "day": 1, "hour": 12, "minute": 0, "second": 0})
	if player_state == null:
		player_state = CountryState.new()
	player_state.turn_count = current_turn
	player_state.set_flag("turn_count", current_turn)
	if not countries_world_state.has(player_state.country_tag):
		countries_world_state[player_state.country_tag] = player_state
	if event_manager == null:
		event_manager = EventManager.new()
		add_child(event_manager)
	if directive_manager == null:
		directive_manager = DirectiveManager.new()
		add_child(directive_manager)

	if research_manager == null:
		research_manager = ResearchManager.new()
		research_manager.name = "ResearchManager"
		add_child(research_manager)
	
	if focus_stage_controller == null:
		focus_stage_controller = FocusStageController.new()
		focus_stage_controller.name = "FocusStageController"
		add_child(focus_stage_controller)
		focus_stage_controller.setup(player_state, directive_manager, self, event_manager)

	_ensure_directive_manager_connected()


func _ensure_directive_manager_connected() -> void:
	if directive_manager == null:
		return
	if not directive_manager.directive_started.is_connected(_on_directive_started):
		directive_manager.directive_started.connect(_on_directive_started)
	if not directive_manager.directive_completed.is_connected(_on_directive_completed):
		directive_manager.directive_completed.connect(_on_directive_completed)
	if not directive_manager.directive_bypassed.is_connected(_on_directive_bypassed):
		directive_manager.directive_bypassed.connect(_on_directive_bypassed)
	if not directive_manager.directive_cancelled.is_connected(_on_directive_cancelled):
		directive_manager.directive_cancelled.connect(_on_directive_cancelled)
	if not directive_manager.directive_event_triggered.is_connected(_on_directive_event_triggered):
		directive_manager.directive_event_triggered.connect(_on_directive_event_triggered)
	if not directive_manager.directive_region_conquered.is_connected(_on_directive_region_conquered):
		directive_manager.directive_region_conquered.connect(_on_directive_region_conquered)
	if not directive_manager.directive_state_conquered.is_connected(_on_directive_state_conquered):
		directive_manager.directive_state_conquered.connect(_on_directive_state_conquered)

	if german_civil_war_manager == null:
		german_civil_war_manager = GermanCivilWarManager.new()
		add_child(german_civil_war_manager)

	if event_manager != null:
		if not event_manager.super_event_triggered.is_connected(_on_event_super_event):
			event_manager.super_event_triggered.connect(_on_event_super_event)
		if not event_manager.territory_transfer_requested.is_connected(_on_event_territory_transfer_requested):
			event_manager.territory_transfer_requested.connect(_on_event_territory_transfer_requested)
		if not event_manager.country_annexation_requested.is_connected(_on_event_country_annexation_requested):
			event_manager.country_annexation_requested.connect(_on_event_country_annexation_requested)

	if german_civil_war_manager != null:
		if not german_civil_war_manager.civil_war_erupted.is_connected(_on_gcw_erupted):
			german_civil_war_manager.civil_war_erupted.connect(_on_gcw_erupted)
		if not german_civil_war_manager.hitler_died.is_connected(_on_gcw_hitler_died):
			german_civil_war_manager.hitler_died.connect(_on_gcw_hitler_died)
		if not german_civil_war_manager.defcon_alert.is_connected(_on_gcw_defcon_alert):
			german_civil_war_manager.defcon_alert.connect(_on_gcw_defcon_alert)
		if not german_civil_war_manager.gcw_concluded.is_connected(_on_gcw_concluded):
			german_civil_war_manager.gcw_concluded.connect(_on_gcw_concluded)

	if us_electoral_engine == null:
		us_electoral_engine = USElectoralEngine.new()

	if russian_unification_manager == null:
		russian_unification_manager = RussianUnificationManager.new()
		russian_unification_manager.name = "RussianUnificationManager"
		add_child(russian_unification_manager)

	if russian_unification_manager != null:
		if player_state != null:
			russian_unification_manager.player_tag = player_state.country_tag
		if not russian_unification_manager.super_event_requested.is_connected(trigger_super_event):
			russian_unification_manager.super_event_requested.connect(trigger_super_event)
		if not russian_unification_manager.final_unification_achieved.is_connected(_on_rum_final_unification):
			russian_unification_manager.final_unification_achieved.connect(_on_rum_final_unification)
		if not russian_unification_manager.midnight_struck.is_connected(_on_rum_midnight_struck):
			russian_unification_manager.midnight_struck.connect(_on_rum_midnight_struck)

	if espionage_engine == null:
		espionage_engine = EspionageEngine.new()

	if japan_empire_manager == null:
		japan_empire_manager = JapanEmpireManager.new()
		japan_empire_manager.name = "JapanEmpireManager"
		add_child(japan_empire_manager)
		japan_empire_manager.initialize(self, player_state)

	if italy_empire_manager == null:
		italy_empire_manager = ItalyEmpireManager.new()
		italy_empire_manager.name = "ItalyEmpireManager"
		add_child(italy_empire_manager)
		italy_empire_manager.initialize(self, player_state)


func _on_directive_started(dir: DirectiveResource) -> void:
	_active_directive = dir
	directive_started.emit(dir)


func _on_directive_completed(dir: DirectiveResource) -> void:
	if _active_directive == dir or (_active_directive != null and _active_directive.id == dir.id):
		_active_directive = null
	directive_completed.emit(dir)


func _on_directive_bypassed(dir: DirectiveResource) -> void:
	if _active_directive == dir or (_active_directive != null and _active_directive.id == dir.id):
		_active_directive = null
	directive_bypassed.emit(dir)


func _on_directive_cancelled(dir: DirectiveResource, reason: String) -> void:
	if _active_directive == dir or (_active_directive != null and _active_directive.id == dir.id):
		_active_directive = null
	directive_cancelled.emit(dir, reason)


func _on_directive_event_triggered(ev_id: String) -> void:
	if event_manager != null:
		var ev = event_manager.get_or_load_event(ev_id)
		if ev != null:
			pending_modal_events.append(ev)

func _on_directive_region_conquered(province_id: int, new_owner_tag: String) -> void:
	var old_owner = ""
	if regions_world_state.has(province_id):
		var reg: RegionData = regions_world_state[province_id]
		old_owner = reg.owner_tag
		reg.owner_tag = new_owner_tag
	region_conquered.emit(province_id, new_owner_tag, old_owner)

func _on_directive_state_conquered(state_id: int, new_owner_tag: String) -> void:
	transfer_state(state_id, new_owner_tag)

func _on_event_territory_transfer_requested(state_id: int, new_owner_tag: String) -> void:
	transfer_state(state_id, new_owner_tag)

func _on_event_country_annexation_requested(victim_tag: String, annexer_tag: String) -> void:
	annex_country(victim_tag, annexer_tag)


## Передача суверенитета над штатом новому владельцу с реактивной синхронизацией LUT карты
func transfer_state(state_id: int, new_owner_tag: String) -> bool:
	if state_id <= 0:
		return false
	var clean_tag = new_owner_tag.to_upper().strip_edges()
	var old_owner = ""

	# 1. Поиск BoundaryManager, если не привязан
	if boundary_manager == null:
		if has_node("BoundaryManager"):
			boundary_manager = get_node("BoundaryManager") as BoundaryManager
		elif get_parent() != null and get_parent().has_node("BoundaryManager"):
			boundary_manager = get_parent().get_node("BoundaryManager") as BoundaryManager

	# 2. Если есть BoundaryManager - используем его для топологического трансфера
	if boundary_manager != null:
		var prev_tag = boundary_manager.state_to_owner.get(state_id, "")
		var ok = boundary_manager.transfer_state(state_id, clean_tag)
		if ok:
			state_conquered.emit(state_id, clean_tag)
			state_transferred.emit(state_id, prev_tag, clean_tag)
			return true

	# 3. Fallback трансфер в локальном world_state
	var provs = state_to_provinces.get(state_id, [])
	for pid in provs:
		if regions_world_state.has(pid):
			var reg: RegionData = regions_world_state[pid]
			if old_owner.is_empty():
				old_owner = reg.owner_tag
			reg.owner_tag = clean_tag
			region_conquered.emit(pid, clean_tag, old_owner)

	# 4. Обновление контролируемых штатов CountryState
	var target_st: CountryState = null
	if player_state != null and player_state.country_tag.to_upper() == clean_tag:
		target_st = player_state
	elif countries_world_state.has(clean_tag):
		target_st = countries_world_state[clean_tag]

	if target_st != null:
		if not target_st.controlled_states.has(state_id):
			target_st.controlled_states.append(state_id)
		if not target_st.owned_states.has(state_id):
			target_st.owned_states.append(state_id)

	var prev_st: CountryState = null
	if not old_owner.is_empty():
		if player_state != null and player_state.country_tag.to_upper() == old_owner:
			prev_st = player_state
		elif countries_world_state.has(old_owner):
			prev_st = countries_world_state[old_owner]

	if prev_st != null:
		prev_st.controlled_states.erase(state_id)
		prev_st.owned_states.erase(state_id)

	# 5. Реактивное обновление MapController, если он доступен
	_sync_map_controller_reactive([state_id], clean_tag)

	state_conquered.emit(state_id, clean_tag)
	state_transferred.emit(state_id, old_owner, clean_tag)
	return true


## Аннексия целого государства
func annex_country(victim_tag: String, annexer_tag: String) -> void:
	var v_tag = victim_tag.to_upper().strip_edges()
	var a_tag = annexer_tag.to_upper().strip_edges()
	var states_to_transfer: Array[int] = []

	if boundary_manager != null and boundary_manager.country_states.has(v_tag):
		states_to_transfer = boundary_manager.country_states[v_tag].duplicate()
	else:
		for pid in regions_world_state.keys():
			var reg: RegionData = regions_world_state[pid]
			if reg.owner_tag.to_upper() == v_tag:
				var sid = province_to_state.get(pid, 0)
				if sid > 0 and not states_to_transfer.has(sid):
					states_to_transfer.append(sid)

	for sid in states_to_transfer:
		transfer_state(sid, a_tag)


## Реактивная синхронизация шейдерной палитры карты
func _sync_map_controller_reactive(affected_states: Array[int], new_owner_tag: String = "") -> void:
	if map_controller == null:
		if has_node("../TabContainer/TacticalMap/SubViewportContainer/SubViewport/MapController"):
			map_controller = get_node("../TabContainer/TacticalMap/SubViewportContainer/SubViewport/MapController")
	if map_controller == null:
		return

	for sid in affected_states:
		if map_controller.has_method("set_state_owner"):
			map_controller.set_state_owner(sid, new_owner_tag)
		else:
			var provs = state_to_provinces.get(sid, [])
			for pid in provs:
				if map_controller.has_method("set_province_owner"):
					map_controller.set_province_owner(pid, new_owner_tag)
				elif map_controller.has_method("update_province_owner"):
					map_controller.update_province_owner(pid, new_owner_tag)

	if map_controller.has_method("populate_data_lut_from_regions") and not regions_world_state.is_empty():
		var p_tag = player_state.country_tag if player_state != null else "KOM"
		map_controller.populate_data_lut_from_regions(regions_world_state, p_tag)


func _on_event_super_event(super_event_id: String) -> void:
	super_event_requested.emit(super_event_id)



func _on_gcw_erupted() -> void:
	super_event_requested.emit("SE_GERMAN_CIVIL_WAR")


func _on_gcw_hitler_died() -> void:
	super_event_requested.emit("SE_GERMAN_CIVIL_WAR")


func _on_gcw_defcon_alert(level: int, _reason: String) -> void:
	if level <= 1:
		super_event_requested.emit("SE_NUCLEAR_WAR")


func trigger_super_event(super_event_id: String) -> void:
	super_event_requested.emit(super_event_id)


## Назначение стейта игрока с синхронизацией хода и модулей
func set_player_state(st: CountryState) -> void:
	if st == null:
		return
	player_state = st
	player_state.turn_count = current_turn
	player_state.set_flag("turn_count", current_turn)
	countries_world_state[player_state.country_tag] = player_state
	if russian_unification_manager != null:
		russian_unification_manager.player_tag = player_state.country_tag
	if focus_stage_controller != null and directive_manager != null and event_manager != null:
		focus_stage_controller.setup(player_state, directive_manager, self, event_manager)



## Загрузка мировой географии и государств из JSON базы данных
func load_world_data(
	regions_path: String = "res://map_data/starting_regions_state.json",
	countries_path: String = "res://map_data/starting_countries_state.json",
	manifest_path: String = "res://map_data/map_manifest.json"
) -> void:
	# 1. Загрузка стартовых стран
	if FileAccess.file_exists(countries_path):
		var f_c = FileAccess.open(countries_path, FileAccess.READ)
		if f_c != null:
			var text = f_c.get_as_text()
			f_c.close()
			var json = JSON.new()
			if json.parse(text) == OK and json.data is Dictionary:
				for c_tag in json.data.keys():
					var c_dict: Dictionary = json.data[c_tag]
					if player_state != null and c_tag == player_state.country_tag:
						countries_world_state[c_tag] = player_state
						continue
					var c_state = CountryState.from_dict(c_dict)
					countries_world_state[c_tag] = c_state

	# Сохраняем стейт игрока во всеобщем справочнике
	if player_state != null:
		countries_world_state[player_state.country_tag] = player_state

	# 2. Загрузка манифеста (штаты и связь с провинциями)
	var loaded_states = false
	if FileAccess.file_exists(manifest_path):
		var f_m = FileAccess.open(manifest_path, FileAccess.READ)
		if f_m != null:
			var m_txt = f_m.get_as_text()
			f_m.close()
			var json_m = JSON.new()
			if json_m.parse(m_txt) == OK and json_m.data is Dictionary:
				var states_dict = json_m.data.get("states", {})
				for sid_str in states_dict.keys():
					var sid = int(sid_str)
					var s_info = states_dict[sid_str]
					var provs = s_info.get("provinces", [])
					var int_provs: Array[int] = []
					for p in provs:
						var pid = int(p)
						int_provs.append(pid)
						province_to_state[pid] = sid
					state_to_provinces[sid] = int_provs

				# Если в манифесте нет секции states, извлекаем штаты из провинций
				if state_to_provinces.is_empty() and json_m.data.has("provinces"):
					var provs_dict = json_m.data["provinces"]
					for pid_str in provs_dict.keys():
						var pid = int(pid_str)
						var p_info = provs_dict[pid_str]
						if p_info is Dictionary and p_info.has("state_id"):
							var sid = int(p_info["state_id"])
							if sid > 0:
								province_to_state[pid] = sid
								if not state_to_provinces.has(sid):
									var new_provs: Array[int] = []
									state_to_provinces[sid] = new_provs
								state_to_provinces[sid].append(pid)

				if not state_to_provinces.is_empty():
					loaded_states = true

	# Дополнительный фоллбек: если штаты не были загружены, проверяем extracted_tno_data
	if not loaded_states and FileAccess.file_exists("res://extracted_tno_data/map_manifest.json"):
		var f_ext = FileAccess.open("res://extracted_tno_data/map_manifest.json", FileAccess.READ)
		if f_ext != null:
			var ext_txt = f_ext.get_as_text()
			f_ext.close()
			var json_ext = JSON.new()
			if json_ext.parse(ext_txt) == OK and json_ext.data is Dictionary:
				var ext_states = json_ext.data.get("states", {})
				for sid_str in ext_states.keys():
					var sid = int(sid_str)
					var s_info = ext_states[sid_str]
					var provs = s_info.get("provinces", [])
					var int_provs: Array[int] = []
					for p in provs:
						var pid = int(p)
						int_provs.append(pid)
						province_to_state[pid] = sid
					state_to_provinces[sid] = int_provs

	# 3. Загрузка стартовых провинций
	if FileAccess.file_exists(regions_path):
		var f_r = FileAccess.open(regions_path, FileAccess.READ)
		if f_r != null:
			var r_txt = f_r.get_as_text()
			f_r.close()
			var json_r = JSON.new()
			if json_r.parse(r_txt) == OK and json_r.data is Dictionary:
				for pid_str in json_r.data.keys():
					var pid = int(pid_str)
					var r_dict: Dictionary = json_r.data[pid_str]
					var r_data = RegionData.from_dict(r_dict)
					regions_world_state[pid] = r_data

	print("[TurnManager] Loaded world data: %d regions, %d countries, %d states." % [
		regions_world_state.size(), countries_world_state.size(), state_to_provinces.size()
	])
	world_data_loaded.emit(regions_world_state.size(), countries_world_state.size())


## Алиас для пошагового расчета (совместимость тестов и UI)
func process_turn() -> void:
	end_turn()


## Возвращает красиво отформатированную дату в стиле TNO / Холодной войны
func get_formatted_date() -> String:
	var current_unix = start_unix_time + (current_turn - 1) * 7 * 86400
	var dict = Time.get_datetime_dict_from_unix_time(current_unix)
	
	var months = [
		"JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE",
		"JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"
	]
	var m_name = months[clampi(dict["month"] - 1, 0, 11)]
	
	# Формат: "14 JANUARY 1962" (или можно оставить "WEEK X", но с точной датой лучше)
	return "%d %s %d" % [dict["day"], m_name, dict["year"]]


## Главный метод завершения хода (вызывается кнопкой «Завершить ход» в UI)
func end_turn() -> void:
	if current_state == TurnState.WAITING_FOR_MODAL_EVENT:
		push_warning("TurnManager: Нельзя завершить ход, пока открыт неразрешенный модальный кризис!")
		return

	# 1. Сброс и начисление тактических очков (Data-Driven через ConfigManager)
	var cfg = ConfigManager.get_instance()
	var base_pc_gain = cfg.get_float("politics", "base_pc_gain_per_turn", 5.0) if cfg != null else 5.0
	var base_cap = cfg.get_int("politics", "base_max_cap", 5) if cfg != null else 5

	if player_state.max_cap <= 0:
		player_state.max_cap = base_cap
	player_state.current_cap = player_state.max_cap

	var pc_gain = player_state.pc_gain_per_turn if player_state.pc_gain_per_turn > 0.0 else base_pc_gain
	player_state.political_capital += pc_gain

	# 2. Фаза экономики
	current_state = TurnState.PROCESSING_ECONOMY
	phase_changed.emit("PROCESSING_ECONOMY")
	last_economic_report = EconomyEngine.process_turn(player_state, regions_world_state)
	if last_economic_report != null and not last_economic_report.societal_evolution_data.is_empty():
		societal_evolution_completed.emit(last_economic_report.societal_evolution_data)

	# Расчет макроэкономики для остальных государств мира (World AI Economy)
	for c_tag in countries_world_state.keys():
		if c_tag != player_state.country_tag:
			var ai_st: CountryState = countries_world_state[c_tag]
			if ai_st != null:
				EconomyEngine.process_ai_turn(ai_st)

	# 2.5. Фаза научно-технических исследований (R&D / PROCESSING_RESEARCH)
	if research_manager != null:
		var tech_reps = research_manager.process_turn(current_turn, player_state)
		for rep in tech_reps:
			tech_completed.emit(rep)

	# 3. Фаза директив и стадий
	current_state = TurnState.PROCESSING_DIRECTIVES
	phase_changed.emit("PROCESSING_DIRECTIVES")
	if focus_stage_controller != null:
		focus_stage_controller.process_turn(1, player_state)
	_process_directives_phase()

	# 3.5. Системная фаза шпионажа и тайных операций (PHASE_ESPIONAGE)
	current_state = TurnState.PHASE_ESPIONAGE
	phase_changed.emit("PHASE_ESPIONAGE")
	if espionage_engine == null:
		espionage_engine = EspionageEngine.new()
	last_espionage_reports = espionage_engine.process_turn(countries_world_state, 1)
	espionage_processed.emit(last_espionage_reports)
	_process_sabotage_and_coups()

	# 4. Фаза фронтов и макро-войны
	current_state = TurnState.PROCESSING_MILITARY
	phase_changed.emit("PROCESSING_MILITARY")
	last_military_reports = MilitaryEngine.simulate_frontlines(1, countries_world_state, regions_world_state)
	military_frontlines_processed.emit(last_military_reports)

	pending_modal_events.clear()

	# Проверка результатов фронтов на захват регионов, боевые инциденты и капитуляцию
	for rep in last_military_reports:
		if rep.get("captured_region_id", -1) > 0:
			var reg_id = int(rep["captured_region_id"])
			var n_tag = str(rep.get("new_owner", "")).to_upper()
			var p_tag = str(rep.get("previous_owner", "")).to_upper()
			var sid = province_to_state.get(reg_id, 0)
			if sid > 0:
				var provs = state_to_provinces.get(sid, [])
				var all_ours = true
				for p in provs:
					var r: RegionData = regions_world_state.get(p, null)
					if r != null and r.owner_tag.to_upper() != n_tag:
						all_ours = false
						break
				if all_ours:
					transfer_state(sid, n_tag)
			region_conquered.emit(reg_id, n_tag, p_tag)
			_sync_map_controller_reactive([sid] if sid > 0 else [], n_tag)

		if rep.get("battle_incident") != null:
			var inc: GameEvent = rep["battle_incident"]
			pending_modal_events.append(inc)

		if rep.get("capitulation", false):
			var victor = str(rep.get("victor_tag", "")).to_upper()
			var defeated = str(rep.get("defeated_tag", "")).to_upper()
			if not defeated.is_empty() and not victor.is_empty():
				annex_country(defeated, victor)
				if countries_world_state.has(defeated):
					var def_st: CountryState = countries_world_state[defeated]
					if def_st != null:
						def_st.is_annexed = true
				if player_state != null and player_state.country_tag == defeated:
					player_state.is_annexed = true
					_trigger_game_over(false, "Ваша держава пала под натиском войск %s и безоговорочно капитулировала." % victor)
				elif player_state != null and player_state.country_tag == victor:
					player_state.legitimacy = clampf(player_state.legitimacy + 12.0, 0.0, 100.0)
					player_state.army_morale = clampf(player_state.army_morale + 15.0, 0.0, 100.0)

	# 4.1. Кампания Германии / Немецкая Гражданская Война (GCW)
	if german_civil_war_manager != null:
		german_civil_war_manager.process_turn(current_turn)

	# 4.2. Кампания Русской Смуты и Воссоединения (Smuta / Unification)
	if russian_unification_manager != null:
		if player_state != null:
			russian_unification_manager.player_tag = player_state.country_tag
		russian_unification_manager.process_turn(current_turn, player_state)

	# 4.3. Электоральная система и политика США (US Politics)
	if us_electoral_engine != null:
		var target_usa_state = player_state if (player_state != null and player_state.country_tag == "USA") else countries_world_state.get("USA", null)
		if target_usa_state != null:
			var usa_report = us_electoral_engine.process_turn(current_turn, target_usa_state)
			if usa_report.get("midterm_triggered", false) or usa_report.get("presidential_triggered", false):
				us_electoral_report_generated.emit(usa_report)

	# 4.4. Империя Японии / Кризис Ясуда и Дайэт (Japan Politics & Zaibatsu)
	if japan_empire_manager != null:
		var target_jap_state = player_state if (player_state != null and player_state.country_tag == "JAP") else countries_world_state.get("JAP", null)
		japan_empire_manager.process_turn(current_turn, target_jap_state, countries_world_state)

	# 4.5. Итальянская Империя / Распад Триумвирата и Битва за Средиземноморье (Italy & Triumvirate)
	if italy_empire_manager != null:
		var target_ita_state = player_state if (player_state != null and player_state.country_tag == "ITA") else countries_world_state.get("ITA", null)
		italy_empire_manager.process_turn(current_turn, target_ita_state, countries_world_state)

	# 5. Фаза проверки нарративных событий и кризисов
	current_state = TurnState.CHECKING_EVENTS
	phase_changed.emit("CHECKING_EVENTS")
	var triggered_events: Array[GameEvent] = []
	if event_manager != null:
		triggered_events = event_manager.evaluate_turn_triggers(player_state, current_turn)

	for ev in triggered_events:
		if ev.is_modal:
			pending_modal_events.append(ev)

	# 6. Проверка блокирующих модальных событий
	if not pending_modal_events.is_empty():
		current_state = TurnState.WAITING_FOR_MODAL_EVENT
		_display_next_modal_event()
	else:
		_finalize_turn()


## Запуск национальной директивы в работу
func start_directive(directive: DirectiveResource, force: bool = false) -> bool:
	if directive_manager != null and directive != null and player_state != null:
		_ensure_directive_manager_connected()
		var dir_id = directive.id if not directive.id.is_empty() else directive.directive_id
		if not directive_manager.all_directives.has(dir_id):
			directive_manager.register_directive(directive)
		var success = directive_manager.start_directive(dir_id, player_state, force)
		if success:
			if player_state.active_directives.has(dir_id):
				_active_directive = directive
				directive_started.emit(directive)
			else:
				_active_directive = null
		return success
	return false



## Фаза пошагового расчета прогресса директивы
func _process_directives_phase() -> void:
	if directive_manager != null:
		var completed = directive_manager.advance_turn(player_state)
		for dir in completed:
			if _active_directive == dir or (_active_directive != null and _active_directive.id == dir.id):
				_active_directive = null
			directive_completed.emit(dir)



func _display_next_modal_event() -> void:
	if pending_modal_events.is_empty():
		current_state = TurnState.IDLE
		_finalize_turn()
		return

	var next_event = pending_modal_events.pop_front()
	modal_event_opened.emit(next_event)


## Вызывается UI при выборе варианта в модальном диалоге события
func resolve_modal_event_choice(event: GameEvent, option_index: int) -> void:
	if option_index >= 0 and option_index < event.options.size():
		var chosen_opt = event.options[option_index]
		event_manager.resolve_event_option(event, chosen_opt, player_state)

	# Переход к следующему модальному событию в очереди, если есть
	if not pending_modal_events.is_empty():
		_display_next_modal_event()
	else:
		current_state = TurnState.IDLE
		_finalize_turn()


func _finalize_turn() -> void:
	# Продвижение календаря (1 ход = 7 реальных дней)
	current_turn += 1
	if player_state != null:
		player_state.turn_count = current_turn
		player_state.set_flag("turn_count", current_turn)
	for c_tag in countries_world_state.keys():
		var c_st = countries_world_state[c_tag]
		if c_st is CountryState:
			c_st.turn_count = current_turn
			c_st.set_flag("turn_count", current_turn)
	current_state = TurnState.IDLE
	save_game("user://savegame.json")
	save_game("user://autosave.json")
	autosaved.emit(current_turn, "user://savegame.json")
	turn_completed.emit(current_turn, last_economic_report)
	turn_started.emit(current_turn, get_formatted_date())
	_check_game_over_conditions()


## Проверка таймеров саботажа и назревающих переворотов
func _process_sabotage_and_coups() -> void:
	for c_tag in countries_world_state.keys():
		var c_st: CountryState = countries_world_state[c_tag]
		if c_st == null:
			continue

		# 1. Таймер саботажа производства
		if c_st.story_flags.has("sabotage_ic_turns"):
			var t_left = int(c_st.story_flags["sabotage_ic_turns"]) - 1
			if t_left <= 0:
				c_st.story_flags.erase("sabotage_ic_turns")
				c_st.story_flags.erase("sabotage_ic_modifier")
			else:
				c_st.story_flags["sabotage_ic_turns"] = t_left

		# 2. Неминуемый государственный переворот
		if bool(c_st.story_flags.get("coup_imminent", false)):
			c_st.story_flags.erase("coup_imminent")
			var sponsor = str(c_st.story_flags.get("coup_sponsor", ""))
			c_st.story_flags.erase("coup_sponsor")
			_resolve_coup(c_st, sponsor)


## Разрешение государственного переворота
func _resolve_coup(victim: CountryState, sponsor_tag: String) -> void:
	victim.legitimacy = maxf(victim.legitimacy - 35.0, 5.0)
	victim.radicalization = minf(victim.radicalization + 30.0, 95.0)

	if not sponsor_tag.is_empty() and countries_world_state.has(sponsor_tag):
		var sponsor: CountryState = countries_world_state[sponsor_tag]
		if sponsor != null:
			victim.ruling_ideology = sponsor.ruling_ideology
			victim.faction = sponsor.faction
			if sponsor == player_state:
				player_state.political_capital += 25.0
				player_state.legitimacy = clampf(player_state.legitimacy + 5.0, 0.0, 100.0)

	if victim == player_state:
		var coup_event = GameEvent.new()
		coup_event.event_id = "crisis_military_coup_%d" % current_turn
		coup_event.title = "ГОСУДАРСТВЕННЫЙ ПЕРЕВОРОТ!"
		coup_event.classification = "[КРИЗИС ВЛАСТИ // ЧРЕЗВЫЧАЙНОЕ ПОЛОЖЕНИЕ]"
		coup_event.description = "Офицеры генштаба и заговорщики окружили правительственный квартал. Прежнее руководство свергнуто."
		coup_event.is_modal = true
		coup_event.options = [
			{
				"option_id": "opt_accept_junta",
				"text": "Признать власть Военной Хунты (-20 к легитимности)",
				"effects": {"modify_legitimacy": -20.0, "modify_radicalization": 15.0}
			}
		]
		pending_modal_events.append(coup_event)


## Проверка финальных условий победы или поражения игрока
func _check_game_over_conditions() -> void:
	if player_state == null:
		return

	# 1. Аннексия государства игрока
	if player_state.is_annexed:
		_trigger_game_over(false, "Ваша держава была аннексирована и стерта с политической карты мира.")
		return

	# 2. Тотальный крах легитимности и революция
	if player_state.legitimacy <= 0.0 and player_state.radicalization >= 95.0:
		_trigger_game_over(false, "Тотальный крах государственности: легитимность рухнула до нуля, в стране бушует восстание и анархия.")
		return

	# 3. Суверенный фискальный дефолт
	if player_state.is_in_fiscal_crisis and player_state.get_debt_to_gdp_ratio() >= 2.5 and player_state.liquid_reserves_billions <= -50.0:
		_trigger_game_over(false, "Фискальный коллапс: национальный долг превысил 250% ВВП при отрицательных резервах. Полное банкротство страны.")
		return


func _trigger_game_over(victory: bool, reason: String) -> void:
	game_over.emit(victory, reason)
	var ev = GameEvent.new()
	ev.event_id = "game_over_victory" if victory else "game_over_defeat"
	ev.title = "ВЕЛИКИЙ ТРИУМФ НАЦИИ" if victory else "НАЦИОНАЛЬНАЯ КАТАСТРОФА"
	ev.classification = "[КОНЕЦ ИГРЫ // ПОБЕДА]" if victory else "[КОНЕЦ ИГРЫ // ПОРАЖЕНИЕ]"
	ev.description = reason
	ev.is_modal = true
	ev.options = [
		{
			"option_id": "opt_game_over_ack",
			"text": "Принять неизбежный финал истории",
			"effects": {}
		}
	]
	pending_modal_events.clear()
	modal_event_opened.emit(ev)


func _on_rum_final_unification(tag: String, _leader: String, _super_event_id: String) -> void:
	if player_state != null and tag.to_upper() == player_state.country_tag.to_upper():
		_trigger_game_over(true, "Священная миссия завершена! Вы окончательно объединили Россию и положили конец эпохе Русской Смуты!")
	else:
		_trigger_game_over(false, "Россия была окончательно воссоединена державой %s. Ваша фракция повержена." % tag)


func _on_rum_midnight_struck() -> void:
	_trigger_game_over(false, "Часы Судного Дня пробили полночь. Режим рухнул в бездну безумия и ядерного кошмара.")


func _on_gcw_concluded(victor_tag: String) -> void:
	if player_state != null and victor_tag.to_upper() == player_state.country_tag.to_upper():
		_trigger_game_over(true, "Борьба за Рейх завершена вашей триумфальной победой! Германия под вашим полным контролем.")
	elif player_state != null and player_state.country_tag in ["BOR", "SPE", "GOR", "HEY"]:
		_trigger_game_over(false, "Гражданская война в Германии проиграна. Власть в Рейхе захватил %s." % victor_tag)


## Сохранение текущей игровой сессии в JSON архив
func save_game(save_path: String = "user://savegame.json") -> bool:
	if player_state == null:
		return false

	var save_dict: Dictionary = {
		"version": 2,
		"current_turn": current_turn,
		"player_tag": player_state.country_tag,
		"player_state": player_state.to_dict(),
		"active_directive_id": active_directive.id if active_directive != null else "",
		"completed_directives": player_state.completed_directives.duplicate(),
		"story_flags": player_state.story_flags.duplicate(true),
		"fired_events": event_manager.fired_events.duplicate() if event_manager != null else [],
		"frontlines": [],
		"countries_world_state": {},
		"regions_world_state": {},
		"directive_progress": {}
	}

	for front in MilitaryEngine.get_active_frontlines():
		if front != null and front.has_method("to_dict"):
			save_dict["frontlines"].append(front.to_dict())

	for c_tag in countries_world_state.keys():
		var c_st = countries_world_state[c_tag]
		if c_st is CountryState:
			save_dict["countries_world_state"][c_tag] = c_st.to_dict()

	for pid in regions_world_state.keys():
		var r_data = regions_world_state[pid]
		if r_data is RegionData:
			save_dict["regions_world_state"][str(pid)] = r_data.to_dict()

	if directive_manager != null:
		save_dict["directive_progress"] = directive_manager.active_progress.duplicate(true)

	var f = FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_error("TurnManager: Не удалось открыть файл сохранения: %s" % save_path)
		return false
	f.store_string(JSON.stringify(save_dict, "\t"))
	f.close()
	print("[TurnManager] Сохранение успешно создано: %s (Ход %d, Держав: %d, Регионов: %d)" % [
		save_path, current_turn, save_dict["countries_world_state"].size(), save_dict["regions_world_state"].size()
	])
	return true


## Загрузка игровой сессии из JSON архива
func load_game(save_path: String = "user://savegame.json") -> bool:
	if not FileAccess.file_exists(save_path):
		push_error("TurnManager: Файл сохранения не найден: %s" % save_path)
		return false

	var f = FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return false
	var text = f.get_as_text()
	f.close()

	var json = JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		push_error("TurnManager: Ошибка чтения JSON из: %s" % save_path)
		return false

	var data: Dictionary = json.data
	current_turn = int(data.get("current_turn", 1))

	var p_data = data.get("player_state", {})
	if not p_data.is_empty():
		player_state = CountryState.from_dict(p_data)
		player_state.turn_count = current_turn
		player_state.set_flag("turn_count", current_turn)
		countries_world_state[player_state.country_tag] = player_state

	# Восстановление состояния всех держав мира
	if data.has("countries_world_state") and data["countries_world_state"] is Dictionary:
		for c_tag in data["countries_world_state"].keys():
			var c_dict = data["countries_world_state"][c_tag]
			if c_dict is Dictionary:
				var c_st = CountryState.from_dict(c_dict)
				c_st.turn_count = current_turn
				countries_world_state[c_tag] = c_st
		if countries_world_state.has(player_state.country_tag):
			player_state = countries_world_state[player_state.country_tag]

	# Восстановление состояния всех регионов и провинций
	if data.has("regions_world_state") and data["regions_world_state"] is Dictionary:
		for pid_str in data["regions_world_state"].keys():
			var r_dict = data["regions_world_state"][pid_str]
			if r_dict is Dictionary:
				regions_world_state[int(pid_str)] = RegionData.from_dict(r_dict)

	if event_manager != null and data.has("fired_events"):
		event_manager.fired_events.clear()
		for ev_id in data["fired_events"]:
			event_manager.fired_events.append(str(ev_id))

	if directive_manager != null and data.has("directive_progress") and data["directive_progress"] is Dictionary:
		directive_manager.active_progress = data["directive_progress"].duplicate(true)

	if data.has("frontlines") and data["frontlines"] is Array:
		MilitaryEngine.clear_frontlines()
		for f_dict in data["frontlines"]:
			if f_dict is Dictionary:
				var front = Frontline.from_dict(f_dict)
				if front != null:
					MilitaryEngine.register_frontline(front)
		military_frontlines_processed.emit(MilitaryEngine.get_active_frontlines())

	# Синхронизация карты после загрузки
	if map_controller != null:
		if map_controller.has_method("populate_data_lut_from_regions") and not regions_world_state.is_empty():
			map_controller.populate_data_lut_from_regions(regions_world_state, player_state.country_tag)
		if map_controller.has_method("refresh_tactical_frontlines"):
			map_controller.refresh_tactical_frontlines()

	print("[TurnManager] Сохранение загружено: Ход %d, Держава: %s (Мир: %d держав, %d регионов)" % [
		current_turn, player_state.country_tag, countries_world_state.size(), regions_world_state.size()
	])
	turn_started.emit(current_turn, get_formatted_date())
	return true
