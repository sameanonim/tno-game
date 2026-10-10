class_name DecisionManager
extends RefCounted

##
## DecisionManager: Централизованный менеджер оперативных решений и кризисов (TNO Decisions Subsystem)
## --------------------------------------------------------------------------------------------------
## Управляет жизненным циклом решений:
## 1. Загрузка решений для государства игрока (через ContentLoader и fallback-пакеты).
## 2. Проверка условий доступности (can_afford, required_flags, blocked_flags, fire_only_once).
## 3. Отслеживание ходов и кулдаунов (cooldowns) с поддержкой сериализации в сохранения.
## 4. Исполнение решений: списание ресурсов, наложение кулдаунов, применение нормализованных эффектов
##    к CountryState и отправка сигналов.
## 5. Оповещение UI через сигналы: decision_executed, decisions_updated.
##

signal decision_executed(decision_id: String, effects: Dictionary)
signal decisions_updated()

var player_state: CountryState = null
var turn_manager: TurnManager = null
var content_loader: ContentLoader = null

## Полный список загруженных решений для текущей державы
var all_decisions: Array[Dictionary] = []

## Словарь кулдаунов: decision_id -> номер хода, на котором решение станет доступно
var cooldowns: Dictionary = {} # String -> int

## Однократные решения, которые уже были выполнены
var executed_once: Dictionary = {} # String -> bool

## Индекс решений по ID для быстрого O(1) доступа
var _decisions_by_id: Dictionary = {} # String -> Dictionary

## Список базовых резервных решений в стиле TNO (Fallback)
var fallback_decisions: Array[Dictionary] = [
	# --- РУССКАЯ СМУТА: ВООРУЖЕНИЕ И ОПЕРАЦИИ ---
	{
		"id": "smuta_arms_smuggling",
		"category": "smuta",
		"category_name": "РУССКАЯ СМУТА: СНАБЖЕНИЕ",
		"title": "Закупка Стрелкового Оружия у Контрабандистов",
		"description": "Через зыбкие границы хлынул поток карабинов Вермахта и американских гарандов. Закупка нелегальных партий оружия для ударных бригад.",
		"cost_pc": 15.0,
		"cost_cap": 1,
		"cost_money": 0.05,
		"cooldown_turns": 2,
		"fire_only_once": false,
		"effects": {
			"modify_weapons": 3000,
			"modify_readiness": 3.0,
			"log": "Контрабандные склады доставлены в расположение фронта: +3,000 винтовок!"
		},
		"requires_russia": true
	},
	{
		"id": "smuta_shock_recruitment",
		"category": "smuta",
		"category_name": "РУССКАЯ СМУТА: АРМИЯ",
		"title": "Формирование Ударных Батальонов Ополчения",
		"description": "Призыв фронтовой молодежи и бывших красноармейцев под знамена объединения. Ускоренная мобилизация добровольческих частей.",
		"cost_pc": 20.0,
		"cost_cap": 1,
		"cost_money": 0.08,
		"cooldown_turns": 3,
		"fire_only_once": false,
		"effects": {
			"modify_manpower": 7500,
			"modify_radicalization": 2.0,
			"log": "Мобилизационные пункты развернуты: +7,500 бойцов в резерв!"
		},
		"requires_russia": true
	},
	{
		"id": "smuta_radio_broadcast",
		"category": "smuta",
		"category_name": "РУССКАЯ СМУТА: АГИТАЦИЯ",
		"title": "Агитационный Радиомост «Голос Отечества»",
		"description": "Трансляция воззваний через радиомачты в соседние враждебные регионы. Подрыв боевого духа гарнизонов противника и рост народной поддержки.",
		"cost_pc": 25.0,
		"cost_cap": 0,
		"cost_money": 0.02,
		"cooldown_turns": 2,
		"fire_only_once": false,
		"effects": {
			"modify_legitimacy": 6.0,
			"modify_radicalization": -4.0,
			"log": "Радиопередачи посеяли сомнения в тылу врага: легитимность +6%, недовольство -4%!"
		},
		"requires_russia": true
	},
	{
		"id": "smuta_infiltrate_caches",
		"category": "smuta",
		"category_name": "РУССКАЯ СМУТА: ДИВЕРСИИ",
		"title": "Ночной Рейд на Склады ГСМ и Боеприпасов",
		"description": "Засылка разведгруппы в глубокий тыл соседнего варлорда для подрыва цистерн и захвата тяжелых минометов.",
		"cost_pc": 30.0,
		"cost_cap": 2,
		"cost_money": 0.04,
		"cooldown_turns": 4,
		"fire_only_once": false,
		"effects": {
			"modify_weapons": 1500,
			"modify_heavy_equipment": 80,
			"modify_war_support": 4.0,
			"log": "Диверсионный рейд увенчался полным успехом: склады подорваны, захвачено 80 ед. тяжелого вооружения!"
		},
		"requires_russia": true
	},
	{
		"id": "smuta_grain_requisition",
		"category": "smuta",
		"category_name": "РУССКАЯ СМУТА: СНАБЖЕНИЕ",
		"title": "Приграничная Продразверстка и Заготовки",
		"description": "Реквизиция продовольствия у зажиточных артелей для снабжения гарнизонов в полевых условиях.",
		"cost_pc": 10.0,
		"cost_cap": 1,
		"cost_money": 0.0,
		"cooldown_turns": 3,
		"fire_only_once": false,
		"effects": {
			"modify_reserves": 0.04,
			"modify_manpower": 1500,
			"modify_radicalization": 5.0,
			"modify_legitimacy": -3.0,
			"log": "Продразверстка пополнила запасы фронта: резервы +$40M, +1,500 новобранцев!"
		},
		"requires_russia": true
	},
	{
		"id": "smuta_veteran_officer_rally",
		"category": "smuta",
		"category_name": "РУССКАЯ СМУТА: ВЕТЕРАНЫ",
		"title": "Сбор Офицеров Разбитых Армий",
		"description": "Амнистия и вербовка опытных ветеранов для реорганизации штабов и проведения полевых учений.",
		"cost_pc": 25.0,
		"cost_cap": 1,
		"cost_money": 0.05,
		"cooldown_turns": 4,
		"fire_only_once": false,
		"effects": {
			"modify_readiness": 10.0,
			"modify_war_support": 5.0,
			"log": "Ветераны возглавили батальоны: боеготовность +10%, поддержка войны +5%!"
		},
		"requires_russia": true
	},

	# --- КРИЗИС ТРЕТЬЕГО РЕЙХА: БОРЬБА ЗА ВЛАСТЬ ---
	{
		"id": "reich_inspect_arsenals",
		"category": "reich",
		"category_name": "КРИЗИС РЕЙХА: ВЕРМАХТ",
		"title": "Внезапная Инспекция Арсеналов Бранденбурга",
		"description": "Проверка боеготовности складов ОКВ и вербовка колеблющихся офицеров перед грядущей гражданской войной.",
		"cost_pc": 20.0,
		"cost_cap": 1,
		"cost_money": 0.06,
		"cooldown_turns": 3,
		"fire_only_once": false,
		"effects": {
			"modify_readiness": 8.0,
			"modify_heavy_equipment": 150,
			"log": "Инспекция завершена: дивизии приведены в повышенную готовность (+8%)!"
		},
		"requires_germany": true
	},
	{
		"id": "reich_subsidize_cartels",
		"category": "reich",
		"category_name": "КРИЗИС РЕЙХА: ОЛИГАРХИЯ",
		"title": "Секретные Субсидии Военно-Промышленным Картелям",
		"description": "Предоставление льготных кредитов концернам Круппа и Сименса в обмен на эксклюзивные поставки танков и лояльность советов директоров.",
		"cost_pc": 25.0,
		"cost_cap": 1,
		"cost_money": 0.15,
		"cooldown_turns": 3,
		"fire_only_once": false,
		"effects": {
			"modify_gdp": 0.6,
			"modify_military_factories": 2,
			"log": "Картели заключили секретные соглашения: ВВП +$0.6B, военные заводы +2!"
		},
		"requires_germany": true
	},
	{
		"id": "reich_press_crackdown",
		"category": "reich",
		"category_name": "КРИЗИС РЕЙХА: ПРОПАГАНДА",
		"title": "Чрезвычайный Надзор Рейхспрессы",
		"description": "Полный запрет независимых бюллетеней и цензура студенческих ячеек для подавления леворадикальных настроений в Руре.",
		"cost_pc": 30.0,
		"cost_cap": 1,
		"cost_money": 0.03,
		"cooldown_turns": 2,
		"fire_only_once": false,
		"effects": {
			"modify_radicalization": -8.0,
			"modify_legitimacy": 4.0,
			"log": "Типографии оппозиции опечатаны: радикализация -8%, стабильность укреплена!"
		},
		"requires_germany": true
	},
	{
		"id": "reich_ss_surveillance",
		"category": "reich",
		"category_name": "КРИЗИС РЕЙХА: СПЕЦСЛУЖБЫ",
		"title": "Развертывание Тайного Надзора СД",
		"description": "Усиление контрразведывательного режима в правительственном квартале и армейских казармах для предотвращения заговоров.",
		"cost_pc": 25.0,
		"cost_cap": 1,
		"cost_money": 0.04,
		"cooldown_turns": 3,
		"fire_only_once": false,
		"effects": {
			"modify_radicalization": -8.0,
			"modify_legitimacy": 4.0,
			"log": "Агентура СД ликвидировала ячейки заговорщиков: радикализация -8%!"
		},
		"requires_germany": true
	},

	# --- СОЕДИНЕННЫЕ ШТАТЫ АМЕРИКИ И ОФН ---
	{
		"id": "usa_civil_rights_executive_order",
		"category": "usa",
		"category_name": "БЕЛЫЙ ДОМ // ГРАЖДАНСКИЕ ПРАВА",
		"title": "Президентский Указ о Гражданских Правах",
		"description": "Исполнительный указ президента о запрете сегрегации на федеральных предприятиях и гарантиях избирательных прав.",
		"cost_pc": 35.0,
		"cost_cap": 2,
		"cost_money": 0.1,
		"cooldown_turns": 4,
		"fire_only_once": true,
		"effects": {
			"modify_legitimacy": 8.0,
			"modify_radicalization": -6.0,
			"modify_political_capital": 20.0,
			"log": "Президентский указ подписан: законность укреплена, прогрессивное крыло ликует!"
		},
		"requires_usa": true
	},
	{
		"id": "usa_ofn_airlift_africa",
		"category": "usa",
		"category_name": "ПЕНТАГОН // ОПЕРАЦИИ ОФН",
		"title": "Воздушный Мост ОФН в Южную Африку",
		"description": "Срочная отправка транспортных самолетов с винтовками М14 и военными инструкторами в Южную Африку.",
		"cost_pc": 25.0,
		"cost_cap": 1,
		"cost_money": 0.25,
		"cooldown_turns": 3,
		"fire_only_once": false,
		"effects": {
			"modify_weapons": 4000,
			"modify_readiness": 6.0,
			"modify_war_support": 5.0,
			"log": "Воздушный мост ОФН запущен: войска снабжены, доставлено 4,000 винтовок!"
		},
		"requires_usa": true
	},

	# --- МАКРОЭКОНОМИКА И ЦЕНТРАЛЬНЫЙ БАНК (ДЛЯ ВСЕХ) ---
	{
		"id": "econ_issue_war_bonds",
		"category": "economy",
		"category_name": "ЦЕНТРАЛЬНЫЙ БАНК // ФИНАНСЫ",
		"title": "Чрезвычайный Выпуск Патриотических Облигаций",
		"description": "Срочное привлечение ликвидности от населения и предприятий для латания бюджетной дыры ценой роста госдолга.",
		"cost_pc": 15.0,
		"cost_cap": 0,
		"cost_money": 0.0,
		"cooldown_turns": 3,
		"fire_only_once": false,
		"effects": {
			"modify_reserves": 0.5,
			"modify_debt": 0.6,
			"log": "Облигационный заем размещен: казна получила +$0.5 млрд резервов (долг +$0.6B)!"
		},
		"requires_general": true
	},
	{
		"id": "econ_strategic_grain",
		"category": "economy",
		"category_name": "ГОСПЛАН // СНАБЖЕНИЕ",
		"title": "Откупоривание Стратегических Госрезервов Зерна",
		"description": "Выброс продовольствия на рынки для остановки продовольственной паники и стабилизации потребительских цен.",
		"cost_pc": 20.0,
		"cost_cap": 1,
		"cost_money": 0.05,
		"cooldown_turns": 4,
		"fire_only_once": false,
		"effects": {
			"modify_radicalization": -6.0,
			"modify_legitimacy": 5.0,
			"log": "Продовольственные резервы распределены: недовольство трудящихся снизилось на 6%!"
		},
		"requires_general": true
	},
	{
		"id": "econ_stimulus_infrastructure",
		"category": "economy",
		"category_name": "ГОСПЛАН // КАПИТАЛОВЛОЖЕНИЯ",
		"title": "Масштабный Пакет Инфраструктурных Инвестиций",
		"description": "Государственное финансирование электрификации, мостов и железнодорожных узлов для расширения экономического базиса.",
		"cost_pc": 25.0,
		"cost_cap": 1,
		"cost_money": 0.4,
		"cooldown_turns": 5,
		"fire_only_once": false,
		"effects": {
			"modify_gdp": 1.2,
			"modify_civilian_factories": 2,
			"modify_legitimacy": 5.0,
			"log": "Инфраструктурные объекты введены в строй: ВВП +$1.2B, фабрики +2!"
		},
		"requires_general": true
	},

	# --- ВОЕННЫЕ МАНЕВРЫ (ДЛЯ ВСЕХ) ---
	{
		"id": "mil_large_scale_drills",
		"category": "military",
		"category_name": "ГЕНШТАБ // УЧЕНИЯ",
		"title": "Общевойсковые Стратегические Маневры",
		"description": "Отработка взаимодействия бронетехники и пехоты в полевых условиях с боевыми стрельбами.",
		"cost_pc": 15.0,
		"cost_cap": 1,
		"cost_money": 0.1,
		"cooldown_turns": 3,
		"fire_only_once": false,
		"effects": {
			"modify_readiness": 12.0,
			"modify_war_support": 6.0,
			"log": "Маневры успешно завершены: дивизии отработали прорыв обороны (+12% боеготовность)!"
		},
		"requires_general": true
	},
	{
		"id": "mil_conscription_expansion",
		"category": "military",
		"category_name": "ГЕНШТАБ // ПРИЗЫВ",
		"title": "Расширенный Призыв Новобранцев",
		"description": "Объявление дополнительного призыва резервистов и ускоренная подготовка в учебных лагерях.",
		"cost_pc": 20.0,
		"cost_cap": 1,
		"cost_money": 0.05,
		"cooldown_turns": 3,
		"fire_only_once": false,
		"effects": {
			"modify_manpower": 12000,
			"modify_radicalization": 3.0,
			"log": "Призывные пункты приняли пополнение: +12,000 бойцов в резерв армии!"
		},
		"requires_general": true
	},

	# --- ГОСУДАРСТВЕННЫЙ АППАРАТ И СПЕЦСЛУЖБЫ (ДЛЯ ВСЕХ) ---
	{
		"id": "state_anti_corruption_purge",
		"category": "state",
		"category_name": "ГОСБЕЗОПАСНОСТЬ // КОНТРОЛЬ",
		"title": "Антикоррупционная Зачистка Аппарата Снабжения",
		"description": "Проведение внезапных ревизий на складах и показательные трибуналы над расхитителями государственного имущества.",
		"cost_pc": 35.0,
		"cost_cap": 2,
		"cost_money": 0.02,
		"cooldown_turns": 5,
		"fire_only_once": false,
		"effects": {
			"modify_legitimacy": 8.0,
			"modify_weapons": 1200,
			"log": "Ревизии выявили тайные схроны: возвращено 1,200 винтовок, авторитет власти +8%!"
		},
		"requires_general": true
	},
	{
		"id": "state_black_budget_covert",
		"category": "state",
		"category_name": "СПЕЦСЛУЖБЫ // АГЕНТУРА",
		"title": "Секретное Финансирование «Черного Бюджета»",
		"description": "Выделение неучтенных ассигнований в распоряжение внешней разведки для тайных операций за рубежом.",
		"cost_pc": 30.0,
		"cost_cap": 2,
		"cost_money": 0.1,
		"cooldown_turns": 4,
		"fire_only_once": false,
		"effects": {
			"modify_political_capital": 35.0,
			"modify_legitimacy": 3.0,
			"log": "Черный бюджет пополнен: резидентура за рубежом получила неограниченные фонды!"
		},
		"requires_general": true
	}
]


func setup(state: CountryState, tm: TurnManager, loader: ContentLoader = null) -> void:
	player_state = state
	turn_manager = tm
	content_loader = loader if loader != null else ContentLoader.get_instance()

	if turn_manager != null:
		if not turn_manager.turn_started.is_connected(_on_turn_started):
			turn_manager.turn_started.connect(_on_turn_started)

	load_decisions()


## Загрузка и фильтрация всех доступных решений для текущей державы игрока
func load_decisions() -> void:
	all_decisions.clear()
	_decisions_by_id.clear()

	var tag := player_state.country_tag.to_upper() if player_state != null else "KOM"
	var is_russian := _is_russian_tag(tag)
	var is_german := _is_german_tag(tag)
	var is_usa := (tag == "USA")

	var dynamic_decs: Array[Dictionary] = []
	if content_loader != null:
		dynamic_decs = content_loader.load_country_decisions(tag)

	var existing_ids: Dictionary = {}

	# 1. Добавляем динамические решения, прошедшие строгую валидацию принадлежности
	for d in dynamic_decs:
		var did = str(d.get("id", ""))
		if did.is_empty() or existing_ids.has(did):
			continue

		if not _is_decision_applicable_to_country(d, tag, is_russian, is_german, is_usa):
			continue

		all_decisions.append(d.duplicate(true))
		existing_ids[did] = true
		_decisions_by_id[did] = d

	# 2. Добавляем базовые проверенные резервные инициативы (Fallback)
	for fd in fallback_decisions:
		var fid = str(fd.get("id", ""))
		if existing_ids.has(fid):
			continue

		if not _is_decision_applicable_to_country(fd, tag, is_russian, is_german, is_usa):
			continue

		all_decisions.append(fd.duplicate(true))
		existing_ids[fid] = true
		_decisions_by_id[fid] = fd

	decisions_updated.emit()


## Возвращает список решений для отображения (с опциональной фильтрацией по категории)
func get_decisions(category_id: String = "all") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var tag := player_state.country_tag.to_upper() if player_state != null else "KOM"

	for dec in all_decisions:
		# Фильтрация по категории
		var dec_cat = str(dec.get("category", "")).to_lower()
		if category_id != "all" and dec_cat != category_id:
			continue

		# Проверка однократности
		var did = str(dec.get("id", ""))
		if dec.get("fire_only_once", false) and executed_once.get(did, false):
			continue

		# Проверка обязательных и блокирующих флагов
		if player_state != null:
			if dec.has("required_flags"):
				var missing_flag := false
				for rf in dec["required_flags"]:
					if not player_state.has_flag(rf):
						missing_flag = true
						break
				if missing_flag:
					continue

			if dec.has("blocked_flags"):
				var has_blocked := false
				for bf in dec["blocked_flags"]:
					if player_state.has_flag(bf):
						has_blocked = true
						break
				if has_blocked:
					continue

		result.append(dec)

	return result


## Проверяет, хватает ли у игрока ресурсов на утверждение решения
func can_afford(dec: Dictionary) -> bool:
	if player_state == null:
		return false

	var cost_pc = float(dec.get("cost_pc", dec.get("cost", 0.0)))
	var cost_cap = int(dec.get("cost_cap", 0))
	var cost_money = float(dec.get("cost_money", 0.0))

	var has_pc = player_state.political_capital >= cost_pc
	var has_cap = player_state.current_cap >= cost_cap
	var has_money = (player_state.liquid_reserves_billions >= cost_money) or (cost_money <= 0.0)

	var on_cd = is_on_cooldown(dec)
	var did = str(dec.get("id", ""))
	var already_taken = dec.get("fire_only_once", false) and executed_once.get(did, false)

	return has_pc and has_cap and has_money and not on_cd and not already_taken


## Проверяет, находится ли решение на кулдауне
func is_on_cooldown(dec: Dictionary) -> bool:
	var did = str(dec.get("id", ""))
	var current_turn = turn_manager.current_turn if turn_manager != null else 1
	var cd_turn = cooldowns.get(did, 0)
	return current_turn < cd_turn


## Возвращает количество оставшихся ходов кулдауна
func get_cooldown_remaining(dec: Dictionary) -> int:
	var did = str(dec.get("id", ""))
	var current_turn = turn_manager.current_turn if turn_manager != null else 1
	var cd_turn = cooldowns.get(did, 0)
	return maxi(0, cd_turn - current_turn)


## Исполняет решение: списывает ресурсы, накладывает кулдаун и применяет эффекты
func execute_decision(decision_id: String) -> bool:
	if not _decisions_by_id.has(decision_id):
		push_warning("DecisionManager: Попытка выполнить неизвестное решение: %s" % decision_id)
		return false

	var dec: Dictionary = _decisions_by_id[decision_id]
	if not can_afford(dec):
		push_warning("DecisionManager: Недостаточно ресурсов для решения: %s" % decision_id)
		return false

	var current_turn = turn_manager.current_turn if turn_manager != null else 1
	var cost_pc = float(dec.get("cost_pc", dec.get("cost", 0.0)))
	var cost_cap = int(dec.get("cost_cap", 0))
	var cost_money = float(dec.get("cost_money", 0.0))

	# Списание ресурсов
	player_state.political_capital = maxf(player_state.political_capital - cost_pc, 0.0)
	player_state.current_cap = maxi(player_state.current_cap - cost_cap, 0)
	player_state.liquid_reserves_billions = maxf(player_state.liquid_reserves_billions - cost_money, 0.0)

	# Установка кулдауна или флага однократного выполнения
	if dec.get("fire_only_once", false):
		executed_once[decision_id] = true
	else:
		var cd_turns = int(dec.get("cooldown_turns", 2))
		cooldowns[decision_id] = current_turn + cd_turns

	# Применение эффектов к CountryState
	var eff: Dictionary = dec.get("effects", {})
	_apply_effects(eff)

	decision_executed.emit(decision_id, eff)
	decisions_updated.emit()
	return true


func _apply_effects(eff: Dictionary) -> void:
	if player_state == null:
		return

	if eff.has("modify_weapons"):
		player_state.infantry_weapons_stockpile += int(eff["modify_weapons"])
	if eff.has("modify_heavy_equipment"):
		player_state.heavy_equipment_stockpile += int(eff["modify_heavy_equipment"])
	if eff.has("modify_manpower"):
		player_state.manpower_pool += int(eff["modify_manpower"])
	if eff.has("modify_readiness"):
		player_state.army_readiness = clampf(player_state.army_readiness + float(eff["modify_readiness"]), 0.0, 100.0)
	if eff.has("modify_legitimacy"):
		player_state.legitimacy = clampf(player_state.legitimacy + float(eff["modify_legitimacy"]), 0.0, 100.0)
	if eff.has("modify_radicalization"):
		player_state.radicalization = clampf(player_state.radicalization + float(eff["modify_radicalization"]), 0.0, 100.0)
	if eff.has("modify_war_support"):
		player_state.war_support_percent = clampf(player_state.war_support_percent + float(eff["modify_war_support"]), 0.0, 100.0)
	if eff.has("modify_gdp"):
		player_state.gdp_billions = maxf(player_state.gdp_billions + float(eff["modify_gdp"]), 0.1)
	if eff.has("modify_reserves"):
		player_state.liquid_reserves_billions += float(eff["modify_reserves"])
	if eff.has("modify_debt"):
		player_state.national_debt_billions += float(eff["modify_debt"])
	if eff.has("modify_military_factories"):
		player_state.military_factories += int(eff["modify_military_factories"])
	if eff.has("modify_civilian_factories"):
		player_state.civilian_factories += int(eff["modify_civilian_factories"])
	if eff.has("modify_inflation"):
		player_state.inflation_rate = clampf(player_state.inflation_rate + float(eff["modify_inflation"]), 0.0, 1.0)
	if eff.has("modify_interest_rate"):
		player_state.interest_rate = clampf(player_state.interest_rate + float(eff["modify_interest_rate"]), 0.01, 0.5)
	if eff.has("modify_political_capital"):
		player_state.political_capital = maxf(player_state.political_capital + float(eff["modify_political_capital"]), 0.0)
	if eff.has("modify_stability"):
		player_state.stability += float(eff["modify_stability"])
	if eff.has("set_flags") and eff["set_flags"] is Dictionary:
		for fk in eff["set_flags"].keys():
			player_state.set_flag(fk, eff["set_flags"][fk])
	if eff.has("clear_flags") and eff["clear_flags"] is Array:
		for cf in eff["clear_flags"]:
			player_state.set_flag(cf, false)


func _on_turn_started(_turn: int, _date: String) -> void:
	decisions_updated.emit()


## Строгая проверка принадлежности решения государству
func _is_decision_applicable_to_country(dec: Dictionary, tag: String, is_russian: bool, is_german: bool, is_usa: bool) -> bool:
	var req_tags: Array = dec.get("requires_tags", [])
	if not req_tags.is_empty():
		return req_tags.has(tag)

	if dec.get("requires_russia", false):
		return is_russian
	if dec.get("requires_germany", false):
		return is_german
	if dec.get("requires_usa", false):
		return is_usa
	if dec.get("requires_general", false):
		return true

	# По умолчанию, если нет тегов и флагов, не отдаем чужим странам
	return false


func _is_russian_tag(tag: String) -> bool:
	return tag in [
		"KOM", "WRS", "WRRF", "SAM", "OMS", "VYT", "SVR", "TYM", "TYU", "IRK",
		"BRY", "TOM", "NOV", "KEM", "MAG", "AMR", "CHT", "YAK", "ZLT", "ORE",
		"MGN", "DRL", "BKR", "TAR", "YGR", "VOR", "KAZ", "AKT", "ARL", "KOK",
		"PAV", "NPL", "KRK", "ALT", "KMC", "MIR", "KHA", "VLG", "KOS", "ONE",
		"ONG", "PRM", "SBA", "URL"
	] or (RussianUnificationManager != null and RussianUnificationManager.is_warlord(tag))


func _is_german_tag(tag: String) -> bool:
	return tag in ["GER", "BOR", "SPE", "GOR", "HEY", "BGR", "SGR", "GGR", "HGR"]


## Сериализация состояния для сохранений
func save_state() -> Dictionary:
	return {
		"cooldowns": cooldowns.duplicate(true),
		"executed_once": executed_once.duplicate(true)
	}


## Десериализация состояния из сохранения
func load_state(data: Dictionary) -> void:
	if data.has("cooldowns") and data["cooldowns"] is Dictionary:
		cooldowns = data["cooldowns"].duplicate(true)
	if data.has("executed_once") and data["executed_once"] is Dictionary:
		executed_once = data["executed_once"].duplicate(true)
	decisions_updated.emit()
