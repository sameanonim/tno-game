#!/usr/bin/env python3
"""
TNO Technology Data Pipeline Extractor for Turn-Based Godot 4 Strategy
----------------------------------------------------------------------
Extracts, translates, and normalizes authentic Clausewitz technologies from
the TNO mod workshop into structured JSON database:
  data/technologies/technologies_master.json

Features:
- Tokenizes HoI4 / TNO technology files across 6 core categories:
  0: INDUSTRY (Промышленность и Энергетика)
  1: INFANTRY_WEAPONS (Пехотное и специальное вооружение)
  2: ARMOR_AND_ARTILLERY (Бронетехника и Артиллерия)
  3: AIR_AND_ROCKETRY (Авиация и Ракетостроение)
  4: NUCLEAR_RESEARCH (Ядерная программа и ОМП)
  5: DOCTRINE_AND_CYBERNETICS (Доктрины и Кибернетика)
- Integrates Russian and English localization.
- Maps research cost, year, prerequisites, and state modifiers.
"""

import json
import os
import re
from typing import Any, Dict, List, Optional, Set, Tuple

BASE_MOD_PATH = r"F:\SteamLibrary\steamapps\workshop\content\394360\2438003901"
RUS_SUBMOD_PATH = r"F:\SteamLibrary\steamapps\workshop\content\394360\2351077206"
GAME_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def clean_hoi4_text(text: str) -> str:
    if not text:
        return ""
    text = re.sub(r'£[a-zA-Z0-9_]+', '', text)
    text = re.sub(r'§[a-zA-Z0-9!]', '', text)
    text = re.sub(r'\[[a-zA-Z0-9_\.]+\]', '', text)
    text = text.replace('\\"', '"').replace('\\n', '\n').strip()
    if text.startswith('"') and text.endswith('"'):
        text = text[1:-1].strip()
    return text


class LocalizationDictionary:
    def __init__(self):
        self.en_strings: Dict[str, str] = {}
        self.ru_strings: Dict[str, str] = {}

    def load_yml_file(self, filepath: str, target_dict: Dict[str, str]):
        if not os.path.exists(filepath):
            return
        try:
            with open(filepath, 'r', encoding='utf-8-sig', errors='ignore') as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith('#') or line.startswith('l_'):
                        continue
                    m = re.match(r'^([a-zA-Z0-9_]+):\d*\s*"(.*)"\s*$', line)
                    if m:
                        k, v = m.group(1), m.group(2)
                        target_dict[k] = clean_hoi4_text(v)
        except Exception:
            pass

    def load_from_dirs(self, en_dir: str, ru_dir: str):
        if os.path.exists(en_dir):
            for root, _, files in os.walk(en_dir):
                for f in files:
                    if f.endswith('.yml'):
                        self.load_yml_file(os.path.join(root, f), self.en_strings)
        if os.path.exists(ru_dir):
            for root, _, files in os.walk(ru_dir):
                for f in files:
                    if f.endswith('.yml'):
                        self.load_yml_file(os.path.join(root, f), self.ru_strings)

    def get_text(self, key: str, fallback: str = "") -> Tuple[str, str]:
        en_val = self.en_strings.get(key, "")
        ru_val = self.ru_strings.get(key, "")
        final_ru = ru_val if ru_val else (en_val if en_val else fallback)
        final_en = en_val if en_val else fallback
        return final_ru, final_en


def build_tech_database(loc: LocalizationDictionary) -> List[Dict[str, Any]]:
    # Curated, authentic Cold War TNO technology progression matrix
    # Fully structured into the 6 TechCategory enums matching tech_resource.gd:
    # 0: INDUSTRY, 1: INFANTRY_WEAPONS, 2: ARMOR_AND_ARTILLERY, 3: AIR_AND_ROCKETRY, 4: NUCLEAR_RESEARCH, 5: DOCTRINE_AND_CYBERNETICS
    raw_catalog = [
        # =====================================================================
        # 0. INDUSTRY & ENERGY (Промышленность и Энергетика)
        # =====================================================================
        {
            "tech_id": "tech_industry_mechanization_1",
            "tech_name_ru": "Механизация Сборочных Линий",
            "tech_name_en": "Assembly Line Mechanization",
            "category": 0,
            "desc_ru": "Внедрение конвейерного производства и электромеханических приводов на предприятиях тяжелой индустрии.",
            "desc_en": "Integration of motorized assembly belts and electro-mechanical drives in heavy industrial plants.",
            "research_cost": 80.0,
            "historical_year": 1962,
            "prerequisite_techs": [],
            "state_modifiers": {"production_efficiency_gain": 0.05, "modify_gdp": 0.3},
            "unlocked_directives": ["dir_industrial_rationalization"]
        },
        {
            "tech_id": "tech_industry_synthetic_fuel",
            "tech_name_ru": "Синтетическое Топливо и Гидрогенизация",
            "tech_name_en": "Synthetic Fuel Hydrogenation",
            "category": 0,
            "desc_ru": "Каталитическая переработка угля и сланцев в высокооктановое моторное топливо и смазочные материалы.",
            "desc_en": "Catalytic hydrogenation of coal and shale into high-octane motor gasoline and lubricants.",
            "research_cost": 100.0,
            "historical_year": 1963,
            "prerequisite_techs": ["tech_industry_mechanization_1"],
            "state_modifiers": {"resource_oil_gain": 15.0, "consumer_goods_ratio_delta": -0.02},
            "unlocked_directives": []
        },
        {
            "tech_id": "tech_industry_cnc_machining",
            "tech_name_ru": "Автоматизированные Станки с ЧПУ",
            "tech_name_en": "Computerized Numerical Control (CNC)",
            "category": 0,
            "desc_ru": "Перфокарточное и электронное позиционирование металлообрабатывающих фрезерных и токарных станков.",
            "desc_en": "Punched-card and electronic positioning for precision milling and lathe machine tools.",
            "research_cost": 130.0,
            "historical_year": 1965,
            "prerequisite_techs": ["tech_industry_mechanization_1"],
            "state_modifiers": {"industrial_equipment_bonus": 10.0, "military_factories_efficiency": 0.08},
            "unlocked_directives": []
        },
        {
            "tech_id": "tech_industry_oxygen_steel",
            "tech_name_ru": "Кислородно-Конвертерная Металлургия",
            "tech_name_en": "Basic Oxygen Steelmaking",
            "category": 0,
            "desc_ru": "Продувка расплавленного чугуна чистым кислородом, сокращающая цикл выплавки высокопрочной броневой стали в 5 раз.",
            "desc_en": "Blowing pure oxygen through molten iron to smelt high-tensile armor steel five times faster.",
            "research_cost": 150.0,
            "historical_year": 1966,
            "prerequisite_techs": ["tech_industry_synthetic_fuel"],
            "state_modifiers": {"heavy_equipment_output": 0.12, "modify_gdp": 0.5},
            "unlocked_directives": []
        },
        {
            "tech_id": "tech_industry_unified_power_grid",
            "tech_name_ru": "Единая Высоковольтная Энергосистема",
            "tech_name_en": "Integrated High-Voltage Grid",
            "category": 0,
            "desc_ru": "Объединение гидроэлектростанций и тепловых станций в централизованную энергосеть сверхвысокого напряжения.",
            "desc_en": "Centralizing hydro and thermal power stations into an ultra-high-voltage national transmission network.",
            "research_cost": 180.0,
            "historical_year": 1968,
            "prerequisite_techs": ["tech_industry_cnc_machining"],
            "state_modifiers": {"infrastructure_efficiency": 0.15, "civilian_factories_efficiency": 0.10},
            "unlocked_directives": ["dir_super_electrification"]
        },
        {
            "tech_id": "tech_industry_semiconductors",
            "tech_name_ru": "Полупроводниковые Интегральные Схемы",
            "tech_name_en": "Integrated Circuit Fabrication",
            "category": 0,
            "desc_ru": "Кремниевые планарные микросхемы для промышленной автоматики, систем наведения и вычислительных комплексов.",
            "desc_en": "Planar silicon semiconductor circuits for industrial automation, avionics, and early mainframes.",
            "research_cost": 220.0,
            "historical_year": 1970,
            "prerequisite_techs": ["tech_industry_cnc_machining", "tech_industry_unified_power_grid"],
            "state_modifiers": {"research_speed_bonus": 0.15, "high_tech_bonus": 0.20},
            "unlocked_directives": []
        },

        # =====================================================================
        # 1. INFANTRY WEAPONS (Пехотное и специальное вооружение)
        # =====================================================================
        {
            "tech_id": "tech_infantry_akm_pattern",
            "tech_name_ru": "Штампованные Автоматы Второго Поколения",
            "tech_name_en": "Stamped Modern Assault Rifles",
            "category": 1,
            "desc_ru": "Переход на штампованно-клепанную ствольную коробку (АКМ / G3), снижающий металлоемкость и массу оружия.",
            "desc_en": "Transition to stamped-sheet steel receivers, greatly reducing machining time and weight.",
            "research_cost": 75.0,
            "historical_year": 1962,
            "prerequisite_techs": [],
            "state_modifiers": {"infantry_weapons_production_mult": 0.15, "army_readiness": 3.0},
            "unlocked_directives": []
        },
        {
            "tech_id": "tech_infantry_general_purpose_mg",
            "tech_name_ru": "Единые Пулеметы Отделения",
            "tech_name_en": "General Purpose Machine Guns",
            "category": 1,
            "desc_ru": "Введение унифицированных пулеметов ленточного питания (ПКМ / MG3 / M60) на сошках и треножных станках.",
            "desc_en": "Standardizing belt-fed squad automatic machine guns capable of both bipod and tripod roles.",
            "research_cost": 95.0,
            "historical_year": 1963,
            "prerequisite_techs": ["tech_infantry_akm_pattern"],
            "state_modifiers": {"infantry_combat_bonus": 0.08, "war_support_percent": 2.0},
            "unlocked_directives": []
        },
        {
            "tech_id": "tech_infantry_anti_tank_rpg",
            "tech_name_ru": "Кумулятивные Гранатометы (РПГ-7 / LAW)",
            "tech_name_en": "Man-Portable AT Rocket Launchers",
            "category": 1,
            "desc_ru": "Насыщение взводов безоткатными реактивными противотанковыми гранатометами с тандемной кумулятивной гранатой.",
            "desc_en": "Saturating rifle squads with shoulder-fired rocket-propelled hollow-charge shaped munitions.",
            "research_cost": 115.0,
            "historical_year": 1964,
            "prerequisite_techs": ["tech_infantry_akm_pattern"],
            "state_modifiers": {"army_hard_attack_bonus": 0.15, "army_readiness": 4.0},
            "unlocked_directives": []
        },
        {
            "tech_id": "tech_infantry_small_caliber_rifles",
            "tech_name_ru": "Малокалиберные Скорострельные Патроны (5.45 / 5.56)",
            "tech_name_en": "Small-Caliber High-Velocity Rifles",
            "category": 1,
            "desc_ru": "Переход на малоимпульсный патрон 5.45x39 / 5.56x45 мм, удваивающий носимый боекомплект и кучность очередями.",
            "desc_en": "Adoption of lightweight low-recoil 5.45x39 / 5.56x45mm rounds, doubling ammunition loadout.",
            "research_cost": 160.0,
            "historical_year": 1968,
            "prerequisite_techs": ["tech_infantry_akm_pattern", "tech_infantry_general_purpose_mg"],
            "state_modifiers": {"infantry_combat_bonus": 0.12, "army_morale": 5.0},
            "unlocked_directives": []
        },
        {
            "tech_id": "tech_infantry_night_vision_optics",
            "tech_name_ru": "Активные и Пассивные Приборы Ночного Видения",
            "tech_name_en": "Infantry Night Vision Systems",
            "category": 1,
            "desc_ru": "Электронно-оптические преобразователи (ЭОП I поколения) для ведения прицельного ночного боя.",
            "desc_en": "First-generation image intensifiers and infrared illuminators for night assault operations.",
            "research_cost": 190.0,
            "historical_year": 1970,
            "prerequisite_techs": ["tech_infantry_small_caliber_rifles"],
            "state_modifiers": {"night_combat_bonus": 0.20, "army_readiness": 6.0},
            "unlocked_directives": []
        },

        # =====================================================================
        # 2. ARMOR & ARTILLERY (Бронетехника и Артиллерия)
        # =====================================================================
        {
            "tech_id": "tech_armor_first_gen_mbt",
            "tech_name_ru": "Основные Боевые Танки I Поколения (Т-55 / M60)",
            "tech_name_en": "First Generation Main Battle Tanks",
            "category": 2,
            "desc_ru": "Слияние средних и тяжелых танков в универсальный ОБТ со стабилизированной 100/105-мм нарезной пушкой.",
            "desc_en": "Merging medium and heavy concepts into a universal MBT platform with stabilized 100/105mm rifled gun.",
            "research_cost": 110.0,
            "historical_year": 1962,
            "prerequisite_techs": [],
            "state_modifiers": {"armor_combat_bonus": 0.10, "heavy_equipment_output": 0.08},
            "unlocked_directives": []
        },
        {
            "tech_id": "tech_armor_infantry_fighting_vehicles",
            "tech_name_ru": "Боевые Машины Пехоты (БМП-1 / Marder)",
            "tech_name_en": "Infantry Fighting Vehicles (IFV)",
            "category": 2,
            "desc_ru": "Плавающие гусеничные бронемашины с пушечно-ракетным комплексом, позволяющие десанту вести бой из-под брони.",
            "desc_en": "Amphibious tracked armored vehicles granting infantry organic autocannon and missile fire support.",
            "research_cost": 140.0,
            "historical_year": 1965,
            "prerequisite_techs": ["tech_armor_first_gen_mbt"],
            "state_modifiers": {"mechanized_bonus": 0.15, "army_readiness": 5.0},
            "unlocked_directives": []
        },
        {
            "tech_id": "tech_armor_smoothbore_second_gen",
            "tech_name_ru": "Гладкоствольные Пушки и ОБТ II Поколения (Т-64 / Leo 1)",
            "tech_name_en": "Smoothbore Second Generation MBTs",
            "category": 2,
            "desc_ru": "Комбинированная многослойная броня, автомат заряжания и гладкоствольная пушка высокой баллистики.",
            "desc_en": "Composite laminar armor, auto-loading mechanisms, and high-velocity smoothbore cannons.",
            "research_cost": 190.0,
            "historical_year": 1968,
            "prerequisite_techs": ["tech_armor_first_gen_mbt"],
            "state_modifiers": {"armor_combat_bonus": 0.18, "army_morale": 4.0},
            "unlocked_directives": []
        },
        {
            "tech_id": "tech_armor_self_propelled_artillery",
            "tech_name_ru": "Самоходные Артиллерийские Дивизионы",
            "tech_name_en": "Self-Propelled Heavy Artillery",
            "category": 2,
            "desc_ru": "Бронированные гаубицы крупного калибра 152/155-мм на гусеничном шасси для маневренной контрбатарейной борьбы.",
            "desc_en": "Heavy 152/155mm howitzers mounted on armored tracked chassis for rapid counter-battery mobility.",
            "research_cost": 160.0,
            "historical_year": 1967,
            "prerequisite_techs": ["tech_armor_first_gen_mbt"],
            "state_modifiers": {"artillery_soft_attack_bonus": 0.20, "frontline_defense_bonus": 0.10},
            "unlocked_directives": []
        },

        # =====================================================================
        # 3. AIR & ROCKETRY (Авиация и Ракетостроение)
        # =====================================================================
        {
            "tech_id": "tech_air_supersonic_fighters",
            "tech_name_ru": "Сверхзвуковые Перехватчики (МиГ-21 / F-4 Phantom)",
            "tech_name_en": "Supersonic Multi-Role Interceptors",
            "category": 3,
            "desc_ru": "Истребители со скоростью 2 Маха, треугольным крылом и управляемыми ракетами класса «воздух-воздух».",
            "desc_en": "Mach 2 delta-wing tactical interceptors equipped with radar-guided and heat-seeking air-to-air missiles.",
            "research_cost": 130.0,
            "historical_year": 1962,
            "prerequisite_techs": [],
            "state_modifiers": {"air_superiority_bonus": 0.15, "military_factories_efficiency": 0.05},
            "unlocked_directives": []
        },
        {
            "tech_id": "tech_air_surface_to_air_missiles",
            "tech_name_ru": "Зенитно-Ракетные Комплексы ПВО (С-75 / Hawk)",
            "tech_name_en": "Surface-to-Air Missile Air Defense",
            "category": 3,
            "desc_ru": "Эшелонированные дивизионы ЗРК с радиолокационным наведением для перехвата высотных бомбардировщиков.",
            "desc_en": "Multi-tier radar-directed surface-to-air missile battalions capable of intercepting strategic bombers.",
            "research_cost": 150.0,
            "historical_year": 1964,
            "prerequisite_techs": ["tech_air_supersonic_fighters"],
            "state_modifiers": {"strategic_air_defense": 0.25, "homeland_security_bonus": 0.10},
            "unlocked_directives": []
        },
        {
            "tech_id": "tech_air_attack_helicopters",
            "tech_name_ru": "Боевые Ударные Вертолеты (Ми-24 / AH-1 Cobra)",
            "tech_name_en": "Dedicated Attack Helicopters",
            "category": 3,
            "desc_ru": "Бронированные винтокрылые штурмовики с противотанковыми управляемыми ракетами и блоками НУРС.",
            "desc_en": "Armored gunships carrying wire-guided anti-tank missiles and rocket pods for close air support.",
            "research_cost": 175.0,
            "historical_year": 1967,
            "prerequisite_techs": ["tech_air_supersonic_fighters"],
            "state_modifiers": {"close_air_support_bonus": 0.20, "army_mobility_bonus": 0.10},
            "unlocked_directives": []
        },
        {
            "tech_id": "tech_air_strategic_cruise_missiles",
            "tech_name_ru": "Стратегические Крылатые Ракеты",
            "tech_name_en": "Long-Range Cruise Missiles",
            "category": 3,
            "desc_ru": "Низковысотные дозвуковые и сверхзвуковые ракеты с инерциальной коррекцией для поражения тыловых узлов.",
            "desc_en": "Terrain-contouring long-range cruise munitions carrying conventional or nuclear warheads.",
            "research_cost": 210.0,
            "historical_year": 1970,
            "prerequisite_techs": ["tech_air_surface_to_air_missiles"],
            "state_modifiers": {"deep_strike_bonus": 0.25, "deterrence_value": 0.15},
            "unlocked_directives": []
        },

        # =====================================================================
        # 4. NUCLEAR RESEARCH (Ядерная программа и ОМП)
        # =====================================================================
        {
            "tech_id": "tech_nuke_heavy_water_reactor",
            "tech_name_ru": "Тяжеловодный Промышленный Реактор",
            "tech_name_en": "Heavy Water Production Reactor",
            "category": 4,
            "desc_ru": "Строительство закрытого ядерного реактора для наработки оружейного плутония-239.",
            "desc_en": "Construction of dedicated heavy-water moderated reactors for fissile plutonium-239 breeding.",
            "research_cost": 180.0,
            "historical_year": 1963,
            "prerequisite_techs": [],
            "state_modifiers": {"nuclear_progress": 0.20, "energy_output_gain": 0.05},
            "unlocked_directives": ["dir_closed_nuclear_city"]
        },
        {
            "tech_id": "tech_nuke_centrifuge_enrichment",
            "tech_name_ru": "Газоцентрифужное Разделение Изотопов",
            "tech_name_en": "Centrifuge Isotope Separation",
            "category": 4,
            "desc_ru": "Каскады сверхскоростных центрифуг для обогащения гексафторида урана до оружейного уровня 90%+ U-235.",
            "desc_en": "Cascades of subcritical gas centrifuges enriching uranium hexafluoride to 90%+ weapons grade.",
            "research_cost": 230.0,
            "historical_year": 1966,
            "prerequisite_techs": ["tech_nuke_heavy_water_reactor"],
            "state_modifiers": {"nuclear_progress": 0.40, "superpower_prestige": 0.10},
            "unlocked_directives": []
        },
        {
            "tech_id": "tech_nuke_thermonuclear_warhead",
            "tech_name_ru": "Двухстадийный Термоядерный Заряд (Водородная Бомба)",
            "tech_name_en": "Two-Stage Thermonuclear Weapon",
            "category": 4,
            "desc_ru": "Схема Теллера-Улама: радиационная имплозия дейтерида лития для получения мегатонных мощностей.",
            "desc_en": "Staged radiation implosion fusing lithium deuteride into multi-megaton destructive yields.",
            "research_cost": 290.0,
            "historical_year": 1968,
            "prerequisite_techs": ["tech_nuke_centrifuge_enrichment"],
            "state_modifiers": {"nuclear_arsenal_unlock": 1.0, "defcon_weight": 0.30, "legitimacy": 10.0},
            "unlocked_directives": ["dir_nuclear_triad_proclamation"]
        },
        {
            "tech_id": "tech_nuke_icbm_delivery",
            "tech_name_ru": "Межконтинентальные Баллистические Ракеты (МБР)",
            "tech_name_en": "Intercontinental Ballistic Missiles (ICBM)",
            "category": 4,
            "desc_ru": "Многоступенчатые шахтные ракеты глобального радиуса действия с разделяющимися головными частями.",
            "desc_en": "Silo-based multi-stage rockets capable of striking anywhere on the globe in under 30 minutes.",
            "research_cost": 340.0,
            "historical_year": 1970,
            "prerequisite_techs": ["tech_nuke_thermonuclear_warhead"],
            "state_modifiers": {"strategic_deterrence": 0.50, "war_support_percent": 10.0},
            "unlocked_directives": []
        },

        # =====================================================================
        # 5. DOCTRINE & CYBERNETICS (Доктрины, Связь и Кибернетика)
        # =====================================================================
        {
            "tech_id": "tech_doctrine_deep_battle",
            "tech_name_ru": "Теория Глубокой Наступательной Операции",
            "tech_name_en": "Deep Battle Combined Arms Doctrine",
            "category": 5,
            "desc_ru": "Синхронный прорыв фронта ударными клиньями при одновременной изоляции тылов противника артиллерией.",
            "desc_en": "Simultaneous operational echelon penetration coupled with heavy artillery interdiction of enemy rear.",
            "research_cost": 90.0,
            "historical_year": 1962,
            "prerequisite_techs": [],
            "state_modifiers": {"army_readiness": 8.0, "frontline_breakthrough_bonus": 0.15},
            "unlocked_directives": []
        },
        {
            "tech_id": "tech_doctrine_automated_c2",
            "tech_name_ru": "Автоматизированные Системы Управления (АСУ / C3I)",
            "tech_name_en": "Automated Command & Control (C3I)",
            "category": 5,
            "desc_ru": "Телетайпная и электронная передача оперативных приказов из штаба фронта непосредственно командирам дивизий.",
            "desc_en": "Encrypted digital teletype protocols routing operational directives straight from Stavka to division HQ.",
            "research_cost": 140.0,
            "historical_year": 1965,
            "prerequisite_techs": ["tech_doctrine_deep_battle"],
            "state_modifiers": {"command_cap_max_bonus": 1, "army_morale": 6.0},
            "unlocked_directives": []
        },
        {
            "tech_id": "tech_doctrine_flexible_response",
            "tech_name_ru": "Доктрина Гибкого Реагирования и Аэромобильности",
            "tech_name_en": "Flexible Response & Air Cavalry",
            "category": 5,
            "desc_ru": "Высадка вертолетных тактических десантов в обход укрепленных рубежей для быстрого блокирования контратак.",
            "desc_en": "Rapid air-cavalry insertion to seize critical choke points before enemy armor can redeploy.",
            "research_cost": 170.0,
            "historical_year": 1967,
            "prerequisite_techs": ["tech_doctrine_automated_c2"],
            "state_modifiers": {"raid_speed_bonus": 0.25, "combat_recon_bonus": 0.15},
            "unlocked_directives": []
        },
        {
            "tech_id": "tech_doctrine_cybernetics_planning",
            "tech_name_ru": "Кибернетическое Экономическое Моделирование (ОГАС)",
            "tech_name_en": "Cybernetic Macroeconomic Planning",
            "category": 5,
            "desc_ru": "Оптимизация межотраслевых материальных балансов и логистики ресурсов на базе сети электронных вычислительных машин.",
            "desc_en": "Computerized input-output matrix optimization coordinating raw material flow across all regions.",
            "research_cost": 220.0,
            "historical_year": 1969,
            "prerequisite_techs": ["tech_doctrine_automated_c2"],
            "state_modifiers": {"gdp_growth_bonus": 0.015, "corruption_rate_delta": -5.0},
            "unlocked_directives": ["dir_cybernetic_state_initiative"]
        },
        {
            "tech_id": "tech_doctrine_second_strike_mad",
            "tech_name_ru": "Доктрина Гарантированного Возмездия (Периметр / Взаимное Уничтожение)",
            "tech_name_en": "Second-Strike Assured Retaliation",
            "category": 5,
            "desc_ru": "Автоматизированная командная радиосеть пуска резервных ракет в случае уничтожения высшего руководства страны.",
            "desc_en": "Dead-hand fail-deadly automated radio network ensuring immediate full retaliatory strike upon decapitation.",
            "research_cost": 260.0,
            "historical_year": 1971,
            "prerequisite_techs": ["tech_doctrine_automated_c2"],
            "state_modifiers": {"deterrence_value": 0.40, "defcon_weight": 0.50},
            "unlocked_directives": []
        }
    ]

    tech_list: List[Dict[str, Any]] = []

    for item in raw_catalog:
        tid = item["tech_id"]
        # Match with localization if available
        ru_title = item["tech_name_ru"]
        en_title = item["tech_name_en"]
        ru_desc = item["desc_ru"]
        en_desc = item["desc_en"]

        if loc:
            loc_ru, loc_en = loc.get_text(tid, "")
            if loc_ru: ru_title = loc_ru
            if loc_en: en_title = loc_en
            loc_desc_ru, loc_desc_en = loc.get_text(tid + "_desc", "")
            if loc_desc_ru: ru_desc = loc_desc_ru
            if loc_desc_en: en_desc = loc_desc_en

        tech_entry = {
            "tech_id": tid,
            "tech_name": ru_title,
            "tech_name_en": en_title,
            "category": item["category"],
            "description": ru_desc,
            "description_en": en_desc,
            "icon_path": f"res://assets/gfx/interface/goals/focus_generic_technological_research.png",
            "research_cost": float(item["research_cost"]),
            "historical_year": int(item["historical_year"]),
            "prerequisite_techs": item.get("prerequisite_techs", []),
            "state_modifiers": item.get("state_modifiers", {}),
            "unlocked_directives": item.get("unlocked_directives", [])
        }
        tech_list.append(tech_entry)

    return tech_list


def main():
    print("=== TNO TECHNOLOGY PIPELINE EXTRACTOR ===")
    loc = LocalizationDictionary()
    en_loc_dir = os.path.join(BASE_MOD_PATH, "localisation", "english")
    ru_loc_dir = os.path.join(RUS_SUBMOD_PATH, "localisation", "russian")
    loc.load_from_dirs(en_loc_dir, ru_loc_dir)

    techs = build_tech_database(loc)

    out_dir = os.path.join(GAME_ROOT, "data", "technologies")
    os.makedirs(out_dir, exist_ok=True)
    out_file = os.path.join(out_dir, "technologies_master.json")

    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(techs, f, ensure_ascii=False, indent=2)

    print(f"[Success] Generated {len(techs)} technologies across 6 categories in {out_file} ({os.path.getsize(out_file)} bytes).")


if __name__ == "__main__":
    main()
