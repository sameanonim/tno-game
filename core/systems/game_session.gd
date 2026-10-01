extends Node

##
## GameSession: Главный синглтон управления сессией игры (Autoload)
##
## Отвечает за:
## 1. Хранение настроек старта (тег страны, сложность, флаги правил мира, CRT-профиль).
## 2. Каноническую базу стартовых досье стран TNO (Русская Смута, Претенденты Рейха, Сверхдержавы).
## 3. Инициализацию CountryState, настройку начальной карты и передачу управления в TerminalMain.
##

signal session_bootstrapped(config: GameStartConfig)
signal crt_settings_updated(settings: Dictionary)

enum Difficulty {
	OBSERVER = 0, # Story / Easy
	STRATEGIST = 1, # Normal (Toolbox Theory canon)
	CRISIS = 2 # Hard / Ironman
}

class GameStartConfig:
	var selected_country_tag: String = "WRS"
	var difficulty: Difficulty = Difficulty.STRATEGIST
	var ironman_mode: bool = false
	var time_step_mode: String = "weekly" # "weekly" (1 week/turn) | "monthly" (1 month/turn)
	var rules: Dictionary = {
		"german_anarchy_timer": true,
		"dynamic_nuclear_defcon": true,
		"battlefield_incidents": true,
		"border_raids_allowed": true
	}


# --- ТЕКУЩЕЕ СОСТОЯНИЕ СЕССИИ ---
var current_config: GameStartConfig = GameStartConfig.new()
var active_player_state: CountryState = null
var is_loading_saved_game: bool = false
var content_loader: ContentLoader = null

# --- CRT / АУДИО НАСТРОЙКИ ---
var crt_settings: Dictionary = {
	"curvature": 0.03,
	"vignette_strength": 0.85,
	"scanline_count": 540.0,
	"scanline_intensity": 0.16,
	"chromatic_aberration": 0.002,
	"phosphor_tint": Color(0.95, 1.0, 0.98, 1.0),
	"brightness_boost": 1.05
}

var audio_settings: Dictionary = {
	"master_volume": 0.8,
	"sfx_volume": 0.9,
	"ambient_volume": 0.7
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	content_loader = ContentLoader.new()
	content_loader.name = "ContentLoader"
	content_loader.content_loaded.connect(func(c_cnt: int, t_cnt: int):
		print("[GameSession] ContentLoader indexed %d countries, %d trees." % [c_cnt, t_cnt])
	)
	content_loader.country_package_loaded.connect(func(tag: String, _st: CountryState):
		print("[GameSession] Country package loaded: %s" % tag)
	)
	add_child(content_loader)



# ==============================================================================
# БАЗА ДАННЫХ ЛИДЕРОВ И ТЕАТРОВ TNO
# ==============================================================================

func get_theaters() -> Array[Dictionary]:
	if content_loader != null and content_loader.has_extracted_data():
		return content_loader.get_theaters()

	return [
		{
			"id": "theater_superpowers",
			"name": "СВЕРХДЕРЖАВЫ ХОЛОДНОЙ ВОЙНЫ",
			"name_en": "COLD WAR SUPERPOWERS",
			"description": "Глобальное геополитическое противостояние трех ядерных блоков: Вашингтон, Берлин и Токио.",
			"tags": ["USA", "GER", "JAP"]
		},
		{
			"id": "theater_smuta",
			"name": "РУССКАЯ СМУТА // ЭПОХА ВАРЛОРДОВ",
			"name_en": "RUSSIAN ANARCHY // WARLORDS",
			"description": "Осколки павшего Союза ведут бескомпромиссную борьбу за воссоединение Родины среди руин и немецких бомбардировок.",
			"tags": ["WRS", "KOM", "VYT", "SAM", "PRM", "TYU", "SVR", "OMS", "TOM", "NOV", "KEM", "SBA", "IRK", "BRY", "CHT", "MAG", "AMR"]
		},
		{
			"id": "theater_gcw",
			"name": "ПРЕТЕНДЕНТЫ РЕЙХА // КРИЗИС",
			"name_en": "GERMAN CIVIL WAR CONTENDERS",
			"description": "Агония фюрера поджигает гражданскую войну между четырьмя фракциями нацистской элиты: Шпеер, Борман, Геринг и Гейдрих.",
			"tags": ["SPE", "BOR", "GOR", "HEY"]
		},
		{
			"id": "theater_europe",
			"name": "ЕВРОПА И ТРИУМВИРАТ",
			"name_en": "EUROPE & THE TRIUMVIRATE",
			"description": "Средиземноморский союз Италии и Иберии, расколотая Британия и зловещая тайна Бургундии.",
			"tags": ["ITA", "IBR", "ENG", "BRG", "FRD", "TUR", "SCO", "WAL", "IRE"]
		},
		{
			"id": "theater_sphere",
			"name": "СФЕРА СОПРОЦВЕТАНИЯ И АЗИЯ",
			"name_en": "CO-PROSPERITY SPHERE & ASIA",
			"description": "Киберпанк-эксперимент Гуандуна, японское ярмо Маньчжоу-Го и национальное возрождение Китая.",
			"tags": ["GNG", "MAN", "CHI", "THA", "YUN"]
		},
		{
			"id": "theater_focus_trees",
			"name": "★ ВСЕ СТРАНЫ С ФОКУСАМИ",
			"name_en": "★ ALL NATIONS WITH FOCUS TREES",
			"description": "Полный каталог всех государств мира, обладающих уникальными древами национальных директив TNO.",
			"tags": ["USA", "GER", "JAP", "WRS", "KOM", "VYT", "SAM", "PRM", "TYU", "SVR", "OMS", "TOM", "NOV", "KEM", "SBA", "IRK", "BRY", "CHT", "MAG", "AMR", "SPE", "BOR", "GOR", "HEY", "ITA", "IBR", "ENG", "BRG", "FRD", "TUR", "GNG", "MAN", "CHI", "THA"]
		}
	]


func has_focus_tree(tag: String) -> bool:
	if content_loader != null:
		return content_loader.has_focus_tree(tag)
	return tag in ["WRS", "KOM", "OMS", "SVE", "TYU", "IRK", "CHT", "GER", "USA", "JAP", "ITA", "IBR"]


func get_focus_tree_summary(tag: String) -> Dictionary:
	if content_loader != null:
		return content_loader.get_focus_tree_summary(tag)
	return {
		"has_tree": false,
		"tree_id": "",
		"tree_title": "",
		"total_directives": 0,
		"categories": [],
		"starting_directives": []
	}


func get_tags_with_focus_trees() -> Array[String]:
	if content_loader != null:
		return content_loader.get_tags_with_focus_trees()
	var fallback: Array[String] = ["WRS", "KOM", "OMS", "SVE", "TYU", "IRK", "CHT", "GER", "USA", "JAP", "ITA", "IBR"]
	return fallback


func get_country_dossier(tag: String) -> Dictionary:
	var dossiers = {
		# --- РУССКАЯ СМУТА ---
		"WRS": {
			"tag": "WRS",
			"name": "Западнорусский Революционный Фронт",
			"leader_name": "Михаил Тухачевский",
			"leader_title": "Маршал Красной Армии",
			"ideology": "Авторитарный Социализм",
			"sub_ideology": "Военная Стратократия",
			"theater": "theater_smuta",
			"color": Color(0.85, 0.20, 0.20),
			"portrait_path": "res://icon.svg",
			"difficulty_rating": "●●○○○ (УМЕРЕННАЯ)",
			"starting_gdp": 18.5,
			"starting_manpower": 85000,
			"starting_factories": 37,
			"traits": ["Красный Наполеон", "Теория глубокой операции", "Бескомпромиссный милитаризм"],
			"lore": "Фронт закален в Первой Западнорусской войне. Маршал Тухачевский верит, что единственным языком возрождения СССР является тотальная индустриализация ВПК и массированные танковые клинья."
		},
		"KOM": {
			"tag": "KOM",
			"name": "Республика Коми (Сыктывкар)",
			"leader_name": "Национальное Собрание",
			"leader_title": "Председатель Парламента",
			"ideology": "Прогрессивизм",
			"sub_ideology": "Социал-Либеральная Демократия",
			"theater": "theater_smuta",
			"color": Color(0.65, 0.25, 0.25),
			"portrait_path": "res://icon.svg",
			"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
			"starting_gdp": 14.0,
			"starting_manpower": 50000,
			"starting_factories": 22,
			"traits": ["Расколотый парламент", "Арена всех идеологий", "Хрупкая демократия"],
			"lore": "Сыктывкар превратился в бурлящий котел: от коммунистов Суслова и Бухариной до ультранационалистов Гумилева и фанатиков Таборицкого. Судьба демократии висит на волоске."
		},
		"SVE": {
			"tag": "SVE",
			"name": "Уральский Военный Округ (Свердловск)",
			"leader_name": "Павел Батов",
			"leader_title": "Генерал-лейтенант",
			"ideology": "Авторитарная Демократия",
			"sub_ideology": "Временная Военная Хунта",
			"theater": "theater_smuta",
			"color": Color(0.35, 0.65, 0.35),
			"portrait_path": "res://icon.svg",
			"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
			"starting_gdp": 22.0,
			"starting_manpower": 92000,
			"starting_factories": 41,
			"traits": ["Солдатский маршал", "Оборонительный рубеж Урала", "Прагматичный баланс"],
			"lore": "Генерал Батов и Рокоссовский сохранили костяк кадровых офицеров. Урал готов оборонять свои рубежи и собирать русские земли без фанатизма и кровавых чисток."
		},
		"TYU": {
			"tag": "TYU",
			"name": "Тюменское Правительство (ВКП(б))",
			"leader_name": "Лазарь Каганович",
			"leader_title": "Генеральный Секретарь ЦК",
			"ideology": "Коммунизм",
			"sub_ideology": "Ортодоксальный Сталинизм",
			"theater": "theater_smuta",
			"color": Color(0.70, 0.12, 0.12),
			"portrait_path": "res://icon.svg",
			"difficulty_rating": "●●●●○ (ВЫСОКАЯ)",
			"starting_gdp": 15.0,
			"starting_manpower": 68000,
			"starting_factories": 32,
			"traits": ["Железный Лазарь", "Ударные пятилетки", "Централизованный диктат"],
			"lore": "Каганович считает падение Союза предательством партийных принципов. Возрождение сибирской тайги пятилетками и тяжелой артиллерией — завет генералиссимуса Сталина."
		},
		"OMS": {
			"tag": "OMS",
			"name": "Черная Лига (Омск)",
			"leader_name": "Дмитрий Язов",
			"leader_title": "Верховный Главнокомандующий",
			"ideology": "Ультранационализм",
			"sub_ideology": "Стратократия Великого Суда",
			"theater": "theater_smuta",
			"color": Color(0.20, 0.20, 0.20),
			"portrait_path": "res://icon.svg",
			"difficulty_rating": "●●●●● (ЭКСТРЕМАЛЬНАЯ)",
			"starting_gdp": 12.0,
			"starting_manpower": 110000,
			"starting_factories": 28,
			"traits": ["Архитектор Великого Суда", "Бункерная фанатичность", "Культ возмездия"],
			"lore": "Для Черной Лиги Россия умерла, осталась лишь миссия: возмездие Тевтону любой ценой, даже если цена — мировой ядерный пепел. Все ресурсы до копейки идут на подготовку к финальной войне."
		},
		"IRK": {
			"tag": "IRK",
			"name": "Президиум Верховного Совета (Иркутск)",
			"leader_name": "Генрих Ягода",
			"leader_title": "Председатель Президиума",
			"ideology": "Авторитарный Социализм",
			"sub_ideology": "Государство Госбезопасности",
			"theater": "theater_smuta",
			"color": Color(0.55, 0.15, 0.15),
			"portrait_path": "res://icon.svg",
			"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
			"starting_gdp": 17.0,
			"starting_manpower": 75000,
			"starting_factories": 34,
			"traits": ["Чекистский монолит", "Тайная полиция", "Байкальская крепость"],
			"lore": "Законные преемники союзного центра во главе с НКВД держат в кулаке Восточную Сибирь, готовясь разгромить белогвардейцев и бунтовщиков Саблина."
		},
		"CHT": {
			"tag": "CHT",
			"name": "Читинская Монархия",
			"leader_name": "Михаил II (Романов)",
			"leader_title": "Император Всероссийский",
			"ideology": "Авторитаризм",
			"sub_ideology": "Военно-монархическая реставрация",
			"theater": "theater_smuta",
			"color": Color(0.40, 0.40, 0.70),
			"portrait_path": "res://icon.svg",
			"difficulty_rating": "●●●●○ (ВЫСОКАЯ)",
			"starting_gdp": 11.5,
			"starting_manpower": 54000,
			"starting_factories": 22,
			"traits": ["Пленник белых генералов", "Тоска по родине", "Маньчжурское снабжение"],
			"lore": "Молодой австралийский эмигрант Михаил Романов завлечен белоэмигрантскими атаманами Семенова и превращен в номинального царя Забайкалья."
		},

		# --- НЕМЕЦКИЙ КРИЗИС ---
		"SPE": {
			"tag": "SPE",
			"name": "Германия (Альберт Шпеер / Реформаторы)",
			"leader_name": "Альберт Шпеер",
			"leader_title": "Рейхсминистр вооружений / Лидер Реформаторов",
			"ideology": "Фашизм",
			"sub_ideology": "Реформистский Фашизм",
			"theater": "theater_gcw",
			"color": Color(0.85, 0.65, 0.20),
			"portrait_path": "res://data/countries/GER/leaders/portraits/GER_albert_speer.png",
			"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
			"starting_gdp": 85.0,
			"starting_manpower": 250000,
			"starting_factories": 110,
			"traits": ["Архитектор Рейха", "Либерализация рынка", "Поддержка студенчества"],
			"lore": "Шпеер осознает крах рабской экономики и предлагает модернизацию системы, опираясь на технократов и реформаторов Цольферайна."
		},
		"BOR": {
			"tag": "BOR",
			"name": "Германия (Мартин Борман / Партократы)",
			"leader_name": "Мартин Борман",
			"leader_title": "Партийный Секретарь НСДАП / Коричневое Преосвященство",
			"ideology": "Национал-Социализм",
			"sub_ideology": "Ортодоксальный НСДАП",
			"theater": "theater_gcw",
			"color": Color(0.60, 0.45, 0.25),
			"portrait_path": "res://data/countries/GER/leaders/portraits/GER_martin_bormann.png",
			"difficulty_rating": "●●○○○ (НИЗКАЯ)",
			"starting_gdp": 95.0,
			"starting_manpower": 380000,
			"starting_factories": 140,
			"traits": ["Коричневое преосвященство", "Аппаратная паутина", "Консервация статуса-кво"],
			"lore": "Борман опирается на партийных функционеров и госаппарат. Его кредо — сохранение наследия фюрера без опасных реформ и военных авантюр."
		},
		"GOR": {
			"tag": "GOR",
			"name": "Германия (Герман Геринг / Милитаристы)",
			"leader_name": "Герман Геринг",
			"leader_title": "Рейхсмаршал Великогермании / Глава Люфтваффе",
			"ideology": "Национал-Социализм",
			"sub_ideology": "Милитаризм Вермахта",
			"theater": "theater_gcw",
			"color": Color(0.48, 0.52, 0.58),
			"portrait_path": "res://data/countries/GER/leaders/portraits/GER_hermann_goring.png",
			"difficulty_rating": "●●●●○ (ВЫСОКАЯ)",
			"starting_gdp": 90.0,
			"starting_manpower": 420000,
			"starting_factories": 150,
			"traits": ["Марионетка Шёрнера", "Экономика непрерывного грабежа", "Воздушный триумф"],
			"lore": "Геринг пошел на поводу у ультра-милитаристов Шёрнера. Единственный выход из банкротства Рейха они видят в непрерывных блицкригах по всей Евразии."
		},
		"HEY": {
			"tag": "HEY",
			"name": "Германия (Рейнхард Гейдрих / Черный Орден СС)",
			"leader_name": "Рейнхард Гейдрих",
			"leader_title": "Обергруппенфюрер СС / Пражский Мясник",
			"ideology": "Бургундская Система",
			"sub_ideology": "Спартанизм СС",
			"theater": "theater_gcw",
			"color": Color(0.18, 0.18, 0.24),
			"portrait_path": "res://data/countries/GER/leaders/portraits/GER_reinhard_heydrich.png",
			"difficulty_rating": "●●●●● (ЭКСТРЕМАЛЬНАЯ)",
			"starting_gdp": 70.0,
			"starting_manpower": 180000,
			"starting_factories": 95,
			"traits": ["Пражский мясник", "Орудие Гиммлера", "Черный орден"],
			"lore": "Гейдрих выступает как проводник воли Генриха Гиммлера. Спартанский террор и безжалостная чистка выродков приведут мир к очистительному пламени."
		},

		# --- СВЕРХДЕРЖАВЫ ---
		"USA": {
			"tag": "USA",
			"name": "Соединенные Штаты Америки",
			"leader_name": "Ричард Никсон",
			"leader_title": "Президент США",
			"ideology": "Либеральная Демократия",
			"sub_ideology": "Республиканско-Демократическая Коалиция",
			"theater": "theater_superpowers",
			"color": Color(0.20, 0.40, 0.85),
			"portrait_path": "res://assets/gfx/leaders/USA/USA_Richard_Nixon.png",
			"difficulty_rating": "●●○○○ (УМЕРЕННАЯ)",
			"starting_gdp": 280.0,
			"starting_manpower": 650000,
			"starting_factories": 310,
			"traits": ["Мастер кулуаров", "Альянс ОФН", "Гражданские права под вопросом"],
			"lore": "Оплот свободного мира после поражения во Второй мировой. Никсон стремится сохранить глобальное влияние через альянс OFN и прокси-войны в Африке и Азии."
		},
		"GER": {
			"tag": "GER",
			"name": "Великогерманский Рейх",
			"leader_name": "Адольф Гитлер",
			"leader_title": "Фюрер и Рейхсканцлер",
			"ideology": "Национал-Социализм",
			"sub_ideology": "Тоталитарный Патернализм",
			"theater": "theater_superpowers",
			"color": Color(0.30, 0.30, 0.30),
			"portrait_path": "res://icon.svg",
			"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
			"starting_gdp": 210.0,
			"starting_manpower": 850000,
			"starting_factories": 280,
			"traits": ["Дряхлеющий титан", "Рабская экономика", "Смертельный кризис наследия"],
			"lore": "Гегемон Европы, стоящий на краю пропасти. Увядающий фюрер не может остановить экономическую стагнацию и надвигающуюся резню за трон."
		},
		"JAP": {
			"tag": "JAP",
			"name": "Великая Японская Империя",
			"leader_name": "Хироя Ино",
			"leader_title": "Премьер-министр Японии",
			"ideology": "Фашизм",
			"sub_ideology": "Ассоциация Помощи Трону",
			"theater": "theater_superpowers",
			"color": Color(0.80, 0.20, 0.25),
			"portrait_path": "res://assets/gfx/leaders/JAP/JAP_Ino_Hiroya.png",
			"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
			"starting_gdp": 190.0,
			"starting_manpower": 780000,
			"starting_factories": 240,
			"traits": ["Кризис корпорации «Ясуда»", "Борьба Армии и Флота (IJA vs IJN)", "Палата Пэров и Дайэт"],
			"lore": "Хозяин Азии и Тихого океана. Япония балансирует между враждующими армией (ИЯА) и флотом (ИЯФ), извлекая богатства из колониальной Сферы Сопроцветания, пока не грянул крах конгломерата Ясуда."
		},
		"ITA": {
			"tag": "ITA",
			"name": "Итальянская Империя (Regno d'Italia)",
			"leader_name": "Галеаццо Чиано",
			"leader_title": "Премьер-министр и Президент Совета",
			"ideology": "Фашизм",
			"sub_ideology": "Авторитарный Реформизм",
			"theater": "theater_europe",
			"color": Color(0.20, 0.50, 0.40),
			"portrait_path": "res://assets/gfx/leaders/ITA/ITA_Galeazzo_Ciano.png",
			"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
			"starting_gdp": 145.0,
			"starting_manpower": 520000,
			"starting_factories": 180,
			"traits": ["Зять Муссолини", "Крах Триумвирата", "Рана Атлантропы", "Великий Фашистский Совет"],
			"lore": "Италия одержала победу во Второй мировой, но оказалась у разбитого корыта: проект Атлантропа иссушил Адриатику и разорил Медзоджорно. Средиземноморский Триумвират трещит по швам, а в Великом Совете Чиано ведет войну не на жизнь, а на смерть против фашистских ортодоксов Скорцы."
		},
		"IBR": {
			"tag": "IBR",
			"name": "Иберийский Союз (Испания и Португалия)",
			"leader_name": "Франсиско Франко",
			"leader_title": "Каудильо Иберии",
			"ideology": "Деспотизм",
			"sub_ideology": "Авторитарный Корпоративизм",
			"theater": "theater_europe",
			"color": Color(0.70, 0.40, 0.15),
			"portrait_path": "res://assets/gfx/leaders/IBR/IBR_Francisco_Franco.png",
			"difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
			"starting_gdp": 68.0,
			"starting_manpower": 320000,
			"starting_factories": 65,
			"traits": ["Хрупкий дуумвират", "Каталонский кризис", "Баскский сепаратизм"],
			"lore": "Франсиско Франко и Антониу ди Салазар удерживают хрупкий Иберийский Союз. Единство двух диктатур подвергается испытаниям со стороны сепаратистов Каталонии и Басконии, террористов и неизбежной борьбы за престолонаследие."
		},
		"FRD": {
			"tag": "FRD",
			"name": "Французская Республика (Сопротивление)",
			"leader_name": "Валери Жискар д'Эстен",
			"leader_title": "Президент Республики",
			"ideology": "Либерализм",
			"sub_ideology": "Республиканский Демократизм",
			"theater": "theater_europe",
			"color": Color(0.25, 0.40, 0.70),
			"portrait_path": "res://assets/gfx/leaders/FRD/FRD_Valery_Giscard_dEstaing.png",
			"difficulty_rating": "●●●●○ (ВЫСОКАЯ)",
			"starting_gdp": 45.0,
			"starting_manpower": 160000,
			"starting_factories": 48,
			"traits": ["Подпольная армия", "Борьба за свободу", "Тень Бургундии"],
			"lore": "Французская Республика под руководством Валери Жискар д'Эстена борется за восстановление демократической и свободной Франции, отвергая как нацистское ярмо Режима Виши, так и террор Бургундии."
		},
		"BRG": {
			"tag": "BRG",
			"name": "Орденштадт Бургундия (SS-Staat)",
			"leader_name": "Генрих Гиммлер",
			"leader_title": "Рейхсфюрер СС",
			"ideology": "Бургундская Система",
			"sub_ideology": "Спартанский Эзотеризм",
			"theater": "theater_europe",
			"color": Color(0.12, 0.12, 0.16),
			"portrait_path": "res://assets/gfx/leaders/BRG/BRG_Heinrich_Himmler.png",
			"difficulty_rating": "●●●●● (ЭКСТРЕМАЛЬНАЯ)",
			"starting_gdp": 55.0,
			"starting_manpower": 240000,
			"starting_factories": 85,
			"traits": ["Черный Орден", "Апокалиптический культ", "Тотальный контроль"],
			"lore": "Генрих Гиммлер превратил Бургундию в самый закрытый и зловещий тоталитарный лагерь на планете. За колючей проволокой СС куются планы апокалипсиса, призванного очистить Землю в ядерном пламени."
		}
	}

	if content_loader != null and content_loader.has_extracted_data():
		var extracted_dossier = content_loader.get_country_dossier(tag)
		if not extracted_dossier.is_empty():
			if str(extracted_dossier.get("lore", "")).is_empty() and dossiers.has(tag):
				extracted_dossier["lore"] = dossiers[tag].get("lore", "")
			if extracted_dossier.get("traits", []).is_empty() and dossiers.has(tag):
				extracted_dossier["traits"] = dossiers[tag].get("traits", [])
			return extracted_dossier

	return dossiers.get(tag, dossiers["WRS"])


# ==============================================================================
# ИНИЦИАЛИЗАЦИЯ И СТАРТ ИГРЫ
# ==============================================================================

func bootstrap_new_game(config: GameStartConfig) -> void:
	current_config = config
	var dossier = get_country_dossier(config.selected_country_tag)

	# Создание главного CountryState для игрока
	var state = CountryState.new()
	state.country_tag = dossier["tag"]
	state.country_name = dossier["name"]
	state.leader_name = dossier["leader_name"]
	state.ruling_ideology = dossier["ideology"]
	state.sub_ideology = dossier["sub_ideology"]
	state.country_color = dossier["color"]
	state.gdp_billions = dossier.get("starting_gdp", 20.0)
	state.manpower_pool = dossier.get("starting_manpower", 75000)
	state.military_factories = int(dossier.get("starting_factories", 30) * 0.6)
	state.civilian_factories = int(dossier.get("starting_factories", 30) * 0.4)
	state.war_support_percent = float(dossier.get("war_support_percent", dossier.get("starting_war_support", 65.0)))


	# Применение модификаторов сложности
	_apply_difficulty(state, config.difficulty)

	# Применение глобальных правил
	state.set_flag("german_anarchy_timer", config.rules.get("german_anarchy_timer", true))
	state.set_flag("dynamic_defcon", config.rules.get("dynamic_nuclear_defcon", true))
	state.set_flag("battle_incidents", config.rules.get("battlefield_incidents", true))
	state.set_flag("time_step_mode", config.time_step_mode)

	active_player_state = state
	session_bootstrapped.emit(config)

	# Переход на боевую сцену
	get_tree().change_scene_to_file("res://ui/screens/terminal_main.tscn")


func _apply_difficulty(state: CountryState, diff: Difficulty) -> void:
	match diff:
		Difficulty.OBSERVER:
			state.political_capital = 150.0
			state.pc_gain_per_turn = 8.0
			state.liquid_reserves_billions += 2.0
			state.legitimacy = 80.0
			state.radicalization = 15.0
			state.real_gdp_growth = 0.06
		Difficulty.STRATEGIST:
			state.political_capital = 100.0
			state.pc_gain_per_turn = 5.0
			state.legitimacy = 65.0
			state.radicalization = 30.0
			state.real_gdp_growth = 0.045
		Difficulty.CRISIS:
			state.political_capital = 60.0
			state.pc_gain_per_turn = 3.5
			state.liquid_reserves_billions = maxf(state.liquid_reserves_billions - 0.5, 0.2)
			state.legitimacy = 50.0
			state.radicalization = 45.0
			state.real_gdp_growth = 0.02
			state.inflation_rate = 0.075


func apply_crt_to_material(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	if has_node("/root/SettingsManager"):
		var sm = get_node("/root/SettingsManager")
		sm.apply_crt_to_material(mat)
		crt_settings_updated.emit(sm.crt_settings)
		return
	for k in crt_settings.keys():
		mat.set_shader_parameter(k, crt_settings[k])
	crt_settings_updated.emit(crt_settings)
