class_name MilitaryTheaterFactory
extends RefCounted

##
## MilitaryTheaterFactory: Фабрика динамического развертывания стратегических ТВД
##
## Отвечает за:
## 1. Процедурное создание и развертывание стартовых стратегических фронтов (Frontline)
##    и оперативных осей (OperationalAxis) под выбранную игроком сверхдержаву или варлорда.
## 2. Инициализацию командиров (LeaderResource) с аутентичными трейтами TNO.
## 3. Развертывание глобальных прокси-театров (SAW, Малайя, Индонезия, Ближний Восток).
##

## Развертывание начального стратегического фронта для державы игрока
static func deploy_starting_theater(state: CountryState, countries_world_state: Dictionary) -> Frontline:
	if state == null:
		return null

	MilitaryEngine.clear_frontlines()

	var tag = state.country_tag.to_upper()
	var is_warlord = RussianUnificationManager.is_warlord(tag)
	var is_german = tag in ["GER", "BOR", "SPE", "GOR", "HEY", "BGR", "SGR", "GGR", "HGR"]
	var is_usa = (tag == "USA")

	if is_warlord:
		return _deploy_warlord_theater(tag, state, countries_world_state)
	elif is_german:
		return _deploy_german_theater(tag, state, countries_world_state)
	elif is_usa:
		return _deploy_usa_theater(tag, state, countries_world_state)
	else:
		return _deploy_generic_theater(tag, state, countries_world_state)


## Развертывание глобального прокси-театра Холодной войны
static func deploy_proxy_theater(
	proxy_id: String,
	superpower_tag: String,
	countries_world_state: Dictionary
) -> Frontline:
	var front_id = "proxy_" + proxy_id.to_lower()
	var existing = MilitaryEngine.get_frontline(front_id)
	if existing != null:
		return existing

	var front_title = "Global Proxy Theater"
	var axis_title = "Strategic Axis"
	var attacker_tag = superpower_tag
	var defender_tag = "NEU"
	var defender_name = "Opposing Proxy Coalition"
	var regions: Array = []
	var cmd_name = "Field Commander"
	var cmd_trait = "proxy_warfare_expert"
	var cmd_skill = 7

	match proxy_id:
		"south_africa":
			front_title = "South African War - International Expeditionary Theater"
			axis_title = "Cape-Transvaal Strategic Axis"
			attacker_tag = superpower_tag if not superpower_tag.is_empty() else "USA"
			defender_tag = "ANG"
			defender_name = "Afrika-Schild / Boers"
			regions = [12000, 12050]
			cmd_name = "Creighton Abrams" if attacker_tag == "USA" else "Hans von Luck"
			cmd_trait = "combined_arms_doctrine"
			cmd_skill = 8

		"middle_east":
			front_title = "Middle East Oil Crisis - Levant Theater"
			axis_title = "Suez & Gulf Petroleum Corridor"
			attacker_tag = superpower_tag if not superpower_tag.is_empty() else "GER"
			defender_tag = "IRQ"
			defender_name = "Ba'athist Revolutionary Vanguard"
			regions = [8500, 8520]
			cmd_name = "Hasso von Manteuffel" if attacker_tag in ["GER", "BOR", "SPE"] else "Norman Schwarzkopf"
			cmd_trait = "desert_warfare_tactician"
			cmd_skill = 7

		"malaya":
			front_title = "Malayan Emergency - Jungle Counter-Insurgency"
			axis_title = "Perak-Johor Jungle Operations"
			attacker_tag = superpower_tag if not superpower_tag.is_empty() else "USA"
			defender_tag = "MLY"
			defender_name = "Malayan National Liberation Army (MNLA)"
			regions = [11400, 11425]
			cmd_name = "Walter Walker"
			cmd_trait = "jungle_infiltrator"
			cmd_skill = 7

		"indonesia":
			front_title = "Indonesian Civil War - Archipelago Operations"
			axis_title = "Java-Sumatra Strategic Axis"
			attacker_tag = superpower_tag if not superpower_tag.is_empty() else "USA"
			defender_tag = "INS"
			defender_name = "Free Indonesia Insurgent Front"
			regions = [11550, 11580]
			cmd_name = "Alexander Haig"
			cmd_trait = "amphibious_specialist"
			cmd_skill = 7

	return create_and_register_theater(
		front_title,
		axis_title,
		attacker_tag,
		defender_tag,
		defender_name,
		regions,
		cmd_name,
		cmd_trait,
		cmd_skill,
		countries_world_state,
		front_id
	)


static func _deploy_warlord_theater(
	tag: String,
	state: CountryState,
	countries_world_state: Dictionary
) -> Frontline:
	var macro = RussianUnificationManager.get_macro_region(tag)
	var enemy_tag = "ONG"
	var enemy_name = "Onega Garrison"
	var front_title = "Western Russia Unification Theater"
	var axis_title = "Onega Strategic Spearhead"
	var target_regions: Array = [9248, 9273]
	var commander_name = "Mikhail Tukhachevsky"
	var commander_trait = "deep_battle_theorist"
	var commander_skill = 8

	match macro:
		RussianUnificationManager.MACRO_WEST_RUSSIA:
			if tag == "WRS":
				enemy_tag = "ONG"
				enemy_name = "Onega Garrison"
				front_title = "Western Russia Unification Theater"
				axis_title = "Onega Strategic Spearhead"
				target_regions = [9248, 9273]
				commander_name = "Mikhail Tukhachevsky"
				commander_trait = "deep_battle_theorist"
				commander_skill = 8
			elif tag == "KOM":
				enemy_tag = "VYT"
				enemy_name = "Vyatka Principality"
				front_title = "Northern Dvina Liberation Theater"
				axis_title = "Vyatka Security Axis"
				target_regions = [9120, 9155]
				commander_name = "Nikolai Krylov"
				commander_trait = "flexible_planner"
				commander_skill = 7
			elif tag == "VYT":
				enemy_tag = "SAM"
				enemy_name = "Committee of Liberation (ROA)"
				front_title = "Imperial Reconquest Theater"
				axis_title = "Samara Operational Axis"
				target_regions = [9180, 9200]
				commander_name = "Vladimir Romanov"
				commander_trait = "monarchist_vanguard"
				commander_skill = 6
			elif tag == "SAM":
				enemy_tag = "WRS"
				enemy_name = "West Russian Revolutionary Front"
				front_title = "ROA Security Theater"
				axis_title = "Plesetsk Counter-Offensive"
				target_regions = [9248, 9273]
				commander_name = "Sergei Bunyachenko"
				commander_trait = "aggressive_offensive"
				commander_skill = 7
			else:
				enemy_tag = "WRS" if tag != "WRS" else "ONG"
				enemy_name = "Opposing Warlord Garrison"
				front_title = "Western Russia Operational Theater"
				axis_title = "Regional Unification Drive"
				target_regions = [9248, 9273]
				commander_name = state.leader_name
				commander_trait = "determined_commander"
				commander_skill = 6

		RussianUnificationManager.MACRO_WEST_SIBERIA:
			if tag == "OMS":
				enemy_tag = "TYM"
				enemy_name = "Tyumen Red Army"
				front_title = "Black League Siberian Reclamation"
				axis_title = "Tobolsk Breakthrough Axis"
				target_regions = [9300, 9340]
				commander_name = "Dmitry Yazov"
				commander_trait = "fanatical_disciplinarian"
				commander_skill = 9
			elif tag == "TYM":
				enemy_tag = "OMS"
				enemy_name = "Omsk All-Russian Black League"
				front_title = "Red Banner Urals Defense"
				axis_title = "Omsk Pacification Axis"
				target_regions = [9300, 9340]
				commander_name = "Lazar Kaganovich"
				commander_trait = "iron_will"
				commander_skill = 7
			elif tag == "SVR":
				enemy_tag = "TYM"
				enemy_name = "Tyumen Red Army"
				front_title = "Urals Military District Offensive"
				axis_title = "Trans-Ural Operational Spearhead"
				target_regions = [9300, 9340]
				commander_name = "Pavel Batov"
				commander_trait = "artillery_master"
				commander_skill = 8
			else:
				enemy_tag = "OMS" if tag != "OMS" else "TYM"
				enemy_name = "Siberian Opponent"
				front_title = "Western Siberian Unification Theater"
				axis_title = "Irtysh Line Axis"
				target_regions = [9300, 9340]
				commander_name = state.leader_name
				commander_trait = "determined_commander"
				commander_skill = 6

		RussianUnificationManager.MACRO_CENTRAL_SIBERIA:
			if tag == "TOM":
				enemy_tag = "NOV"
				enemy_name = "Novosibirsk Central Security"
				front_title = "Central Siberian Defense Theater"
				axis_title = "Ob River Defensive Spearhead"
				target_regions = [9380, 9410]
				commander_name = "Mikhail Kharitonov"
				commander_trait = "calculated_tactician"
				commander_skill = 7
			elif tag == "NOV":
				enemy_tag = "TOM"
				enemy_name = "Tomsk Salon Republic"
				front_title = "Central Siberian Unification Drive"
				axis_title = "Kuzbass Industrial Spearhead"
				target_regions = [9380, 9410]
				commander_name = "Alexander Pokryshkin"
				commander_trait = "air_land_integrator"
				commander_skill = 8
			else:
				enemy_tag = "TOM" if tag != "TOM" else "NOV"
				enemy_name = "Central Siberian Rival"
				front_title = "Central Siberian Operational Theater"
				axis_title = "Yenisey Operational Axis"
				target_regions = [9380, 9410]
				commander_name = state.leader_name
				commander_trait = "determined_commander"
				commander_skill = 6

		RussianUnificationManager.MACRO_FAR_EAST:
			if tag == "BRY":
				enemy_tag = "IRK"
				enemy_name = "Irkutsk Presidium (NKVD)"
				front_title = "Baikal Liberation Operational Theater"
				axis_title = "Irkutsk Revolutionary Axis"
				target_regions = [9450, 9480]
				commander_name = "Valery Sablin"
				commander_trait = "revolutionary_idealist"
				commander_skill = 7
			elif tag == "IRK":
				enemy_tag = "BRY"
				enemy_name = "Buryat Soviet Republic"
				front_title = "Presidium Pacification Theater"
				axis_title = "Ulan-Ude Security Axis"
				target_regions = [9450, 9480]
				commander_name = "Genrikh Yagoda"
				commander_trait = "state_security_iron"
				commander_skill = 7
			elif tag == "MAG":
				enemy_tag = "AMR"
				enemy_name = "All-Russian Fascist Party (Amur)"
				front_title = "Far Eastern Reclamation Theater"
				axis_title = "Amur River Spearhead"
				target_regions = [9480, 9510]
				commander_name = "Mikhail Matkovsky"
				commander_trait = "pragmatic_organizer"
				commander_skill = 6
			elif tag == "AMR":
				enemy_tag = "MAG"
				enemy_name = "Magadan RFP Authority"
				front_title = "Far Eastern Vanguard Theater"
				axis_title = "Okhotsk Security Axis"
				target_regions = [9480, 9510]
				commander_name = "Konstantin Rodzaevsky"
				commander_trait = "fanatical_zealot"
				commander_skill = 6
			else:
				enemy_tag = "IRK" if tag != "IRK" else "BRY"
				enemy_name = "Far East Opponent"
				front_title = "Far Eastern Unification Theater"
				axis_title = "Transbaikal Strategic Axis"
				target_regions = [9450, 9480]
				commander_name = state.leader_name
				commander_trait = "determined_commander"
				commander_skill = 6

	return create_and_register_theater(
		front_title,
		axis_title,
		tag,
		enemy_tag,
		enemy_name,
		target_regions,
		commander_name,
		commander_trait,
		commander_skill,
		countries_world_state
	)


static func _deploy_german_theater(
	tag: String,
	_state: CountryState,
	countries_world_state: Dictionary
) -> Frontline:
	var enemy_tag = "SPE" if tag in ["GER", "BOR"] else "BOR"
	var enemy_name = "Reich Civil War Contender"
	var front_title = "Grossdeutsches Reich Civil War - Operational Theater"
	var axis_title = "Berlin-Ruhr Strategic Corridor"
	var commander_name = "Hans Speidel"
	var commander_trait = "defensive_specialist"
	var commander_skill = 7

	if tag == "BOR":
		enemy_tag = "SPE"
		enemy_name = "Speer Reformist Faction"
		commander_name = "Erich Koch"
		commander_trait = "ruthless_administrator"
	elif tag == "SPE":
		enemy_tag = "BOR"
		enemy_name = "Bormann Conservative Faction"
		commander_name = "Henning von Tresckow"
		commander_trait = "reformist_tactician"
	elif tag == "GOR":
		enemy_tag = "BOR"
		enemy_name = "Bormann Conservative Faction"
		commander_name = "Ferdinand Schörner"
		commander_trait = "militarist_brute"
	elif tag == "HEY":
		enemy_tag = "BOR"
		enemy_name = "Bormann Conservative Faction"
		commander_name = "Reinhard Heydrich"
		commander_trait = "burgundian_enforcer"

	return create_and_register_theater(
		front_title,
		axis_title,
		tag,
		enemy_tag,
		enemy_name,
		[810, 835],
		commander_name,
		commander_trait,
		commander_skill,
		countries_world_state
	)


static func _deploy_usa_theater(
	tag: String,
	_state: CountryState,
	countries_world_state: Dictionary
) -> Frontline:
	return create_and_register_theater(
		"South African War - OFN Expeditionary Theater",
		"Cape-Transvaal Strategic Axis",
		tag,
		"ANG",
		"Afrika-Schild / Boers",
		[12000, 12050],
		"Creighton Abrams",
		"combined_arms_doctrine",
		8,
		countries_world_state
	)


static func _deploy_generic_theater(
	tag: String,
	state: CountryState,
	countries_world_state: Dictionary
) -> Frontline:
	return create_and_register_theater(
		"%s Operational Defense Theater" % tag,
		"Border Defense Sector",
		tag,
		"NEU",
		"Neutral Border Defense",
		[100, 101],
		state.leader_name if not state.leader_name.is_empty() else "Supreme Commander",
		"defensive_specialist",
		6,
		countries_world_state
	)


## Создание, наполнение снаряжением и регистрация стратегического фронта в MilitaryEngine
static func create_and_register_theater(
	front_title: String,
	axis_title: String,
	attacker: String,
	defender: String,
	defender_name: String,
	regions: Array,
	cmd_name: String,
	cmd_trait: String,
	cmd_skill: int,
	countries_world_state: Dictionary,
	custom_front_id: String = ""
) -> Frontline:
	if not countries_world_state.has(defender):
		var enemy_state = CountryState.new()
		enemy_state.country_tag = defender
		enemy_state.country_name = defender_name
		enemy_state.army_readiness = 65.0
		enemy_state.military_factories = 6
		countries_world_state[defender] = enemy_state

	var front = Frontline.new()
	front.front_id = custom_front_id if not custom_front_id.is_empty() else ("front_" + attacker.to_lower() + "_" + defender.to_lower())
	front.name = front_title
	front.attacker_tag = attacker
	front.defender_tag = defender

	var axis = OperationalAxis.new()
	axis.axis_id = "axis_" + attacker.to_lower() + "_spearhead"
	axis.name = axis_title
	axis.target_region_ids.assign(regions)
	axis.progress = 30.0
	axis.assigned_manpower = 25000
	axis.assigned_equipment = {"infantry_weapons": 12000, "heavy_equipment": 250}
	axis.posture = OperationalAxis.Posture.AGGRESSIVE_BREAKTHROUGH

	var cmd = LeaderResource.new()
	cmd.leader_name = cmd_name
	cmd.attack_skill = cmd_skill
	cmd.traits = [cmd_trait]
	axis.commander = cmd

	front.add_axis(axis)
	MilitaryEngine.register_frontline(front)
	return front
