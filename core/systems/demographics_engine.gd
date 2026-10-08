class_name DemographicsEngine
extends RefCounted

##
## DemographicsEngine: Модуль демографии, естественного движения населения и мобилизации TNO.
## ==============================================================================
## Отвечает за:
## 1. Подсчет национального (core) и ненационального (non-core) населения по регионам.
## 2. Расчет базового еженедельного притока рекрутов (manpower pool).
## 3. Моделирование потерь гарнизонов при высоком уровне регионального недовольства (unrest).
## 4. Корректировку темпов мобилизации в зависимости от легитимности, поддержки войны и милитаризма.
## ==============================================================================

const BASE_RECRUIT_RATE: float = 0.00035
const GARRISON_ATTRITION_FACTOR: float = 0.00008
const UNREST_GARRISON_THRESHOLD: float = 25.0


"""Обрабатывает еженедельный демографический цикл для всех регионов и государств мира.
Возвращает сводный отчет по набору рекрутов и потерям гарнизонов.
"""
static func process_turn(regions_world_state: Dictionary, countries_world_state: Dictionary) -> Dictionary:
	if regions_world_state.is_empty():
		return {}

	var country_core_pop: Dictionary = {}
	var country_non_core_pop: Dictionary = {}
	var country_unrest_sum: Dictionary = {}
	var country_regions_count: Dictionary = {}

	for reg_val in regions_world_state.values():
		if reg_val is RegionData:
			var reg: RegionData = reg_val
			var owner: String = reg.owner_tag.to_upper().strip_edges()
			if owner.is_empty():
				continue
			var pop: int = reg.population
			var is_core: bool = reg.is_core_of(owner) or reg.core_tags.has(owner)

			if is_core:
				country_core_pop[owner] = country_core_pop.get(owner, 0) + pop
			else:
				country_non_core_pop[owner] = country_non_core_pop.get(owner, 0) + pop

			# Пограничные регионы в условиях нестабильности дают меньшую отдачу
			var border_penalty: float = 1.2 if reg.is_border_region else 1.0
			country_unrest_sum[owner] = country_unrest_sum.get(owner, 0.0) + (reg.unrest * border_penalty)
			country_regions_count[owner] = country_regions_count.get(owner, 0) + 1

	var total_global_recruits: int = 0
	var total_global_attrition: int = 0

	for c_tag in countries_world_state.keys():
		var c_st: CountryState = countries_world_state[c_tag]
		if c_st == null:
			continue

		var core_pop: int = country_core_pop.get(c_tag, 0)
		var non_core_pop: int = country_non_core_pop.get(c_tag, 0)
		var reg_count: int = country_regions_count.get(c_tag, 0)
		var avg_unrest: float = (country_unrest_sum.get(c_tag, 0.0) / float(maxi(reg_count, 1))) if reg_count > 0 else 0.0

		c_st.set_flag("core_population", core_pop)
		c_st.set_flag("total_population", core_pop + non_core_pop)
		c_st.set_flag("controlled_regions_count", reg_count)

		if core_pop <= 0 and non_core_pop <= 0:
			continue

		var legitimacy_mult: float = 0.5 + (c_st.legitimacy / 100.0) * 0.7
		var war_support_mult: float = 0.6 + (c_st.war_support_percent / 100.0) * 0.6
		var warlord_mult: float = 1.25 if c_st.has_flag("is_warlord") else 1.0
		var draft_evasion_penalty: float = 1.0 - clampf((c_st.radicalization - 50.0) * 0.008, 0.0, 0.5)

		var turn_recruits: int = int(float(core_pop) * BASE_RECRUIT_RATE * legitimacy_mult * war_support_mult * warlord_mult * draft_evasion_penalty)

		var garrison_casualties: int = 0
		if non_core_pop > 0 and avg_unrest > UNREST_GARRISON_THRESHOLD:
			garrison_casualties = int(float(non_core_pop) * (avg_unrest / 100.0) * GARRISON_ATTRITION_FACTOR)

		var net_manpower_gain: int = turn_recruits - garrison_casualties
		c_st.manpower_pool = maxi(c_st.manpower_pool + net_manpower_gain, 0)
		c_st.set_flag("weekly_manpower_growth", net_manpower_gain)
		c_st.set_flag("garrison_attrition", garrison_casualties)

		total_global_recruits += turn_recruits
		total_global_attrition += garrison_casualties

	return {
		"total_recruits": total_global_recruits,
		"total_attrition": total_global_attrition,
		"countries_processed": country_regions_count.size()
	}
