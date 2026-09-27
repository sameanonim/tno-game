class_name GameEvent
extends Resource

##
## GameEvent: Нарративное событие, политический кризис или сводка новостей
##

@export var event_id: String = "tno_event_default"
@export var title: String = "DEFENSE COUNCIL CONVENED"
@export var classification: String = "[EYES ONLY // PREKAS No. 042-B]"
@export_multiline var description: String = "Reports from the frontline indicate..."
@export var portrait_path: String = ""
@export var is_modal: bool = true # If true, pauses turn resolution until an option is chosen
@export var fire_only_once: bool = true

## Dictionary of trigger criteria: flags, stability_min, stability_max, gdp_min, etc.
@export var trigger_conditions: Dictionary = {}

## List of choices available to the player
@export var options: Array = []

## Helper method to check if player meets requirements for a given option
static func can_select_option(option: Dictionary, state: CountryState) -> bool:
	var req_pc = option.get("required_pc", 0.0)
	if state.political_capital < req_pc:
		return false

	var req_cap = option.get("required_cap", 0)
	if state.current_cap < req_cap:
		return false

	var req_flags = option.get("required_flags", [])
	for flag in req_flags:
		if not state.has_flag(flag):
			return false

	return true


func to_dict() -> Dictionary:
	return {
		"event_id": event_id,
		"title": title,
		"classification": classification,
		"description": description,
		"portrait_path": portrait_path,
		"is_modal": is_modal,
		"fire_only_once": fire_only_once,
		"trigger_conditions": trigger_conditions.duplicate(true),
		"options": options.duplicate(true)
	}


static func from_dict(data: Dictionary) -> GameEvent:
	var ev = GameEvent.new()
	ev.event_id = str(data.get("event_id", ""))
	ev.title = str(data.get("title", "UNKNOWN EVENT"))
	ev.classification = str(data.get("classification", "[TOP SECRET]"))
	ev.description = str(data.get("description", ""))
	ev.portrait_path = str(data.get("portrait_path", ""))
	ev.is_modal = bool(data.get("is_modal", true))
	ev.fire_only_once = bool(data.get("fire_only_once", true))
	
	var cond = data.get("trigger_conditions", {})
	if cond is Dictionary:
		ev.trigger_conditions = cond.duplicate(true)
	
	var opts = data.get("options", [])
	if opts is Array:
		ev.options = opts.duplicate(true)
	
	return ev
