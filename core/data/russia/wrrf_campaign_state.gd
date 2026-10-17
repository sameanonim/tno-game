class_name WRRFCampaignState
extends Resource

"""
WRRFCampaignState: Модель состояния кампании Западнорусского Революционного Фронта (ЗРРФ / WRS)
Хранит параметры:
1. Борьбы за власть между маршалом Георгием Жуковым и маршалом Михаилом Тухачевским.
2. Программ секретных военных проектов Тухачевского (ОБТ, Ураган, Циклон, Щука, Леший, Фермент).
3. Баланса влияния триумвирата Жукова (Ахромеев, Рыжков, Яковлев) на региональном этапе.
4. Фронтовой логистики, готовности к Смуте и рейдам против Онеги и Финляндии.
"""

enum Successor {
	NONE = 0,
	ZHUKOV = 1,
	TUKHACHEVSKY = 2
}

enum FactionHeir {
	NONE = 0,
	AKHROMEYEV = 1,
	RYZHKOV = 2,
	YAKOVLEV = 3
}

enum FrontStage {
	PROLOGUE_VOROSHILOV = 0,
	STRUGGLE = 1,
	WARLORD_SMUTA = 2,
	REGIONAL = 3,
	SUPERREGIONAL = 4,
	UNIFIED = 5,
	SECOND_WEST_RUSSIAN_WAR = 6
}

# ==============================================================================
# 1. ОБЩЕЕ СОСТОЯНИЕ ФРОНТА
# ==============================================================================
@export var current_stage: FrontStage = FrontStage.PROLOGUE_VOROSHILOV
@export var terror_bombings_active: bool = true
@export var bombings_end_declared: bool = false
@export var front_supply_stockpile: float = 65.0 # 0..100%
@export var onega_raid_readiness: float = 40.0 # 0..100%
@export var red_army_veterans_corps: int = 15000

# ==============================================================================
# 2. БОРЬБА ЗА ВЛАСТЬ (ЖУКОВ VS ТУХАЧЕВСКИЙ)
# ==============================================================================
@export var zhukov_influence: float = 50.0 # 0..100%
@export var tukhachevsky_influence: float = 50.0 # 0..100%
@export var chosen_successor: Successor = Successor.NONE
@export var power_struggle_resolved: bool = false
@export var marshal_yegorov_health: float = 45.0 # Здоровье старого маршала
@export var veterans_support_zhukov: float = 58.0 # Поддержка ветеранов
@export var officers_support_tukha: float = 58.0 # Поддержка офицерского корпуса
@export var operation_firebird_executed: bool = false
@export var evidence_compiled_against_tukha: bool = false

# ==============================================================================
# 3. ВОЕННЫЙ АРСЕНАЛ ТУХАЧЕВСКОГО (СЕКРЕТНЫЕ ПРОЕКТЫ)
# ==============================================================================
@export var obt_progress: float = 0.0 # 0..100% (Программа Основного Боевого Танка)
@export var obt_completed: bool = false
@export var uragan_active: bool = false # Тяжелая реактивная артиллерия
@export var tsysklon_active: bool = false # Тактическое ракетостроение
@export var shchuka_active: bool = false # Бригада дизельных подлодок СФ
@export var leshiy_active: bool = false # Диверсионно-разведывательные группы спецназа
@export var ferment_chemical_stockpile: int = 0 # Тонны боевых ОВ («Фермент»)
@export var izhevsk_works_expanded: bool = false # Ижевский опытно-механический завод

# ==============================================================================
# 4. ТРИУМВИРАТ ЖУКОВА (АХРОМЕЕВ, РЫЖКОВ, ЯКОВЛЕВ)
# ==============================================================================
@export var akhromeyev_influence: float = 33.3 # Военные ортодоксы / СМЕРШ / Армия
@export var ryzhkov_influence: float = 33.3 # Прагматики-хозяйственники / Госплан
@export var yakovlev_influence: float = 33.4 # Демократические социалисты / Реформы
@export var chosen_heir: FactionHeir = FactionHeir.NONE
@export var triumvirate_tension: float = 20.0 # 0..100%

# Политические решения триумвирата
@export var smersh_jurisdiction_expanded: bool = false
@export var us_equipment_imported: bool = false
@export var kgb_established: bool = false
@export var agricultural_mechanization_done: bool = false
@export var gulag_system_abolished: bool = false
@export var ofn_tariffs_eliminated: bool = false


# ==============================================================================
# СЕРИАЛИЗАЦИЯ И ДЕСЕРИАЛИЗАЦИЯ
# ==============================================================================

"""Преобразует состояние кампании ЗРРФ в словарь для сохранений."""
func to_dict() -> Dictionary:
	return {
		"current_stage": int(current_stage),
		"terror_bombings_active": terror_bombings_active,
		"bombings_end_declared": bombings_end_declared,
		"front_supply_stockpile": front_supply_stockpile,
		"onega_raid_readiness": onega_raid_readiness,
		"red_army_veterans_corps": red_army_veterans_corps,
		"power_struggle": {
			"zhukov_influence": zhukov_influence,
			"tukhachevsky_influence": tukhachevsky_influence,
			"chosen_successor": int(chosen_successor),
			"power_struggle_resolved": power_struggle_resolved,
			"marshal_yegorov_health": marshal_yegorov_health,
			"veterans_support_zhukov": veterans_support_zhukov,
			"officers_support_tukha": officers_support_tukha,
			"operation_firebird_executed": operation_firebird_executed,
			"evidence_compiled_against_tukha": evidence_compiled_against_tukha
		},
		"tukhachevsky_arsenal": {
			"obt_progress": obt_progress,
			"obt_completed": obt_completed,
			"uragan_active": uragan_active,
			"tsysklon_active": tsysklon_active,
			"shchuka_active": shchuka_active,
			"leshiy_active": leshiy_active,
			"ferment_chemical_stockpile": ferment_chemical_stockpile,
			"izhevsk_works_expanded": izhevsk_works_expanded
		},
		"zhukov_triumvirate": {
			"akhromeyev_influence": akhromeyev_influence,
			"ryzhkov_influence": ryzhkov_influence,
			"yakovlev_influence": yakovlev_influence,
			"chosen_heir": int(chosen_heir),
			"triumvirate_tension": triumvirate_tension,
			"smersh_jurisdiction_expanded": smersh_jurisdiction_expanded,
			"us_equipment_imported": us_equipment_imported,
			"kgb_established": kgb_established,
			"agricultural_mechanization_done": agricultural_mechanization_done,
			"gulag_system_abolished": gulag_system_abolished,
			"ofn_tariffs_eliminated": ofn_tariffs_eliminated
		}
	}


"""Восстанавливает состояние кампании ЗРРФ из словаря сохранения."""
func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		return

	current_stage = data.get("current_stage", FrontStage.PROLOGUE_VOROSHILOV) as FrontStage
	terror_bombings_active = bool(data.get("terror_bombings_active", true))
	bombings_end_declared = bool(data.get("bombings_end_declared", false))
	front_supply_stockpile = float(data.get("front_supply_stockpile", 65.0))
	onega_raid_readiness = float(data.get("onega_raid_readiness", 40.0))
	red_army_veterans_corps = int(data.get("red_army_veterans_corps", 15000))

	if data.has("power_struggle") and data["power_struggle"] is Dictionary:
		var ps: Dictionary = data["power_struggle"]
		zhukov_influence = float(ps.get("zhukov_influence", 50.0))
		tukhachevsky_influence = float(ps.get("tukhachevsky_influence", 50.0))
		chosen_successor = ps.get("chosen_successor", Successor.NONE) as Successor
		power_struggle_resolved = bool(ps.get("power_struggle_resolved", false))
		marshal_yegorov_health = float(ps.get("marshal_yegorov_health", 45.0))
		veterans_support_zhukov = float(ps.get("veterans_support_zhukov", 58.0))
		officers_support_tukha = float(ps.get("officers_support_tukha", 58.0))
		operation_firebird_executed = bool(ps.get("operation_firebird_executed", false))
		evidence_compiled_against_tukha = bool(ps.get("evidence_compiled_against_tukha", false))

	if data.has("tukhachevsky_arsenal") and data["tukhachevsky_arsenal"] is Dictionary:
		var ta: Dictionary = data["tukhachevsky_arsenal"]
		obt_progress = float(ta.get("obt_progress", 0.0))
		obt_completed = bool(ta.get("obt_completed", false))
		uragan_active = bool(ta.get("uragan_active", false))
		tsysklon_active = bool(ta.get("tsysklon_active", false))
		shchuka_active = bool(ta.get("shchuka_active", false))
		leshiy_active = bool(ta.get("leshiy_active", false))
		ferment_chemical_stockpile = int(ta.get("ferment_chemical_stockpile", 0))
		izhevsk_works_expanded = bool(ta.get("izhevsk_works_expanded", false))

	if data.has("zhukov_triumvirate") and data["zhukov_triumvirate"] is Dictionary:
		var zt: Dictionary = data["zhukov_triumvirate"]
		akhromeyev_influence = float(zt.get("akhromeyev_influence", 33.3))
		ryzhkov_influence = float(zt.get("ryzhkov_influence", 33.3))
		yakovlev_influence = float(zt.get("yakovlev_influence", 33.4))
		chosen_heir = zt.get("chosen_heir", FactionHeir.NONE) as FactionHeir
		triumvirate_tension = float(zt.get("triumvirate_tension", 20.0))
		smersh_jurisdiction_expanded = bool(zt.get("smersh_jurisdiction_expanded", false))
		us_equipment_imported = bool(zt.get("us_equipment_imported", false))
		kgb_established = bool(zt.get("kgb_established", false))
		agricultural_mechanization_done = bool(zt.get("agricultural_mechanization_done", false))
		gulag_system_abolished = bool(zt.get("gulag_system_abolished", false))
		ofn_tariffs_eliminated = bool(zt.get("ofn_tariffs_eliminated", false))
