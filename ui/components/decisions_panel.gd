class_name DecisionsPanel
extends Control

##
## DecisionsPanel: Аутентичный экран оперативных решений и кризисов TNO (Decisions Tab)
## Управляет решениями Смуты, интригами престолонаследия Рейха и чрезвычайными декретами.
##

signal decision_executed(decision_id: String, effects: Dictionary)

@export var player_state: CountryState
@export var turn_manager: TurnManager

var active_category: String = "all"
var decisions_cooldowns: Dictionary = {} # decision_id -> turn_available

# UI References
var category_list_container: VBoxContainer
var decisions_list_container: VBoxContainer
var log_rich_text: RichTextLabel
var lbl_status_counter: Label

# Список базовых резервных решений в стиле TNO (Fallback)
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
		"effects": {
			"modify_radicalization": -8.0,
			"modify_legitimacy": 4.0,
			"log": "Агентура СД ликвидировала ячейки заговорщиков: радикализация -8%!"
		},
		"requires_germany": true
	},
	{
		"id": "reich_ostheer_parade",
		"category": "reich",
		"category_name": "КРИЗИС РЕЙХА: ПРОПАГАНДА",
		"title": "Триумфальный Смотр Дивизий Вермахта",
		"description": "Масштабный военный парад в столице с демонстрацией новых танков для поднятия национального духа.",
		"cost_pc": 20.0,
		"cost_cap": 1,
		"cost_money": 0.08,
		"cooldown_turns": 4,
		"effects": {
			"modify_war_support": 8.0,
			"modify_legitimacy": 6.0,
			"modify_readiness": 5.0,
			"log": "Смотр войск воодушевил нацию: военная поддержка +8%, авторитет +6%!"
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
		"effects": {
			"modify_weapons": 4000,
			"modify_readiness": 6.0,
			"modify_war_support": 5.0,
			"log": "Воздушный мост ОФН запущен: войска снабжены, доставлено 4,000 винтовок!"
		},
		"requires_usa": true
	},
	{
		"id": "usa_cia_operation_gladio",
		"category": "usa",
		"category_name": "ЛЭНГЛИ // СПЕЦОПЕРАЦИИ",
		"title": "Тайная Сеть ЦРУ в Европе (Operation Gladio)",
		"description": "Финансирование подпольных ячеек сопротивления и тайных складов вооружения в оккупированной Европе.",
		"cost_pc": 30.0,
		"cost_cap": 2,
		"cost_money": 0.15,
		"cooldown_turns": 5,
		"effects": {
			"modify_weapons": 2500,
			"modify_heavy_equipment": 50,
			"modify_legitimacy": 4.0,
			"log": "Сеть агентов ЦРУ активирована в Европе: поток разведданных налажен!"
		},
		"requires_usa": true
	},
	{
		"id": "usa_nasa_apollo_surge",
		"category": "usa",
		"category_name": "МЫС КАНАВЕРАЛ // КОСМОС",
		"title": "Экстренные Ассигнования NASA на Лунную Гонку",
		"description": "Дополнительное финансирование программы «Аполлон» для технологического реванша в космической гонке.",
		"cost_pc": 40.0,
		"cost_cap": 1,
		"cost_money": 0.5,
		"cooldown_turns": 6,
		"effects": {
			"modify_legitimacy": 12.0,
			"modify_war_support": 10.0,
			"modify_gdp": 0.8,
			"log": "Ассигнования одобрены: ученые NASA рапортуют о прорыве в лунной программе!"
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
		"effects": {
			"modify_radicalization": -6.0,
			"modify_legitimacy": 5.0,
			"log": "Продовольственные резервы распределены: недовольство трудящихся снизилось на 6%!"
		},
		"requires_general": true
	},
	{
		"id": "econ_raise_interest_rates",
		"category": "economy",
		"category_name": "ЦЕНТРАЛЬНЫЙ БАНК // МОНЕТАРНАЯ ПОЛИТИКА",
		"title": "Экстренное Повышение Ключевой Ставки ЦБ",
		"description": "Ужесточение денежно-кредитной политики Центробанка для обуздания инфляционной спирали ценой временного охлаждения роста.",
		"cost_pc": 20.0,
		"cost_cap": 1,
		"cost_money": 0.0,
		"cooldown_turns": 3,
		"effects": {
			"modify_inflation": -0.02,
			"modify_interest_rate": 0.015,
			"modify_radicalization": -3.0,
			"log": "Ставка повышена: инфляционное давление снижено на 2.0%!"
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
		"effects": {
			"modify_gdp": 1.2,
			"modify_civilian_factories": 2,
			"modify_legitimacy": 5.0,
			"log": "Инфраструктурные объекты введены в строй: ВВП +$1.2B, фабрики +2!"
		},
		"requires_general": true
	},
	{
		"id": "econ_defense_procurement_surge",
		"category": "economy",
		"category_name": "ВПК // ГОСОБОРОНЗАКАЗ",
		"title": "Экстренный Госзаказ Предприятиям ВПК",
		"description": "Перевод дополнительных производственных мощностей на выпуск военной техники и стрелкового вооружения.",
		"cost_pc": 30.0,
		"cost_cap": 1,
		"cost_money": 0.3,
		"cooldown_turns": 4,
		"effects": {
			"modify_military_factories": 2,
			"modify_weapons": 5000,
			"modify_heavy_equipment": 120,
			"log": "Оборонный заказ размещен: +2 военных завода, +5,000 винтовок на склады!"
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
		"effects": {
			"modify_manpower": 12000,
			"modify_radicalization": 3.0,
			"log": "Призывные пункты приняли пополнение: +12,000 бойцов в резерв армии!"
		},
		"requires_general": true
	},

	# --- ГЕОПОЛИТИКА И ДИПЛОМАТИЯ (ДЛЯ ВСЕХ) ---
	{
		"id": "diplo_foreign_aid_mission",
		"category": "diplomacy",
		"category_name": "МИД // ДИПЛОМАТИЯ",
		"title": "Дипломатический Пакет Помощи Третьему Миру",
		"description": "Направление продовольствия, медикаментов и кредитов неприсоединившимся государствам для расширения сферы влияния.",
		"cost_pc": 25.0,
		"cost_cap": 1,
		"cost_money": 0.2,
		"cooldown_turns": 4,
		"effects": {
			"modify_legitimacy": 7.0,
			"modify_war_support": 4.0,
			"log": "Дипломатический транш доставлен: авторитет державы на международной арене вырос!"
		},
		"requires_general": true
	},
	{
		"id": "diplo_border_fortification",
		"category": "diplomacy",
		"category_name": "ОБОРОНА // ФОРТИФИКАЦИЯ",
		"title": "Инженерное Укрепление Линии Демаркации",
		"description": "Возведение укрепленных опорных пунктов, минных полей и ДОТов вдоль угрожаемых участков государственной границы.",
		"cost_pc": 25.0,
		"cost_cap": 1,
		"cost_money": 0.15,
		"cooldown_turns": 5,
		"effects": {
			"modify_readiness": 8.0,
			"modify_heavy_equipment": 60,
			"log": "Оборонительный рубеж возведен: безопасность приграничных рубежей гарантирована!"
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
		"effects": {
			"modify_political_capital": 35.0,
			"modify_legitimacy": 3.0,
			"log": "Черный бюджет пополнен: резидентура за рубежом получила неограниченные фонды!"
		},
		"requires_general": true
	},
	{
		"id": "state_emergency_decree_curfew",
		"category": "state",
		"category_name": "МВД // ПРАВОПОРЯДОК",
		"title": "Чрезвычайный Декрет: Комендантский Час",
		"description": "Введение жесткого патрулирования улиц армейскими нарядами и временный запрет собраний для подавления беспорядков.",
		"cost_pc": 20.0,
		"cost_cap": 1,
		"cost_money": 0.02,
		"cooldown_turns": 3,
		"effects": {
			"modify_radicalization": -10.0,
			"modify_legitimacy": -4.0,
			"log": "Комендантский час введен: улицы зачищены от провокаторов (-10% радикализации)!"
		},
		"requires_general": true
	}
]

var all_decisions: Array[Dictionary] = []


func _tr(key: String, default_text: String) -> String:
	if is_inside_tree():
		var loc = get_node_or_null("/root/LocalizationManager")
		if loc != null and loc.has_method("tr_key"):
			return loc.tr_key(key, default_text)
	return tr(key) if tr(key) != key else default_text


func _on_locale_changed(_locale: String) -> void:
	_build_category_buttons()
	refresh_panel()


func _ready() -> void:
	if is_inside_tree():
		var loc = get_node_or_null("/root/LocalizationManager")
		if loc != null and loc.has_signal("locale_changed"):
			if not loc.locale_changed.is_connected(_on_locale_changed):
				loc.locale_changed.connect(_on_locale_changed)
	_build_ui()
	_load_decisions_for_player()
	refresh_panel()


func setup(state: CountryState, tm: TurnManager) -> void:
	player_state = state
	turn_manager = tm
	if turn_manager != null:
		if not turn_manager.turn_started.is_connected(_on_turn_started):
			turn_manager.turn_started.connect(_on_turn_started)
	_load_decisions_for_player()
	refresh_panel()


## Динамическая загрузка решений для государства игрока из Data Pipeline
func _load_decisions_for_player() -> void:
	var tag = player_state.country_tag if player_state != null else "KOM"
	var loader = ContentLoader.get_instance()
	var dynamic_decs: Array[Dictionary] = []
	if loader != null:
		dynamic_decs = loader.load_country_decisions(tag)

	if not dynamic_decs.is_empty():
		all_decisions = dynamic_decs
	else:
		all_decisions = fallback_decisions.duplicate(true)

	_build_category_buttons()


func _on_turn_started(_turn: int, _date: String) -> void:
	refresh_panel()


func _build_ui() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0

	var main_vbox = VBoxContainer.new()
	main_vbox.anchor_right = 1.0
	main_vbox.anchor_bottom = 1.0
	main_vbox.add_theme_constant_override("separation", 8)
	add_child(main_vbox)

	# 1. Заголовок терминала решений
	var header_panel = PanelContainer.new()
	header_panel.custom_minimum_size = Vector2(0, 48)
	TNOTheme.apply_panel_style(header_panel, TNOTheme.COLOR_BORDER_CYAN, Color(0.03, 0.06, 0.08, 0.95))
	main_vbox.add_child(header_panel)

	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 12)
	header_panel.add_child(header_hbox)

	var title_lbl = Label.new()
	title_lbl.text = _tr("DEC_TITLE", " ОПЕРАТИВНЫЕ РЕШЕНИЯ И ГОСУДАРСТВЕННЫЕ ИНИЦИАТИВЫ // DECISIONS ")
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", TNOTheme.COLOR_BORDER_CYAN)
	header_hbox.add_child(title_lbl)

	lbl_status_counter = Label.new()
	lbl_status_counter.text = _tr("DEC_AVAILABLE_EMPTY", "[ ДОСТУПНО: 0 ]")
	lbl_status_counter.add_theme_font_size_override("font_size", 12)
	lbl_status_counter.add_theme_color_override("font_color", TNOTheme.COLOR_BORDER_AMBER)
	lbl_status_counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_status_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header_hbox.add_child(lbl_status_counter)

	# 2. Основное тело: Слева фильтр категорий, Справа список карточек
	var body_hbox = HBoxContainer.new()
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 10)
	main_vbox.add_child(body_hbox)

	# Левая колонка: Категории
	var cat_panel = PanelContainer.new()
	cat_panel.custom_minimum_size = Vector2(240, 0)
	TNOTheme.apply_panel_style(cat_panel, TNOTheme.COLOR_BORDER_DIM, Color(0.02, 0.04, 0.06, 0.95))
	body_hbox.add_child(cat_panel)

	var cat_vbox = VBoxContainer.new()
	cat_vbox.add_theme_constant_override("separation", 6)
	cat_panel.add_child(cat_vbox)

	var cat_header = Label.new()
	cat_header.text = _tr("DEC_CATEGORIES_TITLE", "КАТЕГОРИИ ДЕКРЕТОВ")
	cat_header.add_theme_font_size_override("font_size", 12)
	cat_header.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_SECONDARY)
	cat_vbox.add_child(cat_header)

	var sep = HSeparator.new()
	cat_vbox.add_child(sep)

	category_list_container = VBoxContainer.new()
	category_list_container.add_theme_constant_override("separation", 4)
	cat_vbox.add_child(category_list_container)

	_build_category_buttons()

	# Правая колонка: Список решений и телеграфный лог
	var right_vbox = VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 8)
	body_hbox.add_child(right_vbox)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(scroll)

	decisions_list_container = VBoxContainer.new()
	decisions_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	decisions_list_container.add_theme_constant_override("separation", 8)
	scroll.add_child(decisions_list_container)

	# Телеграфный лог результатов
	var log_panel = PanelContainer.new()
	log_panel.custom_minimum_size = Vector2(0, 90)
	TNOTheme.apply_panel_style(log_panel, TNOTheme.COLOR_BORDER_DIM, Color(0.01, 0.03, 0.04, 0.95))
	right_vbox.add_child(log_panel)

	log_rich_text = RichTextLabel.new()
	log_rich_text.bbcode_enabled = true
	log_rich_text.text = _tr("DEC_TELEGRAPH_WAIT", "[color=#557766]ШТАБНОЙ ТЕЛЕГРАФ // Ожидание директив ставки Верховного Командования...[/color]")
	log_panel.add_child(log_rich_text)


func _build_category_buttons() -> void:
	if category_list_container == null:
		return
	for c in category_list_container.get_children():
		c.queue_free()

	var is_russian = false
	var is_german = false
	var is_usa = false
	var tag = ""
	if player_state != null:
		tag = player_state.country_tag.to_upper()
		is_russian = tag in ["WRS", "KOM", "OMS", "SVR", "SAM", "NOV", "TYU", "IRK", "CHT", "MAG", "KEM", "VYT", "BRY", "SBA", "ONE", "ORE", "ZLT", "DRL", "MGN", "VOR"] or RussianUnificationManager.is_warlord(tag)
		is_german = tag in ["GER", "SPE", "BOR", "GOR", "HEY", "BGR", "SGR", "GGR", "HGR"]
		is_usa = (tag == "USA")

	var cat_labels: Dictionary = {
		"all": _tr("DEC_CAT_ALL", " ВСЕ ОПЕРАЦИИ"),
		"smuta": _tr("DEC_CAT_SMUTA", " РУССКАЯ СМУТА"),
		"komi": _tr("DEC_CAT_KOMI", " ВЫБОРЫ В КОМИ"),
		"development": _tr("DEC_CAT_DEVELOPMENT", " РАЗВИТИЕ РЕГИОНОВ"),
		"reich": _tr("DEC_CAT_REICH", " КРИЗИС РЕЙХА"),
		"usa": _tr("DEC_CAT_USA", " ДОКТРИНА США // ОФН"),
		"economy": _tr("DEC_CAT_ECONOMY", " ЦЕНТРАЛЬНЫЙ БАНК"),
		"military": _tr("DEC_CAT_MILITARY", " ВОЕННЫЕ МАНЕВРЫ"),
		"diplomacy": _tr("DEC_CAT_DIPLOMACY", " ГЕОПОЛИТИКА"),
		"state": _tr("DEC_CAT_STATE", " ГОСБЕЗОПАСНОСТЬ")
	}

	var present_cats: Dictionary = {"all": true}
	for dec in all_decisions:
		var req_tags = dec.get("requires_tags", [])
		if not req_tags.is_empty() and not req_tags.has(tag):
			continue
		if dec.get("requires_russia", false) and not is_russian:
			continue
		if dec.get("requires_germany", false) and not is_german:
			continue
		if dec.get("requires_usa", false) and not is_usa:
			continue
		var c = dec.get("category", "state")
		present_cats[c] = true

	var categories: Array[Dictionary] = []
	for cat_id in ["all", "smuta", "komi", "development", "reich", "usa", "economy", "military", "diplomacy", "state"]:
		if present_cats.has(cat_id):
			var c_name = cat_labels.get(cat_id, " " + cat_id.to_upper())
			categories.append({"id": cat_id, "name": c_name})

	for c_id in present_cats.keys():
		if not cat_labels.has(c_id):
			categories.append({"id": c_id, "name": " " + str(c_id).to_upper()})

	for cat in categories:
		var btn = Button.new()
		btn.text = cat["name"]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 34)
		TNOTheme.apply_button_style(btn, TNOTheme.COLOR_BORDER_CYAN if active_category == cat["id"] else TNOTheme.COLOR_BORDER_DIM)
		var cid = cat["id"]
		btn.pressed.connect(func():
			active_category = cid
			_build_category_buttons()
			refresh_panel()
		)
		category_list_container.add_child(btn)


func refresh_panel() -> void:
	if decisions_list_container == null or player_state == null:
		return

	for c in decisions_list_container.get_children():
		c.queue_free()

	var current_turn = turn_manager.current_turn if turn_manager != null else 1
	var tag = player_state.country_tag.to_upper()
	var is_russian = tag in ["WRS", "KOM", "OMS", "SVR", "SAM", "NOV", "TYU", "IRK", "CHT", "MAG", "KEM", "VYT", "BRY", "SBA", "ONE", "ORE", "ZLT", "DRL", "MGN", "VOR"] or RussianUnificationManager.is_warlord(tag)
	var is_german = tag in ["GER", "SPE", "BOR", "GOR", "HEY", "BGR", "SGR", "GGR", "HGR"]
	var is_usa = (tag == "USA")

	var available_count = 0

	for dec in all_decisions:
		# Фильтрация по конкретным тегам державы
		var req_tags = dec.get("requires_tags", [])
		if not req_tags.is_empty() and not req_tags.has(tag):
			continue

		# Фильтрация по региону / типу державы
		if dec.get("requires_russia", false) and not is_russian:
			continue
		if dec.get("requires_germany", false) and not is_german:
			continue
		if dec.get("requires_usa", false) and not is_usa:
			continue

		# Проверка обязательных и блокирующих флагов
		if dec.has("required_flags"):
			var missing_flag = false
			for rf in dec["required_flags"]:
				if not player_state.has_flag(rf):
					missing_flag = true
					break
			if missing_flag:
				continue

		if dec.has("blocked_flags"):
			var has_blocked = false
			for bf in dec["blocked_flags"]:
				if player_state.has_flag(bf):
					has_blocked = true
					break
			if has_blocked:
				continue

		# Фильтрация по выбранной категории
		if active_category != "all" and dec.get("category", "") != active_category:
			continue

		var dec_card = _create_decision_card(dec, current_turn)
		decisions_list_container.add_child(dec_card)
		available_count += 1

	if lbl_status_counter != null:
		lbl_status_counter.text = _tr("DEC_AVAILABLE_FMT", "[ ДОСТУПНО: %d ИНИЦИАТИВ ]") % available_count


func _create_decision_card(dec: Dictionary, current_turn: int) -> Control:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 100)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var dec_id = dec["id"]
	var cd_turn = decisions_cooldowns.get(dec_id, 0)
	var on_cooldown = (current_turn < cd_turn)
	var cd_remaining = cd_turn - current_turn

	var cost_pc = float(dec.get("cost_pc", 0.0))
	var cost_cap = int(dec.get("cost_cap", 0))
	var cost_money = float(dec.get("cost_money", 0.0))

	var has_pc = player_state.political_capital >= cost_pc
	var has_cap = player_state.current_cap >= cost_cap
	var has_money = (player_state.liquid_reserves_billions >= cost_money) or (cost_money <= 0.0)

	var can_afford = has_pc and has_cap and has_money and not on_cooldown

	var border_col = TNOTheme.COLOR_BORDER_CYAN if can_afford else (TNOTheme.COLOR_BORDER_AMBER if on_cooldown else TNOTheme.COLOR_BORDER_DIM)
	var bg_col = Color(0.03, 0.06, 0.08, 0.95) if can_afford else Color(0.02, 0.03, 0.04, 0.90)
	TNOTheme.apply_panel_style(panel, border_col, bg_col)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)

	# Иконка категории
	var icon_rect = TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(48, 48)
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon_path = "res://assets/gfx/interface/war_support_icon.png"
	if dec["category"] == "economy":
		icon_path = "res://assets/gfx/interface/industrial_capacity_icon.png"
	elif dec["category"] == "smuta":
		icon_path = "res://assets/gfx/interface/manpower_icon.png"
	elif dec["category"] == "usa":
		icon_path = "res://assets/gfx/interface/flag_overlay_tno.png"
	elif dec["category"] == "military":
		icon_path = "res://assets/gfx/interface/war_support_icon.png"
	elif dec["category"] == "state":
		icon_path = "res://assets/gfx/interface/stability_icon.png"
	icon_rect.texture = TNOTheme.get_texture(icon_path)
	hbox.add_child(icon_rect)

	# Текстовое досье
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	hbox.add_child(vbox)

	var cat_lbl = Label.new()
	cat_lbl.text = dec.get("category_name", _tr("DEC_DEFAULT_CAT", "ОПЕРАЦИЯ"))
	cat_lbl.add_theme_font_size_override("font_size", 10)
	cat_lbl.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_SECONDARY)
	vbox.add_child(cat_lbl)

	var title_lbl = Label.new()
	title_lbl.text = dec["title"]
	title_lbl.add_theme_font_size_override("font_size", 13)
	title_lbl.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_PRIMARY if can_afford else TNOTheme.COLOR_TEXT_SECONDARY)
	vbox.add_child(title_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = dec["description"]
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.70))
	vbox.add_child(desc_lbl)

	# Плашка стоимости и кнопка выполнения
	var right_col = VBoxContainer.new()
	right_col.custom_minimum_size = Vector2(170, 0)
	right_col.alignment = BoxContainer.ALIGNMENT_CENTER
	right_col.add_theme_constant_override("separation", 6)
	hbox.add_child(right_col)

	var cost_str = _tr("DEC_COST_HEADER", "ЗАТРАТЫ:\n")
	if cost_pc > 0.0: cost_str += "[%d PC] " % int(cost_pc)
	if cost_cap > 0: cost_str += "[%d CAP] " % cost_cap
	if cost_money > 0.0: cost_str += "[$%.2fB] " % cost_money

	var cost_lbl = Label.new()
	cost_lbl.text = cost_str
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_lbl.add_theme_font_size_override("font_size", 10)
	cost_lbl.add_theme_color_override("font_color", TNOTheme.COLOR_BORDER_AMBER if can_afford else Color(0.7, 0.3, 0.3))
	right_col.add_child(cost_lbl)

	var btn_execute = Button.new()
	btn_execute.custom_minimum_size = Vector2(0, 36)
	if on_cooldown:
		btn_execute.text = _tr("DEC_BTN_COOLDOWN", "КД: %d ХОД") % cd_remaining
		btn_execute.disabled = true
	elif not can_afford:
		btn_execute.text = _tr("DEC_BTN_CANNOT_AFFORD", "НЕДОСТАТОЧНО")
		btn_execute.disabled = true
	else:
		btn_execute.text = _tr("DEC_BTN_CONFIRM", "[ УТВЕРДИТЬ ]")
		btn_execute.disabled = false
		TNOTheme.apply_button_style(btn_execute, TNOTheme.COLOR_BORDER_CYAN, Color(0.08, 0.14, 0.16, 0.95))

	btn_execute.pressed.connect(func(): _execute_decision(dec))
	right_col.add_child(btn_execute)

	return panel


func _execute_decision(dec: Dictionary) -> void:
	if player_state == null:
		return

	var dec_id = dec["id"]
	var cost_pc = float(dec.get("cost_pc", 0.0))
	var cost_cap = int(dec.get("cost_cap", 0))
	var cost_money = float(dec.get("cost_money", 0.0))

	# Списание ресурсов
	player_state.political_capital = maxf(player_state.political_capital - cost_pc, 0.0)
	player_state.current_cap = maxi(player_state.current_cap - cost_cap, 0)
	player_state.liquid_reserves_billions = maxf(player_state.liquid_reserves_billions - cost_money, 0.0)

	# Установка кулдауна
	var current_turn = turn_manager.current_turn if turn_manager != null else 1
	var cd_turns = int(dec.get("cooldown_turns", 2))
	decisions_cooldowns[dec_id] = current_turn + cd_turns

	# Применение эффектов
	var eff: Dictionary = dec.get("effects", {})
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

	var log_msg = str(eff.get("log", "Решение утверждено."))
	if log_rich_text != null:
		log_rich_text.text = "[color=#44d990]>> [ХОД %d] ИНИЦИАТИВА [%s]: %s[/color]\n%s" % [
			current_turn,
			dec["title"].to_upper(),
			log_msg,
			log_rich_text.text
		]

	decision_executed.emit(dec_id, eff)
	refresh_panel()
