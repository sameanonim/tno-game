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

## Детальная оценка доступности варианта выбора и генерация тултипа последствий
static func evaluate_option_availability(option: Dictionary, state: CountryState) -> Dictionary:
	var result: Dictionary = {
		"allowed": true,
		"reasons": [] as Array[String],
		"cost_tooltip": "",
		"effects_tooltip": ""
	}

	if state == null:
		result["allowed"] = false
		return result

	# 1. Проверка очков политического капитала (PC)
	var req_pc: float = float(option.get("required_pc", 0.0))
	if req_pc > 0.0:
		if state.political_capital < req_pc:
			result["allowed"] = false
			result["reasons"].append("Недостаточно PC: требуется %0.1f (в наличии %0.1f)" % [req_pc, state.political_capital])

	# 2. Проверка очков кабинета (CAP)
	var req_cap: int = int(option.get("required_cap", 0))
	if req_cap > 0:
		if state.current_cap < req_cap:
			result["allowed"] = false
			result["reasons"].append("Недостаточно CAP: требуется %d (в наличии %d)" % [req_cap, state.current_cap])

	# 3. Проверка требуемых и заблокированных флагов
	var req_flags: Array = option.get("required_flags", [])
	for f: Variant in req_flags:
		var flag_str: String = str(f)
		if not state.has_flag(flag_str):
			result["allowed"] = false
			result["reasons"].append("Требуется условие: [%s]" % flag_str)

	var blk_flags: Array = option.get("blocked_flags", [])
	for bf: Variant in blk_flags:
		var bflag_str: String = str(bf)
		if state.has_flag(bflag_str):
			result["allowed"] = false
			result["reasons"].append("Блокировано условием: [%s]" % bflag_str)

	# 4. Проверка AST-триггера варианта выбора (TNO Clausewitz trigger block)
	var opt_trigger: Dictionary = option.get("trigger", option.get("trigger_conditions", {}))
	if not opt_trigger.is_empty():
		if not ConditionEvaluator.evaluate(opt_trigger, state):
			result["allowed"] = false
			result["reasons"].append("Геополитическая ситуация исключает данный выбор")

	# 5. Формирование цветного тултипа последствий
	var fx: Dictionary = option.get("effects", {})
	var fx_lines: Array[String] = []

	if req_pc > 0.0:
		fx_lines.append("[color=#ff7777]Стоимость: -%0.1f PC[/color]" % req_pc)
	if req_cap > 0:
		fx_lines.append("[color=#ff7777]Стоимость: -%d CAP[/color]" % req_cap)

	if fx.has("MOD_PC") or fx.has("modify_pc") or fx.has("add_political_power"):
		var p_val: float = float(fx.get("MOD_PC", fx.get("modify_pc", fx.get("add_political_power", 0.0))))
		var col_p: String = "#44ff88" if p_val >= 0 else "#ff5555"
		fx_lines.append("[color=%s]Политический капитал: %+0.1f[/color]" % [col_p, p_val])

	if fx.has("MOD_STABILITY") or fx.has("modify_stability") or fx.has("add_stability"):
		var s_val: float = float(fx.get("MOD_STABILITY", fx.get("modify_stability", fx.get("add_stability", 0.0))))
		var s_pct: float = s_val * 50.0 if absf(s_val) <= 1.0 else s_val
		var col_s: String = "#44ff88" if s_pct >= 0 else "#ff5555"
		fx_lines.append("[color=%s]Стабильность / Легитимность: %+0.1f%%[/color]" % [col_s, s_pct])

	if fx.has("MOD_GDP") or fx.has("modify_gdp"):
		var g_val: float = float(fx.get("MOD_GDP", fx.get("modify_gdp", 0.0)))
		var col_g: String = "#44ff88" if g_val >= 0 else "#ff5555"
		fx_lines.append("[color=%s]ВВП: %+0.2f млрд $[/color]" % [col_g, g_val])

	if fx.has("MOD_WAR_SUPPORT") or fx.has("modify_war_support") or fx.has("add_war_support"):
		var ws_val: float = float(fx.get("MOD_WAR_SUPPORT", fx.get("modify_war_support", fx.get("add_war_support", 0.0))))
		var col_ws: String = "#44ff88" if ws_val >= 0 else "#ff5555"
		fx_lines.append("[color=%s]Военная поддержка: %+0.1f%%[/color]" % [col_ws, ws_val])

	if fx.has("MOD_MANPOWER") or fx.has("modify_manpower") or fx.has("add_manpower"):
		var mp_val: int = int(fx.get("MOD_MANPOWER", fx.get("modify_manpower", fx.get("add_manpower", 0))))
		var col_mp: String = "#44ff88" if mp_val >= 0 else "#ff5555"
		fx_lines.append("[color=%s]Людские ресурсы: %+d чел.[/color]" % [col_mp, mp_val])

	if fx.has("MOD_WEAPONS") or fx.has("modify_weapons"):
		var wp_val: int = int(fx.get("MOD_WEAPONS", fx.get("modify_weapons", 0)))
		var col_wp: String = "#44ff88" if wp_val >= 0 else "#ff5555"
		fx_lines.append("[color=%s]Склады вооружения: %+d ед.[/color]" % [col_wp, wp_val])

	if not result["allowed"]:
		if not fx_lines.is_empty():
			fx_lines.append("")
		fx_lines.append("[color=#ff4444]НЕДОСТУПНО:[/color]")
		for r: String in result["reasons"]:
			fx_lines.append("[color=#ff8888]• %s[/color]" % r)

	result["effects_tooltip"] = "\n".join(fx_lines)
	return result


## Helper method to check if player meets requirements for a given option
static func can_select_option(option: Dictionary, state: CountryState) -> bool:
	return evaluate_option_availability(option, state)["allowed"]



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
	ev.event_id = str(data.get("event_id", data.get("id", "")))
	ev.title = str(data.get("title", data.get("name", "UNKNOWN EVENT")))
	ev.classification = str(data.get("classification", "[TOP SECRET]"))
	ev.description = str(data.get("description", data.get("desc", data.get("text", ""))))
	ev.portrait_path = str(data.get("portrait_path", data.get("picture", data.get("image", ""))))
	ev.is_modal = bool(data.get("is_modal", true))
	ev.fire_only_once = bool(data.get("fire_only_once", true))

	var cond = data.get("trigger_conditions", data.get("trigger", {}))
	if cond is Dictionary:
		ev.trigger_conditions = cond.duplicate(true)

	var opts = data.get("options", [])
	if opts is Array:
		var norm_opts: Array = []
		for raw_opt in opts:
			if raw_opt is Dictionary:
				var opt_copy: Dictionary = raw_opt.duplicate(true)
				var opt_txt: String = str(opt_copy.get("text", opt_copy.get("name", "")))
				opt_copy["text"] = opt_txt
				opt_copy["name"] = opt_txt
				norm_opts.append(opt_copy)
			else:
				norm_opts.append(raw_opt)
		ev.options = norm_opts

	return ev
