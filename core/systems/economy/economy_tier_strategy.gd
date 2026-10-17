class_name EconomyTierStrategy
extends Resource

##
## EconomyTierStrategy: Базовый класс паттерна "Стратегия" для рангов экономики.
## Определяет правила функционирования экономики страны в зависимости от ее геополитического статуса:
## Варлорд, Малая держава, Региональная держава, Сверхдержава.
##

enum TierType {
	WARLORD = 0,
	MINOR_POWER = 1,
	REGIONAL_POWER = 2,
	SUPERPOWER = 3
}

signal budget_deficit_handled(deficit_amount: float, resolution_method: StringName)
signal crisis_detected(crisis_type: StringName)
signal simulation_completed(report: Dictionary)


"""Возвращает тип ранга державы."""
func get_tier_type() -> TierType:
	return TierType.REGIONAL_POWER


"""Возвращает человекочитаемое наименование ранга державы."""
func get_tier_name() -> String:
	return "Regional Power"


"""Выполняет расчет ежемесячного экономического тика по правилам данного ранга."""
func process_monthly_economy(_state: EconomyStateResource, _modifiers: Dictionary = {}) -> Dictionary:
	return {}


"""Обрабатывает дефицит бюджета в соответствии с возможностями и институтами ранга."""
func handle_budget_deficit(_state: EconomyStateResource, _deficit_amount: float) -> void:
	pass


"""Возвращает список доступных игровых экономических стимуляций и решений."""
func get_available_stimulations() -> Array[StringName]:
	return []


"""Проверяет условия возникновения специфических кризисов для данного ранга."""
func check_crisis_conditions(_state: EconomyStateResource) -> Array[StringName]:
	return []
