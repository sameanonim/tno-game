class_name StrategicResourcesManager
extends RefCounted

##
## StrategicResourcesManager: Модуль стратегических ресурсов и кризисов сырья (TNO Resources)
## ==============================================================================
## Отвечает за:
## 1. Расчет баланса сырья (Нефть, Сталь, Резина, Редкие сплавы) по регионам и стране.
## 2. Расчет потребления заводами, армией и ТНП.
## 3. Оценку торговой выручки (экспорт) и валютных расходов (импорт дефицита).
## 4. Глобальный Нефтяной Кризис (Oil Crisis Stagflation) и множители цен.
## ==============================================================================

static var global_oil_crisis_active: bool = false
static var global_oil_crisis_multiplier: float = 3.5


"""Включение/выключение глобального Нефтяного кризиса TNO.
"""
static func set_oil_crisis(active: bool, price_multiplier: float = 3.5) -> void:
	global_oil_crisis_active = active
	global_oil_crisis_multiplier = price_multiplier
	TNOLogger.info("StrategicResourcesManager", "Global Oil Crisis status set to: %s (Multiplier: x%.1f)" % [str(active), price_multiplier])


"""Проверка, охвачена ли экономика Нефтяным кризисом.
"""
static func is_oil_crisis(state: CountryState = null) -> bool:
	if global_oil_crisis_active:
		return true
	if state != null:
		return state.has_flag("oil_crisis_active") or bool(state.story_flags.get("oil_crisis_active", false))
	return false


"""Интерактивный запуск глобального Нефтяного кризиса 1973 года (SE_OIL_CRISIS).
"""
static func trigger_oil_crisis_event(turn_mgr: Node = null) -> Dictionary:
	set_oil_crisis(true, 3.5)
	var report: Dictionary = {
		"event": "SE_OIL_CRISIS",
		"price_multiplier": 3.5,
		"affected_hegemons": ["USA", "GER", "JAP"]
	}
	if turn_mgr != null and turn_mgr.has_method("trigger_super_event"):
		turn_mgr.call("trigger_super_event", "SE_OIL_CRISIS")
	return report


"""Дипломатическое и экономическое разрешение Нефтяного кризиса.
"""
static func resolve_oil_crisis_event() -> Dictionary:
	set_oil_crisis(false, 1.0)
	return {"event": "OIL_CRISIS_RESOLVED", "price_multiplier": 1.0}


"""Расчет добычи, потребления и торгового сальдо сырья за ход.
"""
static func calculate_resource_balance(state: CountryState, regions: Dictionary = {}) -> Dictionary:
	var cfg: ConfigManager = ConfigManager.get_instance()

	var oil_base_price: float = 0.006
	if is_oil_crisis(state):
		oil_base_price *= global_oil_crisis_multiplier

	var res_prices: Dictionary = {
		"oil": oil_base_price,
		"steel": 0.003,
		"rubber": 0.004,
		"rare_alloys": 0.008
	}
	if cfg != null and cfg.has_constant("economy", "resource_prices"):
		res_prices = cfg.get_dict("economy", "resource_prices")
		if is_oil_crisis(state):
			res_prices["oil"] = float(res_prices.get("oil", 0.006)) * global_oil_crisis_multiplier

	var produced: Dictionary = {
		"oil": 0,
		"steel": 0,
		"rubber": 0,
		"rare_alloys": 0
	}

	# 1. Агрегация добычи по контролируемым провинциям
	var found_regions: bool = false
	if not regions.is_empty():
		for reg: Variant in regions.values():
			if reg is RegionData and reg.owner_tag == state.country_tag:
				found_regions = true
				produced["steel"] += int(reg.resource_deposits.get("steel", 0))
				produced["oil"] += int(reg.resource_deposits.get("oil", 0))
				produced["rubber"] += int(reg.resource_deposits.get("rubber", 0))
				produced["rare_alloys"] += int(reg.resource_deposits.get("rare_alloys", 0))

	# Если регионы не переданы (тесты или изолированный расчет), берем существующие или базовые
	if not found_regions:
		if state.produced_resources.get("steel", 0) > 0 or state.produced_resources.get("oil", 0) > 0:
			produced = state.produced_resources.duplicate(true)
		else:
			produced["steel"] = int(float(state.civilian_factories) * 0.8) + 5
			produced["oil"] = 8
			produced["rubber"] = 2
			produced["rare_alloys"] = int(float(state.military_factories) * 0.3) + 2

	# 2. Расчет потребления сырья
	var oil_per_10k: float = 0.08
	var steel_civ: float = 0.5
	var steel_mil: float = 1.0
	var rubber_cg: float = 0.35
	var alloys_mil: float = 0.4

	if cfg != null and cfg.has_constant("economy", "resource_consumption"):
		var rc: Dictionary = cfg.get_dict("economy", "resource_consumption")
		oil_per_10k = float(rc.get("oil_per_10k_army", oil_per_10k))
		steel_civ = float(rc.get("steel_per_civ_factory", steel_civ))
		steel_mil = float(rc.get("steel_per_mil_factory", steel_mil))
		rubber_cg = float(rc.get("rubber_per_cg_factory", rubber_cg))
		alloys_mil = float(rc.get("alloys_per_mil_factory", alloys_mil))

	var army_units: float = float(state.manpower_pool) / 10000.0
	var heavy_units: float = float(state.heavy_equipment_stockpile) / 400.0
	var cg_factories: float = float(state.civilian_factories) * state.consumer_goods_ratio

	var consumed: Dictionary = {
		"oil": maxi(int(ceil(army_units * oil_per_10k + heavy_units * 0.5)), 1),
		"steel": maxi(int(ceil(float(state.civilian_factories) * steel_civ + float(state.military_factories) * steel_mil)), 2),
		"rubber": maxi(int(ceil(cg_factories * rubber_cg)), 1),
		"rare_alloys": maxi(int(ceil(float(state.military_factories) * alloys_mil)), 1)
	}

	# 3. Чистое сальдо ресурсов и торговая выручка/расход
	var net: Dictionary = {}
	var export_revenue: float = 0.0
	var import_cost: float = 0.0
	var deficits: Array[String] = []

	for res_key: Variant in produced.keys():
		var s_key: String = str(res_key)
		var p_val: int = int(produced.get(s_key, 0))
		var c_val: int = int(consumed.get(s_key, 0))
		var diff: int = p_val - c_val
		net[s_key] = diff

		var price: float = float(res_prices.get(s_key, 0.005))
		if diff > 0:
			export_revenue += float(diff) * price
		elif diff < 0:
			import_cost += float(abs(diff)) * price
			deficits.append(s_key)

	# Сохраняем показатели в CountryState
	state.produced_resources = produced
	state.consumed_resources = consumed
	state.net_resources = net
	state.resource_trade_balance = export_revenue - import_cost

	# Дефицитные штрафы
	var prod_mult: float = 1.0
	if int(net.get("steel", 0)) < 0:
		prod_mult *= 0.75
	if int(net.get("rare_alloys", 0)) < 0:
		prod_mult *= 0.85
	if int(net.get("oil", 0)) < 0:
		var fuel_penalty: float = 2.8 if is_oil_crisis(state) else 1.2
		state.army_readiness = clampf(state.army_readiness - fuel_penalty, 5.0, 100.0)

	return {
		"produced": produced,
		"consumed": consumed,
		"net": net,
		"export_revenue": export_revenue,
		"import_cost": import_cost,
		"deficits": deficits,
		"production_mult": prod_mult
	}
