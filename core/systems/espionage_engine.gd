class_name EspionageEngine
extends RefCounted

##
## EspionageEngine: Движок разведывательных служб, агентурных сетей и спецопераций TNO
##
## Реализует:
## 1. Управление Черным Бюджетом (Black Budget) и финансированием секретных служб.
## 2. Развитие и пассивную деградацию агентурных сетей внедрения (Infiltration Networks).
## 3. Расчет рисков, проверку порогов и резолв спецопераций (Stealth / Messy / Failure).
## 4. Прикладные диверсионные эффекты (кража технологий, саботаж ВПК, подрыв складов, перевороты).
##

## Результат выполнения одного цикла шпионажа для одной державы
class EspionageReport:
	var country_tag: String
	var black_budget_prev: float
	var black_budget_curr: float
	var total_upkeep: float
	var is_budget_deficit: bool
	var network_updates: Dictionary = {} # tag -> { "delta": float, "new_level": float, "status": String }
	var operations_progressed: Array[Dictionary] = []
	var completed_operations: Array[Dictionary] = []
	var incidents: Array[Dictionary] = []

	func to_dict() -> Dictionary:
		return {
			"country_tag": country_tag,
			"black_budget_prev": black_budget_prev,
			"black_budget_curr": black_budget_curr,
			"total_upkeep": total_upkeep,
			"is_budget_deficit": is_budget_deficit,
			"network_updates": network_updates,
			"operations_progressed": operations_progressed,
			"completed_operations": completed_operations,
			"incidents": incidents
		}


## Детерминированный генератор псевдослучайных величин для хода (Linear Congruential + Bit Shift)
static func _get_deterministic_factor(seed_val: int, min_val: float, max_val: float) -> float:
	var s: int = (seed_val * 73856093) ^ 1274126177
	s = (s ^ (s >> 13)) * 19349663
	var norm: float = float(s & 0x7FFFFFFF) / float(0x7FFFFFFF)
	return min_val + (norm * (max_val - min_val))


# ==============================================================================
# ГЛАВНЫЙ СИСТЕМНЫЙ ЦИКЛ ОБРАБОТКИ ХОДА (PROCESS TURN)
# ==============================================================================

##
## Главный пошаговый расчет разведывательной деятельности для всех стран
##
## countries: Dictionary[String, CountryState] — справочник всех государств
## delta_turns: int — число пропущенных ходов (обычно 1)
##
## Возвращает список отчетов по каждой стране, имеющей разведку
##
static func process_turn(
	countries: Dictionary,
	delta_turns: int = 1
) -> Array[Dictionary]:
	var reports: Array[Dictionary] = []

	for c_tag in countries.keys():
		var state: CountryState = countries[c_tag]
		if state == null:
			continue

		# Симулируем державы, имеющие бюджет, агентов или активные операции
		if state.black_budget > 0.0 or not state.active_agents.is_empty() or not state.active_covert_operations.is_empty() or not state.infiltration_networks.is_empty():
			var rep = _process_country_espionage(state, countries, delta_turns)
			if rep != null:
				reports.append(rep.to_dict())

	return reports


## Обработка разведывательного потенциала конкретного государства
static func _process_country_espionage(
	state: CountryState,
	countries: Dictionary,
	delta_turns: int = 1
) -> EspionageReport:
	var rep = EspionageReport.new()
	rep.country_tag = state.country_tag
	rep.black_budget_prev = state.black_budget

	for _step in range(delta_turns):
		# 1. Фаза финансирования и Черного Бюджета
		_process_black_budget_phase(state, rep)

		# 2. Симуляция агентурного проникновения (Infiltration Networks)
		_process_infiltration_networks_phase(state, countries, rep)

		# 3. Прогресс и резолв спецопераций
		_process_covert_operations_phase(state, countries, rep)

	rep.black_budget_curr = state.black_budget
	return rep


# ==============================================================================
# 1. ФАЗА ФИНАНСИРОВАНИЯ И ЧЕРНОГО БЮДЖЕТА (BLACK BUDGET PHASE)
# ==============================================================================

static func _process_black_budget_phase(
	state: CountryState,
	report: EspionageReport
) -> void:
	# 1.1 Пополнение черного бюджета из открытой казны
	if state.black_budget_allocation_per_turn > 0.0:
		state.black_budget += state.black_budget_allocation_per_turn

		# Списание эквивалента из ликвидных резервов ($ млн -> $ млрд)
		var deduction_billions = state.black_budget_allocation_per_turn / 1000.0
		state.liquid_reserves_billions -= deduction_billions

		# Если ликвидных резервов недостаточно, дефицит ложится на госдолг
		if state.liquid_reserves_billions < 0.0:
			var deficit_b = absf(state.liquid_reserves_billions)
			state.national_debt_billions += deficit_b
			state.liquid_reserves_billions = 0.0

	# 1.2 Списание операционных расходов (агенты + спецоперации)
	var total_upkeep: float = 0.0

	for ag in state.active_agents:
		if ag != null and ag.status != AgentResource.AgentStatus.CAPTURED:
			total_upkeep += ag.upkeep_cost_black_budget

	for op in state.active_covert_operations:
		if op != null and not op.is_aborted:
			total_upkeep += op.cost_per_turn

	state.black_budget -= total_upkeep
	report.total_upkeep = total_upkeep

	# 1.3 Кризис дефицита черного бюджета
	if state.black_budget < 0.0:
		report.is_budget_deficit = true

		# Замораживаем все активные операции
		for op in state.active_covert_operations:
			if op != null:
				op.is_frozen = true

		# Падение лояльности агентов на -15% за ход
		for ag in state.active_agents:
			if ag != null:
				ag.loyalty = clampf(ag.loyalty - 15.0, 0.0, 100.0)
				# При лояльности < 30% растет риск перевербовки в двойного агента
				if ag.loyalty < 30.0 and not ag.is_double_agent:
					var ag_seed: int = (state.turn_count * 99991) ^ (ag.id.hash() * 37)
					if _get_deterministic_factor(ag_seed, 0.0, 1.0) < 0.30:
						ag.is_double_agent = true
						report.incidents.append({
							"type": "AGENT_BETRAYAL",
							"agent_id": ag.id,
							"agent_codename": ag.codename,
							"description": "Агент %s тайно перевербован вражеской контрразведкой из-за хронических невыплат жалованья!" % ag.codename
						})
	else:
		report.is_budget_deficit = false
		# Если бюджет положительный, снимаем флаг дефицитной заморозки
		for op in state.active_covert_operations:
			if op != null and op.is_frozen:
				var net_lvl = state.get_infiltration_level(op.target_country_tag)
				if net_lvl >= op.required_infiltration:
					op.is_frozen = false


# ==============================================================================
# 2. СИМУЛЯЦИЯ АГЕНТУРНОГО ПРОНИКНОВЕНИЯ (INFILTRATION NETWORKS)
# ==============================================================================

static func _process_infiltration_networks_phase(
	state: CountryState,
	countries: Dictionary,
	report: EspionageReport
) -> void:
	# Собираем все страны, где есть присутствие агентов или уже развернутая сеть
	var relevant_tags: Array[String] = []
	for k in state.infiltration_networks.keys():
		var t = str(k).to_upper().strip_edges()
		if not relevant_tags.has(t) and not t.is_empty():
			relevant_tags.append(t)

	for ag in state.active_agents:
		if ag != null and not ag.assigned_country_tag.is_empty():
			var t = ag.assigned_country_tag.to_upper().strip_edges()
			if not relevant_tags.has(t) and t != state.country_tag:
				relevant_tags.append(t)

	for target_tag in relevant_tags:
		var target_st: CountryState = countries.get(target_tag, null)
		var target_sec = target_st.domestic_security if target_st != null else 50.0

		# Подсчет агентов, занимающихся развертыванием сети (INFILTRATING)
		var infiltrating_agents: Array[AgentResource] = []
		var total_agents_in_country = 0

		for ag in state.active_agents:
			if ag != null and ag.assigned_country_tag.to_upper().strip_edges() == target_tag:
				total_agents_in_country += 1
				if ag.status == AgentResource.AgentStatus.INFILTRATING:
					infiltrating_agents.append(ag)

		var delta_inf = 0.0

		if not infiltrating_agents.is_empty():
			# Формула ТЗ: ΔInfiltration = Σ(AgentCompetence * 1.5) - (TargetDomesticSecurity * 0.05)
			var comp_sum = 0
			for ag in infiltrating_agents:
				comp_sum += ag.competence
			delta_inf = (float(comp_sum) * 1.5) - (target_sec * 0.05)
		else:
			# Пассивное угасание: -2.0% за ход при отсутствии агентов внедрения
			delta_inf = -2.0

		var cur_level = state.get_infiltration_level(target_tag)
		var new_level = clampf(cur_level + delta_inf, 0.0, 100.0)

		# Определение статуса сети
		var net_status = "DORMANT"
		if new_level >= 70.0:
			net_status = "DEEP_COVER"
		elif new_level >= 30.0:
			net_status = "OPERATIONAL"
		elif new_level > 0.0:
			net_status = "ESTABLISHING"

		state.infiltration_networks[target_tag] = {
			"level": new_level,
			"network_status": net_status,
			"agents_count": total_agents_in_country
		}

		report.network_updates[target_tag] = {
			"delta": delta_inf,
			"new_level": new_level,
			"status": net_status
		}


# ==============================================================================
# 3. ПРОГРЕСС И РЕЗОЛВ СПЕЦОПЕРАЦИЙ (OPERATION RESOLUTION)
# ==============================================================================

static func _process_covert_operations_phase(
	state: CountryState,
	countries: Dictionary,
	report: EspionageReport
) -> void:
	var ops_to_process = state.active_covert_operations.duplicate()

	for op in ops_to_process:
		if op == null:
			continue

		# 3.1 Обработка протокола отмены (Abort Protocol)
		if op.is_aborted:
			_abort_operation(state, op, report)
			continue

		var target_st: CountryState = countries.get(op.target_country_tag, null)
		var target_sec = target_st.domestic_security if target_st != null else 50.0
		var net_level = state.get_infiltration_level(op.target_country_tag)

		# 3.2 Проверка условий готовности и порога сети
		if net_level < op.required_infiltration:
			op.is_frozen = true
			continue

		if state.black_budget < 0.0:
			op.is_frozen = true
			continue

		op.is_frozen = false

		# 3.3 Расчет пошагового риска раскрытия
		# Формула ТЗ: TurnRisk = Clamp(base_detection_risk + (TargetSecurity - Infiltration) * 0.01 - (AgentSkill * 0.03), 0.05, 0.95)
		var agent_skill_sum = 0
		var has_double_agent = false

		for aid in op.assigned_agent_ids:
			var ag = state.get_agent_by_id(aid)
			if ag != null:
				agent_skill_sum += ag.competence
				if ag.status != AgentResource.AgentStatus.EXECUTING_OP:
					ag.status = AgentResource.AgentStatus.EXECUTING_OP
				if ag.is_double_agent:
					has_double_agent = true

		var turn_risk = clampf(
			op.base_detection_risk + (target_sec - net_level) * 0.01 - (float(agent_skill_sum) * 0.03),
			0.05,
			0.95
		)

		# Удвоение риска при финансовом голоде
		if state.black_budget < 0.0:
			turn_risk = clampf(turn_risk * 2.0, 0.05, 0.98)

		# Штраф за двойного агента в группе
		if has_double_agent:
			turn_risk = clampf(turn_risk + 0.25, 0.05, 0.98)

		# Продвижение таймера операции
		op.current_turn_progress += 1

		report.operations_progressed.append({
			"op_id": op.op_id,
			"title": op.title,
			"target": op.target_country_tag,
			"progress": op.current_turn_progress,
			"total": op.total_turns_required,
			"turn_risk": turn_risk
		})

		# 3.4 Завершение подготовки и резолв
		if op.current_turn_progress >= op.total_turns_required:
			_resolve_operation_outcome(state, op, turn_risk, target_st, countries, report)


## Метод прямого разрешения одной операции (для тестов и скриптов)
func _resolve_operation(op: CovertOperationResource, state: CountryState, countries: Dictionary) -> Dictionary:
	return resolve_operation(op, state, countries)


static func resolve_operation(op: CovertOperationResource, state: CountryState, countries: Dictionary) -> Dictionary:
	var target_st: CountryState = countries.get(op.target_country_tag, null)
	var report_mock = EspionageReport.new()
	var stolen_tech = ""
	if op.type == CovertOperationResource.OpType.STEAL_TECH:
		var tech_key = str(op.operation_payload.get("target_tech", ""))
		if tech_key.is_empty() and target_st != null and not target_st.researched_techs.is_empty():
			for candidate in target_st.researched_techs:
				if not state.is_tech_researched(candidate):
					tech_key = candidate
					break
		stolen_tech = tech_key

	_resolve_operation_outcome(state, op, 0.0, target_st, countries, report_mock)

	var is_success = true
	var summary_text = ""
	if not report_mock.completed_operations.is_empty():
		var last_op = report_mock.completed_operations.back()
		summary_text = last_op.get("summary", "")
		if last_op.get("outcome", "") == "CATASTROPHIC_FAILURE":
			is_success = false

	return {
		"success": is_success,
		"report": summary_text,
		"stolen_tech_id": stolen_tech
	}


## Экстренное сворачивание операции (Abort Protocol)
static func _abort_operation(
	state: CountryState,
	op: CovertOperationResource,
	report: EspionageReport
) -> void:
	for aid in op.assigned_agent_ids:
		var ag = state.get_agent_by_id(aid)
		if ag != null and ag.status == AgentResource.AgentStatus.EXECUTING_OP:
			ag.status = AgentResource.AgentStatus.IDLE

	state.remove_operation(op.op_id)
	report.incidents.append({
		"type": "OPERATION_ABORTED",
		"op_id": op.op_id,
		"title": op.title,
		"description": "Операция [%s] экстренно свернута. Агенты отозваны на конспиративные квартиры." % op.title
	})


## Финальный резолв спецоперации с 3 исходами (Stealth / Messy / Failure)
static func _resolve_operation_outcome(
	state: CountryState,
	op: CovertOperationResource,
	risk: float,
	target_st: CountryState,
	countries: Dictionary,
	report: EspionageReport
) -> void:
	var op_seed: int = (state.turn_count * 73856093) ^ (op.op_id.hash() * 19349663) ^ op.target_country_tag.hash()
	var roll: float = _get_deterministic_factor(op_seed, 0.0, 1.0)

	if roll < risk:
		# ======================================================================
		# ИСХОД В: КАТАСТРОФИЧЕСКИЙ ПРОВАЛ (BUSTED / COMPROMISED)
		# ======================================================================
		_execute_catastrophic_failure(state, op, target_st, report)
	else:
		# Операция успешна. Проверяем скрытность (Stealth vs Messy)
		# Если бросок превысил риск с хорошим запасом — чистый успех
		var is_stealth = (roll > (risk + 0.15)) and not _has_double_agent(state, op)

		if is_stealth:
			# ==================================================================
			# ИСХОД А: ЧИСТЫЙ УСПЕХ (STEALTH SUCCESS)
			# ==================================================================
			_execute_stealth_success(state, op, target_st, report)
		else:
			# ==================================================================
			# ИСХОД Б: УСПЕХ С КОМПРОМЕТАЦИЕЙ (MESSY SUCCESS)
			# ==================================================================
			_execute_messy_success(state, op, target_st, report)

	# Завершение операции и освобождение агентов
	state.remove_operation(op.op_id)
	for aid in op.assigned_agent_ids:
		var ag = state.get_agent_by_id(aid)
		if ag != null and ag.status == AgentResource.AgentStatus.EXECUTING_OP:
			ag.status = AgentResource.AgentStatus.IDLE


static func _has_double_agent(state: CountryState, op: CovertOperationResource) -> bool:
	for aid in op.assigned_agent_ids:
		var ag = state.get_agent_by_id(aid)
		if ag != null and ag.is_double_agent:
			return true
	return false


# ==============================================================================
# 4. ИСПОЛНЕНИЕ ИСХОДОВ И НОМЕНКЛАТУРА ДИВЕРСИЙ
# ==============================================================================

## А. Чистый успех: полный триумф без раскрытия авторства
static func _execute_stealth_success(
	state: CountryState,
	op: CovertOperationResource,
	target_st: CountryState,
	report: EspionageReport
) -> void:
	var effects_summary = _apply_operation_payload_effects(state, op, target_st)

	# Опыт агентам
	for aid in op.assigned_agent_ids:
		var ag = state.get_agent_by_id(aid)
		if ag != null:
			ag.loyalty = clampf(ag.loyalty + 5.0, 0.0, 100.0)
			var xp_seed: int = (state.turn_count * 1013) ^ (ag.id.hash() * 31)
			if _get_deterministic_factor(xp_seed, 0.0, 1.0) < 0.20 and ag.competence < 5:
				ag.competence += 1

	report.completed_operations.append({
		"outcome": "STEALTH_SUCCESS",
		"op_id": op.op_id,
		"title": op.title,
		"target": op.target_country_tag,
		"type": op.type,
		"summary": effects_summary,
		"description": "ОПЕРАЦИЯ УВЕНЧАЛАСЬ ПОЛНЫМ УСПЕХОМ: Цель поражена чисто, следов участия не обнаружено."
	})


## Б. Успех с компрометацией: цель достигнута, но авторство раскрыто
static func _execute_messy_success(
	state: CountryState,
	op: CovertOperationResource,
	target_st: CountryState,
	report: EspionageReport
) -> void:
	var effects_summary = _apply_operation_payload_effects(state, op, target_st)

	# Скачок международной напряженности / падение DEFCON
	_escalate_geopolitical_tension(state, target_st)

	# Дипломатический кризис
	if target_st != null:
		target_st.radicalization = clampf(target_st.radicalization + 10.0, 0.0, 100.0)
		target_st.story_flags["provoked_by_" + state.country_tag] = true

	# Риск компрометации одного из исполнителей
	if not op.assigned_agent_ids.is_empty():
		var comp_ag = state.get_agent_by_id(op.assigned_agent_ids[0])
		if comp_ag != null:
			comp_ag.status = AgentResource.AgentStatus.COMPROMISED

	report.completed_operations.append({
		"outcome": "MESSY_SUCCESS",
		"op_id": op.op_id,
		"title": op.title,
		"target": op.target_country_tag,
		"type": op.type,
		"summary": effects_summary,
		"description": "ЦЕЛЬ ДОСТИГНУТА С ОСЛОЖНЕНИЯМИ: Вражеская контрразведка перехватила связных. Авторство диверсии раскрыто!"
	})


## В. Катастрофический провал: срыв операции, арест агентов и обнуление сети
static func _execute_catastrophic_failure(
	state: CountryState,
	op: CovertOperationResource,
	target_st: CountryState,
	report: EspionageReport
) -> void:
	# Полное обнуление агентурной сети в целевой стране
	state.set_infiltration_level(op.target_country_tag, 0.0, "DORMANT")

	# Арест или гибель назначенных агентов
	for aid in op.assigned_agent_ids:
		var ag = state.get_agent_by_id(aid)
		if ag != null:
			var cap_seed: int = (state.turn_count * 7919) ^ (ag.id.hash() * 43)
			if _get_deterministic_factor(cap_seed, 0.0, 1.0) < 0.60:
				ag.status = AgentResource.AgentStatus.CAPTURED
				ag.loyalty = 0.0
			else:
				ag.status = AgentResource.AgentStatus.COMPROMISED

	# Удар по легитимности и престижу инициатора
	state.legitimacy = clampf(state.legitimacy - 5.0, 0.0, 100.0)

	# Скачок напряженности
	_escalate_geopolitical_tension(state, target_st)

	report.completed_operations.append({
		"outcome": "CATASTROPHIC_FAILURE",
		"op_id": op.op_id,
		"title": op.title,
		"target": op.target_country_tag,
		"type": op.type,
		"summary": "ПРОВАЛ: Сеть ликвидирована, агенты арестованы.",
		"description": "КАТАСТРОФИЧЕСКИЙ ПРОВАЛ: Оперативная группа разгромлена вражеской контрразведкой. Агентурная сеть ликвидирована полностью!"
	})


## Прикладное применение эффектов в зависимости от типа операции
static func _apply_operation_payload_effects(
	state: CountryState,
	op: CovertOperationResource,
	target_st: CountryState
) -> String:
	var op_seed: int = (state.turn_count * 73856093) ^ (op.op_id.hash() * 19349663) ^ op.target_country_tag.hash()

	match op.type:
		CovertOperationResource.OpType.STEAL_TECH:
			# 1. STEAL_TECH: похищение реальных чертежей и начисление 40–70% прогресса технологии
			var gain: float = _get_deterministic_factor(op_seed + 101, 40.0, 70.0)
			var tech_key: String = str(op.operation_payload.get("target_tech", ""))

			# Если конкретная цель не задана, похищаем технологию, которая есть у цели, но нет у нас
			if tech_key.is_empty() and target_st != null and not target_st.researched_techs.is_empty():
				for candidate in target_st.researched_techs:
					if not state.is_tech_researched(candidate):
						tech_key = candidate
						break

			if tech_key.is_empty():
				var pool = [
					"tech_industry_cnc_machining", "tech_infantry_general_purpose_mg",
					"tech_armor_first_gen_mbt", "tech_air_supersonic_fighters",
					"tech_nuke_heavy_water_reactor", "tech_doctrine_automated_c2"
				]
				for cand in pool:
					if not state.is_tech_researched(cand):
						tech_key = cand
						break

			if tech_key.is_empty():
				tech_key = "tech_industry_mechanization_1"

			# Запись чертежа и прогресса в стейт
			var flag_name: String = "blueprint_" + tech_key
			state.set_flag(flag_name, gain)
			state.political_capital += 15.0

			# Если тема прямо сейчас разрабатывается в активном слоте — ускоряем прогресс
			if state.active_researches.has(tech_key):
				var info: Dictionary = state.active_researches[tech_key]
				var cost: float = float(info.get("cost", 100.0))
				info["progress"] = float(info.get("progress", 0.0)) + (cost * (gain / 100.0))
				state.active_researches[tech_key] = info

			var t_label: String = tech_key.replace("tech_", "").replace("_", " ").capitalize()
			return "Похищен секретный комплект чертежей [%s] у державы [%s]. Затраты на исследование снижены на %d%%." % [
				t_label,
				op.target_country_tag,
				int(gain)
			]

		CovertOperationResource.OpType.SABOTAGE_INDUSTRY:
			# 2. SABOTAGE_INDUSTRY: временный штраф на производственный потенциал (IC modifier -25%)
			if target_st != null:
				var turns: int = int(op.operation_payload.get("duration_turns", 6))
				target_st.story_flags["sabotage_ic_turns"] = turns
				target_st.story_flags["sabotage_ic_modifier"] = -0.25
				# Прямой урон по гражданским и военным заводам
				var civ_loss: int = maxi(int(float(target_st.civilian_factories) * 0.15), 1)
				var mil_loss: int = maxi(int(float(target_st.military_factories) * 0.15), 1)
				target_st.civilian_factories = maxi(target_st.civilian_factories - civ_loss, 0)
				target_st.military_factories = maxi(target_st.military_factories - mil_loss, 0)
				return "Взрывы на индустриальных комплексах цели. Выведено из строя %d гражд. и %d воен. заводов на %d ходов." % [civ_loss, mil_loss, turns]
			return "Диверсия на промышленных объектах выполнена."

		CovertOperationResource.OpType.SABOTAGE_MILITARY:
			# 3. SABOTAGE_MILITARY: списание от 10% до 30% запасов снаряжения и снижение готовности
			if target_st != null:
				var cut_ratio: float = _get_deterministic_factor(op_seed + 202, 0.15, 0.30)
				var loss_inf: int = int(float(target_st.infantry_weapons_stockpile) * cut_ratio)
				var loss_heavy: int = int(float(target_st.heavy_equipment_stockpile) * cut_ratio)
				target_st.infantry_weapons_stockpile = maxi(target_st.infantry_weapons_stockpile - loss_inf, 0)
				target_st.heavy_equipment_stockpile = maxi(target_st.heavy_equipment_stockpile - loss_heavy, 0)
				target_st.army_readiness = clampf(target_st.army_readiness - 18.0, 5.0, 100.0)
				target_st.army_morale = clampf(target_st.army_morale - 12.0, 5.0, 100.0)
				return "Взорваны центральные склады РАВ. Уничтожено %d винтовок, %d ед. тяжелой техники. Боеготовность упала на -18%%." % [loss_inf, loss_heavy]
			return "Армейские арсеналы противника подорваны."

		CovertOperationResource.OpType.FUND_COUP:
			# 4. FUND_COUP: падение лояльности фракций цели; при лояльности <20% мятеж
			if target_st != null:
				target_st.modify_faction_loyalty("military", -20.0)
				target_st.modify_faction_loyalty("regional_elites", -25.0)
				target_st.radicalization = clampf(target_st.radicalization + 20.0, 0.0, 100.0)
				target_st.legitimacy = clampf(target_st.legitimacy - 15.0, 0.0, 100.0)

				var mil_loy = target_st.factions_loyalty.get("military", 50.0)
				if mil_loy < 25.0 or target_st.legitimacy < 20.0:
					target_st.story_flags["coup_imminent"] = true
					target_st.story_flags["coup_sponsor"] = state.country_tag
					return "Заговор офицеров созрел: лояльность генералитета упала ниже критической отметки! Переворот неизбежен."
				else:
					return "Подкуплены влиятельные генералы и чиновники. Лояльность фракций цели подорвана (-20%)."
			return "Оппозиционные круги профинансированы."

		CovertOperationResource.OpType.ARM_REBELS:
			# 5. ARM_REBELS: рост недовольства в тыловых провинциях и спавн партизан
			if target_st != null:
				target_st.radicalization = clampf(target_st.radicalization + 15.0, 0.0, 100.0)
				target_st.domestic_security = clampf(target_st.domestic_security - 20.0, 5.0, 100.0)
				target_st.story_flags["active_insurgency"] = true
				return "Оружие доставлено партизанским ячейкам. Вспыхнули восстания в тылу врага, контрразведка дезорганизована."
			return "Партизаны снабжены стрелковым оружием и взрывчаткой."

		CovertOperationResource.OpType.DISINFORMATION:
			# 6. DISINFORMATION: дезинформация и снижение контрразведки противника
			if target_st != null:
				target_st.domestic_security = clampf(target_st.domestic_security - 25.0, 5.0, 100.0)
				target_st.radicalization = clampf(target_st.radicalization + 8.0, 0.0, 100.0)
				return "Дезинформация успешно внедрена в генштаб противника. Эффективность их контрразведки снижена на -25%%."
			return "Дезинформация успешно посеяна."

		CovertOperationResource.OpType.ASSASSINATION:
			# 7. ASSASSINATION: ликвидация командующего или министра
			if target_st != null:
				target_st.legitimacy = clampf(target_st.legitimacy - 20.0, 0.0, 100.0)
				target_st.army_readiness = clampf(target_st.army_readiness - 15.0, 5.0, 100.0)
				if not target_st.military_commanders.is_empty():
					var killed_cmd = target_st.military_commanders.pop_back()
					var cmd_name = killed_cmd.leader_name if killed_cmd != null else "Высший офицер"
					return "Ликвидирован командующий [%s]. Войска противника деморализованы." % cmd_name
				return "Ликвидирован ключевой советник режима цели. Управляемость противника подорвана."
			return "Ликвидация цели завершена успешно."

		_:
			return "Спецоперация выполнена."


## Эскалация шкалы DEFCON при международных скандалах сверхдержав
static func _escalate_geopolitical_tension(initiator: CountryState, target: CountryState) -> void:
	var defcon = initiator.story_flags.get("defcon_level", 5)
	if defcon is int or defcon is float:
		var new_defcon = maxi(int(defcon) - 1, 1)
		initiator.story_flags["defcon_level"] = new_defcon
		if target != null:
			target.story_flags["defcon_level"] = new_defcon


# ==============================================================================
# ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ И СОЗДАНИЕ ОПЕРАЦИЙ
# ==============================================================================

## Создание стандартной спецоперации по шаблону
static func create_covert_operation(
	op_type: CovertOperationResource.OpType,
	target_tag: String,
	title_custom: String = ""
) -> CovertOperationResource:
	var op = CovertOperationResource.new()
	op.type = op_type
	op.target_country_tag = target_tag.to_upper().strip_edges()

	match op_type:
		CovertOperationResource.OpType.STEAL_TECH:
			op.title = title_custom if not title_custom.is_empty() else "Проект «Прометей»: Кража чертежей НИОКР"
			op.required_infiltration = 45.0
			op.cost_per_turn = 1.2
			op.total_turns_required = 3
			op.base_detection_risk = 0.20
			op.operation_payload = {"target_tech": "advanced_rifles"}

		CovertOperationResource.OpType.SABOTAGE_INDUSTRY:
			op.title = title_custom if not title_custom.is_empty() else "Операция «Ржавчина»: Диверсия на заводах"
			op.required_infiltration = 55.0
			op.cost_per_turn = 2.0
			op.total_turns_required = 4
			op.base_detection_risk = 0.30
			op.operation_payload = {"duration_turns": 6}

		CovertOperationResource.OpType.SABOTAGE_MILITARY:
			op.title = title_custom if not title_custom.is_empty() else "Операция «Пороховая бочка»: Подрыв складов"
			op.required_infiltration = 50.0
			op.cost_per_turn = 1.8
			op.total_turns_required = 3
			op.base_detection_risk = 0.28
			op.operation_payload = {"cut_percent": 25.0}

		CovertOperationResource.OpType.FUND_COUP:
			op.title = title_custom if not title_custom.is_empty() else "Операция «Переворот»: Заговор генералов"
			op.required_infiltration = 75.0
			op.cost_per_turn = 4.5
			op.total_turns_required = 6
			op.base_detection_risk = 0.40
			op.operation_payload = {"target_faction": "military"}

		CovertOperationResource.OpType.ARM_REBELS:
			op.title = title_custom if not title_custom.is_empty() else "Операция «Лесной пожар»: Снабжение партизан"
			op.required_infiltration = 40.0
			op.cost_per_turn = 1.5
			op.total_turns_required = 3
			op.base_detection_risk = 0.22

		CovertOperationResource.OpType.DISINFORMATION:
			op.title = title_custom if not title_custom.is_empty() else "Операция «Туман войны»: Дезинформация"
			op.required_infiltration = 30.0
			op.cost_per_turn = 0.8
			op.total_turns_required = 2
			op.base_detection_risk = 0.15

		CovertOperationResource.OpType.ASSASSINATION:
			op.title = title_custom if not title_custom.is_empty() else "Операция «Немезида»: Ликвидация командования"
			op.required_infiltration = 70.0
			op.cost_per_turn = 3.0
			op.total_turns_required = 5
			op.base_detection_risk = 0.35

	return op


## Создание агента с заданным профилем
static func recruit_agent(
	codename: String,
	competence: int = 3,
	assigned_country: String = "",
	upkeep_cost: float = 0.6
) -> AgentResource:
	var ag = AgentResource.new("", codename, competence, 90.0, upkeep_cost)
	ag.assigned_country_tag = assigned_country.to_upper().strip_edges()
	if not assigned_country.is_empty():
		ag.status = AgentResource.AgentStatus.INFILTRATING
	else:
		ag.status = AgentResource.AgentStatus.IDLE
	return ag


# ==============================================================================
# 5. АВТОНОМНЫЙ ТЕСТОВЫЙ RUNNER (HEADLESS DEBUG SIMULATION)
# ==============================================================================

##
## Тестовый метод для валидации шпионажа, списания черного бюджета,
## развития агентурных сетей и диверсий без полного запуска графического клиента
##
static func _run_espionage_debug_simulation() -> bool:
	print("================================================================================")
	print("[ESPIONAGE_ENGINE] RUNNING HEADLESS DEBUG SIMULATION...")
	print("================================================================================")

	# 1. Подготовка тестовых государств
	var attacker = CountryState.new()
	attacker.country_tag = "KOM"
	attacker.country_name = "West Russian Revolutionary Front"
	attacker.black_budget = 20.0
	attacker.black_budget_allocation_per_turn = 5.0
	attacker.liquid_reserves_billions = 2.0
	attacker.domestic_security = 60.0

	var target = CountryState.new()
	target.country_tag = "GER"
	target.country_name = "Greater German Reich"
	target.domestic_security = 50.0
	target.civilian_factories = 40
	target.military_factories = 50
	target.infantry_weapons_stockpile = 50000
	target.heavy_equipment_stockpile = 3000

	var world_countries = {
		"KOM": attacker,
		"GER": target
	}

	# 2. Проверка рекрутинга агентов и внедрения
	var ag1 = recruit_agent("Specter", 4, "GER", 1.0)
	var ag2 = recruit_agent("Valkyrie", 3, "GER", 0.8)
	attacker.add_agent(ag1)
	attacker.add_agent(ag2)

	assert(attacker.active_agents.size() == 2, "Must contain 2 recruited agents")
	print("[OK] Recruited 2 operational agents: Specter (Comp 4), Valkyrie (Comp 3).")

	# 3. Симуляция 3 ходов развития сети
	for turn in range(1, 4):
		var reps = process_turn(world_countries, 1)
		var kom_rep = reps[0] if not reps.is_empty() else {}
		var inf_lvl = attacker.get_infiltration_level("GER")
		print("  -> Turn %d: Infiltration in GER = %0.1f%%, Black Budget = $%0.1f M" % [turn, inf_lvl, attacker.black_budget])

	var net_level_after_3_turns = attacker.get_infiltration_level("GER")
	assert(net_level_after_3_turns > 15.0, "Infiltration network should grow with 2 active agents")
	print("[OK] Infiltration Network Dynamic verified. Level reached: %0.1f%%." % net_level_after_3_turns)

	# 4. Проверка спецоперации: Подрыв армейских складов
	var op_sabotage = create_covert_operation(
		CovertOperationResource.OpType.SABOTAGE_MILITARY,
		"GER",
		"Operation Iron Hammer"
	)
	op_sabotage.required_infiltration = 10.0 # Снижаем для ускоренного теста
	op_sabotage.total_turns_required = 2
	var agent_ids: Array[String] = [ag1.id, ag2.id]
	op_sabotage.assigned_agent_ids = agent_ids
	attacker.add_operation(op_sabotage)

	print("\n[STEP 4] Executing Covert Operation: %s (Total turns: 2)..." % op_sabotage.title)
	var init_weapons = target.infantry_weapons_stockpile

	# Запускаем ходы до завершения операции
	var op_completed = false
	for turn in range(4, 7):
		var reps = process_turn(world_countries, 1)
		for r in reps:
			if r.get("completed_operations", []).size() > 0:
				op_completed = true
				print("  -> Turn %d: Operation completed! Report: %s" % [turn, r["completed_operations"][0]["summary"]])
		if op_completed:
			break

	assert(op_completed, "Covert Operation should be resolved within turns")
	print("[OK] Operation resolved properly. Stockpiles damaged or network compromised.")

	# 5. Проверка дефицита черного бюджета и заморозки
	print("\n[STEP 5] Testing Black Budget Deficit & Operation Freezing...")
	attacker.black_budget = -10.0 # Искусственный дефицит
	attacker.black_budget_allocation_per_turn = 0.0

	var op_new = create_covert_operation(CovertOperationResource.OpType.STEAL_TECH, "GER")
	op_new.required_infiltration = 5.0
	attacker.add_operation(op_new)

	ag1.status = AgentResource.AgentStatus.IDLE
	ag1.loyalty = 80.0
	var prev_loyalty = ag1.loyalty
	process_turn(world_countries, 1)

	assert(op_new.is_frozen == true, "Operation must freeze under black budget deficit")
	assert(ag1.loyalty < prev_loyalty, "Agent loyalty must drop during deficit")
	print("[OK] Deficit crisis mechanics confirmed: operations frozen, agent loyalty dropped (-15%%).")

	# 6. Проверка пассивного угасания сети при отсутствии агентов
	print("\n[STEP 6] Testing Passive Network Decay...")
	attacker.active_agents.clear() # Убираем агентов
	attacker.set_infiltration_level("GER", 40.0)
	var level_before_decay = attacker.get_infiltration_level("GER")
	attacker.black_budget = 50.0 # Восстанавливаем бюджет

	process_turn(world_countries, 1)
	var level_after_decay = attacker.get_infiltration_level("GER")
	assert(level_after_decay < level_before_decay, "Network must passively decay without infiltrating agents")
	assert(is_equal_approx(level_after_decay, 38.0), "Decay must be exactly -2.0% per turn")
	print("[OK] Passive network decay verified: %0.1f%% -> %0.1f%% (-2.0%%/turn)." % [level_before_decay, level_after_decay])

	print("================================================================================")
	print("[ESPIONAGE_ENGINE] ALL HEADLESS TESTS PASSED SUCCESSFULLY [100%]")
	print("================================================================================")
	return true
