class_name LawResource
extends Resource

##
## LawResource: Модель государственного закона / института (Societal Law)
## Задает институциональные планки (Target Equilibrium), фискальный след (EXPENSE / REVENUE / NEUTRAL)
## и условия для пошаговой эволюции шкал социального развития.
##

enum FiscalType {
	EXPENSE, ## Требует прямого бюджетного финансирования (медицина, образование, пенсии)
	REVENUE, ## Влияет на наполнение доходной части казны (налоговый кодекс, таможня, монополии)
	NEUTRAL  ## Регуляторный закон без прямых госрасходов (рабочий день, гражданские права, цензура)
}

@export var law_id: String = "law_default"
@export var law_name: String = "Трудовое законодательство"
@export var category: String = "labor"
@export var fiscal_type: FiscalType = FiscalType.EXPENSE

## Базовый фискальный вес (множитель удельных расходов или доходов на душу населения)
@export var base_fiscal_weight: float = 1.0

## Целевое институциональное влияние на шкалы развития общества
## Формат: {"metric_key": target_value_or_offset}
## Пример: {"public_health": 85.0} или {"labor_rights": 75.0, "public_health": -10.0}
@export var target_societal_impact: Dictionary = {}

## Дополнительные пассивные модификаторы (лояльность фракций, IC, боеготовность)
@export var modifiers: Dictionary = {}

## Уровень градации закона [1 .. max_tier]
@export var tier: int = 1
@export var max_tier: int = 5

## Текстовое отображение ступени (например, "Всеобщая страховая медицина")
@export var value_text: String = "Базовый закон"
@export_multiline var description: String = ""

## Флаг угрозы срыва / деградации закона из-за недофинансирования
@export var is_under_threat: bool = false

## Натуральное обеспечение для варлордов Русской Смуты (товары со складов за ход)
## Пример: {"infantry_weapons": 50, "oil": 1}
@export var in_kind_goods_cost: Dictionary = {}


func _init(
	p_id: String = "",
	p_name: String = "",
	p_category: String = "",
	p_fiscal: FiscalType = FiscalType.EXPENSE,
	p_tier: int = 1,
	p_val_text: String = ""
) -> void:
	law_id = p_id
	law_name = p_name
	category = p_category
	fiscal_type = p_fiscal
	tier = p_tier
	value_text = p_val_text


## Текстовое обозначение фискального типа
func get_fiscal_type_name() -> String:
	match fiscal_type:
		FiscalType.EXPENSE: return "EXPENSE"
		FiscalType.REVENUE: return "REVENUE"
		FiscalType.NEUTRAL: return "NEUTRAL"
	return "UNKNOWN"


## Возвращает структуру, совместимую с legacy-панелями UI и тестами (PoliticsPanel)
func to_legacy_dict() -> Dictionary:
	return {
		"id": law_id,
		"name": law_name,
		"category": category,
		"value": value_text,
		"tier": tier,
		"max_tier": max_tier,
		"fiscal_type": get_fiscal_type_name(),
		"is_under_threat": is_under_threat
	}


## Полная сериализация
func to_dict() -> Dictionary:
	return {
		"law_id": law_id,
		"law_name": law_name,
		"category": category,
		"fiscal_type": get_fiscal_type_name(),
		"base_fiscal_weight": base_fiscal_weight,
		"target_societal_impact": target_societal_impact.duplicate(true),
		"modifiers": modifiers.duplicate(true),
		"tier": tier,
		"max_tier": max_tier,
		"value_text": value_text,
		"description": description,
		"is_under_threat": is_under_threat,
		"in_kind_goods_cost": in_kind_goods_cost.duplicate(true)
	}


## Десериализация
static func from_dict(data: Dictionary) -> LawResource:
	var law = LawResource.new()
	law.law_id = str(data.get("law_id", data.get("id", "law_custom")))
	law.law_name = str(data.get("law_name", data.get("name", "Закон")))
	law.category = str(data.get("category", "general"))
	
	var f_type_str = str(data.get("fiscal_type", "EXPENSE")).to_upper()
	match f_type_str:
		"REVENUE": law.fiscal_type = FiscalType.REVENUE
		"NEUTRAL": law.fiscal_type = FiscalType.NEUTRAL
		_: law.fiscal_type = FiscalType.EXPENSE

	law.base_fiscal_weight = float(data.get("base_fiscal_weight", 1.0))
	if data.has("target_societal_impact") and data["target_societal_impact"] is Dictionary:
		law.target_societal_impact = data["target_societal_impact"].duplicate(true)
	if data.has("modifiers") and data["modifiers"] is Dictionary:
		law.modifiers = data["modifiers"].duplicate(true)

	law.tier = int(data.get("tier", 1))
	law.max_tier = int(data.get("max_tier", 5))
	law.value_text = str(data.get("value_text", data.get("value", "")))
	law.description = str(data.get("description", ""))
	law.is_under_threat = bool(data.get("is_under_threat", false))

	if data.has("in_kind_goods_cost") and data["in_kind_goods_cost"] is Dictionary:
		law.in_kind_goods_cost = data["in_kind_goods_cost"].duplicate(true)

	return law
