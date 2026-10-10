class_name NuclearDefconManager
extends Node

##
## NuclearDefconManager: Глобальный контроллер шкалы ядерной готовности DEFCON и кризисов
##
## Отвечает за:
## 1. Управление шкалой боеготовности DEFCON (5 - Мир, 4 - Повышенная, 3 - Кризис, 2 - Предъядерная, 1 - Армагеддон).
## 2. Мониторинг геополитической напряженности (World Tension) и прокси-конфликтов ядерных сверхдержав.
## 3. Регистрацию и разрешение международных ядерных кризисов (2WRW, Карибский, Южноафриканский и др.).
## 4. Обратный отсчет «Ядерной Полночи» (Doomsday Countdown) на DEFCON 1 с запуском супер-события SE_NUCLEAR_WAR.
## 5. Полную сериализацию и восстановление состояния в сохранениях.
##

signal defcon_level_changed(level: int, reason: String)
signal crisis_started(crisis_id: String, crisis_name: String)
signal crisis_resolved(crisis_id: String, resolution_reason: String)
signal doomsday_ticked(turns_left: int)
signal nuclear_war_triggered(initiator: String, reason: String)
signal super_event_requested(super_event_id: String)

enum DefconLevel {
	DEFCON_5 = 5, # Мирное время
	DEFCON_4 = 4, # Повышенная готовность (локальные прокси-войны)
	DEFCON_3 = 3, # Кризис сверхдержав / мобилизация стратегических сил
	DEFCON_2 = 2, # Предъядерная готовность / бомбардировщики на боевом дежурстве
	DEFCON_1 = 1  # Ядерная полночь / неминуемый термоядерный удар
}

const SUPERPOWERS: Array[String] = [
	"USA", "GER", "JAP", "SPE", "BOR", "GOR", "HEY"
]

@export var current_defcon: int = 5
@export var global_world_tension: float = 10.0
@export var doomsday_turns_remaining: int = -1
@export var default_doomsday_timer: int = 2
@export var nuclear_war_occurred: bool = false

var active_crises: Dictionary = {}
var escalation_history: Array[Dictionary] = []


func _ready() -> void:
	MilitaryEngine.global_defcon_level = current_defcon
	MilitaryEngine.global_world_tension = global_world_tension


"""Регистрирует международный кризис, повышающий напряженность и фиксирующий минимальный порог DEFCON.
"""
func trigger_crisis(
	crisis_id: String,
	crisis_name: String,
	tension_impact: float,
	defcon_floor: int = 3,
	initiator: String = "",
	target: String = ""
) -> void:
	if crisis_id.is_empty():
		return

	var c_floor: int = clampi(defcon_floor, 1, 5)
	active_crises[crisis_id] = {
		"id": crisis_id,
		"name": crisis_name,
		"tension": tension_impact,
		"defcon_floor": c_floor,
		"initiator": initiator,
		"target": target,
		"turns_active": 0
	}

	global_world_tension = clampf(global_world_tension + tension_impact, 5.0, 100.0)
	crisis_started.emit(crisis_id, crisis_name)

	var reason = "Разразился международный кризис: %s" % crisis_name
	if current_defcon > c_floor:
		escalate_defcon(c_floor, reason)
	else:
		_sync_military_engine()


"""Разрешает международный кризис со снижением напряженности и потенциальной деэскалацией DEFCON.
"""
func resolve_crisis(crisis_id: String, relief_impact: float = 20.0, reason: String = "") -> void:
	if not active_crises.has(crisis_id):
		return

	var crisis_info: Dictionary = active_crises[crisis_id]
	var c_name: String = str(crisis_info.get("name", crisis_id))
	active_crises.erase(crisis_id)

	global_world_tension = clampf(global_world_tension - relief_impact, 5.0, 100.0)
	var res_reason: String = reason if not reason.is_empty() else ("Кризис разрешен: %s" % c_name)
	crisis_resolved.emit(crisis_id, res_reason)

	# Если все критические кризисы сняты, проверяем возможность деэскалации
	var floor_lvl: int = _get_active_defcon_floor()
	if current_defcon < floor_lvl:
		deescalate_defcon(res_reason)
	else:
		_sync_military_engine()


"""Принудительно эскалирует шкалу DEFCON на более тревожный уровень (меньшее число).
"""
func escalate_defcon(target_level: int, reason: String) -> void:
	var clamped_target: int = clampi(target_level, 1, 5)
	if clamped_target >= current_defcon:
		return

	var prev: int = current_defcon
	current_defcon = clamped_target

	# Синхронизация напряженности с целевым уровнем эскалации
	match current_defcon:
		1: global_world_tension = maxf(global_world_tension, 95.0)
		2: global_world_tension = maxf(global_world_tension, 80.0)
		3: global_world_tension = maxf(global_world_tension, 55.0)
		4: global_world_tension = maxf(global_world_tension, 30.0)

	_record_history(prev, current_defcon, reason)
	_sync_military_engine()

	defcon_level_changed.emit(current_defcon, reason)

	if current_defcon == 1:
		_initiate_defcon_1(reason)


"""Деэскалирует шкалу DEFCON на более спокойный уровень (большее число).
"""
func deescalate_defcon(reason: String) -> void:
	var floor_lvl: int = _get_active_defcon_floor()
	var target_lvl: int = mini(current_defcon + 1, floor_lvl)
	if target_lvl <= current_defcon:
		return

	var prev: int = current_defcon
	current_defcon = target_lvl
	if current_defcon > 1:
		doomsday_turns_remaining = -1

	_record_history(prev, current_defcon, reason)
	_sync_military_engine()

	defcon_level_changed.emit(current_defcon, reason)


"""Возвращает минимальный уровень DEFCON (наиболее тревожный), наложенный активными кризисами.
"""
func _get_active_defcon_floor() -> int:
	var min_floor: int = 5
	for cid in active_crises.keys():
		var cr = active_crises[cid]
		if cr is Dictionary:
			var fl: int = int(cr.get("defcon_floor", 5))
			if fl < min_floor:
				min_floor = fl
	return min_floor


"""Инициация DEFCON 1: запуск супер-события и таймера судного дня.
"""
func _initiate_defcon_1(reason: String) -> void:
	doomsday_turns_remaining = default_doomsday_timer
	super_event_requested.emit("SE_NUCLEAR_WAR")
	_record_history(current_defcon, 1, "ЯДЕРНАЯ ПОЛНОЧЬ: Активирован таймер Doomsday (%d ходов). %s" % [doomsday_turns_remaining, reason])


"""Ежеходный аудит и расчет динамической эскалации DEFCON на основе состояния мира.
"""
func evaluate_turn(
	frontlines_list: Array[Frontline],
	countries: Dictionary,
	current_turn: int = 1
) -> Dictionary:
	# Инкремент возраста кризисов
	for cid in active_crises.keys():
		var cr = active_crises[cid]
		if cr is Dictionary:
			cr["turns_active"] = int(cr.get("turns_active", 0)) + 1

	# Расчет напряженности от фронтов
	var total_tension: float = 0.0
	var superpower_proxy_clashes: int = 0
	var active_front_count: int = 0

	for front: Frontline in frontlines_list:
		if front != null and front.active:
			active_front_count += 1
			total_tension += front.tension
			var atk: String = front.attacker_tag.to_upper()
			var def: String = front.defender_tag.to_upper()
			if atk in SUPERPOWERS or def in SUPERPOWERS:
				superpower_proxy_clashes += 1

	var tension_fronts: float = (total_tension / float(maxi(active_front_count, 1))) if active_front_count > 0 else 0.0
	var crisis_tension: float = 0.0
	for cr in active_crises.values():
		crisis_tension += float(cr.get("tension", 0.0))

	var target_tension: float = (tension_fronts * 0.4) + (float(superpower_proxy_clashes) * 22.0) + (crisis_tension * 0.6)
	var tension_decay: float = 1.5

	if target_tension > global_world_tension:
		global_world_tension = clampf(global_world_tension + (target_tension - global_world_tension) * 0.5, 5.0, 100.0)
	else:
		global_world_tension = clampf(maxf(global_world_tension - tension_decay, 5.0), 5.0, 100.0)

	# Определение уровня DEFCON по порогам
	var cfg = ConfigManager.get_instance()
	var defcon_thresh: Dictionary = cfg.get_constant("military", "defcon_escalation_thresholds", {}) if cfg != null else {}
	var t1: float = float(defcon_thresh.get("DEFCON_1", 90.0))
	var t2: float = float(defcon_thresh.get("DEFCON_2", 75.0))
	var t3: float = float(defcon_thresh.get("DEFCON_3", 50.0))
	var t4: float = float(defcon_thresh.get("DEFCON_4", 25.0))

	var calculated_defcon: int = 5
	if global_world_tension >= t1:
		calculated_defcon = 1
	elif global_world_tension >= t2:
		calculated_defcon = 2
	elif global_world_tension >= t3:
		calculated_defcon = 3
	elif global_world_tension >= t4:
		calculated_defcon = 4
	else:
		calculated_defcon = 5

	# Применение минимального порога кризисов
	var floor_lvl: int = _get_active_defcon_floor()
	var new_defcon: int = mini(calculated_defcon, floor_lvl)
	if doomsday_turns_remaining >= 0:
		new_defcon = 1

	var changed: bool = (new_defcon != current_defcon)
	var prev_defcon: int = current_defcon
	var reason_str: String = ""

	if changed:
		current_defcon = new_defcon
		if new_defcon < prev_defcon:
			reason_str = "Эскалация международной обстановки: объявлен уровень DEFCON %d!" % new_defcon
		else:
			reason_str = "Деэскалация кризиса: уровень боеготовности снижен до DEFCON %d." % new_defcon

		_record_history(prev_defcon, current_defcon, reason_str)
		defcon_level_changed.emit(current_defcon, reason_str)

	# Обработка DEFCON 1 и Doomsday таймера
	var is_armageddon: bool = false
	if current_defcon == 1:
		if doomsday_turns_remaining < 0:
			_initiate_defcon_1(reason_str)
		else:
			doomsday_turns_remaining -= 1
			doomsday_ticked.emit(doomsday_turns_remaining)
			if doomsday_turns_remaining <= 0:
				nuclear_war_occurred = true
				is_armageddon = true
				nuclear_war_triggered.emit("GLOBAL_MIDNIGHT", "Таймер судного дня истек. Сверхдержавы обменялись ядерными ударами.")
	else:
		doomsday_turns_remaining = -1

	_sync_military_engine()

	# Синхронизация флагов в государствах
	for c_tag in countries.keys():
		var c_st = countries[c_tag]
		if c_st is CountryState:
			c_st.set_flag("defcon_level", current_defcon)
			c_st.set_flag("world_tension", global_world_tension)
			c_st.set_flag("doomsday_turns_left", doomsday_turns_remaining)

	return {
		"defcon_changed": changed,
		"previous_level": prev_defcon,
		"current_level": current_defcon,
		"world_tension": global_world_tension,
		"reason": reason_str,
		"is_nuclear_midnight": (current_defcon == 1),
		"is_armageddon": is_armageddon,
		"doomsday_turns_left": doomsday_turns_remaining,
		"active_crises_count": active_crises.size()
	}


func _sync_military_engine() -> void:
	MilitaryEngine.global_defcon_level = current_defcon
	MilitaryEngine.global_world_tension = global_world_tension


func _record_history(from_lvl: int, to_lvl: int, reason: String) -> void:
	escalation_history.append({
		"from": from_lvl,
		"to": to_lvl,
		"reason": reason,
		"tension": global_world_tension,
		"timestamp": Time.get_unix_time_from_system() if OS.has_feature("standalone") else 0
	})


func has_active_crisis(crisis_id: String) -> bool:
	return active_crises.has(crisis_id)


func get_crisis_data(crisis_id: String) -> Dictionary:
	return active_crises.get(crisis_id, {}).duplicate()


func get_active_crises() -> Array[Dictionary]:
	var res: Array[Dictionary] = []
	for c in active_crises.values():
		if c is Dictionary:
			res.append(c.duplicate())
	return res


func reset_to_peace() -> void:
	current_defcon = 5
	global_world_tension = 10.0
	doomsday_turns_remaining = -1
	nuclear_war_occurred = false
	active_crises.clear()
	_sync_military_engine()


func serialize() -> Dictionary:
	return {
		"current_defcon": current_defcon,
		"global_world_tension": global_world_tension,
		"doomsday_turns_remaining": doomsday_turns_remaining,
		"nuclear_war_occurred": nuclear_war_occurred,
		"active_crises": active_crises.duplicate(true),
		"escalation_history": escalation_history.duplicate(true)
	}


func deserialize(data: Dictionary) -> void:
	if data.is_empty():
		return
	current_defcon = clampi(int(data.get("current_defcon", 5)), 1, 5)
	global_world_tension = clampf(float(data.get("global_world_tension", 10.0)), 5.0, 100.0)
	doomsday_turns_remaining = int(data.get("doomsday_turns_remaining", -1))
	nuclear_war_occurred = bool(data.get("nuclear_war_occurred", false))

	if data.has("active_crises") and data["active_crises"] is Dictionary:
		active_crises = data["active_crises"].duplicate(true)
	if data.has("escalation_history") and data["escalation_history"] is Array:
		escalation_history.clear()
		for item in data["escalation_history"]:
			if item is Dictionary:
				escalation_history.append(item)

	_sync_military_engine()
