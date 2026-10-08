class_name GCWProxyWarHandler
extends RefCounted

##
## GCWProxyWarHandler: Обработка прокси-конфликтов, шкалы DEFCON и поставок ленд-лиза
## ==============================================================================
## Отвечает за:
## 1. Пошаговую эскалацию театров прокси-войн (SAW, Ближний Восток, Малайя, Индонезия).
## 2. Управление уровнем готовности DEFCON и триггер ядерного апокалипсиса при DEFCON 1.
## 3. Отправку добровольческих дивизий и эшелонов ленд-лиза.
## ==============================================================================


"""Пошаговый расчет эскалации прокси-конфликтов и динамики DEFCON.
"""
static func process_proxy_wars(manager: GermanCivilWarManager) -> void:
	var turn_num: int = manager.turn_manager_ref.current_turn if manager.turn_manager_ref != null else 1
	for p_key in manager.proxy_wars.keys():
		var p_data = manager.proxy_wars[p_key]
		if p_data["status"] == "active":
			var p_seed: int = turn_num * 1097 + str(p_key).hash()
			p_data["tension"] = clampf(p_data["tension"] + GermanCivilWarManager._get_deterministic_factor(p_seed, -2.0, 4.0), 0.0, 100.0)
			# Если напряженность критическая (>85), шкала DEFCON сдвигается вниз (к ядерному армагеддону)
			if p_data["tension"] > 85.0 and manager.current_defcon > 2:
				adjust_defcon(manager, manager.current_defcon - 1, "Эскалация в конфликте: %s" % p_data["name"])


"""Отправка военного контингента и финансовой помощи в театр прокси-войны.
"""
static func send_proxy_aid(manager: GermanCivilWarManager, proxy_key: String, volunteer_divisions: int, cash_billions: float) -> bool:
	if manager.active_phase != GermanCivilWarManager.GCWPhase.PHASE_3_HEGEMONY or manager.player_state_ref == null:
		return false
	if not manager.proxy_wars.has(proxy_key):
		return false

	var player_state: CountryState = manager.player_state_ref
	var cost_manpower = volunteer_divisions * 10000
	var cost_weapons = volunteer_divisions * 2500
	var cost_tanks = volunteer_divisions * 50

	if player_state.manpower_pool < cost_manpower or player_state.liquid_reserves_billions < cash_billions:
		return false
	if player_state.infantry_weapons_stockpile < cost_weapons:
		return false

	player_state.manpower_pool -= cost_manpower
	player_state.infantry_weapons_stockpile -= cost_weapons
	if player_state.heavy_equipment_stockpile >= cost_tanks:
		player_state.heavy_equipment_stockpile -= cost_tanks
	player_state.liquid_reserves_billions -= cash_billions

	var p = manager.proxy_wars[proxy_key]
	p["german_volunteers"] += volunteer_divisions
	p["weapons_delivered"] += cost_weapons
	p["tanks_delivered"] += cost_tanks
	p["funded_billions"] += cash_billions
	p["tension"] = maxf(0.0, p["tension"] - (float(volunteer_divisions) * 8.0 + cash_billions * 5.0))

	player_state.legitimacy = clampf(player_state.legitimacy + 2.0, 0.0, 100.0)

	# Развертывание ТВД в MilitaryEngine при отправке контингента
	if manager.turn_manager_ref != null:
		var front = MilitaryEngine.deploy_proxy_theater(proxy_key, player_state.country_tag, manager.turn_manager_ref.countries_world_state)
		if front != null and front.axes.size() > 0:
			var ax = front.axes[0]
			ax.assigned_manpower += cost_manpower
			ax.assigned_equipment["infantry_weapons"] = ax.assigned_equipment.get("infantry_weapons", 0) + cost_weapons
			ax.assigned_equipment["heavy_equipment"] = ax.assigned_equipment.get("heavy_equipment", 0) + cost_tanks

	print("[GCWManager] Proxy aid dispatched to %s: %d divs, $%.2fB." % [p["name"], volunteer_divisions, cash_billions])
	return true


"""Отправка эшелона ленд-лиза (винтовки, бронетехника, валюта).
"""
static func send_proxy_lend_lease(manager: GermanCivilWarManager, proxy_key: String, weapons: int, tanks: int, cash_billions: float) -> Dictionary:
	if manager.active_phase != GermanCivilWarManager.GCWPhase.PHASE_3_HEGEMONY or manager.player_state_ref == null:
		return {"success": false, "message": "ОШИБКА: Доступно только в Фазе 3 (Сверхдержава)."}
	if not manager.proxy_wars.has(proxy_key):
		return {"success": false, "message": "ОШИБКА: Театр прокси-войны не найден."}

	var player_state: CountryState = manager.player_state_ref
	if player_state.infantry_weapons_stockpile < weapons:
		return {"success": false, "message": "ОШИБКА: Недостаточно стрелкового оружия (%d/%d)." % [player_state.infantry_weapons_stockpile, weapons]}
	if player_state.heavy_equipment_stockpile < tanks:
		return {"success": false, "message": "ОШИБКА: Недостаточно бронетехники (%d/%d)." % [player_state.heavy_equipment_stockpile, tanks]}
	if player_state.liquid_reserves_billions < cash_billions:
		return {"success": false, "message": "ОШИБКА: Недостаточно ликвидных резервов ($%.2fB/$%.2fB)." % [player_state.liquid_reserves_billions, cash_billions]}

	player_state.infantry_weapons_stockpile -= weapons
	player_state.heavy_equipment_stockpile -= tanks
	player_state.liquid_reserves_billions -= cash_billions

	var p = manager.proxy_wars[proxy_key]
	p["weapons_delivered"] += weapons
	p["tanks_delivered"] += tanks
	p["funded_billions"] += cash_billions

	var relief = float(weapons) * 0.002 + float(tanks) * 0.04 + cash_billions * 4.0
	p["tension"] = maxf(0.0, p["tension"] - relief)

	player_state.legitimacy = clampf(player_state.legitimacy + 1.5, 0.0, 100.0)
	if "war_support_percent" in player_state:
		player_state.war_support_percent = clampf(player_state.war_support_percent + 1.0, 0.0, 100.0)

	# Развертывание ТВД в MilitaryEngine при отправке ленд-лиза
	if manager.turn_manager_ref != null:
		var front = MilitaryEngine.deploy_proxy_theater(proxy_key, player_state.country_tag, manager.turn_manager_ref.countries_world_state)
		if front != null and front.axes.size() > 0:
			var ax = front.axes[0]
			ax.assigned_equipment["infantry_weapons"] = ax.assigned_equipment.get("infantry_weapons", 0) + weapons
			ax.assigned_equipment["heavy_equipment"] = ax.assigned_equipment.get("heavy_equipment", 0) + tanks

	manager.proxy_lend_lease_delivered.emit(proxy_key, weapons, tanks, cash_billions)
	print("[GCWManager] Lend-Lease dispatched to %s: %d rifles, %d tanks, $%.2fB." % [p["name"], weapons, tanks, cash_billions])
	return {
		"success": true,
		"message": "Эшелон ленд-лиза успешно доставлен в %s: %d винтовок, %d танков, $%.2fB." % [p["name"], weapons, tanks, cash_billions]
	}


"""Изменение шкалы боеготовности DEFCON.
"""
static func adjust_defcon(manager: GermanCivilWarManager, new_level: int, reason: String) -> void:
	manager.current_defcon = clampi(new_level, 1, 5)
	if manager.player_state_ref != null:
		manager.player_state_ref.set_flag("defcon_level", manager.current_defcon)

	manager.defcon_alert.emit(manager.current_defcon, reason)
	print("[GCWManager] DEFCON LEVEL CHANGED: DEFCON %d! Reason: %s" % [manager.current_defcon, reason])

	if manager.current_defcon == 1 and manager.turn_manager_ref != null and manager.turn_manager_ref.event_manager != null:
		var nuke_ev = GameEvent.new()
		nuke_ev.event_id = "event_nuclear_midnight"
		nuke_ev.title = "DEFCON 1 // ЯДЕРНАЯ ПОЛНОЧЬ"
		nuke_ev.classification = "[TOP SECRET // ULTRA BRINKMANSHIP]"
		nuke_ev.description = "Красные телефоны замолчали. Спутники раннего предупреждения засекли массовый пуск МБР. Цивилизация погружается в ядерный пепел."
		nuke_ev.is_modal = true
		nuke_ev.options = [{"text": "Так проходит мирская слава... [GAME OVER]", "effects": {"SET_FLAG": "thermonuclear_war"}}]
		manager.turn_manager_ref.pending_modal_events.push_front(nuke_ev)
