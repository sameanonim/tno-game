class_name MilitaryEngine
extends RefCounted


##
## MilitaryEngine: Военный модуль, стратегические фронты и спецоперации TNO
##
## Реализует:
## 1. Пошаговую макро-войну (региональное объединение Русской Смуты, фронты, оперативные оси).
## 2. Расчет огневой мощи, истощения снаряжения (Stockpiles) и сдвига линии соприкосновения.
## 3. Генерацию тактических дилемм поля боя (Battle Incidents) для EventManager.
## 4. Механику трансграничных набегов (рейдов) за снаряжением, валютой и пленными.
## 5. Шкалу глобальной ядерной напряженности DEFCON.
##

enum DefconLevel {
	PEACE_5 = 5,
	STANDBY_4 = 4,
	CRISIS_3 = 3,
	WAR_FOOTING_2 = 2,
	NUCLEAR_BRINK_1 = 1
}

static func _tr_str(key: String, params: Dictionary = {}, fallback: String = "") -> String:
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

## Детерминированный генератор псевдослучайных величин для хода (Linear Congruential + Bit Shift)
static func _get_deterministic_factor(seed_val: int, min_val: float, max_val: float) -> float:
	var s: int = (seed_val * 73856093) ^ 1274126177
	s = (s ^ (s >> 13)) * 19349663
	var norm: float = float(s & 0x7FFFFFFF) / float(0x7FFFFFFF)
	return min_val + (norm * (max_val - min_val))


static func _get_deterministic_int(seed_val: int, min_val: int, max_val: int) -> int:
	return int(round(_get_deterministic_factor(seed_val, float(min_val), float(max_val))))


## Список активных стратегических фронтов
static var active_frontlines: Array[Frontline] = []

## Глобальный реестр активных стратегических фронтов по ID
static var registered_frontlines: Dictionary = {} # Key: String (front_id), Value: Frontline


# ==============================================================================
# УПРАВЛЕНИЕ ФРОНТАМИ
# ==============================================================================

static func register_frontline(front: Frontline) -> void:
	if front == null:
		return
	registered_frontlines[front.front_id] = front
	if not active_frontlines.has(front):
		active_frontlines.append(front)


static func remove_frontline(front_id: String) -> void:
	if registered_frontlines.has(front_id):
		var front: Frontline = registered_frontlines[front_id]
		registered_frontlines.erase(front_id)
		active_frontlines.erase(front)


static func get_active_frontlines() -> Array[Frontline]:
	return active_frontlines


static func get_frontline(front_id: String) -> Frontline:
	return registered_frontlines.get(front_id, null)


static func clear_frontlines() -> void:
	registered_frontlines.clear()
	active_frontlines.clear()


## Динамическое развертывание стартового стратегического ТВД для державы игрока
static func deploy_starting_theater(player_state: CountryState, countries_world_state: Dictionary) -> Frontline:
	return MilitaryTheaterFactory.deploy_starting_theater(player_state, countries_world_state)


## Развертывание глобального прокси-театра Холодной войны (SAW, Малайя, Индонезия, Ближний Восток)
static func deploy_proxy_theater(proxy_id: String, superpower_tag: String, countries_world_state: Dictionary) -> Frontline:
	return MilitaryTheaterFactory.deploy_proxy_theater(proxy_id, superpower_tag, countries_world_state)



# ==============================================================================
# СИМУЛЯЦИЯ ФРОНТОВ И ОПЕРАТИВНЫХ НАПРАВЛЕНИЙ
# ==============================================================================

##
## Главный пошаговый расчет боевых действий на всех активных фронтах
##
## countries: Dictionary[String, CountryState] — словарь участников по тегам
## regions: Dictionary[int, RegionData] — словарь провинций по ID
##
## Возвращает список отчетов по каждой активной оперативной оси.
##
static func simulate_frontlines(
	delta_turns: int,
	countries: Dictionary,
	regions: Dictionary,
	current_turn: int = 1
) -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	var fronts_to_close: Array[String] = []

	for front in active_frontlines:
		if front == null or not front.active:
			continue

		var attacker: CountryState = countries.get(front.attacker_tag, null)
		var defender: CountryState = countries.get(front.defender_tag, null)

		# Если одна из сторон отсутствует в стейте, симуляция невозможна
		if attacker == null:
			continue

		var all_axes_finished = true
		for axis in front.axes:
			if axis != null:
				var rep = _simulate_axis_turn(axis, front, attacker, defender, regions, current_turn)
				reports.append(rep)
				if not axis.target_region_ids.is_empty():
					all_axes_finished = false

		if all_axes_finished:
			front.active = false
			fronts_to_close.append(front.front_id)
			var def_regions_count = 0
			if defender != null and not regions.is_empty():
				for r in regions.values():
					if r is RegionData and r.owner_tag == front.defender_tag:
						def_regions_count += 1

			# Полная капитуляция происходит, если у обороняющегося не осталось регионов либо силы истощены (< 3000 чел. и <= 2 регионов)
			var is_true_capitulation = (def_regions_count == 0) or (defender != null and defender.manpower_pool <= 3000 and def_regions_count <= 2)
			var cap_summary = ""
			if is_true_capitulation:
				cap_summary = _tr_str("FRONT_CAPITULATION_SUMMARY", {
					"victor": front.attacker_tag,
					"defeated": front.defender_tag
				}, "ПОЛНАЯ КАПИТУЛЯЦИЯ: Войска %s сломили сопротивление %s! Держава полностью капитулировала." % [front.attacker_tag, front.defender_tag])
			else:
				cap_summary = _tr_str("FRONT_VICTORY_SUMMARY", {
					"victor": front.attacker_tag,
					"front_name": front.name,
					"def_regions": def_regions_count
				}, "ТРИУМФ НА ТВД: Войска %s выполнили все директивы на фронте «%s». Противник сохраняет контроль над частью регионов (%d)." % [front.attacker_tag, front.name, def_regions_count])

			var cap_rep: Dictionary = {
				"front_id": front.front_id,
				"capitulation": is_true_capitulation,
				"theater_cleared": not is_true_capitulation,
				"victor_tag": front.attacker_tag,
				"defeated_tag": front.defender_tag,
				"attacker_tag": front.attacker_tag,
				"defender_tag": front.defender_tag,
				"captured_region_id": -1,
				"summary": cap_summary
			}
			reports.append(cap_rep)

	for fid in fronts_to_close:
		remove_frontline(fid)

	return reports


static func _simulate_axis_turn(
	axis: OperationalAxis,
	front: Frontline,
	attacker: CountryState,
	defender: CountryState,
	regions: Dictionary,
	current_turn: int = 1
) -> Dictionary:
	var rep: Dictionary = {
		"front_id": front.front_id,
		"axis_id": axis.axis_id,
		"axis_name": axis.name,
		"attacker_tag": front.attacker_tag,
		"defender_tag": front.defender_tag,
		"progress_delta": 0.0,
		"current_progress": axis.progress,
		"attacker_casualties": 0,
		"defender_casualties": 0,
		"weapons_lost": 0,
		"heavy_equipment_lost": 0,
		"captured_region_id": -1,
		"captured_region_name": "",
		"battle_incident": null,
		"summary": ""
	}

	if axis.target_region_ids.is_empty():
		rep["summary"] = _tr_str("FRONT_AXIS_ALL_OBJECTIVES", {"axis_name": axis.name}, "Направление [%s]: Все оперативные цели достигнуты!" % axis.name)
		return rep

	var target_id = axis.target_region_ids[0]
	var target_region: RegionData = regions.get(target_id, null)

	var cfg = ConfigManager.get_instance()

	# 1. РАСЧЕТ БОЕВОЙ МОЩИ АТАКУЮЩИХ
	var atk_power = axis.get_effective_combat_power(attacker.army_readiness, attacker.army_morale)

	# Влияние тяжелой техники и бронетанковых клиньев в зависимости от ландшафта
	var heavy_armor = axis.assigned_equipment.get("heavy_equipment", 0)
	if heavy_armor > 0 and target_region != null:
		var ttype = target_region.terrain_type.to_lower()
		match ttype:
			"mountains", "marsh":
				atk_power *= 0.85
			"urban":
				atk_power *= 0.90
			"forest":
				atk_power *= 0.95
			_:
				# Равнины, открытая местность: бронетанковый прорыв
				atk_power *= 1.15

	# Проверка складов оружия атакующего (Data-Driven через ConfigManager)
	var hunger_ratio = cfg.get_float("military", "combat_hunger_threshold_ratio", 0.4) if cfg != null else 0.4
	var hunger_penalty = cfg.get_float("military", "combat_hunger_atk_penalty", 0.65) if cfg != null else 0.65
	var weapons_in_use = axis.assigned_equipment.get("infantry_weapons", 0)
	if weapons_in_use < int(float(axis.assigned_manpower) * hunger_ratio):
		atk_power *= hunger_penalty # Штраф за снарядный голод
		axis.is_stalled = true

	# 2. РАСЧЕТ ОБОРОНИТЕЛЬНОЙ МОЩИ
	var def_power = 100.0
	var terrain_mult = 1.0

	var terrain_mods = cfg.get_dict("military", "terrain_modifiers", {}) if cfg != null else {}
	if target_region != null:
		var ttype = target_region.terrain_type.to_lower()
		if terrain_mods.has(ttype):
			terrain_mult = float(terrain_mods[ttype])
		else:
			match ttype:
				"forest": terrain_mult = 1.25
				"marsh": terrain_mult = 1.45
				"mountains": terrain_mult = 1.70
				"urban": terrain_mult = 1.55
				_: terrain_mult = 1.0

		def_power = (target_region.garrison_strength * 1.5 + float(target_region.civilian_infrastructure) * 8.0) * terrain_mult

	if defender != null:
		var def_factory_power = cfg.get_float("military", "defender_factory_power_factor", 15.0) if cfg != null else 15.0
		var def_training = (defender.army_readiness * 0.5 + defender.army_morale * 0.5) / 100.0
		def_power += (float(defender.military_factories) * def_factory_power) * def_training

	# 3. БАЛАНС СИЛ И СДВИГ ФРОНТА (Детерминированный сид хода)
	var axis_seed: int = (current_turn * 73856093) ^ (axis.axis_id.hash() * 19349663) ^ (target_id * 83492791)
	var randomness = _get_deterministic_factor(axis_seed, 0.90, 1.10)
	var ratio = (atk_power * randomness) / maxf(def_power, 1.0)
	var progress_gain = 0.0

	var ratio_high = cfg.get_float("military", "breakthrough_ratio_high", 1.4) if cfg != null else 1.4
	var ratio_mid = cfg.get_float("military", "breakthrough_ratio_mid", 1.0) if cfg != null else 1.0
	var ratio_low = cfg.get_float("military", "breakthrough_ratio_low", 0.75) if cfg != null else 0.75

	if ratio >= ratio_high:
		# Решительный прорыв
		var p_min = cfg.get_float("military", "progress_gain_high_min", 14.0) if cfg != null else 14.0
		var p_max = cfg.get_float("military", "progress_gain_high_max", 24.0) if cfg != null else 24.0
		progress_gain = _get_deterministic_factor(axis_seed + 1, p_min, p_max)
		axis.is_stalled = false
	elif ratio >= ratio_mid:
		# Уверенное продвижение
		var p_min = cfg.get_float("military", "progress_gain_mid_min", 8.0) if cfg != null else 8.0
		var p_max = cfg.get_float("military", "progress_gain_mid_max", 14.0) if cfg != null else 14.0
		progress_gain = _get_deterministic_factor(axis_seed + 2, p_min, p_max)
		axis.is_stalled = false
	elif ratio >= ratio_low:
		# Вязкие позиционные бои
		var p_min = cfg.get_float("military", "progress_gain_low_min", 2.0) if cfg != null else 2.0
		var p_max = cfg.get_float("military", "progress_gain_low_max", 6.0) if cfg != null else 6.0
		progress_gain = _get_deterministic_factor(axis_seed + 3, p_min, p_max)
		axis.is_stalled = false
	else:
		# Наступление захлебнулось
		var p_min = cfg.get_float("military", "progress_loss_stalled_min", 1.0) if cfg != null else 1.0
		var p_max = cfg.get_float("military", "progress_loss_stalled_max", 4.0) if cfg != null else 4.0
		progress_gain = -_get_deterministic_factor(axis_seed + 4, p_min, p_max)
		axis.is_stalled = true

	# Модификатор стойки
	match axis.posture:
		OperationalAxis.Posture.AGGRESSIVE_BREAKTHROUGH:
			var agg_mult = cfg.get_float("military", "posture_aggressive_mult", 1.35) if cfg != null else 1.35
			progress_gain *= agg_mult
		OperationalAxis.Posture.DEFENSIVE:
			var def_max = cfg.get_float("military", "posture_defensive_max_progress", 1.0) if cfg != null else 1.0
			progress_gain = minf(progress_gain, def_max) # В обороне продвижение минимально

	axis.progress = clampf(axis.progress + progress_gain, 0.0, 100.0)
	rep["progress_delta"] = progress_gain
	rep["current_progress"] = axis.progress

	# 4. ПОТЕРИ И АМОРТИЗАЦИЯ СНАРЯЖЕНИЯ
	var loss_min = cfg.get_float("military", "base_losses_rate_min", 0.015) if cfg != null else 0.015
	var loss_max = cfg.get_float("military", "base_losses_rate_max", 0.035) if cfg != null else 0.035
	var wep_loss_ratio = cfg.get_float("military", "weapons_loss_ratio", 0.75) if cfg != null else 0.75

	var loss_rate = _get_deterministic_factor(axis_seed + 5, loss_min, loss_max)
	var base_losses = int(float(axis.assigned_manpower) * loss_rate)
	var atk_casualties = int(base_losses / maxf(ratio * 0.8, 0.5))
	var def_casualties = int(base_losses * ratio)
	var weapons_lost = int(float(atk_casualties) * wep_loss_ratio)
	var heavy_lost = int(float(atk_casualties) * 0.035)

	# Списание потерь (только с боевой группы оси)
	axis.assigned_manpower = maxi(axis.assigned_manpower - atk_casualties, 0)
	var eq_weapons = axis.assigned_equipment.get("infantry_weapons", 0)
	axis.assigned_equipment["infantry_weapons"] = maxi(eq_weapons - weapons_lost, 0)
	var eq_heavy = axis.assigned_equipment.get("heavy_equipment", 0)
	axis.assigned_equipment["heavy_equipment"] = maxi(eq_heavy - heavy_lost, 0)

	# Пополнение потерь оси из глобальных резервов государства
	var manpower_reinforcement = min(atk_casualties, attacker.manpower_pool)
	attacker.manpower_pool -= manpower_reinforcement
	axis.assigned_manpower += manpower_reinforcement
	
	var weapons_reinforcement = min(weapons_lost, attacker.infantry_weapons_stockpile)
	attacker.infantry_weapons_stockpile -= weapons_reinforcement
	axis.assigned_equipment["infantry_weapons"] += weapons_reinforcement

	var heavy_reinforcement = min(heavy_lost, attacker.heavy_equipment_stockpile)
	attacker.heavy_equipment_stockpile -= heavy_reinforcement
	axis.assigned_equipment["heavy_equipment"] += heavy_reinforcement

	if defender != null:
		defender.manpower_pool = maxi(defender.manpower_pool - def_casualties, 0)
		defender.infantry_weapons_stockpile = maxi(defender.infantry_weapons_stockpile - int(def_casualties * 0.6), 0)
		defender.heavy_equipment_stockpile = maxi(defender.heavy_equipment_stockpile - int(def_casualties * 0.025), 0)

	if target_region != null:
		target_region.garrison_strength = clampf(target_region.garrison_strength - (float(def_casualties) * 0.02), 5.0, 100.0)
		target_region.unrest = clampf(target_region.unrest + 4.0, 0.0, 100.0)

	front.total_attacker_casualties += atk_casualties
	front.total_defender_casualties += def_casualties
	front.tension = clampf(front.tension + 2.5, 0.0, 100.0)

	rep["attacker_casualties"] = atk_casualties
	rep["defender_casualties"] = def_casualties
	rep["weapons_lost"] = weapons_lost
	rep["heavy_equipment_lost"] = heavy_lost

	# 5. СМЕНА ВЛАДЕЛЬЦА ПРИ ПРОРЫВЕ (PROGRESS >= 100%)
	if axis.progress >= 100.0:
		rep["captured_region_id"] = target_id
		if target_region != null:
			rep["captured_region_name"] = target_region.province_name
			var old_owner = target_region.owner_tag
			target_region.owner_tag = front.attacker_tag
			
			# Штрафы оккупации эпохи Русской Смуты (Анархия)
			target_region.unrest = 85.0
			target_region.garrison_strength = 15.0

			rep["new_owner"] = front.attacker_tag
			rep["previous_owner"] = old_owner

		# Переход к следующей цели на оперативной оси
		axis.target_region_ids.pop_front()
		axis.progress = 0.0

		# Бонус к легитимности и морали
		attacker.legitimacy = clampf(attacker.legitimacy + 2.5, 0.0, 100.0)
		attacker.army_morale = clampf(attacker.army_morale + 4.0, 0.0, 100.0)
		if defender != null:
			defender.legitimacy = clampf(defender.legitimacy - 3.5, 0.0, 100.0)
			defender.army_morale = clampf(defender.army_morale - 5.0, 0.0, 100.0)

		rep["summary"] = _tr_str("FRONT_BREAKTHROUGH_SUMMARY", {
			"axis_name": axis.name,
			"region_id": target_id,
			"region_name": rep["captured_region_name"],
			"enemy_losses": def_casualties
		}, "ПРОРЫВ ФРОНТА! Ось [%s] сломила оборону и заняла регион #%d (%s)! Потери врага: %d чел." % [axis.name, target_id, rep["captured_region_name"], def_casualties])
	else:
		var status_str = _tr_str("FRONT_STATUS_ADVANCING", {"delta": "%0.1f" % progress_gain}, "продвижение +%0.1f%%" % progress_gain) if progress_gain > 0 else _tr_str("FRONT_STATUS_STALLED", {}, "позиционный тупик")
		rep["summary"] = _tr_str("FRONT_TURN_SUMMARY", {
			"axis_name": axis.name,
			"status": status_str,
			"progress": "%0.1f" % axis.progress,
			"our_losses": atk_casualties,
			"enemy_losses": def_casualties
		}, "Ось [%s]: %s (прогресс %0.1f%%). Потери: наши -%d, враг -%d." % [axis.name, status_str, axis.progress, atk_casualties, def_casualties])

	# 6. ГЕНЕРАЦИЯ БОЕВЫХ ДИЛЕММ (BATTLE INCIDENTS) — Детерминированный расчет
	var incident_roll = _get_deterministic_factor(axis_seed + 6, 0.0, 1.0)
	if ratio >= 1.85 and incident_roll < 0.35:
		rep["battle_incident"] = _create_battle_incident("breakthrough", axis, front, attacker, defender, current_turn)
	elif ratio <= 0.55 and axis.posture == OperationalAxis.Posture.AGGRESSIVE_BREAKTHROUGH and incident_roll < 0.40:
		rep["battle_incident"] = _create_battle_incident("encirclement_risk", axis, front, attacker, defender, current_turn)

	return rep


static func _create_battle_incident(
	type: String,
	axis: OperationalAxis,
	front: Frontline,
	attacker: CountryState,
	defender: CountryState,
	turn: int = 1
) -> GameEvent:
	var ev = GameEvent.new()
	ev.is_modal = true
	ev.fire_only_once = false

	var det_id = absi((axis.axis_id.hash() * 31) ^ (turn * 997))
	if type == "breakthrough":
		ev.event_id = "battle_incident_breakthrough_%s_%d" % [axis.axis_id, det_id]
		ev.title = _tr_str("EVT_BATTLE_BREAKTHROUGH_TITLE", {"axis_name": axis.name.to_upper()}, "ОПЕРАТИВНЫЙ ПРОРЫВ: %s" % axis.name.to_upper())
		ev.classification = _tr_str("EVT_BATTLE_BREAKTHROUGH_CLASS", {}, "[ВОЕННАЯ ДЕПЕША // ГЕНШТАБ]")
		ev.description = _tr_str("EVT_BATTLE_BREAKTHROUGH_DESC", {"axis_name": axis.name}, "Авангардные соединения на оси «%s» разгромили передовые заслоны противника." % axis.name)

		var opt1 = {
			"option_id": "opt_deep_thrust",
			"text": _tr_str("EVT_BATTLE_BREAKTHROUGH_OPT1", {}, "Развить успех глубоким танковым клином (-1500 винтовок, +20%% прогресса)"),
			"required_cap": 1,
			"required_pc": 5.0,
			"effects": {
				"modify_weapons": -1500,
				"modify_pc": -5.0
			}
		}
		var opt2 = {
			"option_id": "opt_consolidate",
			"text": _tr_str("EVT_BATTLE_BREAKTHROUGH_OPT2", {}, "Закрепиться на рубежах и подтянуть артиллерию (+5 к боеготовности)"),
			"required_cap": 0,
			"required_pc": 0.0,
			"effects": {
				"modify_legitimacy": 1.5
			}
		}
		ev.options = [opt1, opt2]

	elif type == "encirclement_risk":
		ev.event_id = "battle_incident_encirclement_%s_%d" % [axis.axis_id, det_id]
		ev.title = _tr_str("EVT_BATTLE_ENCIRCLEMENT_TITLE", {"axis_name": axis.name.to_upper()}, "УГРОЗА ОКРУЖЕНИЯ: %s" % axis.name.to_upper())
		ev.classification = _tr_str("EVT_BATTLE_ENCIRCLEMENT_CLASS", {}, "[СРОЧНАЯ МОЛНИЯ // ОПЕРАТИВНАЯ ГРУППА]")
		ev.description = _tr_str("EVT_BATTLE_ENCIRCLEMENT_DESC", {"axis_name": axis.name}, "Передовые батальоны на острие удара оси «%s» оторвались от тылов..." % axis.name)

		var opt1 = {
			"option_id": "opt_stand_firm",
			"text": _tr_str("EVT_BATTLE_ENCIRCLEMENT_OPT1", {}, "Стоять насмерть, удерживать плацдарм! (-2500 бойцов, +2 к легитимности)"),
			"required_cap": 1,
			"required_pc": 10.0,
			"effects": {
				"modify_manpower": -2500,
				"modify_legitimacy": 2.0
			}
		}
		var opt2 = {
			"option_id": "opt_orderly_retreat",
			"text": _tr_str("EVT_BATTLE_ENCIRCLEMENT_OPT2", {}, "Организованный отход на исходные позиции (-10%% прогресса оси)"),
			"required_cap": 0,
			"required_pc": 0.0,
			"effects": {
				"modify_radicalization": 2.0
			}
		}
		ev.options = [opt1, opt2]

	return ev


# ==============================================================================
# ТРАНСГРАНИЧНЫЕ НАБЕГИ (WARLORD BORDER RAIDS)
# ==============================================================================

class RaidResult:
	var success: bool
	var loot_cash_billions: float
	var captured_weapons: int
	var captured_manpower: int
	var attacker_casualties: int
	var defender_casualties: int
	var region_damage_unrest: float
	var narrative_summary: String


## Расчет и исполнение пошагового набега на пограничный регион
static func execute_border_raid(
	attacker: CountryState,
	target_region: RegionData,
	raid_intensity: String = "medium",
	current_turn: int = 1
) -> RaidResult:
	var result = RaidResult.new()

	var cfg = ConfigManager.get_instance()
	var raids_cfg = cfg.get_dict("military", "raids", {}) if cfg != null else {}

	var commitment_factor = 1.0
	var cost_weapons = 200
	var cost_manpower = 400

	if raids_cfg.has(raid_intensity) and raids_cfg[raid_intensity] is Dictionary:
		var r_data = raids_cfg[raid_intensity]
		commitment_factor = float(r_data.get("commitment_factor", 1.0))
		cost_weapons = int(r_data.get("cost_weapons", 200))
		cost_manpower = int(r_data.get("cost_manpower", 400))
	else:
		match raid_intensity:
			"recon":
				commitment_factor = 0.5
				cost_weapons = 100
				cost_manpower = 150
			"heavy":
				commitment_factor = 2.0
				cost_weapons = 500
				cost_manpower = 1000

	if attacker.infantry_weapons_stockpile < cost_weapons:
		result.success = false
		result.narrative_summary = _tr_str("RAID_DEFICIT_WEAPONS", {}, "Рейд сорван: острая нехватка стрелкового оружия на складах!")
		return result

	attacker.infantry_weapons_stockpile -= cost_weapons

	var attack_power = (attacker.army_readiness * 0.6 + attacker.army_morale * 0.4) * commitment_factor

	var terrain_mult = 1.0
	match target_region.terrain_type:
		"forest": terrain_mult = 1.2
		"marsh": terrain_mult = 1.4
		"mountains": terrain_mult = 1.6
		"urban": terrain_mult = 1.5

	var defense_power = (target_region.garrison_strength * terrain_mult) + (float(target_region.civilian_infrastructure) * 3.0)

	var raid_seed: int = (attacker.country_tag.hash() * 37) ^ (target_region.province_id * 101) ^ (current_turn * 99991)
	var roll = _get_deterministic_factor(raid_seed, 0.85, 1.15)
	var ratio = (attack_power * roll) / maxf(defense_power, 1.0)

	if ratio >= 1.0:
		result.success = true
		var spoils_factor = clampf(ratio - 0.5, 0.5, 3.0) * commitment_factor

		result.loot_cash_billions = float(target_region.industrial_capacity) * 0.04 * spoils_factor
		result.captured_weapons = int(_get_deterministic_int(raid_seed + 1, 150, 450) * spoils_factor)
		result.captured_manpower = int(_get_deterministic_int(raid_seed + 2, 80, 300) * spoils_factor)

		var atk_loss_ratio = _get_deterministic_factor(raid_seed + 3, 0.05, 0.20)
		var def_loss_ratio = _get_deterministic_factor(raid_seed + 4, 0.3, 0.8)
		result.attacker_casualties = int(cost_manpower * atk_loss_ratio / ratio)
		result.defender_casualties = int(cost_manpower * def_loss_ratio * ratio)
		result.region_damage_unrest = clampf(15.0 * spoils_factor, 5.0, 40.0)

		attacker.liquid_reserves_billions += result.loot_cash_billions
		attacker.infantry_weapons_stockpile += result.captured_weapons
		attacker.manpower_pool += result.captured_manpower
		attacker.manpower_pool = maxi(attacker.manpower_pool - result.attacker_casualties, 0)

		attacker.army_morale = clampf(attacker.army_morale + 2.5, 0.0, 100.0)
		attacker.legitimacy = clampf(attacker.legitimacy + 1.5, 0.0, 100.0)

		target_region.unrest = clampf(target_region.unrest + result.region_damage_unrest, 0.0, 100.0)
		target_region.garrison_strength = clampf(target_region.garrison_strength - 20.0 * spoils_factor, 5.0, 100.0)

		result.narrative_summary = _tr_str("RAID_SUCCESS_SUMMARY", {
			"cash": "%0.2f" % result.loot_cash_billions,
			"weapons": result.captured_weapons,
			"manpower": result.captured_manpower,
			"losses": result.attacker_casualties
		}, "Рейд увенчался успехом! Захвачено $%0.2f млрд трофеев, %d стволов оружия, %d пленных. Потери: %d чел." % [result.loot_cash_billions, result.captured_weapons, result.captured_manpower, result.attacker_casualties])
	else:
		result.success = false
		var fail_atk_loss = _get_deterministic_factor(raid_seed + 5, 0.25, 0.60)
		var fail_def_loss = _get_deterministic_factor(raid_seed + 6, 0.10, 0.30)
		result.attacker_casualties = int(cost_manpower * fail_atk_loss)
		result.defender_casualties = int(cost_manpower * fail_def_loss)

		attacker.manpower_pool = maxi(attacker.manpower_pool - result.attacker_casualties, 0)
		attacker.army_morale = clampf(attacker.army_morale - 3.0, 0.0, 100.0)
		attacker.radicalization = clampf(attacker.radicalization + 1.5, 0.0, 100.0)

		result.narrative_summary = _tr_str("RAID_FAILURE_SUMMARY", {
			"losses": result.attacker_casualties
		}, "Отряды натолкнулись на организованную оборону и отступили с потерями (%d бойцов)." % result.attacker_casualties)


	return result
