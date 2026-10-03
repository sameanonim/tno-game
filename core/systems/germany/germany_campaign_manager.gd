class_name GermanyCampaignManager
extends Node

##
## GermanyCampaignManager: Главный системный координатор кампании Германии (GER)
## Управляет жизненным циклом Рейха:
## - Фаза 0: Прелюдия 1962 (Агония Гитлера, стачки в Руре, заговор наследников).
## - Фаза 1: Схватка за власть / Гражданская война (делегирование в GermanCivilWarManager).
## - Фаза 2: Правление победителя (Борман / Шпеер / Гёринг / Гейдрих).
## - Симуляция рабского труда и Восстания рабов (Sklavenaufstand 1970).
##

const CampaignStateScript = preload("res://core/data/germany/germany_campaign_state.gd")
const KartenhausEngineScript = preload("res://core/systems/germany/kartenhaus_engine.gd")
const ZollvereinEngineScript = preload("res://core/systems/germany/zollverein_engine.gd")
const WarPlansEngineScript = preload("res://core/systems/germany/warplans_engine.gd")
const NuclearCustodyEngineScript = preload("res://core/systems/germany/nuclear_custody_engine.gd")

signal germany_state_updated(state: Resource)
signal hitler_health_changed(new_health: float, is_alive: bool)
signal hitler_passed_away()
signal campaign_stage_advanced(new_stage: int, stage_title: String)
signal slave_unrest_changed(new_unrest: float, is_critical: bool)
signal contender_mechanic_stepped(contender_tag: String, step_result: Dictionary)
signal log_message_generated(text: String, is_alert: bool)

@export var campaign_state: Resource = null
@export var current_turn: int = 1

# Ссылки на внешние менеджеры
var civil_war_manager: GermanCivilWarManager = null


func _init() -> void:
	if campaign_state == null:
		campaign_state = CampaignStateScript.new()


func _ready() -> void:
	if campaign_state == null:
		campaign_state = CampaignStateScript.new()


func initialize(gcw_mgr: GermanCivilWarManager = null) -> void:
	if campaign_state == null:
		campaign_state = CampaignStateScript.new()
	civil_war_manager = gcw_mgr
	if civil_war_manager != null and not civil_war_manager.hitler_died.is_connected(_on_gcw_hitler_died):
		civil_war_manager.hitler_died.connect(_on_gcw_hitler_died)
	
	emit_signal("germany_state_updated", campaign_state)


func process_turn(turn_number: int) -> void:
	if campaign_state == null:
		campaign_state = CampaignStateScript.new()
	current_turn = turn_number
	var turn_seed: int = turn_number * 1337 + 42
	
	match campaign_state.current_stage:
		CampaignStateScript.CampaignStage.STAGE_PRELUDE:
			_process_prelude_turn(turn_seed)
		CampaignStateScript.CampaignStage.STAGE_POWER_STRUGGLE:
			_process_power_struggle_turn(turn_seed)
		CampaignStateScript.CampaignStage.STAGE_SUCCESSOR_RULE:
			_process_successor_rule_turn(turn_seed)
		CampaignStateScript.CampaignStage.STAGE_COLLAPSE:
			_process_collapse_turn(turn_seed)
			
	# Общий расчет рабской экономики
	_process_slave_economy(turn_seed)
	
	emit_signal("germany_state_updated", campaign_state)


# ------------------------------------------------------------------------------
# 1. Фаза 0: Прелюдия и угасание Гитлера
# ------------------------------------------------------------------------------
func _process_prelude_turn(seed_val: int) -> void:
	if not campaign_state.hitler_is_alive:
		return
		
	# Ухудшение здоровья на 5-10% за ход
	var decay: float = 6.0 + (float(seed_val % 40) / 10.0)
	campaign_state.hitler_health = maxf(0.0, campaign_state.hitler_health - decay)
	emit_signal("hitler_health_changed", campaign_state.hitler_health, true)
	
	if campaign_state.hitler_health <= 0.0:
		_trigger_hitler_death()
	else:
		emit_signal("log_message_generated", "Бюллетень Рейхсканцелярии: состояние здоровья Фюрера стабильно тяжелое (%0.1f%%)." % campaign_state.hitler_health, false)


func _trigger_hitler_death() -> void:
	campaign_state.hitler_is_alive = false
	campaign_state.hitler_health = 0.0
	campaign_state.current_stage = CampaignStateScript.CampaignStage.STAGE_POWER_STRUGGLE
	
	emit_signal("hitler_passed_away")
	emit_signal("campaign_stage_advanced", int(campaign_state.current_stage), "КРИЗИС ПРЕСТОЛОНАСЛЕДИЯ // ГИТЛЕР МЁРТВ")
	emit_signal("log_message_generated", "ЭКСТРЕННОЕ СООБЩЕНИЕ: Адольф Гитлер скончался. В Рейхе объявлено чрезвычайное положение!", true)
	
	if civil_war_manager != null:
		civil_war_manager.trigger_hitler_death()


func _on_gcw_hitler_died() -> void:
	if campaign_state.hitler_is_alive:
		_trigger_hitler_death()


# ------------------------------------------------------------------------------
# 2. Фаза 1: Схватка за власть
# ------------------------------------------------------------------------------
func _process_power_struggle_turn(_seed_val: int) -> void:
	# Если гражданская война активна в civil_war_manager
	if civil_war_manager != null and civil_war_manager.active_phase == GermanCivilWarManager.GCWPhase.PHASE_3_HEGEMONY:
		# Война завершена, переход к фазе правления
		campaign_state.current_stage = CampaignStateScript.CampaignStage.STAGE_SUCCESSOR_RULE
		emit_signal("campaign_stage_advanced", int(campaign_state.current_stage), "ТРИУМФ НОВОГО ПРАВИТЕЛЯ // РЕКОНСТРУКЦИЯ")


# ------------------------------------------------------------------------------
# 3. Фаза 2: Правление 4 претендентов
# ------------------------------------------------------------------------------
func _process_successor_rule_turn(seed_val: int) -> void:
	var step_res: Dictionary = {}
	match campaign_state.chosen_contender_tag:
		"BOR":
			step_res = KartenhausEngineScript.process_turn_step(campaign_state, seed_val)
		"SPE":
			step_res = ZollvereinEngineScript.process_turn_step(campaign_state, seed_val)
		"GOR":
			step_res = WarPlansEngineScript.process_turn_step(campaign_state, seed_val)
		"HEY":
			step_res = NuclearCustodyEngineScript.process_turn_step(campaign_state, seed_val)
			if step_res.get("apocalypse_triggered", false):
				campaign_state.current_stage = CampaignStateScript.CampaignStage.STAGE_COLLAPSE
				emit_signal("campaign_stage_advanced", int(campaign_state.current_stage), "ЯДЕРНЫЙ АПОКАЛИПСИС // КОНЕЦ СВЕТА")
				return
				
	var log_msg: String = str(step_res.get("log_message", ""))
	if not log_msg.is_empty():
		emit_signal("log_message_generated", log_msg, step_res.get("risk_of_coup", false) or step_res.get("risk_of_dissent", false))
		
	emit_signal("contender_mechanic_stepped", campaign_state.chosen_contender_tag, step_res)


func _process_collapse_turn(_seed_val: int) -> void:
	emit_signal("log_message_generated", "ВНИМАНИЕ: Центральное правительство Рейха пало. Территория охвачена анархией и хаосом.", true)


# ------------------------------------------------------------------------------
# 4. Рабский труд и общенациональная напряженность
# ------------------------------------------------------------------------------
func _process_slave_economy(seed_val: int) -> void:
	# Рабское недовольство медленно растет, если в стране застой
	if campaign_state.chosen_contender_tag != "SPE":
		var unrest_drift: float = 0.01 + (float(seed_val % 20) / 2000.0)
		campaign_state.slave_unrest = clampf(campaign_state.slave_unrest + unrest_drift, 0.0, 1.0)
		
	var is_critical: bool = campaign_state.slave_unrest >= 0.75
	emit_signal("slave_unrest_changed", campaign_state.slave_unrest, is_critical)


# ------------------------------------------------------------------------------
# Публичные действия игрока через UI терминал
# ------------------------------------------------------------------------------
func select_player_contender(tag: String) -> void:
	if tag in ["BOR", "SPE", "GOR", "HEY"]:
		campaign_state.chosen_contender_tag = tag
		if civil_war_manager != null:
			civil_war_manager.player_contender_tag = tag
		emit_signal("germany_state_updated", campaign_state)


func execute_bormann_secure_district(district_id: String) -> bool:
	var success: bool = KartenhausEngineScript.secure_gauleiter(campaign_state, district_id, current_turn * 991)
	emit_signal("germany_state_updated", campaign_state)
	return success


func execute_speer_empower_advisor(advisor_key: String, delta: float) -> void:
	ZollvereinEngineScript.empower_advisor(campaign_state, advisor_key, delta)
	emit_signal("germany_state_updated", campaign_state)


func execute_goering_campaign_victory(target_tag: String) -> Dictionary:
	var res: Dictionary = WarPlansEngineScript.execute_campaign_victory(campaign_state, target_tag)
	emit_signal("germany_state_updated", campaign_state)
	return res


func execute_heydrich_secure_silo() -> bool:
	var success: bool = NuclearCustodyEngineScript.secure_silo_operation(campaign_state, current_turn * 773)
	emit_signal("germany_state_updated", campaign_state)
	return success
