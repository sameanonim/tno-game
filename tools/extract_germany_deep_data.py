#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
================================================================================
TNO GERMANY DEEP DATA EXTRACTOR & ADAPTER
================================================================================
Extracts, structures and adapts authentic Germany content from TNO mod:
1. Localizations (Russian & English)
2. Decisions & Crisis Mechanics (Kartenhaus, Zollverein, Silos, Warplans, Slave unrest)
3. Narrative Events (Hitler's Agony, GCW, Contenders, Slave Revolt, Foreign crises)
4. Leadership & Factions Profile
================================================================================
"""

import os
import sys
import re
import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

sys.stdout.reconfigure(encoding='utf-8')

PROJECT_ROOT = Path(__file__).resolve().parent.parent
BASE_MOD = Path(r"F:\SteamLibrary\steamapps\workshop\content\394360\2438003901")
SUBMOD = Path(r"F:\SteamLibrary\steamapps\workshop\content\394360\3579472890")
RUS_MOD = Path(r"F:\SteamLibrary\steamapps\workshop\content\394360\2351077206")
RUS_SUBMOD = Path(r"F:\SteamLibrary\steamapps\workshop\content\394360\3753104676")

GER_DIR = PROJECT_ROOT / "data" / "countries" / "GER"


def clean_hoi4_text(text: str) -> str:
    """Strips HoI4 formatting codes like §Y, §R, §!, £icon, [GetDateText], etc."""
    if not text:
        return ""
    text = re.sub(r'£[a-zA-Z0-9_]+', '', text)
    text = re.sub(r'§[a-zA-Z0-9!]', '', text)
    text = re.sub(r'\[[a-zA-Z0-9_\.]+\]', '', text)
    text = text.replace('\\"', '"').replace('\\n', '\n').strip()
    if text.startswith('"') and text.endswith('"'):
        text = text[1:-1].strip()
    return text


class LocalizationStore:
    def __init__(self):
        self.ru_strings: Dict[str, str] = {}
        self.en_strings: Dict[str, str] = {}

    def load_file(self, filepath: Path, is_ru: bool):
        if not filepath.exists():
            return
        target = self.ru_strings if is_ru else self.en_strings
        try:
            with open(filepath, 'r', encoding='utf-8-sig', errors='ignore') as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith('#') or line.startswith('l_'):
                        continue
                    m = re.match(r'^([a-zA-Z0-9_\.\-]+):\d*\s*"(.*)"\s*$', line)
                    if m:
                        key, val = m.group(1), m.group(2)
                        target[key] = clean_hoi4_text(val)
        except Exception as e:
            print(f"[WARN] Error reading loc file {filepath.name}: {e}")

    def load_directory(self, dirpath: Path, is_ru: bool, filter_prefix: str = ""):
        if not dirpath.exists():
            return
        for p in dirpath.rglob("*.yml"):
            if filter_prefix and filter_prefix.lower() not in p.name.lower():
                continue
            self.load_file(p, is_ru)

    def get_text(self, key: str, fallback: str = "") -> str:
        if key in self.ru_strings and self.ru_strings[key]:
            return self.ru_strings[key]
        if key in self.en_strings and self.en_strings[key]:
            return self.en_strings[key]
        return fallback

    def get_dual(self, key: str, fallback: str = "") -> Tuple[str, str]:
        ru = self.ru_strings.get(key, fallback)
        en = self.en_strings.get(key, fallback)
        if not ru and en:
            ru = en
        return ru, en


def load_all_localizations() -> LocalizationStore:
    store = LocalizationStore()
    print("--> Loading German Russian localizations...")
    ru_loc_dir = RUS_MOD / "localisation" / "russian"
    store.load_directory(ru_loc_dir, is_ru=True, filter_prefix="GER")
    store.load_directory(ru_loc_dir, is_ru=True, filter_prefix="Germany")
    store.load_directory(ru_loc_dir, is_ru=True, filter_prefix="Speer")
    store.load_directory(ru_loc_dir, is_ru=True, filter_prefix="Bormann")
    store.load_directory(ru_loc_dir, is_ru=True, filter_prefix="Goering")
    store.load_directory(ru_loc_dir, is_ru=True, filter_prefix="Heydrich")
    store.load_directory(ru_loc_dir, is_ru=True, filter_prefix="Kartenhaus")
    store.load_directory(ru_loc_dir, is_ru=True, filter_prefix="militarist")
    store.load_directory(ru_loc_dir, is_ru=True, filter_prefix="decisions")
    store.load_directory(ru_loc_dir, is_ru=True, filter_prefix="events")

    ru_submod_dir = RUS_SUBMOD / "localisation" / "russian"
    if ru_submod_dir.exists():
        store.load_directory(ru_submod_dir, is_ru=True, filter_prefix="GER")
        store.load_directory(ru_submod_dir, is_ru=True, filter_prefix="Germany")
        store.load_directory(ru_submod_dir, is_ru=True, filter_prefix="2WRW")

    print(f"    Loaded {len(store.ru_strings)} Russian keys.")

    print("--> Loading German English localizations...")
    en_loc_dir = BASE_MOD / "localisation" / "english"
    store.load_directory(en_loc_dir, is_ru=False, filter_prefix="GER")
    store.load_directory(en_loc_dir, is_ru=False, filter_prefix="Germany")
    store.load_directory(en_loc_dir, is_ru=False, filter_prefix="Speer")
    store.load_directory(en_loc_dir, is_ru=False, filter_prefix="Bormann")
    store.load_directory(en_loc_dir, is_ru=False, filter_prefix="Goering")
    store.load_directory(en_loc_dir, is_ru=False, filter_prefix="Heydrich")
    store.load_directory(en_loc_dir, is_ru=False, filter_prefix="Kartenhaus")
    store.load_directory(en_loc_dir, is_ru=False, filter_prefix="decisions")
    store.load_directory(en_loc_dir, is_ru=False, filter_prefix="events")
    print(f"    Loaded {len(store.en_strings)} English keys.")

    return store


def parse_clausewitz_events(filepath: Path, loc_store: LocalizationStore) -> List[Dict[str, Any]]:
    """Simple robust regex scanner for HoI4 country_event blocks."""
    if not filepath.exists():
        return []

    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()

    # Match country_event = { ... }
    event_blocks = re.findall(r'(country_event|news_event)\s*=\s*\{([^{}]*(?:\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}[^{}]*)*)\}', content)
    
    parsed_events: List[Dict[str, Any]] = []

    for ev_type, block in event_blocks:
        # Extract id
        m_id = re.search(r'\bid\s*=\s*([a-zA-Z0-9_\.\-]+)', block)
        if not m_id:
            continue
        event_id = m_id.group(1).strip()

        # Title
        m_title = re.search(r'\btitle\s*=\s*([a-zA-Z0-9_\.\-]+|"[^"]+")', block)
        title_raw = m_title.group(1).replace('"', '').strip() if m_title else event_id
        title_ru = loc_store.get_text(title_raw, title_raw)

        # Desc
        m_desc = re.search(r'\bdesc\s*=\s*([a-zA-Z0-9_\.\-]+|"[^"]+")', block)
        desc_raw = m_desc.group(1).replace('"', '').strip() if m_desc else ""
        desc_ru = loc_store.get_text(desc_raw, "")

        # Picture / portrait
        m_pic = re.search(r'\bpicture\s*=\s*([a-zA-Z0-9_\.\-]+)', block)
        picture = m_pic.group(1).strip() if m_pic else ""

        # Options
        options = []
        option_matches = re.findall(r'\boption\s*=\s*\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}', block)
        for opt_block in option_matches:
            m_opt_name = re.search(r'\bname\s*=\s*([a-zA-Z0-9_\.\-]+|"[^"]+")', opt_block)
            opt_name_raw = m_opt_name.group(1).replace('"', '').strip() if m_opt_name else "Принять к сведению."
            opt_name_ru = loc_store.get_text(opt_name_raw, opt_name_raw)

            # Detect basic effects
            effects: Dict[str, Any] = {}
            if "add_political_power" in opt_block:
                m_pp = re.search(r'add_political_power\s*=\s*(-?\d+)', opt_block)
                if m_pp:
                    effects["MOD_PC"] = float(m_pp.group(1))
            if "add_stability" in opt_block:
                m_st = re.search(r'add_stability\s*=\s*(-?[\d\.]+)', opt_block)
                if m_st:
                    effects["MOD_STABILITY"] = float(m_st.group(1))
            if "add_war_support" in opt_block:
                m_ws = re.search(r'add_war_support\s*=\s*(-?[\d\.]+)', opt_block)
                if m_ws:
                    effects["MOD_WAR_SUPPORT"] = float(m_ws.group(1))
            if "set_country_flag" in opt_block:
                m_fl = re.search(r'set_country_flag\s*=\s*([a-zA-Z0-9_\-]+)', opt_block)
                if m_fl:
                    effects["SET_FLAG"] = m_fl.group(1)

            options.append({
                "text": opt_name_ru,
                "effects": effects
            })

        if not options:
            options.append({
                "text": "Принять к сведению.",
                "effects": {}
            })

        parsed_events.append({
            "event_id": event_id,
            "title": title_ru,
            "classification": "[REICHSKANZLEI // EYES ONLY]",
            "description": desc_ru if desc_ru else f"Донесение имперской канцелярии по инциденту {event_id}.",
            "portrait_path": f"res://assets/gfx/interface/events/{picture}.png" if picture else "res://icon.svg",
            "is_modal": True,
            "fire_only_once": True,
            "options": options
        })

    return parsed_events


def extract_all_german_events(loc_store: LocalizationStore) -> List[Dict[str, Any]]:
    print("--> Extracting authentic German narrative events...")
    event_files = [
        BASE_MOD / "events" / "TNO_Germany_Base.txt",
        BASE_MOD / "events" / "TNO_Germany_Bormann.txt",
        BASE_MOD / "events" / "TNO_Germany_Bormann_Dismantlement.txt",
        BASE_MOD / "events" / "TNO_Germany_Speer.txt",
        BASE_MOD / "events" / "TNO_Germany_Heydrich.txt",
        BASE_MOD / "events" / "TNO_Germany_Espionage.txt",
        SUBMOD / "events" / "2WRW_Germany.txt"
    ]

    all_events: List[Dict[str, Any]] = []
    seen_ids: Set[str] = set()

    for ef in event_files:
        if not ef.exists():
            continue
        evs = parse_clausewitz_events(ef, loc_store)
        for ev in evs:
            if ev["event_id"] not in seen_ids:
                seen_ids.add(ev["event_id"])
                all_events.append(ev)

    print(f"    Extracted {len(all_events)} authentic German narrative events!")
    return all_events


def parse_clausewitz_decisions(filepath: Path, loc_store: LocalizationStore, default_cat: str) -> List[Dict[str, Any]]:
    if not filepath.exists():
        return []

    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()

    # Find decision blocks
    decisions: List[Dict[str, Any]] = []
    
    # Extract decision category header if present
    cat_id = default_cat
    m_cat = re.search(r'([a-zA-Z0-9_]+)\s*=\s*\{', content)
    if m_cat:
        cat_id = m_cat.group(1)

    cat_name_ru = loc_store.get_text(cat_id, cat_id.replace("_", " ").title())

    # Find individual decision blocks inside
    # A decision usually looks like: dec_name = { cost = ... days_remove = ... complete_effect = { ... } }
    matches = re.finditer(r'([a-zA-Z0-9_]+)\s*=\s*\{([^{}]*(?:\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}[^{}]*)*)\}', content)

    for m in matches:
        dec_id = m.group(1)
        body = m.group(2)

        # Ignore categories or reserved names
        if dec_id in ("picture", "target_root_trigger", "visible", "available", "cancel_trigger", "remove_effect", "complete_effect", "ai_will_do"):
            continue
        if "complete_effect" not in body and "cost" not in body and "days_remove" not in body:
            continue

        title_ru = loc_store.get_text(dec_id, dec_id.replace("_", " ").title())
        desc_ru = loc_store.get_text(f"{dec_id}_desc", f"Оперативная правительственная инициатива: {title_ru}")

        # Cost extraction
        cost_pc = 25.0
        m_cost = re.search(r'\bcost\s*=\s*(\d+)', body)
        if m_cost:
            cost_pc = float(m_cost.group(1))

        # Cooldown / days
        cooldown = 4
        m_days = re.search(r'\bdays_remove\s*=\s*(\d+)', body)
        if m_days:
            days = int(m_days.group(1))
            cooldown = max(1, days // 7)  # 1 turn = 1 week

        decisions.append({
            "id": dec_id,
            "category": default_cat,
            "category_id": cat_id,
            "category_name": cat_name_ru,
            "title": title_ru,
            "description": desc_ru,
            "cost_pc": cost_pc,
            "cost_cap": 1 if cost_pc >= 40 else 0,
            "cost_money": 0.2 if "economy" in default_cat or "zollverein" in default_cat else 0.0,
            "cooldown_turns": cooldown,
            "fire_only_once": "fire_only_once = yes" in body,
            "requires_tags": ["GER", "BOR", "SPE", "GOR", "HEY"],
            "effects": {
                "log": f"Утверждена директива: «{title_ru}»",
                "modify_stability": 0.02 if "stability" in body else 0.0,
                "modify_pc": -cost_pc
            }
        })

    return decisions


def extract_all_german_decisions(loc_store: LocalizationStore) -> List[Dict[str, Any]]:
    print("--> Extracting authentic German decisions & crisis mechanics...")
    decision_configs = [
        (BASE_MOD / "common" / "decisions" / "TNO_Germany_Base_decisions.txt", "germany_prelude"),
        (BASE_MOD / "common" / "decisions" / "TNO_Germany_Bormann_decisions.txt", "kartenhaus"),
        (BASE_MOD / "common" / "decisions" / "TNO_Germany_Speer_decisions.txt", "speer_reforms"),
        (BASE_MOD / "common" / "decisions" / "TNO_Germany_Heydrich_decisions.txt", "heydrich_crisis"),
        (BASE_MOD / "common" / "decisions" / "TNO_Germany_Espionage_decisions.txt", "espionage"),
        (BASE_MOD / "common" / "decisions" / "TNO_forpol_GER.txt", "foreign_policy"),
    ]

    all_decisions: List[Dict[str, Any]] = []
    seen_ids: Set[str] = set()

    for path, cat in decision_configs:
        if not path.exists():
            continue
        decs = parse_clausewitz_decisions(path, loc_store, cat)
        for d in decs:
            if d["id"] not in seen_ids:
                seen_ids.add(d["id"])
                all_decisions.append(d)

    print(f"    Extracted {len(all_decisions)} authentic German decisions & directives!")
    return all_decisions


def enrich_german_country_profile(loc_store: LocalizationStore):
    print("--> Enriching Germany Country Profile with authentic TNO lore...")
    profile_path = GER_DIR / "country.json"
    
    country_data = {}
    if profile_path.exists():
        with open(profile_path, 'r', encoding='utf-8') as f:
            country_data = json.load(f)

    # 1. Identity & Lore
    identity = country_data.get("identity", {})
    identity["country_tag"] = "GER"
    identity["country_name"] = "Großdeutsches Reich"
    identity["country_name_ru"] = "Великогерманский Рейх Германской Нации"
    identity["theater"] = "theater_world"
    identity["geopolitical_bloc"] = "Einheitspakt (Лидер)"
    identity["primary_leader_id"] = "GER_adolf_hitler"
    identity["leader_name"] = "Адольф Гитлер"
    identity["leader_title"] = "Фюрер и Рейхсканцлер"
    identity["leader_portrait_path"] = "res://data/countries/GER/leaders/portraits/GER_adolf_hitler.png"
    identity["country_color"] = [0.45, 0.45, 0.45, 1.0]
    identity["traits"] = [
        "Колосс на глиняных ногах",
        "Институт рабского труда",
        "Тень Атлантропы",
        "Грызня за корону Рейха"
    ]
    identity["lore"] = (
        "Германия правит крупнейшей колониальной империей в истории человечества, простирающейся от берегов Сены "
        "до Уральских гор. Однако за помпезными фасадами Зала Народа (Volkshalle) скрывается глубочайшее системное гниение. "
        "Экономика истощена колоссальным государственным долгом, махинациями Рейхсбанка и строительством циклопических мегапроектов.\n\n"
        "Миллионы подневольных рабов сковывают технологический прогресс, а улицы немецких городов сотрясаются от студенческих стачек. "
        "Здоровье стареющего фюрера катастрофически ухудшается, и четыре могущественные клики — бюрократы Бормана, реформаторы Шпеера, "
        "милитаристы Гёринга и эсэсовцы Гейдриха — уже взвели курки в ожидании решающей битвы за будущее нации."
    )
    country_data["identity"] = identity

    # 2. Politics, Contenders & Factions
    politics = country_data.get("politics", {})
    politics["political_capital"] = 140.0
    politics["pc_gain_per_turn"] = 8.0
    politics["max_cap"] = 7
    politics["current_cap"] = 7
    politics["legitimacy"] = 75.0
    politics["radicalization"] = 35.0
    
    # 4 factions loyalty
    politics["factions_loyalty"] = {
        "bureaucrats_bormann": 65.0,
        "reformers_speer": 55.0,
        "militarists_goering": 60.0,
        "ss_heydrich": 40.0,
        "neutral_speidel": 80.0
    }

    # Contenders detailed info
    politics["contenders"] = {
        "BOR": {
            "name": "Мартин Борман",
            "title": "Секретарь НСДАП",
            "faction": "Партийный аппарат и ортодоксальный нацизм",
            "influence": 30.0,
            "mechanic": "kartenhaus",
            "portrait": "res://data/countries/GER/leaders/portraits/GER_martin_bormann.png"
        },
        "SPE": {
            "name": "Альберт Шпеер",
            "title": "Главный Архитектор и Рейхсминистр",
            "faction": "Технократы, студенты и Четвёрка реформаторов",
            "influence": 28.0,
            "mechanic": "zollverein_regime_meter",
            "portrait": "res://data/countries/GER/leaders/portraits/GER_albert_speer.png"
        },
        "GOR": {
            "name": "Герман Гёринг",
            "title": "Рейхсмаршал Великогерманского Рейха",
            "faction": "Генералитет Вермахта и ВПК",
            "influence": 25.0,
            "mechanic": "war_plans_plunder",
            "portrait": "res://data/countries/GER/leaders/portraits/GER_hermann_goring.png"
        },
        "HEY": {
            "name": "Рейнхард Гейдрих",
            "title": "Обергруппенфюрер СС",
            "faction": "Черный Орден и Бургундские ячейки",
            "influence": 17.0,
            "mechanic": "nuclear_silos_defense",
            "portrait": "res://data/countries/GER/leaders/portraits/GER_reinhard_heydrich.png"
        }
    }

    # Macroeconomic starting parameters
    economy = country_data.get("economy", {})
    economy["gdp"] = 285.4
    economy["gdp_growth"] = -0.012  # Stagnation / crisis
    economy["treasury"] = 14.5
    economy["debt"] = 248.0
    economy["inflation"] = 0.084
    economy["interest_rate"] = 0.055
    economy["consumer_goods_ratio"] = 0.42
    economy["military_goods_ratio"] = 0.58
    economy["slaves_count_millions"] = 9.8
    economy["slave_unrest_level"] = 0.45
    country_data["economy"] = economy

    with open(profile_path, 'w', encoding='utf-8') as f:
        json.dump(country_data, f, ensure_ascii=False, indent=2)

    print("    Germany Country Profile saved successfully!")


def main():
    print("================================================================================")
    print("STARTING GERMANY DEEP DATA EXTRACTION PIPELINE")
    print("================================================================================")
    
    loc_store = load_all_localizations()
    
    events = extract_all_german_events(loc_store)
    events_out_path = GER_DIR / "events.json"
    with open(events_out_path, 'w', encoding='utf-8') as f:
        json.dump(events, f, ensure_ascii=False, indent=2)
    print(f"--> Saved {len(events)} events to {events_out_path}")

    decisions = extract_all_german_decisions(loc_store)
    decisions_out_path = GER_DIR / "decisions.json"
    with open(decisions_out_path, 'w', encoding='utf-8') as f:
        json.dump(decisions, f, ensure_ascii=False, indent=2)
    print(f"--> Saved {len(decisions)} decisions to {decisions_out_path}")

    enrich_german_country_profile(loc_store)

    print("================================================================================")
    print("GERMANY DEEP DATA EXTRACTION COMPLETED SUCCESSFULLY!")
    print("================================================================================")


if __name__ == "__main__":
    main()
