class_name TestPoliticalMapColors
extends TNOSimpleTest

##
## TestPoliticalMapColors: Юнит-тесты интеграции цвета страны и правящей партии на карте
##

var state: CountryState = null


func setup() -> void:
	state = CountryState.new()
	state.country_tag = "KOM"
	state.country_name = "Республика Коми"
	state.ruling_party = "Authoritarian Socialism"
	state.ruling_ideology = "Authoritarian Socialism"


func teardown() -> void:
	state = null


func test_ideology_registry_normalization() -> void:
	assert_eq(IdeologyRegistry.normalize_key("democratic"), "liberalism", "democratic must map to liberalism")
	assert_eq(IdeologyRegistry.normalize_key("communism"), "communist", "communism must map to communist")
	assert_eq(IdeologyRegistry.normalize_key("neutrality"), "paternalism", "neutrality must map to paternalism")
	assert_eq(IdeologyRegistry.normalize_key("authoritarian_socialism"), "communist", "authoritarian_socialism must map to communist")
	assert_eq(IdeologyRegistry.normalize_key("stalinism"), "communist", "stalinism must map to communist")


func test_ideology_registry_colors() -> void:
	var col_comm = IdeologyRegistry.get_color("communist")
	assert_true(col_comm.r > 0.7, "Communist color red channel must be high")

	var col_naz = IdeologyRegistry.get_color("national_socialism")
	assert_true(col_naz.r > col_naz.g, "National socialism color must be brownish-crimson")

	var col_dem = IdeologyRegistry.get_color("democratic")
	assert_true(col_dem.r > 0.8, "Democratic (liberalism) red channel must match liberalism")


func test_country_state_ruling_party_color() -> void:
	var initial_color = state.get_ruling_party_color()
	assert_not_null(initial_color, "Initial party color must not be null")
	assert_true(initial_color.r > 0.7, "Authoritarian Socialism must map to reddish communist palette")

	var sig_box := {
		"emitted": false,
		"party": "",
		"color": Color.BLACK
	}
	state.ruling_party_changed.connect(func(party, col):
		sig_box["emitted"] = true
		sig_box["party"] = party
		sig_box["color"] = col
	)

	state.set_ruling_party("national_socialism")
	assert_true(sig_box["emitted"], "ruling_party_changed signal must be emitted")
	assert_eq(sig_box["party"], "national_socialism", "Signal must deliver new party key")
	assert_approx_eq(state.country_color.r, sig_box["color"].r, 0.001, "Country color must be updated to ruling party color")


func test_map_lut_pipeline_resolution() -> void:
	var provinces_data = {
		1: {"id": 1, "owner": "KOM"},
		2: {"id": 2, "owner": "GER"}
	}
	var ger_state = CountryState.new()
	ger_state.country_tag = "GER"
	ger_state.ruling_party = "national_socialism"

	var world_state = {
		"KOM": state,
		"GER": ger_state
	}

	var lut_size = Vector2i(4096, 1)
	var pol_res = MapLUTPipeline.setup_political_lut(
		lut_size,
		provinces_data,
		{},
		Color(0.2, 0.2, 0.2, 1.0),
		world_state
	)

	var img: Image = pol_res["image"]
	assert_not_null(img, "LUT Image must be created")

	var p1_col = img.get_pixel(1, 0)
	var p2_col = img.get_pixel(2, 0)

	var expected_kom = state.get_ruling_party_color()
	var expected_ger = ger_state.get_ruling_party_color()

	assert_approx_eq(p1_col.r, expected_kom.r, 0.01, "Province 1 color must match KOM ruling party color")
	assert_approx_eq(p2_col.r, expected_ger.r, 0.01, "Province 2 color must match GER ruling party color")
