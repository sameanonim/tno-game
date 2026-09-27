class_name USElectoralEngine
extends RefCounted

##
## USElectoralEngine: Пошаговый электоральный движок политики США TNO
##
## Моделирует уникальную политическую систему Соединенных Штатов в сеттинге TNO:
## 1. Двухпартийный дуализм: Коалиция РДК (R-D) vs Пакт НПП (NPP).
##    - Фракции: RD_D (Демократы), RD_R (Республиканцы),
##      NPP_C (Прогрессисты / Центр), NPP_FR (Националисты / Ястребы),
##      NPP_L (Марксисты Холла), NPP_Y (Фанатики Йоки).
## 2. Модель Сената США (100 мест):
##    - Выборы каждые 2 года (1/3 Сената — 33-34 места на перевыборах).
##    - Колебания электората в 4 макрорегионах (Северо-Восток, Средний Запад, Юг, Запад).
## 3. Выборы Президента (каждые 4 года: 1964, 1968, 1972):
##    - Коллегия выборщиков (538 голосов, 270 для победы).
##    - Исторические кандидаты TNO (LBJ, RFK, Wallace, Bennett, Goldwater, Hart, Harrington, Yockey, Hall).
##    - Динамическая смена верховного лидера и ветки директив США.
## 4. Законодательный процесс (Конгресс / Passing Bills):
##    - Голосование за законы (Гражданские права, Великое общество, Бюджет ОФН).
##    - Механика «Склонения сенаторов» (Whip Votes) за очки PC / CAP.
##

signal senate_seats_updated(seats: Dictionary, deltas: Dictionary)
signal president_elected(result: Dictionary)
signal bill_vote_completed(bill_id: String, passed: bool, result: Dictionary)
signal civil_rights_tension_changed(new_tension: float)

# Идентификаторы фракций
const FACTION_RD_D = "RD_D"     # РДК Демократы
const FACTION_RD_R = "RD_R"     # РДК Республиканцы
const FACTION_NPP_C = "NPP_C"   # НПП Прогрессисты
const FACTION_NPP_FR = "NPP_FR" # НПП Националисты
const FACTION_NPP_L = "NPP_L"   # НПП Марксисты (Холл)
const FACTION_NPP_Y = "NPP_Y"   # НПП Йоки (Фасцисты)

const ALL_FACTIONS: Array[String] = [
	FACTION_RD_D, FACTION_RD_R, FACTION_NPP_C, FACTION_NPP_FR, FACTION_NPP_L, FACTION_NPP_Y
]

# Цвета партий (канон TNO)
const FACTION_COLORS: Dictionary = {
	FACTION_RD_D: Color(0.25, 0.60, 0.90),
	FACTION_RD_R: Color(0.15, 0.35, 0.85),
	FACTION_NPP_C: Color(0.15, 0.75, 0.65),
	FACTION_NPP_FR: Color(0.55, 0.45, 0.35),
	FACTION_NPP_L: Color(0.85, 0.15, 0.15),
	FACTION_NPP_Y: Color(0.40, 0.10, 0.40)
}

# Регионы Коллегии выборщиков (всего 538 EV)
const REGION_NORTHEAST = "NORTHEAST" # 120 EV
const REGION_MIDWEST = "MIDWEST"     # 135 EV
const REGION_SOUTH = "SOUTH"         # 160 EV
const REGION_WEST = "WEST"           # 123 EV

const ALL_REGIONS: Array[String] = [
	REGION_NORTHEAST, REGION_MIDWEST, REGION_SOUTH, REGION_WEST
]

# --- ТЕКУЩЕЕ СОСТОЯНИЕ ЭЛЕКТОРАЛЬНОЙ СИСТЕМЫ ---
var senate_seats: Dictionary = {
	FACTION_RD_D: 34,
	FACTION_RD_R: 28,
	FACTION_NPP_C: 20,
	FACTION_NPP_FR: 18,
	FACTION_NPP_L: 0,
	FACTION_NPP_Y: 0
}

var current_president: Dictionary = {
	"id": "USA_Richard_Nixon",
	"name": "Ричард Никсон",
	"name_en": "Richard Nixon",
	"portrait_path": "res://assets/gfx/leaders/USA/USA_Richard_Nixon.png",
	"faction": FACTION_RD_R,
	"coalition": "RD",
	"ideology": "conservatism",
	"term_start_year": 1961,
	"term_number": 1,
	"tree_id": "TNO_USA_shared"
}

# Напряженность вокруг Закона о гражданских правах (0.0 - 100.0)
var civil_rights_tension: float = 50.0
# Статус гражданских прав: "PENDING", "WEAK", "MODERATE", "STRONG", "VETOED"
var civil_rights_status: String = "PENDING"

# Внешнеполитическое недовольство (Война в Южной Африке / Гайана)
var hawkish_frustration: float = 20.0

# Календарь выборов
var last_midterm_turn: int = 0
var last_presidential_election_year: int = 1960
var next_midterm_turn: int = 104 # 2 года при недельном шаге (24 при месячном)
var next_presidential_turn: int = 208 # 4 года при недельном шаге (48 при месячном)

# Лог последних выборов
var last_election_report: Dictionary = {}

# Активное лоббирование / законопроект
var active_bill_id: String = ""
var whipped_undecided_bonus: int = 0


# ==============================================================================
# ИНИЦИАЛИЗАЦИЯ И КОНФИГУРАЦИЯ
# ==============================================================================

func _init() -> void:
	_load_constants()


func _load_constants() -> void:
	var cfg = ConfigManager.get_instance()
	if cfg == null or not cfg.has_category("us_politics"):
		return
	var initial_seats = cfg.get_dict("us_politics", "initial_senate_seats", {})
	if not initial_seats.is_empty():
		for f in ALL_FACTIONS:
			if initial_seats.has(f):
				senate_seats[f] = int(initial_seats[f])


# ==============================================================================
# ПУБЛИЧНЫЙ API: СЕНАТ И КОАЛИЦИИ
# ==============================================================================

##
## Возвращает число мест конкретной фракции в Сенате
##
func get_seats(faction: String) -> int:
	return int(senate_seats.get(faction, 0))


##
## Возвращает суммарное число мест коалиции ("RD" или "NPP")
##
func get_coalition_seats(coalition: String) -> int:
	var c_upper = coalition.to_upper()
	if c_upper == "RD":
		return get_seats(FACTION_RD_D) + get_seats(FACTION_RD_R)
	elif c_upper == "NPP":
		return get_seats(FACTION_NPP_C) + get_seats(FACTION_NPP_FR) + get_seats(FACTION_NPP_L) + get_seats(FACTION_NPP_Y)
	return 0


##
## Проверяет, контролирует ли фракция или коалиция большинство в Сенате (>= 51)
##
func has_majority(faction_or_coalition: String) -> bool:
	var threshold = 51
	var cfg = ConfigManager.get_instance()
	if cfg != null and cfg.has_category("us_politics"):
		threshold = cfg.get_int("us_politics", "senate_majority_threshold", 51)

	if faction_or_coalition in ["RD", "NPP"]:
		return get_coalition_seats(faction_or_coalition) >= threshold
	return get_seats(faction_or_coalition) >= threshold


##
## Возвращает общее количество мест в Сенате (всегда 100)
##
func get_total_senate_seats() -> int:
	var total = 0
	for f in senate_seats.keys():
		total += int(senate_seats[f])
	return total


##
## Генерирует массив из 100 объектов мест для отрисовки в полукруге Сената (UI Hemicycle)
##
func get_senate_seat_list() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seat_idx = 0

	# Упорядочиваем слева направо: NPP_L -> NPP_C -> RD_D -> RD_R -> NPP_FR -> NPP_Y
	var faction_order = [
		FACTION_NPP_L, FACTION_NPP_C, FACTION_RD_D, FACTION_RD_R, FACTION_NPP_FR, FACTION_NPP_Y
	]

	for f in faction_order:
		var count = get_seats(f)
		for _i in range(count):
			result.append({
				"seat_index": seat_idx,
				"faction": f,
				"faction_name": get_faction_name(f),
				"color": get_faction_color(f)
			})
			seat_idx += 1

	return result


func get_faction_name(faction: String) -> String:
	match faction:
		FACTION_RD_D: return "РДК (Демократы)"
		FACTION_RD_R: return "РДК (Республиканцы)"
		FACTION_NPP_C: return "НПП (Прогрессисты / Центр)"
		FACTION_NPP_FR: return "НПП (Националисты / Ястребы)"
		FACTION_NPP_L: return "НПП (Марксисты)"
		FACTION_NPP_Y: return "НПП (Йоки)"
	return faction


func get_faction_color(faction: String) -> Color:
	return FACTION_COLORS.get(faction, Color(0.5, 0.5, 0.5))


# ==============================================================================
# ЭЛЕКТОРАЛЬНАЯ ДИНАМИКА И РЕГИОНАЛЬНЫЕ ОПРОСЫ
# ==============================================================================

##
## Рассчитывает популярность партий по 4 ключевым макрорегионам США
##
func calculate_regional_popularities(country_state: CountryState) -> Dictionary:
	var result: Dictionary = {}

	# Базовые региональные предпочтения
	var base_regions = {
		REGION_NORTHEAST: {FACTION_RD_R: 35.0, FACTION_NPP_C: 35.0, FACTION_RD_D: 20.0, FACTION_NPP_FR: 10.0},
		REGION_MIDWEST: {FACTION_RD_R: 40.0, FACTION_RD_D: 25.0, FACTION_NPP_C: 20.0, FACTION_NPP_FR: 15.0},
		REGION_SOUTH: {FACTION_RD_D: 50.0, FACTION_NPP_FR: 40.0, FACTION_RD_R: 7.0, FACTION_NPP_C: 3.0},
		REGION_WEST: {FACTION_RD_R: 35.0, FACTION_NPP_C: 30.0, FACTION_NPP_FR: 20.0, FACTION_RD_D: 15.0}
	}

	# Факторы влияния состояния государства
	var rad = country_state.radicalization if country_state != null else 20.0
	var leg = country_state.legitimacy if country_state != null else 70.0
	var pov = country_state.poverty_rate if country_state != null else 22.0

	# 1. Влияние напряженности гражданских прав
	# Высокая напряженность / принятие Strong CRA отталкивает Юг от RD_D к NPP_FR, но поднимает NPP_C и RD_R на Севере
	var cr_south_shift = (civil_rights_tension - 50.0) * 0.4
	var cr_north_shift = (civil_rights_tension - 50.0) * 0.2

	for reg in ALL_REGIONS:
		var lean = base_regions[reg].duplicate()
		lean[FACTION_NPP_L] = 0.0
		lean[FACTION_NPP_Y] = 0.0

		if reg == REGION_SOUTH:
			lean[FACTION_RD_D] = maxf(5.0, lean[FACTION_RD_D] - cr_south_shift)
			lean[FACTION_NPP_FR] = maxf(10.0, lean[FACTION_NPP_FR] + cr_south_shift)
		elif reg == REGION_NORTHEAST:
			lean[FACTION_NPP_C] = maxf(10.0, lean[FACTION_NPP_C] + cr_north_shift)
			lean[FACTION_RD_R] = maxf(10.0, lean[FACTION_RD_R] + cr_north_shift * 0.5)

		# 2. Влияние бедности и инфляции (поддерживает левых популистов NPP_C)
		if pov > 25.0:
			var pov_shift = (pov - 25.0) * 0.5
			lean[FACTION_NPP_C] += pov_shift
			lean[FACTION_RD_R] = maxf(5.0, lean[FACTION_RD_R] - pov_shift * 0.5)

		# 3. Влияние радикализации: при падении легитимности (< 40) и высокой радикализации (> 40)
		# начинают расти крайние фракции (NPP_L и NPP_Y)
		if rad > 35.0:
			var rad_factor = (rad - 35.0) * 0.25
			lean[FACTION_NPP_L] = rad_factor * 0.5
			lean[FACTION_NPP_Y] = rad_factor * 0.5
			# Отнимаем у центристов
			lean[FACTION_RD_D] = maxf(5.0, lean[FACTION_RD_D] - rad_factor * 0.5)
			lean[FACTION_RD_R] = maxf(5.0, lean[FACTION_RD_R] - rad_factor * 0.5)

		# Нормализация до 100%
		var total_sum = 0.0
		for f in lean.keys():
			total_sum += lean[f]

		var norm_lean: Dictionary = {}
		if total_sum > 0.0:
			for f in lean.keys():
				norm_lean[f] = (lean[f] / total_sum) * 100.0
		else:
			norm_lean = lean

		result[reg] = norm_lean

	return result


# ==============================================================================
# ВЫБОРЫ В СЕНАТ (SENATE MIDTERMS & GENERALS)
# ==============================================================================

##
## Проводит выборы в 1/3 мест Сената (33-34 места)
##
func conduct_senate_elections(country_state: CountryState) -> Dictionary:
	var total_seats_to_elect = 34
	var regional_poll = calculate_regional_popularities(country_state)

	# Распределение 34 мест по регионам:
	# Northeast: 8, Midwest: 9, South: 10, West: 7 (всего 34)
	var seats_per_region = {
		REGION_NORTHEAST: 8,
		REGION_MIDWEST: 9,
		REGION_SOUTH: 10,
		REGION_WEST: 7
	}

	# Новые выигранные места по фракциям в текущем электоральном цикле
	var newly_elected: Dictionary = {
		FACTION_RD_D: 0, FACTION_RD_R: 0, FACTION_NPP_C: 0,
		FACTION_NPP_FR: 0, FACTION_NPP_L: 0, FACTION_NPP_Y: 0
	}

	for reg in ALL_REGIONS:
		var reg_seats = seats_per_region[reg]
		var polls = regional_poll[reg]

		# Пропорциональное распределение мест по методу наибольших остатков
		var raw_seats: Dictionary = {}
		var remainders: Array[Dictionary] = []
		var assigned = 0

		for f in ALL_FACTIONS:
			var vote_share = float(polls.get(f, 0.0)) / 100.0
			var exact = vote_share * float(reg_seats)
			var floored = int(floor(exact))
			raw_seats[f] = floored
			assigned += floored
			remainders.append({"faction": f, "rem": exact - floored})

		# Сортировка остатков по убыванию
		remainders.sort_custom(func(a, b): return a["rem"] > b["rem"])
		var left_to_assign = reg_seats - assigned
		for i in range(mini(left_to_assign, remainders.size())):
			raw_seats[remainders[i]["faction"]] += 1

		for f in ALL_FACTIONS:
			newly_elected[f] += raw_seats.get(f, 0)

	# Места, которые были освобождены под выборы (условно 34 места пропорционально текущему составу)
	var vacated_seats: Dictionary = {}
	var vac_assigned = 0
	var vac_remainders: Array[Dictionary] = []
	for f in ALL_FACTIONS:
		var exact_vac = (float(senate_seats[f]) / 100.0) * float(total_seats_to_elect)
		var floored = int(floor(exact_vac))
		vacated_seats[f] = floored
		vac_assigned += floored
		vac_remainders.append({"faction": f, "rem": exact_vac - floored})

	vac_remainders.sort_custom(func(a, b): return a["rem"] > b["rem"])
	var vac_diff = total_seats_to_elect - vac_assigned
	for i in range(mini(vac_diff, vac_remainders.size())):
		vacated_seats[vac_remainders[i]["faction"]] += 1

	# Расчет сдвигов мест (Deltas)
	var deltas: Dictionary = {}
	for f in ALL_FACTIONS:
		var net_change = newly_elected[f] - vacated_seats[f]
		deltas[f] = net_change
		senate_seats[f] = clampi(senate_seats[f] + net_change, 0, 100)

	# Гарантия суммы 100 мест
	var actual_total = get_total_senate_seats()
	if actual_total != 100:
		var discrepancy = 100 - actual_total
		senate_seats[FACTION_RD_R] += discrepancy

	var report = {
		"total_contested": total_seats_to_elect,
		"newly_elected": newly_elected,
		"vacated": vacated_seats,
		"deltas": deltas,
		"new_composition": senate_seats.duplicate(),
		"rd_total": get_coalition_seats("RD"),
		"npp_total": get_coalition_seats("NPP"),
		"majority_coalition": "RD" if get_coalition_seats("RD") >= 51 else ("NPP" if get_coalition_seats("NPP") >= 51 else "HUNG")
	}

	last_election_report = report
	senate_seats_updated.emit(senate_seats.duplicate(), deltas)
	return report


# ==============================================================================
# ПРЕЗИДЕНТСКИЕ ВЫБОРЫ (PRESIDENTIAL ELECTIONS // ELECTORAL COLLEGE)
# ==============================================================================

##
## Проводит президентские выборы США (1964, 1968, 1972)
##
func conduct_presidential_election(
	election_year: int,
	country_state: CountryState,
	preferred_rd_candidate: String = "",
	preferred_npp_candidate: String = ""
) -> Dictionary:
	last_presidential_election_year = election_year

	# Определение кандидатов
	var candidate_rd = _select_rd_candidate(election_year, preferred_rd_candidate)
	var candidate_npp = _select_npp_candidate(election_year, preferred_npp_candidate, country_state)

	var regional_poll = calculate_regional_popularities(country_state)

	# Голоса Коллегии выборщиков по регионам
	var ev_per_region = {
		REGION_NORTHEAST: 120,
		REGION_MIDWEST: 135,
		REGION_SOUTH: 160,
		REGION_WEST: 123
	}

	var ev_rd = 0
	var ev_npp = 0
	var regional_outcomes: Dictionary = {}

	for reg in ALL_REGIONS:
		var polls = regional_poll[reg]
		var rd_votes = float(polls.get(FACTION_RD_D, 0.0)) + float(polls.get(FACTION_RD_R, 0.0))
		var npp_votes = float(polls.get(FACTION_NPP_C, 0.0)) + float(polls.get(FACTION_NPP_FR, 0.0)) + float(polls.get(FACTION_NPP_L, 0.0)) + float(polls.get(FACTION_NPP_Y, 0.0))

		var ev_count = ev_per_region[reg]
		var reg_winner = ""
		if rd_votes >= npp_votes:
			reg_winner = "RD"
			ev_rd += ev_count
		else:
			reg_winner = "NPP"
			ev_npp += ev_count

		regional_outcomes[reg] = {
			"ev": ev_count,
			"winner": reg_winner,
			"rd_share": rd_votes,
			"npp_share": npp_votes
		}

	# Определение победителя
	var winner_coalition = "RD" if ev_rd >= 270 else "NPP"
	var winning_candidate = candidate_rd if winner_coalition == "RD" else candidate_npp

	# Обновление состояния страны CountryState
	if country_state != null:
		country_state.leader_name = winning_candidate.name
		country_state.leader_portrait_path = winning_candidate.portrait_path
		country_state.ruling_ideology = winning_candidate.ideology
		country_state.ruling_party = winning_candidate.name + " (" + winning_candidate.faction + ")"
		if "initial_parties" in country_state and country_state.initial_parties != null:
			for p in country_state.initial_parties:
				if p is PartyData:
					p.is_ruling = (p.ideology_key == winning_candidate.ideology)


	# Обновление локального состояния президента
	current_president = {
		"id": winning_candidate.id,
		"name": winning_candidate.name,
		"name_en": winning_candidate.name_en,
		"portrait_path": winning_candidate.portrait_path,
		"faction": winning_candidate.faction,
		"coalition": winner_coalition,
		"ideology": winning_candidate.ideology,
		"term_start_year": election_year,
		"term_number": 1,
		"tree_id": winning_candidate.tree_id
	}

	var election_result = {
		"year": election_year,
		"winner_coalition": winner_coalition,
		"winning_candidate": winning_candidate,
		"ev_rd": ev_rd,
		"ev_npp": ev_npp,
		"regional_outcomes": regional_outcomes,
		"candidate_rd": candidate_rd,
		"candidate_npp": candidate_npp
	}

	president_elected.emit(election_result)
	return election_result


func _select_rd_candidate(year: int, preferred: String) -> Dictionary:
	var candidates_1964 = {
		"LBJ": {
			"id": "USA_Lyndon_B_Johnson",
			"name": "Линдон Б. Джонсон",
			"name_en": "Lyndon B. Johnson",
			"portrait_path": "res://assets/gfx/leaders/USA/USA_Lyndon_B_Johnson.png",
			"faction": FACTION_RD_D,
			"ideology": "liberalism",
			"tree_id": "TNO_USA_LBJ_shared"
		},
		"BENNETT": {
			"id": "USA_Wallace_F_Bennett",
			"name": "Уоллес Ф. Беннетт",
			"name_en": "Wallace F. Bennett",
			"portrait_path": "res://assets/gfx/leaders/USA/USA_Wallace_F_Bennett.png",
			"faction": FACTION_RD_R,
			"ideology": "conservatism",
			"tree_id": "TNO_USA_WFB_shared"
		}
	}

	var candidates_1968 = {
		"GOLDWATER": {
			"id": "USA_Barry_Goldwater",
			"name": "Барри Голдуотер",
			"name_en": "Barry Goldwater",
			"portrait_path": "res://assets/gfx/leaders/USA/USA_Barry_Goldwater.png",
			"faction": FACTION_RD_R,
			"ideology": "conservatism",
			"tree_id": "TNO_USA_GLD_shared"
		},
		"HART": {
			"id": "USA_Philip_Hart",
			"name": "Филип Харт",
			"name_en": "Philip Hart",
			"portrait_path": "res://assets/gfx/leaders/USA/USA_Philip_Hart.png",
			"faction": FACTION_RD_D,
			"ideology": "progressivism",
			"tree_id": "TNO_USA_Hart_shared"
		},
		"MCGOVERN": {
			"id": "USA_George_McGovern",
			"name": "Джордж Макговерн",
			"name_en": "George McGovern",
			"portrait_path": "res://assets/gfx/leaders/USA/USA_George_McGovern.png",
			"faction": FACTION_RD_D,
			"ideology": "liberalism",
			"tree_id": "TNO_USA_shared"
		}
	}

	var pool = candidates_1964 if year <= 1964 else candidates_1968
	if not preferred.is_empty() and pool.has(preferred.to_upper()):
		return pool[preferred.to_upper()]

	# По умолчанию: LBJ в 1964, Goldwater в 1968
	if year <= 1964:
		return pool["LBJ"]
	return pool["GOLDWATER"]


func _select_npp_candidate(year: int, preferred: String, country_state: CountryState) -> Dictionary:
	var rad = country_state.radicalization if country_state != null else 20.0
	var leg = country_state.legitimacy if country_state != null else 70.0

	# Если кризис доверия экстремален: выдвижение экстремистов
	if rad >= 50.0 and leg <= 35.0:
		if preferred.to_upper() == "YOCKEY" or randf() < 0.5:
			return {
				"id": "USA_Francis_Yockey",
				"name": "Фрэнсис Паркер Йоки",
				"name_en": "Francis Parker Yockey",
				"portrait_path": "res://assets/gfx/leaders/USA/USA_Francis_Yockey.png",
				"faction": FACTION_NPP_Y,
				"ideology": "ultranationalism",
				"tree_id": "TNO_USA_shared"
			}
		else:
			return {
				"id": "USA_Gus_Hall",
				"name": "Гэс Холл",
				"name_en": "Gus Hall",
				"portrait_path": "res://assets/gfx/leaders/USA/USA_Gus_Hall.png",
				"faction": FACTION_NPP_L,
				"ideology": "communist",
				"tree_id": "TNO_USA_shared"
			}

	var candidates_1964 = {
		"RFK": {
			"id": "USA_Robert_F_Kennedy",
			"name": "Роберт Ф. Кеннеди",
			"name_en": "Robert F. Kennedy",
			"portrait_path": "res://assets/gfx/leaders/USA/USA_Robert_F_Kennedy.png",
			"faction": FACTION_NPP_C,
			"ideology": "progressivism",
			"tree_id": "TNO_USA_RFK_shared"
		},
		"WALLACE": {
			"id": "USA_George_Wallace",
			"name": "Джордж Уоллес",
			"name_en": "George Wallace",
			"portrait_path": "res://assets/gfx/leaders/USA/USA_George_Wallace.png",
			"faction": FACTION_NPP_FR,
			"ideology": "paternalism",
			"tree_id": "TNO_USA_WAL_Response_68"
		}
	}

	var candidates_1968 = {
		"HARRINGTON": {
			"id": "USA_Michael_Harrington",
			"name": "Майкл Харрингтон",
			"name_en": "Michael Harrington",
			"portrait_path": "res://assets/gfx/leaders/USA/USA_Michael_Harrington.png",
			"faction": FACTION_NPP_C,
			"ideology": "socialist",
			"tree_id": "TNO_USA_HAR_shared"
		},
		"SMITH": {
			"id": "USA_Margaret_Chase_Smith",
			"name": "Маргарет Чейз Смит",
			"name_en": "Margaret Chase Smith",
			"portrait_path": "res://assets/gfx/leaders/USA/USA_Margaret_Chase_Smith.png",
			"faction": FACTION_NPP_FR,
			"ideology": "paternalism",
			"tree_id": "TNO_USA_MCS_shared"
		},
		"LEMAY": {
			"id": "USA_Curtis_LeMay",
			"name": "Кёртис ЛеМей",
			"name_en": "Curtis LeMay",
			"portrait_path": "res://assets/gfx/leaders/USA/USA_Curtis_LeMay.png",
			"faction": FACTION_NPP_FR,
			"ideology": "national_socialism",
			"tree_id": "TNO_USA_lemay_shared"
		}
	}

	var pool = candidates_1964 if year <= 1964 else candidates_1968
	if not preferred.is_empty() and pool.has(preferred.to_upper()):
		return pool[preferred.to_upper()]

	# При высокой напряженности гражданских прав Юг голосует за Уоллеса
	if year <= 1964:
		if civil_rights_tension > 60.0:
			return pool["WALLACE"]
		return pool["RFK"]

	return pool["SMITH"]


# ==============================================================================
# ЗАКОНОДАТЕЛЬНЫЙ ПРОЦЕСС (PASSING BILLS & CONGRESS VOTING)
# ==============================================================================

##
## Возвращает список ключевых исторических биллей TNO, доступных для голосования
##
func get_available_bills() -> Array[Dictionary]:
	return [
		{
			"id": "BILL_CIVIL_RIGHTS_1964",
			"title": "Закон о гражданских правах (Civil Rights Act)",
			"description": "Полный федеральный запрет расовой сегрегации в общественных местах и на рабочих местах. Знамя борьбы Мартина Лютера Кинга и прогрессистов.",
			"category": "civil_rights",
			"stances": {
				FACTION_NPP_C: 1.0,  # 100% за
				FACTION_RD_R: 0.65,  # 65% за (северные республиканцы)
				FACTION_RD_D: 0.15,  # 15% за (южные демократы яростно против)
				FACTION_NPP_FR: 0.05,# 5% за
				FACTION_NPP_L: 1.0,
				FACTION_NPP_Y: 0.0
			},
			"cost_pc": 20.0,
			"cost_cap": 2,
			"effects_on_pass": {
				"civil_rights_status": "STRONG",
				"tension_delta": 25.0,
				"radicalization": -5.0,
				"legitimacy": 8.0
			}
		},
		{
			"id": "BILL_GREAT_SOCIETY",
			"title": "Акт программы «Великое общество» // Война с бедностью",
			"description": "Создание федеральных программ Medicare и Medicaid, масштабные субсидии на школьное образование и урбанистическое возрождение.",
			"category": "welfare",
			"stances": {
				FACTION_RD_D: 0.85,
				FACTION_NPP_C: 0.90,
				FACTION_RD_R: 0.25,
				FACTION_NPP_FR: 0.30,
				FACTION_NPP_L: 0.80,
				FACTION_NPP_Y: 0.0
			},
			"cost_pc": 15.0,
			"cost_cap": 1,
			"effects_on_pass": {
				"poverty_rate": -4.0,
				"literacy_rate": 2.5,
				"civilian_expense": 2.0,
				"legitimacy": 5.0
			}
		},
		{
			"id": "BILL_OFN_DEFENSE_APPROPRIATIONS",
			"title": "Оборонные ассигнования ОФН // Военный бюджет",
			"description": "Резкое наращивание военных заказов для сдерживания германского Рейха и японской Сферы, а также снабжение экспедиционного корпуса ОФН в Южной Африке.",
			"category": "military",
			"stances": {
				FACTION_NPP_FR: 0.95,
				FACTION_RD_R: 0.80,
				FACTION_RD_D: 0.60,
				FACTION_NPP_C: 0.20,
				FACTION_NPP_L: 0.0,
				FACTION_NPP_Y: 0.40
			},
			"cost_pc": 10.0,
			"cost_cap": 1,
			"effects_on_pass": {
				"military_factories": 8,
				"weapons_stockpile": 5000,
				"hawkish_frustration": -15.0,
				"military_expense": 3.0
			}
		},
		{
			"id": "BILL_TAX_REFORM",
			"title": "Акт о фискальном стимулировании и дерегуляции бизнеса",
			"description": "Снижение налогов на частные корпорации и фонды для стимулирования промышленного роста и сдерживания государственного долга.",
			"category": "economy",
			"stances": {
				FACTION_RD_R: 0.95,
				FACTION_NPP_FR: 0.70,
				FACTION_RD_D: 0.40,
				FACTION_NPP_C: 0.10,
				FACTION_NPP_L: 0.0,
				FACTION_NPP_Y: 0.30
			},
			"cost_pc": 10.0,
			"cost_cap": 1,
			"effects_on_pass": {
				"tax_rate": -0.03,
				"gdp_growth_boost": 0.015,
				"inflation": -0.005,
				"radicalization": 2.0
			}
		}
	]


##
## Рассчитывает прогноз голосования по биллю (Yeas, Nays, Undecided)
##
func project_bill_votes(bill_id: String) -> Dictionary:
	var target_bill: Dictionary = {}
	for b in get_available_bills():
		if b.get("id", "") == bill_id:
			target_bill = b
			break

	if target_bill.is_empty():
		return {"yeas": 0, "nays": 100, "undecided": 0, "passes": false}

	var stances: Dictionary = target_bill.get("stances", {})
	var yeas = 0
	var nays = 0
	var undecided = 0
	var faction_breakdown: Dictionary = {}

	for f in ALL_FACTIONS:
		var seats = get_seats(f)
		var stance_prob = float(stances.get(f, 0.5))

		# Доля гарантированных голосов за, против и колеблющихся
		var f_yeas = int(round(seats * maxf(0.0, stance_prob - 0.15)))
		var f_nays = int(round(seats * maxf(0.0, (1.0 - stance_prob) - 0.15)))
		var f_undecided = seats - f_yeas - f_nays
		if f_undecided < 0:
			f_undecided = 0
			f_yeas = mini(seats, f_yeas)
			f_nays = seats - f_yeas

		yeas += f_yeas
		nays += f_nays
		undecided += f_undecided

		faction_breakdown[f] = {
			"seats": seats,
			"yeas": f_yeas,
			"nays": f_nays,
			"undecided": f_undecided
		}

	# Учет эффекта лоббирования (Whip votes)
	if active_bill_id == bill_id and whipped_undecided_bonus > 0:
		var swayed = mini(undecided, whipped_undecided_bonus)
		yeas += swayed
		undecided -= swayed

	var threshold = 51
	var cfg = ConfigManager.get_instance()
	if cfg != null and cfg.has_category("us_politics"):
		threshold = cfg.get_int("us_politics", "senate_majority_threshold", 51)

	return {
		"bill_id": bill_id,
		"yeas": yeas,
		"nays": nays,
		"undecided": undecided,
		"threshold": threshold,
		"projected_pass": (yeas >= threshold),
		"faction_breakdown": faction_breakdown
	}


##
## Механика «Склонения сенаторов» (Whip Votes): списывает PC и CAP,
## переманивая колеблющихся сенаторов на сторону Белого Дома
##
func whip_votes(bill_id: String, country_state: CountryState) -> Dictionary:
	var pc_cost = 15.0
	var cap_cost = 1
	var cfg = ConfigManager.get_instance()
	if cfg != null and cfg.has_category("us_politics"):
		pc_cost = cfg.get_float("us_politics", "whip_votes_pc_cost", 15.0)
		cap_cost = cfg.get_int("us_politics", "whip_votes_cap_cost", 1)

	if country_state != null:
		if country_state.political_capital < pc_cost or country_state.current_cap < cap_cost:
			return {"success": false, "reason": "INSUFFICIENT_PC_OR_CAP"}
		country_state.political_capital -= pc_cost
		country_state.current_cap -= cap_cost

	active_bill_id = bill_id
	var projection = project_bill_votes(bill_id)
	var available_undecided = projection.get("undecided", 0)
	var swayed = int(round(float(available_undecided) * 0.75)) + 3
	swayed = mini(available_undecided, swayed)
	whipped_undecided_bonus += swayed

	var updated_proj = project_bill_votes(bill_id)
	return {
		"success": true,
		"swayed": swayed,
		"new_yeas": updated_proj.get("yeas", 0),
		"new_undecided": updated_proj.get("undecided", 0),
		"projected_pass": updated_proj.get("projected_pass", false)
	}


##
## Выносит законопроект на финальное поименное голосование Сената
##
func vote_on_bill(bill_id: String, country_state: CountryState) -> Dictionary:
	var proj = project_bill_votes(bill_id)
	var yeas = proj.get("yeas", 0)
	var nays = proj.get("nays", 0)
	var undecided = proj.get("undecided", 0)

	# На финальном голосовании оставшиеся колеблющиеся голосуют 50/50
	var split_yeas = int(round(undecided * 0.5))
	var split_nays = undecided - split_yeas
	yeas += split_yeas
	nays += split_nays

	var target_bill: Dictionary = {}
	for b in get_available_bills():
		if b.get("id", "") == bill_id:
			target_bill = b
			break

	var passed = (yeas >= 51)
	var effects_applied: Dictionary = {}

	if passed:
		var eff = target_bill.get("effects_on_pass", {})
		effects_applied = eff
		if country_state != null:
			if eff.has("radicalization"):
				country_state.radicalization = clampf(country_state.radicalization + eff["radicalization"], 0.0, 100.0)
			if eff.has("legitimacy"):
				country_state.legitimacy = clampf(country_state.legitimacy + eff["legitimacy"], 0.0, 100.0)
			if eff.has("poverty_rate"):
				country_state.poverty_rate = clampf(country_state.poverty_rate + eff["poverty_rate"], 0.0, 100.0)
			if eff.has("literacy_rate"):
				country_state.literacy_rate = clampf(country_state.literacy_rate + eff["literacy_rate"], 0.0, 100.0)
			if eff.has("military_factories"):
				country_state.military_factories += int(eff["military_factories"])
			if eff.has("weapons_stockpile"):
				country_state.stockpile_weapons += int(eff["weapons_stockpile"])

		if eff.has("civil_rights_status"):
			civil_rights_status = eff["civil_rights_status"]
		if eff.has("tension_delta"):
			civil_rights_tension = clampf(civil_rights_tension + eff["tension_delta"], 0.0, 100.0)
			civil_rights_tension_changed.emit(civil_rights_tension)
	else:
		if country_state != null:
			country_state.legitimacy = maxf(0.0, country_state.legitimacy - 3.0)

	# Сброс лоббирования
	active_bill_id = ""
	whipped_undecided_bonus = 0

	var outcome = {
		"bill_id": bill_id,
		"title": target_bill.get("title", bill_id),
		"passed": passed,
		"yeas": yeas,
		"nays": nays,
		"effects_applied": effects_applied
	}

	bill_vote_completed.emit(bill_id, passed, outcome)
	return outcome


# ==============================================================================
# ПОШАГОВЫЙ ИГРОВОЙ ЦИКЛ (TURN PROCESSING)
# ==============================================================================

##
## Вызывается каждый ход из TurnManager для симуляции электорального цикла США
##
func process_turn(turn_number: int, country_state: CountryState, time_step_mode: String = "weekly") -> Dictionary:
	var report: Dictionary = {
		"midterm_triggered": false,
		"presidential_triggered": false,
		"events": []
	}

	var midterm_interval = 104 if time_step_mode == "weekly" else 24
	var presidential_interval = 208 if time_step_mode == "weekly" else 48

	var cfg = ConfigManager.get_instance()
	if cfg != null and cfg.has_category("us_politics"):
		if time_step_mode == "weekly":
			midterm_interval = cfg.get_int("us_politics", "midterm_interval_turns_weekly", 104)
			presidential_interval = cfg.get_int("us_politics", "presidential_interval_turns_weekly", 208)
		else:
			midterm_interval = cfg.get_int("us_politics", "midterm_interval_turns_monthly", 24)
			presidential_interval = cfg.get_int("us_politics", "presidential_interval_turns_monthly", 48)

	# 1. Проверка наступления выборов в Сенат (каждые 2 года)
	if turn_number > 0 and turn_number % midterm_interval == 0:
		var senate_report = conduct_senate_elections(country_state)
		report["midterm_triggered"] = true
		report["senate_report"] = senate_report

	# 2. Проверка наступления президентских выборов (каждые 4 года)
	if turn_number > 0 and turn_number % presidential_interval == 0:
		var current_year = 1962 + int(float(turn_number) / (52.0 if time_step_mode == "weekly" else 12.0))
		var pres_report = conduct_presidential_election(current_year, country_state)
		report["presidential_triggered"] = true
		report["presidential_report"] = pres_report

	# 3. Дрейф напряженности
	if civil_rights_status == "PENDING":
		civil_rights_tension = clampf(civil_rights_tension + 0.05, 0.0, 100.0)

	return report


# ==============================================================================
# СЕРИАЛИЗАЦИЯ И СОХРАНЕНИЕ (SAVE / LOAD)
# ==============================================================================

func to_dict() -> Dictionary:
	return {
		"senate_seats": senate_seats.duplicate(),
		"current_president": current_president.duplicate(),
		"civil_rights_tension": civil_rights_tension,
		"civil_rights_status": civil_rights_status,
		"hawkish_frustration": hawkish_frustration,
		"last_midterm_turn": last_midterm_turn,
		"last_presidential_election_year": last_presidential_election_year,
		"last_election_report": last_election_report.duplicate()
	}


func from_dict(d: Dictionary) -> void:
	if d.has("senate_seats"):
		var ss = d["senate_seats"]
		for f in ALL_FACTIONS:
			if ss.has(f):
				senate_seats[f] = int(ss[f])

	if d.has("current_president") and d["current_president"] is Dictionary:
		current_president = d["current_president"].duplicate()

	civil_rights_tension = float(d.get("civil_rights_tension", civil_rights_tension))
	civil_rights_status = str(d.get("civil_rights_status", civil_rights_status))
	hawkish_frustration = float(d.get("hawkish_frustration", hawkish_frustration))
	last_midterm_turn = int(d.get("last_midterm_turn", last_midterm_turn))
	last_presidential_election_year = int(d.get("last_presidential_election_year", last_presidential_election_year))
	if d.has("last_election_report") and d["last_election_report"] is Dictionary:
		last_election_report = d["last_election_report"].duplicate()
