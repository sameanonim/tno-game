class_name CovertOperationResource
extends Resource

##
## CovertOperationResource: Модель спецоперации разведывательной службы TNO
##
## Определяет параметры подготовки, бюджетные затраты, риски раскрытия
## и эффекты тайных операций против вражеских государств.
##

enum OpType {
	STEAL_TECH,          ## Кража военных технологий / НИОКР
	SABOTAGE_INDUSTRY,   ## Диверсия на промышленных объектах (снижение IC)
	SABOTAGE_MILITARY,   ## Подрыв армейских складов и подрыв боеготовности
	FUND_COUP,           ## Финансирование антиправительственного путча / переворота
	ARM_REBELS,          ## Снабжение повстанцев и партизанских движений
	DISINFORMATION,      ## Дезинформация и подрыв контрразведки
	ASSASSINATION        ## Ликвидация вражеского лидера/командующего
}

# ==============================================================================
# 1. ОСНОВНЫЕ ПАРАМЕТРЫ ОПЕРАЦИИ
# ==============================================================================
@export var op_id: String = ""
@export var title: String = "Operation Black Sky"
@export var type: OpType = OpType.STEAL_TECH
@export var target_country_tag: String = "GER"

# ==============================================================================
# 2. ПОДГОТОВКА И ТРЕБОВАНИЯ
# ==============================================================================
## Необходимый порог проникновения агентурной сети (0.0..100.0%)
@export_range(0.0, 100.0, 1.0) var required_infiltration: float = 50.0

## Ежеходные операционные расходы ($ млн из Черного Бюджета)
@export var cost_per_turn: float = 1.5

## Длительность фазы подготовки в ходах
@export var total_turns_required: int = 4

## Текущий накопленный прогресс в ходах
@export var current_turn_progress: int = 0

## Базовый риск раскрытия (0.0..1.0)
@export_range(0.0, 1.0, 0.01) var base_detection_risk: float = 0.25

## Идентификаторы назначенных агентов
@export var assigned_agent_ids: Array[String] = []

## Контекстные данные спецоперации (целевая технология, склад, партия, регион)
@export var operation_payload: Dictionary = {}

## Флаг заморозки операции (дефицит черного бюджета или падение сети)
@export var is_frozen: bool = false

## Флаг досрочного экстренного сворачивания (Abort Protocol)
@export var is_aborted: bool = false


static var _seq_id: int = 100000

static func generate_unique_id(prefix: String = "op_") -> String:
	_seq_id += 1
	return prefix + str(_seq_id)


func _init(
	p_op_id: String = "",
	p_title: String = "Covert Operation",
	p_type: OpType = OpType.STEAL_TECH,
	p_target_tag: String = "",
	p_req_inf: float = 50.0,
	p_cost: float = 1.5,
	p_turns: int = 4,
	p_risk: float = 0.25
) -> void:
	if not p_op_id.is_empty():
		op_id = p_op_id
	else:
		op_id = generate_unique_id("op_")
	title = p_title
	type = p_type
	target_country_tag = p_target_tag
	required_infiltration = clampf(p_req_inf, 0.0, 100.0)
	cost_per_turn = maxf(p_cost, 0.1)
	total_turns_required = maxi(p_turns, 1)
	current_turn_progress = 0
	base_detection_risk = clampf(p_risk, 0.05, 0.95)
	assigned_agent_ids = []
	operation_payload = {}
	is_frozen = false
	is_aborted = false


## Возвращает коэффициент прогресса [0.0..1.0]
func get_progress_ratio() -> float:
	if total_turns_required <= 0:
		return 1.0
	return clampf(float(current_turn_progress) / float(total_turns_required), 0.0, 1.0)


## Возвращает псевдографический прогресс-бар [████░░░░]
func get_progress_bar_string(bar_width: int = 10) -> String:
	var ratio = get_progress_ratio()
	var filled_count = int(round(ratio * bar_width))
	var bar_str := "["
	for i in range(bar_width):
		if i < filled_count:
			bar_str += "█"
		else:
			bar_str += "░"
	bar_str += "] %d%%" % int(ratio * 100.0)
	return bar_str


## Возвращает русское наименование типа операции
func get_type_name_ru() -> String:
	match type:
		OpType.STEAL_TECH:
			return "КРАЖА ЧЕРТЕЖЕЙ (НИОКР)"
		OpType.SABOTAGE_INDUSTRY:
			return "ДИВЕРСИЯ НА ПРЕДПРИЯТИЯХ (IC)"
		OpType.SABOTAGE_MILITARY:
			return "ПОДРЫВ АРМЕЙСКИХ СКЛАДОВ"
		OpType.FUND_COUP:
			return "ФИНАНСИРОВАНИЕ ПЕРЕВОРОТА"
		OpType.ARM_REBELS:
			return "СНАБЖЕНИЕ ПАРТИЗАН"
		OpType.DISINFORMATION:
			return "ДЕЗИНФОРМАЦИОННАЯ КАМПАНИЯ"
		OpType.ASSASSINATION:
			return "ЛИКВИДАЦИЯ КОМАНДНОГО СОСТАВА"
		_:
			return "СПЕЦОПЕРАЦИЯ"


# ==============================================================================
# СЕРИАЛИЗАЦИЯ (JSON / SAVEGAME)
# ==============================================================================

func to_dict() -> Dictionary:
	return {
		"op_id": op_id,
		"title": title,
		"type": type,
		"target_country_tag": target_country_tag,
		"required_infiltration": required_infiltration,
		"cost_per_turn": cost_per_turn,
		"total_turns_required": total_turns_required,
		"current_turn_progress": current_turn_progress,
		"base_detection_risk": base_detection_risk,
		"assigned_agent_ids": assigned_agent_ids.duplicate(),
		"operation_payload": operation_payload.duplicate(true),
		"is_frozen": is_frozen,
		"is_aborted": is_aborted
	}


static func from_dict(data: Dictionary) -> CovertOperationResource:
	var op = CovertOperationResource.new()
	var raw_id = str(data.get("op_id", ""))
	op.op_id = raw_id if not raw_id.is_empty() else generate_unique_id("op_")
	op.title = str(data.get("title", "Covert Operation"))
	op.type = data.get("type", OpType.STEAL_TECH) as OpType
	op.target_country_tag = str(data.get("target_country_tag", ""))
	op.required_infiltration = float(data.get("required_infiltration", 50.0))
	op.cost_per_turn = float(data.get("cost_per_turn", 1.5))
	op.total_turns_required = maxi(int(data.get("total_turns_required", 4)), 1)
	op.current_turn_progress = int(data.get("current_turn_progress", 0))
	op.base_detection_risk = float(data.get("base_detection_risk", 0.25))
	op.is_frozen = bool(data.get("is_frozen", false))
	op.is_aborted = bool(data.get("is_aborted", false))
	
	op.assigned_agent_ids.clear()
	for aid in data.get("assigned_agent_ids", []):
		op.assigned_agent_ids.append(str(aid))
		
	var payload = data.get("operation_payload", {})
	if payload is Dictionary:
		op.operation_payload = payload.duplicate(true)
		
	return op
