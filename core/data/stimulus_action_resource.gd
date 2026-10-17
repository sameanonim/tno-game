class_name StimulusActionResource
extends Resource

##
## StimulusActionResource: Описание экономической стимуляции, фискального пакета или монетарной интервенции.
## Хранит базовые параметры доступности, стоимость в политической силе и казне,
## а также разделяет влияние на краткосрочный импульс (3-6 месяцев) и долгосрочные последствия.
##

@export_group("Identity & Availability")
@export var id: StringName = &""
@export var title: String = ""
@export_multiline var description: String = ""

## Разрешенные ранги экономики (соответствуют enum EconomyTierStrategy.TierType: 0 - Warlord, 1 - Minor, 2 - Regional, 3 - Superpower)
@export var allowed_tiers: Array[int] = []

## Период перезарядки в днях (30 дней ~= 1 месяц)
@export var cooldown_days: int = 180

## Длительность действия краткосрочного импульса в месяцах
@export var impulse_duration_months: int = 6

@export_group("Activation Costs")
## Стоимость в политическом капитале (PP / PC)
@export var political_power_cost: float = 25.0

## Прямые затраты из ликвидных резервов казны ($ млрд)
@export var reserve_cost: float = 0.0

@export_group("Effects Definition")
## Мгновенные дельты, применяемые в момент активации (например, приток наличных, списание долга)
@export var immediate_effects: Dictionary = {}

## Модификаторы, активные во время фазы краткосрочного импульса (передаются в monthly tick)
@export var short_term_modifiers: Dictionary = {}

## Долгосрочные структурные последствия, вступающие в силу по завершении импульса
## (например, износ оборудования, рост естественной безработицы, инфляционный похмельный синдром)
@export var long_term_effects: Dictionary = {}


"""Проверяет, разрешено ли действие для переданного типа ранга."""
func is_tier_allowed(tier_type: int) -> bool:
	if allowed_tiers.is_empty():
		return true
	return allowed_tiers.has(tier_type)
