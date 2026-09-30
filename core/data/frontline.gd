class_name Frontline
extends Resource

##
## Frontline: Стратегический фронт между двумя государствами (TNO Regional Unification)
##
## Объединяет оперативные направления ударов (OperationalAxis), отслеживает напряженность
## и статус активных боевых действий на стратегическом театре.
##

@export var front_id: String = "front_western_russia_unification"
@export var name: String = "Western Russia Unification Theater"
@export var attacker_tag: String = "WRS" # Нападающая сторона (ЗРРФ)
@export var defender_tag: String = "ONG" # Обороняющаяся сторона (Онега)

@export var axes: Array[OperationalAxis] = []
@export_range(0.0, 100.0, 1.0) var tension: float = 50.0
@export var active: bool = true

## Общие потери за все время существования фронта
@export var total_attacker_casualties: int = 0
@export var total_defender_casualties: int = 0


## Добавить новую оперативную ось на фронт
func add_axis(axis: OperationalAxis) -> void:
	if not axes.has(axis):
		axes.append(axis)


## Удалить оперативную ось по ID
func remove_axis(axis_id: String) -> void:
	for i in range(axes.size() - 1, -1, -1):
		if axes[i].axis_id == axis_id:
			axes.remove_at(i)
			break


func get_axis(axis_id: String) -> OperationalAxis:
	for ax in axes:
		if ax.axis_id == axis_id:
			return ax
	return null


func to_dict() -> Dictionary:
	var axes_arr: Array = []
	for ax in axes:
		if ax != null:
			axes_arr.append(ax.to_dict())

	return {
		"front_id": front_id,
		"name": name,
		"attacker_tag": attacker_tag,
		"defender_tag": defender_tag,
		"axes": axes_arr,
		"tension": tension,
		"active": active,
		"total_attacker_casualties": total_attacker_casualties,
		"total_defender_casualties": total_defender_casualties
	}


static func from_dict(data: Dictionary) -> Frontline:
	var front = Frontline.new()
	front.front_id = data.get("front_id", "front_default")
	front.name = data.get("name", "Unnamed Front")
	front.attacker_tag = data.get("attacker_tag", "")
	front.defender_tag = data.get("defender_tag", "")
	front.tension = float(data.get("tension", 50.0))
	front.active = bool(data.get("active", true))
	front.total_attacker_casualties = int(data.get("total_attacker_casualties", 0))
	front.total_defender_casualties = int(data.get("total_defender_casualties", 0))

	front.axes.clear()
	for ax_dict in data.get("axes", []):
		if ax_dict is Dictionary:
			front.axes.append(OperationalAxis.from_dict(ax_dict))

	return front
