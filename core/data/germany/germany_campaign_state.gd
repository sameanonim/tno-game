class_name GermanyCampaignState
extends Resource

##
## GermanyCampaignState: Состояние супердержавы Великогерманский Рейх (GER)
## Хранит макро-параметры кризиса престолонаследия, рабской экономики,
## лояльности 4 фракций и подсистем каждого из 4 претендентов.
##

enum CampaignStage {
	STAGE_PRELUDE = 0,         # 1962: Агония Гитлера, стачки, студенты, экономический тупик
	STAGE_POWER_STRUGGLE = 1,   # 1963: Гражданская война (GCW) или острая схватка за власть
	STAGE_SUCCESSOR_RULE = 2,   # 1964+: Правление победителя и реализация национальной программы
	STAGE_COLLAPSE = 3          # Фиаско / Немецкая Анархия / DSR / Ядерный коллапс
}

@export var current_stage: CampaignStage = CampaignStage.STAGE_PRELUDE
@export var chosen_contender_tag: String = "SPE" # BOR, SPE, GOR, HEY

# 1. Агония и здоровье фюрера
@export var hitler_health: float = 100.0
@export var hitler_is_alive: bool = true
@export var hitler_endorsement_tag: String = "BOR"

# 2. Рабский труд и общественное напряжение
@export var slaves_count_millions: float = 9.8
@export var slave_unrest: float = 0.45 # 0.0 .. 1.0 (при > 0.85 в 1970 - Восстание рабов)
@export var slave_productivity_penalty: float = 0.15
@export var slave_revolt_triggered: bool = false
@export var slave_revolt_negotiated: bool = false

# 3. Баланс 4 фракций (0.0 .. 100.0)
@export var faction_influence_bormann: float = 30.0
@export var faction_influence_speer: float = 28.0
@export var faction_influence_goering: float = 25.0
@export var faction_influence_heydrich: float = 17.0
@export var faction_loyalty_wehrmacht: float = 65.0
@export var faction_loyalty_ss: float = 40.0
@export var faction_loyalty_party: float = 70.0
@export var faction_loyalty_students: float = 35.0

# 4. Подсистема Бормана: Карточный Домик (Kartenhaus)
# Структура: {"bureaucrats": float, "militarists": float, "reformers": float, "districts_secured": int, "purges_done": int}
@export var kartenhaus_data: Dictionary = {
	"bureaucrats_control": 65.0,
	"militarists_control": 45.0,
	"reformers_control": 35.0,
	"districts_secured": 12,
	"total_districts": 24,
	"dismantled_factions": [] as Array[String],
	"second_night_knives_done": false
}

# 5. Подсистема Шпеера: Цолльферайн и Счетчик Режима (Zollverein & Regime Meter)
# regime_meter: -100 (Реваншистский фашизм Шпеера) .. 0 (Статус-кво) .. +100 (Демократия Четвёрки)
@export var speer_regime_meter: float = 10.0
@export var zollverein_data: Dictionary = {
	"pakt_members": ["GER", "OST", "UKR", "CAU", "POL", "DEN", "NOR", "HOL"] as Array[String],
	"trade_volume_billions": 48.5,
	"integration_level": 0.40,
	"gang_of_four_influence": {
		"erhard": 50.0,
		"kiesinger": 50.0,
		"schmidt": 50.0,
		"tresckow": 50.0
	},
	"fascist_hardliners_pressure": 45.0
}

# 6. Подсистема Гёринга: Планы Войны и Экономика Грабежа (War Plans & Plunder)
@export var goering_warplans_data: Dictionary = {
	"current_plan": "A", # A, B, C
	"target_country_tag": "SWI",
	"militarist_tension": 30.0, # При > 80 - бунт Шёрнера / переворот
	"plundered_gold_billions": 0.0,
	"okw_readiness": 75.0,
	"completed_targets": [] as Array[String]
}

# 7. Подсистема Гейдриха: Оборона ядерных шахт от Бургундии (Nuclear Silos Custody)
@export var heydrich_nuclear_data: Dictionary = {
	"secured_silos": 14,
	"burgundian_infiltrated_silos": 8,
	"total_silos": 28,
	"ss_loyalists_morale": 60.0,
	"apocalypse_clock_percent": 25.0, # При 100% - Запуск ядерных ракет и конец света
	"resistance_coalition_formed": false
}

# 8. Флаги сюжетных развилок
@export var story_flags: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"current_stage": int(current_stage),
		"chosen_contender_tag": chosen_contender_tag,
		"hitler_health": hitler_health,
		"hitler_is_alive": hitler_is_alive,
		"hitler_endorsement_tag": hitler_endorsement_tag,
		"slaves_count_millions": slaves_count_millions,
		"slave_unrest": slave_unrest,
		"slave_productivity_penalty": slave_productivity_penalty,
		"slave_revolt_triggered": slave_revolt_triggered,
		"slave_revolt_negotiated": slave_revolt_negotiated,
		"faction_influence_bormann": faction_influence_bormann,
		"faction_influence_speer": faction_influence_speer,
		"faction_influence_goering": faction_influence_goering,
		"faction_influence_heydrich": faction_influence_heydrich,
		"faction_loyalty_wehrmacht": faction_loyalty_wehrmacht,
		"faction_loyalty_ss": faction_loyalty_ss,
		"faction_loyalty_party": faction_loyalty_party,
		"faction_loyalty_students": faction_loyalty_students,
		"kartenhaus_data": kartenhaus_data.duplicate(true),
		"speer_regime_meter": speer_regime_meter,
		"zollverein_data": zollverein_data.duplicate(true),
		"goering_warplans_data": goering_warplans_data.duplicate(true),
		"heydrich_nuclear_data": heydrich_nuclear_data.duplicate(true),
		"story_flags": story_flags.duplicate(true)
	}


static func from_dict(d: Dictionary) -> Resource:
	var state = load("res://core/data/germany/germany_campaign_state.gd").new()
	if d.is_empty():
		return state
	
	state.current_stage = d.get("current_stage", CampaignStage.STAGE_PRELUDE) as CampaignStage
	state.chosen_contender_tag = str(d.get("chosen_contender_tag", "SPE"))
	state.hitler_health = float(d.get("hitler_health", 100.0))
	state.hitler_is_alive = bool(d.get("hitler_is_alive", true))
	state.hitler_endorsement_tag = str(d.get("hitler_endorsement_tag", "BOR"))
	state.slaves_count_millions = float(d.get("slaves_count_millions", 9.8))
	state.slave_unrest = float(d.get("slave_unrest", 0.45))
	state.slave_productivity_penalty = float(d.get("slave_productivity_penalty", 0.15))
	state.slave_revolt_triggered = bool(d.get("slave_revolt_triggered", false))
	state.slave_revolt_negotiated = bool(d.get("slave_revolt_negotiated", false))
	
	state.faction_influence_bormann = float(d.get("faction_influence_bormann", 30.0))
	state.faction_influence_speer = float(d.get("faction_influence_speer", 28.0))
	state.faction_influence_goering = float(d.get("faction_influence_goering", 25.0))
	state.faction_influence_heydrich = float(d.get("faction_influence_heydrich", 17.0))
	state.faction_loyalty_wehrmacht = float(d.get("faction_loyalty_wehrmacht", 65.0))
	state.faction_loyalty_ss = float(d.get("faction_loyalty_ss", 40.0))
	state.faction_loyalty_party = float(d.get("faction_loyalty_party", 70.0))
	state.faction_loyalty_students = float(d.get("faction_loyalty_students", 35.0))
	
	if d.has("kartenhaus_data") and d["kartenhaus_data"] is Dictionary:
		state.kartenhaus_data = (d["kartenhaus_data"] as Dictionary).duplicate(true)
	
	state.speer_regime_meter = float(d.get("speer_regime_meter", 10.0))
	if d.has("zollverein_data") and d["zollverein_data"] is Dictionary:
		state.zollverein_data = (d["zollverein_data"] as Dictionary).duplicate(true)
		
	if d.has("goering_warplans_data") and d["goering_warplans_data"] is Dictionary:
		state.goering_warplans_data = (d["goering_warplans_data"] as Dictionary).duplicate(true)
		
	if d.has("heydrich_nuclear_data") and d["heydrich_nuclear_data"] is Dictionary:
		state.heydrich_nuclear_data = (d["heydrich_nuclear_data"] as Dictionary).duplicate(true)
		
	if d.has("story_flags") and d["story_flags"] is Dictionary:
		state.story_flags = (d["story_flags"] as Dictionary).duplicate(true)
		
	return state
