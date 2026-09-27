class_name TNOEconomyScreen
extends Control

##
## TNOEconomyScreen: Полная реализация макроэкономического экрана TNO (Toolbox Theory)
##
## Включает:
## - Сводный дашборд (Реальный ВВП, Темп роста, Госдолг, Долг/ВВП, Кредитный рейтинг)
## - Сравнительный бар Сальдо (Доходы vs Расходы -> Дефицит / Профицит)
## - Слайдеры финансирования секторов (ВПК, ТНП, Госбезопасность, НИОКР)
## - Панель Центрального Банка (Процентная ставка, Инфляция, Резервы, Печатный станок)
## - Модуль стратегических ресурсов (Нефть, Сталь, Резина, Сплавы) и Торговое сальдо
## - Матрицу развития общества (Бедность, Грамотность, Коррупция, Станки)
## - Кризисный комитет (Программа Austerity, Денежная реформа)
##

signal state_modified()

@onready var lbl_gdp_val: Label = $VBox/HeaderCards/CardGDP/VBox/ValLabel
@onready var lbl_gdp_growth: Label = $VBox/HeaderCards/CardGDP/VBox/GrowthLabel

@onready var lbl_debt_val: Label = $VBox/HeaderCards/CardDebt/VBox/ValLabel
@onready var lbl_debt_ratio: Label = $VBox/HeaderCards/CardDebt/VBox/RatioLabel

@onready var lbl_credit_rating: Label = $VBox/HeaderCards/CardCredit/VBox/RatingLabel
@onready var lbl_credit_cap: Label = $VBox/HeaderCards/CardCredit/VBox/CapLabel

# Сальдо
@onready var lbl_rev_val: Label = $VBox/BalanceCard/VBox/HBox/RevVal
@onready var lbl_exp_val: Label = $VBox/BalanceCard/VBox/HBox/ExpVal
@onready var lbl_balance_status: Label = $VBox/BalanceCard/VBox/HBox/BalanceStatusLabel
@onready var balance_progress_bar: ProgressBar = $VBox/BalanceCard/VBox/BalanceProgressBar

# Слайдеры расходов
@onready var slider_mil: HSlider = $VBox/MainHBox/SpendingSection/VBox/MilRow/Slider
@onready var lbl_mil_pct: Label = $VBox/MainHBox/SpendingSection/VBox/MilRow/PctLabel

@onready var slider_civ: HSlider = $VBox/MainHBox/SpendingSection/VBox/CivRow/Slider
@onready var lbl_civ_pct: Label = $VBox/MainHBox/SpendingSection/VBox/CivRow/PctLabel

@onready var slider_admin: HSlider = $VBox/MainHBox/SpendingSection/VBox/AdminRow/Slider
@onready var lbl_admin_pct: Label = $VBox/MainHBox/SpendingSection/VBox/AdminRow/PctLabel

@onready var slider_rd: HSlider = $VBox/MainHBox/SpendingSection/VBox/RDRow/Slider
@onready var lbl_rd_pct: Label = $VBox/MainHBox/SpendingSection/VBox/RDRow/PctLabel

# Центробанк
@onready var lbl_rate_val: Label = $VBox/MainHBox/BankSection/VBox/RateBox/RateLabel
@onready var btn_rate_minus: Button = $VBox/MainHBox/BankSection/VBox/RateBox/BtnMinus
@onready var btn_rate_plus: Button = $VBox/MainHBox/BankSection/VBox/RateBox/BtnPlus

@onready var lbl_inflation_val: Label = $VBox/MainHBox/BankSection/VBox/InflationLabel
@onready var lbl_reserves_val: Label = $VBox/MainHBox/BankSection/VBox/ReservesLabel
@onready var btn_print_money: Button = $VBox/MainHBox/BankSection/VBox/BtnPrintMoney

# Стратегические ресурсы
@onready var lbl_oil: Label = $VBox/BottomHBox/ResourcesSection/VBox/ResGrid/OilLabel
@onready var lbl_steel: Label = $VBox/BottomHBox/ResourcesSection/VBox/ResGrid/SteelLabel
@onready var lbl_rubber: Label = $VBox/BottomHBox/ResourcesSection/VBox/ResGrid/RubberLabel
@onready var lbl_alloys: Label = $VBox/BottomHBox/ResourcesSection/VBox/ResGrid/AlloysLabel
@onready var lbl_trade_balance: Label = $VBox/BottomHBox/ResourcesSection/VBox/TradeBalanceLabel

# Развитие общества и антикризисный штаб
@onready var lbl_poverty: Label = $VBox/BottomHBox/SocietalSection/VBox/SocGrid/PovertyLabel
@onready var lbl_literacy: Label = $VBox/BottomHBox/SocietalSection/VBox/SocGrid/LiteracyLabel
@onready var lbl_corruption: Label = $VBox/BottomHBox/SocietalSection/VBox/SocGrid/CorruptionLabel
@onready var lbl_equipment: Label = $VBox/BottomHBox/SocietalSection/VBox/SocGrid/EquipmentLabel
@onready var btn_austerity: Button = $VBox/BottomHBox/SocietalSection/VBox/BtnBox/BtnAusterity
@onready var btn_currency_reform: Button = $VBox/BottomHBox/SocietalSection/VBox/BtnBox/BtnCurrencyReform

var current_state: CountryState = null


func _ready() -> void:
	_apply_tno_styling()
	_connect_controls()
	_refresh_metrics()


func _apply_tno_styling() -> void:
	# Стили карточек верхнего ряда
	for card in [
		$VBox/HeaderCards/CardGDP,
		$VBox/HeaderCards/CardDebt,
		$VBox/HeaderCards/CardCredit,
		$VBox/BalanceCard,
		$VBox/MainHBox/SpendingSection,
		$VBox/MainHBox/BankSection,
		$VBox/BottomHBox/ResourcesSection,
		$VBox/BottomHBox/SocietalSection
	]:
		if card is PanelContainer:
			TNOTheme.apply_panel_style(card, TNOTheme.COLOR_BORDER_DIM, TNOTheme.COLOR_BG_CARD)

	if btn_print_money != null:
		TNOTheme.apply_button_style(btn_print_money, TNOTheme.COLOR_BORDER_AMBER, Color(0.12, 0.10, 0.05, 0.95))
	if btn_rate_minus != null:
		TNOTheme.apply_button_style(btn_rate_minus, TNOTheme.COLOR_BORDER_CYAN)
	if btn_rate_plus != null:
		TNOTheme.apply_button_style(btn_rate_plus, TNOTheme.COLOR_BORDER_CYAN)
	if btn_austerity != null:
		TNOTheme.apply_button_style(btn_austerity, TNOTheme.COLOR_BORDER_AMBER, Color(0.15, 0.08, 0.08, 0.9))
	if btn_currency_reform != null:
		TNOTheme.apply_button_style(btn_currency_reform, TNOTheme.COLOR_BORDER_CYAN, Color(0.05, 0.12, 0.12, 0.9))


func _connect_controls() -> void:
	if slider_mil != null:
		slider_mil.value_changed.connect(func(val):
			if current_state != null:
				current_state.military_spending_share = val
				_refresh_metrics()
				state_modified.emit()
		)
	if slider_civ != null:
		slider_civ.value_changed.connect(func(val):
			if current_state != null:
				current_state.civilian_spending_share = val
				_refresh_metrics()
				state_modified.emit()
		)
	if slider_admin != null:
		slider_admin.value_changed.connect(func(val):
			if current_state != null:
				current_state.admin_spending_share = val
				_refresh_metrics()
				state_modified.emit()
		)
	if slider_rd != null:
		slider_rd.value_changed.connect(func(val):
			if current_state != null:
				current_state.rd_spending_share = val
				_refresh_metrics()
				state_modified.emit()
		)

	if btn_rate_minus != null:
		btn_rate_minus.pressed.connect(func():
			if current_state != null and current_state.central_bank_rate > 0.01:
				current_state.central_bank_rate -= 0.005
				_refresh_metrics()
				state_modified.emit()
		)
	if btn_rate_plus != null:
		btn_rate_plus.pressed.connect(func():
			if current_state != null and current_state.central_bank_rate < 0.25:
				current_state.central_bank_rate += 0.005
				_refresh_metrics()
				state_modified.emit()
		)

	if btn_print_money != null:
		btn_print_money.pressed.connect(func():
			if current_state != null:
				current_state.money_printing_this_turn += 0.25
				_refresh_metrics()
				state_modified.emit()
		)

	if btn_austerity != null:
		btn_austerity.pressed.connect(func():
			if current_state != null:
				EconomyEngine.toggle_austerity_program(current_state)
				_refresh_metrics()
				state_modified.emit()
		)

	if btn_currency_reform != null:
		btn_currency_reform.pressed.connect(func():
			if current_state != null:
				EconomyEngine.conduct_currency_reform(current_state)
				_refresh_metrics()
				state_modified.emit()
		)


func setup(state: CountryState) -> void:
	current_state = state
	if current_state != null:
		if slider_mil != null:
			slider_mil.value = current_state.military_spending_share
		if slider_civ != null:
			slider_civ.value = current_state.civilian_spending_share
		if slider_admin != null:
			slider_admin.value = current_state.admin_spending_share
		if slider_rd != null:
			slider_rd.value = current_state.rd_spending_share
	_refresh_metrics()


func _refresh_metrics() -> void:
	if current_state == null or lbl_gdp_val == null:
		return

	# ВВП
	lbl_gdp_val.text = "$%.2f B" % current_state.gdp_billions
	var growth_pct = current_state.real_gdp_growth * 100.0
	var sign_g = "+" if growth_pct >= 0 else ""
	lbl_gdp_growth.text = "%s%.2f%% (РЕАЛЬНЫЙ РОСТ)" % [sign_g, growth_pct]
	lbl_gdp_growth.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_GREEN if growth_pct >= 0 else TNOTheme.COLOR_TEXT_RED)

	# Госдолг
	lbl_debt_val.text = "$%.2f B" % current_state.national_debt_billions
	var ratio = current_state.get_debt_to_gdp_ratio() * 100.0
	lbl_debt_ratio.text = "ДОЛГ/ВВП: %.1f%%" % ratio

	# Кредитный рейтинг
	var rating = current_state.get_credit_rating()
	lbl_credit_rating.text = "[ %s ]" % rating
	lbl_credit_cap.text = "ЛИМИТ: $%.1f B" % (current_state.gdp_billions * 1.5)

	# Сальдо
	var revenue = current_state.calculate_total_revenue()
	var expenses = current_state.calculate_total_expenses()
	var diff = revenue - expenses

	lbl_rev_val.text = "ДОХОДЫ: $%.2f B" % revenue
	lbl_exp_val.text = "РАСХОДЫ: $%.2f B" % expenses

	if diff >= 0:
		lbl_balance_status.text = "ПРОФИЦИТ: +$%.2f B" % diff
		lbl_balance_status.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_GREEN)
	else:
		lbl_balance_status.text = "ДЕФИЦИТ: -$%.2f B" % absf(diff)
		lbl_balance_status.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_RED)

	if balance_progress_bar != null:
		var total = maxf(0.01, revenue + expenses)
		balance_progress_bar.max_value = total
		balance_progress_bar.value = revenue

	# Ползунки
	lbl_mil_pct.text = "%d%%" % int(slider_mil.value * 100)
	lbl_civ_pct.text = "%d%%" % int(slider_civ.value * 100)
	lbl_admin_pct.text = "%d%%" % int(slider_admin.value * 100)
	lbl_rd_pct.text = "%d%%" % int(slider_rd.value * 100)

	# Банк
	lbl_rate_val.text = "%.2f%%" % (current_state.central_bank_rate * 100.0)
	lbl_inflation_val.text = "ГОДОВАЯ ИНФЛЯЦИЯ: %.2f%%" % (current_state.inflation_rate * 100.0)
	lbl_reserves_val.text = "РЕЗЕРВЫ КАЗНАЧЕЙСТВА: $%.2f B" % current_state.liquid_reserves_billions

	if btn_print_money != null:
		if current_state.money_printing_this_turn > 0.0:
			btn_print_money.text = "[ ПЕЧАТНЫЙ СТАНОК: +$%.2fB В ХОД ]" % current_state.money_printing_this_turn
		else:
			btn_print_money.text = "[ ЭМИССИЯ ВАЛЮТЫ (+$0.25B) ]"

	# Стратегические ресурсы
	if lbl_oil != null:
		var p_oil = int(current_state.produced_resources.get("oil", 0))
		var c_oil = int(current_state.consumed_resources.get("oil", 0))
		var n_oil = p_oil - c_oil
		lbl_oil.text = "НЕФТЬ: %d / %d (%+d)" % [p_oil, c_oil, n_oil]
		lbl_oil.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_GREEN if n_oil >= 0 else TNOTheme.COLOR_TEXT_RED)

	if lbl_steel != null:
		var p_steel = int(current_state.produced_resources.get("steel", 0))
		var c_steel = int(current_state.consumed_resources.get("steel", 0))
		var n_steel = p_steel - c_steel
		lbl_steel.text = "СТАЛЬ: %d / %d (%+d)" % [p_steel, c_steel, n_steel]
		lbl_steel.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_GREEN if n_steel >= 0 else TNOTheme.COLOR_TEXT_RED)

	if lbl_rubber != null:
		var p_rubber = int(current_state.produced_resources.get("rubber", 0))
		var c_rubber = int(current_state.consumed_resources.get("rubber", 0))
		var n_rubber = p_rubber - c_rubber
		lbl_rubber.text = "РЕЗИНА: %d / %d (%+d)" % [p_rubber, c_rubber, n_rubber]
		lbl_rubber.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_GREEN if n_rubber >= 0 else TNOTheme.COLOR_TEXT_RED)

	if lbl_alloys != null:
		var p_alloys = int(current_state.produced_resources.get("rare_alloys", 0))
		var c_alloys = int(current_state.consumed_resources.get("rare_alloys", 0))
		var n_alloys = p_alloys - c_alloys
		lbl_alloys.text = "СПЛАВЫ: %d / %d (%+d)" % [p_alloys, c_alloys, n_alloys]
		lbl_alloys.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_GREEN if n_alloys >= 0 else TNOTheme.COLOR_TEXT_RED)

	if lbl_trade_balance != null:
		var tb = current_state.resource_trade_balance
		if tb >= 0.0:
			lbl_trade_balance.text = "САЛЬДО ЭКСПОРТА: +$%.2f B / ход" % tb
			lbl_trade_balance.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_GREEN)
		else:
			lbl_trade_balance.text = "САЛЬДО ЭКСПОРТА: -$%.2f B (ИМПОРТ)" % absf(tb)
			lbl_trade_balance.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_RED)

	# Развитие общества
	if lbl_poverty != null:
		lbl_poverty.text = "БЕДНОСТЬ: %.1f%%" % current_state.poverty_rate
		lbl_poverty.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_RED if current_state.poverty_rate > 50.0 else TNOTheme.COLOR_TEXT_AMBER)

	if lbl_literacy != null:
		lbl_literacy.text = "ГРАМОТНОСТЬ: %.1f%%" % current_state.literacy_rate
		lbl_literacy.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_GREEN if current_state.literacy_rate > 60.0 else TNOTheme.COLOR_TEXT_AMBER)

	if lbl_corruption != null:
		lbl_corruption.text = "КОРРУПЦИЯ: %.1f%%" % current_state.corruption_rate
		lbl_corruption.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_RED if current_state.corruption_rate > 40.0 else TNOTheme.COLOR_BORDER_CYAN)

	if lbl_equipment != null:
		lbl_equipment.text = "СТАНКИ: %.1f%%" % current_state.industrial_equipment_level
		lbl_equipment.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_GREEN if current_state.industrial_equipment_level > 50.0 else TNOTheme.COLOR_BORDER_CYAN)

	# Антикризисные кнопки
	if btn_austerity != null:
		if current_state.is_austerity_active:
			btn_austerity.text = "[ ЖЕСТКАЯ ЭКОНОМИЯ: ВКЛ ]"
			btn_austerity.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_RED)
		else:
			btn_austerity.text = "[ ЖЕСТКАЯ ЭКОНОМИЯ: ВЫКЛ ]"
			btn_austerity.add_theme_color_override("font_color", TNOTheme.COLOR_BORDER_CYAN)

	if btn_currency_reform != null:
		if current_state.liquid_reserves_billions >= 0.40:
			btn_currency_reform.text = "[ ДЕНЕЖНАЯ РЕФОРМА ($0.4B) ]"
			btn_currency_reform.disabled = false
		else:
			btn_currency_reform.text = "[ РЕФОРМА: НЕТ РЕЗЕРВОВ ]"
			btn_currency_reform.disabled = true
