class_name DirectiveResource
extends Resource

##
## DirectiveResource: Пошаговая национальная инициатива / проект развития (вместо древ фокусов HoI4)
##
## Представляет узел направленного графа директив (DAG), управляемый пошаговым циклом TurnManager.
## Поддерживает:
## - Группы пререквизитов: логическое И между группами, логическое ИЛИ внутри группы
## - Двусторонние взаимоисключающие связи (mutually_exclusive)
## - Дерево условий (AST) произвольной сложности для доступности (available_ast) и автопропуска (bypass_ast)
## - Автоматический пропуск (bypass) и срыв выполнения при нарушении условий (cancel_if_invalid)
##

enum Status {
	LOCKED,
	AVAILABLE,
	IN_PROGRESS,
	COMPLETED,
	MUTUALLY_BLOCKED,
	HIDDEN,
	CANCELLED
}

# ==============================================================================
# ИДЕНТИФИКАЦИЯ И ОПИСАНИЕ
# ==============================================================================
@export var id: String = "directive_default"
@export var title: String = "Национальная инициатива"
@export var category: String = "doctrine" # economy, military, politics, intelligence, doctrine
@export_multiline var description: String = ""
@export var icon_symbol: String = "[★]"
@export var icon_path: String = "res://icon.svg"
@export var icon: Texture2D = null

## Ленивое получение и кэширование иконки директивы
func get_icon() -> Texture2D:
	if icon != null:
		if icon.resource_path != "" and (icon_path.is_empty() or icon_path == "res://icon.svg"):
			icon_path = icon.resource_path
		return icon
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		icon = load(icon_path)
	return icon

# ==============================================================================
# СЕТКА И СТОИМОСТЬ
# ==============================================================================
@export var grid_position: Vector2 = Vector2.ZERO
@export var turns_to_complete: int = 4
@export var turns_remaining: int = 4
@export var cost_per_turn: float = 0.05
@export var cost_initial_cap: int = 1
@export var cost_initial_pc: float = 10.0

# ==============================================================================
# СВЯЗИ И ОГРАНИЧЕНИЯ ГРАФА
# ==============================================================================
## Плоский список пререквизитов (для совместимости)
@export var prerequisites: Array = []

## Группы пререквизитов: Внешний массив = логическое «И» (AND), Внутренний массив = логическое «ИЛИ» (OR).
## Пример: [["A", "B"], ["C"]] означает: (A ИЛИ B) И C.
@export var prerequisites_groups: Array = []

## Список взаимоисключающих директив
@export var mutually_exclusive: Array = []

@export var status: Status = Status.LOCKED
@export var cancel_if_invalid: bool = true

# ==============================================================================
# СЛОЖНЫЕ ЛОГИЧЕСКИЕ ДЕРЕВЬЯ (AST)
# ==============================================================================
## Рекурсивное дерево условий доступности директивы
@export var available_ast: Dictionary = {}

## Рекурсивное дерево условий автопропуска (bypass)
@export var bypass_ast: Dictionary = {}

## Рекурсивное дерево условий отображения и активности ветки (allow_branch)
@export var allow_branch_ast: Dictionary = {}

## Награды и эффекты директивы
@export var available_triggers: Array = []
@export var completion_rewards: Array = []
@export var completion_effects: Dictionary = {}
@export var bypass_rewards: Array = []

# Псевдонимы совместимости со старым кодом
var directive_id: String:
	get: return id
	set(val): id = val

var turns_required: int:
	get: return turns_to_complete
	set(val): turns_to_complete = val

var cost_money_per_turn_billions: float:
	get: return cost_per_turn
	set(val): cost_per_turn = val

var mutually_exclusive_with: Array[String]:
	get: return mutually_exclusive
	set(val): mutually_exclusive = val


# ==============================================================================
# ПРОВЕРКА УСЛОВИЙ ЗАПУСКА ДИРЕКТИВЫ (CAN BE STARTED)
# ==============================================================================

func _tr_str(key: String, params: Dictionary = {}, fallback: String = "") -> String:
	var main_loop = Engine.get_main_loop()
	if main_loop is SceneTree and main_loop.root != null and main_loop.root.has_node("LocalizationManager"):
		var loc = main_loop.root.get_node("LocalizationManager")
		if loc != null and loc.has_method("tr_key"):
			return loc.tr_key(key, params, fallback)
	var s = TranslationServer.translate(key)
	if s.is_empty() or s == key:
		s = fallback
	for k in params:
		s = s.replace("{%s}" % str(k), str(params[k]))
	return s



## Комплексная проверка готовности директивы к запуску с возвратом причины отказа
func can_be_started(state: CountryState, completed_directives: Array = []) -> Dictionary:
	if state == null:
		return {"allowed": false, "reason": _tr_str("DIR_ERR_NO_STATE", {}, "Государство не инициализировано."), "failed_conditions": ["NO_STATE"]}

	var completed_list: Array = state.completed_directives.duplicate()
	for c in completed_directives:
		if not completed_list.has(str(c)):
			completed_list.append(str(c))
	var hist = state.story_flags.get("completed_historical_focuses", [])
	if hist is Array:
		for h in hist:
			var s_h = str(h)
			if not completed_list.has(s_h):
				completed_list.append(s_h)
	var arch = state.story_flags.get("completed_directives_archive", [])
	if arch is Array:
		for a in arch:
			var s_a = str(a)
			if not completed_list.has(s_a):
				completed_list.append(s_a)

	# 1. Проверка уже запущенных и завершенных директив
	if state.active_directives.has(id):
		return {"allowed": false, "reason": _tr_str("DIR_ERR_ALREADY_ACTIVE", {}, "Директива уже находится в процессе реализации."), "failed_conditions": ["ALREADY_ACTIVE"]}
	if completed_list.has(id):
		return {"allowed": false, "reason": _tr_str("DIR_ERR_ALREADY_COMPLETED", {}, "Директива уже успешно выполнена."), "failed_conditions": ["ALREADY_COMPLETED"]}

	# 1.1. Проверка доступности ветки (allow_branch)
	if not is_branch_allowed(state):
		return {
			"allowed": false,
			"reason": _tr_str("DIR_ERR_BRANCH_DISALLOWED", {}, "Ветка директив недоступна при текущей политической обстановке (allow_branch)."),
			"failed_conditions": ["BRANCH_DISALLOWED"]
		}

	# 2. Проверка тактических ресурсов (CAP) и политического капитала (PC)
	if state.current_cap < cost_initial_cap:
		return {
			"allowed": false,
			"reason": _tr_str("DIR_ERR_INSUFFICIENT_CAP", {"req": cost_initial_cap, "cur": state.current_cap}, "Недостаточно Очков Действий Кабинета (CAP): требуется %d, в наличии %d." % [cost_initial_cap, state.current_cap]),
			"failed_conditions": ["INSUFFICIENT_CAP"]
		}
	if state.political_capital < cost_initial_pc:
		return {
			"allowed": false,
			"reason": _tr_str("DIR_ERR_INSUFFICIENT_PC", {"req": "%0.1f" % cost_initial_pc, "cur": "%0.1f" % state.political_capital}, "Недостаточно Политического Капитала (PC): требуется %0.1f, в наличии %0.1f." % [cost_initial_pc, state.political_capital]),
			"failed_conditions": ["INSUFFICIENT_PC"]
		}

	# 3. Проверка взаимоисключающих директив
	if state.has_flag("locked_focus_" + id) or state.has_flag("mutually_locked_" + id):
		return {
			"allowed": false,
			"reason": _tr_str("DIR_ERR_MUTUALLY_LOCKED", {"id": id}, "Директива заблокирована политическим решением руководства страны: %s" % id),
			"failed_conditions": ["MUTUALLY_LOCKED"]
		}

	for excl_id in mutually_exclusive:
		if completed_list.has(excl_id):
			return {
				"allowed": false,
				"reason": _tr_str("DIR_INTERRUPTED_MUTUAL", {"title": excl_id}, "Ветка заблокирована: ранее был выбран и завершен взаимоисключающий проект [%s]." % excl_id),
				"failed_conditions": ["MUTUALLY_EXCLUSIVE_COMPLETED:" + excl_id]
			}

	# 4. Проверка групп пререквизитов (AND между группами, OR внутри группы)
	var failed_prereqs: Array[String] = []
	if not prerequisites_groups.is_empty():
		for group in prerequisites_groups:
			if group is Array:
				var group_satisfied := false
				for req_id in group:
					if completed_list.has(str(req_id)):
						group_satisfied = true
						break
				if not group_satisfied:
					failed_prereqs.append("(%s)" % ", ".join(group))
	elif not prerequisites.is_empty():
		# Запасная проверка для плоского списка
		for req_id in prerequisites:
			if not completed_list.has(str(req_id)):
				failed_prereqs.append(str(req_id))

	if not failed_prereqs.is_empty():
		return {
			"allowed": false,
			"reason": "Не выполнены предшествующие директивы: %s." % ", ".join(failed_prereqs),
			"failed_conditions": failed_prereqs
		}

	# 5. Проверка динамического AST-дерева условий (available_ast)
	if not available_ast.is_empty():
		if not ConditionEvaluator.evaluate(available_ast, state):
			return {
				"allowed": false,
				"reason": "Не соблюдены стратегические требования директивы (политическая обстановка).",
				"failed_conditions": ["AVAILABLE_AST_FAILED"]
			}
	elif not available_triggers.is_empty():
		# Запасная проверка через устаревшие опкоды
		for trg in available_triggers:
			if not _evaluate_legacy_trigger(trg, state):
				return {
					"allowed": false,
					"reason": "Не соблюдены условия инициативы: %s." % str(trg),
					"failed_conditions": ["TRIGGER_FAILED:" + str(trg.get("opcode", ""))]
				}

	return {
		"allowed": true,
		"reason": "Все условия соблюдены. Директива готова к утверждению.",
		"failed_conditions": []
	}


## Обратная совместимость для can_start
func can_start(state: CountryState) -> bool:
	return can_be_started(state)["allowed"]


## Оценивает доступность директивы с учетом истории выполненных директив и текущего состояния государства
func evaluate_availability(state: CountryState, completed_history: Array = []) -> Dictionary:
	return can_be_started(state, completed_history)


## Проверяет выполнимость условий автопропуска (bypass_ast)
func check_bypass(state: CountryState) -> bool:
	return should_bypass(state)


## Проверяет условия отображения и валидности ветки (allow_branch_ast)
func check_allow_branch(state: CountryState) -> bool:
	return is_branch_allowed(state)


# ==============================================================================
# АВТОПРОПУСК (BYPASS) И ВАЛИДАЦИЯ (CANCEL IF INVALID)
# ==============================================================================

## Проверяет, должна ли директива быть автоматически пропущена (bypassed) без затраты ходов
func should_bypass(state: CountryState) -> bool:
	if state == null or bypass_ast.is_empty():
		return false
	return ConditionEvaluator.evaluate(bypass_ast, state)


## Проверяет, сохраняет ли выполняемая директива валидность условий
func is_still_valid(state: CountryState) -> bool:
	if not cancel_if_invalid:
		return true
	if not is_branch_allowed(state):
		return false
	if available_ast.is_empty():
		return true
	return ConditionEvaluator.evaluate(available_ast, state)


## Проверяет, разрешена ли ветка директивы по условиям allow_branch
func is_branch_allowed(state: CountryState) -> bool:
	if state == null or allow_branch_ast.is_empty():
		return true
	return ConditionEvaluator.evaluate(allow_branch_ast, state)


# ==============================================================================
# УСТАРЕВШАЯ ОЦЕНКА ОПКОДОВ (ДЛЯ ОБРАТНОЙ СОВМЕСТИМОСТИ)
# ==============================================================================
func _evaluate_legacy_trigger(trg: Dictionary, state: CountryState) -> bool:
	var op = str(trg.get("opcode", ""))
	match op:
		"HAS_FLAG":
			return state.has_flag(str(trg.get("flag", "")))
		"HAS_GLOBAL_FLAG":
			return state.has_flag(str(trg.get("flag", "")))
		"IS_TAG":
			return state.country_tag.to_upper() == str(trg.get("tag", "")).to_upper()
		"IS_AI":
			return false == bool(trg.get("value", false))
		"HAS_WAR":
			var is_at_war = state.has_flag("at_war") or state.story_flags.get("has_war", false)
			return is_at_war == bool(trg.get("value", true))
		"CHECK_STABILITY":
			return ConditionEvaluator._compare(state.get_stability_index(), str(trg.get("operator", ">=")), float(trg.get("value", 0.0)))
		"CHECK_PC":
			return ConditionEvaluator._compare(state.political_capital, str(trg.get("operator", ">=")), float(trg.get("value", 0.0)))
		"CONTROLS_STATE", "OWNS_STATE":
			var sid = int(trg.get("state_id", trg.get("state", 0)))
			return state.controlled_states.has(sid) or state.owned_states.has(sid) or state.has_flag("controls_state_%d" % sid)
		"THREAT", "CHECK_TENSION":
			var op_t = str(trg.get("operator", ">="))
			var tension = float(state.story_flags.get("world_tension", state.story_flags.get("defcon_tension", 25.0)))
			return ConditionEvaluator._compare(tension, op_t, float(trg.get("value", 0.0)))
		"HAS_IDEA":
			var idea_id = str(trg.get("idea_id", trg.get("idea", trg.get("target", trg.get("id", trg.get("value", ""))))))
			if state.has_method("has_idea"):
				return state.has_idea(idea_id)
			var has_law = state.has_active_law(idea_id) if state.has_method("has_active_law") else false
			var has_spirit = state.has_national_spirit(idea_id) if state.has_method("has_national_spirit") else false
			return state.has_flag("idea_" + idea_id) or state.has_flag(idea_id) or has_law or has_spirit
		"CHECK_DATE":
			var op_d = str(trg.get("operator", ">="))
			return ConditionEvaluator._compare(float(state.turn_count), op_d, float(trg.get("turn", trg.get("value", 1))))
		_:
			return true


# ==============================================================================
# СЕРИАЛИЗАЦИЯ И ДЕСЕРИАЛИЗАЦИЯ
# ==============================================================================
func to_dict() -> Dictionary:
	var rew_list: Array[Dictionary] = []
	for r in completion_rewards:
		rew_list.append(r.duplicate(true))

	var trg_list: Array[Dictionary] = []
	for t in available_triggers:
		trg_list.append(t.duplicate(true))

	var effective_icon_path: String = icon_path
	if (effective_icon_path.is_empty() or effective_icon_path == "res://icon.svg") and icon != null and not icon.resource_path.is_empty():
		effective_icon_path = icon.resource_path

	return {
		"id": id,
		"directive_id": id,
		"title": title,
		"description": description,
		"category": category,
		"icon_symbol": icon_symbol,
		"icon_path": effective_icon_path,
		"grid_position": [grid_position.x, grid_position.y],
		"turns_to_complete": turns_to_complete,
		"turns_remaining": turns_remaining,
		"turns_required": turns_to_complete,
		"cost_per_turn": cost_per_turn,
		"cost_money_per_turn_billions": cost_per_turn,
		"cost_initial_cap": cost_initial_cap,
		"cost_initial_pc": cost_initial_pc,
		"prerequisites": prerequisites.duplicate(),
		"prerequisites_groups": prerequisites_groups.duplicate(true),
		"mutually_exclusive": mutually_exclusive.duplicate(),
		"mutually_exclusive_with": mutually_exclusive.duplicate(),
		"available_ast": available_ast.duplicate(true),
		"bypass_ast": bypass_ast.duplicate(true),
		"allow_branch_ast": allow_branch_ast.duplicate(true),
		"cancel_if_invalid": cancel_if_invalid,
		"available_triggers": trg_list,
		"completion_rewards": rew_list,
		"completion_effects": completion_effects.duplicate(true),
		"bypass_rewards": bypass_rewards.duplicate(true),
		"status": int(status)
	}


static func from_dict(data: Dictionary) -> DirectiveResource:
	var res = DirectiveResource.new()

	# Идентификатор
	if data.has("id"):
		res.id = str(data["id"])
	elif data.has("directive_id"):
		res.id = str(data["directive_id"])

	# Название директивы: поддержка HoI4/Clausewitz полей ("name", "name_text", "title")
	if data.has("title") and not str(data["title"]).is_empty():
		res.title = str(data["title"])
	elif data.has("name") and not str(data["name"]).is_empty():
		res.title = str(data["name"])
	elif data.has("name_text") and not str(data["name_text"]).is_empty():
		res.title = str(data["name_text"])
	else:
		res.title = res.id

	# Описание директивы: поддержка HoI4/Clausewitz "desc"
	if data.has("description") and not str(data["description"]).is_empty():
		res.description = str(data["description"])
	elif data.has("desc") and not str(data["desc"]).is_empty():
		res.description = str(data["desc"])
	elif data.has("desc_text") and not str(data["desc_text"]).is_empty():
		res.description = str(data["desc_text"])
	else:
		res.description = ""

	res.category = str(data.get("category", "doctrine"))
	res.icon_symbol = str(data.get("icon_symbol", "[★]"))

	# Иконка фокуса
	if data.has("icon_path"):
		res.icon_path = str(data["icon_path"])
	elif data.has("icon") and data["icon"] is String:
		res.icon_path = str(data["icon"])
	else:
		res.icon_path = "res://icon.svg"

	if not res.icon_path.is_empty() and ResourceLoader.exists(res.icon_path):
		res.icon = load(res.icon_path) as Texture2D

	# Координаты сетки: поддержка HoI4 "x" и "y"
	if data.has("x") and data.has("y"):
		res.grid_position = Vector2(float(data["x"]), float(data["y"]))
	else:
		var gp = data.get("grid_position", [0.0, 0.0])
		if gp is Array and gp.size() >= 2:
			res.grid_position = Vector2(float(gp[0]), float(gp[1]))
		elif gp is Vector2:
			res.grid_position = gp
		elif gp is Vector2i:
			res.grid_position = Vector2(gp.x, gp.y)

	# Сроки выполнения: поддержка HoI4 "cost_turns"
	if data.has("cost_turns"):
		res.turns_to_complete = maxi(1, int(data["cost_turns"]))
	elif data.has("turns_to_complete"):
		res.turns_to_complete = maxi(1, int(data["turns_to_complete"]))
	elif data.has("turns_required"):
		res.turns_to_complete = maxi(1, int(data["turns_required"]))
	else:
		res.turns_to_complete = 4

	res.turns_remaining = int(data.get("turns_remaining", res.turns_to_complete))

	if data.has("cost_per_turn"):
		res.cost_per_turn = float(data["cost_per_turn"])
	elif data.has("cost_money_per_turn_billions"):
		res.cost_per_turn = float(data["cost_money_per_turn_billions"])
	else:
		res.cost_per_turn = 0.05

	res.cost_initial_cap = int(data.get("cost_initial_cap", 1))
	res.cost_initial_pc = float(data.get("cost_initial_pc", 10.0))

	# Связи пререквизитов
	res.prerequisites.clear()
	var raw_prereqs = data.get("prerequisites", data.get("prerequisite", []))
	if raw_prereqs is Array:
		for p in raw_prereqs:
			if p is String:
				res.prerequisites.append(str(p))
			elif p is Dictionary and p.has("focus"):
				res.prerequisites.append(str(p["focus"]))

	res.prerequisites_groups.clear()
	if data.has("prerequisites_groups") and data["prerequisites_groups"] is Array:
		for g in data["prerequisites_groups"]:
			if g is Array:
				var grp_arr: Array[String] = []
				for elem in g:
					grp_arr.append(str(elem))
				res.prerequisites_groups.append(grp_arr)
	elif not res.prerequisites.is_empty():
		for p in res.prerequisites:
			res.prerequisites_groups.append([p])

	# Взаимоисключения
	res.mutually_exclusive.clear()
	var raw_excl = data.get("mutually_exclusive", data.get("mutually_exclusive_with", []))
	if raw_excl is Array:
		for m in raw_excl:
			if m is String:
				res.mutually_exclusive.append(str(m))
			elif m is Dictionary and m.has("focus"):
				res.mutually_exclusive.append(str(m["focus"]))

	# AST логика
	res.available_ast = data.get("available_ast", {}).duplicate(true)
	res.bypass_ast = data.get("bypass_ast", {}).duplicate(true)
	res.allow_branch_ast = data.get("allow_branch_ast", {}).duplicate(true)
	res.cancel_if_invalid = bool(data.get("cancel_if_invalid", true))

	# Опкоды
	res.available_triggers.clear()
	for trg in data.get("available_triggers", []):
		if trg is Dictionary:
			res.available_triggers.append(trg.duplicate(true))

	res.completion_rewards.clear()
	for rew in data.get("completion_rewards", []):
		if rew is Dictionary:
			res.completion_rewards.append(rew.duplicate(true))

	# Парсинг HoI4 Clausewitz completion_reward (Dictionary)
	if data.has("completion_reward") and data["completion_reward"] is Dictionary:
		var raw_cr: Dictionary = data["completion_reward"]
		_parse_hoi4_completion_reward(raw_cr, res)

	res.completion_effects = data.get("completion_effects", {}).duplicate(true)

	res.bypass_rewards.clear()
	for brew in data.get("bypass_rewards", []):
		if brew is Dictionary:
			res.bypass_rewards.append(brew.duplicate(true))

	if data.has("status"):
		res.status = int(data["status"]) as Status

	# Ленивая предзагрузка текстуры
	if not res.icon_path.is_empty() and ResourceLoader.exists(res.icon_path):
		res.icon = load(res.icon_path)

	return res


## Парсинг HoI4 словаря наград в структурированные опкоды DirectiveResource
static func _parse_hoi4_completion_reward(cr: Dictionary, res: DirectiveResource) -> void:
	if cr.has("add_political_power"):
		res.completion_rewards.append({
			"opcode": "MOD_PC",
			"value": float(cr["add_political_power"])
		})
	if cr.has("add_war_support"):
		res.completion_rewards.append({
			"opcode": "MOD_WAR_SUPPORT",
			"value": float(cr["add_war_support"])
		})
	if cr.has("add_stability"):
		res.completion_rewards.append({
			"opcode": "MOD_STABILITY",
			"value": float(cr["add_stability"])
		})
	if cr.has("add_manpower"):
		res.completion_rewards.append({
			"opcode": "MOD_MANPOWER",
			"value": int(cr["add_manpower"])
		})
	if cr.has("country_event"):
		var ev_id := ""
		if cr["country_event"] is Dictionary:
			ev_id = str(cr["country_event"].get("id", ""))
		elif cr["country_event"] is String:
			ev_id = str(cr["country_event"])
		if not ev_id.is_empty():
			res.completion_rewards.append({
				"opcode": "FIRE_EVENT",
				"event_id": ev_id
			})
	if cr.has("set_country_flag"):
		res.completion_rewards.append({
			"opcode": "SET_FLAG",
			"flag": str(cr["set_country_flag"])
		})
	if cr.has("transfer_state"):
		res.completion_rewards.append({
			"opcode": "TRANSFER_STATE",
			"state_id": int(cr["transfer_state"])
		})
	for k in cr.keys():
		res.completion_effects[k] = cr[k]
