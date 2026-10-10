class_name TerminalMapHUDController
extends Node

##
## TerminalMapHUDController: Контроллер HUD карты, инспектора и тактических операций
## ==============================================================================
## Отвечает за:
## 1. Режимы карты (Политический, ВПК, Недовольство, Дипломатия/Сферы).
## 2. Фокусировку домена правителя (Ruler Domain) и режим набегов Смуты.
## 3. Инспекцию провинций (ProvinceInspectorPanel) и мост к управлению (RegionManagementPanel).
## 4. Расчет шансов и проведение тактических набегов (RaidPlanningPanel).
## ==============================================================================

signal hud_updated()
signal log_message_posted(msg: String)
signal sound_effect_requested(sfx_name: String, pitch: float)

var map_controller: MapController = null
var turn_manager: TurnManager = null
var province_inspector: ProvinceInspectorPanel = null
var region_management: RegionManagementPanel = null

var raid_panel: PanelContainer = null
var raid_panel_info: RichTextLabel = null
var btn_panel_recon: Button = null
var btn_panel_heavy: Button = null
var btn_panel_cancel: Button = null

var btn_map_pol: Button = null
var btn_map_econ: Button = null
var btn_map_unrest: Button = null
var btn_map_diplo: Button = null
var btn_ruler_focus: Button = null
var btn_raid_toggle: Button = null

var is_raid_mode_active: bool = false
var planned_raid_region_id: int = 0


func setup(
	p_map_controller: MapController,
	p_turn_manager: TurnManager,
	p_province_inspector: ProvinceInspectorPanel,
	p_region_management: RegionManagementPanel,
	p_raid_panel: PanelContainer,
	p_raid_info: RichTextLabel,
	p_btn_recon: Button,
	p_btn_heavy: Button,
	p_btn_cancel: Button,
	map_mode_buttons: Dictionary
) -> void:
	map_controller = p_map_controller
	turn_manager = p_turn_manager
	province_inspector = p_province_inspector
	region_management = p_region_management
	raid_panel = p_raid_panel
	raid_panel_info = p_raid_info
	btn_panel_recon = p_btn_recon
	btn_panel_heavy = p_btn_heavy
	btn_panel_cancel = p_btn_cancel

	btn_map_pol = map_mode_buttons.get("pol")
	btn_map_econ = map_mode_buttons.get("econ")
	btn_map_unrest = map_mode_buttons.get("unrest")
	btn_map_diplo = map_mode_buttons.get("diplo")
	btn_ruler_focus = map_mode_buttons.get("ruler")
	btn_raid_toggle = map_mode_buttons.get("raid")

	_bind_map_buttons()
	_bind_panels()


func _bind_map_buttons() -> void:
	if btn_map_pol != null:
		btn_map_pol.pressed.connect(func():
			if map_controller != null: map_controller.set_map_mode(0)
			sound_effect_requested.emit("switch_click", 900.0)
			if has_node("/root/AudioManager"):
				get_node("/root/AudioManager").play_sfx("ui_mapmode_land")
		)
	if btn_map_econ != null:
		btn_map_econ.pressed.connect(func():
			if map_controller != null: map_controller.set_map_mode(1)
			sound_effect_requested.emit("switch_click", 950.0)
			if has_node("/root/AudioManager"):
				get_node("/root/AudioManager").play_sfx("ui_mapmode_land")
		)
	if btn_map_unrest != null:
		btn_map_unrest.pressed.connect(func():
			if map_controller != null: map_controller.set_map_mode(2)
			sound_effect_requested.emit("switch_click", 1000.0)
			if has_node("/root/AudioManager"):
				get_node("/root/AudioManager").play_sfx("ui_mapmode_land")
		)
	if btn_map_diplo != null:
		btn_map_diplo.pressed.connect(func():
			if map_controller != null: map_controller.set_map_mode(3)
			sound_effect_requested.emit("switch_click", 1050.0)
			if has_node("/root/AudioManager"):
				get_node("/root/AudioManager").play_sfx("ui_mapmode_land")
		)

	if btn_ruler_focus != null:
		btn_ruler_focus.pressed.connect(func():
			if map_controller != null:
				map_controller.toggle_ruler_domain_focus()
				btn_ruler_focus.text = tr("[ ПРАВИТЕЛЬ: АКТИВЕН ]") if map_controller.is_ruler_domain_focus else tr("[ ПРАВИТЕЛЬ: ВЫКЛ ]")
			sound_effect_requested.emit("switch_click", 1150.0)
		)

	if btn_raid_toggle != null:
		btn_raid_toggle.pressed.connect(func():
			is_raid_mode_active = not is_raid_mode_active
			btn_raid_toggle.text = tr("[ РЕЙД: АКТИВЕН ]") if is_raid_mode_active else tr("[ РЕЙД: ВЫКЛ ]")
			sound_effect_requested.emit("switch_click", 950.0)
			log_message_posted.emit("РЕЖИМ НАБЕГОВ СМУТЫ: " + ("АКТИВИРОВАН. Выберите вражеский регион на карте." if is_raid_mode_active else "ОТКЛЮЧЕН."))
		)

	if btn_panel_recon != null:
		btn_panel_recon.pressed.connect(func(): execute_context_raid("recon"))
	if btn_panel_heavy != null:
		btn_panel_heavy.pressed.connect(func(): execute_context_raid("heavy"))
	if btn_panel_cancel != null:
		btn_panel_cancel.pressed.connect(func():
			if raid_panel != null: raid_panel.visible = false
		)


func _bind_panels() -> void:
	if region_management != null:
		region_management.invest_infrastructure_requested.connect(func(_pid):
			hud_updated.emit()
			if map_controller != null and turn_manager != null:
				map_controller.populate_data_lut_from_regions(turn_manager.regions_world_state, turn_manager.player_state.country_tag)
			if province_inspector != null and province_inspector.visible:
				province_inspector._update_display()
			sound_effect_requested.emit("switch_click", 800.0)
		)
		region_management.suppress_unrest_requested.connect(func(_pid):
			hud_updated.emit()
			if map_controller != null and turn_manager != null:
				map_controller.populate_data_lut_from_regions(turn_manager.regions_world_state, turn_manager.player_state.country_tag)
			if province_inspector != null and province_inspector.visible:
				province_inspector._update_display()
			sound_effect_requested.emit("switch_click", 750.0)
		)
		region_management.convert_military_requested.connect(func(_pid):
			hud_updated.emit()
			if map_controller != null and turn_manager != null:
				map_controller.populate_data_lut_from_regions(turn_manager.regions_world_state, turn_manager.player_state.country_tag)
			if province_inspector != null and province_inspector.visible:
				province_inspector._update_display()
			sound_effect_requested.emit("switch_click", 900.0)
		)
		region_management.garrison_reinforce_requested.connect(func(_pid):
			hud_updated.emit()
			if province_inspector != null and province_inspector.visible:
				province_inspector._update_display()
			sound_effect_requested.emit("switch_click", 850.0)
		)

	if province_inspector != null:
		province_inspector.open_region_management_requested.connect(func(_sid):
			if region_management != null and turn_manager != null:
				var pid = province_inspector.current_province_id
				var reg_obj: RegionData = turn_manager.regions_world_state.get(pid)
				if reg_obj == null:
					reg_obj = RegionData.new()
					reg_obj.province_id = pid
					reg_obj.province_name = "Регион #%d" % pid
					reg_obj.owner_tag = turn_manager.player_state.country_tag
					turn_manager.regions_world_state[pid] = reg_obj
				region_management.setup_for_region(reg_obj, turn_manager.player_state)
				sound_effect_requested.emit("switch_click", 1100.0)
		)
		province_inspector.plan_raid_target_requested.connect(func(pid):
			is_raid_mode_active = true
			if btn_raid_toggle != null:
				btn_raid_toggle.text = tr("[ РЕЙД: АКТИВЕН ]")
			var p_data = map_controller.get_province_data(pid) if map_controller != null else {}
			open_raid_planning_panel(pid, p_data)
			sound_effect_requested.emit("alarm_buzz", 520.0)
		)


func handle_province_click(pid: int, data: Dictionary) -> void:
	if turn_manager == null:
		return

	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("click_province")

	var prov_owner = data.get("owner", "NEU")
	var is_player = (prov_owner == turn_manager.player_state.country_tag)

	if is_raid_mode_active and not is_player:
		if province_inspector != null:
			province_inspector.visible = false
		open_raid_planning_panel(pid, data)
		sound_effect_requested.emit("alarm_buzz", 520.0)
	else:
		if raid_panel != null:
			raid_panel.visible = false
		if province_inspector != null and map_controller != null:
			var reg_obj: RegionData = turn_manager.regions_world_state.get(pid, null)
			province_inspector.inspect_province(pid, map_controller.province_features_data, turn_manager.player_state.country_tag, reg_obj)
		sound_effect_requested.emit("switch_click", 1000.0)


func open_raid_planning_panel(region_id: int, data: Dictionary) -> void:
	planned_raid_region_id = region_id
	if turn_manager == null:
		return

	var reg_obj: RegionData = turn_manager.regions_world_state.get(region_id)
	if reg_obj == null:
		reg_obj = RegionData.new()
		reg_obj.province_id = region_id
		reg_obj.province_name = data.get("name", "Регион #%d" % region_id)
		reg_obj.owner_tag = data.get("owner", "NEU")
		reg_obj.garrison_strength = 60.0
		reg_obj.industrial_capacity = int(data.get("ic", 2))
		reg_obj.civilian_infrastructure = int(data.get("infra", 2))
		reg_obj.terrain_type = data.get("terrain", "plains")
		turn_manager.regions_world_state[region_id] = reg_obj

	var reg_name = reg_obj.province_name
	var owner_tag = reg_obj.owner_tag
	var garrison = int(reg_obj.garrison_strength)
	var ic = reg_obj.industrial_capacity
	var infra = reg_obj.civilian_infrastructure
	var t_type = reg_obj.terrain_type

	var p_state = turn_manager.player_state
	var readiness = p_state.army_readiness if p_state != null else 50.0
	var morale = p_state.army_morale if p_state != null else 50.0
	var weapons = p_state.infantry_weapons_stockpile if p_state != null else 0
	var manpower = p_state.manpower_pool if p_state != null else 0

	var terrain_mult: float = 1.0
	match t_type.to_lower():
		"forest": terrain_mult = 1.2
		"marsh": terrain_mult = 1.4
		"mountains": terrain_mult = 1.6
		"urban": terrain_mult = 1.5
	var def_power: float = (float(garrison) * terrain_mult) + (float(infra) * 3.0)

	var atk_recon: float = (readiness * 0.6 + morale * 0.4) * 0.5
	var ratio_recon = atk_recon / maxf(def_power, 1.0)
	var chance_recon = clampi(int(round(ratio_recon * 80.0)), 10, 95)

	var atk_heavy: float = (readiness * 0.6 + morale * 0.4) * 2.0
	var ratio_heavy = atk_heavy / maxf(def_power, 1.0)
	var chance_heavy = clampi(int(round(ratio_heavy * 85.0)), 15, 99)

	var has_recon_wep = weapons >= 100 and manpower >= 150
	var has_heavy_wep = weapons >= 500 and manpower >= 1000

	if btn_panel_recon != null:
		btn_panel_recon.disabled = not has_recon_wep
		btn_panel_recon.text = ("> Разведка боем (%d%%)" % chance_recon) if has_recon_wep else "> Разведка (НЕДОСТАТОЧНО СИЛ)"
	if btn_panel_heavy != null:
		btn_panel_heavy.disabled = not has_heavy_wep
		btn_panel_heavy.text = ("> Тяжелый набег (%d%%)" % chance_heavy) if has_heavy_wep else "> Набег (НЕДОСТАТОЧНО СИЛ)"

	var recon_col = "#33ff66" if chance_recon >= 60 else ("#ffcc00" if chance_recon >= 40 else "#ff5555")
	var heavy_col = "#33ff66" if chance_heavy >= 60 else ("#ffcc00" if chance_heavy >= 40 else "#ff5555")

	if raid_panel_info != null:
		var info_fmt = """[b][color=#00e5ff]СЕКТОР ОПЕРАЦИИ:[/color][/b] %s [PID: %d] | [color=#aaaaaa]ВЛАДЕЛЕЦ:[/color] [color=#ffcc00]%s[/color]
[color=#aaaaaa]МЕСТНОСТЬ:[/color] %s | [color=#ff5555]ГАРНИЗОН:[/color] %d%% | [color=#33ff66]IC:[/color] %d | [color=#00e5ff]ИНФРА:[/color] %d/10

[b][color=#ffd133]══ ВАРИАНТЫ УДАРА ══[/color][/b]
• [color=#66bbff]1. РАЗВЕДКА БОЕМ:[/color] Шанс: [color=%s]%d%%[/color] (100 винтовок, 150 бойцов)
• [color=#ffaa33]2. ТЯЖЕЛЫЙ НАБЕГ:[/color] Шанс: [color=%s]%d%%[/color] (500 винтовок, 1 000 бойцов)
[color=#88ccff]Ожидаемые трофеи:[/color] до $0.15B казны, до 450 винтовок, военнопленные."""
		raid_panel_info.text = info_fmt % [
			reg_name, region_id, owner_tag,
			t_type.capitalize(), garrison, ic, infra,
			recon_col, chance_recon,
			heavy_col, chance_heavy
		]

	if raid_panel != null:
		raid_panel.visible = true

	if map_controller != null:
		var target_centroid = map_controller.get_province_centroid(region_id)
		map_controller.set_active_theater_radar(target_centroid, 0.22)


func execute_context_raid(intensity: String) -> void:
	if raid_panel != null:
		raid_panel.visible = false
	if turn_manager == null:
		return

	var reg_obj: RegionData = turn_manager.regions_world_state.get(planned_raid_region_id)
	if reg_obj == null:
		reg_obj = RegionData.new()
		reg_obj.province_id = planned_raid_region_id
		reg_obj.province_name = "Target Sector #%d" % planned_raid_region_id
		reg_obj.garrison_strength = 60.0
		reg_obj.industrial_capacity = 2
		reg_obj.owner_tag = "ONG"
		turn_manager.regions_world_state[planned_raid_region_id] = reg_obj

	var res = MilitaryEngine.execute_border_raid(turn_manager.player_state, reg_obj, intensity, turn_manager.current_turn)
	var staging_id = get_player_staging_province_for_target(planned_raid_region_id)

	if map_controller != null:
		map_controller.add_combat_incident_ping(planned_raid_region_id, "raid")
		map_controller.add_raid_corridor(staging_id, planned_raid_region_id, intensity)
		map_controller.populate_data_lut_from_regions(turn_manager.regions_world_state, turn_manager.player_state.country_tag)

	sound_effect_requested.emit("alarm_buzz", 440.0)
	log_message_posted.emit("РЕЗУЛЬТАТ НАБЕГА: " + res.narrative_summary)
	hud_updated.emit()


func get_player_staging_province_for_target(target_pid: int) -> int:
	var p_tag = turn_manager.player_state.country_tag if turn_manager != null and turn_manager.player_state != null else ""
	if p_tag.is_empty():
		return target_pid

	if turn_manager != null and turn_manager.boundary_manager != null:
		var bm = turn_manager.boundary_manager
		if bm.province_adjacency.has(target_pid):
			for n_id in bm.province_adjacency[target_pid]:
				var nid_int = int(n_id)
				var reg = turn_manager.regions_world_state.get(nid_int)
				if reg is RegionData and reg.owner_tag == p_tag:
					return nid_int

	var best_pid = 0
	var min_dist = INF
	var target_pos = map_controller.get_province_centroid(target_pid) if map_controller != null else Vector2.ZERO

	if turn_manager != null:
		for reg in turn_manager.regions_world_state.values():
			if reg is RegionData and reg.owner_tag == p_tag:
				if map_controller != null and map_controller.province_centroids.has(reg.province_id):
					var p_pos = map_controller.province_centroids[reg.province_id]
					var dist = p_pos.distance_to(target_pos)
					if dist < min_dist:
						min_dist = dist
						best_pid = reg.province_id
				elif best_pid == 0:
					best_pid = reg.province_id

	if best_pid > 0:
		return best_pid

	return target_pid


func close_all_overlays() -> void:
	if province_inspector != null and province_inspector.visible:
		province_inspector.visible = false
	if region_management != null and region_management.visible:
		region_management.visible = false
	if raid_panel != null and raid_panel.visible:
		raid_panel.visible = false
