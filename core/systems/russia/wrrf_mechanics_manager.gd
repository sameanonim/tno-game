class_name WRRFMechanicsManager
extends RefCounted

"""
WRRFMechanicsManager: Главный управляющий модуль уникальных механик ЗРРФ (WRS)
--------------------------------------------------------------------------------
Моделирует:
1. Острую борьбу за власть после отставки Ворошилова / болезни Егорова:
   - Маршал Георгий Жуков (Народный Фронт, регулярная РККА, компромисс и реформы)
   - Маршал Михаил Тухачевский ("Красный Бонапарт", тотальная война, военная диктатура)
2. Программу Секретных Военных Проектов Тухачевского (Tukhachevsky's Red Arsenal):
   - Программа ОБТ (Основной Боевой Танк)
   - Проект УРАГАН (Тяжелая реактивная артиллерия)
   - Проект ЦИКЛОН (Ракетное вооружение)
   - Проект ЩУКА (Северный подводный флот)
   - Проект ЛЕШИЙ (Диверсионно-разведывательные бригады Спецназа)
   - Проект ФЕРМЕНТ (Арсенал химического оружия)
   - Ижевский опытно-механический завод
3. Триумвират Жукова и преемственность на региональном этапе:
   - Сергей Ахромеев (Армейские ортодоксы, СМЕРШ, американское военное снаряжение)
   - Николай Рыжков (Госплан, модернизация сельского хозяйства, создание КГБ)
   - Александр Яковлев (Демократический социализм, отмена ГУЛАГа, тарифы ОФН)
4. Взаимодействие со Смутой:
   - Пакт о ненападении с Республикой Коми
   - Интеграция танковой бригады Горького
   - Рейды и пограничные операции против Онеги и Финляндии
"""

signal power_struggle_updated(zhukov_pct: float, tukha_pct: float)
signal successor_chosen(successor_name: String, leader_id: String)
signal secret_project_progressed(project_id: String, progress: float, is_complete: bool)
signal triumvirate_balance_shifted(akhromeyev: float, ryzhkov: float, yakovlev: float)
signal heir_declared(heir_name: String)
signal mechanic_action_executed(action_id: String, details: Dictionary)
signal terror_bombings_lifted()

const LEADER_YEGOROV_ID = "WRS_Alexander_Yegorov"
const LEADER_ZHUKOV_ID = "WRS_Georgy_Zhukov"
const LEADER_TUKHA_ID = "WRS_Mikhail_Tukhachevsky"

const TREE_INITIAL = "WRS_initial"
const TREE_BOMBINGS_END = "WRS_bombings_end"
const TREE_ZHUKOV_WARLORD = "WRS_zhukov_warlord"
const TREE_TUKHA_WARLORD = "WRS_tukhachevsky_warlord"
const TREE_ZHUKOV_REGIONAL = "WRS_zhukov_regional"
const TREE_TUKHA_REGIONAL = "WRS_tukhachevsky_regional"
const TREE_ZHUKOV_SUPERREGIONAL = "WRS_zhukov_superregional"
const TREE_TUKHA_SUPERREGIONAL = "WRS_tukhachevsky_superregional"

var state: WRRFCampaignState = WRRFCampaignState.new()
var player_state: CountryState = null
var turn_manager: TurnManager = null


# ==============================================================================
# ИНИЦИАЛИЗАЦИЯ И СВЯЗЫВАНИЕ
# ==============================================================================

"""Инициализирует менеджер механик ЗРРФ для переданного государства игрока."""
func setup(country_state: CountryState, tm: TurnManager = null) -> void:
	player_state = country_state
	turn_manager = tm

	# Синхронизация флагов
	if player_state != null:
		if player_state.has_flag("wrs_zhukov_chosen"):
			state.chosen_successor = WRRFCampaignState.Successor.ZHUKOV
			state.power_struggle_resolved = true
		elif player_state.has_flag("wrs_tukhachevsky_chosen"):
			state.chosen_successor = WRRFCampaignState.Successor.TUKHACHEVSKY
			state.power_struggle_resolved = true

		if player_state.has_flag("bombings_ended"):
			state.terror_bombings_active = false
			state.bombings_end_declared = true


# ==============================================================================
# ПОШАГОВАЯ ОБРАБОТКА ХОДА
# ==============================================================================

"""Обрабатывает ход кампании ЗРРФ и возвращает отчет о фронтовых показателях."""
func process_turn(current_turn: int) -> Dictionary:
	var report: Dictionary = {
		"turn": current_turn,
		"stage": int(state.current_stage),
		"zhukov_influence": state.zhukov_influence,
		"tukha_influence": state.tukhachevsky_influence,
		"power_struggle_resolved": state.power_struggle_resolved,
		"terror_bombings_active": state.terror_bombings_active,
		"supply_stockpile": state.front_supply_stockpile,
		"readiness": state.onega_raid_readiness
	}

	# 1. Проверка снятия террористических бомбардировок (Германская гражданская война или флаг)
	if state.terror_bombings_active:
		var end_bombings := false
		if player_state != null and (player_state.has_flag("bombings_ended") or player_state.has_flag("gcw_started")):
			end_bombings = true
		elif current_turn >= 12: # В TNO бомбардировки прекращаются с началом GCW (осень 1963)
			end_bombings = true

		if end_bombings:
			lift_terror_bombings()
			report["terror_bombings_active"] = false

	# 2. Течение борьбы за власть (если еще не разрешена)
	if not state.power_struggle_resolved:
		state.marshal_yegorov_health = maxf(state.marshal_yegorov_health - 1.5, 5.0)

		# Авто-разрешение при критическом перевесе или при переходе к Смуте
		if state.zhukov_influence >= 75.0 and state.zhukov_influence - state.tukhachevsky_influence >= 25.0:
			resolve_power_struggle(WRRFCampaignState.Successor.ZHUKOV)
		elif state.tukhachevsky_influence >= 75.0 and state.tukhachevsky_influence - state.zhukov_influence >= 25.0:
			resolve_power_struggle(WRRFCampaignState.Successor.TUKHACHEVSKY)
		elif current_turn >= 18 and not state.terror_bombings_active:
			# К моменту начала Смуты лидер должен быть определен
			var winner = WRRFCampaignState.Successor.ZHUKOV if state.zhukov_influence >= state.tukhachevsky_influence else WRRFCampaignState.Successor.TUKHACHEVSKY
			resolve_power_struggle(winner)

	# 3. Бонусы арсенала Тухачевского
	if state.chosen_successor == WRRFCampaignState.Successor.TUKHACHEVSKY and player_state != null:
		if state.obt_completed:
			player_state.heavy_equipment_stockpile += 15
			player_state.army_readiness = clampf(player_state.army_readiness + 0.2, 0.0, 100.0)
		if state.uragan_active:
			player_state.infantry_weapons_stockpile += 50
		if state.izhevsk_works_expanded:
			player_state.military_factories = maxi(player_state.military_factories, 8)

	# 4. Бонусы триумвирата Жукова
	if state.chosen_successor == WRRFCampaignState.Successor.ZHUKOV and player_state != null:
		if state.agricultural_mechanization_done:
			player_state.gdp_billions = maxf(player_state.gdp_billions + 0.01, 0.5)
		if state.us_equipment_imported:
			player_state.infantry_weapons_stockpile += 100
		if state.gulag_system_abolished:
			player_state.legitimacy = clampf(player_state.legitimacy + 0.3, 0.0, 100.0)

	# Пополнение снабжения фронта
	state.front_supply_stockpile = clampf(state.front_supply_stockpile + 0.5, 0.0, 100.0)
	state.onega_raid_readiness = clampf(state.onega_raid_readiness + 0.8, 0.0, 100.0)

	return report


"""Снимает режим террористических бомбардировок Люфтваффе."""
func lift_terror_bombings() -> void:
	state.terror_bombings_active = false
	state.bombings_end_declared = true

	if player_state != null:
		player_state.set_flag("bombings_ended", true)
		player_state.stability = clampf(player_state.stability + 0.15, 0.0, 1.0)
		player_state.war_support_percent = clampf(player_state.war_support_percent + 10.0, 0.0, 100.0)

	# Переключаем дерево на WRS_bombings_end, если не выбрана ветка варлорда
	if turn_manager != null and turn_manager.focus_stage_controller != null:
		if not state.power_struggle_resolved:
			turn_manager.focus_stage_controller.switch_focus_tree(TREE_BOMBINGS_END, true)

	terror_bombings_lifted.emit()
	mechanic_action_executed.emit("terror_bombings_lifted", {"status": "success"})


# ==============================================================================
# БОРЬБА ЗА ВЛАСТЬ (ЖУКОВ VS ТУХАЧЕВСКИЙ)
# ==============================================================================

"""Исполняет оперативное действие борьбы за власть или нацпрограмм."""
func execute_decision_action(action_id: String) -> bool:
	match action_id:
		"WRS_zhukov_influence_ticker":
			return execute_zhukov_influence_ticker()
		"WRS_tukha_influence_ticker":
			return execute_tukha_influence_ticker()
		"WRS_appease_zhukov":
			return execute_appease_zhukov()
		"WRS_appease_tukha":
			return execute_appease_tukha()
		"WRS_work_against_zhukov":
			return execute_work_against_zhukov()
		"WRS_work_against_tukha":
			return execute_work_against_tukha()
		"WRS_zhukov_military_parade":
			return execute_zhukov_military_parade()
		"WRS_tukha_military_parade":
			return execute_tukha_military_parade()
		"WRS_zhukov_meet_with_veterans":
			return execute_zhukov_meet_with_veterans()
		"WRS_tukha_meet_with_veterans":
			return execute_tukha_meet_with_veterans()
		"WRS_zhukov_meet_with_yegorov":
			return execute_zhukov_meet_with_yegorov()
		"WRS_tukha_meet_with_yegorov":
			return execute_tukha_meet_with_yegorov()
		"WRS_tukha_operation_firebird":
			return execute_tukha_operation_firebird()
		"WRS_zhukov_compile_evidence":
			return execute_zhukov_compile_evidence()
		"WRS_zhukov_increase_oil_quotas":
			return execute_zhukov_increase_oil_quotas()
		"WRS_zhukov_deploy_red_army_labour_battalions":
			return execute_zhukov_deploy_labour_battalions()
		"WRS_OBT_program":
			return advance_obt_program(25.0)
		"WRS_izhevsk_experimental_constructor_works":
			return expand_izhevsk_works()
		"WRS_project_uragan":
			return activate_project_uragan()
		"WRS_project_tsysklon":
			return activate_project_tsysklon()
		"WRS_project_shchuka":
			return activate_project_shchuka()
		"WRS_project_leshiy":
			return activate_project_leshiy()
		"WRS_project_ferment":
			return produce_ferment_chemical_weapons(50)
		"WRS_appease_akhromeyev":
			appease_triumvirate_faction("akhromeyev")
			return true
		"WRS_appease_ryzhkov":
			appease_triumvirate_faction("ryzhkov")
			return true
		"WRS_appease_yakovlev":
			appease_triumvirate_faction("yakovlev")
			return true
		"WRS_akhromeyev_draw_closer_to_USA":
			return execute_akhromeyev_draw_closer_to_usa()
		"WRS_akhromeyev_widen_smersh_powers":
			return execute_akhromeyev_widen_smersh_powers()
		"WRS_ryzhkov_agricultural_mechanization":
			return execute_ryzhkov_agricultural_mechanization()
		"WRS_ryzhkov_establish_the_kgb":
			return execute_ryzhkov_establish_kgb()
		"WRS_yakovlev_eliminate_ofn_tariffs":
			return execute_yakovlev_eliminate_ofn_tariffs()
		"WRS_yakovlev_abolish_gulag":
			return execute_yakovlev_abolish_gulag()
		"RUS_Decision_Smuta_Expansion_KOM_WRS_Establish_NAP":
			return establish_komi_nap()
		"RUS_Decision_Smuta_Expansion_KOM_WRS_End_NAP":
			return end_komi_nap()
		"RUS_Decision_Smuta_Expansion_GOR_WRS_NyomNyomNyom":
			return integrate_gorky_brigade()
		_:
			return false


func execute_zhukov_influence_ticker() -> bool:
	state.zhukov_influence = clampf(state.zhukov_influence + 6.0, 0.0, 100.0)
	state.tukhachevsky_influence = clampf(state.tukhachevsky_influence - 3.0, 0.0, 100.0)
	power_struggle_updated.emit(state.zhukov_influence, state.tukhachevsky_influence)
	mechanic_action_executed.emit("WRS_zhukov_influence_ticker", {"zhukov": state.zhukov_influence})
	return true


func execute_tukha_influence_ticker() -> bool:
	state.tukhachevsky_influence = clampf(state.tukhachevsky_influence + 6.0, 0.0, 100.0)
	state.zhukov_influence = clampf(state.zhukov_influence - 3.0, 0.0, 100.0)
	power_struggle_updated.emit(state.zhukov_influence, state.tukhachevsky_influence)
	mechanic_action_executed.emit("WRS_tukha_influence_ticker", {"tukha": state.tukhachevsky_influence})
	return true


func execute_appease_zhukov() -> bool:
	state.zhukov_influence = clampf(state.zhukov_influence + 8.0, 0.0, 100.0)
	if player_state != null:
		player_state.stability = clampf(player_state.stability + 0.03, 0.0, 1.0)
	power_struggle_updated.emit(state.zhukov_influence, state.tukhachevsky_influence)
	mechanic_action_executed.emit("WRS_appease_zhukov", {"zhukov": state.zhukov_influence})
	return true


func execute_appease_tukha() -> bool:
	state.tukhachevsky_influence = clampf(state.tukhachevsky_influence + 8.0, 0.0, 100.0)
	if player_state != null:
		player_state.army_readiness = clampf(player_state.army_readiness + 3.0, 0.0, 100.0)
	power_struggle_updated.emit(state.zhukov_influence, state.tukhachevsky_influence)
	mechanic_action_executed.emit("WRS_appease_tukha", {"tukha": state.tukhachevsky_influence})
	return true


func execute_work_against_zhukov() -> bool:
	state.zhukov_influence = clampf(state.zhukov_influence - 10.0, 0.0, 100.0)
	state.tukhachevsky_influence = clampf(state.tukhachevsky_influence + 4.0, 0.0, 100.0)
	if player_state != null:
		player_state.stability = clampf(player_state.stability - 0.02, 0.0, 1.0)
	power_struggle_updated.emit(state.zhukov_influence, state.tukhachevsky_influence)
	mechanic_action_executed.emit("WRS_work_against_zhukov", {"zhukov": state.zhukov_influence})
	return true


func execute_work_against_tukha() -> bool:
	state.tukhachevsky_influence = clampf(state.tukhachevsky_influence - 10.0, 0.0, 100.0)
	state.zhukov_influence = clampf(state.zhukov_influence + 4.0, 0.0, 100.0)
	if player_state != null:
		player_state.stability = clampf(player_state.stability - 0.02, 0.0, 1.0)
	power_struggle_updated.emit(state.zhukov_influence, state.tukhachevsky_influence)
	mechanic_action_executed.emit("WRS_work_against_tukha", {"tukha": state.tukhachevsky_influence})
	return true


func execute_zhukov_military_parade() -> bool:
	if player_state != null and player_state.infantry_weapons_stockpile >= 250:
		player_state.infantry_weapons_stockpile -= 250
		player_state.war_support_percent = clampf(player_state.war_support_percent + 5.0, 0.0, 100.0)
		player_state.legitimacy = clampf(player_state.legitimacy + 4.0, 0.0, 100.0)
	state.zhukov_influence = clampf(state.zhukov_influence + 7.0, 0.0, 100.0)
	state.veterans_support_zhukov = clampf(state.veterans_support_zhukov + 8.0, 0.0, 100.0)
	power_struggle_updated.emit(state.zhukov_influence, state.tukhachevsky_influence)
	mechanic_action_executed.emit("WRS_zhukov_military_parade", {"success": true})
	return true


func execute_tukha_military_parade() -> bool:
	if player_state != null and player_state.infantry_weapons_stockpile >= 250:
		player_state.infantry_weapons_stockpile -= 250
		player_state.war_support_percent = clampf(player_state.war_support_percent + 5.0, 0.0, 100.0)
		player_state.army_readiness = clampf(player_state.army_readiness + 4.0, 0.0, 100.0)
	state.tukhachevsky_influence = clampf(state.tukhachevsky_influence + 7.0, 0.0, 100.0)
	state.officers_support_tukha = clampf(state.officers_support_tukha + 8.0, 0.0, 100.0)
	power_struggle_updated.emit(state.zhukov_influence, state.tukhachevsky_influence)
	mechanic_action_executed.emit("WRS_tukha_military_parade", {"success": true})
	return true


func execute_zhukov_meet_with_veterans() -> bool:
	state.veterans_support_zhukov = clampf(state.veterans_support_zhukov + 10.0, 0.0, 100.0)
	state.zhukov_influence = clampf(state.zhukov_influence + 5.0, 0.0, 100.0)
	power_struggle_updated.emit(state.zhukov_influence, state.tukhachevsky_influence)
	mechanic_action_executed.emit("WRS_zhukov_meet_with_veterans", {"veterans": state.veterans_support_zhukov})
	return true


func execute_tukha_meet_with_veterans() -> bool:
	state.officers_support_tukha = clampf(state.officers_support_tukha + 10.0, 0.0, 100.0)
	state.tukhachevsky_influence = clampf(state.tukhachevsky_influence + 5.0, 0.0, 100.0)
	power_struggle_updated.emit(state.zhukov_influence, state.tukhachevsky_influence)
	mechanic_action_executed.emit("WRS_tukha_meet_with_veterans", {"officers": state.officers_support_tukha})
	return true


func execute_zhukov_meet_with_yegorov() -> bool:
	state.zhukov_influence = clampf(state.zhukov_influence + 6.0, 0.0, 100.0)
	if player_state != null:
		player_state.legitimacy = clampf(player_state.legitimacy + 5.0, 0.0, 100.0)
	power_struggle_updated.emit(state.zhukov_influence, state.tukhachevsky_influence)
	mechanic_action_executed.emit("WRS_zhukov_meet_with_yegorov", {"success": true})
	return true


func execute_tukha_meet_with_yegorov() -> bool:
	state.tukhachevsky_influence = clampf(state.tukhachevsky_influence + 6.0, 0.0, 100.0)
	if player_state != null:
		player_state.army_readiness = clampf(player_state.army_readiness + 3.0, 0.0, 100.0)
	power_struggle_updated.emit(state.zhukov_influence, state.tukhachevsky_influence)
	mechanic_action_executed.emit("WRS_tukha_meet_with_yegorov", {"success": true})
	return true


func execute_tukha_operation_firebird() -> bool:
	state.operation_firebird_executed = true
	state.tukhachevsky_influence = clampf(state.tukhachevsky_influence + 12.0, 0.0, 100.0)
	state.onega_raid_readiness = clampf(state.onega_raid_readiness + 20.0, 0.0, 100.0)
	if player_state != null:
		player_state.set_flag("wrs_tukha_firebird_done", true)
		player_state.army_readiness = clampf(player_state.army_readiness + 6.0, 0.0, 100.0)
		player_state.infantry_weapons_stockpile += 500
	power_struggle_updated.emit(state.zhukov_influence, state.tukhachevsky_influence)
	mechanic_action_executed.emit("WRS_tukha_operation_firebird", {"readiness": state.onega_raid_readiness})
	return true


func execute_zhukov_compile_evidence() -> bool:
	state.evidence_compiled_against_tukha = true
	state.zhukov_influence = clampf(state.zhukov_influence + 12.0, 0.0, 100.0)
	state.tukhachevsky_influence = clampf(state.tukhachevsky_influence - 10.0, 0.0, 100.0)
	if player_state != null:
		player_state.set_flag("wrs_zhukov_evidence_compiled", true)
		player_state.legitimacy = clampf(player_state.legitimacy + 6.0, 0.0, 100.0)
	power_struggle_updated.emit(state.zhukov_influence, state.tukhachevsky_influence)
	mechanic_action_executed.emit("WRS_zhukov_compile_evidence", {"evidence": true})
	return true


func execute_zhukov_increase_oil_quotas() -> bool:
	if player_state != null:
		player_state.liquid_reserves_billions += 0.08
		player_state.civilian_factories = maxi(player_state.civilian_factories + 1, 1)
	state.front_supply_stockpile = clampf(state.front_supply_stockpile + 15.0, 0.0, 100.0)
	mechanic_action_executed.emit("WRS_zhukov_increase_oil_quotas", {"stockpile": state.front_supply_stockpile})
	return true


func execute_zhukov_deploy_labour_battalions() -> bool:
	if player_state != null:
		player_state.radicalization = clampf(player_state.radicalization - 5.0, 0.0, 100.0)
		player_state.legitimacy = clampf(player_state.legitimacy + 4.0, 0.0, 100.0)
	state.front_supply_stockpile = clampf(state.front_supply_stockpile + 10.0, 0.0, 100.0)
	mechanic_action_executed.emit("WRS_zhukov_deploy_labour_battalions", {"success": true})
	return true


# ==============================================================================
# РАЗРЕШЕНИЕ БОРЬБЫ ЗА ВЛАСТЬ И СМЕНА ЛИДЕРА
# ==============================================================================

"""Окончательно разрешает борьбу за лидерство во Фронте."""
func resolve_power_struggle(forced_successor: WRRFCampaignState.Successor = WRRFCampaignState.Successor.NONE) -> String:
	if state.power_struggle_resolved and forced_successor == WRRFCampaignState.Successor.NONE:
		return "ALREADY_RESOLVED"

	var winner: WRRFCampaignState.Successor = forced_successor
	if winner == WRRFCampaignState.Successor.NONE:
		var zhukov_score: float = state.zhukov_influence + (state.veterans_support_zhukov * 0.3)
		var tukha_score: float = state.tukhachevsky_influence + (state.officers_support_tukha * 0.3)
		winner = WRRFCampaignState.Successor.ZHUKOV if zhukov_score >= tukha_score else WRRFCampaignState.Successor.TUKHACHEVSKY

	state.chosen_successor = winner
	state.power_struggle_resolved = true

	var leader_id := ""
	var leader_title := ""
	var target_tree := ""

	if winner == WRRFCampaignState.Successor.ZHUKOV:
		leader_id = LEADER_ZHUKOV_ID
		leader_title = "Маршал Георгий Жуков"
		target_tree = TREE_ZHUKOV_WARLORD
		if player_state != null:
			player_state.set_flag("wrs_zhukov_chosen", true)
			player_state.set_flag("wrs_tukhachevsky_chosen", false)
			player_state.leader_name = "Георгий Жуков"
			player_state.ruling_ideology = "communist_bolshevism_subtype"
			player_state.legitimacy = clampf(player_state.legitimacy + 15.0, 0.0, 100.0)
	else:
		leader_id = LEADER_TUKHA_ID
		leader_title = "Маршал Михаил Тухачевский"
		target_tree = TREE_TUKHA_WARLORD
		if player_state != null:
			player_state.set_flag("wrs_tukhachevsky_chosen", true)
			player_state.set_flag("wrs_zhukov_chosen", false)
			player_state.leader_name = "Михаил Тухачевский"
			player_state.ruling_ideology = "communist_stratocratic_communism_subtype"
			player_state.army_readiness = clampf(player_state.army_readiness + 15.0, 0.0, 100.0)

	# Переключение фокусного древа
	if turn_manager != null and turn_manager.focus_stage_controller != null:
		turn_manager.focus_stage_controller.switch_focus_tree(target_tree, true)

	successor_chosen.emit(leader_title, leader_id)
	mechanic_action_executed.emit("power_struggle_resolved", {
		"winner": leader_title,
		"leader_id": leader_id,
		"tree": target_tree
	})

	return leader_id


# ==============================================================================
# СЕКРЕТНЫЕ ПРОЕКТЫ ТУХАЧЕВСКОГО
# ==============================================================================

"""Продвигает программу разработки Основного Боевого Танка (ОБТ)."""
func advance_obt_program(step: float = 25.0) -> bool:
	state.obt_progress = clampf(state.obt_progress + step, 0.0, 100.0)
	var is_complete := state.obt_progress >= 100.0
	state.obt_completed = is_complete

	if player_state != null:
		player_state.set_flag("wrs_obt_in_progress", true)
		if is_complete:
			player_state.set_flag("wrs_obt_completed", true)
			player_state.heavy_equipment_stockpile += 80
			player_state.army_readiness = clampf(player_state.army_readiness + 8.0, 0.0, 100.0)

	secret_project_progressed.emit("OBT", state.obt_progress, is_complete)
	mechanic_action_executed.emit("WRS_OBT_program", {"progress": state.obt_progress, "completed": is_complete})
	return true


func expand_izhevsk_works() -> bool:
	state.izhevsk_works_expanded = true
	if player_state != null:
		player_state.military_factories += 2
		player_state.infantry_weapons_stockpile += 1500
		player_state.set_flag("wrs_izhevsk_expanded", true)
	secret_project_progressed.emit("IZHEVSK", 100.0, true)
	mechanic_action_executed.emit("WRS_izhevsk_experimental_constructor_works", {"factories": 2})
	return true


func activate_project_uragan() -> bool:
	state.uragan_active = true
	if player_state != null:
		player_state.heavy_equipment_stockpile += 60
		player_state.army_readiness = clampf(player_state.army_readiness + 5.0, 0.0, 100.0)
		player_state.set_flag("wrs_uragan_active", true)
	secret_project_progressed.emit("URAGAN", 100.0, true)
	mechanic_action_executed.emit("WRS_project_uragan", {"active": true})
	return true


func activate_project_tsysklon() -> bool:
	state.tsysklon_active = true
	if player_state != null:
		player_state.research_speed_bonus += 0.08
		player_state.set_flag("wrs_tsysklon_active", true)
	secret_project_progressed.emit("TSYSKLON", 100.0, true)
	mechanic_action_executed.emit("WRS_project_tsysklon", {"active": true})
	return true


func activate_project_shchuka() -> bool:
	state.shchuka_active = true
	if player_state != null:
		player_state.war_support_percent = clampf(player_state.war_support_percent + 6.0, 0.0, 100.0)
		player_state.set_flag("wrs_shchuka_active", true)
	secret_project_progressed.emit("SHCHUKA", 100.0, true)
	mechanic_action_executed.emit("WRS_project_shchuka", {"active": true})
	return true


func activate_project_leshiy() -> bool:
	state.leshiy_active = true
	state.onega_raid_readiness = clampf(state.onega_raid_readiness + 15.0, 0.0, 100.0)
	if player_state != null:
		player_state.army_readiness = clampf(player_state.army_readiness + 5.0, 0.0, 100.0)
		player_state.set_flag("wrs_leshiy_active", true)
	secret_project_progressed.emit("LESHIY", 100.0, true)
	mechanic_action_executed.emit("WRS_project_leshiy", {"active": true})
	return true


func produce_ferment_chemical_weapons(tons: int = 50) -> bool:
	state.ferment_chemical_stockpile += tons
	if player_state != null:
		player_state.radicalization = clampf(player_state.radicalization + 2.0, 0.0, 100.0)
		player_state.set_flag("wrs_chemical_weapons_stockpiled", true)
	secret_project_progressed.emit("FERMENT", float(state.ferment_chemical_stockpile), true)
	mechanic_action_executed.emit("WRS_project_ferment", {"chemical_tons": state.ferment_chemical_stockpile})
	return true


# ==============================================================================
# ТРИУМВИРАТ ЖУКОВА (АХРОМЕЕВ, РЫЖКОВ, ЯКОВЛЕВ)
# ==============================================================================

"""Смещает баланс триумвирата в пользу указанной фракции."""
func appease_triumvirate_faction(faction: String) -> void:
	match faction.to_lower():
		"akhromeyev":
			state.akhromeyev_influence = clampf(state.akhromeyev_influence + 10.0, 0.0, 100.0)
			state.ryzhkov_influence = clampf(state.ryzhkov_influence - 5.0, 0.0, 100.0)
			state.yakovlev_influence = clampf(state.yakovlev_influence - 5.0, 0.0, 100.0)
			if player_state != null:
				player_state.army_readiness = clampf(player_state.army_readiness + 4.0, 0.0, 100.0)
		"ryzhkov":
			state.ryzhkov_influence = clampf(state.ryzhkov_influence + 10.0, 0.0, 100.0)
			state.akhromeyev_influence = clampf(state.akhromeyev_influence - 5.0, 0.0, 100.0)
			state.yakovlev_influence = clampf(state.yakovlev_influence - 5.0, 0.0, 100.0)
			if player_state != null:
				player_state.liquid_reserves_billions += 0.05
		"yakovlev":
			state.yakovlev_influence = clampf(state.yakovlev_influence + 10.0, 0.0, 100.0)
			state.akhromeyev_influence = clampf(state.akhromeyev_influence - 5.0, 0.0, 100.0)
			state.ryzhkov_influence = clampf(state.ryzhkov_influence - 5.0, 0.0, 100.0)
			if player_state != null:
				player_state.legitimacy = clampf(player_state.legitimacy + 4.0, 0.0, 100.0)
				player_state.radicalization = clampf(player_state.radicalization - 4.0, 0.0, 100.0)

	state.triumvirate_tension = clampf(state.triumvirate_tension - 4.0, 0.0, 100.0)
	triumvirate_balance_shifted.emit(state.akhromeyev_influence, state.ryzhkov_influence, state.yakovlev_influence)
	mechanic_action_executed.emit("appease_triumvirate", {
		"akhromeyev": state.akhromeyev_influence,
		"ryzhkov": state.ryzhkov_influence,
		"yakovlev": state.yakovlev_influence
	})


func execute_akhromeyev_draw_closer_to_usa() -> bool:
	state.us_equipment_imported = true
	state.akhromeyev_influence = clampf(state.akhromeyev_influence + 8.0, 0.0, 100.0)
	if player_state != null:
		player_state.infantry_weapons_stockpile += 2000
		player_state.army_readiness = clampf(player_state.army_readiness + 5.0, 0.0, 100.0)
		player_state.set_flag("wrs_us_supplies_received", true)
	mechanic_action_executed.emit("WRS_akhromeyev_draw_closer_to_USA", {"imported": true})
	return true


func execute_akhromeyev_widen_smersh_powers() -> bool:
	state.smersh_jurisdiction_expanded = true
	state.akhromeyev_influence = clampf(state.akhromeyev_influence + 8.0, 0.0, 100.0)
	if player_state != null:
		player_state.radicalization = clampf(player_state.radicalization - 6.0, 0.0, 100.0)
		player_state.set_flag("wrs_smersh_expanded", true)
	mechanic_action_executed.emit("WRS_akhromeyev_widen_smersh_powers", {"smersh": true})
	return true


func execute_ryzhkov_agricultural_mechanization() -> bool:
	state.agricultural_mechanization_done = true
	state.ryzhkov_influence = clampf(state.ryzhkov_influence + 8.0, 0.0, 100.0)
	if player_state != null:
		player_state.gdp_billions += 0.05
		player_state.stability = clampf(player_state.stability + 0.05, 0.0, 1.0)
		player_state.set_flag("wrs_agriculture_mechanized", true)
	mechanic_action_executed.emit("WRS_ryzhkov_agricultural_mechanization", {"gdp_bonus": 0.05})
	return true


func execute_ryzhkov_establish_kgb() -> bool:
	state.kgb_established = true
	state.ryzhkov_influence = clampf(state.ryzhkov_influence + 8.0, 0.0, 100.0)
	if player_state != null:
		player_state.legitimacy = clampf(player_state.legitimacy + 5.0, 0.0, 100.0)
		player_state.set_flag("wrs_kgb_established", true)
	mechanic_action_executed.emit("WRS_ryzhkov_establish_the_kgb", {"kgb": true})
	return true


func execute_yakovlev_eliminate_ofn_tariffs() -> bool:
	state.ofn_tariffs_eliminated = true
	state.yakovlev_influence = clampf(state.yakovlev_influence + 8.0, 0.0, 100.0)
	if player_state != null:
		player_state.gdp_billions += 0.04
		player_state.liquid_reserves_billions += 0.06
		player_state.set_flag("wrs_ofn_trade_open", true)
	mechanic_action_executed.emit("WRS_yakovlev_eliminate_ofn_tariffs", {"open_trade": true})
	return true


func execute_yakovlev_abolish_gulag() -> bool:
	state.gulag_system_abolished = true
	state.yakovlev_influence = clampf(state.yakovlev_influence + 12.0, 0.0, 100.0)
	if player_state != null:
		player_state.legitimacy = clampf(player_state.legitimacy + 8.0, 0.0, 100.0)
		player_state.radicalization = clampf(player_state.radicalization - 8.0, 0.0, 100.0)
		player_state.set_flag("wrs_gulag_abolished", true)
	mechanic_action_executed.emit("WRS_yakovlev_abolish_gulag", {"gulag": false})
	return true


# ==============================================================================
# СМУТА И ВНЕШНЯЯ ДИПЛОМАТИЯ
# ==============================================================================

"""Заключает пакт о ненападении с Республикой Коми."""
func establish_komi_nap() -> bool:
	if player_state != null:
		player_state.set_flag("wrs_komi_nap_active", true)
		player_state.stability = clampf(player_state.stability + 0.04, 0.0, 1.0)
	mechanic_action_executed.emit("RUS_Decision_Smuta_Expansion_KOM_WRS_Establish_NAP", {"status": "pact_signed"})
	return true


"""Расторгает пакт о ненападении с Республикой Коми."""
func end_komi_nap() -> bool:
	if player_state != null:
		player_state.set_flag("wrs_komi_nap_active", false)
		player_state.set_flag("wrs_komi_nap_broken", true)
	mechanic_action_executed.emit("RUS_Decision_Smuta_Expansion_KOM_WRS_End_NAP", {"status": "pact_broken"})
	return true


"""Интегрирует танковую бригаду Горького в состав РККА."""
func integrate_gorky_brigade() -> bool:
	if player_state != null:
		player_state.heavy_equipment_stockpile += 50
		player_state.army_readiness = clampf(player_state.army_readiness + 5.0, 0.0, 100.0)
		player_state.manpower_pool += 4000
		player_state.set_flag("wrs_gorky_integrated", true)
	mechanic_action_executed.emit("RUS_Decision_Smuta_Expansion_GOR_WRS_NyomNyomNyom", {"equipment": 50, "manpower": 4000})
	return true


# ==============================================================================
# СЕРИАЛИЗАЦИЯ
# ==============================================================================

func to_dict() -> Dictionary:
	return state.to_dict()


func from_dict(data: Dictionary) -> void:
	state.from_dict(data)
