class_name TestParliamentEngine
extends TNOSimpleTest

##
## TestParliamentEngine: Юнит-тесты парламентского движка TNO (Рейхстаг, коалиции, сделки, голосование)
## ==============================================================================

var parliament: ParliamentEngine
var state: CountryState


func setup() -> void:
	parliament = ParliamentEngine.new()
	state = CountryState.new()
	state.country_tag = "GER"
	state.political_capital = 100.0
	state.current_cap = 5
	state.liquid_reserves_billions = 10.0
	state.legitimacy = 60.0
	state.radicalization = 20.0
	parliament.initialize_for_country(state)


func test_german_reichstag_initialization() -> void:
	assert_eq(parliament.country_tag, "GER", "Тег страны должен быть GER")
	assert_eq(parliament.total_seats, 500, "Рейхстаг Великой Германии должен иметь 500 мест")
	assert_true(parliament.factions.size() >= 4, "Должно быть как минимум 4 фракции")
	assert_false(parliament.active_bills.is_empty(), "Должен быть список активных законопроектов")
	assert_eq(state.total_parliament_seats, 500, "Стейт должен синхронизировать количество мест")


func test_vote_projection_calculation() -> void:
	var first_bill: ParliamentEngine.ParliamentBill = parliament.active_bills[0]
	var proj: Dictionary = parliament.calculate_vote_projection(first_bill.id)

	assert_true(proj.has("yeas"), "Проекция должна содержать 'yeas'")
	assert_true(proj.has("nays"), "Проекция должна содержать 'nays'")
	assert_true(proj.has("quorum_needed"), "Проекция должна содержать 'quorum_needed'")
	assert_eq(proj["quorum_needed"], 251, "Для большинства в 500 мест нужно 251 голос")

	var total_calculated: int = int(proj["yeas"]) + int(proj["nays"]) + int(proj["abstain"])
	assert_eq(total_calculated, 500, "Сумма голосов за, против и воздержавшихся должна равняться 500")


func test_offer_favor_compromise() -> void:
	var faction_id: String = parliament.factions[0].id
	var initial_pc: float = state.political_capital
	var res: Dictionary = parliament.offer_favor(faction_id, "compromise", state)

	assert_true(res.get("success", false), "Сделка компромисса должна успешно пройти при наличии PC")
	assert_approx_eq(state.political_capital, initial_pc - 15.0, 0.01, "Должно списаться 15 PC")
	assert_true(int(res.get("bonus_votes", 0)) > 0, "Сделка должна дать бонусные голоса")


func test_vote_execution_with_sufficient_capital() -> void:
	var first_bill: ParliamentEngine.ParliamentBill = parliament.active_bills[0]
	var init_legitimacy: float = state.legitimacy
	var vote_res: Dictionary = parliament.call_parliament_vote(first_bill.id, state)

	assert_true(vote_res.get("success", false), "Голосование должно успешно состояться при достаточных PC/CAP")
	assert_ne(state.legitimacy, init_legitimacy, "Легитимность должна измениться по итогам голосования")
