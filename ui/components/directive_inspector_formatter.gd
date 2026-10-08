class_name DirectiveInspectorFormatter
extends Node

##
## DirectiveInspectorFormatter: Форматирование тактического инспектора и досье директивы
## ==============================================================================
## Отвечает за:
## 1. Форматирование описания, оперативных затрат (CAP, PC, бюджет, ходы).
## 2. Форматирование условий/пререквизитов с оценкой AST (ConditionEvaluator) и подсветкой статуса.
## 3. Форматирование опкодов наград (MOD_PC, MOD_STABILITY, MOD_WAR_SUPPORT, SET_FLAG, etc.).
## 4. Определение доступности и статуса кнопки старта директивы.
## ==============================================================================


"""Обновляет все контролы панели инспектора директивы.
"""
static func update_inspector(
	dir: DirectiveResource,
	all_directives: Dictionary,
	player_state: CountryState,
	turn_manager: TurnManager,
	focus_stage_controller: FocusStageController,
	lbl_insp_title: Label,
	lbl_insp_desc: RichTextLabel,
	lbl_insp_cost: Label,
	lbl_insp_reqs: RichTextLabel,
	lbl_insp_effects: RichTextLabel,
	btn_insp_start: Button,
	formatted_title: String
) -> void:
	if dir == null:
		return

	if lbl_insp_title != null:
		lbl_insp_title.text = "%s %s" % [dir.icon_symbol, formatted_title.to_upper()]
	if lbl_insp_desc != null:
		lbl_insp_desc.text = "[color=#b0d0c0]%s[/color]" % (dir.description if not dir.description.is_empty() else "Описание директивы засекречено или отсутствует.")

	if lbl_insp_cost != null:
		var cost_txt := "ОПЕРАТИВНЫЕ ЗАТРАТЫ:\n"
		cost_txt += "• Очки кабинета (CAP): %d\n" % dir.cost_initial_cap
		cost_txt += "• Политический капитал (PC): %0.1f\n" % dir.cost_initial_pc
		cost_txt += "• Финансирование за ход: $%0.2f B\n" % dir.cost_per_turn
		cost_txt += "• Расчетный срок реализации: %d ходов" % dir.turns_to_complete
		lbl_insp_cost.text = cost_txt

	# 1. Требования, пререквизиты и статус ветки
	var req_txt := ""
	if not dir.prerequisites_groups.is_empty():
		req_txt += "[b]ПРЕРЕКВИЗИТЫ (И/ИЛИ):[/b]\n"
		for grp in dir.prerequisites_groups:
			if grp is Array:
				var grp_ok := false
				var titles: Array[String] = []
				for pid in grp:
					var p_title = all_directives[pid].title if all_directives.has(pid) else str(pid)
					titles.append(p_title)
					if player_state != null and player_state.completed_directives.has(str(pid)):
						grp_ok = true
				var col = "#33ff66" if grp_ok else "#ff5555"
				var mark = "✓" if grp_ok else "✖"
				req_txt += "• [color=%s]%s Требуется: %s[/color]\n" % [col, mark, " ИЛИ ".join(titles)]
	elif not dir.prerequisites.is_empty():
		req_txt += "[b]ПРЕРЕКВИЗИТЫ:[/b]\n"
		for pid in dir.prerequisites:
			var ok = player_state != null and player_state.completed_directives.has(str(pid))
			var col = "#33ff66" if ok else "#ff5555"
			var mark = "✓" if ok else "✖"
			var p_title = all_directives[pid].title if all_directives.has(pid) else str(pid)
			req_txt += "• [color=%s]%s %s[/color]\n" % [col, mark, p_title]

	if not dir.mutually_exclusive.is_empty():
		req_txt += "[b]ВЗАИМОИСКЛЮЧЕНИЯ:[/b]\n"
		for excl_id in dir.mutually_exclusive:
			var excl_title = all_directives[excl_id].title if all_directives.has(excl_id) else str(excl_id)
			var is_locked = player_state != null and (player_state.completed_directives.has(str(excl_id)) or player_state.active_directives.has(str(excl_id)) or player_state.has_flag("locked_focus_" + str(excl_id)))
			if is_locked:
				req_txt += "• [color=#ff5555]✖ Заблокировано: [%s] уже выбран[/color]\n" % excl_title
			else:
				req_txt += "• [color=#ffaa00]⚠ Исключает проект: [%s][/color]\n" % excl_title

	if not dir.available_ast.is_empty() and player_state != null:
		req_txt += "[b]ТРЕБОВАНИЯ ОБСТАНОВКИ:[/b]\n"
		var explained = ConditionEvaluator.explain(dir.available_ast, player_state)
		for cond_info in explained:
			var col = "#33ff66" if cond_info["passed"] else "#ff5555"
			var mark = "✓" if cond_info["passed"] else "✖"
			var indent = "  ".repeat(cond_info["depth"])
			req_txt += "• %s[color=%s]%s %s[/color]\n" % [indent, col, mark, cond_info["text"]]

	if not dir.bypass_ast.is_empty() and player_state != null:
		var bp_ok = dir.should_bypass(player_state)
		var col = "#00e5ff" if bp_ok else "#668877"
		req_txt += "[b]АВТОПРОПУСК (BYPASS):[/b] [color=%s]%s[/color]\n" % [col, ("АКТИВЕН (будет пропущен)" if bp_ok else "Не выполнен")]

	if req_txt.is_empty():
		req_txt = "[color=#33ff66]✓ Базовая директива. Особых предварительных условий нет.[/color]"
	if lbl_insp_reqs != null:
		lbl_insp_reqs.text = req_txt

	# 2. Вывод опкодов наград
	var eff_txt := ""
	for rew in dir.completion_rewards:
		var op = str(rew.get("opcode", ""))
		match op:
			"MOD_PC":
				var v = float(rew.get("value", 0))
				var sgn = "+" if v >= 0 else ""
				eff_txt += "• [color=#44d990][b][★] ПОЛИТИЧЕСКИЙ КАПИТАЛ:[/b] %s%0.1f PC[/color]\n" % [sgn, v]
			"MOD_STABILITY":
				var v = float(rew.get("value", 0))
				var sgn = "+" if v >= 0 else ""
				eff_txt += "• [color=#44d990][b][✦] СТАБИЛЬНОСТЬ:[/b] %s%0.1f%%[/color]\n" % [sgn, v * 100.0]
			"MOD_WAR_SUPPORT":
				var v = float(rew.get("value", 0))
				var sgn = "+" if v >= 0 else ""
				eff_txt += "• [color=#ffcc33][b][⚔] ВОЕННАЯ ПОДДЕРЖКА:[/b] %s%0.1f%%[/color]\n" % [sgn, v]
			"SET_FLAG":
				eff_txt += "• [color=#8caebd][b][⚑] СЮЖЕТНЫЙ ФЛАГ:[/b] %s[/color]\n" % str(rew.get("flag", ""))
			"FIRE_EVENT":
				eff_txt += "• [color=#ff594d][b][⚡] ИНИЦИАЦИЯ СОБЫТИЯ:[/b] %s[/color]\n" % str(rew.get("event_id", ""))
			"MOD_MANPOWER":
				var v = int(rew.get("value", 0))
				var sgn = "+" if v >= 0 else ""
				eff_txt += "• [color=#00e5ff][b][👥] ЛЮДСКИЕ РЕСУРСЫ:[/b] %s%d чел.[/color]\n" % [sgn, v]
			"TRANSFER_STATE":
				eff_txt += "• [color=#00e5ff][b][🗺] ПЕРЕДАЧА СЕКТОРА:[/b] регион #%d[/color]\n" % int(rew.get("state_id", 0))
			_:
				eff_txt += "• [color=#00e5ff][b]%s:[/b][/color] %s\n" % [op, str(rew)]

	# Legacy эффекты
	for k in dir.completion_effects.keys():
		eff_txt += "• %s: %s\n" % [k, str(dir.completion_effects[k])]

	if eff_txt.is_empty():
		eff_txt = "[color=#668877]Прямых численных эффектов не предусмотрено (нарративный прогресс).[/color]"
	if lbl_insp_effects != null:
		lbl_insp_effects.text = eff_txt

	# 3. Кнопка запуска
	if btn_insp_start == null:
		return

	var is_completed = (player_state != null and player_state.completed_directives.has(dir.id)) \
		or (focus_stage_controller != null and focus_stage_controller.completed_directive_ids.has(dir.id)) \
		or dir.status == DirectiveResource.Status.COMPLETED
	var is_active = (turn_manager != null and "active_directive" in turn_manager and turn_manager.active_directive != null and turn_manager.active_directive.id == dir.id) \
		or (player_state != null and player_state.active_directives.has(dir.id)) \
		or dir.status == DirectiveResource.Status.IN_PROGRESS
	var dossier = dir.can_be_started(player_state) if player_state != null else {"allowed": false, "reason": ""}
	var can_start = dossier.get("allowed", false)

	# Проверка на взаимную блокировку
	var is_mutually_locked := false
	if player_state != null:
		if player_state.has_flag("locked_focus_" + dir.id) or player_state.has_flag("mutually_locked_" + dir.id):
			is_mutually_locked = true
		for excl_id in dir.mutually_exclusive:
			if player_state.completed_directives.has(excl_id) or player_state.active_directives.has(excl_id) or player_state.has_flag("locked_focus_" + excl_id):
				is_mutually_locked = true
				break

	if is_completed:
		btn_insp_start.text = TranslationServer.translate("[ ПРОЕКТ УЖЕ ВЫПОЛНЕН ]")
		btn_insp_start.disabled = true
	elif is_active:
		btn_insp_start.text = TranslationServer.translate("[ ДИРЕКТИВА В РАБОТЕ ]")
		btn_insp_start.disabled = true
	elif is_mutually_locked:
		btn_insp_start.text = TranslationServer.translate("[ ЗАБЛОКИРОВАНО ВЫБОРОМ ]")
		btn_insp_start.disabled = true
	elif can_start:
		btn_insp_start.text = TranslationServer.translate("[ УТВЕРДИТЬ ДИРЕКТИВУ ]")
		btn_insp_start.disabled = false
	else:
		btn_insp_start.text = TranslationServer.translate("[ УСЛОВИЯ НЕ ВЫПОЛНЕНЫ ]")
		btn_insp_start.disabled = true
