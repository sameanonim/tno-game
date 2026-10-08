class_name CountryState
extends Resource

##
## CountryState: Главная модель геополитического, макроэкономического и военного состояния страны
## Реализует логику TNO / Toolbox Theory в пошаговой парадигме.
##

const CountryStateSerializerScript = preload("res://core/data/country_state_serializer.gd")

# ==============================================================================
# 1. ОСНОВНЫЕ ДАННЫЕ И ЛИДЕРСТВО
# ==============================================================================
@export_group("Identity")
@export var country_tag: String = "KOM"
@export var country_name: String = "West Russian Revolutionary Front"
@export var leader_name: String = "Mikhail Tukhachevsky"
@export var leader_portrait_path: String = "res://icon.svg"
@export var ruling_ideology: String = "Authoritarian Socialism"
@export var sub_ideology: String = ""
@export var leader_title: String = "Глава государства"
## @deprecated: Устаревший ID портрета лидера. Рекомендуется использовать leader_portrait_path.
@export var leader_portrait_id: String = "":
	get:
		return leader_portrait_id if not leader_portrait_id.is_empty() else leader_portrait_path
	set(val):
		leader_portrait_id = val
@export var ruling_party: String = "Authoritarian Socialism"
@export var country_color: Color = Color(0.85, 0.2, 0.2, 1.0)

# ==============================================================================
# 1.1. ДИПЛОМАТИЯ И ГЛОБАЛЬНЫЕ СФЕРЫ ВЛИЯНИЯ
# ==============================================================================
@export_group("Diplomacy & Global Spheres")
## Глобальная фракция / альянс (OFN, EINHEITSPAKT, CO_PROSPERITY_SPHERE, TRIUMVIRATE, SOVEREIGN_RUSSIA, NON_ALIGNED)
@export var faction: String = "NON_ALIGNED"
## @deprecated: Устаревшее наименование альянса. Рекомендуется использовать поле faction.
@export var alliance: String = "Non-Aligned":
	get:
		return alliance if alliance != "Non-Aligned" else faction
	set(val):
		alliance = val
@export var global_sphere: String = "NON_ALIGNED"
## @deprecated: Устаревший числовой код сферы. Рекомендуется использовать строковый global_sphere.
@export var sphere_code: float = 0.05

## Контролируемые и национальные штаты (ID штатов)
@export var controlled_states: Array[int] = []
@export var owned_states: Array[int] = []

# ==============================================================================
# 2. ПОЛИТИЧЕСКИЙ КАПИТАЛ И СТАБИЛЬНОСТЬ
# ==============================================================================

@export_group("Politics & Power")
## Политический капитал (PC) — стратегический ресурс для законов, наград и фракционных сделок
@export var political_capital: float = 100.0
@export var pc_gain_per_turn: float = 5.0

## Очки действий кабинета (CAP) — тактические очки действий министров (тратятся на ход)
@export var max_cap: int = 5
@export var current_cap: int = 5

## Легитимность режима (0..100) — доверие институтам и армии
@export_range(0.0, 100.0, 1.0) var legitimacy: float = 65.0

## Общественное недовольство и радикализация (0..100) — угроза забастовок и бунтов
@export_range(0.0, 100.0, 1.0) var radicalization: float = 30.0

## Лояльность ключевых фракций (Военные, Бюрократия, Олигархи/Хозяйственники, Партизаны)
@export var factions_loyalty: Dictionary = {
	"military": 75.0,
	"bureaucracy": 60.0,
	"proletariat": 70.0,
	"regional_elites": 45.0
}

## Состав парламента / Верховного Совета / Рейхстага (Количество мест)
@export var parliament_seats: Dictionary = {
	"hardliners": 140,
	"reformists": 80,
	"moderates": 60,
	"militarists": 120
}
@export var total_parliament_seats: int = 400

## Политические партии и электоральный баланс
@export var initial_parties: Array[PartyData] = []

## Лидеры и состав кабинета министров
@export var head_of_state: LeaderResource
@export var cabinet_members: Array[LeaderResource] = []
@export var military_commanders: Array[LeaderResource] = []

## Национальные духи и идеи (National Spirits / Ideas)
@export var national_spirits: Array[Dictionary] = []

## Матрица законов и структуры общества (Societal Laws & Development)
@export var societal_laws: Array[Dictionary] = []

# ==============================================================================
# 3. МАКРОЭКОНОМИКА (TOOLBOX THEORY)
# ==============================================================================
@export_group("Macroeconomics (Toolbox)")
## ВВП в миллиардах долларов / рублей
@export var gdp_billions: float = 18.5

## Реальный годовой рост ВВП (0.05 = +5.0% / год)
@export var real_gdp_growth: float = 0.045
## @deprecated: Устаревший процентный аксессор. Используйте каноническое поле real_gdp_growth.
var gdp_growth_rate: float:
	get:
		return real_gdp_growth * 100.0
	set(val):
		real_gdp_growth = val / 100.0 if val > 1.0 else val

## Ликвидные валютные резервы казны ($ млрд)
@export var liquid_reserves_billions: float = 1.2

## Совокупный государственный долг ($ млрд)
@export var national_debt_billions: float = 3.5

## Лимит государственного долга (% от ВВП, 1.0 = 100%)
@export var debt_ceiling_ratio: float = 1.0

## Статус фискального кризиса (дефолта)
@export var is_in_fiscal_crisis: bool = false
## @deprecated: Устаревший псевдоним. Используйте каноническое поле is_in_fiscal_crisis.
var fiscal_crisis_active: bool:
	get:
		return is_in_fiscal_crisis
	set(val):
		is_in_fiscal_crisis = val

## Множитель эффективности фабрик и заводов
@export var factory_output_multiplier: float = 1.0

## Ключевая ставка Центрального Банка (0.06 = 6.0%)
@export var central_bank_rate: float = 0.065

## Текущий уровень инфляции в годовом исчислении (0.04 = 4.0%)
@export var inflation_rate: float = 0.05

## Базовая эффективная налоговая ставка (0.15 = 15%)
@export_range(0.05, 0.60, 0.01) var tax_rate: float = 0.22

## Доля расходов на военный сектор от общих госрасходов (0.40 = 40%)
@export_range(0.05, 0.85, 0.01) var military_spending_share: float = 0.45

## Доля расходов на социальный сектор и медицину (0.25 = 25%)
@export_range(0.05, 0.60, 0.01) var civilian_spending_share: float = 0.30

## Доля расходов на госаппарат и правопорядок (0.20 = 20%)
@export_range(0.05, 0.40, 0.01) var admin_spending_share: float = 0.25

## Доля расходов на НИОКР и науку (0.10 = 10%)
@export_range(0.0, 0.40, 0.01) var rd_spending_share: float = 0.10

## Эмиссия («Печатный станок») за текущий ход ($ млрд)
@export var money_printing_this_turn: float = 0.0

# ==============================================================================
# 3.1. СТРАТЕГИЧЕСКИЕ РЕСУРСЫ И ТОРГОВЛЯ
# ==============================================================================
@export_group("Strategic Resources")
## Добываемые ресурсы за ход (агрегируются по контролируемым провинциям)
@export var produced_resources: Dictionary = {
	"oil": 0,
	"steel": 0,
	"rubber": 0,
	"rare_alloys": 0
}

## Потребляемые ресурсы за ход (армия, фабрики, ВПК)
@export var consumed_resources: Dictionary = {
	"oil": 0,
	"steel": 0,
	"rubber": 0,
	"rare_alloys": 0
}

## Чистый баланс ресурсов (+ излишек на экспорт / - дефицит)
@export var net_resources: Dictionary = {
	"oil": 0,
	"steel": 0,
	"rubber": 0,
	"rare_alloys": 0
}

## Доход/расход от международной торговли сырьем ($ млрд за ход)
@export var resource_trade_balance: float = 0.0

# ==============================================================================
# ==============================================================================
# 3.2. МАТРИЦА СОЦИАЛЬНОГО РАЗВИТИЯ (SOCIETAL DEVELOPMENT)
# ==============================================================================
@export_group("Societal Development")
## 6 институциональных шкал долгосрочного развития общества (0..100)
@export var societal_development: Dictionary = {}

## Активные институциональные законы державы (LawResource)
@export var active_laws: Dictionary = {}

## Общая численность населения государства (человек)
@export var total_population: int = 15000000

## Уровень бедности населения (0..100%, снижает налоги, повышает радикализм)
@export_range(0.0, 100.0, 0.5) var poverty_rate: float = 45.0

## Уровень грамотности населения (0..100%, бустит рост ВВП и НИОКР)
@export_range(0.0, 100.0, 0.5) var literacy_rate: float = 60.0

## Уровень коррупции в госаппарате (0..100%, утечки бюджета)
@export_range(0.0, 100.0, 0.5) var corruption_rate: float = 35.0

## Оснащенность промышленности современным оборудованием (0..100%, продуктивность фабрик)
@export_range(0.0, 100.0, 0.5) var industrial_equipment_level: float = 40.0

## Режим жесткой экономии (Austerity)
@export var is_austerity_active: bool = false

# ==============================================================================
# 4. ПРОИЗВОДСТВЕННЫЙ ПОТЕНЦИАЛ (IC) И СКЛАДЫ
# ==============================================================================
@export_group("Industry & Stockpiles")
## Количество гражданских фабрик (ТНП, строительство, поддержка уровня жизни)
@export var civilian_factories: int = 15

## Количество военных заводов (ВПК, выпуск снаряжения)
@export var military_factories: int = 22

## Доля гражданских фабрик, выделенных под сектор ТНП для сдерживания недовольства (0.0..1.0)
@export_range(0.10, 0.90, 0.05) var consumer_goods_ratio: float = 0.35

## Мобилизационный резерв (людские ресурсы)
@export var manpower_pool: int = 85000

## Склады пехотного вооружения (винтовки, автоматы)
@export var infantry_weapons_stockpile: int = 34000

## Склады тяжелого вооружения и техники (артиллерия, броневики, танки)
@export var heavy_equipment_stockpile: int = 1200

## Боеготовность и выучка армии (0..100)
@export_range(0.0, 100.0, 1.0) var army_readiness: float = 80.0

## Моральный дух вооруженных сил (0..100)
@export_range(0.0, 100.0, 1.0) var army_morale: float = 75.0

## Поддержка войны в обществе (0..100)
@export_range(0.0, 100.0, 1.0) var war_support_percent: float = 65.0

# ==============================================================================
# 4.1. ШПИОНАЖ, РАЗВЕДКА И КОНТРРАЗВЕДКА (ESPIONAGE & COVERT OPS)
# ==============================================================================
@export_group("Espionage & Covert Ops")
## Черный бюджет ($ млн) — обособленный тайный фонд разведывательных служб
@export var black_budget: float = 50.0

## Ежеходный скрытый транш из открытого бюджета / теневых схем ($ млн за ход)
@export var black_budget_allocation_per_turn: float = 5.0

## Уровень контрразведки и внутренней безопасности (0.0..100.0)
@export_range(0.0, 100.0, 1.0) var domestic_security: float = 50.0

## Действующие агенты внешней и внутренней разведки
@export var active_agents: Array[AgentResource] = []

## Активные тайные спецоперации
@export var active_covert_operations: Array[CovertOperationResource] = []

## Матрица проникновения агентурных сетей (Infiltration Networks)
## Key: target_tag (String) -> Value: { "level": float, "network_status": String, "agents_count": int }
@export var infiltration_networks: Dictionary = {}

# ==============================================================================
# 5. НАРРАТИВ, ДИРЕКТИВЫ И ФЛАГИ
# ==============================================================================
@export_group("Directives & Narrative Flags")
## Активные национальные проекты / директивы
@export var active_directives: Array = []

## Завершенные национальные директивы
@export var completed_directives: Array = []

## Проверяет, была ли директива завершена (в текущей партии или исторически до 1962 года)
func is_directive_completed(dir_id: String) -> bool:
	if completed_directives.has(dir_id):
		return true
	var hist = story_flags.get("completed_historical_focuses", [])
	if hist is Array and hist.has(dir_id):
		return true
	var arch = story_flags.get("completed_directives_archive", [])
	if arch is Array and arch.has(dir_id):
		return true
	return false

## Флаг аннексии/капитуляции государства
@export var is_annexed: bool = false

## Сюжетные флаги состояния мира
@export var turn_count: int = 1
@export var story_flags: Dictionary = {
	"turn_count": 1,
	"smuta_phase": 1,
	"border_raids_unlocked": true,
	"germany_civil_war_status": "standby",
	"defcon_level": 5
}

# ==============================================================================
# 5.5. НАУЧНО-ТЕХНИЧЕСКИЙ ПРОГРЕСС (НИОКР / R&D)
# ==============================================================================
@export_group("Research & Development")
## Список ID завершенных исследований
@export var researched_techs: Array = []

## Активные научно-исследовательские проекты (Key: tech_id -> Value: {"progress": float, "cost": float, "slot": int})
@export var active_researches: Dictionary = {}

## Базовое число доступных слотов НИОКР
## @deprecated: Для получения итогового количества слотов с учётом всех модификаторов используйте метод get_total_research_slots().
@export var research_slots_count: int = 3

## @deprecated: Аксессор совместимости. Рекомендуется использовать get_total_research_slots().
var research_slots: int:
	get:
		return get_total_research_slots()
	set(val):
		research_slots_count = val

## Накопленный резерв очков науки
@export var research_points_pool: float = 0.0

## Выработка очков НИОКР за ход (рассчитывается от бюджета НИОКР, грамотности и оснащенности)
@export var research_points_per_turn: float = 15.0

# ==============================================================================
# ВЫЧИСЛЯЕМЫЕ СВОЙСТВА И МЕТОДЫ
# ==============================================================================

## Индекс чистой стабильности государства [-1.0 .. +1.0]
func get_stability_index() -> float:
	var raw = (legitimacy - radicalization) / 100.0
	return clampf(raw, -1.0, 1.0)


## Псевдоним стабильности для прямого чтения и записи
var stability: float:
	get:
		return get_stability_index()
	set(val):
		var normalized_stab = val if (val <= 1.0 and val >= -1.0) else (val / 100.0)
		legitimacy = clampf(50.0 + (normalized_stab * 50.0), 0.0, 100.0)
		radicalization = clampf(50.0 - (normalized_stab * 50.0), 0.0, 100.0)


## Отношение госдолга к ВВП (Debt-to-GDP ratio)
func get_debt_to_gdp_ratio() -> float:
	if gdp_billions <= 0.001:
		return 0.0
	return national_debt_billions / gdp_billions


## Номинальный лимит госдолга (Debt Ceiling)
func get_debt_ceiling() -> float:
	return gdp_billions * debt_ceiling_ratio


## Дискретный кредитный индекс TNO (1..14): 14=AAA, 13=AA+, 12=AA, 11=AA-, 10=A+, 9=A, 8=A-, 7=BBB+, 6=BBB, 5=BBB-, 4=BB, 3=B, 2=CCC, 1=D
@export_range(1, 14, 1) var credit_rating_index: int = 10
@export var credit_rating_min: int = 1
@export var credit_rating_max: int = 14

## Кредитный рейтинг страны (AAA, AA, A, BBB, BB, B, CCC, D) либо статус казны варлорда
func get_credit_rating() -> String:
	var eco_type = EconomyEngine.get_economy_type(self as Variant)
	if eco_type == EconomyEngine.EconomyType.WARLORD:
		if liquid_reserves_billions >= 0.2:
			return "КАЗНА: СТАБИЛЬНА"
		elif liquid_reserves_billions > 0.0:
			return "КАЗНА: ИСТОЩЕНИЕ"
		else:
			return "ДЕФИЦИТ // УГРОЗА БУНТА"

	match credit_rating_index:
		14: return "AAA"
		13: return "AA+"
		12: return "AA"
		11: return "AA-"
		10: return "A+"
		9: return "A"
		8: return "A-"
		7: return "BBB+"
		6: return "BBB"
		5: return "BBB-"
		4: return "BB"
		3: return "B"
		2: return "CCC"
		_: return "D (Default Risk)"



## Псевдоним ключевой ставки для совместимости
var central_bank_interest_rate: float:
	get:
		return central_bank_rate
	set(val):
		central_bank_rate = val

## Псевдоним ключевой ставки для вызовов из панелей решений
var interest_rate: float:
	get:
		return central_bank_rate
	set(val):
		central_bank_rate = val


## Добавление национального духа (идеи)
func add_national_spirit(spirit_id: String, spirit_name: String = "", icon_path: String = "", desc: String = "") -> void:
	for s in national_spirits:
		if s.get("id", "") == spirit_id:
			return
	national_spirits.append({
		"id": spirit_id,
		"name": spirit_name if not spirit_name.is_empty() else spirit_id,
		"icon": icon_path,
		"desc": desc
	})


## Удаление национального духа (идеи)
func remove_national_spirit(spirit_id: String) -> void:
	var idx := -1
	for i in range(national_spirits.size()):
		if national_spirits[i].get("id", "") == spirit_id:
			idx = i
			break
	if idx >= 0:
		national_spirits.remove_at(idx)


## Проверка наличия национального духа
func has_national_spirit(spirit_id: String) -> bool:
	for s in national_spirits:
		if s.get("id", "") == spirit_id:
			return true
	return false


## Проверка наличия активного закона
func has_active_law(law_id: String) -> bool:
	if active_laws.has(law_id):
		return true
	for val in active_laws.values():
		if val is LawResource and val.law_id == law_id:
			return true
		elif val is Dictionary and (val.get("id", "") == law_id or val.get("law_id", "") == law_id):
			return true
		elif str(val) == law_id:
			return true
	for sl in societal_laws:
		if sl.get("id", "") == law_id or sl.get("law_id", "") == law_id:
			return true
	return has_flag("law_" + law_id) or has_flag(law_id)


## Проверка наличия идеи, национального духа или закона
func has_idea(idea_id: String) -> bool:
	return has_flag("idea_" + idea_id) or has_flag(idea_id) or has_active_law(idea_id) or has_national_spirit(idea_id)


## Совокупные доходы бюджета за ход ($ млрд)
func calculate_total_revenue() -> float:
	return EconomyEngine.calculate_turn_revenue(self as Variant)


## Совокупные расходы бюджета за ход ($ млрд)
func calculate_total_expenses() -> float:
	var exp_dict = EconomyEngine.calculate_turn_expenses(self as Variant)
	return float(exp_dict.get("total", 0.0))


## Проверка сюжетного флага
func has_flag(flag_name: String) -> bool:
	if flag_name == "turn_count":
		return true
	return story_flags.has(flag_name) and bool(story_flags[flag_name])


## Чтение сюжетного флага с дефолтным значением
func get_flag(flag_name: String, default_value: Variant = null) -> Variant:
	if flag_name == "turn_count":
		return turn_count if turn_count > 0 else int(story_flags.get("turn_count", 1))
	return story_flags.get(flag_name, default_value)


## Псевдонимы для совместимости с Clausewitz / HoI4
func has_country_flag(flag_name: String) -> bool:
	return has_flag(flag_name)


func has_global_flag(flag_name: String) -> bool:
	return has_flag(flag_name)


## Установка сюжетного флага
func set_flag(flag_name: String, value: Variant = true) -> void:
	story_flags[flag_name] = value
	if flag_name == "turn_count":
		turn_count = int(value)


func set_country_flag(flag_name: String, value: Variant = true) -> void:
	set_flag(flag_name, value)


## Работа с кастомными переменными (check_variable, set_variable)
func set_custom_variable(var_name: String, value: float) -> void:
	story_flags["var_" + var_name] = value


func get_custom_variable(var_name: String, default_value: float = 0.0) -> float:
	if story_flags.has("var_" + var_name):
		return float(story_flags["var_" + var_name])
	if story_flags.has(var_name):
		return float(story_flags[var_name])
	return default_value


# ==============================================================================
# МЕТОДЫ РАБОТЫ С НИОКР И ТЕХНОЛОГИЯМИ
# ==============================================================================

## Проверка, изучена ли технология
func is_tech_researched(tech_id: String) -> bool:
	return researched_techs.has(tech_id)


## Возвращает общее количество доступных слотов исследований с учетом развития державы
func get_total_research_slots() -> int:
	var slots = research_slots_count
	var tag = country_tag.to_upper().strip_edges()
	if tag in ["USA", "GER", "JAP"]:
		slots = maxi(slots, 4)
	elif tag in ["RUS", "SOV", "WRS", "KOM", "OMS", "SAM", "NOV", "SVR"]:
		slots = maxi(slots, 3)

	if literacy_rate >= 80.0 and industrial_equipment_level >= 70.0:
		slots += 1
	return clampi(slots, 1, 6)


## Проверка, есть ли свободный слот для запуска исследований
func has_available_research_slot() -> bool:
	return active_researches.size() < get_total_research_slots()


## Применение постоянных модификаторов от изученной технологии
func apply_tech_modifiers(modifiers: Dictionary) -> void:
	if modifiers.has("modify_gdp"):
		gdp_billions = maxf(gdp_billions + float(modifiers["modify_gdp"]), 0.1)
	if modifiers.has("production_efficiency_gain"):
		civilian_factories = maxi(civilian_factories + 1, civilian_factories)
		factory_output_multiplier += float(modifiers["production_efficiency_gain"])
	if modifiers.has("factory_output_multiplier"):
		factory_output_multiplier += float(modifiers["factory_output_multiplier"])
	if modifiers.has("heavy_equipment_output"):
		heavy_equipment_stockpile += 100
	if modifiers.has("army_readiness"):
		army_readiness = clampf(army_readiness + float(modifiers["army_readiness"]), 0.0, 100.0)
	if modifiers.has("army_morale"):
		army_morale = clampf(army_morale + float(modifiers["army_morale"]), 0.0, 100.0)
	if modifiers.has("war_support_percent"):
		war_support_percent = clampf(war_support_percent + float(modifiers["war_support_percent"]), 0.0, 100.0)
	if modifiers.has("infantry_weapons_production_mult"):
		infantry_weapons_stockpile += 2000
	if modifiers.has("research_speed_bonus"):
		research_points_per_turn *= (1.0 + float(modifiers["research_speed_bonus"]))
	if modifiers.has("command_cap_max_bonus"):
		max_cap += int(modifiers["command_cap_max_bonus"])
		current_cap = max_cap
	if modifiers.has("nuclear_arsenal_unlock"):
		set_flag("has_nuclear_weapons", true)
	if modifiers.has("defcon_weight"):
		set_flag("nuclear_deterrence_active", true)


## Модификация лояльности фракции с защитой диапазона [0..100]
func modify_faction_loyalty(faction_key: String, delta: float) -> void:
	var current = factions_loyalty.get(faction_key, 50.0)
	factions_loyalty[faction_key] = clampf(current + delta, 0.0, 100.0)


## Изменение популярности партии с пропорциональным изъятием у остальных (до 100%)
func modify_party_popularity(ideology_key: String, delta: float) -> void:
	if initial_parties.is_empty():
		return
		
	var target_party: PartyData = null
	var total_other_pop := 0.0
	
	for p in initial_parties:
		if p.ideology_key == ideology_key:
			target_party = p
		else:
			total_other_pop += p.popularity
			
	if target_party == null:
		return
		
	var old_pop = target_party.popularity
	var new_pop = clampf(old_pop + delta, 0.0, 100.0)
	var actual_delta = new_pop - old_pop
	
	if absf(actual_delta) < 0.001:
		return
		
	target_party.popularity = new_pop
	
	if total_other_pop > 0.001:
		for p in initial_parties:
			if p != target_party:
				var share = p.popularity / total_other_pop
				p.popularity = clampf(p.popularity - (actual_delta * share), 0.0, 100.0)
	else:
		# Edge case: all other parties are at 0%. We just subtract evenly.
		var ev_sub = actual_delta / (initial_parties.size() - 1)
		for p in initial_parties:
			if p != target_party:
				p.popularity = clampf(p.popularity - ev_sub, 0.0, 100.0)
				
	normalize_parties_popularity()


## Словарь популярности партий {ideology_key: popularity_float}
var parties_popularity: Dictionary:
	get:
		var dict: Dictionary = {}
		for p in initial_parties:
			if p != null and not p.ideology_key.is_empty():
				dict[p.ideology_key] = p.popularity
		return dict


## Получение процента популярности конкретной партии/идеологии
func get_party_popularity(ideology_key: String) -> float:
	var clean = ideology_key.to_lower().strip_edges()
	for p in initial_parties:
		if p != null:
			if p.ideology_key.to_lower() == clean or p.party_name.to_lower() == clean:
				return p.popularity
	return 0.0


## Нормализация массива партий, чтобы сумма была ровно 100.0
func normalize_parties_popularity() -> void:
	if initial_parties.is_empty():
		return
		
	var sum := 0.0
	for p in initial_parties:
		sum += p.popularity
		
	if sum > 0.001:
		for p in initial_parties:
			p.popularity = (p.popularity / sum) * 100.0
	else:
		var ev = 100.0 / initial_parties.size()
		for p in initial_parties:
			p.popularity = ev


## ==============================================================================
## МЕТОДЫ РАБОТЫ С ИНСТИТУЦИОНАЛЬНЫМИ ШКАЛАМИ И НАСЕЛЕНИЕМ
## ==============================================================================

## Возвращает объект институциональной шкалы общества (SocietalMetricResource)
func get_societal_metric(metric_key: String) -> SocietalMetricResource:
	if societal_development.is_empty():
		init_default_societal_development()
	if societal_development.has(metric_key):
		var val = societal_development[metric_key]
		if val is SocietalMetricResource:
			return val
		elif val is Dictionary:
			var res = SocietalMetricResource.from_dict(val)
			societal_development[metric_key] = res
			return res
		elif val is float or val is int:
			var res = SocietalMetricResource.new(metric_key, metric_key.capitalize(), float(val))
			societal_development[metric_key] = res
			return res
	return null


## Возвращает текущее числовое значение шкалы [0.0 .. 100.0]
func get_societal_metric_value(metric_key: String, default_value: float = 25.0) -> float:
	var m = get_societal_metric(metric_key)
	if m != null:
		return m.current_value
	return default_value


## Устанавливает числовое значение институциональной шкалы
func set_societal_metric_value(metric_key: String, val: float) -> void:
	var m = get_societal_metric(metric_key)
	if m != null:
		m.current_value = val
	else:
		var new_m = SocietalMetricResource.new(metric_key, metric_key.capitalize(), val)
		new_m.tier_changed.connect(func(old_tier: int, new_tier: int):
			print("[CountryState:%s] Societal metric '%s' transitioned tier %d -> %d" % [country_tag, metric_key, old_tier, new_tier])
		)
		societal_development[metric_key] = new_m



## Изменяет числовое значение институциональной шкалы на delta
func modify_societal_metric(metric_key: String, delta: float) -> void:
	var cur = get_societal_metric_value(metric_key, 25.0)
	set_societal_metric_value(metric_key, clampf(cur + delta, 0.0, 100.0))


## Инициализирует аутентичный стартовый набор институциональных шкал для державы
func init_default_societal_development() -> void:
	societal_development = SocietalLawsManager.create_default_metrics_for_country(country_tag)


## Возвращает общую численность населения страны (агрегируя регионы или сохраненное значение)
func get_population(regions: Dictionary = {}) -> int:
	if not regions.is_empty():
		var sum_pop := 0
		for reg in regions.values():
			if reg is RegionData and reg.owner_tag == country_tag:
				sum_pop += reg.population
		if sum_pop > 0:
			total_population = sum_pop
			return total_population
	if total_population > 0:
		return total_population

	# Оценочные аутентичные дефолты по тэгу страны на 1962 год
	match country_tag.to_upper():
		"USA": total_population = 185000000
		"GER", "SPE", "BOR", "GOR", "HEY": total_population = 78000000
		"JAP": total_population = 95000000
		"ITA": total_population = 50000000
		"ENG": total_population = 52000000
		"IBE": total_population = 36000000
		"BUR": total_population = 14000000
		_: total_population = 4500000 # Базовый варлорд Русской Смуты
	return total_population


# ==============================================================================
# МЕТОДЫ РАБОТЫ СО ШПИОНАЖЕМ И АГЕНТУРНЫМИ СЕТЯМИ
# ==============================================================================

## Возвращает текущий уровень проникновения сети в целевую страну [0.0..100.0]
func get_infiltration_level(target_tag: String) -> float:
	var clean_tag = target_tag.to_upper().strip_edges()
	if infiltration_networks.has(clean_tag):
		var data = infiltration_networks[clean_tag]
		if data is Dictionary:
			return float(data.get("level", 0.0))
		elif data is float or data is int:
			return float(data)
	return 0.0


## Устанавливает уровень проникновения и статус сети в целевой стране
func set_infiltration_level(target_tag: String, level: float, status: String = "") -> void:
	var clean_tag = target_tag.to_upper().strip_edges()
	var clamped_lvl = clampf(level, 0.0, 100.0)
	var final_status = status
	if final_status.is_empty():
		if clamped_lvl >= 70.0:
			final_status = "DEEP_COVER"
		elif clamped_lvl >= 30.0:
			final_status = "OPERATIONAL"
		elif clamped_lvl > 0.0:
			final_status = "ESTABLISHING"
		else:
			final_status = "DORMANT"
	
	var ag_count := 0
	for ag in active_agents:
		if ag != null and ag.assigned_country_tag == clean_tag:
			ag_count += 1
			
	infiltration_networks[clean_tag] = {
		"level": clamped_lvl,
		"network_status": final_status,
		"agents_count": ag_count
	}


## Изменяет уровень проникновения на delta и возвращает новое значение
func modify_infiltration_level(target_tag: String, delta: float) -> float:
	var current = get_infiltration_level(target_tag)
	var new_lvl = clampf(current + delta, 0.0, 100.0)
	set_infiltration_level(target_tag, new_lvl)
	return new_lvl


## Находит агента по ID
func get_agent_by_id(agent_id: String) -> AgentResource:
	for ag in active_agents:
		if ag != null and ag.id == agent_id:
			return ag
	return null


## Добавляет агента в активный штат
func add_agent(agent: AgentResource) -> void:
	if agent != null and not active_agents.has(agent):
		active_agents.append(agent)


## Удаляет агента по ID
func remove_agent(agent_id: String) -> bool:
	for i in range(active_agents.size()):
		var ag = active_agents[i]
		if ag != null and ag.id == agent_id:
			active_agents.remove_at(i)
			return true
	return false


## Находит активную спецоперацию по ID
func get_operation_by_id(op_id: String) -> CovertOperationResource:
	for op in active_covert_operations:
		if op != null and op.op_id == op_id:
			return op
	return null


## Добавляет операцию в список активных
func add_operation(op: CovertOperationResource) -> void:
	if op != null and not active_covert_operations.has(op):
		active_covert_operations.append(op)


## Удаляет операцию по ID
func remove_operation(op_id: String) -> bool:
	for i in range(active_covert_operations.size()):
		var op = active_covert_operations[i]
		if op != null and op.op_id == op_id:
			active_covert_operations.remove_at(i)
			return true
	return false


## Автоматическое наполнение аутентичными стартовыми законами TNO при их отсутствии
func ensure_default_societal_laws() -> void:
	if not societal_laws.is_empty():
		return
	var tag = country_tag.to_upper().strip_edges()
	if tag in ["GER", "SPE", "BOR", "GOR", "HEY", "BGR", "SGR", "GGR", "HGR"]:
		societal_laws = [
			{"name": "Трудовые отношения", "value": "Подневольный / рабский труд (Sklaverei)", "tier": 1, "max_tier": 5},
			{"name": "Свобода печати", "value": "Тотальная цензура Рейхспрессы", "tier": 1, "max_tier": 5},
			{"name": "Политическая система", "value": "Однопартийная диктатура НСДАП", "tier": 1, "max_tier": 5},
			{"name": "Военная повинность", "value": "Всеобщий призыв Вермахта", "tier": 4, "max_tier": 5},
			{"name": "Права меньшинств", "value": "Нюрнбергское расовое право", "tier": 1, "max_tier": 5},
			{"name": "Медицинское обеспечение", "value": "Расовая селективная медицина", "tier": 2, "max_tier": 5}
		]
	elif tag in ["USA"]:
		societal_laws = [
			{"name": "Трудовое законодательство", "value": "Защищенные профсоюзы (AFL-CIO)", "tier": 4, "max_tier": 5},
			{"name": "Свобода печати", "value": "Свободная пресса (Первая поправка)", "tier": 5, "max_tier": 5},
			{"name": "Политическая система", "value": "Двухпартийная демократия", "tier": 5, "max_tier": 5},
			{"name": "Военная повинность", "value": "Селективная служба / Призыв", "tier": 3, "max_tier": 5},
			{"name": "Гражданские права", "value": "Сегрегация Джима Кроу (в реформе)", "tier": 2, "max_tier": 5},
			{"name": "Медицинское обеспечение", "value": "Страховая частная медицина", "tier": 3, "max_tier": 5}
		]
	elif tag in ["RUS", "SOV", "WRS", "KOM", "SAM", "VYT", "OMS", "IRK", "PRC", "SBA", "TOM", "NOV", "KEM", "ALT", "TYM", "SVR", "ZLT", "ORE", "MGN", "DRL", "BKR", "TAR", "YGR", "VOR", "KAZ", "AKT", "ARL", "KOK", "PAV", "NPL", "KRK", "BRY", "CHT", "AMR", "MAG", "YAK", "KMC", "TYU", "MIR", "KHA", "VLG", "KOS", "ONE", "ONG"]:
		societal_laws = [
			{"name": "Военная мобилизация", "value": "Всеобщая милитаризация фронта", "tier": 4, "max_tier": 5},
			{"name": "Экономическая модель", "value": "Военный социализм / Госплан", "tier": 4, "max_tier": 5},
			{"name": "Трудовые нормы", "value": "Трудовая мобилизация заводов", "tier": 2, "max_tier": 5},
			{"name": "Политический контроль", "value": "Чрезвычайные тройки госбезопасности", "tier": 5, "max_tier": 5},
			{"name": "Свобода печати", "value": "Фронтовая агитация и цензура", "tier": 1, "max_tier": 5},
			{"name": "Торговый режим", "value": "Военный бартер и продразверстка", "tier": 2, "max_tier": 5}
		]
	else:
		societal_laws = [
			{"name": "Трудовые нормы", "value": "Регулируемый рабочий день", "tier": 3, "max_tier": 5},
			{"name": "Свобода печати", "value": "Государственный надзор за печатью", "tier": 3, "max_tier": 5},
			{"name": "Политическая система", "value": "Ограниченная представительная система", "tier": 3, "max_tier": 5},
			{"name": "Военная повинность", "value": "Регулярный призыв", "tier": 3, "max_tier": 5},
			{"name": "Медицинское обеспечение", "value": "Базовые государственные клиники", "tier": 2, "max_tier": 5}
		]



# ==============================================================================
# СЕРИАЛИЗАЦИЯ (JSON / SAVEGAME)
# ==============================================================================

func to_dict() -> Dictionary:
	return CountryStateSerializerScript.to_dict(self)


static func from_dict(data: Dictionary) -> CountryState:
	return CountryStateSerializerScript.from_dict(data)


func save_to_json_file(file_path: String) -> Error:
	return CountryStateSerializerScript.save_to_json_file(self, file_path)


static func load_from_json_file(file_path: String) -> CountryState:
	return CountryStateSerializerScript.load_from_json_file(file_path)
