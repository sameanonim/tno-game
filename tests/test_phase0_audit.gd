class_name TestPhase0Audit
extends TNOSimpleTest

##
## TestPhase0Audit: Фаза 0 - Аудит целостности данных и Smoke-тест Game Flow
##

var content_loader: ContentLoader = null


func setup() -> void:
	content_loader = ContentLoader.new()
	content_loader.load_all()


func teardown() -> void:
	if content_loader != null:
		content_loader.free()
		content_loader = null


func test_countries_index_integrity() -> void:
	var file := FileAccess.open("res://data/countries/index.json", FileAccess.READ)
	assert_not_null(file, "index.json must exist")
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	assert_eq(err, OK, "index.json must be valid JSON")
	var data = json.data
	assert_true(data is Dictionary or data is Array, "index.json data must be Dictionary or Array")
	var tags: Dictionary = {}
	if data is Dictionary:
		var d: Dictionary = data as Dictionary
		assert_true(d.size() >= 700, "index.json should contain at least 700 countries (got %d)" % d.size())
		tags = d
	elif data is Array:
		var arr: Array = data as Array
		assert_true(arr.size() >= 700, "index.json should contain at least 700 countries (got %d)" % arr.size())
		for item in arr:
			if item is Dictionary and item.has("tag"):
				tags[item["tag"]] = true

	assert_true(tags.has("KOM"), "Tags should include KOM")
	assert_true(tags.has("GER"), "Tags should include GER")
	assert_true(tags.has("USA"), "Tags should include USA")
	assert_true(tags.has("JAP"), "Tags should include JAP")
	assert_true(tags.has("ITA"), "Tags should include ITA")


func test_major_countries_loading() -> void:
	var majors: Array[String] = ["KOM", "GER", "USA", "JAP", "ITA"]
	for tag in majors:
		var state: CountryState = content_loader.load_country_package(tag)
		assert_not_null(state, "Should load CountryState for %s" % tag)
		if state != null:
			assert_eq(state.country_tag, tag, "State tag must match %s" % tag)
			assert_true(not state.country_name.is_empty(), "%s must have non-empty name" % tag)
			assert_true(state.gdp_billions > 0.0, "%s GDP must be positive" % tag)


func test_map_manifest_and_starting_countries_sync() -> void:
	var sc_file := FileAccess.open("res://map_data/starting_countries_state.json", FileAccess.READ)
	assert_not_null(sc_file, "starting_countries_state.json must exist")
	if sc_file == null:
		return
	var sc_json := JSON.new()
	var sc_err := sc_json.parse(sc_file.get_as_text())
	sc_file.close()
	assert_eq(sc_err, OK, "starting_countries_state.json must be valid JSON")
	var sc_data: Dictionary = sc_json.data if sc_json.data is Dictionary else {}

	var mm_file := FileAccess.open("res://map_data/map_manifest.json", FileAccess.READ)
	assert_not_null(mm_file, "map_manifest.json must exist")
	if mm_file == null:
		return
	var mm_json := JSON.new()
	var mm_err := mm_json.parse(mm_file.get_as_text())
	mm_file.close()
	assert_eq(mm_err, OK, "map_manifest.json must be valid JSON")
	var mm_data: Dictionary = mm_json.data if mm_json.data is Dictionary else {}

	assert_true(sc_data.size() > 50, "starting_countries_state.json must contain countries")
	assert_true(mm_data.has("countries") or mm_data.has("states") or mm_data.has("provinces"), "map_manifest.json must contain map elements")


const GameSessionScript = preload("res://core/systems/game_session.gd")

func test_game_flow_smoke() -> void:
	# 1. Config creation
	var config = GameSessionScript.GameStartConfig.new()
	config.selected_country_tag = "KOM"
	config.difficulty = GameSessionScript.Difficulty.STRATEGIST

	# 2. Dossier retrieval
	var session = GameSessionScript.new()
	var dossier: Dictionary = session.get_country_dossier("KOM")
	assert_false(dossier.is_empty(), "KOM dossier must not be empty")
	assert_eq(dossier.get("tag"), "KOM", "Dossier tag must be KOM")

	# 3. Create player state from dossier
	var state := CountryState.new()
	state.country_tag = dossier["tag"]
	state.country_name = dossier["name"]
	state.leader_name = dossier["leader_name"]
	state.ruling_ideology = dossier["ideology"]
	state.gdp_billions = float(dossier.get("starting_gdp", 14.0))

	# 4. TurnManager setup & world data loading
	var tm := TurnManager.new()
	tm.load_world_data()
	tm.set_player_state(state)
	assert_eq(tm.player_state.country_tag, "KOM", "TM player state must be KOM")

	# 5. Advance 1 turn
	var start_turn: int = tm.current_turn
	tm.advance_turn()
	assert_eq(tm.current_turn, start_turn + 1, "Advancing turn must increment turn count")
	assert_true(tm.player_state.turn_count >= 2, "Player state turn count must be updated")

	tm.free()
	session.free()
