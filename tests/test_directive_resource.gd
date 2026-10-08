class_name TestDirectiveResource
extends TNOSimpleTest

##
## TestDirectiveResource: Юнит-тесты ресурса национальных директив
##

var state: CountryState = null
var directive: DirectiveResource = null


func setup() -> void:
	state = CountryState.new()
	state.country_tag = "KOM"
	state.current_cap = 5
	state.political_capital = 50.0
	state.liquid_reserves_billions = 2.0

	directive = DirectiveResource.new()
	directive.id = "test_directive_alpha"
	directive.title = "Тестовая директива Альфа"
	directive.turns_to_complete = 5
	directive.turns_remaining = 5
	directive.cost_initial_cap = 1
	directive.cost_initial_pc = 15.0


func teardown() -> void:
	state = null
	directive = null


func test_directive_initial_state() -> void:
	assert_eq(directive.id, "test_directive_alpha", "ID must match initial setting")
	assert_eq(directive.turns_to_complete, 5, "Turns to complete must match")
	assert_eq(directive.turns_remaining, 5, "Turns remaining must match")


func test_can_start_basic_allowed() -> void:
	var dossier = directive.can_be_started(state)
	assert_true(dossier.get("allowed", false), "Directive must be allowed when requirements are met")


func test_can_start_insufficient_cap() -> void:
	state.current_cap = 0
	var dossier = directive.can_be_started(state)
	assert_false(dossier.get("allowed", true), "Directive must not be allowed when CAP is insufficient")


func test_can_start_insufficient_pc() -> void:
	state.political_capital = 5.0 # Требуется 15.0
	var dossier = directive.can_be_started(state)
	assert_false(dossier.get("allowed", true), "Directive must not be allowed when PC is insufficient")


func test_prerequisites_blocking() -> void:
	directive.prerequisites = ["prereq_focus_1"]
	var dossier = directive.can_be_started(state)
	assert_false(dossier.get("allowed", true), "Directive must be blocked if prereq is not completed")

	state.completed_directives.append("prereq_focus_1")
	var dossier_after = directive.can_be_started(state)
	assert_true(dossier_after.get("allowed", false), "Directive must be allowed once prereq is in completed list")


func test_mutually_exclusive_locking() -> void:
	directive.mutually_exclusive = ["rival_directive_beta"]
	state.completed_directives.append("rival_directive_beta")
	var dossier = directive.can_be_started(state)
	assert_false(dossier.get("allowed", true), "Directive must be blocked if mutually exclusive rival is completed")
