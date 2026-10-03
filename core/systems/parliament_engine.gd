class_name ParliamentEngine
extends RefCounted

##
## ParliamentEngine: Движок парламентской борьбы, коалиций и законодательных сделок TNO
## Реализует:
## 1. Универсальную модель законодательного органа (Рейхстаг, Верховный Совет/Дума, Сейм, Конгресс, Парламент).
## 2. Распределение мандатов (мест), коалиционное большинство (50% + 1) и оппозицию.
## 3. Систему политических сделок и лоббирования (Favors):
##    - "Политический компромисс / Лоббирование" (PC)
##    - "Министерский портфель / Аппаратная уступка" (CAP)
##    - "Бюджетная субсидия сектору фракции" (Деньги)
## 4. Законодательный стол (Parliamentary Bills) с аутентичными законопроектами Германии, России и мира.
## 5. Процедуру голосования с поименным прогнозом и применением последствий к CountryState.
##

signal vote_completed(bill_id: String, passed: bool, result: Dictionary)
signal favor_granted(party_key: String, deal_type: String, bonus_votes: int)
signal seats_updated()

## Структура парламентской фракции
class ParliamentFaction:
	var id: String = ""
	var name: String = ""
	var seats: int = 0
	var color: Color = Color(0.5, 0.5, 0.5, 1.0)
	var loyalty: float = 50.0       # Лояльность правительству (0..100)
	var favors: int = 0             # Накопленные обязательства режима перед фракцией
	var is_in_coalition: bool = false
	var whipped_votes_bonus: int = 0

## Структура законопроекта
class ParliamentBill:
	var id: String = ""
	var title: String = ""
	var category: String = "general" # economy, military, reform, security, general
	var description: String = ""
	var cost_pc: float = 15.0
	var cost_cap: int = 1
	var base_support_weights: Dictionary = {} # party_id -> float (0.0 .. 1.0)
	var effects: Dictionary = {}

var country_tag: String = "KOM"
var parliament_name: String = "Верховный Совет"
var total_seats: int = 400
var factions: Array[ParliamentFaction] = []
var active_bills: Array[ParliamentBill] = []
var selected_bill_id: String = ""
var last_vote_record: Dictionary = {}


func initialize_for_country(state: CountryState) -> void:
	if state == null:
		return
	country_tag = state.country_tag.to_upper().strip_edges()
	factions.clear()
	active_bills.clear()

	if country_tag in ["GER", "SPE", "BOR", "GOR", "HEY", "BGR", "SGR", "GGR", "HGR"]:
		_setup_german_reichstag(state)
	elif country_tag == "JAP":
		_setup_japanese_diet(state)
	elif country_tag == "ITA":
		_setup_italian_council(state)
	elif RussianUnificationManager.is_warlord(country_tag) or country_tag in ["RUS", "SOV", "WRS"]:
		_setup_russian_legislature(state)
	else:
		_setup_generic_parliament(state)

	_populate_bills_for_country(state)
	if not active_bills.is_empty():
		selected_bill_id = active_bills[0].id


# ==============================================================================
# 1. КОНФИГУРАЦИЯ ЗАКОНОДАТЕЛЬНЫХ ОРГАНОВ
# ==============================================================================

func _setup_german_reichstag(state: CountryState) -> void:
	parliament_name = "Großdeutscher Reichstag (Рейхстаг Великой Германии)"
	total_seats = 500

	# 1. Бюрократия НСДАП (Борман)
	var f_bor = ParliamentFaction.new()
	f_bor.id = "NSDAP_MITTE"
	f_bor.name = "Партийная бюрократия (Борман / NSDAP-Mitte)"
	f_bor.seats = 165
	f_bor.color = Color(0.55, 0.35, 0.18, 1.0) # Партийный коричневый
	f_bor.loyalty = 65.0
	f_bor.is_in_coalition = (country_tag in ["GER", "BOR"])
	factions.append(f_bor)

	# 2. Милитаристы Вермахта (Геринг)
	var f_gor = ParliamentFaction.new()
	f_gor.id = "WEHRMACHT"
	f_gor.name = "Милитаристы Вермахта (Геринг / OKW)"
	f_gor.seats = 135
	f_gor.color = Color(0.35, 0.45, 0.55, 1.0) # Фельдграу / Серый
	f_gor.loyalty = 55.0
	f_gor.is_in_coalition = (country_tag == "GOR")
	factions.append(f_gor)

	# 3. Реформисты Шпеера (Гражданский сектор)
	var f_spe = ParliamentFaction.new()
	f_spe.id = "REFORMISTEN"
	f_spe.name = "Реформисты и технократы (Шпеер / Ziviler Flügel)"
	f_spe.seats = 110
	f_spe.color = Color(0.20, 0.65, 0.85, 1.0) # Неоново-голубой
	f_spe.loyalty = 70.0
	f_spe.is_in_coalition = (country_tag == "SPE")
	factions.append(f_spe)

	# 4. Радикалы СС (Гейдрих)
	var f_hey = ParliamentFaction.new()
	f_hey.id = "SS_FRAKTION"
	f_hey.name = "Фракция СС (Гейдрих / Черный орден)"
	f_hey.seats = 50
	f_hey.color = Color(0.18, 0.18, 0.22, 1.0) # Черный СС
	f_hey.loyalty = 30.0
	f_hey.is_in_coalition = (country_tag == "HEY")
	factions.append(f_hey)

	# 5. Промышленные монополии (Крупп, Сименс)
	var f_krn = ParliamentFaction.new()
	f_krn.id = "KONZERNE"
	f_krn.name = "Промышленные картели (IG Farben, Krupp)"
	f_krn.seats = 40
	f_krn.color = Color(0.85, 0.70, 0.20, 1.0) # Золото промышленников
	f_krn.loyalty = 60.0
	f_krn.is_in_coalition = true
	factions.append(f_krn)

	_sync_state_seats(state)


func _setup_russian_legislature(state: CountryState) -> void:
	var ruling_id = state.ruling_ideology.to_lower()
	if "communist" in ruling_id or "social" in ruling_id:
		parliament_name = "Верховный Совет народных комиссаров"
	elif "despot" in ruling_id or "fasc" in ruling_id or "nat" in ruling_id:
		parliament_name = "Военно-государственный комитет обороны"
	else:
		parliament_name = "Временная Государственная Дума"

	total_seats = 400

	# 1. Большевики / Военное крыло фронта
	var f1 = ParliamentFaction.new()
	f1.id = "RUS_MILITARY_LEFT"
	f1.name = "Военно-партийный блок (Штаб и армия)"
	f1.seats = 150
	f1.color = Color(0.85, 0.15, 0.15, 1.0)
	f1.loyalty = 80.0
	f1.is_in_coalition = true
	factions.append(f1)

	# 2. Рабочая оппозиция и фабзавкомы
	var f2 = ParliamentFaction.new()
	f2.id = "RUS_LABOR"
	f2.name = "Фабричные комитеты и профсоюзы"
	f2.seats = 95
	f2.color = Color(0.92, 0.40, 0.20, 1.0)
	f2.loyalty = 65.0
	f2.is_in_coalition = true
	factions.append(f2)

	# 3. Умеренные социалисты / Демократы
	var f3 = ParliamentFaction.new()
	f3.id = "RUS_MODERATES"
	f3.name = "Умеренные демократы и земцы"
	f3.seats = 75
	f3.color = Color(0.25, 0.75, 0.65, 1.0)
	f3.loyalty = 50.0
	f3.is_in_coalition = false
	factions.append(f3)

	# 4. Региональные хозяйственники / Кадеты
	var f4 = ParliamentFaction.new()
	f4.id = "RUS_REGIONAL"
	f4.name = "Региональные хозяйственники и кооператоры"
	f4.seats = 50
	f4.color = Color(0.35, 0.60, 0.85, 1.0)
	f4.loyalty = 45.0
	f4.is_in_coalition = false
	factions.append(f4)

	# 5. Офицерские патриоты / Националисты
	var f5 = ParliamentFaction.new()
	f5.id = "RUS_OFFICERS"
	f5.name = "Офицерский корпус и патриотический союз"
	f5.seats = 30
	f5.color = Color(0.30, 0.30, 0.40, 1.0)
	f5.loyalty = 40.0
	f5.is_in_coalition = false
	factions.append(f5)

	_sync_state_seats(state)


func _setup_japanese_diet(state: CountryState) -> void:
	parliament_name = "Kizokuin & Teikoku Gikai (Палата Пэров и Дайэт)"
	total_seats = 466

	# 1. Финансовая бюрократия (Икэда Хаято)
	var f1 = ParliamentFaction.new()
	f1.id = "JAP_IKEDA"
	f1.name = "Финансовая бюрократия (Икэда Хаято / Дзайбацу)"
	f1.seats = 145
	f1.color = Color(0.20, 0.65, 0.85, 1.0)
	f1.loyalty = 60.0
	f1.is_in_coalition = true
	factions.append(f1)

	# 2. Армейская военщина (ИЯА / Киси)
	var f2 = ParliamentFaction.new()
	f2.id = "JAP_IJA"
	f2.name = "Военная хунта (Тосэйха / Армейские генералы)"
	f2.seats = 116
	f2.color = Color(0.65, 0.25, 0.25, 1.0)
	f2.loyalty = 45.0
	f2.is_in_coalition = false
	factions.append(f2)

	# 3. Реформисты Тэйсэйкай (Такаги Сокити / Флот)
	var f3 = ParliamentFaction.new()
	f3.id = "JAP_TAKAGI"
	f3.name = "Реформисты Тэйсэйкай (Такаги / Умеренный флот)"
	f3.seats = 110
	f3.color = Color(0.25, 0.85, 0.55, 1.0)
	f3.loyalty = 55.0
	f3.is_in_coalition = false
	factions.append(f3)

	# 4. Технократы Госплана (Кая Окинори)
	var f4 = ParliamentFaction.new()
	f4.id = "JAP_KAYA"
	f4.name = "Технократы Госплана (Кая Окинори / Синканрё)"
	f4.seats = 95
	f4.color = Color(0.85, 0.65, 0.20, 1.0)
	f4.loyalty = 50.0
	f4.is_in_coalition = false
	factions.append(f4)

	_sync_state_seats(state)


func _setup_italian_council(state: CountryState) -> void:
	parliament_name = "Gran Consiglio del Fascismo (Великий Фашистский Совет)"
	total_seats = 300

	# 1. Демократические реформаторы (Чиано)
	var f1 = ParliamentFaction.new()
	f1.id = "ITA_CIANO"
	f1.name = "Реформаторы Чиано (Либерализация и светский курс)"
	f1.seats = 130
	f1.color = Color(0.20, 0.70, 0.90, 1.0)
	f1.loyalty = 70.0
	f1.is_in_coalition = true
	factions.append(f1)

	# 2. Ортодоксальные чернорубашечники (Скорца)
	var f2 = ParliamentFaction.new()
	f2.id = "ITA_SCORZA"
	f2.name = "Жесткие фашисты Скорцы (PNF Hardliners / Сквадристы)"
	f2.seats = 110
	f2.color = Color(0.25, 0.25, 0.30, 1.0)
	f2.loyalty = 45.0
	f2.is_in_coalition = false
	factions.append(f2)

	# 3. Монархисты и Сенат Королевства
	var f3 = ParliamentFaction.new()
	f3.id = "ITA_MONARCHY"
	f3.name = "Монархисты Савойского Дома и маршалы"
	f3.seats = 60
	f3.color = Color(0.85, 0.70, 0.25, 1.0)
	f3.loyalty = 55.0
	f3.is_in_coalition = true
	factions.append(f3)

	_sync_state_seats(state)


func _setup_generic_parliament(state: CountryState) -> void:
	parliament_name = "Национальное Законодательное Собрание"
	total_seats = 350

	if not state.initial_parties.is_empty():
		var allocated := 0
		for i in range(state.initial_parties.size()):
			var p = state.initial_parties[i]
			var f = ParliamentFaction.new()
			f.id = p.ideology_key
			f.name = p.party_name
			f.color = p.color
			f.is_in_coalition = p.is_ruling
			f.loyalty = 75.0 if p.is_ruling else 45.0
			var seat_share = int(round((p.popularity / 100.0) * float(total_seats)))
			f.seats = maxi(10, seat_share)
			allocated += f.seats
			factions.append(f)
		# Балансировка
		if allocated != total_seats and not factions.is_empty():
			factions[0].seats += (total_seats - allocated)
	else:
		# Fallback
		var f_rule = ParliamentFaction.new()
		f_rule.id = "RULING_COALITION"
		f_rule.name = "Правительственная коалиция"
		f_rule.seats = 190
		f_rule.color = Color(0.20, 0.65, 0.85, 1.0)
		f_rule.loyalty = 80.0
		f_rule.is_in_coalition = true
		factions.append(f_rule)

		var f_opp = ParliamentFaction.new()
		f_opp.id = "OPPOSITION"
		f_opp.name = "Объединенная оппозиция"
		f_opp.seats = 160
		f_opp.color = Color(0.85, 0.35, 0.30, 1.0)
		f_opp.loyalty = 40.0
		f_opp.is_in_coalition = false
		factions.append(f_opp)

	_sync_state_seats(state)


func _sync_state_seats(state: CountryState) -> void:
	if state == null:
		return
	state.total_parliament_seats = total_seats
	state.parliament_seats.clear()
	for f in factions:
		state.parliament_seats[f.id] = f.seats
	seats_updated.emit()


# ==============================================================================
# 2. БАЗА ЗАКОНОПРОЕКТОВ
# ==============================================================================

func _populate_bills_for_country(state: CountryState) -> void:
	active_bills.clear()

	if country_tag in ["GER", "SPE", "BOR", "GOR", "HEY"]:
		# 1. Оборонный бюджет Вермахта
		var b1 = ParliamentBill.new()
		b1.id = "GER_BILL_DEFENSE"
		b1.title = "Чрезвычайный оборонный бюджет Вермахта"
		b1.category = "military"
		b1.description = "Выделение $1.2 млрд на перевооружение приграничных гарнизонов и пополнение арсеналов тяжелой техники."
		b1.cost_pc = 20.0
		b1.cost_cap = 1
		b1.base_support_weights = {"WEHRMACHT": 0.95, "NSDAP_MITTE": 0.65, "KONZERNE": 0.70, "REFORMISTEN": 0.35, "SS_FRAKTION": 0.80}
		b1.effects = {"weapons": 15000, "budget_delta": -1.2, "readiness": 8.0, "militarist_loyalty": 10.0}
		active_bills.append(b1)

		# 2. Реформа рабского труда (Sklaverei-Reform)
		var b2 = ParliamentBill.new()
		b2.id = "GER_BILL_SLAVERY_REFORM"
		b2.title = "Постепенная ликвидация рабского труда (Sklaverei-Reform)"
		b2.category = "reform"
		b2.description = "Законодательный демонтаж системы принудительного рабства в промышленности и перевод остарбайтеров на контрактную оплату пайками."
		b2.cost_pc = 30.0
		b2.cost_cap = 2
		b2.base_support_weights = {"REFORMISTEN": 0.95, "KONZERNE": 0.55, "NSDAP_MITTE": 0.40, "WEHRMACHT": 0.25, "SS_FRAKTION": 0.05}
		b2.effects = {"radicalization": -8.0, "legitimacy": 6.0, "societal_labor": 15.0, "reformist_loyalty": 15.0, "militarist_loyalty": -8.0}
		active_bills.append(b2)

		# 3. Субсидии промышленным синдикатам
		var b3 = ParliamentBill.new()
		b3.id = "GER_BILL_SYNDICATES"
		b3.title = "Госпрограмма модернизации сталелитейных синдикатов"
		b3.category = "economy"
		b3.description = "Налоговые каникулы и субсидирование концернов Рура и Силезии для расширения гражданских и военных фабрик."
		b3.cost_pc = 15.0
		b3.cost_cap = 1
		b3.base_support_weights = {"KONZERNE": 0.95, "NSDAP_MITTE": 0.70, "REFORMISTEN": 0.60, "WEHRMACHT": 0.50, "SS_FRAKTION": 0.40}
		b3.effects = {"civilian_factories": 2, "gdp_growth": 0.015, "budget_delta": -0.6}
		active_bills.append(b3)

		# 4. Чрезвычайные директивные полномочия
		var b4 = ParliamentBill.new()
		b4.id = "GER_BILL_EMERGENCY"
		b4.title = "Чрезвычайный декрет о полномочиях канцелярии (Ermächtigung)"
		b4.category = "security"
		b4.description = "Передача канцлеру права издавать указы в обход парламентских слушаний в случае военной тревоги."
		b4.cost_pc = 25.0
		b4.cost_cap = 1
		b4.base_support_weights = {"NSDAP_MITTE": 0.85, "SS_FRAKTION": 0.90, "WEHRMACHT": 0.60, "KONZERNE": 0.40, "REFORMISTEN": 0.15}
		b4.effects = {"pc_gain": 2.0, "cap_max": 1, "radicalization": 5.0}
		active_bills.append(b4)

	elif RussianUnificationManager.is_warlord(country_tag) or country_tag in ["RUS", "SOV", "WRS"]:
		# 1. Трудовая мобилизация
		var b1 = ParliamentBill.new()
		b1.id = "RUS_BILL_LABOR_MOBILIZATION"
		b1.title = "Закон о фронтовой трудовой мобилизации"
		b1.category = "reform"
		b1.description = "Введение 10-часовой рабочей смены на оружейных заводах и нормированного рабочего пайка для форсирования выпуска стрелкового оружия."
		b1.cost_pc = 15.0
		b1.cost_cap = 1
		b1.base_support_weights = {"RUS_MILITARY_LEFT": 0.90, "RUS_OFFICERS": 0.85, "RUS_REGIONAL": 0.50, "RUS_LABOR": 0.45, "RUS_MODERATES": 0.30}
		b1.effects = {"weapons": 8000, "military_factories": 1, "radicalization": 3.0, "societal_labor": 10.0}
		active_bills.append(b1)

		# 2. Чрезвычайный военный налог
		var b2 = ParliamentBill.new()
		b2.id = "RUS_BILL_WAR_TAX"
		b2.title = "Чрезвычайный налог на объединение русских земель"
		b2.category = "economy"
		b2.description = "Разовый сбор с кооперативов и артелей для закупки сырья и комплектования регулярных ударных бригад."
		b2.cost_pc = 15.0
		b2.cost_cap = 1
		b2.base_support_weights = {"RUS_MILITARY_LEFT": 0.85, "RUS_OFFICERS": 0.70, "RUS_LABOR": 0.50, "RUS_REGIONAL": 0.25, "RUS_MODERATES": 0.40}
		b2.effects = {"reserves_delta": 0.4, "manpower": 5000, "radicalization": 4.0}
		active_bills.append(b2)

		# 3. Амнистия ученых и инженеров
		var b3 = ParliamentBill.new()
		b3.id = "RUS_BILL_AMNESTY"
		b3.title = "Амнистия и привлечение научно-технических специалистов"
		b3.category = "reform"
		b3.description = "Снятие ограничений с бывших царских, советских и эвакуированных инженеров для развертывания конструкторских бюро."
		b3.cost_pc = 20.0
		b3.cost_cap = 1
		b3.base_support_weights = {"RUS_MODERATES": 0.90, "RUS_REGIONAL": 0.85, "RUS_LABOR": 0.65, "RUS_MILITARY_LEFT": 0.50, "RUS_OFFICERS": 0.35}
		b3.effects = {"legitimacy": 5.0, "societal_academic": 15.0, "radicalization": -4.0}
		active_bills.append(b3)

	elif country_tag == "JAP":
		# 1. Антикризисный закон о финансовых рынках
		var b1 = ParliamentBill.new()
		b1.id = "JAP_BILL_YASUDA_STABILIZATION"
		b1.title = "Чрезвычайный закон о стабилизации финансовых рынков и биржи TSE"
		b1.category = "economy"
		b1.description = "Ограничение спекуляций на Токийской бирже, реструктуризация долговых обязательств дзайбацу и валютные интервенции Банка Японии."
		b1.cost_pc = 25.0
		b1.cost_cap = 1
		b1.base_support_weights = {"JAP_IKEDA": 0.95, "JAP_KAYA": 0.80, "JAP_TAKAGI": 0.60, "JAP_IJA": 0.35}
		b1.effects = {"reserves_delta": -2.0, "inflation_delta": -0.015, "legitimacy": 6.0}
		active_bills.append(b1)

		# 2. Ассигнования на Императорский флот
		var b2 = ParliamentBill.new()
		b2.id = "JAP_BILL_NAVY_APPROPRIATION"
		b2.title = "Морская программа национальной безопасности (Квоты верфей)"
		b2.category = "military"
		b2.description = "Выделение бюджетных лимитов на модернизацию суперавианосцев и подводных крейсеров Объединенного Флота."
		b2.cost_pc = 20.0
		b2.cost_cap = 1
		b2.base_support_weights = {"JAP_TAKAGI": 0.90, "JAP_IKEDA": 0.65, "JAP_KAYA": 0.50, "JAP_IJA": 0.15}
		b2.effects = {"military_factories": 3, "readiness": 8.0, "budget_delta": -1.5}
		active_bills.append(b2)

		# 3. Интеграция колониальных ресурсов Сферы
		var b3 = ParliamentBill.new()
		b3.id = "JAP_BILL_SPHERE_TARIFFS"
		b3.title = "Акт о гармонизации таможенных пошлин Великой Сферы Сопроцветания"
		b3.category = "reform"
		b3.description = "Льготный ввоз каучука из Малайи и нефти из Индонезии в обмен на японскую промышленную продукцию."
		b3.cost_pc = 20.0
		b3.cost_cap = 1
		b3.base_support_weights = {"JAP_IKEDA": 0.90, "JAP_KAYA": 0.85, "JAP_TAKAGI": 0.70, "JAP_IJA": 0.60}
		b3.effects = {"gdp_growth": 0.008, "civilian_factories": 4}
		active_bills.append(b3)

	elif country_tag == "ITA":
		# 1. Судебная реформа Чиано
		var b1 = ParliamentBill.new()
		b1.id = "ITA_BILL_JUDICIAL_REFORM"
		b1.title = "Закон о реформе трибуналов и гарантиях гражданских свобод (Чиано)"
		b1.category = "reform"
		b1.description = "Ограничение произвола фашистских спецтрибуналов, амнистия части политических заключенных и курс на конституционную модернизацию."
		b1.cost_pc = 30.0
		b1.cost_cap = 1
		b1.base_support_weights = {"ITA_CIANO": 0.95, "ITA_MONARCHY": 0.75, "ITA_SCORZA": 0.10}
		b1.effects = {"radicalization": -10.0, "legitimacy": 8.0, "stability_delta": 6.0}
		active_bills.append(b1)

		# 2. Фонд спасения от последствий Атлантропы
		var b2 = ParliamentBill.new()
		b2.id = "ITA_BILL_ATLANTROPA_RELIEF"
		b2.title = "Чрезвычайный план субсидирования Медзоджорно и Адриатики"
		b2.category = "economy"
		b2.description = "Государственные ассигнования на подведение пресной воды, восстановление портов Венеции и помощь фермерам Сицилии."
		b2.cost_pc = 20.0
		b2.cost_cap = 1
		b2.base_support_weights = {"ITA_MONARCHY": 0.90, "ITA_CIANO": 0.85, "ITA_SCORZA": 0.70}
		b2.effects = {"budget_delta": -2.0, "gdp_growth": 0.006, "radicalization": -5.0}
		active_bills.append(b2)

		# 3. Бюджет Черных Рубашек (MVSN)
		var b3 = ParliamentBill.new()
		b3.id = "ITA_BILL_MVSN_EXPANSION"
		b3.title = "Декрет об укреплении Добровольческой милиции национальной безопасности (MVSN)"
		b3.category = "military"
		b3.description = "Перевооружение легионов чернорубашечников для защиты колониальных рубежей в Ливии и Восточной Африке."
		b3.cost_pc = 25.0
		b3.cost_cap = 1
		b3.base_support_weights = {"ITA_SCORZA": 0.95, "ITA_MONARCHY": 0.40, "ITA_CIANO": 0.20}
		b3.effects = {"weapons": 8000, "manpower": 12000, "radicalization": 4.0}
		active_bills.append(b3)

	else:
		# Универсальный набор
		var b1 = ParliamentBill.new()
		b1.id = "GEN_BILL_BUDGET"
		b1.title = "Государственный антикризисный бюджет и инфраструктурный план"
		b1.category = "economy"
		b1.description = "Финансирование модернизации магистралей, портов и систем связи за счет оптимизации налоговой ставки."
		b1.cost_pc = 15.0
		b1.cost_cap = 1
		b1.effects = {"gdp_growth": 0.012, "legitimacy": 4.0, "budget_delta": -0.3}
		active_bills.append(b1)

		var b2 = ParliamentBill.new()
		b2.id = "GEN_BILL_DEFENSE"
		b2.title = "Закон об укреплении национального суверенитета и резервов"
		b2.category = "military"
		b2.description = "Формирование новых складов снаряжения и модернизация гарнизонной службы."
		b2.cost_pc = 20.0
		b2.cost_cap = 1
		b2.effects = {"weapons": 6000, "readiness": 5.0}
		active_bills.append(b2)


# ==============================================================================
# 3. МЕХАНИКА СДЕЛОК И ЛОББИРОВАНИЯ (FAVORS)
# ==============================================================================

## Заключает политическую сделку с фракцией парламента
func offer_favor(party_id: String, deal_type: String, state: CountryState) -> Dictionary:
	var f = _get_faction(party_id)
	if f == null:
		return {"success": false, "message": "Фракция не найдена."}

	var cost_pc := 0.0
	var cost_cap := 0
	var cost_money := 0.0
	var bonus_votes := 0

	match deal_type:
		"compromise": # Политический компромисс и лоббирование (15 PC)
			cost_pc = 15.0
			bonus_votes = int(round(float(f.seats) * 0.35))
		"cabinet_post": # Обещание министерского портфеля / квоты (1 CAP)
			cost_cap = 1
			bonus_votes = int(round(float(f.seats) * 0.60))
			f.favors += 1
		"pork_barrel": # Бюджетная субсидия сектору фракции ($0.15 млрд)
			cost_money = 0.15
			cost_pc = 5.0
			bonus_votes = int(round(float(f.seats) * 0.80))
			f.loyalty = clampf(f.loyalty + 8.0, 0.0, 100.0)

	if state.political_capital < cost_pc:
		return {"success": false, "message": "Недостаточно политического капитала (нужно %.0f PC)." % cost_pc}
	if state.current_cap < cost_cap:
		return {"success": false, "message": "Недостаточно очков кабинета (нужно %d CAP)." % cost_cap}
	if cost_money > 0.0 and state.liquid_reserves_billions < cost_money:
		return {"success": false, "message": "Недостаточно ликвидных резервов бюджета (нужно $%.2f млрд)." % cost_money}

	state.political_capital -= cost_pc
	state.current_cap -= cost_cap
	if cost_money > 0.0:
		state.liquid_reserves_billions -= cost_money

	f.whipped_votes_bonus += bonus_votes
	favor_granted.emit(f.id, deal_type, bonus_votes)

	return {
		"success": true,
		"bonus_votes": bonus_votes,
		"message": "Сделка заключена с [%s]: +%d гарантированных голосов «ЗА»!" % [f.name, bonus_votes]
	}


# ==============================================================================
# 4. ПРОГНОЗ И ПОИМЕННОЕ ГОЛОСОВАНИЕ
# ==============================================================================

## Возвращает прогноз голосования по текущему законопроекту
func calculate_vote_projection(bill_id: String) -> Dictionary:
	var b = _get_bill(bill_id)
	var yeas := 0
	var nays := 0
	var abstain := 0

	for f in factions:
		var base_support := 0.50
		if b != null and b.base_support_weights.has(f.id):
			base_support = float(b.base_support_weights[f.id])
		elif f.is_in_coalition:
			base_support = 0.75
		else:
			base_support = 0.35

		# Влияние лояльности и сделок
		var loyalty_mod = (f.loyalty - 50.0) / 100.0 * 0.25
		var total_rate = clampf(base_support + loyalty_mod, 0.05, 0.95)

		var raw_yeas = int(round(float(f.seats) * total_rate)) + f.whipped_votes_bonus
		raw_yeas = mini(f.seats, raw_yeas)
		var rem = f.seats - raw_yeas
		var f_abstain = int(round(float(rem) * 0.20))
		var f_nays = rem - f_abstain

		yeas += raw_yeas
		nays += f_nays
		abstain += f_abstain

	var quorum_needed = int(ceil(float(total_seats) * 0.50)) + 1
	var is_passing = (yeas >= quorum_needed)

	return {
		"yeas": yeas,
		"nays": nays,
		"abstain": abstain,
		"quorum_needed": quorum_needed,
		"is_passing": is_passing
	}


## Запуск поименного голосования по законопроекту
func call_parliament_vote(bill_id: String, state: CountryState) -> Dictionary:
	var b = _get_bill(bill_id)
	if b == null or state == null:
		return {"success": false, "message": "Законопроект не найден."}

	if state.political_capital < b.cost_pc:
		return {"success": false, "message": "Недостаточно PC для внесения законопроекта (требуется %.0f PC)." % b.cost_pc}
	if state.current_cap < b.cost_cap:
		return {"success": false, "message": "Недостаточно CAP для регламента слушаний (требуется %d CAP)." % b.cost_cap}

	state.political_capital -= b.cost_pc
	state.current_cap -= b.cost_cap

	var proj = calculate_vote_projection(bill_id)
	var passed = proj["is_passing"]

	# Применение эффектов
	if passed:
		_apply_bill_effects(b, state)
		state.legitimacy = clampf(state.legitimacy + 3.0, 0.0, 100.0)
	else:
		state.legitimacy = clampf(state.legitimacy - 4.0, 0.0, 100.0)
		state.radicalization = clampf(state.radicalization + 3.5, 0.0, 100.0)

	# Сброс бонусов сделок
	for f in factions:
		f.whipped_votes_bonus = 0

	last_vote_record = {
		"bill_id": b.id,
		"bill_title": b.title,
		"passed": passed,
		"yeas": proj["yeas"],
		"nays": proj["nays"],
		"abstain": proj["abstain"],
		"quorum_needed": proj["quorum_needed"]
	}

	vote_completed.emit(b.id, passed, last_vote_record)

	return {
		"success": true,
		"passed": passed,
		"record": last_vote_record,
		"message": "РЕЗУЛЬТАТ ГОЛОСОВАНИЯ: Законопроект [%s] %s! (ЗА: %d, ПРОТИВ: %d, Кворум: %d)" % [
			b.title, ("ПРИНЯТ И ВСТУПИЛ В СИЛУ" if passed else "ОТКЛОНЕН ПАРЛАМЕНТОМ"),
			proj["yeas"], proj["nays"], proj["quorum_needed"]
		]
	}


func _apply_bill_effects(b: ParliamentBill, state: CountryState) -> void:
	var eff = b.effects
	if eff.has("weapons"):
		state.infantry_weapons_stockpile += int(eff["weapons"])
	if eff.has("manpower"):
		state.manpower_pool += int(eff["manpower"])
	if eff.has("readiness"):
		state.army_readiness = clampf(state.army_readiness + float(eff["readiness"]), 0.0, 100.0)
	if eff.has("budget_delta"):
		state.liquid_reserves_billions = maxf(0.0, state.liquid_reserves_billions + float(eff["budget_delta"]))
	if eff.has("radicalization"):
		state.radicalization = clampf(state.radicalization + float(eff["radicalization"]), 0.0, 100.0)
	if eff.has("legitimacy"):
		state.legitimacy = clampf(state.legitimacy + float(eff["legitimacy"]), 0.0, 100.0)
	if eff.has("civilian_factories"):
		state.civilian_factories += int(eff["civilian_factories"])
	if eff.has("military_factories"):
		state.military_factories += int(eff["military_factories"])
	if eff.has("gdp_growth"):
		state.real_gdp_growth += float(eff["gdp_growth"])
	if eff.has("societal_labor"):
		state.modify_societal_metric("labor_rights", float(eff["societal_labor"]))
	if eff.has("societal_academic"):
		state.modify_societal_metric("academic_base", float(eff["societal_academic"]))
	if eff.has("pc_gain"):
		state.pc_gain_per_turn += float(eff["pc_gain"])
	if eff.has("cap_max"):
		state.max_cap += int(eff["cap_max"])

	# Если это реформа рабства за Германию, обновим соответствующий закон в societal_laws
	if b.id == "GER_BILL_SLAVERY_REFORM":
		for law in state.societal_laws:
			if "труд" in str(law.get("name", "")).to_lower():
				law["tier"] = mini(int(law.get("max_tier", 5)), int(law.get("tier", 1)) + 1)
				law["value"] = "Контрактная повинность (сворачивание рабства)"
				break
	elif b.id == "RUS_BILL_LABOR_MOBILIZATION":
		for law in state.societal_laws:
			if "труд" in str(law.get("name", "")).to_lower() or "мобилиз" in str(law.get("name", "")).to_lower():
				law["tier"] = mini(int(law.get("max_tier", 5)), int(law.get("tier", 1)) + 1)
				law["value"] = "Фронтовая мобилизация заводов"
				break

	SocietalLawsManager.synchronize_societal_metrics_with_state(state)


func _get_faction(id_str: String) -> ParliamentFaction:
	for f in factions:
		if f.id == id_str:
			return f
	return null


func _get_bill(id_str: String) -> ParliamentBill:
	for b in active_bills:
		if b.id == id_str:
			return b
	return null
