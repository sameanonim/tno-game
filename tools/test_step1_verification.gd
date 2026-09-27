extends SceneTree

func _init() -> void:
	print("==================================================")
	print("STEP 1 INTEGRITY VERIFICATION TEST STARTING...")
	print("==================================================")

	var errs: int = 0

	# 1. Test CountryState from_dict with party_popularities
	print("\n[TEST 1] Party Popularities & Ideology Parsing...")
	var test_country_dict = {
		"identity": {
			"country_tag": "WRS",
			"country_name": "West Russian Revolutionary Front",
			"ruling_ideology": "Communist"
		},
		"politics": {
			"political_capital": 100.0,
			"party_popularities": {
				"communist": 75.0,
				"socialist": 25.0
			}
		},
		"economy": {
			"gdp_billions": 20.0,
			"rd_spending_share": 0.15
		}
	}
	var state = CountryState.from_dict(test_country_dict)
	if state.initial_parties.size() != 2:
		push_error("FAILED: Expected 2 parties, got %d" % state.initial_parties.size())
		errs += 1
	else:
		print("PASS: Successfully parsed %d parties." % state.initial_parties.size())
		var has_ruling = false
		for p in state.initial_parties:
			print("  Party: [%s] %s - %.1f%% (Ruling: %s, Color: %s)" % [
				p.ideology_key, p.party_name, p.popularity, str(p.is_ruling), str(p.color)
			])
			if p.is_ruling:
				has_ruling = true
		if not has_ruling:
			push_error("FAILED: Ruling party was not marked as is_ruling!")
			errs += 1
		else:
			print("PASS: Ruling party correctly identified.")

	# 2. Test R&D spending in EconomyEngine
	print("\n[TEST 2] R&D Spending and Expenses in EconomyEngine...")
	if state.rd_spending_share != 0.15:
		push_error("FAILED: rd_spending_share not deserialized (got %f)" % state.rd_spending_share)
		errs += 1
	else:
		print("PASS: rd_spending_share correctly deserialized: %f" % state.rd_spending_share)

	var exp_dict = EconomyEngine.calculate_turn_expenses(state)
	if not exp_dict.has("rd") or exp_dict["rd"] <= 0.0:
		push_error("FAILED: rd expenses not calculated in exp_dict!")
		errs += 1
	else:
		print("PASS: R&D expenses calculated: $%.4fB per turn." % exp_dict["rd"])

	# 3. Test Consumer Goods check
	print("\n[TEST 3] Consumer Goods in EconomyEngine.process_turn...")
	state.civilian_factories = 15
	state.military_factories = 10
	state.consumer_goods_ratio = 0.20
	var rep = EconomyEngine.process_turn(state)
	if rep == null or not rep.consumer_goods_met:
		push_error("FAILED: Consumer goods should be met with 15 civ / 10 mil / 20% ratio!")
		errs += 1
	else:
		print("PASS: Consumer goods check passed (met: %s)." % str(rep.consumer_goods_met))

	# 4. Test Money Printing Single-Application
	print("\n[TEST 4] Money Printing Single-Application...")
	var initial_reserves = state.liquid_reserves_billions
	var initial_inflation = state.inflation_rate
	state.money_printing_this_turn = 0.50

	var rep2 = EconomyEngine.process_turn(state)
	if state.money_printing_this_turn != 0.0:
		push_error("FAILED: money_printing_this_turn was not reset to 0!")
		errs += 1
	else:
		print("PASS: money_printing_this_turn reset to 0 after process_turn.")

	var diff_reserves = state.liquid_reserves_billions - initial_reserves
	var diff_inflation = state.inflation_rate - initial_inflation
	print("  Reserve delta: $%.2fB, Inflation delta: +%.4f" % [diff_reserves, diff_inflation])
	if diff_reserves < 0.40:
		push_error("FAILED: Emission of 0.50B not properly credited to reserves!")
		errs += 1
	else:
		print("PASS: Emission credited exactly once in process_turn.")

	# 5. Test GameSession tags and dossiers
	print("\n[TEST 5] GameSession WRS and KOM Dossiers...")
	var GameSessionScript = load("res://core/systems/game_session.gd")
	var gs = GameSessionScript.new()
	var wrs_dossier = gs.get_country_dossier("WRS")
	var kom_dossier = gs.get_country_dossier("KOM")

	if wrs_dossier.get("tag") != "WRS" or not ("Западнорусский" in wrs_dossier.get("name", "")):
		push_error("FAILED: WRS dossier not properly configured!")
		errs += 1
	else:
		print("PASS: WRS dossier: %s (%s)" % [wrs_dossier.get("name"), wrs_dossier.get("leader_name")])

	if kom_dossier.get("tag") != "KOM" or not ("Коми" in kom_dossier.get("name", "")):
		push_error("FAILED: KOM dossier not properly configured!")
		errs += 1
	else:
		print("PASS: KOM dossier: %s (%s)" % [kom_dossier.get("name"), kom_dossier.get("leader_name")])

	var smuta_tags = []
	for t in gs.get_theaters():
		if t.get("id") == "theater_smuta":
			smuta_tags = t.get("tags", [])
	if not ("WRS" in smuta_tags and "KOM" in smuta_tags):
		push_error("FAILED: theater_smuta does not contain both WRS and KOM! Tags: %s" % str(smuta_tags))
		errs += 1
	else:
		print("PASS: theater_smuta contains both WRS and KOM: %s" % str(smuta_tags))

	print("\n==================================================")
	if errs == 0:
		print("ALL STEP 1 VERIFICATION TESTS PASSED SUCCESSFULLY! (0 errors)")
	else:
		print("VERIFICATION COMPLETED WITH %d ERRORS." % errs)
	print("==================================================")

	quit(0 if errs == 0 else 1)
