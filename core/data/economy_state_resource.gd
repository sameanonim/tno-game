class_name EconomyStateResource
extends Resource

##
## EconomyStateResource: Ресурс макроэкономического состояния государства.
## Хранит производственные факторы, параметры рынка труда, монетарные и фискальные метрики
## в соответствии с математическими моделями Солоу-Свана, кривой Филлипса и закона Оукена.
##

signal state_updated()

# ==============================================================================
# 1. ПРОИЗВОДСТВЕННЫЕ ФАКТОРЫ (МОДЕЛЬ СОЛОУ-СВАНА / КОББ-ДУГЛАС)
# ==============================================================================
@export_group("Production Factors")
## Основной капитал (K): заводы, станочный парк, транспортная сеть, инфраструктура ($ млрд)
@export var capital_stock: float = 100.0:
	set(val):
		capital_stock = maxf(0.001, val)

## Эффективная рабочая сила (L): занятое и готовое к труду население (млн человек)
@export var labor_force: float = 50.0:
	set(val):
		labor_force = maxf(0.001, val)

## Совокупная факторная производительность (A / TFP): технологический уровень и институциональное качество
@export var tfp_technology: float = 1.0:
	set(val):
		tfp_technology = maxf(0.001, val)

## Норма амортизации капитала (delta): доля изнашивающегося капитала в год (например, 0.05 = 5%/год)
@export_range(0.001, 0.50, 0.001) var depreciation_rate: float = 0.05:
	set(val):
		depreciation_rate = clampf(val, 0.001, 0.50)

# ==============================================================================
# 2. РЫНОК ТРУДА
# ==============================================================================
@export_group("Labor Market")
## Фактический уровень безработицы (u): доля безработных от совокупной рабочей силы (0.05 = 5.0%)
@export_range(0.001, 0.95, 0.001) var unemployment_rate: float = 0.05:
	set(val):
		unemployment_rate = clampf(val, 0.001, 0.95)

## Естественный уровень безработицы (u* / NAIRU): структурная и фрикционная безработица (0.045 = 4.5%)
@export_range(0.001, 0.50, 0.001) var natural_unemployment: float = 0.045:
	set(val):
		natural_unemployment = clampf(val, 0.001, 0.50)

# ==============================================================================
# 3. МОНЕТАРНЫЕ ПОКАЗАТЕЛИ
# ==============================================================================
@export_group("Monetary Indicators")
## Номинальный ВВП в текущих ценах ($ млрд)
@export var nominal_gdp: float = 100.0:
	set(val):
		nominal_gdp = maxf(0.001, val)

## Реальный ВВП в постоянных ценах базового периода ($ млрд)
@export var real_gdp: float = 100.0:
	set(val):
		real_gdp = maxf(0.001, val)

## Потенциальный ВВП при полной занятости ресурсов по Солоу-Свану ($ млрд)
@export var potential_gdp: float = 100.0:
	set(val):
		potential_gdp = maxf(0.001, val)

## Фактический годовой темп инфляции (0.03 = 3.0%)
@export var inflation: float = 0.03:
	set(val):
		inflation = clampf(val, -0.50, 50.0) # От -50% дефляции до 5000% гиперинфляции

## Инфляционные ожидания населения и бизнеса (expected inflation, pi_e)
@export var expected_inflation: float = 0.03:
	set(val):
		expected_inflation = clampf(val, -0.30, 20.0)

## Ключевая ставка Центрального Банка (0.06 = 6.0%)
@export_range(-0.02, 1.0, 0.001) var key_interest_rate: float = 0.05:
	set(val):
		key_interest_rate = clampf(val, -0.02, 1.0)

## Темп годового прироста денежной массы M2 (0.05 = +5.0%)
@export var money_supply_growth: float = 0.04:
	set(val):
		money_supply_growth = clampf(val, -0.90, 100.0)

# ==============================================================================
# 4. ФИСКАЛЬНЫЕ ПОКАЗАТЕЛИ
# ==============================================================================
@export_group("Fiscal Indicators")
## Совокупный государственный долг ($ млрд)
@export var national_debt: float = 40.0:
	set(val):
		national_debt = maxf(0.0, val)

## Ликвидные резервы казны и суверенного фонда ($ млрд)
@export var liquid_reserves: float = 10.0:
	set(val):
		liquid_reserves = maxf(0.0, val)

## Эффективная ставка налогообложения экономики (0.20 = 20.0%)
@export_range(0.01, 0.90, 0.005) var tax_rate: float = 0.20:
	set(val):
		tax_rate = clampf(val, 0.01, 0.90)

## Предельная склонность к потреблению (MPC): доля прироста располагаемого дохода, идущая на потребление
@export_range(0.05, 0.98, 0.01) var marginal_propensity_to_consume: float = 0.70:
	set(val):
		marginal_propensity_to_consume = clampf(val, 0.05, 0.98)


"""Возвращает соотношение государственного долга к номинальному ВВП."""
func get_debt_to_gdp_ratio() -> float:
	var safe_gdp: float = maxf(nominal_gdp, 0.001)
	return national_debt / safe_gdp


"""Возвращает разрыв выпуска (Output Gap / GDP Gap) в относительных долях: (Y - Y*) / Y*."""
func get_output_gap() -> float:
	var safe_pot: float = maxf(potential_gdp, 0.001)
	return (real_gdp - safe_pot) / safe_pot


"""Возвращает разрыв безработицы (u - u*). Положительный при спаде, отрицательный при перегреве."""
func get_unemployment_gap() -> float:
	return unemployment_rate - natural_unemployment


"""Создает глубокую копию состояния для расчетов и прогнозирования сценариев."""
func clone() -> EconomyStateResource:
	var copy: EconomyStateResource = EconomyStateResource.new()
	copy.capital_stock = capital_stock
	copy.labor_force = labor_force
	copy.tfp_technology = tfp_technology
	copy.depreciation_rate = depreciation_rate
	copy.unemployment_rate = unemployment_rate
	copy.natural_unemployment = natural_unemployment
	copy.nominal_gdp = nominal_gdp
	copy.real_gdp = real_gdp
	copy.potential_gdp = potential_gdp
	copy.inflation = inflation
	copy.expected_inflation = expected_inflation
	copy.key_interest_rate = key_interest_rate
	copy.money_supply_growth = money_supply_growth
	copy.national_debt = national_debt
	copy.liquid_reserves = liquid_reserves
	copy.tax_rate = tax_rate
	copy.marginal_propensity_to_consume = marginal_propensity_to_consume
	return copy


"""Сериализует состояние в Dictionary для сохранения игры."""
func to_dict() -> Dictionary:
	return {
		"capital_stock": capital_stock,
		"labor_force": labor_force,
		"tfp_technology": tfp_technology,
		"depreciation_rate": depreciation_rate,
		"unemployment_rate": unemployment_rate,
		"natural_unemployment": natural_unemployment,
		"nominal_gdp": nominal_gdp,
		"real_gdp": real_gdp,
		"potential_gdp": potential_gdp,
		"inflation": inflation,
		"expected_inflation": expected_inflation,
		"key_interest_rate": key_interest_rate,
		"money_supply_growth": money_supply_growth,
		"national_debt": national_debt,
		"liquid_reserves": liquid_reserves,
		"tax_rate": tax_rate,
		"marginal_propensity_to_consume": marginal_propensity_to_consume
	}


"""Загружает параметры состояния из Dictionary."""
func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		return
	capital_stock = float(data.get("capital_stock", capital_stock))
	labor_force = float(data.get("labor_force", labor_force))
	tfp_technology = float(data.get("tfp_technology", tfp_technology))
	depreciation_rate = float(data.get("depreciation_rate", depreciation_rate))
	unemployment_rate = float(data.get("unemployment_rate", unemployment_rate))
	natural_unemployment = float(data.get("natural_unemployment", natural_unemployment))
	nominal_gdp = float(data.get("nominal_gdp", nominal_gdp))
	real_gdp = float(data.get("real_gdp", real_gdp))
	potential_gdp = float(data.get("potential_gdp", potential_gdp))
	inflation = float(data.get("inflation", inflation))
	expected_inflation = float(data.get("expected_inflation", expected_inflation))
	key_interest_rate = float(data.get("key_interest_rate", key_interest_rate))
	money_supply_growth = float(data.get("money_supply_growth", money_supply_growth))
	national_debt = float(data.get("national_debt", national_debt))
	liquid_reserves = float(data.get("liquid_reserves", liquid_reserves))
	tax_rate = float(data.get("tax_rate", tax_rate))
	marginal_propensity_to_consume = float(data.get("marginal_propensity_to_consume", marginal_propensity_to_consume))
	state_updated.emit()
