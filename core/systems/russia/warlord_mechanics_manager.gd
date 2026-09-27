class_name WarlordMechanicsManager
extends RefCounted

##
## WarlordMechanicsManager: Уникальные механики ключевых варлордов Русской Смуты
##
## Моделирует:
## 1. Сергей Таборицкий (Коми / HRE):
##    - Часы Судного Дня (Midnight Clock: 00:00 -> 24:00).
##    - Поиски Царевича Алексея, Химическое очищение регионов ("Табун"), Имперская верификация.
##    - Наступление Полночи (Midnight Strikes / 24:00): коллапс Священной Российской Империи.
## 2. Дмитрий Язов (Омск / Черная Лига):
##    - Подготовка к Великому Суду (The Great Trial).
##    - Шкала Ненависти к Тевтонам, Сеть бункеров Карбышева, Химический арсенал ("Омск-65").
##    - Военные трибуналы и тотальная мобилизация.
## 3. Валерий Саблин (Бурятия):
##    - Борьба двух путей: Ленинский Идеализм vs Бухаринистский Прагматизм (Realpolitik).
##    - Прямая власть Советов, амнистия политзаключенных, добровольческие дружины Байкала.
##

signal midnight_clock_advanced(new_minutes: int, formatted_time: String)
signal midnight_struck()
signal great_trial_prepared(readiness_pct: float)
signal sablin_balance_shifted(new_idealism: float)
signal mechanic_action_executed(action_id: String, details: Dictionary)

# Идентификаторы поддерживаемых варлордов
const WARLORD_TABORITSKY = "KOM"
const WARLORD_YAZOV = "OMS"
const WARLORD_SABLIN = "BRY"

# ==============================================================================
# СОСТОЯНИЕ: СЕРГЕЙ ТАБОРИЦКИЙ (ЧАСЫ РЕГЕНТА)
# ==============================================================================
## Минуты до полночи: от 0 (12:00) до 720 (24:00 - ПОЛНОЧЬ)
## 720 минут = 12 часов. 1 минута = 1 шаг.
var taboritsky_clock_minutes: int = 240 # 16:00 на старте регентства
var taboritsky_insanity_level: float = 25.0 # 0..100
var taboritsky_cleansed_regions_count: int = 0
var taboritsky_alexei_searches_count: int = 0
var is_midnight_collapsed: bool = false

# ==============================================================================
# СОСТОЯНИЕ: ДМИТРИЙ ЯЗОВ (ВЕЛИКИЙ СУД)
# ==============================================================================
var yazov_teutonic_hatred: float = 65.0 # 0..100%
var yazov_bunker_network_level: int = 1 # 0..5 уровней
var yazov_chemical_stockpile_tons: int = 250 # Тонны боевых ОВ
var yazov_trial_readiness: float = 20.0 # 0..100%
var yazov_is_trial_declared: bool = false

# ==============================================================================
# СОСТОЯНИЕ: ВАЛЕРИЙ САБЛИН (ИДЕАЛИЗМ VS ПРАГМАТИЗМ)
# ==============================================================================
## 100.0 = Чистый Ленинский Идеализм, 0.0 = Жесткий Бухаринистский Прагматизм
var sablin_idealism: float = 68.0 # Стартовый идеализм
var sablin_soviet_democracy: float = 75.0 # 0..100%
var sablin_revolutionary_enthusiasm: float = 80.0 # 0..100%


# ==============================================================================
# ПРОВЕРКА АКТИВНОСТИ МЕХАНИК
# ==============================================================================

## Определяет, какая уникальная механика активна для страны
static func get_active_mechanic_type(tag: String, country_state: CountryState = null) -> String:
	var clean_tag = tag.to_upper()
	var leader = country_state.leader_name.to_lower() if country_state != null else ""
	
	if clean_tag == WARLORD_TABORITSKY and (leader.contains("tabor") or leader.contains("табориц") or country_state == null or country_state.ruling_ideology.contains("Burgund")):
		return "TABORITSKY"
	elif clean_tag == WARLORD_YAZOV or leader.contains("yazov") or leader.contains("язов") or leader.contains("karby") or leader.contains("карбыш"):
		return "YAZOV"
	elif clean_tag == WARLORD_SABLIN or leader.contains("sablin") or leader.contains("саблин"):
		return "SABLIN"
	return "GENERIC_WARLORD"


## Проверяет, является ли тег одним из уникальных варлордов
static func has_unique_mechanic(tag: String, country_state: CountryState = null) -> bool:
	return get_active_mechanic_type(tag, country_state) != "GENERIC_WARLORD"


# ==============================================================================
# МЕХАНИКА 1: СЕРГЕЙ ТАБОРИЦКИЙ (ЧАСЫ РЕГЕНТА / ПОЛНОЧЬ)
# ==============================================================================

## Форматированное время часов (например "23:45" или "24:00 [ПОЛНОЧЬ]")
func get_taboritsky_clock_str() -> String:
	if is_midnight_collapsed or taboritsky_clock_minutes >= 720:
		return "24:00 [ПОЛНОЧЬ]"
	var total_min = 720 + taboritsky_clock_minutes # от 12:00 (720) до 24:00 (1440)
	var hours = int(float(total_min) / 60.0)
	var mins = total_min % 60
	return "%02d:%02d" % [hours, mins]


## Продвижение часов Таборицкого вперед
func advance_taboritsky_clock(added_minutes: int, country_state: CountryState = null) -> Dictionary:
	if is_midnight_collapsed:
		return {"collapsed": true, "message": "Полночь уже наступила. Россия поглощена тьмой."}
	
	taboritsky_clock_minutes = clampi(taboritsky_clock_minutes + added_minutes, 0, 720)
	taboritsky_insanity_level = clampf(taboritsky_insanity_level + float(added_minutes) * 0.15, 0.0, 100.0)
	
	var time_str = get_taboritsky_clock_str()
	midnight_clock_advanced.emit(taboritsky_clock_minutes, time_str)
	
	# Проверка на наступление Полночи (24:00)
	if taboritsky_clock_minutes >= 720:
		return trigger_midnight_collapse(country_state)
		
	return {
		"collapsed": false,
		"new_time": time_str,
		"minutes_added": added_minutes,
		"insanity": taboritsky_insanity_level
	}


## Действие Таборицкого: «Поиски Царевича Алексея»
func taboritsky_action_hunt_alexei(country_state: CountryState) -> Dictionary:
	var pc_cost = 15.0
	var cap_cost = 1
	var money_cost = 0.05
	
	if country_state != null:
		if country_state.political_capital < pc_cost or country_state.current_cap < cap_cost:
			return {"success": false, "reason": "НЕДОСТАТОЧНО PC ИЛИ CAP"}
		country_state.political_capital -= pc_cost
		country_state.current_cap -= cap_cost
		country_state.liquid_reserves_billions = maxf(0.0, country_state.liquid_reserves_billions - money_cost)
		country_state.legitimacy = clampf(country_state.legitimacy + 4.0, 0.0, 100.0)
	
	taboritsky_alexei_searches_count += 1
	# Поиски приближают полуночный кризис (+15 минут)
	var clk = advance_taboritsky_clock(15, country_state)
	
	var res = {
		"success": true,
		"action": "HUNT_ALEXEI",
		"search_num": taboritsky_alexei_searches_count,
		"time": get_taboritsky_clock_str(),
		"collapsed": clk.get("collapsed", false),
		"narrative": "Имперские эмиссары прочесали уральские шахты и скиты. Слухи о спасении Царевича укрепляют веру Регента, но стрелка часов неумолимо движется вперед."
	}
	mechanic_action_executed.emit("HUNT_ALEXEI", res)
	return res


## Действие Таборицкого: «Химическая дезинфекция региона» (Табун)
func taboritsky_action_purification(country_state: CountryState) -> Dictionary:
	var weapons_cost = 250
	var pc_cost = 20.0
	
	if country_state != null:
		if country_state.infantry_weapons_stockpile < weapons_cost or country_state.political_capital < pc_cost:
			return {"success": false, "reason": "НЕДОСТАТОЧНО ОРУЖИЯ ИЛИ PC"}
		country_state.infantry_weapons_stockpile -= weapons_cost
		country_state.political_capital -= pc_cost
		# Жестокое уничтожение радикалов и недовольных ценой демографии
		country_state.radicalization = maxf(0.0, country_state.radicalization - 18.0)
		country_state.manpower_pool = maxi(0, country_state.manpower_pool - 8000)
		country_state.poverty_rate = clampf(country_state.poverty_rate + 3.0, 0.0, 100.0)
	
	taboritsky_cleansed_regions_count += 1
	# Очищение отнимает последние крупицы рассудка (+25 минут)
	var clk = advance_taboritsky_clock(25, country_state)
	
	var res = {
		"success": true,
		"action": "CHEMICAL_PURIFICATION",
		"cleansed_total": taboritsky_cleansed_regions_count,
		"time": get_taboritsky_clock_str(),
		"collapsed": clk.get("collapsed", false),
		"narrative": "Эскадрильи с распылителями ядовитого реагента «Табун» накрыли мятежные деревни. Враги Господни очищены. В воздухе стоит запах смерти, а тиканье часов отдается гулом в висках."
	}
	mechanic_action_executed.emit("CHEMICAL_PURIFICATION", res)
	return res


## Действие Таборицкого: «Имперская верификация верности»
func taboritsky_action_verify(country_state: CountryState) -> Dictionary:
	var pc_cost = 25.0
	var cap_cost = 2
	
	if country_state != null:
		if country_state.political_capital < pc_cost or country_state.current_cap < cap_cost:
			return {"success": false, "reason": "НЕДОСТАТОЧНО PC ИЛИ CAP"}
		country_state.political_capital -= pc_cost
		country_state.current_cap -= cap_cost
		country_state.legitimacy = clampf(country_state.legitimacy + 8.0, 0.0, 100.0)
		country_state.army_readiness = clampf(country_state.army_readiness + 6.0, 0.0, 100.0)
	
	var clk = advance_taboritsky_clock(10, country_state)
	
	var res = {
		"success": true,
		"action": "IMPERIAL_VERIFICATION",
		"time": get_taboritsky_clock_str(),
		"collapsed": clk.get("collapsed", false),
		"narrative": "Чрезвычайные тройки Регента провели допросы командного состава. Отклонения от догмата пресечены на корню. Государство замерло в ожидании Государя."
	}
	mechanic_action_executed.emit("IMPERIAL_VERIFICATION", res)
	return res


## Наступление Полночи: катастрофический распад Священной Российской Империи
func trigger_midnight_collapse(country_state: CountryState) -> Dictionary:
	is_midnight_collapsed = true
	taboritsky_clock_minutes = 720
	
	if country_state != null:
		country_state.country_name = "Земля Немого Отчаяния (Пост-Полночь)"
		country_state.leader_name = "Осталась только тьма..."
		country_state.leader_portrait_path = "res://assets/gfx/leaders/KOM/KOM_Sergey_Taboritsky.png"
		country_state.ruling_ideology = "Post-Midnight Anarchy"
		country_state.legitimacy = 0.0
		country_state.radicalization = 100.0
		country_state.set_flag("midnight_struck", true)
		country_state.set_flag("post_midnight_collapse", true)
	
	midnight_struck.emit()
	
	return {
		"collapsed": true,
		"event_id": "SE_POST_MIDNIGHT_COLLAPSE",
		"title": "ОСТАЛАСЬ ТОЛЬКО ПОЛНОЧЬ",
		"message": "Часы пробили двенадцать. Регент упал замертво у пустого трона. Царевич Алексей так и не вернулся, ибо был мертв уже полвека. Священная Российская Империя рассыпалась в прах и ядовитый пепел."
	}


# ==============================================================================
# МЕХАНИКА 2: ДМИТРИЙ ЯЗОВ (ВЕЛИКИЙ СУД // ЧЕРНАЯ ЛИГА)
# ==============================================================================

## Действие Язова: «Строительство подземных бункеров Карбышева»
func yazov_action_build_bunker(country_state: CountryState) -> Dictionary:
	var money_cost = 0.08
	var cap_cost = 1
	var pc_cost = 10.0
	
	if country_state != null:
		if country_state.liquid_reserves_billions < money_cost or country_state.current_cap < cap_cost:
			return {"success": false, "reason": "НЕДОСТАТОЧНО РЕЗЕРВОВ ИЛИ CAP"}
		country_state.liquid_reserves_billions -= money_cost
		country_state.current_cap -= cap_cost
		country_state.political_capital = maxf(0.0, country_state.political_capital - pc_cost)
		country_state.army_readiness = clampf(country_state.army_readiness + 3.0, 0.0, 100.0)
	
	yazov_bunker_network_level = clampi(yazov_bunker_network_level + 1, 0, 5)
	yazov_trial_readiness = clampf(yazov_trial_readiness + 12.0, 0.0, 100.0)
	
	var capacity_str = get_yazov_bunker_capacity_str()
	var res = {
		"success": true,
		"action": "BUILD_BUNKER",
		"bunker_level": yazov_bunker_network_level,
		"capacity": capacity_str,
		"readiness": yazov_trial_readiness,
		"narrative": "Подземные цитадели в скалах Урала расширены до Уровня %d. Черная Лига гарантирует выживание нации в пламени Судного Дня. Вместимость убежищ: %s." % [yazov_bunker_network_level, capacity_str]
	}
	mechanic_action_executed.emit("BUILD_BUNKER", res)
	return res


## Действие Язова: «Синтез боевых токсинов "Омск-65"»
func yazov_action_produce_chemical_weapons(country_state: CountryState) -> Dictionary:
	var weapons_cost = 180
	var pc_cost = 15.0
	
	if country_state != null:
		if country_state.infantry_weapons_stockpile < weapons_cost or country_state.political_capital < pc_cost:
			return {"success": false, "reason": "НЕДОСТАТОЧНО ОРУЖИЯ ИЛИ PC"}
		country_state.infantry_weapons_stockpile -= weapons_cost
		country_state.political_capital -= pc_cost
		country_state.military_factories += 1
	
	yazov_chemical_stockpile_tons += 350
	yazov_teutonic_hatred = clampf(yazov_teutonic_hatred + 5.0, 0.0, 100.0)
	yazov_trial_readiness = clampf(yazov_trial_readiness + 8.0, 0.0, 100.0)
	
	var res = {
		"success": true,
		"action": "PRODUCE_CHEMICAL_WEAPONS",
		"stockpile_tons": yazov_chemical_stockpile_tons,
		"hatred": yazov_teutonic_hatred,
		"narrative": "Химические лаборатории Омска поставили на конвейер боевые токсины. Каждый тевтонский захватчик захлебнется собственной кровью при первой же контратаке Лиги."
	}
	mechanic_action_executed.emit("PRODUCE_CHEMICAL_WEAPONS", res)
	return res


## Действие Язова: «Полевые трибуналы и искоренение слабости»
func yazov_action_field_tribunals(country_state: CountryState) -> Dictionary:
	var pc_cost = 15.0
	var cap_cost = 1
	
	if country_state != null:
		if country_state.political_capital < pc_cost or country_state.current_cap < cap_cost:
			return {"success": false, "reason": "НЕДОСТАТОЧНО PC ИЛИ CAP"}
		country_state.political_capital -= pc_cost
		country_state.current_cap -= cap_cost
		country_state.legitimacy = clampf(country_state.legitimacy + 6.0, 0.0, 100.0)
		country_state.army_readiness = clampf(country_state.army_readiness + 8.0, 0.0, 100.0)
		country_state.manpower_pool += 12000
	
	yazov_teutonic_hatred = clampf(yazov_teutonic_hatred + 6.0, 0.0, 100.0)
	yazov_trial_readiness = clampf(yazov_trial_readiness + 10.0, 0.0, 100.0)
	
	var res = {
		"success": true,
		"action": "FIELD_TRIBUNALS",
		"hatred": yazov_teutonic_hatred,
		"readiness": yazov_trial_readiness,
		"narrative": "Трибуналы Карбышева-Язова пресекли любые пораженческие настроения. Вся сибирская молодежь призвана под черные знамена. Нет отступления, нет пощады."
	}
	mechanic_action_executed.emit("FIELD_TRIBUNALS", res)
	return res


## Действие Язова: «Провозглашение готовности к Великому Суду»
func yazov_action_proclaim_great_trial(country_state: CountryState) -> Dictionary:
	if yazov_trial_readiness < 80.0:
		return {"success": false, "reason": "ГОТОВНОСТЬ К СУДУ НИЖЕ 80%% (СЕЙЧАС %0.1f%%)" % yazov_trial_readiness}
	
	yazov_is_trial_declared = true
	if country_state != null:
		country_state.country_name = "Всероссийская Черная Лига (Великий Суд)"
		country_state.legitimacy = 100.0
		country_state.army_readiness = 100.0
		country_state.set_flag("great_trial_active", true)
	
	great_trial_prepared.emit(yazov_trial_readiness)
	
	var res = {
		"success": true,
		"action": "PROCLAIM_GREAT_TRIAL",
		"readiness": yazov_trial_readiness,
		"narrative": "ГЕНЕРАЛ ЯЗОВ ОБРАТИЛСЯ К НАЦИИ: ЧАС ВЕЛИКОГО СУДА НАСТАЛ. Вся экономика переведена на режим тотального возмездия. Германия заплатит за каждую пядь русской земли!"
	}
	mechanic_action_executed.emit("PROCLAIM_GREAT_TRIAL", res)
	return res


func get_yazov_bunker_capacity_str() -> String:
	match yazov_bunker_network_level:
		0: return "0 чел."
		1: return "500,000 чел."
		2: return "1,500,000 чел."
		3: return "3,500,000 чел."
		4: return "7,000,000 чел."
		5: return "15,000,000 чел. (ТОТАЛЬНАЯ ЗАЩИТА)"
		_: return "3,000,000 чел."


# ==============================================================================
# МЕХАНИКА 3: ВАЛЕРИЙ САБЛИН (ИДЕАЛИЗМ VS ПРАГМАТИЗМ)
# ==============================================================================

## Действие Саблина: «Открытые дебаты в Советах» (Путь Идеализма)
func sablin_action_soviet_democracy(country_state: CountryState) -> Dictionary:
	var pc_cost = 10.0
	var cap_cost = 1
	
	if country_state != null:
		if country_state.political_capital < pc_cost or country_state.current_cap < cap_cost:
			return {"success": false, "reason": "НЕДОСТАТОЧНО PC ИЛИ CAP"}
		country_state.political_capital -= pc_cost
		country_state.current_cap -= cap_cost
		country_state.legitimacy = clampf(country_state.legitimacy + 9.0, 0.0, 100.0)
		country_state.radicalization = maxf(0.0, country_state.radicalization - 8.0)
		country_state.gdp_billions += 0.03
	
	sablin_idealism = clampf(sablin_idealism + 8.0, 0.0, 100.0)
	sablin_soviet_democracy = clampf(sablin_soviet_democracy + 10.0, 0.0, 100.0)
	sablin_revolutionary_enthusiasm = clampf(sablin_revolutionary_enthusiasm + 7.0, 0.0, 100.0)
	sablin_balance_shifted.emit(sablin_idealism)
	
	var res = {
		"success": true,
		"action": "SOVIET_DEMOCRACY",
		"idealism": sablin_idealism,
		"democracy": sablin_soviet_democracy,
		"narrative": "Советы рабочих и красноармейцев получили право вето на решения комиссаров. Народный энтузиазм на Байкале бьет ключом. Революция жива!"
	}
	mechanic_action_executed.emit("SOVIET_DEMOCRACY", res)
	return res


## Действие Саблина: «Амнистия для оступившихся узников» (Путь Идеализма)
func sablin_action_amnesty_prisoners(country_state: CountryState) -> Dictionary:
	var pc_cost = 15.0
	
	if country_state != null:
		if country_state.political_capital < pc_cost:
			return {"success": false, "reason": "НЕДОСТАТОЧНО PC"}
		country_state.political_capital -= pc_cost
		country_state.radicalization = maxf(0.0, country_state.radicalization - 12.0)
		country_state.manpower_pool += 6000
		country_state.literacy_rate = clampf(country_state.literacy_rate + 1.5, 0.0, 100.0)
	
	sablin_idealism = clampf(sablin_idealism + 6.0, 0.0, 100.0)
	sablin_revolutionary_enthusiasm = clampf(sablin_revolutionary_enthusiasm + 8.0, 0.0, 100.0)
	sablin_balance_shifted.emit(sablin_idealism)
	
	var res = {
		"success": true,
		"action": "AMNESTY_PRISONERS",
		"idealism": sablin_idealism,
		"narrative": "Двери тюрем открыты для тех, кто стал жертвой деспотизма Ягоды. Освобожденные специалисты и рабочие присоединяются к строительству свободного социализма."
	}
	mechanic_action_executed.emit("AMNESTY_PRISONERS", res)
	return res


## Действие Саблина: «Органы безопасности Революции» (Путь Прагматизма)
func sablin_action_cheka_discipline(country_state: CountryState) -> Dictionary:
	var pc_cost = 15.0
	var cap_cost = 1
	
	if country_state != null:
		if country_state.political_capital < pc_cost or country_state.current_cap < cap_cost:
			return {"success": false, "reason": "НЕДОСТАТОЧНО PC ИЛИ CAP"}
		country_state.political_capital -= pc_cost
		country_state.current_cap -= cap_cost
		country_state.army_readiness = clampf(country_state.army_readiness + 10.0, 0.0, 100.0)
		country_state.infantry_weapons_stockpile += 200
		country_state.legitimacy = maxf(0.0, country_state.legitimacy - 3.0)
	
	# Сдвиг в сторону прагматизма
	sablin_idealism = clampf(sablin_idealism - 10.0, 0.0, 100.0)
	sablin_soviet_democracy = maxf(0.0, sablin_soviet_democracy - 8.0)
	sablin_balance_shifted.emit(sablin_idealism)
	
	var res = {
		"success": true,
		"action": "CHEKA_DISCIPLINE",
		"idealism": sablin_idealism,
		"narrative": "Для защиты Революции от диверсантов Иркутска и Читы учрежден Революционный Комитет Безопасности. Дисциплина возросла, хотя старые ленинцы выражают тревогу."
	}
	mechanic_action_executed.emit("CHEKA_DISCIPLINE", res)
	return res


## Действие Саблина: «Формирование Красных Добровольческих Дружин»
func sablin_action_red_volunteers(country_state: CountryState) -> Dictionary:
	var pc_cost = 12.0
	var cap_cost = 1
	
	if country_state != null:
		if country_state.political_capital < pc_cost or country_state.current_cap < cap_cost:
			return {"success": false, "reason": "НЕДОСТАТОЧНО PC ИЛИ CAP"}
		country_state.political_capital -= pc_cost
		country_state.current_cap -= cap_cost
		var bonus_manpower = int(8000.0 * (sablin_revolutionary_enthusiasm / 100.0)) + 3000
		country_state.manpower_pool += bonus_manpower
		country_state.infantry_weapons_stockpile += 150
	
	var res = {
		"success": true,
		"action": "RED_VOLUNTEERS",
		"narrative": "Сотни добровольцев из глубин Сибири стекаются под знамена Саблина, вдохновленные надеждой на подлинное рабочее государство."
	}
	mechanic_action_executed.emit("RED_VOLUNTEERS", res)
	return res


# ==============================================================================
# ПОШАГОВЫЙ ЦИКЛ (TURN PROCESS)
# ==============================================================================

## Вызывается каждый ход из RussianUnificationManager
func process_turn(tag: String, country_state: CountryState) -> Dictionary:
	var m_type = get_active_mechanic_type(tag, country_state)
	var report = {
		"mechanic_type": m_type,
		"events": []
	}
	
	match m_type:
		"TABORITSKY":
			if not is_midnight_collapsed:
				# Пассивное тиканье часов каждый ход (+5 минут)
				var clk = advance_taboritsky_clock(5, country_state)
				report["clock_time"] = get_taboritsky_clock_str()
				report["collapsed"] = clk.get("collapsed", false)
				if report["collapsed"]:
					report["events"].append("MIDNIGHT_COLLAPSE")
		"YAZOV":
			# Пассивный дрейф ненависти и готовности к суду
			if country_state != null:
				yazov_trial_readiness = clampf(yazov_trial_readiness + 0.5 + float(yazov_bunker_network_level) * 0.2, 0.0, 100.0)
				yazov_chemical_stockpile_tons += 25 * yazov_bunker_network_level
			report["hatred"] = yazov_teutonic_hatred
			report["readiness"] = yazov_trial_readiness
			report["bunkers"] = yazov_bunker_network_level
		"SABLIN":
			# Баланс стабильности
			if sablin_idealism >= 70.0:
				if country_state != null:
					country_state.legitimacy = clampf(country_state.legitimacy + 0.8, 0.0, 100.0)
			report["idealism"] = sablin_idealism
			report["democracy"] = sablin_soviet_democracy
			
	return report


# ==============================================================================
# СЕРИАЛИЗАЦИЯ И ВОССТАНОВЛЕНИЕ
# ==============================================================================

func to_dict() -> Dictionary:
	return {
		"taboritsky": {
			"clock_minutes": taboritsky_clock_minutes,
			"insanity": taboritsky_insanity_level,
			"cleansed_count": taboritsky_cleansed_regions_count,
			"alexei_searches": taboritsky_alexei_searches_count,
			"is_collapsed": is_midnight_collapsed
		},
		"yazov": {
			"hatred": yazov_teutonic_hatred,
			"bunker_level": yazov_bunker_network_level,
			"chemical_tons": yazov_chemical_stockpile_tons,
			"readiness": yazov_trial_readiness,
			"trial_declared": yazov_is_trial_declared
		},
		"sablin": {
			"idealism": sablin_idealism,
			"democracy": sablin_soviet_democracy,
			"enthusiasm": sablin_revolutionary_enthusiasm
		}
	}


func from_dict(data: Dictionary) -> void:
	if data.has("taboritsky") and data["taboritsky"] is Dictionary:
		var t = data["taboritsky"]
		taboritsky_clock_minutes = int(t.get("clock_minutes", 240))
		taboritsky_insanity_level = float(t.get("insanity", 25.0))
		taboritsky_cleansed_regions_count = int(t.get("cleansed_count", 0))
		taboritsky_alexei_searches_count = int(t.get("alexei_searches", 0))
		is_midnight_collapsed = bool(t.get("is_collapsed", false))
		
	if data.has("yazov") and data["yazov"] is Dictionary:
		var y = data["yazov"]
		yazov_teutonic_hatred = float(y.get("hatred", 65.0))
		yazov_bunker_network_level = int(y.get("bunker_level", 1))
		yazov_chemical_stockpile_tons = int(y.get("chemical_tons", 250))
		yazov_trial_readiness = float(y.get("readiness", 20.0))
		yazov_is_trial_declared = bool(y.get("trial_declared", false))
		
	if data.has("sablin") and data["sablin"] is Dictionary:
		var s = data["sablin"]
		sablin_idealism = float(s.get("idealism", 68.0))
		sablin_soviet_democracy = float(s.get("democracy", 75.0))
		sablin_revolutionary_enthusiasm = float(s.get("enthusiasm", 80.0))
