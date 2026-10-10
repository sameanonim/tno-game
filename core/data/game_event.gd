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


static func clean_paradox_markup(text: String) -> String:
	if text.is_empty():
		return ""
	var cleaned := text
	if cleaned.contains("§"):
		var color_regex := RegEx.new()
		color_regex.compile("§[A-Za-z0-9!_,\\^\\%\\-\\+=]")
		cleaned = color_regex.sub(cleaned, "", true)
		if cleaned.contains("§"):
			var fallback_regex := RegEx.new()
			fallback_regex.compile("§.")
			cleaned = fallback_regex.sub(cleaned, "", true)
	return cleaned.strip_edges()


static func resolve_localized_string(key_or_text: String, fallback_key: String = "") -> String:
	if key_or_text.is_empty() and fallback_key.is_empty():
		return ""
	
	var candidate: String = key_or_text if not key_or_text.is_empty() else fallback_key
	
	# If candidate contains spaces or cyrillic characters, it is already a human-readable string
	var has_space: bool = candidate.contains(" ") or candidate.contains("\n")
	var is_raw_key: bool = not has_space and (candidate.contains(".") or candidate.begins_with("GFX_") or candidate.begins_with("tno_") or candidate.ends_with(".t") or candidate.ends_with(".d") or candidate.ends_with(".a"))
	
	if Engine.has_singleton("LocalizationManager") or (Engine.get_main_loop() != null and Engine.get_main_loop().root != null and Engine.get_main_loop().root.has_node("/root/LocalizationManager")):
		var lm = Engine.get_main_loop().root.get_node("/root/LocalizationManager")
		if is_raw_key:
			var tr_res: String = lm.tr_key(candidate, {}, "")
			if not tr_res.is_empty() and tr_res != candidate:
				return clean_paradox_markup(tr_res)
		elif candidate.is_empty() and not fallback_key.is_empty():
			var tr_res2: String = lm.tr_key(fallback_key, {}, "")
			if not tr_res2.is_empty() and tr_res2 != fallback_key:
				return clean_paradox_markup(tr_res2)
	
	if is_raw_key:
		var ts_tr: String = TranslationServer.translate(candidate)
		if ts_tr != candidate and not ts_tr.is_empty():
			return clean_paradox_markup(ts_tr)
		if not fallback_key.is_empty() and fallback_key != candidate:
			var ts_fb: String = TranslationServer.translate(fallback_key)
			if ts_fb != fallback_key and not ts_fb.is_empty():
				return clean_paradox_markup(ts_fb)

	return clean_paradox_markup(candidate)


static func from_dict(data: Dictionary) -> GameEvent:
	var ev = GameEvent.new()
	ev.event_id = str(data.get("event_id", data.get("id", "")))
	
	var raw_title: String = str(data.get("title", data.get("name", "")))
	ev.title = resolve_localized_string(raw_title, ev.event_id + ".t")
	if ev.title.is_empty() or ev.title == "UNKNOWN EVENT" or ev.title.ends_with(".t"):
		ev.title = "ДОНЕСЕНИЕ: " + ev.event_id.to_upper().replace(".", " / ")

	var raw_class: String = str(data.get("classification", ""))
	if raw_class.is_empty():
		var parts = ev.event_id.split(".")
		var prefix = parts[0].to_upper() if parts.size() > 0 else "СТАВКА"
		ev.classification = "[ДЕПЕША // %s]" % prefix
	else:
		ev.classification = clean_paradox_markup(raw_class)

	var raw_desc: String = str(data.get("description", data.get("desc", data.get("text", ""))))
	ev.description = resolve_localized_string(raw_desc, ev.event_id + ".d")
	if ev.description.is_empty() or ev.description.ends_with(".d"):
		ev.description = "Внимание: Получены экстренные сводки по обстановке в регионе [%s]. Требуется решение руководства." % ev.event_id

	ev.portrait_path = str(data.get("portrait_path", data.get("picture", data.get("image", ""))))
	ev.is_modal = bool(data.get("is_modal", true))
	ev.fire_only_once = bool(data.get("fire_only_once", true))

	var cond = data.get("trigger_conditions", data.get("trigger", {}))
	if cond is Dictionary:
		ev.trigger_conditions = cond.duplicate(true)

	var raw_options: Variant = data.get("options", data.get("option", []))
	var opts_array: Array = []
	if raw_options is Array:
		opts_array = raw_options
	elif raw_options is Dictionary:
		for k in raw_options.keys():
			if raw_options[k] is Dictionary:
				opts_array.append(raw_options[k])

	var norm_opts: Array = []
	var opt_letters: Array[String] = ["a", "b", "c", "d", "e", "f"]
	for idx in range(opts_array.size()):
		var raw_opt = opts_array[idx]
		if raw_opt is Dictionary:
			var opt_copy: Dictionary = raw_opt.duplicate(true)
			var raw_opt_text: String = str(opt_copy.get("text", opt_copy.get("name", "")))
			var opt_suffix = opt_letters[idx] if idx < opt_letters.size() else str(idx)
			var n_key: String = str(opt_copy.get("name_key", ev.event_id + "." + opt_suffix))
			
			var final_text: String = resolve_localized_string(raw_opt_text, n_key)
			if final_text.is_empty() or final_text == n_key or final_text.ends_with("." + opt_suffix):
				final_text = "ПРИНЯТЬ К СВЕДЕНИЮ" if idx == 0 else "ВАРИАНТ %d" % (idx + 1)
			
			opt_copy["text"] = final_text
			opt_copy["name"] = final_text
			opt_copy["name_key"] = n_key
			norm_opts.append(opt_copy)
		else:
			norm_opts.append(raw_opt)

	# Guaranteed fallback option: Never drop an event with empty options!
	if norm_opts.is_empty():
		norm_opts.append({
			"name": "ПРИНЯТЬ К СВЕДЕНИЮ",
			"text": "ПРИНЯТЬ К СВЕДЕНИЮ",
			"name_key": "OK",
			"effects": {}
		})

	ev.options = norm_opts
	return ev

