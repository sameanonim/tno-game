class_name TestCountryState
extends TNOSimpleTest

##
## TestCountryState: Юнит-тесты модели геополитического состояния государства
##

var state: CountryState = null


func setup() -> void:
	state = CountryState.new()
	state.country_tag = "WRS"
	state.country_name = "Западно-Русский Революционный Фронт"
	state.leader_name = "Михаил Тухачевский"
	state.ruling_ideology = "Authoritarian Socialism"
	state.gdp_billions = 24.5
	state.national_debt_billions = 4.2
	state.liquid_reserves_billions = 1.8
	state.legitimacy = 75.0
	state.radicalization = 25.0


func teardown() -> void:
	state = null


func test_flags_lifecycle() -> void:
	assert_false(state.has_flag("smuta_raid_prepared"), "Flag should not exist initially")
	
	state.set_flag("smuta_raid_prepared", true)
	assert_true(state.has_flag("smuta_raid_prepared"), "Flag should exist after set_flag")
	assert_true(bool(state.get_flag("smuta_raid_prepared")), "Flag value should be true")

	state.set_flag("smuta_raid_prepared", false)
	assert_false(state.has_flag("smuta_raid_prepared"), "Flag set to false should report inactive in has_flag")
	assert_false(bool(state.get_flag("smuta_raid_prepared")), "Flag value should be false")


func test_serialization_roundtrip() -> void:
	state.set_flag("test_var", 42)
	state.controlled_states = [101, 102, 103]

	var serialized = state.to_dict()
	assert_true(serialized is Dictionary, "Serialized state must be Dictionary")
	assert_true(serialized.has("identity"), "Serialized state must have identity section")
	assert_eq(serialized["identity"].get("country_tag"), "WRS", "Tag must serialize correctly in identity")
	assert_approx_eq(float(serialized["economy"].get("gdp_billions")), 24.5, 0.001, "GDP must match in economy")

	var restored = CountryState.from_dict(serialized)
	assert_not_null(restored, "Restored state must not be null")
	assert_eq(restored.country_tag, "WRS", "Restored tag must match")
	assert_approx_eq(restored.gdp_billions, 24.5, 0.001, "Restored GDP must match")
	assert_eq(restored.leader_name, state.leader_name, "Restored leader must match")
	assert_true(restored.controlled_states.has(102), "Controlled states array must persist")


func test_legitimacy_and_power_values() -> void:
	assert_true(state.legitimacy >= 0.0 and state.legitimacy <= 100.0, "Legitimacy must be within 0..100")
	assert_true(state.radicalization >= 0.0 and state.radicalization <= 100.0, "Radicalization must be within 0..100")


func test_research_slots() -> void:
	var slots = state.get_total_research_slots()
	assert_true(slots >= 1, "State should have at least 1 research slot")
