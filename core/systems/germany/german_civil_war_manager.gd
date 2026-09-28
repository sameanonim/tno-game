class_name GermanCivilWarManager
extends Node

##
## GermanCivilWarManager: Главный контроллер кампании Германии и Немецкой Гражданской Войны (GCW)
##
## Реализует:
## 1. Фаза 1: Агония Фюрера и борьба за влияние (Ходы 1-12, интриги, вербовка округов, склады).
## 2. Фаза 2: Немецкая Гражданская Война (4 претендента, LUT-карта, фронты в MilitaryEngine,
##    уникальные механики претендентов, Берлин/Шпандау, босс-кризисы Анархии >15 ходов).
## 3. Фаза 3: Восстановление гегемонии и Холодная Война (Toolbox-экономика, DEFCON, прокси-войны).
##

# ==============================================================================
# СИГНАЛЫ
# ==============================================================================
signal phase_changed(new_phase: int, phase_name: String)
signal hitler_died()
signal civil_war_erupted()
signal contender_influence_changed(contender_key: String, new_val: float)
signal contender_mechanic_updated(contender_key: String, mechanic_data: Dictionary)
signal goebbels_crisis_triggered()
signal red_anarchy_triggered()
signal berlin_captured(conquering_tag: String)
signal gcw_concluded(victor_tag: String)
signal tactical_order_resolved(order_type: String, result: Dictionary)
signal defcon_alert(level: int, reason: String)
signal proxy_lend_lease_delivered(proxy_key: String, weapons: int, tanks: int, cash: float)
signal post_cw_reform_updated(contender: String, reform_data: Dictionary)
signal focus_tree_switch_requested(tree_id: String, tree_path: String)

# ==============================================================================
# ПЕРЕЧИСЛЕНИЯ И КОНСТАНТЫ
# ==============================================================================
enum GCWPhase {
	PHASE_1_AGONY = 1,      # Агония Гитлера и подковерные интриги
	PHASE_2_CIVIL_WAR = 2,  # Гражданская война 4 претендентов + кризисы Анархии
	PHASE_3_HEGEMONY = 3    # Восстановление порядка, сверхдержава, Холодная война
}

const TAG_SPEER = "SPE"
const TAG_BORMANN = "BOR"
const TAG_GOERING = "GOR"
const TAG_HEYDRICH = "HEY"
const TAG_GOEBBELS = "GOB"
const TAG_RED_ANARCHY = "DSR"
const TAG_BERLIN_NEUTRAL = "SPN"

# Цвета претендентов для динамической LUT-палитры карты
const COLOR_SPEER = Color(0.85, 0.65, 0.20, 1.0)       # Золотисто-янтарный (Реформаторы)
const COLOR_BORMANN = Color(0.60, 0.45, 0.25, 1.0)     # Коричневый НСДАП (Партийная бюрократия)
const COLOR_GOERING = Color(0.48, 0.52, 0.58, 1.0)     # Стальной серо-голубой (Милитаристы Вермахта)
const COLOR_HEYDRICH = Color(0.18, 0.18, 0.24, 1.0)    # Угольно-черный СС (Бургундская система)
const COLOR_GOEBBELS = Color(0.75, 0.15, 0.15, 1.0)    # Кроваво-багровый (Фольксштурм/Реваншисты)
const COLOR_RED_ANARCHY = Color(0.85, 0.10, 0.10, 1.0) # Алый пролетарский (KPD / DSR)
const COLOR_BERLIN = Color(0.70, 0.70, 0.60, 1.0)      # Нейтральный пепельный (Гарнизон Шпандау)

# ==============================================================================
# СОСТОЯНИЕ МОДУЛЯ
# ==============================================================================
@export var active_phase: GCWPhase = GCWPhase.PHASE_1_AGONY
@export var player_contender_tag: String = TAG_SPEER

# --- ФАЗА 1: ТАЙМЕР И ВЛИЯНИЕ ---
@export var turns_until_hitler_death: int = 12
var faction_influence: Dictionary = {
	"SPEER": 25.0,
	"BORMANN": 25.0,
	"GOERING": 25.0,
	"HEYDRICH": 25.0
}

# Предварительно завербованные военные округа и склады
var recruited_commanders: Dictionary = {
	"SPEER": ["Hans Speidel", "Alexander von Falkenhausen"],
	"BORMANN": ["Ferdinand Schörner (nominal)", "Alfred Jodl"],
	"GOERING": ["Erhard Milch", "Hermann-Bernhard Ramcke"],
	"HEYDRICH": ["Karl Wolff", "Otto Skorzeny"]
}
var secured_depots: Dictionary = {
	"SPEER": 25000,
	"BORMANN": 35000,
	"GOERING": 40000,
	"HEYDRICH": 20000
}

# --- ФАЗА 2: ГРАЖДАНСКАЯ ВОЙНА ---
var gcw_turns_elapsed: int = 0
var gcw_active: bool = false
var berlin_has_fallen: bool = false
var berlin_controller: String = TAG_BERLIN_NEUTRAL

# Уникальные механики претендентов
# Шпеер: Баланс реформ (-100 = диктат Вермахта, +100 = полное подчинение студентам/ОФН, 0 = баланс)
var speer_reform_balance: float = 15.0
# Борман: Партийная паутина (0..100) — бюрократический контроль, перехват снабжения
var bormann_party_web: float = 65.0
# Геринг: Военный долг ($ млрд) и лояльность хунты Шёрнера (0..100)
var goering_war_debt_billions: float = 18.0
var goering_militarist_loyalty: float = 70.0
# Гейдрих: Бургундский саботаж (0..100) и коды ядерных шахт (0..10)
var heydrich_burgundian_influence: float = 80.0
var heydrich_nuclear_codes: int = 1

# Сюжетные босс-кризисы Анархии (>15 ходов)
var goebbels_crisis_active: bool = false
var red_anarchy_active: bool = false
var goebbels_ai: Node = null # GoebbelsCrisisAI

# --- ФАЗА 3: СВЕРХДЕРЖАВА И ХОЛОДНАЯ ВОЙНА ---
var current_defcon: int = 5
var proxy_wars: Dictionary = {
	"south_africa": {
		"name": "Южно-Африканская Война (SAW)",
		"theater_code": "SAW",
		"tension": 45.0,
		"german_volunteers": 0,
		"funded_billions": 0.0,
		"weapons_delivered": 0,
		"tanks_delivered": 0,
		"key_provinces": [12000, 12050],
		"status": "active",
		"description": "ОФН и ЮАР против Бурской Республики и Африка-Шильда (Хюттиг, Шенк, Лорис)."
	},
	"middle_east": {
		"name": "Нефтяной Кризис / Ближний Восток",
		"theater_code": "MEC",
		"tension": 30.0,
		"german_volunteers": 0,
		"funded_billions": 0.0,
		"weapons_delivered": 0,
		"tanks_delivered": 0,
		"key_provinces": [8500, 8520],
		"status": "standby",
		"description": "Борьба за Суэц, нефтяные концессии Ирака и Левант между Италией, Рейхом и баасистами."
	},
	"malaya": {
		"name": "Война в Малайе (Malayan Emergency)",
		"theater_code": "MAL",
		"tension": 40.0,
		"german_volunteers": 0,
		"funded_billions": 0.0,
		"weapons_delivered": 0,
		"tanks_delivered": 0,
		"key_provinces": [11400, 11425],
		"status": "active",
		"description": "Партизанская война МНАО в джунглях против британских колониальных войск и сателлитов Сферы."
	},
	"indonesia": {
		"name": "Гражданская Война в Индонезии (Indonesian War)",
		"theater_code": "INS",
		"tension": 35.0,
		"german_volunteers": 0,
		"funded_billions": 0.0,
		"weapons_delivered": 0,
		"tanks_delivered": 0,
		"key_provinces": [11550, 11580],
		"status": "active",
		"description": "Крах голландского контроля, восстание Свободной Индонезии и вмешательство блоков сверхдержав."
	}
}

var satellite_revolts: Dictionary = {
	"moskowien": {"unrest": 60.0, "pacified": false},
	"ostland": {"unrest": 50.0, "pacified": false},
	"kaukasien": {"unrest": 40.0, "pacified": false}
}

# --- ПОСЛЕВОЕННОЕ УПРАВЛЕНИЕ И РЕФОРМЫ ПРЕТЕНДЕНТОВ ---
var post_cw_victor_tag: String = ""
var post_cw_tree_id: String = ""

# 1. Шпеер и «Банда Четырех» (The Gang of Four & Zollverein)
var speer_g4_schmidt: float = 50.0       # Гельмут Шмидт: Либерализация и диалог с ОФН
var speer_g4_erhard: float = 50.0        # Людвиг Эрхард: Рыночные реформы и Цольферайн
var speer_g4_tresckow: float = 50.0      # Хеннинг фон Тресков: Деполитизация Вермахта
var speer_g4_kiesinger: float = 50.0     # Курт Кизингер: Аппаратный компромисс
var speer_slave_emancipation: float = 15.0 # Прогресс ликвидации рабства (0..100%)
var speer_zollverein_integration: float = 25.0 # Экономический союз Рейха и колоний (0..100%)
var speer_student_unrest: float = 30.0   # Студенческие волнения в университетах (0..100%)

# 2. Борман и «Картотека» (The Card Index & Dismantling Factions)
var bormann_card_index: float = 65.0     # Полнота досье на партийных баронов (0..100%)
var bormann_faction_militarists: float = 45.0 # Лояльность офицерства Вермахта
var bormann_faction_reformers: float = 25.0   # Остатки реформистов Шираха
var bormann_faction_party: float = 75.0       # Лояльность ортодоксальной партийной бюрократии
var bormann_megaprojects_progress: float = 20.0 # Строительство Столицы Мира Германиа

# 3. Геринг и Военная Экономика (War Economy & Fall Plans)
var goering_fall_plan_stage: int = 1     # Стадия Планов Войны: 1 (План А), 2 (План Б), 3 (План С)
var goering_plunder_accumulated: float = 0.0 # Награбленные активы ($ млрд)

# 4. Гейдрих и Бургундский кризис шахт
var heydrich_silos_secured: int = 3      # Захваченные ядерные шахты (цель: 10/10)

# Ссылки на внешние игровые подсистемы
var turn_manager_ref: TurnManager = null
var map_controller_ref: MapController = null
var player_state_ref: CountryState = null

# Распределение ключевых регионов Рейха по претендентам (ID реальных провинций HoI4/TNO)
# 6521 = Welthauptstadt Germania / Берлин (Шпандау)
# Северо-Запад / Рур / Гамбург / Ганновер (Шпеер)
# Бавария / Франкфурт / Нюрнберг / Мюнхен (Борман)
# Пруссия / Силезия / Штеттин (Геринг)
# Эльзас / Саар / Вюртемберг / базы СС (Гейдрих)
# Одер / Бранденбург (Геббельс при Анархии)
# Рурские стачки (Красная Анархия)

const BERLIN_PROVINCE_ID: int = 6521

const GCW_PROVINCES_BERLIN: Array[int] = [6521]
const GCW_PROVINCES_SPEER: Array[int] = [3512, 15821, 15833, 18143, 587, 3488, 3547, 6570, 9347, 241, 247, 374, 3271]
const GCW_PROVINCES_BORMANN: Array[int] = [692, 707, 3688, 3705, 532, 571, 586, 3299, 629, 3508, 3538, 6542]
const GCW_PROVINCES_GOERING: Array[int] = [349, 3340, 6282, 6309, 552, 3283, 3438, 3485, 479, 506, 6464, 6512, 266, 281, 348, 395]
const GCW_PROVINCES_HEYDRICH: Array[int] = [549, 678, 1346, 6529, 694, 3530, 3679, 3692, 617, 3550, 6572]
const GCW_PROVINCES_GOEBBELS: Array[int] = [375, 444, 478, 537, 3207]
const GCW_PROVINCES_RED_ANARCHY: Array[int] = [3512, 15821, 15833, 18143]

var regional_partition: Dictionary = {
	TAG_BERLIN_NEUTRAL: GCW_PROVINCES_BERLIN.duplicate(),
	TAG_SPEER: GCW_PROVINCES_SPEER.duplicate(),
	TAG_BORMANN: GCW_PROVINCES_BORMANN.duplicate(),
	TAG_GOERING: GCW_PROVINCES_GOERING.duplicate(),
	TAG_HEYDRICH: GCW_PROVINCES_HEYDRICH.duplicate()
}


# ==============================================================================
# ИНИЦИАЛИЗАЦИЯ
# ==============================================================================
func _ready() -> void:
	name = "GermanCivilWarManager"


func initialize(tm: TurnManager, mc: MapController, p_state: CountryState) -> void:
	turn_manager_ref = tm
	map_controller_ref = mc
	player_state_ref = p_state
	if player_state_ref != null and player_state_ref.country_tag in [TAG_SPEER, TAG_BORMANN, TAG_GOERING, TAG_HEYDRICH]:
		player_contender_tag = player_state_ref.country_tag

	var cfg = ConfigManager.get_instance()
	if cfg != null and cfg.is_loaded:
		turns_until_hitler_death = cfg.get_int("gcw", "turns_until_hitler_death", turns_until_hitler_death)
		secured_depots = cfg.get_dict("gcw", "initial_depots", secured_depots)

	var loader = ContentLoader.get_instance()
	if loader != null:
		for tag in [TAG_SPEER, TAG_BORMANN, TAG_GOERING, TAG_HEYDRICH]:
			var st = loader.load_country_by_tag(tag)
			if st != null and not st.military_commanders.is_empty():
				var names: Array = []
				for cmd in st.military_commanders:
					names.append(cmd.leader_name)
				recruited_commanders[tag] = names

	_initialize_starting_regions()
	print("[GCWManager] Initialized. Current phase: %d (%s). Player: %s" % [active_phase, get_phase_name(), player_contender_tag])


func get_phase_name() -> String:
	match active_phase:
		GCWPhase.PHASE_1_AGONY: return "АГОНИЯ ФЮРЕРА // БОРЬБА ЗА ВЛИЯНИЕ"
		GCWPhase.PHASE_2_CIVIL_WAR: return "НЕМЕЦКАЯ ГРАЖДАНСКАЯ ВОЙНА (GCW)"
		GCWPhase.PHASE_3_HEGEMONY: return "ВОССТАНОВЛЕНИЕ ГЕГЕМОНИИ // ХОЛОДНАЯ ВОЙНА"
		_: return "UNKNOWN"


# ==============================================================================
# ПОШАГОВЫЙ ЦИКЛ (TURN ADVANCEMENT)
# ==============================================================================
func process_turn(current_turn: int) -> void:
	match active_phase:
		GCWPhase.PHASE_1_AGONY:
			_process_phase_1_turn(current_turn)
		GCWPhase.PHASE_2_CIVIL_WAR:
			_process_phase_2_turn(current_turn)
		GCWPhase.PHASE_3_HEGEMONY:
			_process_phase_3_turn(current_turn)


# ==============================================================================
# ФАЗА 1: АГОНИЯ ФЮРЕРА И ПОДКОФЕРНЫЕ ИНТРИГИ
# ==============================================================================
func _process_phase_1_turn(_turn: int) -> void:
	turns_until_hitler_death -= 1
	print("[GCWManager] Phase 1 Agony: %d turns until Hitler's death." % turns_until_hitler_death)

	# Пассивный дрейф влияния ИИ-фракций
	for k in faction_influence.keys():
		if k != _tag_to_contender_name(player_contender_tag):
			var drift = randf_range(-0.5, 1.5)
			faction_influence[k] = clampf(faction_influence[k] + drift, 5.0, 95.0)

	_normalize_influence()

	if turns_until_hitler_death <= 0:
		trigger_hitler_death()


func _normalize_influence() -> void:
	var total = 0.0
	for v in faction_influence.values():
		total += v
	if total > 0.001:
		for k in faction_influence.keys():
			faction_influence[k] = (faction_influence[k] / total) * 100.0
			contender_influence_changed.emit(k, faction_influence[k])


## Действие игрока: Подкуп регионального гауляйтера (тратит PC)
func bribe_gauleiter(contender: String, region_id: int, pc_cost: float = 25.0) -> bool:
	if active_phase != GCWPhase.PHASE_1_AGONY or player_state_ref == null:
		return false
	if player_state_ref.political_capital < pc_cost:
		return false

	player_state_ref.political_capital -= pc_cost
	faction_influence[contender] = faction_influence.get(contender, 25.0) + 6.0
	_normalize_influence()

	# Предварительное закрепление региона за претендентом
	var tag = _contender_name_to_tag(contender)
	for t in regional_partition.keys():
		regional_partition[t].erase(region_id)
	if not regional_partition.has(tag):
		regional_partition[tag] = []
	regional_partition[tag].append(region_id)

	print("[GCWManager] Bribed Gauleiter of region %d for %s. Influence increased." % [region_id, contender])
	return true


## Действие игрока: Вербовка генерала военного округа (тратит CAP)
func sway_general(contender: String, general_name: String, cap_cost: int = 1) -> bool:
	if active_phase != GCWPhase.PHASE_1_AGONY or player_state_ref == null:
		return false
	if player_state_ref.current_cap < cap_cost:
		return false

	player_state_ref.current_cap -= cap_cost
	if not recruited_commanders.has(contender):
		recruited_commanders[contender] = []
	recruited_commanders[contender].append(general_name)
	faction_influence[contender] = faction_influence.get(contender, 25.0) + 4.5
	_normalize_influence()

	print("[GCWManager] General %s swayed to %s." % [general_name, contender])
	return true


## Действие игрока: Перетягивание армейских складов вооружения (тратит PC & CAP)
func seize_depot(contender: String, weapons_amount: int = 10000) -> bool:
	if active_phase != GCWPhase.PHASE_1_AGONY or player_state_ref == null:
		return false
	if player_state_ref.political_capital < 20.0 or player_state_ref.current_cap < 1:
		return false

	player_state_ref.political_capital -= 20.0
	player_state_ref.current_cap -= 1
	secured_depots[contender] = secured_depots.get(contender, 20000) + weapons_amount
	faction_influence[contender] = faction_influence.get(contender, 25.0) + 3.5
	_normalize_influence()

	print("[GCWManager] Depots seized: +%d weapons for %s." % [weapons_amount, contender])
	return true


# ==============================================================================
# ТРИГГЕР СМЕРТИ ГИТЛЕРА И ВЗРЫВ ГРАЖДАНСКОЙ ВОЙНЫ
# ==============================================================================
func start_civil_war() -> void:
	trigger_hitler_death()


func trigger_hitler_death() -> void:
	if active_phase != GCWPhase.PHASE_1_AGONY:
		return

	active_phase = GCWPhase.PHASE_2_CIVIL_WAR
	gcw_active = true
	gcw_turns_elapsed = 0
	hitler_died.emit()
	phase_changed.emit(active_phase, get_phase_name())

	print("[GCWManager] ADOLF HITLER IS DEAD! The German Civil War erupts.")

	# 1. Создание CountryState для 4 претендентов в мировом стейте
	_spawn_contender_states()

	# 2. Разделение карты по цветам и владельцам в LUT-палитре
	_apply_gcw_map_partition()

	# 3. Регистрация фронтов и оперативных осей в MilitaryEngine
	_spawn_gcw_frontlines()

	# 4. Модальное событие в EventManager
	if turn_manager_ref != null and turn_manager_ref.event_manager != null:
		var ev = GermanyContentBundle.create_event_hitler_death()
		turn_manager_ref.pending_modal_events.push_front(ev)

	civil_war_erupted.emit()


func _spawn_contender_states() -> void:
	if turn_manager_ref == null:
		return

	var world_countries = turn_manager_ref.countries_world_state
	var loader = ContentLoader.get_instance()

	var contender_tags = [TAG_SPEER, TAG_BORMANN, TAG_GOERING, TAG_HEYDRICH, TAG_BERLIN_NEUTRAL]

	for tag in contender_tags:
		var c_state: CountryState = null

		# 1. Попытка динамической загрузки через модульный ContentLoader
		if loader != null:
			c_state = loader.load_country_by_tag(tag)

		# 2. Если это страна игрока, синхронизируем с player_state_ref
		if tag == player_contender_tag and player_state_ref != null:
			if c_state != null:
				player_state_ref.country_tag = tag
				player_state_ref.country_name = c_state.country_name
				player_state_ref.country_color = c_state.country_color
				player_state_ref.manpower_pool = c_state.manpower_pool
				player_state_ref.infantry_weapons_stockpile = c_state.infantry_weapons_stockpile
				player_state_ref.military_factories = c_state.military_factories
				player_state_ref.civilian_factories = c_state.civilian_factories
				player_state_ref.army_readiness = c_state.army_readiness
				player_state_ref.army_morale = c_state.army_morale
			c_state = player_state_ref

		# 3. Аварийный fallback, если файл отсутствует
		if c_state == null:
			c_state = CountryState.new()
			c_state.country_tag = tag
			c_state.country_color = _get_tag_color(tag)
			c_state.manpower_pool = 150000
			c_state.infantry_weapons_stockpile = 25000

		# 4. Динамическая коррекция на баланс влияния фракции перед войной
		var f_key = ""
		match tag:
			TAG_SPEER: f_key = "SPEER"
			TAG_BORMANN: f_key = "BORMANN"
			TAG_GOERING: f_key = "GOERING"
			TAG_HEYDRICH: f_key = "HEYDRICH"

		if not f_key.is_empty() and faction_influence.has(f_key):
			var infl_ratio = faction_influence[f_key] / 25.0
			c_state.manpower_pool = int(float(c_state.manpower_pool) * infl_ratio)
			if secured_depots.has(f_key):
				c_state.infantry_weapons_stockpile = secured_depots[f_key]

		world_countries[tag] = c_state


func _apply_gcw_map_partition() -> void:
	if turn_manager_ref == null:
		return

	var regions = turn_manager_ref.regions_world_state
	for tag in regional_partition.keys():
		var p_ids: Array = regional_partition[tag]
		var col = _get_tag_color(tag)
		for pid in p_ids:
			var reg: RegionData = regions.get(pid, null)
			if reg == null:
				reg = RegionData.new()
				reg.province_id = pid
				reg.province_name = "Сектор #%d" % pid
				regions[pid] = reg
			reg.owner_tag = tag
			reg.unrest = 40.0
			reg.garrison_strength = 60.0
			if pid == BERLIN_PROVINCE_ID:
				reg.province_name = "Германия (Берлин / Рейхстаг)"
				reg.garrison_strength = 90.0

			if map_controller_ref != null:
				map_controller_ref.set_province_owner(pid, tag, col)

	if map_controller_ref != null:
		map_controller_ref.populate_data_lut_from_regions(regions, player_contender_tag)


func _spawn_gcw_frontlines() -> void:
	MilitaryEngine.clear_frontlines()

	# 1. Фронт Шпеер -> Берлин (Ось Рур - Берлин)
	var front_speer = Frontline.new()
	front_speer.front_id = "front_gcw_speer_berlin"
	front_speer.name = "Рурско-Берлинский Оперативный Театр"
	front_speer.attacker_tag = TAG_SPEER
	front_speer.defender_tag = TAG_BERLIN_NEUTRAL

	var axis_speer = OperationalAxis.new()
	axis_speer.axis_id = "axis_ruhr_berlin"
	axis_speer.name = "Направление: Рур -> Ганновер -> Берлин"
	axis_speer.target_region_ids = [3271, BERLIN_PROVINCE_ID]
	axis_speer.assigned_manpower = 65000
	axis_speer.assigned_equipment = {"infantry_weapons": 30000, "heavy_equipment": 450}
	axis_speer.posture = OperationalAxis.Posture.BALANCED
	front_speer.add_axis(axis_speer)
	MilitaryEngine.register_frontline(front_speer)

	# 2. Фронт Борман -> Берлин (Ось Бавария - Лейпциг - Берлин)
	var front_bormann = Frontline.new()
	front_bormann.front_id = "front_gcw_bormann_berlin"
	front_bormann.name = "Южногерманский Театр (Партийный Вал)"
	front_bormann.attacker_tag = TAG_BORMANN
	front_bormann.defender_tag = TAG_BERLIN_NEUTRAL

	var axis_bormann = OperationalAxis.new()
	axis_bormann.axis_id = "axis_bavaria_berlin"
	axis_bormann.name = "Направление: Мюнхен -> Франкен -> Берлин"
	axis_bormann.target_region_ids = [3299, BERLIN_PROVINCE_ID]
	axis_bormann.assigned_manpower = 85000
	axis_bormann.assigned_equipment = {"infantry_weapons": 42000, "heavy_equipment": 380}
	axis_bormann.posture = OperationalAxis.Posture.AGGRESSIVE_BREAKTHROUGH
	front_bormann.add_axis(axis_bormann)
	MilitaryEngine.register_frontline(front_bormann)

	# 3. Фронт Геринг -> Берлин (Ось Пруссия - Померания - Берлин)
	var front_goering = Frontline.new()
	front_goering.front_id = "front_gcw_goering_berlin"
	front_goering.name = "Северо-Восточный Театр Люфтваффе"
	front_goering.attacker_tag = TAG_GOERING
	front_goering.defender_tag = TAG_BERLIN_NEUTRAL

	var axis_goering = OperationalAxis.new()
	axis_goering.axis_id = "axis_prussia_berlin"
	axis_goering.name = "Направление: Кёнигсберг -> Штеттин -> Берлин"
	axis_goering.target_region_ids = [6309, BERLIN_PROVINCE_ID]
	axis_goering.assigned_manpower = 95000
	axis_goering.assigned_equipment = {"infantry_weapons": 48000, "heavy_equipment": 600}
	axis_goering.posture = OperationalAxis.Posture.AGGRESSIVE_BREAKTHROUGH
	front_goering.add_axis(axis_goering)
	MilitaryEngine.register_frontline(front_goering)

	# 4. Фронт Гейдрих -> Франкфурт (Ось Эльзас - Бавария)
	var front_heydrich = Frontline.new()
	front_heydrich.front_id = "front_gcw_heydrich_central"
	front_heydrich.name = "Рейнский Театр СС-Орденштадта"
	front_heydrich.attacker_tag = TAG_HEYDRICH
	front_heydrich.defender_tag = TAG_BORMANN

	var axis_heydrich = OperationalAxis.new()
	axis_heydrich.axis_id = "axis_alsace_frankfurt"
	axis_heydrich.name = "Направление: Штутгарт -> Франкфурт"
	axis_heydrich.target_region_ids = [3679, 707]
	axis_heydrich.assigned_manpower = 45000
	axis_heydrich.assigned_equipment = {"infantry_weapons": 25000, "heavy_equipment": 280}
	axis_heydrich.posture = OperationalAxis.Posture.AGGRESSIVE_BREAKTHROUGH
	front_heydrich.add_axis(axis_heydrich)
	MilitaryEngine.register_frontline(front_heydrich)

	if map_controller_ref != null:
		map_controller_ref.refresh_tactical_frontlines()


# ==============================================================================
# ФАЗА 2: ДИНАМИКА ГРАЖДАНСКОЙ ВОЙНЫ И КРИЗИСЫ АНАРХИИ
# ==============================================================================
func _process_phase_2_turn(_turn: int) -> void:
	gcw_turns_elapsed += 1
	print("[GCWManager] Phase 2 GCW: Turn %d of war." % gcw_turns_elapsed)

	# Обновление уникальных механик претендентов
	_update_contender_mechanics()

	# Проверка контроля над Берлином
	_check_berlin_status()

	# Проверка таймера Анархии (>15 ходов затяжной войны)
	if gcw_turns_elapsed > 15 and not berlin_has_fallen:
		if not goebbels_crisis_active and randf() < 0.65:
			spawn_goebbels_faction()
		elif not red_anarchy_active and randf() < 0.60:
			spawn_red_anarchy()

	# Обновление ИИ Геббельса при активности
	if goebbels_crisis_active and goebbels_ai != null:
		if goebbels_ai.has_method("process_turn"):
			goebbels_ai.process_turn()

	# Проверка победы в объединении
	check_unification_victory()


func _update_contender_mechanics() -> void:
	# 1. Шпеер: Баланс реформ дрейфует под давлением войны
	speer_reform_balance = clampf(speer_reform_balance + randf_range(-3.0, 3.0), -100.0, 100.0)
	contender_mechanic_updated.emit(TAG_SPEER, {"reform_balance": speer_reform_balance})

	# 2. Борман: Партийная паутина истощает вражеские склады (-350 винтовок врагам за ход)
	bormann_party_web = clampf(bormann_party_web + 1.5, 0.0, 100.0)
	if turn_manager_ref != null:
		for tag in [TAG_SPEER, TAG_GOERING, TAG_HEYDRICH]:
			var s: CountryState = turn_manager_ref.countries_world_state.get(tag)
			if s != null:
				s.infantry_weapons_stockpile = maxi(s.infantry_weapons_stockpile - 350, 0)
	contender_mechanic_updated.emit(TAG_BORMANN, {"party_web": bormann_party_web})

	# 3. Геринг: Рост долга за каждый ход блицкрига (+$0.8 млрд) и риск бунта Шёрнера
	goering_war_debt_billions += 0.8
	if goering_war_debt_billions > 30.0:
		goering_militarist_loyalty = clampf(goering_militarist_loyalty - 4.0, 0.0, 100.0)
		if goering_militarist_loyalty < 30.0:
			print("[GCWManager] CAUTION: General Schörner threatens mutiny against Göring!")
	contender_mechanic_updated.emit(TAG_GOERING, {
		"war_debt": goering_war_debt_billions,
		"schorner_loyalty": goering_militarist_loyalty
	})

	# 4. Гейдрих: Охота за ядерными кодами
	if randf() < 0.25 and heydrich_nuclear_codes < 10:
		heydrich_nuclear_codes += 1
		print("[GCWManager] Heydrich SS commandos captured silo nuclear code: %d/10!" % heydrich_nuclear_codes)
	contender_mechanic_updated.emit(TAG_HEYDRICH, {
		"burgundian_influence": heydrich_burgundian_influence,
		"nuclear_codes": heydrich_nuclear_codes
	})


func _check_berlin_status() -> void:
	if turn_manager_ref == null or berlin_has_fallen:
		return

	var berlin_region: RegionData = turn_manager_ref.regions_world_state.get(BERLIN_PROVINCE_ID, null)
	if berlin_region != null and berlin_region.owner_tag != TAG_BERLIN_NEUTRAL:
		berlin_has_fallen = true
		berlin_controller = berlin_region.owner_tag
		print("[GCWManager] BERLIN HAS FALLEN! Victorious controller: %s" % berlin_controller)

		# Награда взявшему Берлин (+25% легитимности, $5.0 млрд казна, +50 PC)
		var conqueror: CountryState = turn_manager_ref.countries_world_state.get(berlin_controller, null)
		if conqueror != null:
			conqueror.legitimacy = clampf(conqueror.legitimacy + 25.0, 0.0, 100.0)
			conqueror.liquid_reserves_billions += 5.0
			conqueror.political_capital += 50.0
			conqueror.army_morale = clampf(conqueror.army_morale + 15.0, 0.0, 100.0)

		berlin_captured.emit(berlin_controller)

		# Создание модального события
		if turn_manager_ref.event_manager != null:
			var ev = GermanyContentBundle.create_event_fall_of_berlin(berlin_controller)
			turn_manager_ref.pending_modal_events.push_front(ev)


## Спавн босс-кризиса Йозефа Геббельса (Реваншистский Фольксштурм)
func spawn_goebbels_faction() -> void:
	if goebbels_crisis_active or turn_manager_ref == null:
		return

	goebbels_crisis_active = true
	print("[GCWManager] BOSS CRISIS: Joseph Goebbels proclaims Total War and mobilizes Volkssturm!")

	# Создание CountryState для Геббельса
	var gob_state = CountryState.new()
	gob_state.country_tag = TAG_GOEBBELS
	gob_state.country_name = "Одерский Рубеж Тотальной Войны (Йозеф Геббельс)"
	gob_state.country_color = COLOR_GOEBBELS
	gob_state.manpower_pool = 120000
	gob_state.infantry_weapons_stockpile = 60000
	gob_state.army_readiness = 85.0
	gob_state.army_morale = 100.0
	gob_state.set_flag("total_war_crusade", true)
	gob_state.set_flag("scorched_earth_active", true)
	turn_manager_ref.countries_world_state[TAG_GOEBBELS] = gob_state

	# Передача восточных регионов (Одер / Бранденбург) Геббельсу
	var regions = turn_manager_ref.regions_world_state
	for pid in GCW_PROVINCES_GOEBBELS:
		var r = regions.get(pid, null)
		if r == null:
			r = RegionData.new()
			r.province_id = pid
			r.province_name = "Одерский Укрепрайон #%d" % pid
			regions[pid] = r
		r.owner_tag = TAG_GOEBBELS
		r.unrest = 80.0
		r.garrison_strength = 95.0
		if map_controller_ref != null:
			map_controller_ref.set_province_owner(pid, TAG_GOEBBELS, COLOR_GOEBBELS)

	# Подключение скрипта GoebbelsCrisisAI
	var script = load("res://core/systems/germany/goebbels_crisis_ai.gd")
	if script != null:
		goebbels_ai = Node.new()
		goebbels_ai.set_script(script)
		goebbels_ai.name = "GoebbelsCrisisAI"
		add_child(goebbels_ai)
		if goebbels_ai.has_method("setup"):
			goebbels_ai.setup(turn_manager_ref, map_controller_ref, gob_state)
		if goebbels_ai.has_signal("sector_scorched"):
			goebbels_ai.connect("sector_scorched", func(pid: int, pname: String):
				print("[GCWManager] WAR CRIME: Goebbels scorched sector %s (#%d)" % [pname, pid])
				if map_controller_ref != null:
					map_controller_ref.add_combat_incident_ping(pid, "raid")
			)
		if goebbels_ai.has_signal("fanatic_offensive_launched"):
			goebbels_ai.connect("fanatic_offensive_launched", func(axis_id: String, bonus: float):
				print("[GCWManager] OFFENSIVE: Volkssturm launched fanatic strike along %s (+%.0f%%)" % [axis_id, (bonus - 1.0) * 100.0])
			)

	# Спавн фронта фанатичной контратаки
	var gob_front = Frontline.new()
	gob_front.front_id = "front_gcw_goebbels_fanatics"
	gob_front.name = "Восточный Вал Тотальной Войны (Геббельс)"
	gob_front.attacker_tag = TAG_GOEBBELS
	gob_front.defender_tag = TAG_BERLIN_NEUTRAL

	var gob_axis = OperationalAxis.new()
	gob_axis.axis_id = "axis_oder_fanatic_surge"
	gob_axis.name = "Прорыв Фольксштурма: Одер -> Берлин"
	gob_axis.target_region_ids = [BERLIN_PROVINCE_ID]
	gob_axis.assigned_manpower = 80000
	gob_axis.assigned_equipment = {"infantry_weapons": 45000, "heavy_equipment": 150}
	gob_axis.posture = OperationalAxis.Posture.AGGRESSIVE_BREAKTHROUGH
	gob_front.add_axis(gob_axis)
	MilitaryEngine.register_frontline(gob_front)

	if map_controller_ref != null:
		map_controller_ref.refresh_tactical_frontlines()

	goebbels_crisis_triggered.emit()

	if turn_manager_ref.event_manager != null:
		var ev = GermanyContentBundle.create_event_goebbels_uprising()
		turn_manager_ref.pending_modal_events.push_front(ev)


## Спавн кризиса Красной Анархии (стачки в Руре, восстание рабочих DSR)
func spawn_red_anarchy() -> void:
	if red_anarchy_active or turn_manager_ref == null:
		return

	red_anarchy_active = true
	print("[GCWManager] CRISIS: Red Anarchy strikes the Ruhr industrial heartland!")

	# Создание CountryState для Красной Анархии
	var red_state = CountryState.new()
	red_state.country_tag = TAG_RED_ANARCHY
	red_state.country_name = "Совет Рабочих и Солдат Рура (KPD / DSR)"
	red_state.country_color = COLOR_RED_ANARCHY
	red_state.manpower_pool = 90000
	red_state.infantry_weapons_stockpile = 35000
	red_state.army_readiness = 60.0
	red_state.army_morale = 95.0
	turn_manager_ref.countries_world_state[TAG_RED_ANARCHY] = red_state

	# Восстание в Руре (провинции Рурского бассейна)
	var regions = turn_manager_ref.regions_world_state
	for pid in GCW_PROVINCES_RED_ANARCHY:
		var r = regions.get(pid, null)
		if r != null:
			r.owner_tag = TAG_RED_ANARCHY
			r.unrest = 90.0
			# Падение выработки IC на 40% из-за стачек
			r.industrial_capacity = maxi(int(float(r.industrial_capacity) * 0.6), 1)
			if map_controller_ref != null:
				map_controller_ref.set_province_owner(pid, TAG_RED_ANARCHY, COLOR_RED_ANARCHY)

	# Спавн фронта Рура
	var red_front = Frontline.new()
	red_front.front_id = "front_gcw_red_anarchy"
	red_front.name = "Фронт Рабочего Восстания (Рур)"
	red_front.attacker_tag = TAG_RED_ANARCHY
	red_front.defender_tag = TAG_SPEER

	var red_axis = OperationalAxis.new()
	red_axis.axis_id = "axis_ruhr_workers_strike"
	red_axis.name = "Вооруженное восстание рабочих Рура"
	red_axis.target_region_ids = [587]
	red_axis.assigned_manpower = 50000
	red_axis.assigned_equipment = {"infantry_weapons": 25000, "heavy_equipment": 80}
	red_axis.posture = OperationalAxis.Posture.AGGRESSIVE_BREAKTHROUGH
	red_front.add_axis(red_axis)
	MilitaryEngine.register_frontline(red_front)

	if map_controller_ref != null:
		map_controller_ref.refresh_tactical_frontlines()

	red_anarchy_triggered.emit()

	if turn_manager_ref.event_manager != null:
		var ev = GermanyContentBundle.create_event_ruhr_strike()
		turn_manager_ref.pending_modal_events.push_front(ev)


# ==============================================================================
# ПРОВЕРКА ПОБЕДЫ В ГРАЖДАНСКОЙ ВОЙНЕ
# ==============================================================================
func check_unification_victory() -> String:
	if active_phase != GCWPhase.PHASE_2_CIVIL_WAR or turn_manager_ref == null:
		return ""

	var regions = turn_manager_ref.regions_world_state
	var counts: Dictionary = {}
	var total_german_cores = 0

	var all_cores: Array[int] = []
	for p_list in regional_partition.values():
		for p in p_list:
			if not all_cores.has(p):
				all_cores.append(p)

	for pid in all_cores:
		var r: RegionData = regions.get(pid, null)
		if r != null:
			total_german_cores += 1
			counts[r.owner_tag] = counts.get(r.owner_tag, 0) + 1

	for tag in [TAG_SPEER, TAG_BORMANN, TAG_GOERING, TAG_HEYDRICH]:
		var controlled = counts.get(tag, 0)
		var ratio = float(controlled) / float(maxi(total_german_cores, 1))

		# Условие триумфа: контроль Берлина (6521) и >= 65% регионов Рейха
		var berlin_controlled = (regions.has(BERLIN_PROVINCE_ID) and regions[BERLIN_PROVINCE_ID].owner_tag == tag)
		if berlin_controlled and ratio >= 0.65:
			_conclude_civil_war(tag)
			return tag

	return ""


func _conclude_civil_war(victor_tag: String) -> void:
	active_phase = GCWPhase.PHASE_3_HEGEMONY
	gcw_active = false
	post_cw_victor_tag = victor_tag
	print("[GCWManager] GERMAN CIVIL WAR CONCLUDED! Hegemon of the Reich: %s" % victor_tag)

	# 1. Определение послевоенного древа фокусов и пути к файлу для победителя
	var post_cw_path: String = ""
	match victor_tag:
		TAG_SPEER:
			post_cw_tree_id = "GER_speer_post_cw_tree"
			post_cw_path = "res://data/countries/GER/directives/tree_GER_speer_post_cw_tree.json"
		TAG_BORMANN:
			post_cw_tree_id = "GER_bormann_post_cw_tree"
			post_cw_path = "res://data/countries/GER/directives/tree_GER_bormann_post_cw_tree.json"
		TAG_GOERING:
			post_cw_tree_id = "GER_Germany_War_Tree"
			post_cw_path = "res://data/countries/GER/directives/tree_GER_Germany_War_Tree.json"
		TAG_HEYDRICH:
			post_cw_tree_id = "GER_heydrich_successor"
			post_cw_path = "res://data/countries/GER/directives/tree_GER_heydrich_successor.json"
		_:
			post_cw_tree_id = "GER_bormann_post_cw_tree"
			post_cw_path = "res://data/countries/GER/directives/tree_GER_bormann_post_cw_tree.json"

	# 2. Очистка фронтов гражданской войны
	MilitaryEngine.clear_frontlines()

	# 3. Перекраска всей Германии в цвет победителя
	if turn_manager_ref != null:
		var col = _get_tag_color(victor_tag)
		var regions = turn_manager_ref.regions_world_state
		for pid in regions.keys():
			var r: RegionData = regions[pid]
			if r != null and (r.owner_tag in [TAG_SPEER, TAG_BORMANN, TAG_GOERING, TAG_HEYDRICH, TAG_GOEBBELS, TAG_RED_ANARCHY, TAG_BERLIN_NEUTRAL, "GER"]):
				r.owner_tag = victor_tag
				r.unrest = 15.0
				r.garrison_strength = 80.0
				if map_controller_ref != null:
					map_controller_ref.set_province_owner(pid, victor_tag, col)

		# 4. Обновление стейта победителя
		var victor_state: CountryState = turn_manager_ref.countries_world_state.get(victor_tag, null)
		if victor_state == null and player_state_ref != null:
			victor_state = player_state_ref

		if victor_state != null:
			victor_state.country_name = "Великогерманский Рейх (%s)" % victor_state.leader_name
			victor_state.legitimacy = 85.0
			victor_state.radicalization = 20.0
			victor_state.liquid_reserves_billions += 15.0
			victor_state.set_flag("germany_unified", true)
			victor_state.set_flag("gcw_victor", victor_tag)
			victor_state.set_flag("post_cw_phase", true)
			victor_state.set_flag("current_focus_tree", post_cw_tree_id)
			victor_state.active_directives.clear()

		# Если игрок играл за претендента или Германию, объединяем тег в GER
		if player_state_ref != null:
			player_state_ref.country_tag = "GER"
			if victor_state != null:
				player_state_ref.country_name = victor_state.country_name
				player_state_ref.leader_name = victor_state.leader_name
				player_state_ref.ruling_ideology = victor_state.ruling_ideology
				player_state_ref.sub_ideology = victor_state.sub_ideology
			player_state_ref.set_flag("germany_unified", true)
			player_state_ref.set_flag("gcw_victor", victor_tag)
			player_state_ref.set_flag("post_cw_phase", true)
			player_state_ref.set_flag("current_focus_tree", post_cw_tree_id)
			player_state_ref.active_directives.clear()
			turn_manager_ref.countries_world_state["GER"] = player_state_ref

		# 5. Автоматическое переключение на послевоенное древо национальных директив
		if turn_manager_ref.focus_stage_controller != null:
			turn_manager_ref.focus_stage_controller.country_tag = "GER"
			turn_manager_ref.focus_stage_controller.switch_focus_tree(post_cw_tree_id, false)
		elif turn_manager_ref.directive_manager != null and not post_cw_path.is_empty():
			_load_and_register_post_cw_directives(post_cw_path)

		# 6. Запуск модального события победы и супер-ивента
		if turn_manager_ref.event_manager != null:
			var vic_ev = GermanyContentBundle.create_event_gcw_victory(victor_tag)
			turn_manager_ref.pending_modal_events.push_front(vic_ev)

		turn_manager_ref.super_event_requested.emit("SUPER_GERMAN_REUNIFICATION")

	if map_controller_ref != null:
		map_controller_ref.refresh_tactical_frontlines()

	# Отправка сигналов переключения фокусного древа и завершения войны
	focus_tree_switch_requested.emit(post_cw_tree_id, post_cw_path)
	gcw_concluded.emit(victor_tag)
	phase_changed.emit(active_phase, get_phase_name())


# ==============================================================================
# ФАЗА 3: ВОССТАНОВЛЕНИЕ ГЕГЕМОНИИ И ХОЛОДНАЯ ВОЙНА (SUPERPOWER SYSTEM)
# ==============================================================================
func _process_phase_3_turn(_turn: int) -> void:
	# 1. Полноценная экономика Toolbox Theory: интеграция Рейхсмарки, реструктуризация долга
	if player_state_ref != null:
		# Восстановление промышленного потенциала после войны
		player_state_ref.civilian_factories = maxi(player_state_ref.civilian_factories + 1, 40)
		player_state_ref.real_gdp_growth = clampf(player_state_ref.real_gdp_growth + 0.001, 0.02, 0.08)

		# 2. Симуляция специфических реформ победителя
		match post_cw_victor_tag:
			TAG_SPEER:
				# Эмансипация рабов снижает радикализацию, но требует осторожного балансирования
				if speer_slave_emancipation > 50.0:
					player_state_ref.radicalization = maxf(player_state_ref.radicalization - 0.5, 5.0)
					player_state_ref.legitimacy = minf(player_state_ref.legitimacy + 0.3, 100.0)
				# Цольферайн приносит дивиденды в бюджет
				var zoll_bonus = (speer_zollverein_integration / 100.0) * 1.5
				player_state_ref.liquid_reserves_billions += zoll_bonus
				# Студенческие волнения растут, если реформы тормозятся
				if speer_reform_balance < 0.0:
					speer_student_unrest = clampf(speer_student_unrest + 1.0, 0.0, 100.0)

			TAG_BORMANN:
				# Картотека укрепляет власть НСДАП
				player_state_ref.political_capital += 1.5
				bormann_megaprojects_progress = clampf(bormann_megaprojects_progress + 0.4, 0.0, 100.0)
				if bormann_megaprojects_progress >= 100.0:
					player_state_ref.legitimacy = minf(player_state_ref.legitimacy + 10.0, 100.0)

			TAG_GOERING:
				# Военный долг растет без грабежа
				goering_war_debt_billions += 0.5
				if goering_war_debt_billions > 40.0:
					player_state_ref.inflation_rate = clampf(player_state_ref.inflation_rate + 0.003, 0.0, 0.30)

			TAG_HEYDRICH:
				# Опасность бургундской диверсии
				if heydrich_silos_secured < 7 and randf() < 0.2:
					heydrich_burgundian_influence = clampf(heydrich_burgundian_influence + 2.0, 0.0, 100.0)

		post_cw_reform_updated.emit(post_cw_victor_tag, get_post_cw_status())

	# 3. Мониторинг прокси-войн
	_process_proxy_wars()


## Выполнение реформы Шпеера
func execute_speer_reform(action_key: String) -> Dictionary:
	if active_phase != GCWPhase.PHASE_3_HEGEMONY or player_state_ref == null:
		return {"success": false, "message": "ОШИБКА: Доступно только в Фазе 3 (Сверхдержава)."}

	var res = {"success": false, "message": ""}
	match action_key:
		"erhard_decree", "decree_erhard":
			if player_state_ref.political_capital >= 25.0 and player_state_ref.current_cap >= 1:
				player_state_ref.political_capital -= 25.0
				player_state_ref.current_cap -= 1
				speer_g4_erhard = clampf(speer_g4_erhard + 12.0, 0.0, 100.0)
				speer_reform_balance = clampf(speer_reform_balance + 8.0, -100.0, 100.0)
				player_state_ref.real_gdp_growth = clampf(player_state_ref.real_gdp_growth + 0.005, 0.01, 0.12)
				res["success"] = true
				res["message"] = "ДЕКРЕТ ЭРХАРДА: Либерализация цен и дерегуляция частного сектора ускорили рост ВВП."
			else:
				res["message"] = "Недостаточно PC (требуется 25) или CAP (требуется 1)."

		"slave_emancipation":
			if player_state_ref.political_capital >= 35.0 and player_state_ref.liquid_reserves_billions >= 5.0:
				player_state_ref.political_capital -= 35.0
				player_state_ref.liquid_reserves_billions -= 5.0
				speer_slave_emancipation = clampf(speer_slave_emancipation + 25.0, 0.0, 100.0)
				speer_reform_balance = clampf(speer_reform_balance + 15.0, -100.0, 100.0)
				player_state_ref.radicalization = maxf(player_state_ref.radicalization - 12.0, 0.0)
				player_state_ref.civilian_factories += 6
				res["success"] = true
				res["message"] = "ЛИКВИДАЦИЯ РАБСТВА: Миллионы остарбайтеров переведены в статус оплачиваемых рабочих."
			else:
				res["message"] = "Недостаточно PC (35) или ликвидных резервов ($5.0B)."

		"tresckow_wehrmacht", "wehrmacht_reform":
			if player_state_ref.political_capital >= 30.0 and player_state_ref.current_cap >= 1:
				player_state_ref.political_capital -= 30.0
				player_state_ref.current_cap -= 1
				speer_g4_tresckow = clampf(speer_g4_tresckow + 15.0, 0.0, 100.0)
				player_state_ref.army_professionalism = clampf(player_state_ref.army_professionalism + 0.12, 0.0, 1.0)
				res["success"] = true
				res["message"] = "РЕФОРМА ТРЕСКОВА: Вермахт очищен от партийных комиссаров и преобразован в профессиональную армию."
			else:
				res["message"] = "Недостаточно PC (30) или CAP (1)."

		"zollverein_expansion", "zollverein_expand":
			if player_state_ref.liquid_reserves_billions >= 8.0:
				player_state_ref.liquid_reserves_billions -= 8.0
				speer_zollverein_integration = clampf(speer_zollverein_integration + 20.0, 0.0, 100.0)
				res["success"] = true
				res["message"] = "ЦОЛЬФЕРАЙН: Подписаны пакты о таможенном союзе с восточными Рейхскомиссариатами."
			else:
				res["message"] = "Недостаточно валютных резервов ($8.0B)."

		_:
			res["message"] = "Неизвестная инициатива реформ."

	if res["success"]:
		post_cw_reform_updated.emit(TAG_SPEER, get_post_cw_status())
	return res


## Выполнение распоряжения Бормана
func execute_bormann_action(action_key: String) -> Dictionary:
	if active_phase != GCWPhase.PHASE_3_HEGEMONY or player_state_ref == null:
		return {"success": false, "message": "ОШИБКА: Доступно только в Фазе 3 (Сверхдержава)."}

	var res = {"success": false, "message": ""}
	match action_key:
		"card_index_purge", "purge_card_index":
			if player_state_ref.political_capital >= 30.0 and player_state_ref.current_cap >= 1:
				player_state_ref.political_capital -= 30.0
				player_state_ref.current_cap -= 1
				bormann_card_index = clampf(bormann_card_index + 10.0, 0.0, 100.0)
				bormann_faction_militarists = maxf(bormann_faction_militarists - 12.0, 0.0)
				bormann_faction_reformers = maxf(bormann_faction_reformers - 10.0, 0.0)
				bormann_faction_party = clampf(bormann_faction_party + 8.0, 0.0, 100.0)
				res["success"] = true
				res["message"] = "КАРТОТЕКА: Компромат на гауляйтеров пущен в ход. Фракционеры отстранены от должностей."
			else:
				res["message"] = "Недостаточно PC (30) или CAP (1)."

		"megaproject_build", "megaprojects_germania":
			if player_state_ref.liquid_reserves_billions >= 6.0:
				player_state_ref.liquid_reserves_billions -= 6.0
				bormann_megaprojects_progress = clampf(bormann_megaprojects_progress + 18.0, 0.0, 100.0)
				player_state_ref.legitimacy = clampf(player_state_ref.legitimacy + 6.0, 0.0, 100.0)
				res["success"] = true
				res["message"] = "СТОЛИЦА МИРА ГЕРМАНИА: Возведение Зала Народа и триумфальных монументов продолжается."
			else:
				res["message"] = "Недостаточно валютных резервов ($6.0B)."

		"integrate_rk", "centralize_rks":
			if player_state_ref.political_capital >= 40.0:
				player_state_ref.political_capital -= 40.0
				player_state_ref.civilian_factories += 4
				player_state_ref.military_factories += 3
				res["success"] = true
				res["message"] = "ЦЕНТРАЛИЗАЦИЯ: Автономия колониальных баронов ликвидирована. Доходы поступают напрямую в Берлин."
			else:
				res["message"] = "Недостаточно PC (40)."

		_:
			res["message"] = "Неизвестное распоряжение."

	if res["success"]:
		post_cw_reform_updated.emit(TAG_BORMANN, get_post_cw_status())
	return res


## Регистрация и загрузка послевоенных директив напрямую из JSON
func _load_and_register_post_cw_directives(tree_path: String) -> void:
	if not FileAccess.file_exists(tree_path) or turn_manager_ref == null or turn_manager_ref.directive_manager == null:
		return

	var file = FileAccess.open(tree_path, FileAccess.READ)
	if file == null:
		return

	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK or not (json.data is Dictionary):
		file.close()
		return
	file.close()

	var dm = turn_manager_ref.directive_manager
	dm.all_directives.clear()

	var nodes_dict = json.data.get("nodes", {})
	if nodes_dict is Dictionary:
		for nid in nodes_dict.keys():
			var node_data = nodes_dict[nid]
			if node_data is Dictionary:
				var res = DirectiveResource.from_dict(node_data)
				dm.register_directive(res)

	elif json.data.has("directives") and json.data["directives"] is Array:
		for node_data in json.data["directives"]:
			if node_data is Dictionary:
				var res = DirectiveResource.from_dict(node_data)
				dm.register_directive(res)

	print("[GCWManager] Зарегистрировано %d послевоенных директив из [%s]." % [dm.all_directives.size(), tree_path])


## Сводка текущего состояния послевоенных реформ
func get_post_cw_status() -> Dictionary:
	return {
		"victor_tag": post_cw_victor_tag,
		"tree_id": post_cw_tree_id,
		"speer": {
			"reform_balance": speer_reform_balance,
			"schmidt": speer_g4_schmidt,
			"erhard": speer_g4_erhard,
			"tresckow": speer_g4_tresckow,
			"kiesinger": speer_g4_kiesinger,
			"slave_emancipation": speer_slave_emancipation,
			"zollverein_integration": speer_zollverein_integration,
			"student_unrest": speer_student_unrest
		},
		"bormann": {
			"card_index": bormann_card_index,
			"militarists": bormann_faction_militarists,
			"reformers": bormann_faction_reformers,
			"party": bormann_faction_party,
			"megaprojects": bormann_megaprojects_progress
		},
		"goering": {
			"war_debt": goering_war_debt_billions,
			"fall_stage": goering_fall_plan_stage,
			"plunder": goering_plunder_accumulated
		},
		"heydrich": {
			"silos_secured": heydrich_silos_secured,
			"burgundian_influence": heydrich_burgundian_influence
		}
	}


func _process_proxy_wars() -> void:
	for p_key in proxy_wars.keys():
		var p_data = proxy_wars[p_key]
		if p_data["status"] == "active":
			p_data["tension"] = clampf(p_data["tension"] + randf_range(-2.0, 4.0), 0.0, 100.0)
			# Если напряженность критическая (>85), шкала DEFCON сдвигается вниз (к ядерному армагеддону)
			if p_data["tension"] > 85.0 and current_defcon > 2:
				adjust_defcon(current_defcon - 1, "Эскалация в конфликте: %s" % p_data["name"])


## Отправка добровольцев или военного транша в прокси-войну
func send_proxy_aid(proxy_key: String, volunteer_divisions: int, cash_billions: float) -> bool:
	if active_phase != GCWPhase.PHASE_3_HEGEMONY or player_state_ref == null:
		return false
	if not proxy_wars.has(proxy_key):
		return false

	var cost_manpower = volunteer_divisions * 10000
	var cost_weapons = volunteer_divisions * 2500
	var cost_tanks = volunteer_divisions * 50

	if player_state_ref.manpower_pool < cost_manpower or player_state_ref.liquid_reserves_billions < cash_billions:
		return false
	if player_state_ref.infantry_weapons_stockpile < cost_weapons:
		return false

	player_state_ref.manpower_pool -= cost_manpower
	player_state_ref.infantry_weapons_stockpile -= cost_weapons
	if player_state_ref.heavy_equipment_stockpile >= cost_tanks:
		player_state_ref.heavy_equipment_stockpile -= cost_tanks
	player_state_ref.liquid_reserves_billions -= cash_billions

	var p = proxy_wars[proxy_key]
	p["german_volunteers"] += volunteer_divisions
	p["weapons_delivered"] += cost_weapons
	p["tanks_delivered"] += cost_tanks
	p["funded_billions"] += cash_billions
	p["tension"] = maxf(0.0, p["tension"] - (float(volunteer_divisions) * 8.0 + cash_billions * 5.0))

	player_state_ref.legitimacy = clampf(player_state_ref.legitimacy + 2.0, 0.0, 100.0)

	# Развертывание ТВД в MilitaryEngine при отправке контингента
	if turn_manager_ref != null:
		var front = MilitaryEngine.deploy_proxy_theater(proxy_key, player_state_ref.country_tag, turn_manager_ref.countries_world_state)
		if front != null and front.axes.size() > 0:
			var ax = front.axes[0]
			ax.assigned_manpower += cost_manpower
			ax.assigned_equipment["infantry_weapons"] = ax.assigned_equipment.get("infantry_weapons", 0) + cost_weapons
			ax.assigned_equipment["heavy_equipment"] = ax.assigned_equipment.get("heavy_equipment", 0) + cost_tanks

	print("[GCWManager] Proxy aid dispatched to %s: %d divs, $%.2fB." % [p["name"], volunteer_divisions, cash_billions])
	return true


## Отправка эшелона ленд-лиза (винтовки, бронетехника со складов ВПК + валютный транш)
func send_proxy_lend_lease(proxy_key: String, weapons: int, tanks: int, cash_billions: float) -> Dictionary:
	if active_phase != GCWPhase.PHASE_3_HEGEMONY or player_state_ref == null:
		return {"success": false, "message": "ОШИБКА: Доступно только в Фазе 3 (Сверхдержава)."}
	if not proxy_wars.has(proxy_key):
		return {"success": false, "message": "ОШИБКА: Театр прокси-войны не найден."}

	if player_state_ref.infantry_weapons_stockpile < weapons:
		return {"success": false, "message": "ОШИБКА: Недостаточно стрелкового оружия (%d/%d)." % [player_state_ref.infantry_weapons_stockpile, weapons]}
	if player_state_ref.heavy_equipment_stockpile < tanks:
		return {"success": false, "message": "ОШИБКА: Недостаточно бронетехники (%d/%d)." % [player_state_ref.heavy_equipment_stockpile, tanks]}
	if player_state_ref.liquid_reserves_billions < cash_billions:
		return {"success": false, "message": "ОШИБКА: Недостаточно ликвидных резервов ($%.2fB/$%.2fB)." % [player_state_ref.liquid_reserves_billions, cash_billions]}

	player_state_ref.infantry_weapons_stockpile -= weapons
	player_state_ref.heavy_equipment_stockpile -= tanks
	player_state_ref.liquid_reserves_billions -= cash_billions

	var p = proxy_wars[proxy_key]
	p["weapons_delivered"] += weapons
	p["tanks_delivered"] += tanks
	p["funded_billions"] += cash_billions

	var relief = float(weapons) * 0.002 + float(tanks) * 0.04 + cash_billions * 4.0
	p["tension"] = maxf(0.0, p["tension"] - relief)

	player_state_ref.legitimacy = clampf(player_state_ref.legitimacy + 1.5, 0.0, 100.0)
	player_state_ref.war_support_percent = clampf(player_state_ref.war_support_percent + 1.0, 0.0, 100.0)

	# Развертывание ТВД в MilitaryEngine при отправке ленд-лиза
	if turn_manager_ref != null:
		var front = MilitaryEngine.deploy_proxy_theater(proxy_key, player_state_ref.country_tag, turn_manager_ref.countries_world_state)
		if front != null and front.axes.size() > 0:
			var ax = front.axes[0]
			ax.assigned_equipment["infantry_weapons"] = ax.assigned_equipment.get("infantry_weapons", 0) + weapons
			ax.assigned_equipment["heavy_equipment"] = ax.assigned_equipment.get("heavy_equipment", 0) + tanks

	proxy_lend_lease_delivered.emit(proxy_key, weapons, tanks, cash_billions)
	print("[GCWManager] Lend-Lease dispatched to %s: %d rifles, %d tanks, $%.2fB." % [p["name"], weapons, tanks, cash_billions])
	return {
		"success": true,
		"message": "Эшелон ленд-лиза успешно доставлен в %s: %d винтовок, %d танков, $%.2fB." % [p["name"], weapons, tanks, cash_billions]
	}



## Изменение шкалы DEFCON
func adjust_defcon(new_level: int, reason: String) -> void:
	current_defcon = clampi(new_level, 1, 5)
	if player_state_ref != null:
		player_state_ref.set_flag("defcon_level", current_defcon)

	defcon_alert.emit(current_defcon, reason)
	print("[GCWManager] DEFCON LEVEL CHANGED: DEFCON %d! Reason: %s" % [current_defcon, reason])

	if current_defcon == 1 and turn_manager_ref != null and turn_manager_ref.event_manager != null:
		# Ядерный армагеддон
		var nuke_ev = GameEvent.new()
		nuke_ev.event_id = "event_nuclear_midnight"
		nuke_ev.title = "DEFCON 1 // ЯДЕРНАЯ ПОЛНОЧЬ"
		nuke_ev.classification = "[TOP SECRET // ULTRA BRINKMANSHIP]"
		nuke_ev.description = "Красные телефоны замолчали. Спутники раннего предупреждения засекли массовый пуск МБР. Цивилизация погружается в ядерный пепел."
		nuke_ev.is_modal = true
		nuke_ev.options = [{"text": "Так проходит мирская слава... [GAME OVER]", "effects": {"SET_FLAG": "thermonuclear_war"}}]
		turn_manager_ref.pending_modal_events.push_front(nuke_ev)


# ==============================================================================
# ТАКТИЧЕСКИЕ ПРИКАЗЫ НА ХОД (1 CAP)
# ==============================================================================
func execute_tactical_order(order_type: String, target_axis_id: String = "") -> Dictionary:
	var result = {"success": false, "order_type": order_type, "message": ""}
	if player_state_ref == null or player_state_ref.current_cap < 1:
		result["message"] = "Отказ: Недостаточно очков кабинета (требуется 1 CAP)!"
		return result

	var axis: OperationalAxis = null
	for front in MilitaryEngine.get_active_frontlines():
		for ax in front.axes:
			if ax.axis_id == target_axis_id or target_axis_id.is_empty():
				axis = ax
				break
		if axis != null:
			break

	player_state_ref.current_cap -= 1

	match order_type:
		"panzer_breakthrough":
			# Танковый прорыв: резкий скачок прогресса, трата техники
			if player_state_ref.heavy_equipment_stockpile >= 100:
				player_state_ref.heavy_equipment_stockpile -= 100
				if axis != null:
					axis.progress = clampf(axis.progress + 15.0, 0.0, 100.0)
					axis.posture = OperationalAxis.Posture.AGGRESSIVE_BREAKTHROUGH
				result["success"] = true
				result["message"] = "ПРИКАЗ ИСПОЛНЕН: Танковые клинья взломали оборону (+15% прогресс, -100 танков)."
			else:
				result["message"] = "Срыв атаки: нехватка тяжелой бронетехники на складах!"

		"entrenched_defense":
			# Эшелонированная оборона
			if axis != null:
				axis.posture = OperationalAxis.Posture.DEFENSIVE
			player_state_ref.army_readiness = clampf(player_state_ref.army_readiness + 5.0, 0.0, 100.0)
			result["success"] = true
			result["message"] = "ПРИКАЗ ИСПОЛНЕН: Войска окопались на рубежах. Боеготовность +5%, потери снижены."

		"luftwaffe_strike":
			# Авиаудар Люфтваффе: подавление узлов врага
			if player_state_ref.liquid_reserves_billions >= 0.15:
				player_state_ref.liquid_reserves_billions -= 0.15
				if axis != null:
					axis.progress = clampf(axis.progress + 10.0, 0.0, 100.0)
					axis.is_stalled = false
				result["success"] = true
				result["message"] = "ПРИКАЗ ИСПОЛНЕН: Штуки и бомбардировщики смели укрепления врага (-$0.15B, +10% прогресс)."
			else:
				result["message"] = "Отказ: Казна истощена для закупки авиатоплива!"

		"ss_sabotage":
			# Диверсия в тылу СС: срыв логистики врага
			if player_state_ref.political_capital >= 15.0:
				player_state_ref.political_capital -= 15.0
				if axis != null:
					axis.is_stalled = true
				result["success"] = true
				result["message"] = "ПРИКАЗ ИСПОЛНЕН: Спецгруппы подорвали мосты и эшелоны врага. Наступление врага сорвано."
			else:
				result["message"] = "Отказ: Недостаточно политического капитала для санкционирования спецоперации!"

	tactical_order_resolved.emit(order_type, result)
	return result


# ==============================================================================
# ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ
# ==============================================================================
func _initialize_starting_regions() -> void:
	if turn_manager_ref == null:
		return
	var regions = turn_manager_ref.regions_world_state
	var all_cores: Array[int] = []
	for p_list in regional_partition.values():
		for p in p_list:
			if not all_cores.has(p):
				all_cores.append(p)

	# Инициализация провинций Германии в Фазе 1 под единым тегом GER
	for pid in all_cores:
		if not regions.has(pid):
			var r = RegionData.new()
			r.province_id = pid
			r.province_name = "Рейхсгау #%d" % pid
			r.owner_tag = "GER"
			r.industrial_capacity = randi_range(3, 8)
			r.civilian_infrastructure = randi_range(4, 9)
			r.unrest = 15.0
			r.garrison_strength = 80.0
			regions[pid] = r


func _tag_to_contender_name(tag: String) -> String:
	match tag:
		TAG_SPEER: return "SPEER"
		TAG_BORMANN: return "BORMANN"
		TAG_GOERING: return "GOERING"
		TAG_HEYDRICH: return "HEYDRICH"
		_: return "SPEER"


func _contender_name_to_tag(name_str: String) -> String:
	match name_str.to_upper():
		"SPEER": return TAG_SPEER
		"BORMANN": return TAG_BORMANN
		"GOERING": return TAG_GOERING
		"HEYDRICH": return TAG_HEYDRICH
		_: return TAG_SPEER


func _get_tag_color(tag: String) -> Color:
	match tag:
		TAG_SPEER: return COLOR_SPEER
		TAG_BORMANN: return COLOR_BORMANN
		TAG_GOERING: return COLOR_GOERING
		TAG_HEYDRICH: return COLOR_HEYDRICH
		TAG_GOEBBELS: return COLOR_GOEBBELS
		TAG_RED_ANARCHY: return COLOR_RED_ANARCHY
		TAG_BERLIN_NEUTRAL: return COLOR_BERLIN
		_: return Color(0.4, 0.4, 0.4, 1.0)
