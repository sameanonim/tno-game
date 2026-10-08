class_name RegionalInvestmentsManager
extends RefCounted

##
## RegionalInvestmentsManager: Менеджер региональных инвестиций в инфраструктуру, заводы и недра
## ==============================================================================
## Отвечает за:
## 1. Модернизацию инфраструктуры провинций (требует деньги, CAP и учет строительного пула).
## 2. Строительство гражданских фабрик и военных заводов (с учетом доступности Construction Pool).
## 3. Геологоразведку и освоение месторождений природных ресурсов.
## ==============================================================================


static func _tr_str(key: String, params: Dictionary = {}, fallback: String = "") -> String:
	return EconomyEngine._tr_str(key, params, fallback)


"""Инвестиция в модернизацию инфраструктуры провинции.
"""
static func invest_in_infrastructure(province_id: int, state: CountryState, regions: Dictionary) -> Dictionary:
	var cfg = ConfigManager.get_instance()
	var cost_money := 0.15
	var cost_cap := 1
	if cfg != null and cfg.has_constant("economy", "regional_investments"):
		var ri = cfg.get_dict("economy", "regional_investments")
		cost_money = float(ri.get("infrastructure_cost_money", cost_money))
		cost_cap = int(ri.get("infrastructure_cost_cap", cost_cap))

	if not regions.has(province_id):
		return {"success": false, "message": _tr_str("ECON_PROVINCE_NOT_FOUND", {}, "Провинция не найдена.")}

	var reg: RegionData = regions[province_id]
	if reg.owner_tag != state.country_tag:
		return {"success": false, "message": _tr_str("ECON_PROVINCE_NOT_OWNED", {}, "Регион не находится под контролем государства.")}

	# Проверка строительного пула: при нехватке свободных мощностей применяются штрафы частных подрядчиков
	if state.civilian_factories > 0 and EconomyEngine.get_available_construction_factories(state) <= 0:
		cost_money *= 1.5
		cost_cap += 1

	if state.current_cap < cost_cap:
		return {"success": false, "message": _tr_str("ECON_INSUFFICIENT_CAP", {}, "Недостаточно очков действий кабинета (CAP).")}

	if state.liquid_reserves_billions < cost_money:
		if state.is_in_fiscal_crisis:
			return {"success": false, "message": _tr_str("ECON_FISCAL_CRISIS_BLOCK", {}, "Фискальный кризис: казна пуста, кредиторы заблокировали займы.")}
		state.national_debt_billions += cost_money
	else:
		state.liquid_reserves_billions -= cost_money

	state.current_cap -= cost_cap
	reg.civilian_infrastructure = mini(reg.civilian_infrastructure + 1, 10)

	return {
		"success": true,
		"new_level": reg.civilian_infrastructure,
		"message": _tr_str("ECON_INVEST_INFRA_SUCCESS", {"name": reg.province_name, "level": reg.civilian_infrastructure}, "Инфраструктура региона %s модернизирована до ур. %d!" % [reg.province_name, reg.civilian_infrastructure])
	}


"""Строительство фабрики или военного завода в регионе.
"""
static func invest_in_factory(province_id: int, state: CountryState, regions: Dictionary, is_military: bool) -> Dictionary:
	var cfg = ConfigManager.get_instance()
	var cost_money := 0.35
	var cost_cap := 2
	if cfg != null and cfg.has_constant("economy", "regional_investments"):
		var ri = cfg.get_dict("economy", "regional_investments")
		cost_money = float(ri.get("factory_cost_money", cost_money))
		cost_cap = int(ri.get("factory_cost_cap", cost_cap))

	if not regions.has(province_id):
		return {"success": false, "message": _tr_str("ECON_PROVINCE_NOT_FOUND", {}, "Провинция не найдена.")}

	var reg: RegionData = regions[province_id]
	if reg.owner_tag != state.country_tag:
		return {"success": false, "message": _tr_str("ECON_PROVINCE_NOT_OWNED", {}, "Регион не контролируется государством.")}

	# Проверка строительного пула (Construction Pool / Consumer Goods lock)
	if state.civilian_factories > 0 and EconomyEngine.get_available_construction_factories(state) <= 0:
		return {
			"success": false,
			"message": _tr_str("ECON_NO_CONSTRUCTION_FACTORIES", {}, "Строительный пул исчерпан: все гражданские мощности задействованы на производство товаров народного потребления (ТНП).")
		}

	if state.current_cap < cost_cap:
		return {"success": false, "message": _tr_str("ECON_INSUFFICIENT_CAP", {}, "Недостаточно очков действий кабинета (CAP).")}

	if state.liquid_reserves_billions < cost_money:
		if state.is_in_fiscal_crisis:
			return {"success": false, "message": _tr_str("ECON_FISCAL_CRISIS_BLOCK", {}, "Фискальный кризис: казна пуста, новые займы недоступны.")}
		state.national_debt_billions += cost_money
	else:
		state.liquid_reserves_billions -= cost_money

	state.current_cap -= cost_cap
	reg.industrial_capacity += 1
	if is_military:
		state.military_factories += 1
	else:
		state.civilian_factories += 1

	var fac_msg = _tr_str("ECON_BUILD_FAC_MIL_SUCCESS", {"name": reg.province_name}, "Военный завод успешно возведен в регионе %s!" % reg.province_name) if is_military else _tr_str("ECON_BUILD_FAC_CIV_SUCCESS", {"name": reg.province_name}, "Гражданская фабрика успешно возведена в регионе %s!" % reg.province_name)
	return {
		"success": true,
		"message": fac_msg
	}


"""Геологоразведка и освоение месторождений в регионе.
"""
static func prospect_resources(province_id: int, state: CountryState, regions: Dictionary, resource_type: String) -> Dictionary:
	var cfg = ConfigManager.get_instance()
	var cost_money := 0.20
	var cost_cap := 1
	if cfg != null and cfg.has_constant("economy", "regional_investments"):
		var ri = cfg.get_dict("economy", "regional_investments")
		cost_money = float(ri.get("resource_prospect_cost_money", cost_money))
		cost_cap = int(ri.get("resource_prospect_cost_cap", cost_cap))

	if not regions.has(province_id):
		return {"success": false, "message": _tr_str("ECON_PROVINCE_NOT_FOUND", {}, "Провинция не найдена.")}

	var reg: RegionData = regions[province_id]
	if reg.owner_tag != state.country_tag:
		return {"success": false, "message": _tr_str("ECON_PROVINCE_NOT_OWNED", {}, "Регион не контролируется государством.")}

	if state.current_cap < cost_cap:
		return {"success": false, "message": _tr_str("ECON_INSUFFICIENT_CAP", {}, "Недостаточно очков действий кабинета (CAP).")}

	if state.liquid_reserves_billions < cost_money:
		if state.is_in_fiscal_crisis:
			return {"success": false, "message": _tr_str("ECON_FISCAL_CRISIS_BLOCK", {}, "Фискальный кризис: недостаточно средств для геологоразведки.")}
		state.national_debt_billions += cost_money
	else:
		state.liquid_reserves_billions -= cost_money

	state.current_cap -= cost_cap
	var current_dep = int(reg.resource_deposits.get(resource_type, 0))
	var gained := 6
	reg.resource_deposits[resource_type] = current_dep + gained

	return {
		"success": true,
		"new_amount": current_dep + gained,
		"message": _tr_str("ECON_PROSPECT_SUCCESS", {"name": reg.province_name, "resource": resource_type.to_upper(), "amount": gained}, "Геологоразведка завершена: в %s открыты новые пласты (%s +%d)!" % [reg.province_name, resource_type.to_upper(), gained])
	}
