class_name ItalyEmpireManager
extends Node

##
## ItalyEmpireManager: Главный контроллер Итальянской Империи (Regno d'Italia / ITA)
##
## Реализует уникальные механики TNO для Италии:
## 1. Распад Триумвирата (The Fall of the Triumvirate):
##    - Отношения и дипломатическое напряжение с Иберией и Турцией.
##    - Споры вокруг Гибралтара, Суэца, Леванта и проекта Атлантропа.
##    - Неминуемый крах средиземноморского альянса и супер-событие раскола.
## 2. Битва за Средиземноморье (The Battle for the Mediterranean):
##    - Геополитическое влияние в Египте, Ираке, Леванте, Греции и Йемене.
##    - Отправка карабинеров, торговые концессии, субсидии и подавление мятежей.
## 3. Катастрофа Атлантропы (The Atlantropa Disaster):
##    - Осушение Адриатики (Венеция и Триест), деградация портов.
##    - Кризис юга Италии (Mezzogiorno drain), дефицит пресной воды.
##    - Проекты ирригации, обводных каналов и гидроэлектростанций.
## 4. Великий Фашистский Совет (Gran Consiglio del Fascismo):
##    - Борьба между реформаторами/демократами (Галеаццо Чиано) и жесткими фашистами (Карло Скорца).
##    - Автоматическое переключение на древа директив: tno_italy_dem_shared / tno_italy_scorza_shared.
##

signal triumvirate_tension_changed(iberia_tension: float, turkey_tension: float)
signal triumvirate_collapsed()
signal mediterranean_influence_updated(theater_key: String, influence_data: Dictionary)
signal atlantropa_project_completed(project_key: String)
signal council_power_shifted(new_balance: float)
signal ideology_path_chosen(path_key: String, tree_id: String)

enum TriumvirateState {
	ALLIED = 0,     # Начальный союз трех держав
	STRAINED = 1,   # Нарастающие разногласия
	COLLAPSING = 2, # Острый дипломатический кризис
	DISSOLVED = 3   # Полный распад и начало Битвы за Средиземноморье
}

# --- РАСПАД ТРИУМВИРАТА ---
@export var triumvirate_state: TriumvirateState = TriumvirateState.ALLIED
var iberia_tension: float = 30.0   # Спор о Гибралтаре и Марокко (0..100)
var turkey_tension: float = 40.0   # Спор о Додеканесе, Леванте и нефти Мосула (0..100)
var triumvirate_turns_elapsed: int = 0

# --- БИТВА ЗА СРЕДИЗЕМНОМОРЬЕ (СФЕРЫ ВЛИЯНИЯ) ---
var mediterranean_theaters: Dictionary = {
	"egypt": {
		"name": "Королевство Египет (Суэцкий Канал)",
		"italian_influence": 55.0,
		"german_influence": 25.0,
		"arab_nationalism": 35.0,
		"status": "monarchy_secured",
		"desc": "Контроль над каналом и королем Фаруком — ключ к Африке."
	},
	"levant_iraq": {
		"name": "Левант и Ирак (Нефтяные Концессии)",
		"italian_influence": 45.0,
		"turkish_influence": 35.0,
		"baath_insurgency": 40.0,
		"status": "contested",
		"desc": "Трубопроводы Киркука и Хайфы под угрозой турецкой экспансии и баасистов."
	},
	"greece": {
		"name": "Королевство Греция и Эгейское Море",
		"italian_influence": 65.0,
		"partisans_threat": 30.0,
		"status": "protectorate",
		"desc": "Марионеточная монархия, морские базы на Крите и Родосе."
	},
	"yemen": {
		"name": "Йемен и Баб-эль-Мандебский Пролив",
		"italian_influence": 50.0,
		"status": "outpost",
		"desc": "Южные ворота Красного моря и выход в Индийский океан."
	}
}

# --- КАТАСТРОФА АТЛАНТРОПЫ ---
var atlantropa_damage_index: float = 75.0      # Общий экологический и экономический ущерб
var adriatic_drain_level: float = 80.0        # Усыхание Адриатического моря
var mezzogiorno_poverty_drain: float = 60.0   # Депрессия Юга Италии и Сицилии ($ млрд субсидий)
var atlantropa_projects: Dictionary = {
	"adriatic_canal": {"name": "Судоходный канал Венеция-Адриатика", "progress": 20.0, "cost": 6.0, "completed": false},
	"southern_aqueducts": {"name": "Система акведуков Медзоджорно", "progress": 15.0, "cost": 5.0, "completed": false},
	"po_valley_irrigation": {"name": "Рекультивация солончаков долины По", "progress": 30.0, "cost": 4.0, "completed": false}
}

# --- ВЕЛИКИЙ ФАШИСТСКИЙ СОВЕТ (CIANO VS SCORZA) ---
# -100.0 = Тотальный триумф жестких фашистов (Карло Скорца)
# +100.0 = Тотальный триумф реформаторов/демократов (Галеаццо Чиано)
# 0.0 = Равновесие в Совете
var council_balance: float = 15.0
var ciano_popularity: float = 60.0
var scorza_loyalty: float = 55.0
var active_path_key: String = "STATUS_QUO"

var turn_manager_ref: TurnManager = null
var player_state_ref: CountryState = null


func _ready() -> void:
	name = "ItalyEmpireManager"


func initialize(tm: TurnManager, p_state: CountryState) -> void:
	turn_manager_ref = tm
	player_state_ref = p_state
	print("[ItalyEmpireManager] Инициализирован для Итальянской Империи. Лидер: %s" % (player_state_ref.leader_name if player_state_ref else "Галеаццо Чиано"))


## Детерминированный генератор псевдослучайных величин для хода
static func _get_deterministic_factor(seed_val: int, min_val: float, max_val: float) -> float:
	var s: int = (seed_val * 73856093) ^ 1274126177
	s = (s ^ (s >> 13)) * 19349663
	var norm: float = float(s & 0x7FFFFFFF) / float(0x7FFFFFFF)
	return min_val + (norm * (max_val - min_val))


# ==============================================================================
# ПОШАГОВЫЙ ЦИКЛ СИМУЛЯЦИИ (Turn Process)
# ==============================================================================
func process_turn(turn_num: int, p_state: CountryState = null, _world_states: Dictionary = {}) -> void:
	if p_state != null:
		player_state_ref = p_state

	# 1. Симуляция распада Триумвирата
	_process_triumvirate_turn(turn_num)

	# 2. Симуляция Битвы за Средиземноморье
	_process_mediterranean_turn(turn_num)

	# 3. Экономический ущерб Атлантропы
	_process_atlantropa_drain()


func _process_triumvirate_turn(turn_num: int) -> void:
	triumvirate_turns_elapsed += 1

	if triumvirate_state != TriumvirateState.DISSOLVED:
		# Постепенный рост напряжения (детерминированный расчет)
		var ib_seed: int = (turn_num * 99991) ^ 104729
		var tr_seed: int = (turn_num * 73856093) ^ 224737
		iberia_tension = clampf(iberia_tension + _get_deterministic_factor(ib_seed, 1.5, 3.5), 0.0, 100.0)
		turkey_tension = clampf(turkey_tension + _get_deterministic_factor(tr_seed, 2.0, 4.5), 0.0, 100.0)
		triumvirate_tension_changed.emit(iberia_tension, turkey_tension)

		# Стадии кризиса
		if iberia_tension > 50.0 or turkey_tension > 55.0:
			if triumvirate_state == TriumvirateState.ALLIED:
				triumvirate_state = TriumvirateState.STRAINED
				print("[ItalyEmpireManager] Триумвират дал трещину: обострение споров о Суэце и Гибралтаре.")

		if iberia_tension > 75.0 and turkey_tension > 75.0:
			if triumvirate_state == TriumvirateState.STRAINED:
				triumvirate_state = TriumvirateState.COLLAPSING
				print("[ItalyEmpireManager] Острый дипломатический кризис: послы Иберии и Турции угрожают разрывом пакта.")

		# На 4-6 ходу неизбежен распад Триумвирата
		if turn_num >= 4 and (iberia_tension >= 85.0 or turkey_tension >= 90.0 or turn_num >= 6):
			trigger_triumvirate_collapse()


func trigger_triumvirate_collapse() -> void:
	if triumvirate_state == TriumvirateState.DISSOLVED:
		return

	triumvirate_state = TriumvirateState.DISSOLVED
	print("[ItalyEmpireManager] РАСПАД ТРИУМВИРАТА! Средиземноморский союз распался.")

	if player_state_ref != null:
		player_state_ref.set_flag("triumvirate_collapsed", true)
		player_state_ref.legitimacy = maxf(player_state_ref.legitimacy - 10.0, 20.0)

	triumvirate_collapsed.emit()

	if turn_manager_ref != null:
		turn_manager_ref.super_event_requested.emit("SUPER_FALL_OF_TRIUMVIRATE")
		if turn_manager_ref.event_manager != null:
			var ev = _create_event_triumvirate_fall()
			turn_manager_ref.pending_modal_events.push_front(ev)


func _process_mediterranean_turn(turn_num: int = 1) -> void:
	# Фоновая борьба за влияние (детерминированная симуляция)
	for th_key in mediterranean_theaters.keys():
		var th: Dictionary = mediterranean_theaters[th_key]
		var th_seed: int = (turn_num * 31337) ^ str(th_key).hash()
		# Арабский национализм и повстанцы медленно подтачивают позиции Италии
		if th.has("arab_nationalism"):
			th["arab_nationalism"] = clampf(th["arab_nationalism"] + _get_deterministic_factor(th_seed + 1, 0.5, 2.0), 0.0, 100.0)
			if th["arab_nationalism"] > 60.0:
				th["italian_influence"] = maxf(th["italian_influence"] - 1.0, 0.0)

		if th.has("baath_insurgency"):
			th["baath_insurgency"] = clampf(th["baath_insurgency"] + _get_deterministic_factor(th_seed + 2, 0.5, 2.5), 0.0, 100.0)


func _process_atlantropa_drain() -> void:
	if player_state_ref == null:
		return
	# Если проекты не завершены, Атлантропа вытягивает из бюджета средства
	var incomplete_projects = 0
	for p_key in atlantropa_projects.keys():
		if not atlantropa_projects[p_key]["completed"]:
			incomplete_projects += 1

	if incomplete_projects > 0:
		# Убытки от деградации портов и засухи
		player_state_ref.liquid_reserves_billions = maxf(player_state_ref.liquid_reserves_billions - 0.4 * incomplete_projects, 1.0)


# ==============================================================================
# ДЕЙСТВИЯ ИГРОКА: ДИПЛОМАТИЯ И БИТВА ЗА СРЕДИЗЕМНОМОРЬЕ
# ==============================================================================

## Дипломатические уступки для снижения напряжения
func appease_ally(target_country: String) -> Dictionary:
	if player_state_ref == null or player_state_ref.political_capital < 20.0:
		return {"success": false, "message": "Недостаточно PC (требуется 20)."}

	player_state_ref.political_capital -= 20.0
	match target_country.to_upper():
		"IBERIA":
			iberia_tension = maxf(iberia_tension - 18.0, 0.0)
			return {"success": true, "message": "ДИАЛОГ С МАДРИДОМ: Территориальные споры по Марокко урегулированы. Напряжение снижено."}
		"TURKEY":
			turkey_tension = maxf(turkey_tension - 18.0, 0.0)
			return {"success": true, "message": "ПРОЛИВЫ И ЛЕВАНТ: Переданы нефтяные концессии Анкаре. Напряжение с Турцией ослаблено."}
		_:
			return {"success": false, "message": "Неизвестная держава."}


## Инвестиции в Средиземноморский театр (Укрепление влияния)
func invest_in_theater(theater_key: String, cash_billions: float) -> Dictionary:
	if not mediterranean_theaters.has(theater_key) or player_state_ref == null:
		return {"success": false, "message": "Театр не найден."}
	if player_state_ref.liquid_reserves_billions < cash_billions:
		return {"success": false, "message": "Недостаточно резервов ($%.1fB требуется)." % cash_billions}

	player_state_ref.liquid_reserves_billions -= cash_billions
	var th = mediterranean_theaters[theater_key]
	th["italian_influence"] = clampf(th["italian_influence"] + cash_billions * 3.5, 0.0, 100.0)
	mediterranean_influence_updated.emit(theater_key, th)
	return {"success": true, "message": "ИНВЕСТИЦИИ: Позиции Италии в театре [%s] усилены (+%0.1f%% влияния)." % [th["name"], cash_billions * 3.5]}


## Развертывание карабинеров / спецоперации SIM
func deploy_carabinieri(theater_key: String) -> Dictionary:
	if not mediterranean_theaters.has(theater_key) or player_state_ref == null:
		return {"success": false, "message": "Театр не найден."}
	if player_state_ref.manpower_pool < 4000 or player_state_ref.current_cap < 1:
		return {"success": false, "message": "Недостаточно рекрутов (4000) или CAP (1)."}

	player_state_ref.manpower_pool -= 4000
	player_state_ref.current_cap -= 1
	var th = mediterranean_theaters[theater_key]
	if th.has("arab_nationalism"):
		th["arab_nationalism"] = maxf(th["arab_nationalism"] - 20.0, 0.0)
	if th.has("partisans_threat"):
		th["partisans_threat"] = maxf(th["partisans_threat"] - 25.0, 0.0)
	if th.has("baath_insurgency"):
		th["baath_insurgency"] = maxf(th["baath_insurgency"] - 20.0, 0.0)

	th["italian_influence"] = clampf(th["italian_influence"] + 8.0, 0.0, 100.0)
	return {"success": true, "message": "КАРАБИНЕРЫ: Военно-полицейская миссия подавила ячейки антиитальянских боевиков в [%s]." % th["name"]}


# ==============================================================================
# ПРОЕКТЫ ВОССТАНОВЛЕНИЯ АТЛАНТРОПЫ
# ==============================================================================
func advance_atlantropa_project(proj_key: String) -> Dictionary:
	if not atlantropa_projects.has(proj_key) or player_state_ref == null:
		return {"success": false, "message": "Проект не найден."}

	var p = atlantropa_projects[proj_key]
	if p["completed"]:
		return {"success": false, "message": "Проект уже полностью завершен."}

	var cost = float(p.get("cost", 4.0))
	if player_state_ref.liquid_reserves_billions < cost:
		return {"success": false, "message": "Недостаточно средств ($%.1fB требуется)." % cost}

	player_state_ref.liquid_reserves_billions -= cost
	p["progress"] = clampf(p["progress"] + 35.0, 0.0, 100.0)
	if p["progress"] >= 100.0:
		p["completed"] = true
		atlantropa_damage_index = maxf(atlantropa_damage_index - 20.0, 0.0)
		player_state_ref.civilian_factories += 4
		player_state_ref.real_gdp_growth = clampf(player_state_ref.real_gdp_growth + 0.005, 0.01, 0.09)
		atlantropa_project_completed.emit(proj_key)
		return {"success": true, "message": "ТРИУМФ ИНЖЕНЕРИИ: Проект «%s» успешно завершен! Экономика восстановлена." % p["name"]}

	return {"success": true, "message": "СТРОИТЕЛЬСТВО: Прогресс проекта «%s» достиг %0.0f%%." % [p["name"], p["progress"]]}


# ==============================================================================
# ВЕЛИКИЙ ФАШИСТСКИЙ СОВЕТ: ЧИАНО VS СКОРЦА И СМЕНА ДРЕВА
# ==============================================================================

## Выбор курса реформаторов Чиано (Демократизация / tno_italy_dem_shared)
func adopt_ciano_democratic_reforms() -> Dictionary:
	if player_state_ref == null:
		return {"success": false, "message": "Ошибка состояния."}
	if player_state_ref.political_capital < 35.0:
		return {"success": false, "message": "Недостаточно PC (35) для утверждения курса Чиано."}

	player_state_ref.political_capital -= 35.0
	council_balance = clampf(council_balance + 35.0, -100.0, 100.0)
	council_power_shifted.emit(council_balance)
	active_path_key = "CIANO_DEM"
	player_state_ref.ruling_ideology = "fascism"
	player_state_ref.sub_ideology = "Авторитарный Реформизм"
	player_state_ref.set_flag("italy_path", "ciano_dem")
	player_state_ref.active_directives.clear()

	var tree_id = "tno_italy_dem_shared"
	var tree_path = "res://data/countries/ITA/directives/trees/tno_italy_dem_shared.json"

	_switch_italian_tree(tree_id, tree_path)
	ideology_path_chosen.emit("CIANO_DEM", tree_id)
	return {"success": true, "message": "КУРС ЧИАНО: Великий Совет утвердил постепенную демократизацию и реформу фашизма."}


## Выбор курса жестких фашистов Скорцы (Тоталитаризм / tno_italy_scorza_shared)
func adopt_scorza_hardliner_path() -> Dictionary:
	if player_state_ref == null:
		return {"success": false, "message": "Ошибка состояния."}
	if player_state_ref.political_capital < 35.0:
		return {"success": false, "message": "Недостаточно PC (35) для утверждения курса Скорцы."}

	player_state_ref.political_capital -= 35.0
	council_balance = clampf(council_balance - 35.0, -100.0, 100.0)
	council_power_shifted.emit(council_balance)
	active_path_key = "SCORZA_HARDLINER"
	player_state_ref.leader_name = "Карло Скорца"
	player_state_ref.sub_ideology = "Ортодоксальный Фашизм"
	player_state_ref.set_flag("italy_path", "scorza_hardliner")
	player_state_ref.active_directives.clear()

	var tree_id = "tno_italy_scorza_shared"
	var tree_path = "res://data/countries/ITA/directives/trees/tno_italy_scorza_shared.json"

	_switch_italian_tree(tree_id, tree_path)
	ideology_path_chosen.emit("SCORZA_HARDLINER", tree_id)
	return {"success": true, "message": "ДИКТАТ СКОРЦЫ: Карло Скорца захватил руководство Советом. Начат имперский реванш."}


func modify_council_balance(delta: float) -> void:
	council_balance = clampf(council_balance + delta, -100.0, 100.0)
	council_power_shifted.emit(council_balance)


func _switch_italian_tree(tree_id: String, tree_path: String) -> void:
	if turn_manager_ref != null:
		if turn_manager_ref.focus_stage_controller != null:
			turn_manager_ref.focus_stage_controller.country_tag = "ITA"
			turn_manager_ref.focus_stage_controller.switch_focus_tree(tree_id, false)
		elif turn_manager_ref.directive_manager != null and FileAccess.file_exists(tree_path):
			_load_italian_directives(tree_path)
	print("[ItalyEmpireManager] Активировано древо директив Италии: [%s]" % tree_id)


func _load_italian_directives(path: String) -> void:
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
# НАРРАТИВНЫЕ СОБЫТИЯ ИТАЛИИ
# ==============================================================================
func _create_event_triumvirate_fall() -> GameEvent:
	var ev = GameEvent.new()
	ev.event_id = "ita_triumvirate_collapse_modal"
	ev.is_modal = true
	ev.title = "РАСПАД ТРИУМВИРАТА: КРАХ СРЕДИЗЕМНОМОРСКОГО АЛЬЯНСА"
	ev.description = (
		"Средиземноморский пакт трех держав (Италия, Иберия, Турция), созданный как противовес безумию Рейха " +
		"и экспансии ОФН, окончательно похоронен. Неразрешимые противоречия вокруг высыхающей Атлантропы, " +
		"контроля над нефтью Леванта и статуса Гибралтара взорвали союз.\n\n" +
		"Иберия замыкается в глухой обороне Пиренеев. Турция открыто стягивает дивизии к сирийской границе. " +
		"Италия остается в одиночестве. Начинается безжалостная Битва за Средиземноморье."
	)
	ev.options.append({
		"text": "[ СРЕДИЗЕМНОЕ МОРЕ ПРИНАДЛЕЖИТ РИМУ! ]",
		"effects": {"MOD_STABILITY": -10.0, "MOD_RADICALIZATION": 15.0}
	})
	return ev
