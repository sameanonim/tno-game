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
signal defcon_level_changed(level: int, reason: String)

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

const TurnSerializerScript = preload("res://core/systems/turn_serializer.gd")
const DemographicsEngineScript = preload("res://core/systems/demographics_engine.gd")
const TurnTerritoryHandlerScript = preload("res://core/systems/turn_territory_handler.gd")
const TurnCrisisHandlerScript = preload("res://core/systems/turn_crisis_handler.gd")

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
var _event_manager_node: EventManager = null
@export var event_manager: EventManager:
	get:
		if _event_manager_node != null:
			return _event_manager_node
		if has_node("EventManager"):
			_event_manager_node = get_node("EventManager") as EventManager
		elif _event_manager_node == null:
			_event_manager_node = EventManager.new()
			_event_manager_node.name = "EventManager"
			if is_inside_tree():
				add_child(_event_manager_node)
		return _event_manager_node
	set(val):
		_event_manager_node = val

var _directive_manager_node: DirectiveManager = null
@export var directive_manager: DirectiveManager:
	get:
		if _directive_manager_node != null:
			return _directive_manager_node
		if has_node("DirectiveManager"):
			_directive_manager_node = get_node("DirectiveManager") as DirectiveManager
		elif _directive_manager_node == null:
			_directive_manager_node = DirectiveManager.new()
			_directive_manager_node.name = "DirectiveManager"
			if is_inside_tree():
				add_child(_directive_manager_node)
		return _directive_manager_node
	set(val):
		_directive_manager_node = val

var _focus_stage_controller_node: FocusStageController = null
@export var focus_stage_controller: FocusStageController:
	get:
		if _focus_stage_controller_node != null:
			return _focus_stage_controller_node
		if has_node("FocusStageController"):
			_focus_stage_controller_node = get_node("FocusStageController") as FocusStageController
		elif _focus_stage_controller_node == null:
			_focus_stage_controller_node = FocusStageController.new()
			_focus_stage_controller_node.name = "FocusStageController"
			if is_inside_tree():
				add_child(_focus_stage_controller_node)
		return _focus_stage_controller_node
	set(val):
		_focus_stage_controller_node = val

var _german_civil_war_manager_node: GermanCivilWarManager = null
@export var german_civil_war_manager: GermanCivilWarManager:
	get:
		if _german_civil_war_manager_node != null:
			return _german_civil_war_manager_node
		if has_node("GermanCivilWarManager"):
			_german_civil_war_manager_node = get_node("GermanCivilWarManager") as GermanCivilWarManager
		elif _german_civil_war_manager_node == null:
			_german_civil_war_manager_node = GermanCivilWarManager.new()
			_german_civil_war_manager_node.name = "GermanCivilWarManager"
			if is_inside_tree():
				add_child(_german_civil_war_manager_node)
		return _german_civil_war_manager_node
	set(val):
		_german_civil_war_manager_node = val

var _germany_campaign_manager_node: GermanyCampaignManager = null
@export var germany_campaign_manager: GermanyCampaignManager:
	get:
		if _germany_campaign_manager_node != null:
			return _germany_campaign_manager_node
		if has_node("GermanyCampaignManager"):
			_germany_campaign_manager_node = get_node("GermanyCampaignManager") as GermanyCampaignManager
		elif _germany_campaign_manager_node == null:
			_germany_campaign_manager_node = GermanyCampaignManager.new()
			_germany_campaign_manager_node.name = "GermanyCampaignManager"
			if is_inside_tree():
				add_child(_germany_campaign_manager_node)
		return _germany_campaign_manager_node
	set(val):
		_germany_campaign_manager_node = val

@export var russian_unification_manager: RussianUnificationManager:
	get:
		if russian_unification_manager == null:
			if has_node("RussianUnificationManager"):
				russian_unification_manager = get_node("RussianUnificationManager") as RussianUnificationManager
			else:
				russian_unification_manager = RussianUnificationManager.new()
				russian_unification_manager.name = "RussianUnificationManager"
				if is_inside_tree():
					add_child(russian_unification_manager)
		return russian_unification_manager
	set(val):
		russian_unification_manager = val

var _japan_empire_manager_node: JapanEmpireManager = null
@export var japan_empire_manager: JapanEmpireManager:
	get:
		if _japan_empire_manager_node != null:
			return _japan_empire_manager_node
		if has_node("JapanEmpireManager"):
			_japan_empire_manager_node = get_node("JapanEmpireManager") as JapanEmpireManager
		elif _japan_empire_manager_node == null:
			_japan_empire_manager_node = JapanEmpireManager.new()
			_japan_empire_manager_node.name = "JapanEmpireManager"
			if is_inside_tree():
				add_child(_japan_empire_manager_node)
		return _japan_empire_manager_node
	set(val):
		_japan_empire_manager_node = val

var _italy_empire_manager_node: ItalyEmpireManager = null
@export var italy_empire_manager: ItalyEmpireManager:
	get:
		if _italy_empire_manager_node != null:
			return _italy_empire_manager_node
		if has_node("ItalyEmpireManager"):
			_italy_empire_manager_node = get_node("ItalyEmpireManager") as ItalyEmpireManager
		elif _italy_empire_manager_node == null:
			_italy_empire_manager_node = ItalyEmpireManager.new()
			_italy_empire_manager_node.name = "ItalyEmpireManager"
			if is_inside_tree():
				add_child(_italy_empire_manager_node)
		return _italy_empire_manager_node
	set(val):
		_italy_empire_manager_node = val

var _research_manager_node: ResearchManager = null
@export var research_manager: ResearchManager:
	get:
		if _research_manager_node != null:
			return _research_manager_node
		if has_node("ResearchManager"):
			_research_manager_node = get_node("ResearchManager") as ResearchManager
		elif _research_manager_node == null:
			_research_manager_node = ResearchManager.new()
			_research_manager_node.name = "ResearchManager"
			if is_inside_tree():
				add_child(_research_manager_node)
		return _research_manager_node
	set(val):
		_research_manager_node = val

@export var boundary_manager: BoundaryManager:
	get:
		if boundary_manager == null:
			if has_node("BoundaryManager"):
				boundary_manager = get_node("BoundaryManager") as BoundaryManager
			else:
				boundary_manager = BoundaryManager.new()
				boundary_manager.name = "BoundaryManager"
				if is_inside_tree():
					add_child(boundary_manager)
		return boundary_manager
	set(val):
		boundary_manager = val
@export var map_controller: Node = null:
	set(val):
		map_controller = val
		if val is MapController and boundary_manager != null:
			boundary_manager.map_controller = val
var espionage_engine: EspionageEngine = null
var us_electoral_engine: USElectoralEngine = null
var last_espionage_reports: Array[Dictionary] = []

## Текущая активная государственная директива игрока
var active_directive: DirectiveResource:
	get:
		if _active_directive != null:
			return _active_directive
		if player_state != null and not player_state.active_directives.is_empty() and directive_manager != null:
			var act_id: String = player_state.active_directives[0]
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
var _cached_serialized_regions: Dictionary = {} # Кэш сериализованных регионов для мгновенных дельта-сейвов

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
	if not us_electoral_engine.president_elected.is_connected(_on_us_president_elected):
		us_electoral_engine.president_elected.connect(_on_us_president_elected)

	if germany_campaign_manager != null and german_civil_war_manager != null:
		germany_campaign_manager.initialize(german_civil_war_manager)

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

	if german_civil_war_manager == null:
		german_civil_war_manager = GermanCivilWarManager.new()
		german_civil_war_manager.name = "GermanCivilWarManager"
		add_child(german_civil_war_manager)
		german_civil_war_manager.initialize(self, map_controller, player_state)

	if germany_campaign_manager == null:
		germany_campaign_manager = GermanyCampaignManager.new()
		germany_campaign_manager.name = "GermanyCampaignManager"
		add_child(germany_campaign_manager)
		germany_campaign_manager.civil_war_manager = german_civil_war_manager


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


func _on_directive_event_triggered(ev_id: String, delay_days: int = 0) -> void:
	if event_manager != null:
		if delay_days > 0:
			var turns_delay = maxi(1, int(ceil(float(delay_days) / 7.0)))
			event_manager.schedule_event(ev_id, turns_delay, current_turn, player_state.country_tag if player_state != null else "")
		else:
			var ev: GameEvent = event_manager.get_or_load_event(ev_id)
			if ev != null:
				pending_modal_events.append(ev)

func _on_directive_region_conquered(province_id: int, new_owner_tag: String) -> void:
	var old_owner: String = ""
	if regions_world_state.has(province_id):
		var reg: RegionData = regions_world_state[province_id]
		old_owner = reg.owner_tag
		reg.owner_tag = new_owner_tag
		reg.is_dirty = true
	region_conquered.emit(province_id, new_owner_tag, old_owner)

func _on_directive_state_conquered(state_id: int, new_owner_tag: String) -> void:
	transfer_state(state_id, new_owner_tag)

func _on_event_territory_transfer_requested(state_id: int, new_owner_tag: String) -> void:
	transfer_state(state_id, new_owner_tag)

func _on_event_country_annexation_requested(victim_tag: String, annexer_tag: String) -> void:
	annex_country(victim_tag, annexer_tag)


## Передача суверенитета над штатом новому владельцу с реактивной синхронизацией LUT карты
func transfer_state(state_id: int, new_owner_tag: String) -> bool:
	return TurnTerritoryHandlerScript.transfer_state(self, state_id, new_owner_tag)


## Аннексия целого государства
func annex_country(victim_tag: String, annexer_tag: String) -> void:
	TurnTerritoryHandlerScript.annex_country(self, victim_tag, annexer_tag)


## Реактивная синхронизация шейдерной палитры карты
func _sync_map_controller_reactive(affected_states: Array[int], new_owner_tag: String = "") -> void:
	TurnTerritoryHandlerScript.sync_map_controller_reactive(self, affected_states, new_owner_tag)



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
			var json := JSON.new()
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
	var loaded_states := false
	if FileAccess.file_exists(manifest_path):
		var f_m = FileAccess.open(manifest_path, FileAccess.READ)
		if f_m != null:
			var m_txt = f_m.get_as_text()
			f_m.close()
			var json_m := JSON.new()
			if json_m.parse(m_txt) == OK and json_m.data is Dictionary:
				var states_dict = json_m.data.get("states", {})
				for sid_str in states_dict.keys():
					var sid := int(sid_str)
					var s_info = states_dict[sid_str]
					var provs = s_info.get("provinces", [])
					var int_provs: Array[int] = []
					for p in provs:
						var pid := int(p)
						int_provs.append(pid)
						province_to_state[pid] = sid
					state_to_provinces[sid] = int_provs

				# Если в манифесте нет секции states, извлекаем штаты из провинций
				if state_to_provinces.is_empty() and json_m.data.has("provinces"):
					var provs_dict = json_m.data["provinces"]
					for pid_str in provs_dict.keys():
						var pid := int(pid_str)
						var p_info = provs_dict[pid_str]
						if p_info is Dictionary and p_info.has("state_id"):
							var sid := int(p_info["state_id"])
							if sid > 0:
								province_to_state[pid] = sid
								if not state_to_provinces.has(sid):
									var new_provs: Array[int] = []
									state_to_provinces[sid] = new_provs
								state_to_provinces[sid].append(pid)

				if not state_to_provinces.is_empty():
					loaded_states = true

	# Дополнительный фоллбек: загрузка штатов из border_hierarchy_manifest.json
	if not loaded_states and FileAccess.file_exists("res://map_data/border_hierarchy_manifest.json"):
		var f_ext = FileAccess.open("res://map_data/border_hierarchy_manifest.json", FileAccess.READ)
		if f_ext != null:
			var ext_txt = f_ext.get_as_text()
			f_ext.close()
			var json_ext := JSON.new()
			if json_ext.parse(ext_txt) == OK and json_ext.data is Dictionary:
				var ext_states = json_ext.data.get("states", {})
				for sid_str in ext_states.keys():
					var sid := int(sid_str)
					var s_info = ext_states[sid_str]
					var provs = s_info.get("provinces", [])
					var int_provs: Array[int] = []
					for p in provs:
						var pid := int(p)
						int_provs.append(pid)
						province_to_state[pid] = sid
					state_to_provinces[sid] = int_provs

	# 3. Загрузка стартовых провинций
	if FileAccess.file_exists(regions_path):
		var f_r = FileAccess.open(regions_path, FileAccess.READ)
		if f_r != null:
			var r_txt = f_r.get_as_text()
			f_r.close()
			var json_r := JSON.new()
			if json_r.parse(r_txt) == OK and json_r.data is Dictionary:
				for pid_str in json_r.data.keys():
					var pid := int(pid_str)
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
	if player_state == null:
		TNOLogger.error("TurnManager", "Cannot end turn: player_state is null!")
		return

	if current_state == TurnState.WAITING_FOR_MODAL_EVENT:
		if pending_modal_events.is_empty():
			# Автоматическое восстановление, если модальное окно было разрешено без сброса стейта
			current_state = TurnState.IDLE
		else:
			TNOLogger.warn("TurnManager", "Нельзя завершить ход, пока открыт неразрешенный модальный кризис!")
			return

	TNOLogger.info("TurnManager", "Advancing turn %d (%s) for player [%s]" % [current_turn, get_formatted_date(), player_state.country_tag])

	# 1. Сброс и начисление тактических очков (Data-Driven через ConfigManager)
	var cfg = ConfigManager.get_instance()
	var base_pc_gain: float = cfg.get_float("politics", "base_pc_gain_per_turn", 5.0) if cfg != null else 5.0
	var base_cap: int = cfg.get_int("politics", "base_max_cap", 5) if cfg != null else 5

	if player_state.max_cap <= 0:
		player_state.max_cap = base_cap
	player_state.current_cap = player_state.max_cap

	var pc_gain: float = player_state.pc_gain_per_turn if player_state.pc_gain_per_turn > 0.0 else base_pc_gain
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

	# 2.3. Клиринговые союзы и взаимное влияние экономических сфер (Sphere Clearing & Spillover)
	var _sphere_report: Dictionary = EconomyEngine.process_sphere_clearing_and_spillover(countries_world_state)

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

	# 3.9. Фаза региональной демографии и мобилизации (Demographics & Manpower)
	_process_demographics_and_manpower()

	# 4. Фаза фронтов и макро-войны
	current_state = TurnState.PROCESSING_MILITARY
	phase_changed.emit("PROCESSING_MILITARY")
	last_military_reports = MilitaryEngine.simulate_frontlines(1, countries_world_state, regions_world_state, current_turn)
	military_frontlines_processed.emit(last_military_reports)

	# Расчет глобальной ядерной эскалации DEFCON
	var defcon_rep: Dictionary = MilitaryEngine.evaluate_global_defcon(
		MilitaryEngine.get_active_frontlines(),
		countries_world_state,
		current_turn
	)
	if defcon_rep.get("defcon_changed", false):
		var new_lvl: int = int(defcon_rep["current_level"])
		defcon_level_changed.emit(new_lvl, str(defcon_rep.get("reason", "")))
		if map_controller != null and map_controller.has_method("update_defcon_visuals"):
			map_controller.update_defcon_visuals(new_lvl)
	if defcon_rep.get("is_nuclear_midnight", false):
		_trigger_game_over(false, "Шкала DEFCON достигла уровня 1 (Ядерная Полночь). Термоядерный апокалипсис уничтожил мир.")

	pending_modal_events.clear()

	# Проверка результатов фронтов на захват регионов, боевые инциденты и капитуляцию
	var regions_captured_count: int = 0
	for rep in last_military_reports:
		if rep.get("captured_region_id", -1) > 0:
			var reg_id: int = int(rep["captured_region_id"])
			var n_tag: String = str(rep.get("new_owner", "")).to_upper().strip_edges()
			if n_tag.is_empty():
				n_tag = str(rep.get("attacker_tag", "")).to_upper().strip_edges()
			var p_tag: String = str(rep.get("previous_owner", "")).to_upper().strip_edges()
			if p_tag.is_empty():
				p_tag = str(rep.get("defender_tag", "")).to_upper().strip_edges()
			var sid: int = province_to_state.get(reg_id, 0)

			if not n_tag.is_empty():
				if boundary_manager != null:
					boundary_manager.transfer_province(reg_id, n_tag)

				if sid > 0:
					var provs: Array = state_to_provinces.get(sid, [])
					var all_ours: bool = true
					for p in provs:
						var r: RegionData = regions_world_state.get(p, null)
						if r != null and r.owner_tag.to_upper() != n_tag:
							all_ours = false
							break
					if all_ours:
						transfer_state(sid, n_tag)
					else:
						if map_controller != null and map_controller.has_method("update_province_owner"):
							map_controller.update_province_owner(reg_id, n_tag)
				else:
					if map_controller != null and map_controller.has_method("update_province_owner"):
						map_controller.update_province_owner(reg_id, n_tag)

				region_conquered.emit(reg_id, n_tag, p_tag)
				regions_captured_count += 1

		if rep.get("battle_incident") != null:
			var inc: GameEvent = rep["battle_incident"]
			pending_modal_events.append(inc)

		if rep.get("capitulation", false):
			var victor: String = str(rep.get("victor_tag", "")).to_upper()
			var defeated: String = str(rep.get("defeated_tag", "")).to_upper()
			if not defeated.is_empty() and not victor.is_empty():
				if russian_unification_manager != null and RussianUnificationManager.is_warlord(victor) and RussianUnificationManager.is_warlord(defeated):
					russian_unification_manager.execute_warlord_conquest(victor, defeated, self, "annex_and_integrate")
				else:
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

	if regions_captured_count > 0 and boundary_manager != null:
		boundary_manager.audit_enclaves()

	# 4.1. Кампания Германии / Немецкая Гражданская Война (GCW)
	if german_civil_war_manager != null:
		german_civil_war_manager.process_turn(current_turn)
	if germany_campaign_manager != null:
		germany_campaign_manager.process_turn(current_turn)

	# 4.2. Кампания Русской Смуты и Воссоединения (Smuta / Unification)
	if russian_unification_manager != null:
		if player_state != null:
			russian_unification_manager.player_tag = player_state.country_tag
		russian_unification_manager.process_turn(current_turn, player_state, self)

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

	# 4.6. Великогерманский Рейх и Немецкий Кризис (Germany Campaign & GCW)
	if germany_campaign_manager != null:
		germany_campaign_manager.process_turn(current_turn)
	if german_civil_war_manager != null:
		german_civil_war_manager.process_turn(current_turn)

	# 5. Фаза проверки нарративных событий и кризисов
	current_state = TurnState.CHECKING_EVENTS
	phase_changed.emit("CHECKING_EVENTS")
	var triggered_events: Array[GameEvent] = []
	if event_manager != null:
		triggered_events = event_manager.evaluate_turn_triggers(player_state, current_turn)

	for ev in triggered_events:
		if ev.is_modal:
			pending_modal_events.append(ev)
		else:
			if not ev.options.is_empty():
				event_manager.resolve_event_option(ev, ev.options[0], player_state)
			event_manager.event_triggered.emit(ev)

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
		var dir_id: String = directive.id if not directive.id.is_empty() else directive.directive_id
		if not directive_manager.all_directives.has(dir_id):
			directive_manager.register_directive(directive)
		var success: bool = directive_manager.start_directive(dir_id, player_state, force)
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
		var completed: Array[DirectiveResource] = directive_manager.advance_turn(player_state)
		for dir in completed:
			if _active_directive == dir or (_active_directive != null and _active_directive.id == dir.id):
				_active_directive = null
			directive_completed.emit(dir)



func _display_next_modal_event() -> void:
	if pending_modal_events.is_empty():
		_finalize_turn()
		return

	var next_event: GameEvent = pending_modal_events.pop_front()
	if next_event == null or next_event.options.is_empty():
		push_warning("TurnManager: Modal event is null or has no options. Auto-resolving.")
		_display_next_modal_event()
		return

	current_state = TurnState.WAITING_FOR_MODAL_EVENT
	modal_event_opened.emit(next_event)


## Вызывается UI при выборе варианта в модальном диалоге события
func resolve_modal_event_choice(event: GameEvent, option_index: int) -> void:
	if event != null and option_index >= 0 and option_index < event.options.size():
		var chosen_opt: Dictionary = event.options[option_index]
		if event_manager != null:
			event_manager.resolve_event_option(event, chosen_opt, player_state)
		elif event.has_method("resolve_option_effects"):
			event.resolve_option_effects(chosen_opt, player_state)

	# Переход к следующему модальному событию в очереди, либо финализация хода
	_display_next_modal_event()


## Алиас для обратной совместимости с внешними системами и тестами
func resolve_modal_event(event: GameEvent, option_index: int = 0) -> void:
	resolve_modal_event_choice(event, option_index)


## Принудительное снятие блокировки хода при сбое или закрытии внешнего UI
func force_unlock_turn() -> void:
	pending_modal_events.clear()
	if current_state == TurnState.WAITING_FOR_MODAL_EVENT:
		_finalize_turn()
	else:
		current_state = TurnState.IDLE


## Обработчик победы кандидата на президентских выборах США
func _on_us_president_elected(election_result: Dictionary) -> void:
	var win_cand = election_result.get("winning_candidate", {})
	if win_cand.is_empty():
		return
	var c_name: String = str(win_cand.get("name", ""))
	var c_id: String = str(win_cand.get("id", ""))
	var p_path: String = str(win_cand.get("portrait_path", ""))
	var ideol: String = str(win_cand.get("ideology", ""))
	var yr: int = int(election_result.get("year", 1964))

	var target_usa: CountryState = player_state if (player_state != null and player_state.country_tag == "USA") else countries_world_state.get("USA", null)
	if target_usa != null:
		if not c_name.is_empty():
			target_usa.leader_name = c_name
		if not p_path.is_empty():
			target_usa.leader_portrait_path = p_path
		if not ideol.is_empty():
			target_usa.ruling_ideology = ideol
		target_usa.set_flag("president_" + c_id.to_lower(), true)
		target_usa.set_flag("presidential_election_winner_%d" % yr, c_id)

	# Определение канонического ID древа директив под нового президента США
	var target_tree := ""
	var cand_str = c_id.to_upper()
	if cand_str.contains("JOHNSON") or cand_str.contains("LBJ"):
		target_tree = "USA_LBJ_64"
	elif cand_str.contains("KENNEDY") or cand_str.contains("RFK"):
		target_tree = "USA_RFK_64"
	elif cand_str.contains("WALLACE") and not cand_str.contains("BENNETT"):
		target_tree = "USA_WAL_64"
	elif cand_str.contains("BENNETT"):
		target_tree = "USA_WFB_64"
	elif cand_str.contains("GOLDWATER"):
		target_tree = "USA_GLD_68"
	elif cand_str.contains("HART"):
		target_tree = "USA_Hart"
	elif cand_str.contains("HARRINGTON"):
		target_tree = "USA_HAR_68"
	elif cand_str.contains("SMITH") or cand_str.contains("MCS"):
		target_tree = "USA_MCS_68"
	elif cand_str.contains("LEMAY"):
		target_tree = "USA_LEMAY"

	if player_state != null and player_state.country_tag == "USA" and focus_stage_controller != null and not target_tree.is_empty():
		print("[TurnManager] ВЫБОРЫ США: Победа [%s] -> Переключение древа директив на [%s]" % [c_name, target_tree])
		focus_stage_controller.switch_focus_tree(target_tree, true)


func _finalize_turn() -> void:
	if current_state == TurnState.IDLE:
		return
	current_state = TurnState.IDLE

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
	if FileAccess.file_exists("user://savegame.json"):
		DirAccess.copy_absolute("user://savegame.json", "user://autosave.json")
	autosaved.emit(current_turn, "user://autosave.json")
	turn_completed.emit(current_turn, last_economic_report)
	turn_started.emit(current_turn, get_formatted_date())
	_check_game_over_conditions()


## Расчет региональной демографии, естественного прироста и притока рекрутов (TNO Demographic Engine)
func _process_demographics_and_manpower() -> void:
	DemographicsEngineScript.process_turn(regions_world_state, countries_world_state)


## Проверка таймеров саботажа и назревающих переворотов
func _process_sabotage_and_coups() -> void:
	TurnCrisisHandlerScript.process_sabotage_and_coups(self)


## Разрешение государственного переворота
func _resolve_coup(victim: CountryState, sponsor_tag: String) -> void:
	TurnCrisisHandlerScript.resolve_coup(self, victim, sponsor_tag)


## Проверка финальных условий победы или поражения игрока
func _check_game_over_conditions() -> void:
	TurnCrisisHandlerScript.check_game_over_conditions(self)


func _trigger_game_over(victory: bool, reason: String) -> void:
	TurnCrisisHandlerScript.trigger_game_over(self, victory, reason)


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
func save_game(save_path: String = "user://savegame.json", pretty: bool = false) -> bool:
	return TurnSerializerScript.save_session(self, save_path, pretty)


## Загрузка игровой сессии из JSON архива
func load_game(save_path: String = "user://savegame.json") -> bool:
	return TurnSerializerScript.load_session(self, save_path)
