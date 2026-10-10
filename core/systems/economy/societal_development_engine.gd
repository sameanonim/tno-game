class_name SocietalDevelopmentEngine
extends RefCounted

##
## SocietalDevelopmentEngine: Модуль социального развития и антикризисных мер TNO
## ==============================================================================
## Отвечает за:
## 1. Динамику бедности (Poverty Rate), грамотности (Literacy) и коррупции (Corruption).
## 2. Развитие промышленной оснащенности (Industrial Equipment).
## 3. Антикризисные фискальные программы:
##    - Режим жесткой экономии (Austerity)
##    - Денежная стабилизационная реформа (Currency Reform)
##    - Реструктуризация суверенного долга (Debt Restructuring)
## ==============================================================================


static func _tr_str(key: String, params: Dictionary = {}, fallback: String = "") -> String:
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree and main_loop.root != null and main_loop.root.has_node("LocalizationManager"):
		var loc: Node = main_loop.root.get_node("LocalizationManager")
		if loc != null and loc.has_method("tr_key"):
			return str(loc.call("tr_key", key, params, fallback))
	var s: String = TranslationServer.translate(key)
	if s.is_empty() or s == key:
		s = fallback
	for k: Variant in params:
		s = s.replace("{%s}" % str(k), str(params[k]))
	return s


"""Обновление параметров общества за ход.
"""
static func update_societal_development(state: CountryState, turns_per_year: float) -> Dictionary:
	var cfg: ConfigManager = ConfigManager.get_instance()
	var soc_cfg: Dictionary = cfg.get_dict("economy", "societal_development") if (cfg != null and cfg.has_constant("economy", "societal_development")) else {}

	var pov_red_rate: float = float(soc_cfg.get("poverty_reduction_base_rate", 0.05))
	var pov_neg_rate: float = float(soc_cfg.get("poverty_growth_neglect_rate", 0.08))
	var lit_gain_rate: float = float(soc_cfg.get("literacy_gain_base_rate", 0.04))
	var cor_red_rate: float = float(soc_cfg.get("corruption_reduction_base_rate", 0.05))
	var cor_neg_rate: float = float(soc_cfg.get("corruption_growth_neglect_rate", 0.07))
	var eq_growth_rate: float = float(soc_cfg.get("industrial_equipment_growth_rate", 0.03))

	# 1. Бедность (Poverty Rate)
	var poverty_delta: float = 0.0
	if state.civilian_spending_share >= 0.25:
		poverty_delta = - (state.civilian_spending_share - 0.20) * pov_red_rate
	elif state.civilian_spending_share < 0.18:
		poverty_delta = (0.18 - state.civilian_spending_share) * pov_neg_rate
	state.poverty_rate = clampf(state.poverty_rate + (poverty_delta * 52.0 / turns_per_year), 3.0, 95.0)

	# 2. Грамотность (Literacy Rate)
	var literacy_delta: float = 0.0
	if state.rd_spending_share >= 0.08:
		literacy_delta = state.rd_spending_share * lit_gain_rate
	state.literacy_rate = clampf(state.literacy_rate + (literacy_delta * 52.0 / turns_per_year), 10.0, 99.0)

	# 3. Коррупция (Corruption Rate)
	var corruption_delta: float = 0.0
	if state.admin_spending_share >= 0.22:
		corruption_delta = - (state.admin_spending_share - 0.18) * cor_red_rate
	elif state.admin_spending_share < 0.16:
		corruption_delta = (0.16 - state.admin_spending_share) * cor_neg_rate
	state.corruption_rate = clampf(state.corruption_rate + (corruption_delta * 52.0 / turns_per_year), 5.0, 90.0)

	# 4. Промышленная оснащенность (Industrial Equipment)
	var eq_delta: float = 0.0
	if state.civilian_factories >= 12 and state.liquid_reserves_billions > 0.5:
		eq_delta = eq_growth_rate
	state.industrial_equipment_level = clampf(state.industrial_equipment_level + (eq_delta * 52.0 / turns_per_year), 10.0, 100.0)

	return {
		"poverty_delta": poverty_delta,
		"literacy_delta": literacy_delta,
		"corruption_delta": corruption_delta,
		"equipment_delta": eq_delta
	}


"""Переключение режима жесткой экономии (Austerity).
"""
static func toggle_austerity_program(state: CountryState) -> Dictionary:
	state.is_austerity_active = not state.is_austerity_active
	if state.is_austerity_active:
		state.radicalization = clampf(state.radicalization + 6.0, 0.0, 100.0)
		state.legitimacy = clampf(state.legitimacy - 4.0, 0.0, 100.0)
		return {
			"active": true,
			"message": _tr_str("ECON_AUSTERITY_ON_MSG", {}, "РЕЖИМ ЖЕСТКОЙ ЭКОНОМИИ ВКЛЮЧЕН: Военные и гражданские расходы урезаны, сборы повышены, но недовольство растет.")
		}
	else:
		return {
			"active": false,
			"message": _tr_str("ECON_AUSTERITY_OFF_MSG", {}, "РЕЖИМ ЖЕСТКОЙ ЭКОНОМИИ СНЯТ: Финансирование секторов возвращено в штатный режим.")
		}


"""Проведение денежной реформы (сбивает гиперинфляцию ценой резервов).
"""
static func conduct_currency_reform(state: CountryState) -> Dictionary:
	var cost: float = 0.40
	if state.liquid_reserves_billions < cost:
		return {
			"success": false,
			"message": _tr_str(
				"ECON_CURRENCY_REFORM_FAIL_MSG",
				{"required": "0.40"},
				"Отказ: Недостаточно валютных резервов для обеспечения новой денежной массы (требуется $0.40 млрд)."
			)
		}

	state.liquid_reserves_billions -= cost
	state.inflation_rate = clampf(state.inflation_rate * 0.45, 0.02, 0.95)
	state.legitimacy = clampf(state.legitimacy + 5.0, 0.0, 100.0)
	return {
		"success": true,
		"message": _tr_str(
			"ECON_CURRENCY_REFORM_SUCCESS_MSG",
			{"rate": "%.1f" % (state.inflation_rate * 100.0)},
			"Денежная реформа успешно проведена: инфляция сбита ценой стабилизационного фонда."
		)
	}


"""Реструктуризация суверенного внешнего долга.
"""
static func restructure_foreign_debt(state: CountryState) -> Dictionary:
	if state.national_debt_billions <= 0.0:
		return {
			"success": false,
			"message": _tr_str(
				"ECON_DEBT_RESTRUCTURE_ZERO_MSG",
				{},
				"Отказ: У государства отсутствует суверенный долг для реструктуризации."
			)
		}

	var haircut: float = state.national_debt_billions * 0.35
	state.national_debt_billions = maxf(state.national_debt_billions - haircut, 0.0)
	state.credit_rating_index = maxi(state.credit_rating_index - 3, state.credit_rating_min)
	state.legitimacy = clampf(state.legitimacy - 12.0, 0.0, 100.0)
	state.radicalization = clampf(state.radicalization + 8.0, 0.0, 100.0)

	return {
		"success": true,
		"haircut": haircut,
		"message": _tr_str(
			"ECON_DEBT_RESTRUCTURE_SUCCESS_MSG",
			{"haircut": "%.2f" % haircut},
			"Долг реструктурирован: списано $%.2f млрд обязательств, однако кредитный рейтинг обрушен до дефолтного уровня."
		)
	}
