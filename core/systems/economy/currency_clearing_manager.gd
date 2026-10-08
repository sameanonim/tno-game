class_name CurrencyClearingManager
extends RefCounted

##
## CurrencyClearingManager: Управление валютными зонами, клиринговыми союзами и инфляционным трансфером
## ==============================================================================
## Отвечает за:
## 1. Определение валютной зоны державы (USD, Reichsmark, Yen, Sovereign).
## 2. Расчет курсов валют к доллару США.
## 3. Расчет клиринговых пошлин и валютных издержек внешней торговли.
## 4. Клиринговые союзы и моделирование Spillover Inflation на государства-гегемоны.
## ==============================================================================

enum CurrencyZone {
	USD,         ## OFN / Бреттон-Вудс (Доллар США — глобальная расчетная единица)
	REICHSMARK,  ## Einheitspakt / Zollverein (Рейхсмарка — клиринг Европы)
	YEN,         ## Сфера Сопроцветания (Иена — расчетный блок Азии)
	SOVEREIGN    ## Суверенная автаркия / Неприсоединившиеся (Рубль, Лира и др.)
}


"""Определение валютной зоны державы.
"""
static func get_country_currency_zone(state: CountryState) -> CurrencyZone:
	if state == null:
		return CurrencyZone.SOVEREIGN
	var tag: String = state.country_tag.to_upper().strip_edges()
	var sphere: String = state.global_sphere.to_upper().strip_edges()
	if tag == "USA" or sphere == "OFN":
		return CurrencyZone.USD
	elif tag == "GER" or sphere in ["EINHEITSPAKT", "ZOLLVEREIN", "GERMAN_SPHERE"]:
		return CurrencyZone.REICHSMARK
	elif tag == "JAP" or sphere in ["CO_PROSPERITY", "CO_PROSPERITY_SPHERE", "JAPAN_SPHERE"]:
		return CurrencyZone.YEN
	return CurrencyZone.SOVEREIGN


"""Динамический расчет курсов валют к доллару США ($1.00).
"""
static func calculate_currency_exchange_rates(hegemon_states: Dictionary) -> Dictionary:
	var usa: CountryState = hegemon_states.get("USA", null)
	var ger: CountryState = hegemon_states.get("GER", null)
	var jap: CountryState = hegemon_states.get("JAP", null)

	var usa_growth: float = usa.real_gdp_growth if usa != null else 0.04
	var usa_infl: float = usa.inflation_rate if usa != null else 0.03

	var ger_growth: float = ger.real_gdp_growth if ger != null else 0.035
	var ger_infl: float = ger.inflation_rate if ger != null else 0.045

	var jap_growth: float = jap.real_gdp_growth if jap != null else 0.05
	var jap_infl: float = jap.inflation_rate if jap != null else 0.04

	var rm_base: float = 2.50
	var rm_rate: float = clampf(rm_base * ((1.0 + ger_infl - ger_growth) / maxf(1.0 + usa_infl - usa_growth, 0.5)), 1.20, 5.00)

	var yen_base: float = 360.0
	var yen_rate: float = clampf(yen_base * ((1.0 + jap_infl - jap_growth) / maxf(1.0 + usa_infl - usa_growth, 0.5)), 180.0, 600.0)

	return {
		CurrencyZone.USD: 1.0,
		CurrencyZone.REICHSMARK: rm_rate,
		CurrencyZone.YEN: yen_rate,
		CurrencyZone.SOVEREIGN: 1.0
	}


"""Расчет клиринговых пошлин и валютных издержек внешней торговли.
"""
static func calculate_trade_clearing(
	exporter: CountryState,
	importer: CountryState,
	trade_volume: float
) -> Dictionary:
	var exp_zone: CurrencyZone = get_country_currency_zone(exporter)
	var imp_zone: CurrencyZone = get_country_currency_zone(importer)

	var is_intra_sphere: bool = (exp_zone == imp_zone) and (exp_zone != CurrencyZone.SOVEREIGN)

	if is_intra_sphere:
		var clearing_fee: float = trade_volume * 0.02
		return {
			"is_intra_sphere": true,
			"tariff_rate": 0.0,
			"tariff_revenue": 0.0,
			"clearing_fee": clearing_fee,
			"reserve_drain": 0.0,
			"currency_used": exp_zone
		}
	else:
		var tariff_rate: float = 0.18
		var tariff_total: float = trade_volume * tariff_rate
		var reserve_drain: float = trade_volume * 0.15
		return {
			"is_intra_sphere": false,
			"tariff_rate": tariff_rate,
			"tariff_revenue": tariff_total,
			"clearing_fee": 0.0,
			"reserve_drain": reserve_drain,
			"currency_used": CurrencyZone.USD
		}


"""Расчет клирингового союза и инфляционного трансфера периферии на гегемонов.
"""
static func process_sphere_clearing_and_spillover(countries: Dictionary) -> Dictionary:
	var turns_year: float = EconomyEngine.get_turns_per_year()
	var report: Dictionary = {
		"OFN": {"hegemon": "USA", "satellites": 0, "net_clearing_flow": 0.0, "inflation_spillover": 0.0},
		"EINHEITSPAKT": {"hegemon": "GER", "satellites": 0, "net_clearing_flow": 0.0, "inflation_spillover": 0.0},
		"CO_PROSPERITY_SPHERE": {"hegemon": "JAP", "satellites": 0, "net_clearing_flow": 0.0, "inflation_spillover": 0.0}
	}

	var sphere_to_hegemon: Dictionary = {
		"OFN": "USA",
		"EINHEITSPAKT": "GER",
		"CO_PROSPERITY_SPHERE": "JAP"
	}

	if not countries.has("GER"):
		for gcw_tag: String in ["SPE", "BOR", "GOR", "HEY"]:
			if countries.has(gcw_tag):
				sphere_to_hegemon["EINHEITSPAKT"] = gcw_tag
				report["EINHEITSPAKT"]["hegemon"] = gcw_tag
				break

	for c_tag: String in countries.keys():
		var st: CountryState = countries[c_tag]
		if st == null:
			continue

		var sphere: String = st.global_sphere.to_upper().strip_edges()
		if sphere.is_empty() or sphere == "NON_ALIGNED" or not sphere_to_hegemon.has(sphere):
			continue

		var hegemon_tag: String = sphere_to_hegemon[sphere]
		if c_tag.to_upper() == hegemon_tag:
			continue

		report[sphere]["satellites"] += 1

		if st.is_in_fiscal_crisis or st.inflation_rate > 0.15:
			var debt_burden: float = (st.gdp_billions * 0.015) / turns_year
			var excess_inf: float = maxf(st.inflation_rate - 0.12, 0.0) * 0.04 / turns_year
			report[sphere]["net_clearing_flow"] -= debt_burden
			report[sphere]["inflation_spillover"] += excess_inf
		else:
			var royalty: float = (st.gdp_billions * st.tax_rate * 0.05) / turns_year
			report[sphere]["net_clearing_flow"] += royalty

	for sphere: String in report.keys():
		var hegemon_tag: String = report[sphere]["hegemon"]
		if not countries.has(hegemon_tag):
			continue

		var hegemon_st: CountryState = countries[hegemon_tag]
		if hegemon_st == null:
			continue

		var net_flow: float = float(report[sphere]["net_clearing_flow"])
		var inf_spill: float = float(report[sphere]["inflation_spillover"])

		if net_flow >= 0.0:
			hegemon_st.liquid_reserves_billions += net_flow
		else:
			var drain: float = absf(net_flow)
			if hegemon_st.liquid_reserves_billions >= drain:
				hegemon_st.liquid_reserves_billions -= drain
			else:
				hegemon_st.national_debt_billions += (drain - hegemon_st.liquid_reserves_billions)
				hegemon_st.liquid_reserves_billions = 0.0

		if inf_spill > 0.0:
			hegemon_st.inflation_rate = clampf(hegemon_st.inflation_rate + inf_spill, 0.005, 0.95)

	return report
