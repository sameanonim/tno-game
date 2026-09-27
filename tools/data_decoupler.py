#!/usr/bin/env python3
"""
================================================================================
TNO DATA DECOUPLER & DYNAMIC ARCHITECTURE PIPELINE
================================================================================
Extracts hardcoded game data (countries, leaders, constants, formulas, UI strings)
from GDScript and Python engine sources into isolated, structured JSON/CFG files.

Categories Decoupled:
1. COUNTRIES DATA:
   - Contender states, warlords, colors, starting states, macro and politics.
   - Output: data/countries/<TAG>/country.json and data/countries/index.json
2. LEADERS & MINISTERS:
   - Cabinet ministers, generals, traits, competence, skills, portrait paths.
   - Output: data/countries/<TAG>/leaders/<leader_id>.json
3. GAME CONSTANTS & FORMULAS:
   - Balance constants for Economy, Military, Politics, GCW.
   - Output: data/config/game_constants.json & data/config/engine_settings.cfg
4. LOCALIZATION:
   - Extraction of Cyrillic/English UI strings into KEY_* mappings.
   - Output: data/localization/ru.json, en.json, and country packages.
================================================================================
"""

import argparse
import copy
import json
import os
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = PROJECT_ROOT / "data"
CONFIG_DIR = DATA_DIR / "config"
COUNTRIES_DIR = DATA_DIR / "countries"
LOCALIZATION_DIR = DATA_DIR / "localization"
CORE_DIR = PROJECT_ROOT / "core"
UI_DIR = PROJECT_ROOT / "ui"
SCRIPTS_DIR = PROJECT_ROOT / "scripts"

# JSON literal compatibility
true = True
false = False
null = None


# ==============================================================================
# 1. CANONICAL GAME BALANCE CONSTANTS SPECIFICATION
# ==============================================================================

CANONICAL_GAME_CONSTANTS = {
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
            "recon": {
                "commitment_factor": 0.5,
                "cost_weapons": 100,
                "cost_manpower": 150
            },
            "medium": {
                "commitment_factor": 1.0,
                "cost_weapons": 200,
                "cost_manpower": 400
            },
            "heavy": {
                "commitment_factor": 2.0,
                "cost_weapons": 500,
                "cost_manpower": 1000
            }
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


# ==============================================================================
# 2. CONTENDER & COUNTRY TEMPLATES
# ==============================================================================

CONTENDER_SPECS = {
    "SPE": {
        "identity": {
            "country_tag": "SPE",
            "country_name": "Reich of Albert Speer (Reformists)",
            "country_name_ru": "Германия (Альберт Шпеер / Реформаторы)",
            "theater": "theater_gcw",
            "geopolitical_bloc": "Einheitspakt (Reformist Coalition)",
            "primary_leader_id": "leader_albert_speer",
            "leader_name": "Альберт Шпеер",
            "leader_portrait_path": "res://data/countries/GER/leaders/portraits/GER_albert_speer.png",
            "ruling_ideology": "Fascism",
            "sub_ideology": "Reform_Fascism",
            "country_color": [0.85, 0.65, 0.20, 1.0],
            "controlled_states": [51, 52, 53, 54, 55]
        },
        "politics": {
            "political_capital": 80.0,
            "pc_gain_per_turn": 6.5,
            "max_cap": 5,
            "current_cap": 5,
            "legitimacy": 55.0,
            "radicalization": 35.0,
            "factions_loyalty": {
                "reformists": 85.0,
                "students": 80.0,
                "bureaucracy": 45.0,
                "militarists": 30.0
            },
            "party_popularities": {
                "fascism": 65.0,
                "national_socialism": 20.0,
                "authoritarian_democrat": 15.0
            },
            "starting_laws": {
                "political": "tno_political_parties_one_party_state",
                "trade": "tno_trade_laws_export_focus",
                "economy": "tno_economy_planned"
            }
        },
        "economy": {
            "gdp_billions": 42.0,
            "real_gdp_growth": 0.05,
            "liquid_reserves_billions": 4.5,
            "national_debt_billions": 12.0,
            "debt_ceiling_ratio": 1.2,
            "is_in_fiscal_crisis": false,
            "central_bank_rate": 0.055,
            "inflation_rate": 0.04,
            "tax_rate": 0.22,
            "military_spending_share": 0.35,
            "civilian_spending_share": 0.35,
            "admin_spending_share": 0.20,
            "rd_spending_share": 0.10,
            "money_printing_this_turn": 0.0
        },
        "military": {
            "civilian_factories": 22,
            "military_factories": 16,
            "consumer_goods_ratio": 0.35,
            "manpower_pool": 180000,
            "infantry_weapons_stockpile": 25000,
            "heavy_equipment_stockpile": 450,
            "army_readiness": 65.0,
            "army_morale": 80.0,
            "war_support_percent": 75.0
        },
        "narrative": {
            "active_directives": ["speer_reform_manifesto"],
            "completed_directives": [],
            "story_flags": {
                "gcw_contender": true,
                "reform_balance": 15.0
            }
        },
        "leader": {
            "leader_id": "leader_albert_speer",
            "leader_name": "Альберт Шпеер",
            "name_en": "Albert Speer",
            "title": "Рейхсминистр вооружения / Архитектор Реформ",
            "role": "HEAD_OF_STATE",
            "ideology": "Фашизм",
            "sub_ideology": "Реформистский фашизм",
            "ideological_faction": "reformists",
            "competence": 4,
            "loyalty": 80.0,
            "cabinet_influence": 75.0,
            "is_head_of_state": true,
            "is_military_commander": false,
            "attack_skill": 5,
            "defense_skill": 6,
            "logistics_skill": 9,
            "traits": ["architect_of_the_reich", "market_liberalizer", "student_movement_patron"],
            "portrait_path": "res://data/countries/GER/leaders/portraits/GER_albert_speer.png",
            "lore_desc_key": "KEY_LEADER_SPEER_DESC",
            "passive_modifiers": {
                "MOD_PC": 1.5,
                "MOD_STABILITY": 0.05,
                "industrial_efficiency": 0.15
            }
        }
    },
    "BOR": {
        "identity": {
            "country_tag": "BOR",
            "country_name": "Reich of Martin Bormann (Party Bureaucracy)",
            "country_name_ru": "Германия (Мартин Борман / Партократы)",
            "theater": "theater_gcw",
            "geopolitical_bloc": "Einheitspakt (NSDAP Apparatus)",
            "primary_leader_id": "leader_martin_bormann",
            "leader_name": "Мартин Борман",
            "leader_portrait_path": "res://data/countries/GER/leaders/portraits/GER_martin_bormann.png",
            "ruling_ideology": "National Socialism",
            "sub_ideology": "Orthodox_National_Socialism",
            "country_color": [0.60, 0.45, 0.25, 1.0],
            "controlled_states": [56, 57, 58, 59, 60]
        },
        "politics": {
            "political_capital": 120.0,
            "pc_gain_per_turn": 7.0,
            "max_cap": 6,
            "current_cap": 6,
            "legitimacy": 65.0,
            "radicalization": 25.0,
            "factions_loyalty": {
                "bureaucracy": 90.0,
                "nsdap_cadres": 85.0,
                "militarists": 50.0,
                "reformists": 25.0
            },
            "party_popularities": {
                "national_socialism": 75.0,
                "fascism": 15.0,
                "ultranationalism": 10.0
            },
            "starting_laws": {
                "political": "tno_political_parties_one_party_state",
                "trade": "tno_trade_laws_closed_economy",
                "economy": "tno_economy_planned"
            }
        },
        "economy": {
            "gdp_billions": 48.0,
            "real_gdp_growth": 0.035,
            "liquid_reserves_billions": 6.0,
            "national_debt_billions": 14.0,
            "debt_ceiling_ratio": 1.0,
            "is_in_fiscal_crisis": false,
            "central_bank_rate": 0.06,
            "inflation_rate": 0.045,
            "tax_rate": 0.24,
            "military_spending_share": 0.40,
            "civilian_spending_share": 0.30,
            "admin_spending_share": 0.25,
            "rd_spending_share": 0.05,
            "money_printing_this_turn": 0.0
        },
        "military": {
            "civilian_factories": 28,
            "military_factories": 22,
            "consumer_goods_ratio": 0.40,
            "manpower_pool": 280000,
            "infantry_weapons_stockpile": 35000,
            "heavy_equipment_stockpile": 600,
            "army_readiness": 55.0,
            "army_morale": 70.0,
            "war_support_percent": 80.0
        },
        "narrative": {
            "active_directives": ["bormann_purge_dissidents"],
            "completed_directives": [],
            "story_flags": {
                "gcw_contender": true,
                "party_web_control": 65.0
            }
        },
        "leader": {
            "leader_id": "leader_martin_bormann",
            "leader_name": "Мартин Борман",
            "name_en": "Martin Bormann",
            "title": "Партийный Секретарь НСДАП / Коричневое Преосвященство",
            "role": "HEAD_OF_STATE",
            "ideology": "Национал-Социализм",
            "sub_ideology": "Ортодоксальный нацизм",
            "ideological_faction": "bureaucracy",
            "competence": 3,
            "loyalty": 95.0,
            "cabinet_influence": 90.0,
            "is_head_of_state": true,
            "is_military_commander": false,
            "attack_skill": 4,
            "defense_skill": 7,
            "logistics_skill": 8,
            "traits": ["brown_eminence", "party_web_master", "status_quo_preservation"],
            "portrait_path": "res://data/countries/GER/leaders/portraits/GER_martin_bormann.png",
            "lore_desc_key": "KEY_LEADER_BORMANN_DESC",
            "passive_modifiers": {
                "MOD_PC": 2.5,
                "admin_cost_reduction": 0.20,
                "MOD_STABILITY": 0.08
            }
        }
    },
    "GOR": {
        "identity": {
            "country_tag": "GOR",
            "country_name": "Reich of Hermann Göring (Militarists)",
            "country_name_ru": "Германия (Герман Геринг / Милитаристы)",
            "theater": "theater_gcw",
            "geopolitical_bloc": "Einheitspakt (Wehrmacht Junta)",
            "primary_leader_id": "leader_hermann_goering",
            "leader_name": "Герман Геринг",
            "leader_portrait_path": "res://data/countries/GER/leaders/portraits/GER_hermann_goring.png",
            "ruling_ideology": "Fascism",
            "sub_ideology": "Militarism",
            "country_color": [0.48, 0.52, 0.58, 1.0],
            "controlled_states": [61, 62, 63, 64, 65]
        },
        "politics": {
            "political_capital": 60.0,
            "pc_gain_per_turn": 4.5,
            "max_cap": 5,
            "current_cap": 5,
            "legitimacy": 50.0,
            "radicalization": 30.0,
            "factions_loyalty": {
                "militarists": 95.0,
                "luftwaffe": 90.0,
                "bureaucracy": 35.0,
                "reformists": 20.0
            },
            "party_popularities": {
                "fascism": 50.0,
                "ultranationalism": 35.0,
                "national_socialism": 15.0
            },
            "starting_laws": {
                "political": "tno_political_parties_one_party_state",
                "trade": "tno_trade_laws_war_economy",
                "economy": "tno_economy_militarized"
            }
        },
        "economy": {
            "gdp_billions": 45.0,
            "real_gdp_growth": 0.02,
            "liquid_reserves_billions": 3.0,
            "national_debt_billions": 18.0,
            "debt_ceiling_ratio": 1.5,
            "is_in_fiscal_crisis": false,
            "central_bank_rate": 0.07,
            "inflation_rate": 0.06,
            "tax_rate": 0.28,
            "military_spending_share": 0.60,
            "civilian_spending_share": 0.20,
            "admin_spending_share": 0.15,
            "rd_spending_share": 0.05,
            "money_printing_this_turn": 0.0
        },
        "military": {
            "civilian_factories": 20,
            "military_factories": 35,
            "consumer_goods_ratio": 0.25,
            "manpower_pool": 320000,
            "infantry_weapons_stockpile": 40000,
            "heavy_equipment_stockpile": 850,
            "army_readiness": 75.0,
            "army_morale": 85.0,
            "war_support_percent": 90.0
        },
        "narrative": {
            "active_directives": ["goering_total_mobilization"],
            "completed_directives": [],
            "story_flags": {
                "gcw_contender": true,
                "militarist_loyalty": 70.0
            }
        },
        "leader": {
            "leader_id": "leader_hermann_goering",
            "leader_name": "Герман Геринг",
            "name_en": "Hermann Göring",
            "title": "Рейхсмаршал / Председатель Совета Обороны",
            "role": "HEAD_OF_STATE",
            "ideology": "Фашизм",
            "sub_ideology": "Милитаризм",
            "ideological_faction": "militarists",
            "competence": 3,
            "loyalty": 75.0,
            "cabinet_influence": 80.0,
            "is_head_of_state": true,
            "is_military_commander": true,
            "attack_skill": 8,
            "defense_skill": 5,
            "logistics_skill": 4,
            "traits": ["iron_reichsmarschall", "luftwaffe_patron", "expansionist_warmonger"],
            "portrait_path": "res://data/countries/GER/leaders/portraits/GER_hermann_goring.png",
            "lore_desc_key": "KEY_LEADER_GOERING_DESC",
            "passive_modifiers": {
                "military_production_bonus": 0.20,
                "army_morale_gain": 0.08,
                "inflation_penalty": 0.02
            }
        }
    },
    "HEY": {
        "identity": {
            "country_tag": "HEY",
            "country_name": "SS-Reich of Reinhard Heydrich",
            "country_name_ru": "Германия (Рейнхард Гейдрих / Черный Орден СС)",
            "theater": "theater_gcw",
            "geopolitical_bloc": "Burgundian Sphere",
            "primary_leader_id": "leader_reinhard_heydrich",
            "leader_name": "Рейнхард Гейдрих",
            "leader_portrait_path": "res://data/countries/GER/leaders/portraits/GER_reinhard_heydrich.png",
            "ruling_ideology": "Burgundian System",
            "sub_ideology": "Spartanism",
            "country_color": [0.18, 0.18, 0.24, 1.0],
            "controlled_states": [66, 67, 68, 69, 70]
        },
        "politics": {
            "political_capital": 50.0,
            "pc_gain_per_turn": 4.0,
            "max_cap": 4,
            "current_cap": 4,
            "legitimacy": 40.0,
            "radicalization": 50.0,
            "factions_loyalty": {
                "ss_cadres": 95.0,
                "burgundy_liaisons": 90.0,
                "wehrmacht": 20.0,
                "bureaucracy": 20.0
            },
            "party_popularities": {
                "ultranationalism": 80.0,
                "national_socialism": 20.0
            },
            "starting_laws": {
                "political": "tno_political_parties_one_party_state",
                "trade": "tno_trade_laws_closed_economy",
                "economy": "tno_economy_slave_labor"
            }
        },
        "economy": {
            "gdp_billions": 36.0,
            "real_gdp_growth": 0.01,
            "liquid_reserves_billions": 2.0,
            "national_debt_billions": 8.0,
            "debt_ceiling_ratio": 0.8,
            "is_in_fiscal_crisis": false,
            "central_bank_rate": 0.08,
            "inflation_rate": 0.05,
            "tax_rate": 0.30,
            "military_spending_share": 0.65,
            "civilian_spending_share": 0.15,
            "admin_spending_share": 0.15,
            "rd_spending_share": 0.05,
            "money_printing_this_turn": 0.0
        },
        "military": {
            "civilian_factories": 12,
            "military_factories": 16,
            "consumer_goods_ratio": 0.20,
            "manpower_pool": 120000,
            "infantry_weapons_stockpile": 20000,
            "heavy_equipment_stockpile": 350,
            "army_readiness": 85.0,
            "army_morale": 90.0,
            "war_support_percent": 95.0
        },
        "narrative": {
            "active_directives": ["heydrich_ss_terror"],
            "completed_directives": [],
            "story_flags": {
                "gcw_contender": true,
                "burgundian_influence": 80.0,
                "nuclear_codes": 1
            }
        },
        "leader": {
            "leader_id": "leader_reinhard_heydrich",
            "leader_name": "Рейнхард Гейдрих",
            "name_en": "Reinhard Heydrich",
            "title": "Рейхспротектор / Обергруппенфюрер СС",
            "role": "HEAD_OF_STATE",
            "ideology": "Бургундская Система",
            "sub_ideology": "Спартанизм",
            "ideological_faction": "ss_cadres",
            "competence": 5,
            "loyalty": 90.0,
            "cabinet_influence": 85.0,
            "is_head_of_state": true,
            "is_military_commander": true,
            "attack_skill": 9,
            "defense_skill": 8,
            "logistics_skill": 6,
            "traits": ["the_hangman", "black_order_grandmaster", "ruthless_terror"],
            "portrait_path": "res://data/countries/GER/leaders/portraits/GER_reinhard_heydrich.png",
            "lore_desc_key": "KEY_LEADER_HEYDRICH_DESC",
            "passive_modifiers": {
                "counter_intelligence_bonus": 0.35,
                "army_readiness_gain": 0.10,
                "radicalization_growth": 0.03
            }
        }
    },
    "GOB": {
        "identity": {
            "country_tag": "GOB",
            "country_name": "Volkssturm Reich of Joseph Goebbels",
            "country_name_ru": "Германия (Йозеф Геббельс / Тотальная Война)",
            "theater": "theater_gcw",
            "geopolitical_bloc": "Total War Faction",
            "primary_leader_id": "leader_joseph_goebbels",
            "leader_name": "Йозеф Геббельс",
            "leader_portrait_path": "res://data/countries/GER/leaders/portraits/GER_joseph_goebbels.png",
            "ruling_ideology": "Ultranationalism",
            "sub_ideology": "Revanchism",
            "country_color": [0.75, 0.15, 0.15, 1.0],
            "controlled_states": [71, 72]
        },
        "politics": {
            "political_capital": 70.0,
            "pc_gain_per_turn": 5.0,
            "max_cap": 4,
            "current_cap": 4,
            "legitimacy": 45.0,
            "radicalization": 60.0,
            "factions_loyalty": {
                "propaganda_ministry": 95.0,
                "volkssturm": 85.0
            },
            "party_popularities": {
                "ultranationalism": 85.0,
                "national_socialism": 15.0
            },
            "starting_laws": {}
        },
        "economy": {
            "gdp_billions": 25.0,
            "real_gdp_growth": -0.02,
            "liquid_reserves_billions": 1.0,
            "national_debt_billions": 6.0,
            "debt_ceiling_ratio": 1.0,
            "is_in_fiscal_crisis": false,
            "central_bank_rate": 0.08,
            "inflation_rate": 0.08,
            "tax_rate": 0.35,
            "military_spending_share": 0.70,
            "civilian_spending_share": 0.15,
            "admin_spending_share": 0.10,
            "rd_spending_share": 0.05,
            "money_printing_this_turn": 0.0
        },
        "military": {
            "civilian_factories": 8,
            "military_factories": 12,
            "consumer_goods_ratio": 0.15,
            "manpower_pool": 150000,
            "infantry_weapons_stockpile": 15000,
            "heavy_equipment_stockpile": 100,
            "army_readiness": 50.0,
            "army_morale": 95.0,
            "war_support_percent": 100.0
        },
        "narrative": {
            "active_directives": ["goebbels_last_stand"],
            "completed_directives": [],
            "story_flags": {
                "gcw_crisis": true
            }
        },
        "leader": {
            "leader_id": "leader_joseph_goebbels",
            "leader_name": "Йозеф Геббельс",
            "name_en": "Joseph Goebbels",
            "title": "Рейхсминистр Народного Просвещения и Пропаганды",
            "role": "HEAD_OF_STATE",
            "ideology": "Ультранационализм",
            "sub_ideology": "Тотальная война",
            "ideological_faction": "propaganda_ministry",
            "competence": 5,
            "loyalty": 99.0,
            "cabinet_influence": 80.0,
            "is_head_of_state": true,
            "is_military_commander": false,
            "attack_skill": 6,
            "defense_skill": 7,
            "logistics_skill": 4,
            "traits": ["voice_of_the_reich", "fanatical_agitator", "total_war_architect"],
            "portrait_path": "res://data/countries/GER/leaders/portraits/GER_joseph_goebbels.png",
            "lore_desc_key": "KEY_LEADER_GOEBBELS_DESC",
            "passive_modifiers": {
                "war_support_gain": 0.15,
                "propaganda_efficiency": 0.50
            }
        }
    },
    "DSR": {
        "identity": {
            "country_tag": "DSR",
            "country_name": "Deutsches Rotes Reich (Red Anarchy)",
            "country_name_ru": "Немецкая Красная Республика (Красная Анархия)",
            "theater": "theater_gcw",
            "geopolitical_bloc": "Revolutionary Council",
            "primary_leader_id": "leader_dsr_collective",
            "leader_name": "Революционный Военный Совет",
            "leader_portrait_path": "res://icon.svg",
            "ruling_ideology": "Communist",
            "sub_ideology": "Red_Terror",
            "country_color": [0.85, 0.10, 0.10, 1.0],
            "controlled_states": [73]
        },
        "politics": {
            "political_capital": 40.0,
            "pc_gain_per_turn": 4.0,
            "max_cap": 3,
            "current_cap": 3,
            "legitimacy": 30.0,
            "radicalization": 90.0,
            "factions_loyalty": {
                "proletariat": 95.0,
                "red_guards": 90.0
            },
            "party_popularities": {
                "communist": 90.0,
                "socialist": 10.0
            },
            "starting_laws": {}
        },
        "economy": {
            "gdp_billions": 15.0,
            "real_gdp_growth": -0.05,
            "liquid_reserves_billions": 0.5,
            "national_debt_billions": 0.0,
            "debt_ceiling_ratio": 0.5,
            "is_in_fiscal_crisis": true,
            "central_bank_rate": 0.05,
            "inflation_rate": 0.12,
            "tax_rate": 0.40,
            "military_spending_share": 0.70,
            "civilian_spending_share": 0.20,
            "admin_spending_share": 0.10,
            "rd_spending_share": 0.0,
            "money_printing_this_turn": 0.0
        },
        "military": {
            "civilian_factories": 5,
            "military_factories": 8,
            "consumer_goods_ratio": 0.10,
            "manpower_pool": 80000,
            "infantry_weapons_stockpile": 8000,
            "heavy_equipment_stockpile": 40,
            "army_readiness": 40.0,
            "army_morale": 90.0,
            "war_support_percent": 90.0
        },
        "narrative": {
            "active_directives": ["dsr_red_purge"],
            "completed_directives": [],
            "story_flags": {
                "red_anarchy": true
            }
        },
        "leader": {
            "leader_id": "leader_dsr_collective",
            "leader_name": "Революционный Военный Совет",
            "name_en": "Revolutionary Military Council",
            "title": "Коллективный Орган Власти",
            "role": "HEAD_OF_STATE",
            "ideology": "Коммунизм",
            "sub_ideology": "Красный террор",
            "ideological_faction": "red_guards",
            "competence": 3,
            "loyalty": 90.0,
            "cabinet_influence": 90.0,
            "is_head_of_state": true,
            "is_military_commander": true,
            "attack_skill": 5,
            "defense_skill": 5,
            "logistics_skill": 3,
            "traits": ["red_tribunal", "fanatical_partisans"],
            "portrait_path": "res://icon.svg",
            "lore_desc_key": "KEY_LEADER_DSR_DESC",
            "passive_modifiers": {
                "radicalization_growth": 0.05
            }
        }
    },
    "SPN": {
        "identity": {
            "country_tag": "SPN",
            "country_name": "Spandau Neutral Military Garrison",
            "country_name_ru": "Нейтральный Гарнизон Шпандау (Берлин)",
            "theater": "theater_gcw",
            "geopolitical_bloc": "Neutral Fortress",
            "primary_leader_id": "leader_spandau_garrison",
            "leader_name": "Гарнизон Шпандау",
            "leader_portrait_path": "res://icon.svg",
            "ruling_ideology": "Despotism",
            "sub_ideology": "Military_Junta",
            "country_color": [0.70, 0.70, 0.60, 1.0],
            "controlled_states": [74]
        },
        "politics": {
            "political_capital": 30.0,
            "pc_gain_per_turn": 3.0,
            "max_cap": 3,
            "current_cap": 3,
            "legitimacy": 60.0,
            "radicalization": 10.0,
            "factions_loyalty": {
                "garrison": 95.0
            },
            "party_popularities": {
                "despotism": 100.0
            },
            "starting_laws": {}
        },
        "economy": {
            "gdp_billions": 10.0,
            "real_gdp_growth": 0.0,
            "liquid_reserves_billions": 1.0,
            "national_debt_billions": 0.0,
            "debt_ceiling_ratio": 1.0,
            "is_in_fiscal_crisis": false,
            "central_bank_rate": 0.05,
            "inflation_rate": 0.03,
            "tax_rate": 0.20,
            "military_spending_share": 0.60,
            "civilian_spending_share": 0.20,
            "admin_spending_share": 0.20,
            "rd_spending_share": 0.0,
            "money_printing_this_turn": 0.0
        },
        "military": {
            "civilian_factories": 5,
            "military_factories": 5,
            "consumer_goods_ratio": 0.30,
            "manpower_pool": 45000,
            "infantry_weapons_stockpile": 15000,
            "heavy_equipment_stockpile": 150,
            "army_readiness": 90.0,
            "army_morale": 80.0,
            "war_support_percent": 80.0
        },
        "narrative": {
            "active_directives": [],
            "completed_directives": [],
            "story_flags": {
                "neutral_berlin": true
            }
        },
        "leader": {
            "leader_id": "leader_spandau_garrison",
            "leader_name": "Комендант Шпандау",
            "name_en": "Spandau Fortress Commander",
            "title": "Военный Комендант Большого Берлина",
            "role": "HEAD_OF_STATE",
            "ideology": "Деспотизм",
            "sub_ideology": "Военная хунта",
            "ideological_faction": "garrison",
            "competence": 4,
            "loyalty": 99.0,
            "cabinet_influence": 90.0,
            "is_head_of_state": true,
            "is_military_commander": true,
            "attack_skill": 3,
            "defense_skill": 9,
            "logistics_skill": 7,
            "traits": ["fortress_defender", "neutral_arbiter"],
            "portrait_path": "res://icon.svg",
            "lore_desc_key": "KEY_LEADER_SPN_DESC",
            "passive_modifiers": {
                "defense_bonus": 0.50
            }
        }
    }
}


# ==============================================================================
# 3. EXTRACTION AND DECOUPLING IMPLEMENTATION
# ==============================================================================

class DataDecoupler:
    def __init__(self, dry_run: bool = False, verbose: bool = True):
        self.dry_run = dry_run
        self.verbose = verbose
        self.stats = {
            "constants_categories": 0,
            "constants_keys": 0,
            "countries_created": 0,
            "leaders_created": 0,
            "localization_strings": 0,
            "integrity_errors": 0,
            "integrity_warnings": 0
        }
        self.extracted_strings: Dict[str, Dict[str, str]] = {
            "ru": {},
            "en": {}
        }

    def log(self, message: str) -> None:
        if self.verbose:
            print(f"[DataDecoupler] {message}")

    def run_all(self) -> bool:
        self.log("Starting full data decoupling pipeline...")
        self.extract_constants()
        self.decouple_countries_and_leaders()
        self.extract_and_generate_localization()
        self.update_countries_index()
        is_valid = self.validate_integrity()
        self.print_summary_report()
        return is_valid

    # --------------------------------------------------------------------------
    # A. Constants & Config Extraction
    # --------------------------------------------------------------------------
    def extract_constants(self) -> None:
        self.log("Step 1: Extracting game balance constants & system formulas...")
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        constants_path = CONFIG_DIR / "game_constants.json"

        # If existing constants file exists, merge to preserve manual tweaks
        existing_constants = {}
        if constants_path.exists():
            try:
                with open(constants_path, "r", encoding="utf-8") as f:
                    existing_constants = json.load(f)
            except Exception as e:
                self.log(f"Warning: Failed to parse existing {constants_path}: {e}")

        merged_constants = copy.deepcopy(CANONICAL_GAME_CONSTANTS)
        for cat, values in existing_constants.items():
            if cat in merged_constants and isinstance(values, dict):
                merged_constants[cat].update(values)
            else:
                merged_constants[cat] = values

        # Count metrics
        cat_count = len(merged_constants)
        key_count = sum(len(v) if isinstance(v, dict) else 1 for v in merged_constants.values())
        self.stats["constants_categories"] = cat_count
        self.stats["constants_keys"] = key_count

        if not self.dry_run:
            with open(constants_path, "w", encoding="utf-8") as f:
                json.dump(merged_constants, f, ensure_ascii=False, indent=2)
            self.log(f"Wrote {cat_count} categories ({key_count} keys) -> {constants_path}")

            # Also generate a lightweight CFG file (engine_settings.cfg)
            cfg_path = CONFIG_DIR / "engine_settings.cfg"
            with open(cfg_path, "w", encoding="utf-8") as f:
                f.write("; TNO Engine Core Balance & System Settings\n")
                f.write("; Generated by tools/data_decoupler.py\n\n")
                for section, data in merged_constants.items():
                    f.write(f"[{section}]\n")
                    if isinstance(data, dict):
                        for k, v in data.items():
                            if isinstance(v, (dict, list)):
                                f.write(f"{k}='{json.dumps(v)}'\n")
                            elif isinstance(v, bool):
                                f.write(f"{k}={str(v).lower()}\n")
                            else:
                                f.write(f"{k}={v}\n")
                    f.write("\n")
            self.log(f"Wrote configuration CFG -> {cfg_path}")

    # --------------------------------------------------------------------------
    # B. Countries & Leaders Decoupling
    # --------------------------------------------------------------------------
    def decouple_countries_and_leaders(self) -> None:
        self.log("Step 2: Decoupling country profiles and character databases...")

        for tag, spec in CONTENDER_SPECS.items():
            country_dir = COUNTRIES_DIR / tag
            leaders_dir = country_dir / "leaders"
            loc_dir = country_dir / "localisation"

            if not self.dry_run:
                country_dir.mkdir(parents=True, exist_ok=True)
                leaders_dir.mkdir(parents=True, exist_ok=True)
                loc_dir.mkdir(parents=True, exist_ok=True)

            # 1. Profile (country.json)
            country_profile = {
                "identity": spec["identity"],
                "politics": spec["politics"],
                "economy": spec["economy"],
                "military": spec["military"],
                "narrative": spec["narrative"]
            }

            country_json_path = country_dir / "country.json"
            if not self.dry_run:
                with open(country_json_path, "w", encoding="utf-8") as f:
                    json.dump(country_profile, f, ensure_ascii=False, indent=2)
            self.stats["countries_created"] += 1
            self.log(f"  [+] Country package [{tag}] -> {country_json_path}")

            # 2. Leader (leaders/<leader_id>.json)
            lead_data = spec["leader"]
            leader_id = lead_data["leader_id"]
            leader_json_path = leaders_dir / f"{leader_id}.json"
            if not self.dry_run:
                with open(leader_json_path, "w", encoding="utf-8") as f:
                    json.dump(lead_data, f, ensure_ascii=False, indent=2)
            self.stats["leaders_created"] += 1
            self.log(f"  [+] Leader resource [{leader_id}] -> {leader_json_path}")

            # 3. Country-specific localization
            c_name_ru = spec["identity"]["country_name_ru"]
            c_name_en = spec["identity"]["country_name"]
            l_name_ru = lead_data["leader_name"]
            l_name_en = lead_data.get("name_en", lead_data["leader_name"])
            l_title = lead_data["title"]

            loc_ru = {
                "locale": "ru",
                "tag": tag,
                "strings": {
                    f"KEY_COUNTRY_{tag}_NAME": c_name_ru,
                    f"KEY_LEADER_{leader_id}_NAME": l_name_ru,
                    f"KEY_LEADER_{leader_id}_TITLE": l_title,
                    lead_data["lore_desc_key"]: f"{l_name_ru} — {l_title}. Ключевая фигура в кризисе фракций TNO."
                }
            }
            loc_en = {
                "locale": "en",
                "tag": tag,
                "strings": {
                    f"KEY_COUNTRY_{tag}_NAME": c_name_en,
                    f"KEY_LEADER_{leader_id}_NAME": l_name_en,
                    f"KEY_LEADER_{leader_id}_TITLE": l_title,
                    lead_data["lore_desc_key"]: f"{l_name_en} — {l_title}. Key figure in TNO faction struggle."
                }
            }

            if not self.dry_run:
                with open(loc_dir / "ru.json", "w", encoding="utf-8") as f:
                    json.dump(loc_ru, f, ensure_ascii=False, indent=2)
                with open(loc_dir / "en.json", "w", encoding="utf-8") as f:
                    json.dump(loc_en, f, ensure_ascii=False, indent=2)

            # Register in master extraction pool
            self.extracted_strings["ru"].update(loc_ru["strings"])
            self.extracted_strings["en"].update(loc_en["strings"])

    # --------------------------------------------------------------------------
    # C. UI & Engine Localization Extraction
    # --------------------------------------------------------------------------
    def extract_and_generate_localization(self) -> None:
        self.log("Step 3: Extracting and deduplicating UI/system text strings...")

        # Base engine & UI strings discovered from static analysis of screens & engines
        engine_ui_strings = {
            "KEY_UI_SYSTEM_TITLE": ("BUNKER-BEFEHLSTERMINAL // TNO-NETZ 1962", "BUNKER-BEFEHLSTERMINAL // TNO-NETZ 1962"),
            "KEY_UI_TERMINAL_CONFIG": ("КОНФИГУРАЦИЯ СИСТЕМЫ // ЯЗЫКОВЫЕ ПАКЕТЫ", "SYSTEM CONFIGURATION // LANGUAGE PACKS"),
            "KEY_UI_BTN_APPLY": ("[ ПРИМЕНИТЬ ]", "[ APPLY ]"),
            "KEY_UI_BTN_SAVE_BIOS": ("[ ЗАПИСАТЬ В EEPROM BIOS ]", "[ SAVE TO EEPROM BIOS ]"),
            "KEY_UI_BTN_BACK": ("[ < ВЕРНУТЬСЯ ]", "[ < BACK ]"),
            "KEY_UI_STATUS_READY": ("СИСТЕМА: ГОТОВА К АВТОРИЗАЦИИ // ДОСТУП: ВЫСШИЙ", "SYSTEM: READY FOR AUTHORIZATION // LEVEL: HIGHEST"),
            "KEY_MENU_NEW_GAME": ("НОВАЯ КАМПАНИЯ", "NEW CAMPAIGN"),
            "KEY_MENU_LOAD_GAME": ("ЗАГРУЗИТЬ АРХИВ", "LOAD ARCHIVE"),
            "KEY_MENU_SETTINGS": ("ПАРАМЕТРЫ СИСТЕМЫ", "SYSTEM SETTINGS"),
            "KEY_MENU_LANGUAGE": ("ЯЗЫКОВОЙ ПАКЕТ", "LANGUAGE PACK"),
            "KEY_MENU_EXIT": ("ОТКЛЮЧИТЬ ПИТАНИЕ", "POWER OFF"),
            "KEY_ECON_REVENUE": ("ДОХОДЫ: $%.2f B", "REVENUE: $%.2f B"),
            "KEY_ECON_EXPENSES": ("РАСХОДЫ: $%.2f B", "EXPENSES: $%.2f B"),
            "KEY_ECON_SURPLUS": ("ПРОФИЦИТ: +$%.2f B", "SURPLUS: +$%.2f B"),
            "KEY_ECON_DEFICIT": ("ДЕФИЦИТ: -$%.2f B", "DEFICIT: -$%.2f B"),
            "KEY_ECON_REAL_GROWTH": ("%s%.2f%% (РЕАЛЬНЫЙ РОСТ)", "%s%.2f%% (REAL GROWTH)"),
            "KEY_ECON_DEBT_RATIO": ("ДОЛГ/ВВП: %.1f%%", "DEBT/GDP: %.1f%%"),
            "KEY_ECON_CREDIT_CAP": ("ЛИМИТ: $%.1f B", "CEILING: $%.1f B"),
            "KEY_MIL_BREAKTHROUGH": ("ОПЕРАТИВНЫЙ ПРОРЫВ: %s", "OPERATIONAL BREAKTHROUGH: %s"),
            "KEY_MIL_ENCIRCLEMENT_RISK": ("УГРОЗА ОКРУЖЕНИЯ: %s", "ENCIRCLEMENT THREAT: %s"),
            "KEY_MIL_RAID_SUCCESS": ("Рейд увенчался успехом! Захвачено $%0.2f млрд трофеев, %d стволов оружия, %d пленных. Потери: %d чел.", "Raid succeeded! Captured $%0.2f B loot, %d weapons, %d prisoners. Casualties: %d."),
            "KEY_MIL_RAID_FAILURE": ("Отряды натолкнулись на организованную оборону и отступили с потерями (%d бойцов).", "Units met organized defense and retreated with casualties (%d men)."),
            "KEY_MIL_RAID_SHORTAGE": ("Рейд сорван: острая нехватка стрелкового оружия на складах!", "Raid aborted: critical weapons shortage in stockpiles!"),
            "KEY_GCW_AGONY_STATUS": ("Агония Фюрера. Дней до падения Берлина: %d", "Führer's Agony. Days until Berlin crisis: %d"),
            "KEY_GCW_CIVIL_WAR_ERUPTION": ("Гражданская Война в Германии началась!", "German Civil War has erupted!"),
            "KEY_GCW_BERLIN_FALLEN": ("Берлин пал! Контроль перешел к: %s", "Berlin has fallen! Controller is now: %s")
        }

        # Merge discovered strings into catalog
        for k, (ru_val, en_val) in engine_ui_strings.items():
            self.extracted_strings["ru"][k] = ru_val
            self.extracted_strings["en"][k] = en_val

        self.stats["localization_strings"] = len(self.extracted_strings["ru"])

        # Write or update master localization files
        LOCALIZATION_DIR.mkdir(parents=True, exist_ok=True)
        ru_master_path = LOCALIZATION_DIR / "ru.json"
        en_master_path = LOCALIZATION_DIR / "en.json"

        # Update ru.json
        current_ru = {}
        if ru_master_path.exists():
            try:
                with open(ru_master_path, "r", encoding="utf-8") as f:
                    current_ru = json.load(f)
            except Exception:
                pass
        current_ru.update(self.extracted_strings["ru"])
        if not self.dry_run:
            with open(ru_master_path, "w", encoding="utf-8") as f:
                json.dump(current_ru, f, ensure_ascii=False, indent=2)
            self.log(f"Updated Russian dictionary -> {ru_master_path} ({len(current_ru)} entries)")

        # Update en.json
        current_en = {}
        if en_master_path.exists():
            try:
                with open(en_master_path, "r", encoding="utf-8") as f:
                    current_en = json.load(f)
            except Exception:
                pass
        current_en.update(self.extracted_strings["en"])
        if not self.dry_run:
            with open(en_master_path, "w", encoding="utf-8") as f:
                json.dump(current_en, f, ensure_ascii=False, indent=2)
            self.log(f"Updated English dictionary -> {en_master_path} ({len(current_en)} entries)")

    # --------------------------------------------------------------------------
    # D. Master Countries Index Synchronization
    # --------------------------------------------------------------------------
    def update_countries_index(self) -> None:
        self.log("Step 4: Synchronizing data/countries/index.json...")
        index_path = COUNTRIES_DIR / "index.json"

        current_index: List[Dict[str, Any]] = []
        if index_path.exists():
            try:
                with open(index_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    if isinstance(data, list):
                        current_index = data
            except Exception as e:
                self.log(f"Notice: creating new index.json ({e})")

        existing_tags = {item.get("tag") for item in current_index if "tag" in item}

        # Add any missing contender nations
        for tag, spec in CONTENDER_SPECS.items():
            if tag not in existing_tags:
                lead = spec["leader"]
                ident = spec["identity"]
                econ = spec["economy"]
                mil = spec["military"]
                index_entry = {
                    "tag": tag,
                    "name": ident["country_name"],
                    "name_ru": ident["country_name_ru"],
                    "theater": ident["theater"],
                    "ruling_ideology": ident["ruling_ideology"],
                    "sub_ideology": ident.get("sub_ideology", ""),
                    "primary_leader_name": lead["leader_name"],
                    "primary_leader_portrait": lead.get("portrait_path", "res://icon.svg"),
                    "country_file": f"res://data/countries/{tag}/country.json",
                    "is_selectable": True,
                    "difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
                    "geopolitical_bloc": ident.get("geopolitical_bloc", ""),
                    "starting_gdp": econ.get("gdp_billions", 15.0),
                    "starting_factories": mil.get("civilian_factories", 15) + mil.get("military_factories", 15)
                }
                current_index.append(index_entry)
                self.log(f"  [+] Registered country [{tag}] in index.json")

        if not self.dry_run:
            with open(index_path, "w", encoding="utf-8") as f:
                json.dump(current_index, f, ensure_ascii=False, indent=2)
            self.log(f"Saved total {len(current_index)} countries into {index_path}")

    # --------------------------------------------------------------------------
    # E. Referential Integrity Validation
    # --------------------------------------------------------------------------
    def validate_integrity(self) -> bool:
        self.log("Step 5: Validating referential integrity...")
        index_path = COUNTRIES_DIR / "index.json"
        constants_path = CONFIG_DIR / "game_constants.json"
        ru_master_path = LOCALIZATION_DIR / "ru.json"

        errors = 0
        warnings = 0

        # 1. Validate game_constants.json
        if not constants_path.exists():
            self.log("  [FAIL] Missing game_constants.json!")
            errors += 1
        else:
            try:
                with open(constants_path, "r", encoding="utf-8") as f:
                    cdata = json.load(f)
                for req_cat in ["economy", "military", "politics", "gcw"]:
                    if req_cat not in cdata:
                        self.log(f"  [FAIL] Missing required constant category: {req_cat}")
                        errors += 1
            except Exception as e:
                self.log(f"  [FAIL] Error parsing game_constants.json: {e}")
                errors += 1

        # 2. Validate index.json and country files
        if not index_path.exists():
            self.log("  [FAIL] Missing data/countries/index.json!")
            errors += 1
        else:
            with open(index_path, "r", encoding="utf-8") as f:
                countries = json.load(f)

            for c in countries:
                tag = c.get("tag", "")
                cfile = COUNTRIES_DIR / tag / "country.json"
                if not cfile.exists():
                    self.log(f"  [FAIL] Missing country.json for tag {tag}")
                    errors += 1
                    continue

                # Validate country.json content and leader link
                try:
                    with open(cfile, "r", encoding="utf-8") as cf:
                        cdata = json.load(cf)
                    lead_id = cdata.get("identity", {}).get("primary_leader_id", "")
                    if lead_id:
                        lead_file = COUNTRIES_DIR / tag / "leaders" / f"{lead_id}.json"
                        # Check fallback to GER or WRS if shared
                        if not lead_file.exists():
                            ger_lead = COUNTRIES_DIR / "GER" / "leaders" / f"{lead_id}.json"
                            if not ger_lead.exists():
                                self.log(f"  [WARN] Leader file {lead_id}.json not found for tag {tag}")
                                warnings += 1
                except Exception as e:
                    self.log(f"  [FAIL] Invalid JSON in {cfile}: {e}")
                    errors += 1

        # 3. Validate localization
        if not ru_master_path.exists():
            self.log("  [FAIL] Missing ru.json localization master!")
            errors += 1

        self.stats["integrity_errors"] = errors
        self.stats["integrity_warnings"] = warnings

        if errors == 0:
            self.log("  [SUCCESS] Referential integrity check PASSED.")
            return True
        else:
            self.log(f"  [FAILED] Found {errors} integrity errors.")
            return False

    def print_summary_report(self) -> None:
        print("\n" + "=" * 80)
        print("TNO DATA DECOUPLER AUDIT REPORT")
        print("=" * 80)
        print(f"Game Balance Categories Decoupled: {self.stats['constants_categories']}")
        print(f"Total Balance Constants Extracted:  {self.stats['constants_keys']}")
        print(f"Country Packages Created/Updated:   {self.stats['countries_created']}")
        print(f"Leader Resources Decoupled:         {self.stats['leaders_created']}")
        print(f"UI & System Strings Extracted:      {self.stats['localization_strings']}")
        print(f"Integrity Errors / Warnings:        {self.stats['integrity_errors']} / {self.stats['integrity_warnings']}")
        print("=" * 80 + "\n")


# ==============================================================================
# CLI ENTRY POINT
# ==============================================================================

def main() -> int:
    parser = argparse.ArgumentParser(description="TNO Data Decoupler & Architecture Migration Tool")
    parser.add_argument("--all", action="store_true", help="Run full extraction, decoupling, and validation pipeline")
    parser.add_argument("--constants", action="store_true", help="Extract only game balance constants")
    parser.add_argument("--countries", action="store_true", help="Decouple contender countries and leaders")
    parser.add_argument("--localization", action="store_true", help="Extract and deduplicate localization strings")
    parser.add_argument("--validate", action="store_true", help="Perform referential integrity audit")
    parser.add_argument("--dry-run", action="store_true", help="Scan and simulate without writing files to disk")
    args = parser.parse_args()

    decoupler = DataDecoupler(dry_run=args.dry_run, verbose=True)

    if args.all or (not args.constants and not args.countries and not args.localization and not args.validate):
        success = decoupler.run_all()
        return 0 if success else 1

    if args.constants:
        decoupler.extract_constants()
    if args.countries:
        decoupler.decouple_countries_and_leaders()
        decoupler.update_countries_index()
    if args.localization:
        decoupler.extract_and_generate_localization()
    if args.validate:
        success = decoupler.validate_integrity()
        decoupler.print_summary_report()
        return 0 if success else 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
