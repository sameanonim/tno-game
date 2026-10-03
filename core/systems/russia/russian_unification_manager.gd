class_name RussianUnificationManager
extends Node

##
## RussianUnificationManager: Главный контроллер стадий Русской Смуты и Воссоединения России
##
## Реализует:
## 1. Четыре канонические стадии объединения TNO:
##    - Стадия I: Раздробленность (Warlord Era / Smuta 1962-63)
##    - Стадия II: Региональный этап (Regional Unification 1963-65)
##    - Стадия III: Супер-региональный этап (Super-Regional Unification 1966-68)
##    - Стадия IV: Окончательное воссоединение России (Final Unification 1969-72)
##    - Стадия V: Единая Российская Держава (Superpower Status)
## 2. Макро-регионы России (Западная Россия, Западная Сибирь, Центральная Сибирь, Дальний Восток).
## 3. Механику мирных дипломатических переговоров (Peaceful Reunification Summit) на основе
##    идеологической совместимости лидеров и фракций.
## 4. Смену государственных титулов, флагов и деревьев директив при переходе между стадиями.
## 5. Вызов аутентичных Супер-событий TNO (SE_RUSSIAN_REUNIFICATION_*) при объединении.
##

# ==============================================================================
# СИГНАЛЫ
# ==============================================================================
signal stage_changed(new_stage: int, stage_name: String)
signal regional_triumph_achieved(tag: String, macro_region: String, new_title: String)
signal superregional_triumph_achieved(tag: String, super_region: String, new_title: String)
signal final_unification_achieved(tag: String, leader: String, super_event_id: String)
signal diplomatic_summit_resolved(success: bool, player_tag: String, target_tag: String, details: Dictionary)
signal super_event_requested(super_event_id: String)
signal operational_log_entry(text: String)

# Сигналы уникальных механик варлордов (Таборицкий, Язов, Саблин)
signal midnight_clock_advanced(new_minutes: int, formatted_time: String)
signal midnight_struck()
signal great_trial_prepared(readiness_pct: float)
signal sablin_balance_shifted(new_idealism: float)

# ==============================================================================
# ДЕТЕРМИНИРОВАННЫЙ ГЕНЕРАТОР
# ==============================================================================
static func _get_deterministic_factor(seed_val: int, min_val: float, max_val: float) -> float:
	var s: int = (seed_val * 73856093) ^ 1274126177
	s = (s ^ (s >> 13)) * 19349663
	var norm: float = float(s & 0x7FFFFFFF) / float(0x7FFFFFFF)
	return min_val + (norm * (max_val - min_val))


# ==============================================================================
# ПЕРЕЧИСЛЕНИЯ И КОНСТАНТЫ СТАДИЙ
# ==============================================================================
enum SmutaStage {
	STAGE_1_WARLORD = 1,       # Раздробленность: набеги, подготовка к объединению региона
	STAGE_2_REGIONAL = 2,      # Региональная война: покорение своего макро-региона
	STAGE_3_SUPERREGIONAL = 3, # Супер-регионал: слияние Запада/Востока (мирные переговоры или война)
	STAGE_4_FINAL = 4,         # Финальная битва: Восток против Запада
	STAGE_5_UNIFIED = 5        # Россия едина (провозглашение сверхдержавы, супер-событие)
}

const MACRO_WEST_RUSSIA = "west_russia"
const MACRO_WEST_SIBERIA = "west_siberia"
const MACRO_CENTRAL_SIBERIA = "central_siberia"
const MACRO_FAR_EAST = "far_east"

const SUPER_REGION_WEST = "super_west" # Западная Россия + Западная Сибирь (Европейская Россия)
const SUPER_REGION_EAST = "super_east" # Центральная Сибирь + Дальний Восток (Сибирь)

# Карта распределения варлордов по макро-регионам
const WARLORD_REGIONS: Dictionary = {
	# Западная Россия
	"WRS": MACRO_WEST_RUSSIA,
	"KOM": MACRO_WEST_RUSSIA,
	"VYT": MACRO_WEST_RUSSIA,
	"SAM": MACRO_WEST_RUSSIA,
	"GOR": MACRO_WEST_RUSSIA,
	"ONG": MACRO_WEST_RUSSIA,
	"ONE": MACRO_WEST_RUSSIA,
	"GAY": MACRO_WEST_RUSSIA,
	"KOS": MACRO_WEST_RUSSIA,

	# Западная Сибирь
	"TYM": MACRO_WEST_SIBERIA,
	"OMS": MACRO_WEST_SIBERIA,
	"SVR": MACRO_WEST_SIBERIA,
	"ZLT": MACRO_WEST_SIBERIA,
	"URL": MACRO_WEST_SIBERIA,
	"ORE": MACRO_WEST_SIBERIA,
	"MGN": MACRO_WEST_SIBERIA,
	"DRL": MACRO_WEST_SIBERIA,

	# Центральная Сибирь
	"TOM": MACRO_CENTRAL_SIBERIA,
	"NOV": MACRO_CENTRAL_SIBERIA,
	"KEM": MACRO_CENTRAL_SIBERIA,
	"ALT": MACRO_CENTRAL_SIBERIA,
	"KRA": MACRO_CENTRAL_SIBERIA,

	# Дальний Восток
	"IRK": MACRO_FAR_EAST,
	"BRY": MACRO_FAR_EAST,
	"MAG": MACRO_FAR_EAST,
	"CHT": MACRO_FAR_EAST,
	"AMR": MACRO_FAR_EAST,
	"YAK": MACRO_FAR_EAST,
	"KMC": MACRO_FAR_EAST
}

# ==============================================================================
# СОСТОЯНИЕ МОДУЛЯ
# ==============================================================================
@export var current_stage: SmutaStage = SmutaStage.STAGE_1_WARLORD
@export var player_tag: String = "WRS"
var turns_in_current_stage: int = 0

# Уникальные механики ключевых варлордов (Таборицкий, Язов, Саблин)
var warlord_mechanics: WarlordMechanicsManager = null

# Журнал дипломатических переговоров и набегов
var operations_log: Array[String] = []


func _init() -> void:
	warlord_mechanics = WarlordMechanicsManager.new()
	warlord_mechanics.midnight_clock_advanced.connect(func(m, s): midnight_clock_advanced.emit(m, s))
	warlord_mechanics.midnight_struck.connect(func():
		midnight_struck.emit()
		super_event_requested.emit("SE_POST_MIDNIGHT_COLLAPSE")
	)
	warlord_mechanics.great_trial_prepared.connect(func(r): great_trial_prepared.emit(r))
	warlord_mechanics.sablin_balance_shifted.connect(func(i): sablin_balance_shifted.emit(i))


# ==============================================================================
# ПРОВЕРКА ПРИНАДЛЕЖНОСТИ И МАКРО-ГЕОГРАФИЯ
# ==============================================================================

static func is_russian_tag(tag: String) -> bool:
	return WARLORD_REGIONS.has(tag.to_upper())


static func is_warlord(tag: String) -> bool:
	return is_russian_tag(tag)


static func get_macro_region(tag: String) -> String:
	return WARLORD_REGIONS.get(tag.to_upper(), "")


static func get_macro_region_name(region_key: String) -> String:
	match region_key:
		MACRO_WEST_RUSSIA: return "ЗАПАДНАЯ РОССИЯ"
		MACRO_WEST_SIBERIA: return "ЗАПАДНАЯ СИБИРЬ"
		MACRO_CENTRAL_SIBERIA: return "ЦЕНТРАЛЬНАЯ СИБИРЬ"
		MACRO_FAR_EAST: return "ДАЛЬНИЙ ВОСТОК"
		_: return "НЕИЗВЕСТНЫЙ ТЕАТР"


static func get_super_region(macro_region: String) -> String:
	match macro_region:
		MACRO_WEST_RUSSIA, MACRO_WEST_SIBERIA:
			return SUPER_REGION_WEST
		MACRO_CENTRAL_SIBERIA, MACRO_FAR_EAST:
			return SUPER_REGION_EAST
		_:
			return ""


static func get_super_region_name(super_key: String) -> String:
	match super_key:
		SUPER_REGION_WEST: return "ЕВРОПЕЙСКО-УРАЛЬСКАЯ РОССИЯ"
		SUPER_REGION_EAST: return "ВОСТОЧНО-СИБИРСКАЯ РОССИЯ"
		_: return "СУПЕР-РЕГИОН"


static func get_stage_title(stage: SmutaStage) -> String:
	match stage:
		SmutaStage.STAGE_1_WARLORD: return "I. РАЗДРОБЛЕННОСТЬ (ЭРА СМУТЫ)"
		SmutaStage.STAGE_2_REGIONAL: return "II. РЕГИОНАЛЬНЫЙ ЭТАП"
		SmutaStage.STAGE_3_SUPERREGIONAL: return "III. СУПЕР-РЕГИОНАЛЬНЫЙ ЭТАП"
		SmutaStage.STAGE_4_FINAL: return "IV. ОКОНЧАТЕЛЬНОЕ ВОССОЕДИНЕНИЕ"
		SmutaStage.STAGE_5_UNIFIED: return "V. ЕДИНАЯ РОССИЙСКАЯ ДЕРЖАВА"
		_: return "НЕИЗВЕСТНАЯ СТАДИЯ"


# ==============================================================================
# ИДЕОЛОГИЧЕСКАЯ СОВМЕСТИМОСТЬ И МИРНЫЕ ПЕРЕГОВОРЫ
# ==============================================================================

## Категоризация идеологий для дипломатического объединения
static func get_ideology_category(tag: String, country: CountryState) -> String:
	var ideol = country.ruling_ideology.to_lower() if country != null else ""
	var sub = country.sub_ideology.to_lower() if country != null else ""
	var leader = country.leader_name.to_lower() if country != null else ""
	var clean_tag = tag.to_upper()

	# 1. Непримиримые радикалы / фанатики — мирное объединение НЕВОЗМОЖНО
	if clean_tag == "OMS" or leader.contains("yazov") or leader.contains("карбышев"):
		return "FANATICAL_BLACK_LEAGUE"
	if clean_tag == "KOM" and (leader.contains("taboritsky") or leader.contains("таборицкий") or leader.contains("serov") or leader.contains("серов") or leader.contains("gumil") or leader.contains("гумилев")):
		return "FANATICAL_RADICAL"
	if clean_tag == "AMR" or leader.contains("rodzaevsky") or leader.contains("родзаевский"):
		return "FANATICAL_RADICAL"
	if clean_tag == "DRL" or clean_tag == "URL":
		return "FANATICAL_RADICAL"
	if ideol.contains("burgund") or ideol.contains("national_socialism") or ideol.contains("ultranational"):
		return "FANATICAL_RADICAL"

	# 2. Социалисты / Коммунисты
	if ideol.contains("communist") or ideol.contains("socialist") or clean_tag in ["WRS", "TYM", "IRK", "BRY", "PRC"]:
		return "COMMUNIST_SOCIALIST"
	if clean_tag == "KOM" and (leader.contains("bukharin") or leader.contains("бухарина") or leader.contains("suslov") or leader.contains("суслов") or leader.contains("zhdan") or leader.contains("жданов")):
		return "COMMUNIST_SOCIALIST"

	# 3. Демократы и либералы
	if ideol.contains("democratic") or ideol.contains("liberal") or clean_tag in ["TOM", "NOV"]:
		return "DEMOCRATIC_LIBERAL"
	if clean_tag == "KOM" and (leader.contains("voznes") or leader.contains("вознесенский") or leader.contains("stalin") or leader.contains("сталина")):
		return "DEMOCRATIC_LIBERAL"
	if clean_tag == "VYT" and (leader.contains("gul") or leader.contains("гулькевич")):
		return "DEMOCRATIC_LIBERAL"

	# 4. Прагматичные милитаристы / Автократы
	if ideol.contains("authoritarian") or ideol.contains("despot") or clean_tag in ["SVR", "SAM", "CHT", "MAG", "GOR"]:
		return "PRAGMATIC_AUTOCRATIC"

	return "PRAGMATIC_AUTOCRATIC"


## Проверка идеологической совместимости двух варлордов для мирного объединения
static func are_ideologies_compatible(tag1: String, tag2: String, countries: Dictionary) -> bool:
	var c1: CountryState = countries.get(tag1, null)
	var c2: CountryState = countries.get(tag2, null)

	var cat1 = get_ideology_category(tag1, c1)
	var cat2 = get_ideology_category(tag2, c2)

	# Радикалы никогда не идут на мирный компромисс
	if cat1.begins_with("FANATICAL") or cat2.begins_with("FANATICAL"):
		return false

	# Полное совпадение блоков
	if cat1 == cat2:
		return true

	# Допустимые дипломатические союзы (Демократы + Прагматичные автократы)
	if (cat1 == "DEMOCRATIC_LIBERAL" and cat2 == "PRAGMATIC_AUTOCRATIC") or (cat1 == "PRAGMATIC_AUTOCRATIC" and cat2 == "DEMOCRATIC_LIBERAL"):
		return true

	return false


# ==============================================================================
# ПЕРЕХОДЫ МЕЖДУ СТАДИЯМИ И ПРОВЕРКА УСЛОВИЙ
# ==============================================================================

## Проверка готовности к переходу из Стадии I в Стадию II (Региональная война)
func can_advance_to_regional(country: CountryState) -> bool:
	if current_stage != SmutaStage.STAGE_1_WARLORD:
		return false
	# Требуется минимальная готовность армии и запас оружия
	if country == null:
		return false
	return (country.infantry_weapons_stockpile >= 800 and country.army_readiness >= 45.0) or turns_in_current_stage >= 6


## Перевод на Стадию II: Региональная война
func advance_to_regional(country: CountryState = null, turn_mgr: TurnManager = null) -> bool:
	if current_stage != SmutaStage.STAGE_1_WARLORD:
		return false
	current_stage = SmutaStage.STAGE_2_REGIONAL
	turns_in_current_stage = 0
	var name_stage = get_stage_title(current_stage)
	_log("ПРОРЕВЕЛИ ГОРНЫ: Эпоха раздробленности завершена. Началась Региональная кампания за объединение театра!")
	stage_changed.emit(int(current_stage), name_stage)
	if turn_mgr != null:
		_switch_directives_tree(turn_mgr, "_regional")
	return true


## Проверка: покорен ли макро-регион (Стадия II -> III)
func check_regional_victory(tag: String, regions_world: Dictionary, countries: Dictionary) -> bool:
	if current_stage != SmutaStage.STAGE_2_REGIONAL:
		return false

	var my_macro = get_macro_region(tag)
	if my_macro.is_empty():
		return false

	# Проверяем всех остальных варлордов этого макро-региона
	for w_tag in WARLORD_REGIONS.keys():
		if w_tag == tag:
			continue
		if WARLORD_REGIONS[w_tag] == my_macro:
			var rival: CountryState = countries.get(w_tag, null)
			var is_ann = bool(rival.get("is_annexed")) if (rival != null and rival.get("is_annexed") != null) else false
			if rival != null and not is_ann:
				# Проверяем, остались ли у соперника подконтрольные регионы
				var owned := 0
				for r in regions_world.values():
					if r is RegionData and r.owner_tag == w_tag:
						owned += 1
				if owned > 0:
					return false
	return true


## Провозглашение регионального объединения (Стадия II -> III)
func proclaim_regional_unification(country: CountryState, turn_manager: TurnManager) -> void:
	if current_stage != SmutaStage.STAGE_2_REGIONAL:
		return

	var my_macro = get_macro_region(player_tag)
	var new_title = get_regional_title(player_tag, country)
	country.country_name = new_title
	country.legitimacy = clampf(country.legitimacy + 20.0, 0.0, 100.0)
	country.manpower_pool += 15000
	country.political_capital += 35.0

	current_stage = SmutaStage.STAGE_3_SUPERREGIONAL
	turns_in_current_stage = 0

	_log("РЕГИОНАЛЬНЫЙ ТРИУМФ! Провозглашено [%s]! Театр [%s] подчинен." % [new_title, get_macro_region_name(my_macro)])
	regional_triumph_achieved.emit(player_tag, my_macro, new_title)
	stage_changed.emit(int(current_stage), get_stage_title(current_stage))

	# Переключение древа директив на региональное
	_switch_directives_tree(turn_manager, "_regional")


## Проверка готовности к супер-региональной победе (Стадия III -> IV)
func check_superregional_victory(tag: String, regions_world: Dictionary, countries: Dictionary) -> bool:
	if current_stage != SmutaStage.STAGE_3_SUPERREGIONAL:
		return false

	var my_macro = get_macro_region(tag)
	var my_super = get_super_region(my_macro)

	# В нашем супер-регионе не должно остаться независимых варлордов
	for w_tag in WARLORD_REGIONS.keys():
		if w_tag == tag:
			continue
		var rival_macro = get_macro_region(w_tag)
		if get_super_region(rival_macro) == my_super:
			var rival: CountryState = countries.get(w_tag, null)
			var is_ann = bool(rival.get("is_annexed")) if (rival != null and rival.get("is_annexed") != null) else false
			if rival != null and not is_ann:
				var owned := 0
				for r in regions_world.values():
					if r is RegionData and r.owner_tag == w_tag:
						owned += 1
				if owned > 0:
					return false
	return true


## Провозглашение супер-регионального объединения (Стадия III -> IV)
func proclaim_superregional_unification(country: CountryState, turn_manager: TurnManager) -> void:
	if current_stage != SmutaStage.STAGE_3_SUPERREGIONAL:
		return

	var my_macro = get_macro_region(player_tag)
	var my_super = get_super_region(my_macro)
	var new_title = get_superregional_title(player_tag, country)
	country.country_name = new_title
	country.legitimacy = clampf(country.legitimacy + 25.0, 0.0, 100.0)
	country.manpower_pool += 30000
	country.liquid_reserves_billions += 0.50

	current_stage = SmutaStage.STAGE_4_FINAL
	turns_in_current_stage = 0

	_log("СУПЕР-РЕГИОНАЛЬНЫЙ ТРИУМФ! Провозглашено [%s]! [%s] под единым знаменем." % [new_title, get_super_region_name(my_super)])
	superregional_triumph_achieved.emit(player_tag, my_super, new_title)
	stage_changed.emit(int(current_stage), get_stage_title(current_stage))

	# Переключение древа директив на супер-региональное
	_switch_directives_tree(turn_manager, "_superregional")


## Проверка окончательного воссоединения всей России (Стадия IV -> V)
func check_final_unification(tag: String, regions_world: Dictionary, countries: Dictionary) -> bool:
	if current_stage != SmutaStage.STAGE_4_FINAL:
		return false

	# Проверяем, есть ли хотя бы один живой русский варлорд кроме нас
	for w_tag in WARLORD_REGIONS.keys():
		if w_tag == tag:
			continue
		var rival: CountryState = countries.get(w_tag, null)
		var is_ann = bool(rival.get("is_annexed")) if (rival != null and rival.get("is_annexed") != null) else false
		if rival != null and not is_ann:
			var owned := 0
			for r in regions_world.values():
				if r is RegionData and r.owner_tag == w_tag:
					owned += 1
			if owned > 0:
				return false
	return true


## Финальное провозглашение объединения России (запуск TNO Super Event)
func proclaim_final_unification(country: CountryState) -> String:
	current_stage = SmutaStage.STAGE_5_UNIFIED
	var final_title = get_final_all_russian_title(player_tag, country)
	country.country_name = final_title
	country.legitimacy = 100.0
	country.radicalization = 0.0

	var se_id = get_reunification_super_event_id(player_tag, country)
	_log("ВЕЛИКИЙ ТРИУМФ! РОССИЯ ВОССОЕДИНЕНА ПОД НАЧАЛОМ [%s]! СУПЕР-СОБЫТИЕ: %s" % [final_title, se_id])

	final_unification_achieved.emit(player_tag, country.leader_name, se_id)
	super_event_requested.emit(se_id)
	stage_changed.emit(int(current_stage), get_stage_title(current_stage))
	return se_id


# ==============================================================================
# МИРНЫЙ ДИПЛОМАТИЧЕСКИЙ САММИТ (PEACEFUL REUNIFICATION)
# ==============================================================================

## Возможно ли начать переговоры о мирном слиянии
func can_start_diplomatic_summit(target_tag: String, countries: Dictionary) -> bool:
	if current_stage < SmutaStage.STAGE_3_SUPERREGIONAL or current_stage >= SmutaStage.STAGE_5_UNIFIED:
		return false
	if target_tag == player_tag or not is_russian_tag(target_tag):
		return false

	var target: CountryState = countries.get(target_tag, null)
	if target == null or target.is_annexed:
		return false

	return are_ideologies_compatible(player_tag, target_tag, countries)


## Проведение дипломатического саммита
func execute_diplomatic_summit(target_tag: String, turn_manager: TurnManager) -> Dictionary:
	var res = {
		"success": false,
		"target_tag": target_tag,
		"narrative": "",
		"transferred_provinces": 0,
		"annexed": false
	}

	var p_state = turn_manager.player_state
	var t_state: CountryState = turn_manager.countries_world_state.get(target_tag, null)

	if p_state == null or t_state == null:
		res["narrative"] = "Ошибка саммита: данные государств не найдены."
		return res

	if not are_ideologies_compatible(player_tag, target_tag, turn_manager.countries_world_state):
		res["narrative"] = "Дипломатический провал: идеологическая пропасть непреодолима. Переговоры сорваны."
		diplomatic_summit_resolved.emit(false, player_tag, target_tag, res)
		return res

	# Шанс успеха на основе военного превосходства, легитимности и политического капитала
	var p_power = p_state.army_readiness * 0.5 + p_state.legitimacy * 0.5
	var t_power = t_state.army_readiness * 0.5 + t_state.legitimacy * 0.5
	var ratio = p_power / maxf(t_power, 1.0)

	var summit_seed: int = (turn_manager.current_turn * 73856093) ^ (player_tag.hash() * 19349663) ^ target_tag.hash()
	var roll = _get_deterministic_factor(summit_seed, 0.8, 1.2) * ratio
	if roll >= 0.90:
		res["success"] = true
		res["annexed"] = true

		# Передача всех территорий соперника без разрушений
		var transferred := 0
		for pid in turn_manager.regions_world_state.keys():
			var reg: RegionData = turn_manager.regions_world_state[pid]
			if reg != null and reg.owner_tag == target_tag:
				reg.owner_tag = player_tag
				transferred += 1
		res["transferred_provinces"] = transferred

		# Интеграция ресурсов и армии
		p_state.liquid_reserves_billions += t_state.liquid_reserves_billions * 0.85
		p_state.infantry_weapons_stockpile += t_state.infantry_weapons_stockpile
		p_state.manpower_pool += int(t_state.manpower_pool * 0.75) + 15000
		p_state.civilian_factories += t_state.civilian_factories
		p_state.military_factories += t_state.military_factories
		p_state.political_capital = maxf(p_state.political_capital - 30.0, 0.0)

		t_state.is_annexed = true

		res["narrative"] = (
			("ИСТОРИЧЕСКИЙ САММИТ УВЕНЧАЛСЯ УСПЕХОМ!\n" +
			"Делегация [%s] подписала Акт о Национальном Единстве.\n" +
			"Мирно присоединено %d регионов, армия и арсеналы влились в наши ряды без единого выстрела!") %
			[t_state.country_name, transferred]
		)
		_log("МИРНОЕ СЛИЯНИЕ: [%s] вошло в состав нашего государства." % t_state.country_name)
	else:
		res["success"] = false
		p_state.political_capital = maxf(p_state.political_capital - 15.0, 0.0)
		res["narrative"] = (
			"Переговоры зашли в тупик: делегация [%s] отклонила предложенные условия интеграции.\n" +
			"Требуются дополнительные уступки или военное давление." % t_state.country_name
		)
		_log("ДИПЛОМАТИЧЕСКИЙ ТУПИК: Переговоры с [%s] не дали результата." % t_state.country_name)

	diplomatic_summit_resolved.emit(res["success"], player_tag, target_tag, res)
	return res


# ==============================================================================
# ВОЕННЫЙ ЗАХВАТ, РАЗГРАБЛЕНИЕ И СЛИЯНИЕ АРМИЙ ВАРЛОРДОВ
# ==============================================================================

## Военный разгром и поглощение варлорда (Loot & Military Integration)
func execute_warlord_conquest(
	conqueror_tag: String,
	victim_tag: String,
	turn_manager: TurnManager,
	loot_mode: String = "annex_and_integrate"
) -> Dictionary:
	var res: Dictionary = {
		"success": false,
		"conqueror_tag": conqueror_tag,
		"victim_tag": victim_tag,
		"loot_mode": loot_mode,
		"transferred_states": 0,
		"weapons_captured": 0,
		"manpower_integrated": 0,
		"cash_plundered": 0.0,
		"stage_advanced": false
	}

	if turn_manager == null:
		return res

	var c_state: CountryState = turn_manager.countries_world_state.get(conqueror_tag, null)
	var v_state: CountryState = turn_manager.countries_world_state.get(victim_tag, null)
	if c_state == null and turn_manager.player_state != null and turn_manager.player_state.country_tag == conqueror_tag:
		c_state = turn_manager.player_state
	if v_state == null and turn_manager.player_state != null and turn_manager.player_state.country_tag == victim_tag:
		v_state = turn_manager.player_state

	if c_state == null or v_state == null:
		return res

	# 1. Аннексия территорий
	turn_manager.annex_country(victim_tag, conqueror_tag)
	v_state.is_annexed = true
	res["transferred_states"] = v_state.controlled_states.size()

	# 2. Трофеи и слияние армий
	var weapons: int = 0
	var manpower: int = 0
	var cash: float = 0.0

	if loot_mode == "pillage_and_strip":
		# Полное разграбление военных складов и казны
		weapons = v_state.infantry_weapons_stockpile + int(float(v_state.military_factories) * 80)
		cash = v_state.liquid_reserves_billions * 0.90 + 0.15
		manpower = int(float(v_state.manpower_pool) * 0.40)
		c_state.radicalization = clampf(c_state.radicalization + 3.0, 0.0, 100.0)
		c_state.political_capital += 15.0
		_log("РАЗГРАБЛЕНИЕ ВАРЛОРДА: Арсеналы [%s] вывезены подчистую, казна разграблена." % victim_tag)
	else:
		# Интеграция и слияние институтов (annex_and_integrate)
		weapons = int(float(v_state.infantry_weapons_stockpile) * 0.85)
		cash = v_state.liquid_reserves_billions * 0.70
		manpower = int(float(v_state.manpower_pool) * 0.70) + 8000
		c_state.legitimacy = clampf(c_state.legitimacy + 8.0, 0.0, 100.0)
		c_state.civilian_factories += v_state.civilian_factories
		c_state.military_factories += v_state.military_factories
		_log("СЛИЯНИЕ АРМИЙ: Войска [%s] присягнули на верность нашему знамени." % victim_tag)

	c_state.infantry_weapons_stockpile += weapons
	c_state.liquid_reserves_billions += cash
	c_state.manpower_pool += manpower

	res["weapons_captured"] = weapons
	res["manpower_integrated"] = manpower
	res["cash_plundered"] = cash
	res["success"] = true

	# 3. Автоматическая проверка эволюции стадий
	if conqueror_tag == player_tag:
		if current_stage == SmutaStage.STAGE_2_REGIONAL and check_regional_victory(player_tag, turn_manager.regions_world_state, turn_manager.countries_world_state):
			proclaim_regional_unification(c_state, turn_manager)
			res["stage_advanced"] = true
		elif current_stage == SmutaStage.STAGE_3_SUPERREGIONAL and check_superregional_victory(player_tag, turn_manager.regions_world_state, turn_manager.countries_world_state):
			proclaim_superregional_unification(c_state, turn_manager)
			res["stage_advanced"] = true
		elif current_stage == SmutaStage.STAGE_4_FINAL and check_final_unification(player_tag, turn_manager.regions_world_state, turn_manager.countries_world_state):
			proclaim_final_unification(c_state)
			res["stage_advanced"] = true

	return res


# ==============================================================================
# ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ТИТУЛОВ И СУПЕР-СОБЫТИЙ
# ==============================================================================

static func get_regional_title(tag: String, country: CountryState) -> String:
	match tag.to_upper():
		"WRS": return "Западнорусская Советская Республика"
		"KOM":
			var l = country.leader_name.to_lower() if country != null else ""
			if l.contains("serov"): return "Русское Национальное Государство"
			if l.contains("tabor"): return "Коми Имперское Правительство"
			if l.contains("gumil"): return "Евразийское Государство"
			if l.contains("bukhar"): return "Коми Социалистическая Республика"
			return "Всероссийское Временное Правительство"
		"VYT": return "Российское Царство (Вятка)"
		"SAM": return "Комитет Освобождения Народов России"
		"TYM": return "Западно-Сибирская Народная Республика"
		"OMS": return "Западно-Сибирское Военное Правительство"
		"SVR": return "Уральская Военная Администрация"
		"TOM": return "Центрально-Сибирская Республика"
		"NOV": return "Сибирская Федерация"
		"KEM": return "Кемеровское Княжество"
		"IRK": return "Президиум Верховного Совета СССР"
		"BRY": return "Бурятская Советская Республика"
		"MAG": return "Магаданская Военная Администрация"
		"CHT": return "Российская Восточная Окраина"
		"AMR": return "Русская Фашистская Партия"
		_: return "%s (Региональное Правительство)" % tag


static func get_superregional_title(tag: String, country: CountryState) -> String:
	match tag.to_upper():
		"WRS": return "Союз Советских Республик России"
		"KOM":
			var l = country.leader_name.to_lower() if country != null else ""
			if l.contains("serov"): return "Ордосоциалистическая Россия"
			if l.contains("tabor"): return "Священная Российская Империя"
			if l.contains("gumil"): return "Евразийская Федерация"
			return "Российская Федеративная Республика"
		"VYT": return "Всероссийское Царство"
		"SAM": return "Российское Государство (КОНР)"
		"TYM": return "Российская Советская Республика"
		"OMS": return "Всероссийское Правительство Черной Лиги"
		"SVR": return "Российская Военная Республика"
		"TOM": return "Сибирская Демократическая Федерация"
		"NOV": return "Российская Федерация"
		"KEM": return "Русское Царство Рюриковичей"
		"IRK": return "Союз Советских Социалистических Республик"
		"BRY": return "Советская Федерация Трудящихся"
		_: return "%s (Супер-Региональное Государство)" % tag


static func get_final_all_russian_title(tag: String, country: CountryState) -> String:
	match tag.to_upper():
		"WRS", "TYM", "IRK", "BRY":
			return "Союз Советских Социалистических Республик"
		"KOM":
			var l = country.leader_name.to_lower() if country != null else ""
			if l.contains("serov"): return "Ордосоциалистический Русский Союз"
			if l.contains("tabor"): return "Священная Российская Империя"
			if l.contains("gumil"): return "Евразийский Союз"
			return "Российская Федерация"
		"VYT": return "Российская Империя"
		"OMS": return "Русское Национальное Государство"
		"SVR", "NOV", "TOM": return "Российская Федерация"
		"KEM": return "Российская Империя Рюрика"
		"AMR": return "Российское Национальное Государство"
		_: return "Единая и Неделимая Россия"


## Точный маппинг на аутентичный ID TNO Супер-события
static func get_reunification_super_event_id(tag: String, country: CountryState) -> String:
	var l = country.leader_name.to_lower() if country != null else ""
	match tag.to_upper():
		"WRS":
			if l.contains("tukh") or l.contains("тухач"):
				return "SE_RUSSIAN_REUNIFICATION_WRRF_TUKHA"
			return "SE_RUSSIAN_REUNIFICATION_WRRF_ZHUKOV"
		"KOM":
			if l.contains("serov") or l.contains("серов"): return "SE_RUSSIAN_REUNIFICATION_KOMI_SEROV"
			if l.contains("tabor") or l.contains("табориц"): return "SE_RUSSIAN_REUNIFICATION_KOMI_TABORITSKY"
			if l.contains("bukhar") or l.contains("бухарин"): return "SE_RUSSIAN_REUNIFICATION_KOMI_BUKHARINA"
			if l.contains("gumil") or l.contains("гумилев"): return "SE_RUSSIAN_REUNIFICATION_KOMI_GUMMILYOV"
			if l.contains("shafar") or l.contains("шафаревич"): return "SE_RUSSIAN_REUNIFICATION_KOMI_SHAFAREVICH"
			if l.contains("stalin") or l.contains("сталина"): return "SE_RUSSIAN_REUNIFICATION_KOMI_STALINA"
			if l.contains("suslov") or l.contains("суслов"): return "SE_RUSSIAN_REUNIFICATION_KOMI_SUSLOV"
			if l.contains("zhdan") or l.contains("жданов"): return "SE_RUSSIAN_REUNIFICATION_KOMI_ZHDANOV"
			return "SE_RUSSIAN_REUNIFICATION_KOMI_DEMOCRATIC"
		"OMS": return "SE_RUSSIAN_REUNIFICATION_OMSK"
		"TYM":
			if l.contains("khrush") or l.contains("хрущев"): return "SE_RUSSIAN_REUNIFICATION_TYUMEN_KHRUSHCHEV"
			return "SE_RUSSIAN_REUNIFICATION_TYUMEN_KAGANOVICH"
		"SVR":
			if l.contains("yelts") or l.contains("ельцин"): return "SE_RUSSIAN_REUNIFICATION_SVERDLOVSK_YELTSIN"
			return "SE_RUSSIAN_REUNIFICATION_SVERDLOVSK_BATOV"
		"TOM":
			if l.contains("human") or l.contains("гуманист"): return "SE_RUSSIAN_REUNIFICATION_TOMSK_HUMANIST"
			if l.contains("modern") or l.contains("модернист"): return "SE_RUSSIAN_REUNIFICATION_TOMSK_MODERNISTS"
			if l.contains("bastil") or l.contains("бастильяр"): return "SE_RUSSIAN_REUNIFICATION_TOMSK_BASTILLARDS"
			return "SE_RUSSIAN_REUNIFICATION_TOMSK_DECEMBRISTS"
		"NOV":
			if l.contains("shuksh") or l.contains("шукшин"): return "SE_RUSSIAN_REUNIFICATION_NOVOSIBIRSK_SHUKSHIN"
			return "SE_RUSSIAN_REUNIFICATION_NOVOSIBIRSK_POKRYSHKIN"
		"KEM":
			if l.contains("lydia") or l.contains("лидия"): return "SE_RUSSIAN_REUNIFICATION_KEMEROVO_LYDIA"
			return "SE_RUSSIAN_REUNIFICATION_KEMEROVO_YURIY"
		"IRK": return "SE_RUSSIAN_REUNIFICATION_IRKUTSK_PARTY"
		"BRY": return "SE_RUSSIAN_REUNIFICATION_BURYATIA_LIBSOC"
		"VYT": return "SE_RUSSIAN_REUNIFICATION_VYATKA_CONDEM"
		"SAM": return "SE_RUSSIAN_REUNIFICATION_SAMARA_ZYKOV"
		"MAG": return "SE_RUSSIAN_REUNIFICATION_MAGADAN_MATKOVSKY"
		"AMR": return "SE_RUSSIAN_REUNIFICATION_AMUR"
		"CHT": return "SE_RUSSIAN_REUNIFICATION_CHITA_IMPERIAL"
		_: return "SE_RUSSIAN_REUNIFICATION_WRRF_ZHUKOV"


# ==============================================================================
# ПОШАГОВАЯ ОБРАБОТКА ХОДА
# ==============================================================================

func process_turn(_current_turn: int, country_state: CountryState = null) -> void:
	turns_in_current_stage += 1
	if warlord_mechanics != null and is_russian_tag(player_tag):
		var rep = warlord_mechanics.process_turn(player_tag, country_state)
		if rep.get("collapsed", false):
			_log("ПОЛНОЧЬ НАСТУПИЛА: Священная Российская Империя рухнула!")
			super_event_requested.emit("SE_POST_MIDNIGHT_COLLAPSE")


func _switch_directives_tree(turn_manager: TurnManager, stage_suffix: String) -> void:
	if turn_manager == null:
		return

	var country: CountryState = turn_manager.player_state
	var clean_tag: String = player_tag.to_upper() if not player_tag.is_empty() else (country.country_tag.to_upper() if country != null else "")
	var l_name: String = country.leader_name.to_lower() if country != null else ""
	var ideol: String = country.ruling_ideology.to_lower() if country != null else ""

	# Ключевые маркеры лидеров для сопоставления с именами деревьев
	var leader_tokens: Array[String] = []
	if l_name.contains("tabor") or l_name.contains("табориц"): leader_tokens.append("taboritsky")
	elif l_name.contains("bukhar") or l_name.contains("бухарин"): leader_tokens.append("bukharina")
	elif l_name.contains("suslov") or l_name.contains("суслов"): leader_tokens.append("suslov")
	elif l_name.contains("zhdan") or l_name.contains("жданов"): leader_tokens.append("zhdanov")
	elif l_name.contains("gumil") or l_name.contains("гумилев") or l_name.contains("гумилёв"): leader_tokens.append("gumilyov")
	elif l_name.contains("serov") or l_name.contains("серов"): leader_tokens.append("serov")
	elif l_name.contains("shafar") or l_name.contains("шафаревич"): leader_tokens.append("shafarevich")
	elif l_name.contains("stalin") or l_name.contains("сталин"): leader_tokens.append("stalina")
	elif l_name.contains("moroz") or l_name.contains("морозов"): leader_tokens.append("morozov")
	elif l_name.contains("voznes") or l_name.contains("вознесенск"): leader_tokens.append("voznesensky")
	elif l_name.contains("yazov") or l_name.contains("язов"): leader_tokens.append("yazov")
	elif l_name.contains("zhukov") or l_name.contains("жуков"): leader_tokens.append("zhukov")
	elif l_name.contains("tukhach") or l_name.contains("тухачевск"): leader_tokens.append("tukhachevsky")
	elif l_name.contains("batov") or l_name.contains("батов"): leader_tokens.append("batov")
	elif l_name.contains("yelts") or l_name.contains("ельцин"): leader_tokens.append("yeltsin")
	elif l_name.contains("sablin") or l_name.contains("саблин"): leader_tokens.append("sablin")
	elif l_name.contains("rodzaev") or l_name.contains("родзаевск"): leader_tokens.append("rodzaevsky")
	elif l_name.contains("matkov") or l_name.contains("матковск"): leader_tokens.append("matkovsky")
	elif l_name.contains("pokrysh") or l_name.contains("покрышкин"): leader_tokens.append("pokryshkin")
	elif l_name.contains("shuksh") or l_name.contains("шукшин"): leader_tokens.append("shukshin")

	var candidates: Array[String] = []

	# 1. Из FocusStageController.trees_manifest
	if turn_manager.focus_stage_controller != null:
		for tid in turn_manager.focus_stage_controller.trees_manifest.keys():
			var s_tid = str(tid)
			if s_tid.to_lower().contains(stage_suffix.to_lower()):
				candidates.append(s_tid)

	# 2. Из файловой структуры директории страны
	var dir_paths = [
		"res://data/countries/%s/directives" % clean_tag,
		"res://data/countries/%s/directives/trees" % clean_tag
	]
	for d_path in dir_paths:
		if DirAccess.dir_exists_absolute(d_path):
			var dir = DirAccess.open(d_path)
			if dir != null:
				dir.list_dir_begin()
				var fn = dir.get_next()
				while fn != "":
					if not dir.current_is_dir() and fn.ends_with(".json") and fn.to_lower().contains(stage_suffix.to_lower()):
						var tree_id = fn.trim_suffix(".json")
						if not candidates.has(tree_id):
							candidates.append(tree_id)
					fn = dir.get_next()

	if candidates.is_empty():
		_log("ПРЕДУПРЕЖДЕНИЕ: Дерево директив для стадии [%s] не найдено." % stage_suffix)
		return

	# Скоринг кандидатов
	var best_tree := ""
	var best_score := -100

	for cand in candidates:
		var c_lower = cand.to_lower()
		var score := 0

		# Обязательный фильтр: дерево должно принадлежать тегу игрока
		if not c_lower.contains(clean_tag.to_lower()):
			continue

		# Совпадение суффикса стадии
		if c_lower.contains(stage_suffix.to_lower()):
			score += 10

		# Совпадение лидера
		for token in leader_tokens:
			if c_lower.contains(token):
				score += 50
				break

		# Совпадение идеологии
		if ideol.contains("communist") and (c_lower.contains("communist") or c_lower.contains("socialist") or c_lower.contains("socdem") or c_lower.contains("bukharin") or c_lower.contains("suslov") or c_lower.contains("zhdanov")):
			score += 15
		elif (ideol.contains("fascist") or ideol.contains("national_socialism")) and (c_lower.contains("fascist") or c_lower.contains("serov") or c_lower.contains("gumilyov") or c_lower.contains("shafarevich")):
			score += 15
		elif (ideol.contains("democrat") or ideol.contains("liberal")) and (c_lower.contains("democrat") or c_lower.contains("dsnp") or c_lower.contains("psd") or c_lower.contains("stalina")):
			score += 15
		elif (ideol.contains("despot") or ideol.contains("authoritarian")) and (c_lower.contains("despot") or c_lower.contains("morozov")):
			score += 15
		elif ideol.contains("burgund") and c_lower.contains("taboritsky"):
			score += 25

		if score > best_score:
			best_score = score
			best_tree = cand

	if not best_tree.is_empty() and turn_manager.focus_stage_controller != null:
		turn_manager.focus_stage_controller.switch_focus_tree(best_tree, true)
		_log("РАЗВЕРНУТО НОВОЕ ДРЕВО ДИРЕКТИВ: %s (Оценка соответствия: %d)" % [best_tree, best_score])
	elif candidates.size() > 0 and turn_manager.focus_stage_controller != null:
		var fallback_cand := ""
		for cand in candidates:
			if cand.to_lower().contains(clean_tag.to_lower()):
				fallback_cand = cand
				break
		if fallback_cand.is_empty():
			fallback_cand = candidates[0]
		turn_manager.focus_stage_controller.switch_focus_tree(fallback_cand, true)
		_log("РАЗВЕРНУТО РЕЗЕРВНОЕ ДРЕВО ДИРЕКТИВ: %s" % fallback_cand)


func _log(msg: String) -> void:
	operations_log.append(msg)
	operational_log_entry.emit(msg)
	print("[RussianUnificationManager] %s" % msg)
