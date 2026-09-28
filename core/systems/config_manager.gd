class_name ConfigManager
extends Node

##
## ConfigManager: Синглтон управления балансными константами и настройками движка (Autoload)
##
## Загружает и кэширует res://data/config/game_constants.json.
## Предоставляет типизированные методы безопасного доступа с аварийными fallback-значениями
## для исключения любых runtime сбоев при отсутствии или повреждении конфигурационных файлов.
##

signal constants_reloaded()

const CONSTANTS_JSON_PATH = "res://data/config/game_constants.json"
const CONFIG_CFG_PATH = "res://data/config/engine_settings.cfg"

static var instance = null

var is_loaded: bool = false
var _constants_cache: Dictionary = {}

# Встроенные аварийные значения на случай повреждения или отсутствия JSON-файла
var _default_constants: Dictionary = {
	"economy": {
		"turns_per_year": 52.143,
		"tax_efficiency_base": 0.8,
		"tax_efficiency_legitimacy_factor": 0.003,
		"tax_efficiency_radicalization_factor": 0.002,
		"tax_efficiency_min": 0.4,
		"tax_efficiency_max": 1.3,
		"resource_income_base": 0.02,
		"debt_risk_threshold": 0.8,
		"debt_risk_multiplier": 0.08,
		"stability_risk_multiplier": 0.04,
		"fiscal_crisis_risk_premium": 0.15,
		"military_expense_gdp_share_mult": 0.15,
		"military_factory_cost_mult": 0.015,
		"manpower_cost_mult": 0.000001,
		"civilian_expense_mult": 0.12,
		"admin_expense_mult": 0.08,
		"rd_expense_mult": 0.08,
		"surplus_debt_repayment_ratio": 0.4,
		"deficit_reserves_drain_ratio": 1.0,
		"inflation_base": 0.02,
		"inflation_money_print_factor": 0.05,
		"inflation_gdp_growth_offset": 0.25,
		"consumer_goods_shortage_inflation_penalty": 0.03,
		"consumer_goods_deficit_radicalization_penalty": 1.5,
		"production_weapons_per_factory": 150,
		"production_heavy_per_factory": 25,
		"fiscal_crisis_default_ceiling": 2.0,
		"interest_rate_floor": 0.01,
		"interest_rate_ceiling": 0.35
	},
	"military": {
		"combat_hunger_threshold_ratio": 0.4,
		"combat_hunger_atk_penalty": 0.65,
		"terrain_modifiers": {
			"plains": 1.0,
			"forest": 1.25,
			"marsh": 1.45,
			"mountains": 1.70,
			"urban": 1.55,
			"hills": 1.20,
			"desert": 1.10
		},
		"defender_factory_power_factor": 15.0,
		"breakthrough_ratio_high": 1.4,
		"breakthrough_ratio_mid": 1.0,
		"breakthrough_ratio_low": 0.75,
		"progress_gain_high_min": 14.0,
		"progress_gain_high_max": 24.0,
		"progress_gain_mid_min": 8.0,
		"progress_gain_mid_max": 14.0,
		"progress_gain_low_min": 2.0,
		"progress_gain_low_max": 6.0,
		"progress_loss_stalled_min": 1.0,
		"progress_loss_stalled_max": 4.0,
		"posture_aggressive_mult": 1.35,
		"posture_defensive_max_progress": 1.0,
		"base_losses_rate_min": 0.015,
		"base_losses_rate_max": 0.035,
		"weapons_loss_ratio": 0.75,
		"capture_occupy_unrest": 85.0,
		"capture_occupy_garrison": 15.0,
		"victory_legitimacy_gain": 2.5,
		"victory_morale_gain": 4.0,
		"defeat_legitimacy_loss": 3.5,
		"defeat_morale_loss": 5.0,
		"battle_incident_breakthrough_chance": 0.35,
		"battle_incident_encirclement_chance": 0.40,
		"raids": {
			"recon": { "commitment_factor": 0.5, "cost_weapons": 100, "cost_manpower": 150 },
			"medium": { "commitment_factor": 1.0, "cost_weapons": 200, "cost_manpower": 400 },
			"heavy": { "commitment_factor": 2.0, "cost_weapons": 500, "cost_manpower": 1000 }
		},
		"defcon_escalation_thresholds": {
			"DEFCON_5": 0,
			"DEFCON_4": 25,
			"DEFCON_3": 50,
			"DEFCON_2": 75,
			"DEFCON_1": 90
		}
	},
	"politics": {
		"base_pc_gain_per_turn": 5.0,
		"base_max_cap": 5,
		"base_legitimacy": 50.0,
		"base_radicalization": 20.0,
		"faction_loyalty_threshold_revolt": 20.0,
		"faction_loyalty_threshold_discontent": 40.0,
		"faction_loyalty_threshold_content": 60.0,
		"faction_loyalty_threshold_loyal": 80.0,
		"minister_dismissal_pc_cost": 15.0,
		"minister_dismissal_loyalty_penalty": 20.0,
		"cabinet_appointment_cap_cost": 1,
		"cabinet_appointment_pc_cost": 10.0,
		"law_change_pc_cost": 25.0,
		"law_change_cap_cost": 2
	},
	"gcw": {
		"turns_until_hitler_death": 12,
		"initial_influence": {
			"SPEER": 25.0,
			"BORMANN": 25.0,
			"GOERING": 25.0,
			"HEYDRICH": 25.0
		},
		"initial_depots": {
			"SPEER": 25000,
			"BORMANN": 35000,
			"GOERING": 40000,
			"HEYDRICH": 20000
		},
		"initial_manpower": {
			"SPEER": 180000,
			"BORMANN": 280000,
			"GOERING": 320000,
			"HEYDRICH": 120000
		},
		"initial_factories": {
			"SPEER": 38,
			"BORMANN": 50,
			"GOERING": 55,
			"HEYDRICH": 28
		},
		"anarchy_trigger_turns": 15,
		"speer_initial_reform_balance": 15.0,
		"bormann_initial_party_web": 65.0,
		"goering_initial_war_debt": 18.0,
		"goering_initial_loyalty": 70.0,
		"heydrich_initial_burgundy_influence": 80.0,
		"heydrich_initial_nuclear_codes": 1
	}
}


func _init() -> void:
	if instance == null:
		instance = self
	load_constants()


func _ready() -> void:
	if not is_loaded:
		load_constants()


static func get_instance() -> ConfigManager:
	if instance == null:
		var script_res = load("res://core/systems/config_manager.gd")
		if script_res != null:
			instance = script_res.new()
	return instance


##
## Главный метод загрузки конфигурационных констант
##
func load_constants() -> bool:
	_constants_cache = _default_constants.duplicate(true)

	if not FileAccess.file_exists(CONSTANTS_JSON_PATH):
		print("[ConfigManager] Warning: %s not found. Using fallback defaults." % CONSTANTS_JSON_PATH)
		is_loaded = true
		return false

	var file = FileAccess.open(CONSTANTS_JSON_PATH, FileAccess.READ)
	if file == null:
		push_warning("[ConfigManager] Failed to open %s. Using defaults." % CONSTANTS_JSON_PATH)
		is_loaded = true
		return false

	var content = file.get_as_text()
	file.close()

	var json = JSON.new()
	var err = json.parse(content)
	if err != OK:
		push_error("[ConfigManager] JSON parse error in %s: %s (line %d). Using defaults." % [
			CONSTANTS_JSON_PATH, json.get_error_message(), json.get_error_line()
		])
		is_loaded = true
		return false

	if json.data is Dictionary:
		var file_dict: Dictionary = json.data
		for cat in file_dict.keys():
			if not _constants_cache.has(cat):
				_constants_cache[cat] = {}
			if file_dict[cat] is Dictionary:
				var cat_dict: Dictionary = file_dict[cat]
				for k in cat_dict.keys():
					_constants_cache[cat][k] = cat_dict[k]
			else:
				_constants_cache[cat] = file_dict[cat]

		is_loaded = true
		print("[ConfigManager] Successfully loaded balance constants from %s." % CONSTANTS_JSON_PATH)
		constants_reloaded.emit()
		return true

	is_loaded = true
	return false


##
## Горячая перезагрузка констант во время рантайма
##
func reload_constants() -> bool:
	return load_constants()


##
## Безопасный доступ к константе с возвратом значения по умолчанию
##
func get_constant(category: String, key: String, default_value: Variant = null) -> Variant:
	if _constants_cache.has(category):
		var cat_data = _constants_cache[category]
		if cat_data is Dictionary and cat_data.has(key):
			return cat_data[key]

	# Fallback на аварийную таблицу
	if _default_constants.has(category):
		var def_cat = _default_constants[category]
		if def_cat is Dictionary and def_cat.has(key):
			return def_cat[key]

	return default_value


##
## Типизированное получение числа с плавающей точкой
##
func get_float(category: String, key: String, default_val: float = 0.0) -> float:
	var val = get_constant(category, key, default_val)
	if val is float or val is int:
		return float(val)
	return default_val


##
## Типизированное получение целого числа
##
func get_int(category: String, key: String, default_val: int = 0) -> int:
	var val = get_constant(category, key, default_val)
	if val is int or val is float:
		return int(val)
	return default_val


##
## Типизированное получение словаря
##
func get_dict(category: String, key: String, default_val: Dictionary = {}) -> Dictionary:
	var val = get_constant(category, key, default_val)
	if val is Dictionary:
		return val
	return default_val


##
## Типизированное получение массива
##
func get_array(category: String, key: String, default_val: Array = []) -> Array:
	var val = get_constant(category, key, default_val)
	if val is Array:
		return val
	return default_val


##
## Проверка наличия категории в конфигурации
##
func has_category(category: String) -> bool:
	return _constants_cache.has(category) or _default_constants.has(category)


##
## Проверка наличия константы
##
func has_constant(category: String, key: String) -> bool:
	if _constants_cache.has(category):
		var cat_data = _constants_cache[category]
		if cat_data is Dictionary:
			return cat_data.has(key)
	return false

