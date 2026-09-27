class_name SocietalMetricResource
extends Resource

##
## SocietalMetricResource: Модель институциональной шкалы развития общества (Societal Metric)
## Реализует долгосрочную пошаговую эволюцию институтов в стиле TNO / Toolbox Theory.
##

signal value_changed(old_value: float, new_value: float)
signal tier_changed(old_tier: int, new_tier: int)

# Диапазоны институциональных уровней (0.0 .. 100.0)
const TIER_1_MAX = 20.0 # 0.0 .. 19.9: Разруха / Архаика
const TIER_2_MAX = 40.0 # 20.0 .. 39.9: Минимальный / Кустарный уровень (варлорды)
const TIER_3_MAX = 60.0 # 40.0 .. 59.9: Удовлетворительный / Базовый госстандарт
const TIER_4_MAX = 80.0 # 60.0 .. 79.9: Развитый / Индустриальный стандарт передовых держав
# 80.0 .. 100.0: Передовой / Золотой век благосостояния

@export var metric_key: String = "academic_base"
@export var metric_name: String = "Академическая база"
@export_multiline var description: String = ""

## Текущее значение институциональной шкалы [0.0 .. 100.0]
@export_range(0.0, 100.0, 0.1) var current_value: float = 25.0:
	set(val):
		var clamped = clampf(val, 0.0, 100.0)
		if not is_equal_approx(current_value, clamped):
			var old_val = current_value
			var old_t = get_tier_for_value(old_val)
			current_value = clamped
			var new_t = get_tier_for_value(current_value)
			value_changed.emit(old_val, current_value)
			if old_t != new_t:
				tier_changed.emit(old_t, new_t)

## Равновесная целевая планка, задаваемая действующим законодательством [0.0 .. 100.0]
@export_range(0.0, 100.0, 0.1) var target_value: float = 25.0

## Базовая инерционная скорость приближения к целевой планке за ход
@export var velocity: float = 0.05

## Базовый износ / естественная деградация за ход
@export var base_decay: float = 0.15

## История значений по ходам (последние 20 ходов)
@export var history: Array[float] = []

## Кэшированные системные модификаторы от текущего значения шкалы
@export var state_modifiers: Dictionary = {}

## Текстовые названия институциональных тиров для каждой базовой шкалы
const TIER_NAMES: Dictionary = {
	"academic_base": {
		1: "Разруха науки и образования",
		2: "Кустарно-технические школы",
		3: "Среднее образование и техникумы",
		4: "Индустриальные НИИ и политехи",
		5: "Академический авангард"
	},
	"public_health": {
		1: "Эпидемический коллапс и мор",
		2: "Полевые фельдшерские пункты",
		3: "Санитарная служба и поликлиники",
		4: "Развитая сеть клинических больниц",
		5: "Передовая всеобщая медицина"
	},
	"pension_welfare": {
		1: "Социальная разруха и нищета",
		2: "Пайки ветеранам и инвалидам",
		3: "Базовые пенсии и пособия",
		4: "Развитое социальное страхование",
		5: "Государство всеобщего благоденствия"
	},
	"labor_rights": {
		1: "Подневольный и каторжный труд",
		2: "Военная трудовая мобилизация",
		3: "Нормированный рабочий день",
		4: "Защищенные профсоюзы",
		5: "Промышленная демократия"
	},
	"administrative_integrity": {
		1: "Тотальное казнокрадство",
		2: "Кумовство и поборы варлордов",
		3: "Удовлетворительный госучет",
		4: "Профессиональная неподкупная служба",
		5: "Абсолютная финансовая прозрачность"
	},
	"social_cohesion": {
		1: "Расовый апартеид и сегрегация",
		2: "Вооруженное перемирие общин",
		3: "Базовые гражданские гарантии",
		4: "Широкая гражданская нация",
		5: "Гармоничное сплоченное общество"
	}
}

const TIER_DESCRIPTIONS: Dictionary = {
	"academic_base": {
		1: "Школы сожжены или закрыты, университеты пустуют. Катастрофический отток умов и технологическая слепота.",
		2: "Кустарные курсы грамоты и ремесленные училища. Подготовка механиков и стрелков для фронта.",
		3: "Стабильная система всеобщего среднего образования, выпуск квалифицированных заводских кадров.",
		4: "Мощная сеть научно-исследовательских институтов, опережающая модернизация вооружений и технологий.",
		5: "Золотой век науки. Ведущие мировые лаборатории, атомные и космические прорывы."
	},
	"public_health": {
		1: "Вспышки тифа и холеры, отсутствие чистой воды и антибиотиков. Огромная небоевая смертность.",
		2: "Примитивные полевые лазареты. Доступны бинты и простейшие медикаменты, операции без должного наркоза.",
		3: "Государственный контроль санитарных норм, вакцинация, базовые родильные дома и терапия.",
		4: "Современная специализированная медицина, доступность фармакологии и быстрое возвращение солдат в строй.",
		5: "Высочайшая продолжительность жизни, передовые хирургические центры и превентивная медицина."
	},
	"pension_welfare": {
		1: "Старики и сироты брошены на произвол судьбы. Хронический голод и всплеск отчаянных радикалов.",
		2: "Минимальные сухие пайки семьям погибших бойцов и инвалидам труда.",
		3: "Гарантированная государственная пенсия по старости и фиксированные пособия по безработице.",
		4: "Широкий охват социальной помощи, поддерживающий потребительский спрос и снижающий преступность.",
		5: "Комплексная защита от колыбели до могилы. Абсолютное доверие граждан социальным гарантиям государства."
	},
	"labor_rights": {
		1: "Бесправный подневольный труд. Высочайшая смертность на производстве, ненависть рабочих к властям.",
		2: "Жесткая трудовая повинность, 12-14 часовые смены без выходных ради фронтовых заказов.",
		3: "Восьмичасовой рабочий день, базовые нормы техники безопасности и компенсация травматизма.",
		4: "Легальные сильные профсоюзы, оплачиваемые отпуска и справедливая оплата сверхурочных.",
		5: "Рабочее самоуправление, высокие стандарты эргономики и высочайшая производительность труда."
	},
	"administrative_integrity": {
		1: "Чиновники открыто разворовывают бюджет и склады. Налоги не доходят до казны, взятки правят судом.",
		2: "Полевые командиры и коменданты собирают дань в личный карман, ведомственный хаос.",
		3: "Базовая отчетность и ревизии. Коррупция существует, но масштабные махинации пресекаются.",
		4: "Строгие антикоррупционные трибуналы, высокая собираемость налогов и целевое расходование казны.",
		5: "Меритократический госаппарат с нулевой терпимостью к взяткам. Предельный КПД бюджетных трат."
	},
	"social_cohesion": {
		1: "Открытый террор против меньшинств, этнические чистки и постоянная угроза восстаний.",
		2: "Хрупкий баланс между враждующими группировками. Взаимное недоверие и дискриминация.",
		3: "Равенство перед законом независимо от происхождения. Локальные трения подавляются судами.",
		4: "Культурный плюрализм, высокая степень взаимопомощи и патриотического единства нации.",
		5: "Идеальная социальная солидарность, абсолютная устойчивость к провокациям и иностранному шпионажу."
	}
}


func _init(p_key: String = "academic_base", p_name: String = "Академическая база", p_val: float = 25.0) -> void:
	metric_key = p_key
	metric_name = p_name
	current_value = p_val
	target_value = p_val


## Возвращает дискретный уровень институтов [1..5]
static func get_tier_for_value(val: float) -> int:
	if val < TIER_1_MAX:
		return 1
	elif val < TIER_2_MAX:
		return 2
	elif val < TIER_3_MAX:
		return 3
	elif val < TIER_4_MAX:
		return 4
	else:
		return 5


## Возвращает текущий уровень шкалы
func get_tier() -> int:
	return get_tier_for_value(current_value)


## Название текущего институционального уровня
func get_tier_name() -> String:
	var t = get_tier()
	if TIER_NAMES.has(metric_key) and TIER_NAMES[metric_key].has(t):
		return TIER_NAMES[metric_key][t]
	match t:
		1: return "Разруха / Архаика"
		2: return "Минимальный / Кустарный уровень"
		3: return "Удовлетворительный / Базовый госстандарт"
		4: return "Развитый / Индустриальный стандарт"
		5: return "Передовой / Золотой век благосостояния"
	return "Неизвестный уровень"


## Описание текущего институционального уровня
func get_tier_description() -> String:
	var t = get_tier()
	if TIER_DESCRIPTIONS.has(metric_key) and TIER_DESCRIPTIONS[metric_key].has(t):
		return TIER_DESCRIPTIONS[metric_key][t]
	return description


## Сохраняет текущее значение в историю ходов
func record_history() -> void:
	history.append(current_value)
	if history.size() > 52: # Храним историю за последний год
		history.pop_front()


## Возвращает тренд изменения за последние N ходов
func get_trend(turns: int = 4) -> float:
	if history.is_empty():
		return 0.0
	var count = mini(turns, history.size())
	var start_idx = history.size() - count
	return current_value - history[start_idx]


## Рассчитывает системные макроэкономические модификаторы для CountryState
func calculate_modifiers() -> Dictionary:
	var mods: Dictionary = {}
	var normalized = current_value / 100.0 # 0.0 .. 1.0
	var tier = get_tier()

	match metric_key:
		"academic_base":
			# Влияет на множитель НИОКР и совокупную факторную производительность (A в Коббе-Дугласе)
			mods["rd_speed_mult"] = 0.5 + (normalized * 0.8) # 0.5 .. 1.3
			mods["total_factor_productivity"] = 0.85 + (normalized * 0.35) # 0.85 .. 1.20
			mods["literacy_target"] = current_value
			if tier == 1:
				mods["brain_drain_penalty"] = -0.05

		"public_health":
			# Влияет на демографический прирост и снижение небоевых потерь
			mods["pop_growth_rate"] = -0.005 + (normalized * 0.02) # -0.5% .. +1.5%
			mods["attrition_reduction"] = normalized * 0.35 # До 35% снижения истощения
			if tier == 1:
				mods["epidemic_risk"] = 0.25

		"pension_welfare":
			# Влияет на снижение радикализации и потребительские расходы домохозяйств
			mods["unrest_reduction_per_turn"] = normalized * 0.25
			mods["consumer_spending_boost"] = 0.80 + (normalized * 0.40) # 0.8 .. 1.2 к C
			mods["poverty_target"] = clampf(100.0 - (current_value * 0.85), 5.0, 95.0)
			if tier == 1:
				mods["bread_riot_risk"] = 0.20

		"labor_rights":
			# Влияет на лояльность левых/профсоюзов, риск забастовок и выработку фабрик (IC)
			mods["proletariat_loyalty_boost"] = (normalized - 0.4) * 25.0 # -10.0 .. +15.0
			mods["strike_risk"] = maxf(0.0, (0.40 - normalized) * 0.5) # При <40% растет риск забастовок
			mods["factory_ic_efficiency"] = 0.85 + (normalized * 0.30) # 0.85 .. 1.15
			if tier == 1:
				mods["slave_revolt_risk"] = 0.30

		"administrative_integrity":
			# Влияет на собираемость налогов (Tax Efficiency) и КПД расходов
			mods["tax_efficiency_mult"] = 0.60 + (0.40 * normalized) # 0.60 .. 1.00
			mods["procurement_leakage"] = maxf(0.0, (1.0 - normalized) * 0.30) # До 30% хищений в ВПК
			mods["corruption_target"] = clampf(100.0 - current_value, 5.0, 95.0)

		"social_cohesion":
			# Влияет на легитимность, скорость мирной интеграции и контрразведку
			mods["legitimacy_drift_per_turn"] = (normalized - 0.40) * 0.20
			mods["integration_speed_mult"] = 0.50 + (normalized * 0.80)
			mods["counter_intelligence_boost"] = normalized * 0.40
			if tier == 1:
				mods["racial_unrest_risk"] = 0.35

	state_modifiers = mods
	return mods


## Сериализация в словарь для сохранений и сетевой синхронизации
func to_dict() -> Dictionary:
	return {
		"metric_key": metric_key,
		"metric_name": metric_name,
		"description": description,
		"current_value": current_value,
		"target_value": target_value,
		"velocity": velocity,
		"base_decay": base_decay,
		"history": history.duplicate(),
		"state_modifiers": state_modifiers.duplicate(true)
	}


## Десериализация из словаря
static func from_dict(data: Dictionary) -> SocietalMetricResource:
	var res = SocietalMetricResource.new()
	res.metric_key = str(data.get("metric_key", "academic_base"))
	res.metric_name = str(data.get("metric_name", res.metric_key.capitalize()))
	res.description = str(data.get("description", ""))
	res.current_value = float(data.get("current_value", 25.0))
	res.target_value = float(data.get("target_value", res.current_value))
	res.velocity = float(data.get("velocity", 0.05))
	res.base_decay = float(data.get("base_decay", 0.15))
	
	res.history.clear()
	var raw_h = data.get("history", [])
	if raw_h is Array:
		for val in raw_h:
			res.history.append(float(val))

	if data.has("state_modifiers") and data["state_modifiers"] is Dictionary:
		res.state_modifiers = data["state_modifiers"].duplicate(true)
	else:
		res.calculate_modifiers()

	return res
