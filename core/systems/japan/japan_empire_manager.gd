class_name JapanEmpireManager
extends Node

##
## JapanEmpireManager: Главный контроллер Японской Империи (Empire of Japan / JAP)
## 
## Модуль реализует ключевые уникальные механики TNO для Японии:
## 1. Крах корпорации «Ясуда» (Yasuda Crisis):
##    - Финансовая паника на Токийской фондовой бирже (TSE Index), девальвация иены.
##    - Падение доверия к кабинету министров Ино Хироя.
##    - Расследование коррупции, сценарии разрешения (санация/bailout, национализация, антикоррупционный суд).
## 2. Палата Пэров (Kizokuin) и Палата Представителей (Diet):
##    - Борьба 4 фракций: Реформаторы (Такаги), Финансисты (Икэда), Технократы (Кая), Милитаристы (ИЯА).
##    - Выборы премьер-министра и автоматическая смена древа директив.
## 3. Борьба четырех великих Дзайбацу (Mitsui, Mitsubishi, Sumitomo, Yasuda).
## 4. Соперничество Императорской Армии (IJA) и Флота (IJN).
## 5. Управление колониальной Великой Восточноазиатской Сферой Сопроцветания (GEACPS).
##

signal yasuda_crisis_triggered(severity: float)
signal yasuda_crisis_resolved(resolution_type: String)
signal prime_minister_elected(leader_name: String, tree_id: String)
signal zaibatsu_influence_changed(zaibatsu_key: String, new_val: float)
signal ija_ijn_balance_shifted(new_balance: float)
signal diet_vote_called(bill_id: String, passed: bool)
signal sphere_incident_reported(member_tag: String, message: String)

enum YasudaPhase {
	NORMAL = 0,         # Предкризисный период (Ходы 1-2)
	STOCK_CRASH = 1,    # Паника на Токийской бирже (TSE Crash)
	INVESTIGATION = 2,  # Расследование коррупции и правительственный кризис
	RESOLVED = 3        # Кризис преодолён новым кабинетом
}

# --- КРИЗИС КОРПОРАЦИИ «ЯСУДА» И БИРЖА (TSE) ---
@export var yasuda_phase: YasudaPhase = YasudaPhase.NORMAL
var tse_index: float = 1000.0             # Индекс Токийской биржи (базовый 1000, при крахе падает до ~450)
var yasuda_corruption_evidence: float = 0.0 # Улики спецпрокуратуры (0..100)
var ino_cabinet_approval: float = 65.0      # Доверие к премьеру Ино Хироя (0..100)
var current_prime_minister: String = "Хироя Ино"
var active_prime_minister_key: String = "INO"

# --- ПАЛАТА ПЭРОВ И ДАЙЭТ (KIZOKUIN & DIET) ---
# 4 ключевые политические силы Японии
var factions_diet: Dictionary = {
	"TAKAGI": {
		"name": "Реформисты Тэйсэйкай (Такаги Сокити)",
		"leader": "Такаги Сокити",
		"seats": 110,
		"loyalty": 55.0,
		"tree_id": "TNO_Japan_PMTakagi_shared",
		"tree_path": "res://data/countries/JAP/directives/trees/TNO_Japan_PMTakagi_shared.json",
		"desc": "Либерализация режима, искоренение коррупции, опора на умеренных адмиралов флота."
	},
	"IKEDA": {
		"name": "Финансовая бюрократия (Икэда Хаято)",
		"leader": "Икэда Хаято",
		"seats": 145,
		"loyalty": 60.0,
		"tree_id": "TNO_Japan_PMIkeda_shared",
		"tree_path": "res://data/countries/JAP/directives/trees/TNO_Japan_PMIkeda_shared.json",
		"desc": "Союз с крупными дзайбацу, дерегуляция, экономический прагматизм."
	},
	"KAYA": {
		"name": "Технократы Госплана (Кая Окинори)",
		"leader": "Кая Окинори",
		"seats": 95,
		"loyalty": 50.0,
		"tree_id": "TNO_Japan_PMKaya_shared",
		"tree_path": "res://data/countries/JAP/directives/trees/TNO_Japan_PMKaya_shared.json",
		"desc": "Жесткое государственное планирование, модернизация ВПК, подавление олигархов."
	},
	"MILITARISTS": {
		"name": "Военная хунта (ИЯА / Тосэйха / Киси)",
		"leader": "Нобусукэ Киси",
		"seats": 116,
		"loyalty": 40.0,
		"tree_id": "TNO_Japan_shared",
		"tree_path": "res://data/countries/JAP/directives/trees/TNO_Japan_shared.json",
		"desc": "Тотальный контроль армии, реваншизм, экспансия в Китае."
	}
}

# --- БОРЬБА ВЕЛИКИХ ДЗАЙБАЦУ (THE BIG FOUR) ---
var zaibatsu_influence: Dictionary = {
	"MITSUI": 32.0,      # Тесные связи с Флотом и легкой индустрией
	"MITSUBISHI": 35.0,  # Тесные связи с Армией, авиация и танкостроение
	"SUMITOMO": 20.0,    # Горнодобыча, металлургия, Манчжурия
	"YASUDA": 13.0       # Банковский сектор, недвижимость (эпицентр кризиса)
}

# --- СОПЕРНИЧЕСТВО АРМИИ И ФЛОТА (IJA vs IJN) ---
# -100.0 = Тотальный диктат Армии (IJA), +100.0 = Тотальный диктат Флота (IJN), 0 = Равновесие
var ija_ijn_balance: float = -10.0
var army_steel_quota: float = 55.0 # % стали Армии
var navy_oil_quota: float = 60.0   # % топлива Флоту

# --- ВЕЛИКАЯ ВОСТОЧНОАЗИАТСКАЯ СФЕРА СОПРОЦВЕТАНИЯ (GEACPS) ---
var sphere_members: Dictionary = {
	"CHI": {"name": "Китай (Правительство Ван Цзинвэя)", "loyalty": 55.0, "tribute_factories": 8, "unrest": 35.0},
	"MAN": {"name": "Маньчжоу-Го (Империя Пу И)", "loyalty": 80.0, "tribute_factories": 12, "unrest": 15.0},
	"GNG": {"name": "Гуандун (Корпоративный анклав)", "loyalty": 75.0, "tribute_factories": 14, "unrest": 20.0},
	"INS": {"name": "Индонезия (Сукарно)", "loyalty": 60.0, "tribute_factories": 6, "unrest": 40.0},
	"THA": {"name": "Таиланд (Королевство Сиам)", "loyalty": 70.0, "tribute_factories": 4, "unrest": 10.0}
}

var turn_manager_ref: TurnManager = null
var player_state_ref: CountryState = null


func _ready() -> void:
	name = "JapanEmpireManager"


func initialize(tm: TurnManager, p_state: CountryState) -> void:
	turn_manager_ref = tm
	player_state_ref = p_state
	print("[JapanEmpireManager] Инициализирован для Японской Империи. Премьер: %s" % current_prime_minister)


# ==============================================================================
# ПОШАГОВЫЙ ЦИКЛ СИМУЛЯЦИИ (Turn Process)
# ==============================================================================
func process_turn(turn_num: int, p_state: CountryState = null, _world_states: Dictionary = {}) -> void:
	if p_state != null:
		player_state_ref = p_state

	# 1. Запуск или развитие Кризиса Ясуда
	_process_yasuda_turn(turn_num)

	# 2. Балансировка Армии и Флота
	_process_military_rivalry_turn()

	# 3. Доходы и стабильность Сферы Сопроцветания
	_process_sphere_turn()


func _process_yasuda_turn(turn_num: int) -> void:
	match yasuda_phase:
		YasudaPhase.NORMAL:
			# На 2-3 ходу взрывается катастрофа Ясуда
			if turn_num >= 2:
				trigger_yasuda_crash()

		YasudaPhase.STOCK_CRASH:
			# Падение биржи продолжается
			tse_index = clampf(tse_index - randf_range(35.0, 75.0), 380.0, 1000.0)
			ino_cabinet_approval = clampf(ino_cabinet_approval - 8.0, 5.0, 100.0)
			if player_state_ref != null:
				player_state_ref.inflation_rate = clampf(player_state_ref.inflation_rate + 0.008, 0.0, 0.35)
				player_state_ref.radicalization = clampf(player_state_ref.radicalization + 2.5, 0.0, 100.0)

			# Если одобрение кабинета упало ниже 25%, начинается открытое расследование
			if ino_cabinet_approval <= 30.0:
				yasuda_phase = YasudaPhase.INVESTIGATION
				print("[JapanEmpireManager] Кабинет Ино потерял доверие. Начинается парламентское расследование скандала Ясуда.")

		YasudaPhase.INVESTIGATION:
			# Накопление улик
			yasuda_corruption_evidence = clampf(yasuda_corruption_evidence + randf_range(3.0, 8.0), 0.0, 100.0)
			if ino_cabinet_approval <= 12.0 and active_prime_minister_key == "INO":
				# Крах правительства Ино
				_force_cabinet_resignation()

		YasudaPhase.RESOLVED:
			# Постепенное восстановление биржи
			tse_index = clampf(tse_index + randf_range(5.0, 15.0), 400.0, 950.0)
			if player_state_ref != null:
				player_state_ref.inflation_rate = maxf(player_state_ref.inflation_rate - 0.002, 0.03)


func trigger_yasuda_crash() -> void:
	yasuda_phase = YasudaPhase.STOCK_CRASH
	tse_index = 580.0
	ino_cabinet_approval = 40.0
	zaibatsu_influence["YASUDA"] = 5.0
	zaibatsu_influence_changed.emit("YASUDA", 5.0)

	if player_state_ref != null:
		player_state_ref.liquid_reserves_billions = maxf(player_state_ref.liquid_reserves_billions - 12.0, 2.0)
		player_state_ref.real_gdp_growth = clampf(player_state_ref.real_gdp_growth - 0.025, -0.05, 0.05)
		player_state_ref.set_flag("yasuda_crisis_active", true)

	print("[JapanEmpireManager] КАТАСТРОФА КОРПОРАЦИИ ЯСУДА! Токийская фондовая биржа обвалилась до %0.1f." % tse_index)
	yasuda_crisis_triggered.emit(tse_index)

	if turn_manager_ref != null:
		turn_manager_ref.super_event_requested.emit("SUPER_YASUDA_CRISIS")
		if turn_manager_ref.event_manager != null:
			var ev = _create_event_yasuda_crash()
			turn_manager_ref.pending_modal_events.push_front(ev)


func _force_cabinet_resignation() -> void:
	print("[JapanEmpireManager] Премьер-министр Хироя Ино уходит в отставку из-за взяток дзайбацу!")
	if turn_manager_ref != null and turn_manager_ref.event_manager != null:
		var ev = _create_event_ino_resignation()
		turn_manager_ref.pending_modal_events.push_front(ev)


# ==============================================================================
# РАЗРЕШЕНИЕ КРИЗИСА И ВЫБОР ПУТИ РЕФОРМ (Player Actions)
# ==============================================================================

## 1. Санация и спасение банков (Путь Икэды / Финансистов)
func resolve_yasuda_bailout() -> Dictionary:
	if player_state_ref == null:
		return {"success": false, "message": "Ошибка состояния."}
	if player_state_ref.liquid_reserves_billions < 15.0:
		return {"success": false, "message": "Недостаточно валютных резервов для санации ($15.0B требуется)."}

	player_state_ref.liquid_reserves_billions -= 15.0
	player_state_ref.inflation_rate += 0.03
	tse_index = 750.0
	yasuda_phase = YasudaPhase.RESOLVED
	factions_diet["IKEDA"]["loyalty"] = clampf(factions_diet["IKEDA"]["loyalty"] + 25.0, 0.0, 100.0)
	zaibatsu_influence["MITSUI"] += 5.0
	zaibatsu_influence["MITSUBISHI"] += 5.0
	zaibatsu_influence_changed.emit("MITSUI", zaibatsu_influence["MITSUI"])
	zaibatsu_influence_changed.emit("MITSUBISHI", zaibatsu_influence["MITSUBISHI"])

	appoint_prime_minister("IKEDA")
	yasuda_crisis_resolved.emit("bailout")
	return {"success": true, "message": "САНАЦИЯ ЯСУДА: Государство выкупило токсичные долги. Биржа стабилизирована, но инфляция выросла."}


## 2. Бескомпромиссное расследование и чистка олигархов (Путь Такаги / Реформаторов)
func resolve_yasuda_investigation() -> Dictionary:
	if player_state_ref == null:
		return {"success": false, "message": "Ошибка состояния."}
	if player_state_ref.political_capital < 40.0 or player_state_ref.current_cap < 1:
		return {"success": false, "message": "Недостаточно PC (40) или CAP (1) для санкционирования облав."}

	player_state_ref.political_capital -= 40.0
	player_state_ref.current_cap -= 1
	yasuda_phase = YasudaPhase.RESOLVED
	tse_index = 680.0
	factions_diet["TAKAGI"]["loyalty"] = clampf(factions_diet["TAKAGI"]["loyalty"] + 30.0, 0.0, 100.0)
	player_state_ref.radicalization = maxf(player_state_ref.radicalization - 15.0, 0.0)
	player_state_ref.legitimacy = clampf(player_state_ref.legitimacy + 12.0, 0.0, 100.0)

	appoint_prime_minister("TAKAGI")
	yasuda_crisis_resolved.emit("investigation")
	return {"success": true, "message": "АНТИКОРРУПЦИОННЫЙ СУД: Руководство Ясуда арестовано. Адмирал Такаги возглавил правительство национального доверия."}


## 3. Национализация и госплан (Путь Каи / Технократов)
func resolve_yasuda_nationalize() -> Dictionary:
	if player_state_ref == null:
		return {"success": false, "message": "Ошибка состояния."}
	if player_state_ref.political_capital < 35.0:
		return {"success": false, "message": "Недостаточно PC (35) для проведения национализации."}

	player_state_ref.political_capital -= 35.0
	yasuda_phase = YasudaPhase.RESOLVED
	player_state_ref.military_factories += 6
	player_state_ref.civilian_factories += 4
	factions_diet["KAYA"]["loyalty"] = clampf(factions_diet["KAYA"]["loyalty"] + 30.0, 0.0, 100.0)
	tse_index = 620.0

	appoint_prime_minister("KAYA")
	yasuda_crisis_resolved.emit("nationalize")
	return {"success": true, "message": "НАЦИОНАЛИЗАЦИЯ: Активы конгломерата перешли под контроль Госплана. Кая Окинори назначен премьером."}


# ==============================================================================
# НАЗНАЧЕНИЕ ПРЕМЬЕР-МИНИСТРА И ПЕРЕКЛЮЧЕНИЕ ДРЕВА ФОКУСОВ
# ==============================================================================
func appoint_prime_minister(cand_key: String) -> void:
	if not factions_diet.has(cand_key):
		return

	var f_info = factions_diet[cand_key]
	active_prime_minister_key = cand_key
	current_prime_minister = str(f_info["leader"])

	if player_state_ref != null:
		player_state_ref.leader_name = current_prime_minister
		player_state_ref.set_flag("japan_prime_minister", cand_key)
		player_state_ref.active_directives.clear()

	var target_tree_id = str(f_info["tree_id"])
	var target_tree_path = str(f_info["tree_path"])

	# Переключение фокусного древа
	if turn_manager_ref != null:
		if turn_manager_ref.focus_stage_controller != null:
			turn_manager_ref.focus_stage_controller.country_tag = "JAP"
			turn_manager_ref.focus_stage_controller.switch_focus_tree(target_tree_id, false)
		elif turn_manager_ref.directive_manager != null:
			_load_japan_directives(target_tree_path)

	prime_minister_elected.emit(current_prime_minister, target_tree_id)
	print("[JapanEmpireManager] Новый Премьер-министр Японии: %s. Активировано древо: %s" % [current_prime_minister, target_tree_id])


## Проведение голосования по законопроекту в Палате Представителей (Diet)
func call_diet_vote(bill_id: String, required_threshold: float = 50.0) -> bool:
	var total_support = 0.0
	for f_key in factions_diet.keys():
		var f_data = factions_diet[f_key]
		var seats = float(f_data.get("seats", 0))
		var loyalty = float(f_data.get("loyalty", 50.0))
		if loyalty >= 50.0:
			total_support += seats
		elif loyalty >= 30.0:
			total_support += seats * (loyalty / 100.0)
	var passed = total_support >= required_threshold
	diet_vote_called.emit(bill_id, passed)
	return passed


## Модификация влияния дзайбацу с уведомлением подписчиков
func modify_zaibatsu_influence(key: String, delta: float) -> void:
	var cur = float(zaibatsu_influence.get(key, 25.0))
	var n_val = clampf(cur + delta, 0.0, 100.0)
	zaibatsu_influence[key] = n_val
	zaibatsu_influence_changed.emit(key, n_val)


func _load_japan_directives(path: String) -> void:
	if not FileAccess.file_exists(path) or turn_manager_ref == null or turn_manager_ref.directive_manager == null:
		return
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null: return
	var json = JSON.new()
	if json.parse(f.get_as_text()) != OK or not (json.data is Dictionary):
		f.close()
		return
	f.close()

	var dm = turn_manager_ref.directive_manager
	dm.all_directives.clear()
	var raw_nodes = json.data.get("nodes", json.data.get("directives", []))
	if raw_nodes is Dictionary:
		for nid in raw_nodes.keys():
			dm.register_directive(DirectiveResource.from_dict(raw_nodes[nid]))
	elif raw_nodes is Array:
		for d in raw_nodes:
			dm.register_directive(DirectiveResource.from_dict(d))


# ==============================================================================
# БАЛАНС ИЯА И ИЯФ (IJA vs IJN Rivalry)
# ==============================================================================
func _process_military_rivalry_turn() -> void:
	# Дрейф баланса
	if ija_ijn_balance < -60.0:
		# Слишком сильное влияние Армии — недовольство на флотилии
		if player_state_ref != null and randf() < 0.15:
			player_state_ref.political_capital = maxf(player_state_ref.political_capital - 5.0, 0.0)
	elif ija_ijn_balance > 60.0:
		# Слишком сильный Флот — офицеры Квантунской армии ропщут
		if player_state_ref != null and randf() < 0.15:
			player_state_ref.war_support_percent = maxf(player_state_ref.war_support_percent - 2.0, 10.0)


func adjust_military_balance(delta: float) -> void:
	ija_ijn_balance = clampf(ija_ijn_balance + delta, -100.0, 100.0)
	ija_ijn_balance_shifted.emit(ija_ijn_balance)


func allocate_resources_to_navy() -> Dictionary:
	if player_state_ref == null or player_state_ref.political_capital < 15.0:
		return {"success": false, "message": "Недостаточно PC (15)."}
	player_state_ref.political_capital -= 15.0
	adjust_military_balance(10.0)
	navy_oil_quota = clampf(navy_oil_quota + 5.0, 30.0, 85.0)
	army_steel_quota = clampf(army_steel_quota - 5.0, 20.0, 70.0)
	return {"success": true, "message": "ПРИОРИТЕТ ФЛОТУ: Квоты на нефть и доки переданы Объединенному Флоту."}


func allocate_resources_to_army() -> Dictionary:
	if player_state_ref == null or player_state_ref.political_capital < 15.0:
		return {"success": false, "message": "Недостаточно PC (15)."}
	player_state_ref.political_capital -= 15.0
	adjust_military_balance(-10.0)
	army_steel_quota = clampf(army_steel_quota + 5.0, 20.0, 85.0)
	navy_oil_quota = clampf(navy_oil_quota - 5.0, 30.0, 70.0)
	return {"success": true, "message": "ПРИОРИТЕТ АРМИИ: Выпуск бронетехники и артиллерии для сухопутных войск увеличен."}


# ==============================================================================
# СФЕРА СОПРОЦВЕТАНИЯ (GEACPS Management)
# ==============================================================================
func _process_sphere_turn() -> void:
	if player_state_ref == null:
		return
	var total_tribute = 0
	for m_tag in sphere_members.keys():
		var m = sphere_members[m_tag]
		total_tribute += int(m.get("tribute_factories", 0))
		# Случайные партизанские инциденты
		if float(m.get("unrest", 0.0)) > 50.0 and randf() < 0.1:
			sphere_incident_reported.emit(m_tag, "Восстание местных партизан в %s!" % m["name"])

	# Часть фабрик сателлитов питает японскую промышленность
	player_state_ref.civilian_factories = maxi(player_state_ref.civilian_factories, 80 + int(total_tribute * 0.4))


func suppress_sphere_insurgency(m_tag: String) -> Dictionary:
	if not sphere_members.has(m_tag) or player_state_ref == null:
		return {"success": false, "message": "Сателлит не найден."}
	if player_state_ref.manpower_pool < 5000 or player_state_ref.political_capital < 15.0:
		return {"success": false, "message": "Недостаточно рекрутов (5000) или PC (15)."}

	player_state_ref.manpower_pool -= 5000
	player_state_ref.political_capital -= 15.0
	var m = sphere_members[m_tag]
	m["unrest"] = maxf(m["unrest"] - 25.0, 0.0)
	m["loyalty"] = clampf(m["loyalty"] + 10.0, 0.0, 100.0)
	return {"success": true, "message": "КЭМПЭЙТАЙ: Мятежи в %s подавлены силами гарнизона." % m["name"]}


# ==============================================================================
# НАРРАТИВНЫЕ СОБЫТИЯ ЯПОНИИ
# ==============================================================================
func _create_event_yasuda_crash() -> GameEvent:
	var ev = GameEvent.new()
	ev.event_id = "jap_yasuda_crash_modal"
	ev.is_modal = true
	ev.title = "ЧЕРНЫЙ ПОНЕДЕЛЬНИК В ТОКИО: КРАХ КОРПОРАЦИИ «ЯСУДА»"
	ev.description = (
		"Токийская фондовая биржа погрузилась в неконтролируемый хаос. Конгломерат «Ясуда» — " +
		"один из четырех титанов японской экономики, финансировавший флот и застройку Азии, — " +
		"объявил о неплатежеспособности. Раскрыта колоссальная сеть взяток в министерствах.\n\n" +
		"Тысячи инвесторов штурмуют отделения банков. Премьер-министр Хироя Ино пытается замять скандал, " +
		"но оппозиция в Палате Пэров и армейское командование требуют немедленной расправы над олигархами."
	)
	ev.options.append({
		"text": "[ КАТАСТРОФА НЕИЗБЕЖНА: ВВЕСТИ ЧРЕЗВЫЧАЙНОЕ ПОЛОЖЕНИЕ ]",
		"effects": {"MOD_STABILITY": -15.0, "MOD_RADICALIZATION": 20.0}
	})
	return ev


func _create_event_ino_resignation() -> GameEvent:
	var ev = GameEvent.new()
	ev.event_id = "jap_ino_resignation_modal"
	ev.is_modal = true
	ev.title = "ОТСТАВКА КАБИНЕТА ХИРОЯ ИНО"
	ev.description = (
		"Под давлением неопровержимых улик и народного гнева премьер-министр Хироя Ино подал Императору " +
		"прошение об отставке. Теневое правительство дзайбацу разрушено.\n\n" +
		"В Палате Пэров начинается ожесточенная битва за пост нового главы правительства: " +
		"реформаторы адмирала Такаги, либеральные бюрократы Икэды или ультра-технократы Каи?"
	)
	ev.options.append({
		"text": "[ СОЗВАТЬ ЭКСТРЕННОЕ ЗАСЕДАНИЕ ДАЙЭТА ]"
	})
	return ev
