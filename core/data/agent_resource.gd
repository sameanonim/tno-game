class_name AgentResource
extends Resource

##
## AgentResource: Модель оперативного агента внешней и внутренней разведки TNO
##
## Представляет секретного агента спецслужб (ЦРУ, Абвер/СД, КГБ/НКВД Варлорда).
## Участвует в развертывании агентурных сетей и проведении спецопераций.
##

enum AgentStatus {
	IDLE,           ## Свободен / В резерве
	INFILTRATING,   ## Развертывание агентурной сети в целевой стране
	EXECUTING_OP,   ## Непосредственное выполнение спецоперации
	COMPROMISED,    ## Скомпрометирован / Раскрыт
	CAPTURED        ## Арестован контрразведкой противника
}

# ==============================================================================
# 1. ИДЕНТИФИКАТОРЫ И ПАСПОРТ АГЕНТА
# ==============================================================================
@export var id: String = ""
@export var codename: String = "Shadow"
@export var assigned_country_tag: String = ""

# ==============================================================================
# 2. ОПЕРАТИВНЫЕ ХАРАКТЕРИСТИКИ
# ==============================================================================
## Навык/компетентность агента (от 1 до 5 звезд)
@export_range(1, 5, 1) var competence: int = 3

## Уровень личной лояльности агента (0.0..100.0)
## При падении ниже 30.0 резко возрастает риск перевербовки в двойного агента
@export_range(0.0, 100.0, 1.0) var loyalty: float = 85.0

## Текущий оперативный статус
@export var status: AgentStatus = AgentStatus.IDLE

## Стоимость содержания за ход ($ млн из Черного Бюджета)
@export var upkeep_cost_black_budget: float = 0.5

## Флаг перевербовки вражеской контрразведкой (двойной агент)
@export var is_double_agent: bool = false

## Оперативные специализации (traits)
@export var traits: Array[String] = []


static var _seq_id: int = 100000

static func generate_unique_id(prefix: String = "agent_") -> String:
	_seq_id += 1
	return prefix + str(_seq_id)


func _init(
	p_id: String = "",
	p_codename: String = "Shadow",
	p_competence: int = 3,
	p_loyalty: float = 85.0,
	p_upkeep: float = 0.5
) -> void:
	if not p_id.is_empty():
		id = p_id
	else:
		id = generate_unique_id("agent_")
	codename = p_codename
	competence = clampi(p_competence, 1, 5)
	loyalty = clampf(p_loyalty, 0.0, 100.0)
	upkeep_cost_black_budget = maxf(p_upkeep, 0.1)


## Возвращает текстовое представление статуса на русском языке
func get_status_string_ru() -> String:
	match status:
		AgentStatus.IDLE:
			return "В РЕЗЕРВЕ"
		AgentStatus.INFILTRATING:
			return "ВНЕДРЕНИЕ (%s)" % assigned_country_tag
		AgentStatus.EXECUTING_OP:
			return "НА ОПЕРАЦИИ"
		AgentStatus.COMPROMISED:
			return "СКОМПРОМЕТИРОВАН"
		AgentStatus.CAPTURED:
			return "ЗАХВАЧЕН"
		_:
			return "НЕИЗВЕСТНО"


## Возвращает псевдографические звезды навыка
func get_stars_string() -> String:
	var stars := ""
	for i in range(5):
		if i < competence:
			stars += "★"
		else:
			stars += "☆"
	return stars


# ==============================================================================
# СЕРИАЛИЗАЦИЯ (JSON / SAVEGAME)
# ==============================================================================

func to_dict() -> Dictionary:
	return {
		"id": id,
		"codename": codename,
		"assigned_country_tag": assigned_country_tag,
		"competence": competence,
		"loyalty": loyalty,
		"status": status,
		"upkeep_cost_black_budget": upkeep_cost_black_budget,
		"is_double_agent": is_double_agent,
		"traits": traits.duplicate()
	}


static func from_dict(data: Dictionary) -> AgentResource:
	var agent = AgentResource.new()
	var raw_id = str(data.get("id", ""))
	agent.id = raw_id if not raw_id.is_empty() else generate_unique_id("agent_")
	agent.codename = str(data.get("codename", "Shadow"))
	agent.assigned_country_tag = str(data.get("assigned_country_tag", ""))
	agent.competence = clampi(int(data.get("competence", 3)), 1, 5)
	agent.loyalty = clampf(float(data.get("loyalty", 85.0)), 0.0, 100.0)
	agent.status = data.get("status", AgentStatus.IDLE) as AgentStatus
	agent.upkeep_cost_black_budget = float(data.get("upkeep_cost_black_budget", 0.5))
	agent.is_double_agent = bool(data.get("is_double_agent", false))
	agent.traits.clear()
	for t in data.get("traits", []):
		agent.traits.append(str(t))
	return agent
