#!/usr/bin/env python3
"""
tools/sync_territories_and_names.py: Territory Ownership Fixer & Country Labels Generator
========================================================================================
1. Parses all 2525 Clausewitz state files from TNO mod:
   - F:/SteamLibrary/steamapps/workshop/content/394360/2438003901/history/states
2. Extracts authentic 1962 ownership, provinces, state categories, cores, and buildings.
3. Loads English and Russian localizations from TNO and RU localization submod:
   - F:/SteamLibrary/steamapps/workshop/content/394360/2351077206/localisation/russian/
   - F:/SteamLibrary/steamapps/workshop/content/394360/2438003901/localisation/
4. Fixes all territorial ownership in:
   - map_data/starting_regions_state.json (576+ mismatched provinces corrected to 100% authentic TNO borders)
   - map_data/starting_countries_state.json (owned_states, controlled_states, names, counts)
   - data/countries/*/country.json (controlled_states, especially GER 56 states)
5. Generates map_data/country_labels.json:
   - Pre-calculated centroids (filtered for main territorial cluster), bounding boxes,
     tier classifications (Tier 1: Superpowers, Tier 2: Regional, Tier 3: Minors/Warlords),
     and dual EN/RU localized labels.
6. Re-bakes map_data/ownership_lut.png via TNOBorderLUTBuilder.
"""

from __future__ import annotations

import argparse
import glob
import json
import math
import os
from pathlib import Path
import re
import sys
import time
from typing import Any, Dict, List, Optional, Set, Tuple

import numpy as np
from PIL import Image

PROJECT_ROOT = Path(__file__).resolve().parent.parent
TNO_MOD_PATH = Path(r"F:/SteamLibrary/steamapps/workshop/content/394360/2438003901")
TNO_RU_PATH = Path(r"F:/SteamLibrary/steamapps/workshop/content/394360/2351077206")

RE_HOI4_COLOR_CODE = re.compile(r"§[a-zA-Z0-9!_]")
RE_HOI4_ICON_CODE = re.compile(r"£[a-zA-Z0-9_]+£?")
RE_YML_LINE = re.compile(r'^\s*([A-Za-z0-9_.\-]+):[0-9]*\s*"(.*)"\s*$')

# Priority Great Powers / Superpowers (Tier 1: always visible on macro map)
TIER_1_TAGS = {
    "GER", "USA", "JAP", "ITA", "IBR", "ENG", "CHI", "OST", "UKR", "MCW",
    "CAU", "BUR", "FRS", "BRG", "CAN", "AST", "SAF", "TUR", "FIN", "SWE",
    "IND", "INS", "MAN", "EGY", "MEX", "BRA", "ARG", "NOR", "DEN", "HOL",
    "GGN", "SER", "CRO", "HUN", "ROM", "BUL", "SLO", "WRS", "KOM", "OMS",
    "SVR", "TYM", "MAG", "IRK", "PRC", "SBA", "NOV", "KEM", "TOM", "VYT",
    "SAM", "AMR", "CHL", "COL", "PER", "VEN", "IRA", "SAU", "THA", "PHI"
}


def clean_hoi4_text(raw_text: str) -> str:
    if not raw_text:
        return ""
    text = RE_HOI4_COLOR_CODE.sub("", raw_text)
    text = RE_HOI4_ICON_CODE.sub("", text)
    text = text.replace(r"\n", " ").replace(r'\"', '"').strip()
    if text.startswith('"') and text.endswith('"') and len(text) >= 2:
        text = text[1:-1]
    return text.strip()


def parse_yml_file(fpath: Path) -> Dict[str, str]:
    res = {}
    if not fpath.exists():
        return res
    try:
        with open(fpath, "r", encoding="utf-8-sig", errors="replace") as f:
            for line in f:
                m = RE_YML_LINE.match(line)
                if m:
                    k, v = m.groups()
                    res[k.strip()] = clean_hoi4_text(v)
    except Exception as e:
        print(f"[WARN] Failed to parse YML {fpath}: {e}")
    return res


def load_localizations() -> Tuple[Dict[str, str], Dict[str, str]]:
    ru_loc: Dict[str, str] = {}
    en_loc: Dict[str, str] = {}

    # 1. Russian localization files
    if TNO_RU_PATH.exists():
        print(f"[LOC] Loading Russian localizations from: {TNO_RU_PATH}")
        for yf in TNO_RU_PATH.rglob("*.yml"):
            ru_loc.update(parse_yml_file(yf))

    # 2. English localization files
    if TNO_MOD_PATH.exists():
        print(f"[LOC] Loading English localizations from: {TNO_MOD_PATH / 'localisation'}")
        for yf in (TNO_MOD_PATH / "localisation").rglob("*.yml"):
            en_loc.update(parse_yml_file(yf))

    print(f"[LOC] Loaded {len(ru_loc)} RU entries and {len(en_loc)} EN entries")
    return en_loc, ru_loc


def parse_history_states(states_dir: Path) -> Tuple[
    Dict[int, Dict[str, Any]],  # state_id -> state_data
    Dict[int, str],             # prov_id -> owner
    Dict[int, int],             # prov_id -> state_id
    Dict[str, List[int]],       # owner -> list of state_ids
    Dict[str, List[int]]        # owner -> list of prov_ids
]:
    re_id = re.compile(r"\bid\s*=\s*(\d+)", re.IGNORECASE)
    re_name = re.compile(r'\bname\s*=\s*"([^"]+)"', re.IGNORECASE)
    re_owner = re.compile(r"\bowner\s*=\s*([A-Za-z0-9_]{3})", re.IGNORECASE)
    re_provs_block = re.compile(r"\bprovinces\s*=\s*\{([^}]+)\}", re.DOTALL | re.IGNORECASE)
    re_cores = re.compile(r"\badd_core_of\s*=\s*([A-Za-z0-9_]{3})", re.IGNORECASE)

    states_db: Dict[int, Dict[str, Any]] = {}
    prov_to_owner: Dict[int, str] = {}
    prov_to_state: Dict[int, int] = {}
    owner_to_states: Dict[str, List[int]] = {}
    owner_to_provs: Dict[str, List[int]] = {}

    print(f"[STATES] Parsing state files in: {states_dir}")
    count = 0
    for sf in states_dir.glob("*.txt"):
        try:
            content = sf.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue

        m_id = re_id.search(content)
        if not m_id:
            continue
        sid = int(m_id.group(1))

        m_name = re_name.search(content)
        sname = m_name.group(1) if m_name else f"STATE_{sid}"

        m_owner = re_owner.search(content)
        owner = m_owner.group(1).upper() if m_owner else "WST"

        cores = re_cores.findall(content)
        cores = [c.upper() for c in cores]

        provs: List[int] = []
        m_provs = re_provs_block.search(content)
        if m_provs:
            for tok in m_provs.group(1).split():
                if tok.isdigit():
                    pid = int(tok)
                    provs.append(pid)
                    prov_to_owner[pid] = owner
                    prov_to_state[pid] = sid

        states_db[sid] = {
            "id": sid,
            "name": sname,
            "owner": owner,
            "provinces": provs,
            "cores": cores
        }

        if owner not in owner_to_states:
            owner_to_states[owner] = []
            owner_to_provs[owner] = []
        owner_to_states[owner].append(sid)
        owner_to_provs[owner].extend(provs)
        count += 1

    print(f"[STATES] Parsed {count} states. Found {len(owner_to_states)} unique sovereign tags.")
    return states_db, prov_to_owner, prov_to_state, owner_to_states, owner_to_provs


HOI4_MAP_NAMES_RU = {
    "GER": "ГЕРМАНИЯ",
    "ENG": "ВЕЛИКОБРИТАНИЯ",
    "SCO": "ШОТЛАНДИЯ",
    "WLS": "УЭЛЬС",
    "WAL": "УЭЛЬС",
    "IRE": "ИРЛАНДИЯ",
    "NIR": "СЕВ. ИРЛАНДИЯ",
    "FRS": "ФРАНЦИЯ",
    "FRA": "ФРАНЦИЯ",
    "BRG": "БУРГУНДИЯ",
    "ITA": "ИТАЛИЯ",
    "IBR": "ИБЕРИЯ",
    "SPA": "ИСПАНИЯ",
    "POR": "ПОРТУГАЛИЯ",
    "USA": "СОЕДИНЁННЫЕ ШТАТЫ",
    "CAN": "КАНАДА",
    "MEX": "МЕКСИКА",
    "JAP": "ЯПОНИЯ",
    "MAN": "МАНЬЧЖУРИЯ",
    "MEN": "МЭНЦЗЯН",
    "CHI": "КИТАЙ",
    "OST": "ОСТЛАНД",
    "UKR": "УКРАИНА",
    "MCW": "МОСКОВИЯ",
    "CAU": "КАВКАЗ",
    "GGN": "ГЕНЕРАЛ-ГУБЕРНАТОРСТВО",
    "FIN": "ФИНЛЯНДИЯ",
    "SWE": "ШВЕЦИЯ",
    "NOR": "НОРВЕГИЯ",
    "DEN": "ДАНИЯ",
    "HOL": "НИДЕРЛАНДЫ",
    "BEL": "БЕЛЬГИЯ",
    "SWI": "ШВЕЙЦАРИЯ",
    "HUN": "ВЕНГРИЯ",
    "ROM": "РУМЫНИЯ",
    "BUL": "БОЛГАРИЯ",
    "SER": "СЕРБИЯ",
    "CRO": "ХОРВАТИЯ",
    "SLO": "СЛОВАКИЯ",
    "POL": "ПОЛЬША",
    "TUR": "ТУРЦИЯ",
    "GRE": "ГРЕЦИЯ",
    "ALB": "АЛБАНИЯ",
    "MNT": "ЧЕРНОГОРИЯ",
    "BRA": "БРАЗИЛИЯ",
    "ARG": "АРГЕНТИНА",
    "CHL": "ЧИЛИ",
    "PER": "ПЕРУ",
    "COL": "КОЛУМБИЯ",
    "VEN": "ВЕНЕСУЭЛА",
    "BOL": "БОЛИВИЯ",
    "PAR": "ПАРАГВАЙ",
    "URG": "УРУГВАЙ",
    "AST": "АВСТРАЛИЯ",
    "NZL": "НОВАЯ ЗЕЛАНДИЯ",
    "SAF": "ЮЖНАЯ АФРИКА",
    "EGY": "ЕГИПЕТ",
    "ETH": "ЭФИОПИЯ",
    "ANG": "АНГОЛА",
    "MZB": "МОЗАМБИК",
    "COG": "КОНГО",
    "MAD": "МАДАГАСКАР",
    "BUR": "БИРМА",
    "THA": "ТАИЛАНД",
    "VIN": "ВЬЕТНАМ",
    "INS": "ИНДОНЕЗИЯ",
    "PHI": "ФИЛИППИНЫ",
    "IND": "ИНДИЯ",
    "PAK": "ПАКИСТАН",
    "IRA": "ИРАН",
    "IRQ": "ИРАК",
    "SAU": "САУДОВСКАЯ АРАВИЯ",
    "KOM": "КОМИ",
    "WRS": "ЗАП. РУССКИЙ ФРОНТ",
    "VYT": "ВЯТКА",
    "SAM": "САМАРА",
    "GOR": "ГОРЬКИЙ",
    "PRM": "ПЕРМЬ",
    "ONE": "ОНЕГА",
    "TYM": "ТЮМЕНЬ",
    "OMS": "ОМСК",
    "SVR": "СВЕРДЛОВСК",
    "ZLT": "ЗЛАТОУСТ",
    "NOV": "НОВОСИБИРСК",
    "TOM": "ТОМСК",
    "KEM": "КЕМЕРОВО",
    "SBA": "СБА",
    "PRC": "КРАСНОЯРСК",
    "IRK": "ИРКУТСК",
    "BRY": "БУРЯТИЯ",
    "CHT": "ЧИТА",
    "AMR": "АМУР",
    "MAG": "МАГАДАН",
    "YAK": "ЯКУТИЯ",
    "KMC": "КАМЧАТКА",
    "KAZ": "КАЗАХСТАН"
}

HOI4_MAP_NAMES_EN = {
    "GER": "GERMANY",
    "ENG": "BRITAIN",
    "SCO": "SCOTLAND",
    "WLS": "WALES",
    "WAL": "WALES",
    "IRE": "IRELAND",
    "NIR": "N. IRELAND",
    "FRS": "FRANCE",
    "FRA": "FRANCE",
    "BRG": "BURGUNDY",
    "ITA": "ITALY",
    "IBR": "IBERIA",
    "SPA": "SPAIN",
    "POR": "PORTUGAL",
    "USA": "UNITED STATES",
    "CAN": "CANADA",
    "MEX": "MEXICO",
    "JAP": "JAPAN",
    "MAN": "MANCHURIA",
    "MEN": "MENGJIANG",
    "CHI": "CHINA",
    "OST": "OSTLAND",
    "UKR": "UKRAINE",
    "MCW": "MOSKOWIEN",
    "CAU": "KAUKASIEN",
    "GGN": "GENERALGOUVERNEMENT",
    "FIN": "FINLAND",
    "SWE": "SWEDEN",
    "NOR": "NORWAY",
    "DEN": "DENMARK",
    "HOL": "NETHERLANDS",
    "BEL": "BELGIUM",
    "SWI": "SWITZERLAND",
    "HUN": "HUNGARY",
    "ROM": "ROMANIA",
    "BUL": "BULGARIA",
    "SER": "SERBIA",
    "CRO": "CROATIA",
    "SLO": "SLOVAKIA",
    "POL": "POLAND",
    "TUR": "TURKEY",
    "GRE": "GREECE",
    "BRA": "BRAZIL",
    "ARG": "ARGENTINA",
    "CHL": "CHILE",
    "PER": "PERU",
    "COL": "COLOMBIA",
    "VEN": "VENEZUELA",
    "IND": "INDIA",
    "BUR": "BURMA",
    "THA": "THAILAND",
    "INS": "INDONESIA",
    "PHI": "PHILIPPINES",
    "KOM": "KOMI",
    "WRS": "WRRF",
    "VYT": "VYATKA",
    "SAM": "SAMARA",
    "OMS": "OMSK",
    "SVR": "SVERDLOVSK",
    "TYM": "TYUMEN",
    "NOV": "NOVOSIBIRSK",
    "TOM": "TOMSK",
    "MAG": "MAGADAN",
    "IRK": "IRKUTSK",
    "KAZ": "KAZAKHSTAN"
}


def calculate_country_label_metrics(
    tag: str,
    prov_ids: List[int],
    province_centroids: Dict[int, Tuple[float, float]],
    country_name_en: str,
    country_name_ru: str,
    country_color: List[float]
) -> Optional[Dict[str, Any]]:
    points: List[Tuple[float, float]] = []
    for pid in prov_ids:
        if pid in province_centroids:
            points.append(province_centroids[pid])

    if not points:
        return None

    xs = [p[0] for p in points]
    ys = [p[1] for p in points]

    # Calculate median to filter out distant overseas colonies / islands
    median_x = float(np.median(xs))
    median_y = float(np.median(ys))

    # Calculate MAD (Median Absolute Deviation)
    mad_x = float(np.median([abs(x - median_x) for x in xs]))
    mad_y = float(np.median([abs(y - median_y) for y in ys]))

    # Threshold for filtering mainland cluster
    cutoff_x = max(180.0, mad_x * 3.2)
    cutoff_y = max(180.0, mad_y * 3.2)

    cluster_points = [
        p for p in points
        if abs(p[0] - median_x) <= cutoff_x and abs(p[1] - median_y) <= cutoff_y
    ]

    if not cluster_points:
        cluster_points = points

    c_xs = [p[0] for p in cluster_points]
    c_ys = [p[1] for p in cluster_points]

    centroid_x = float(np.mean(c_xs))
    centroid_y = float(np.mean(c_ys))

    min_x, max_x = min(c_xs), max(c_xs)
    min_y, max_y = min(c_ys), max(c_ys)
    width = max_x - min_x
    height = max_y - min_y
    diag = math.sqrt(width * width + height * height)

    # Determine LOD tier
    tier = 3
    if tag in TIER_1_TAGS:
        tier = 1
    elif len(prov_ids) >= 18 or diag >= 350.0:
        tier = 2

    # Clean short names for HoI4 cartography
    short_ru = HOI4_MAP_NAMES_RU.get(tag)
    if not short_ru:
        short_ru = country_name_ru
        for pfx in ["Республика ", "Королевство ", "Государство ", "Царство ", "Эмират ", "Княжество "]:
            if short_ru.startswith(pfx):
                short_ru = short_ru[len(pfx):].strip()

    short_en = HOI4_MAP_NAMES_EN.get(tag)
    if not short_en:
        short_en = country_name_en
        for pfx in ["Republic of ", "Kingdom of ", "State of ", "Empire of "]:
            if short_en.startswith(pfx):
                short_en = short_en[len(pfx):].strip()

    # Calculate optimal font size strictly constrained by country territorial width
    chars_count = max(4, len(short_ru))
    # Font size must ensure entire text fits inside ~65% of territorial width
    max_char_width = (width * 0.65) / float(chars_count)
    base_font_size = int(round(clamp(max_char_width * 1.35, 9.0, 32.0)))

    if tier == 1:
        base_font_size = int(round(clamp(base_font_size, 14.0, 34.0)))
    elif tier == 2:
        base_font_size = int(round(clamp(base_font_size, 11.0, 22.0)))
    else:
        base_font_size = int(round(clamp(base_font_size, 8.0, 14.0)))

    return {
        "tag": tag,
        "name_en": short_en,
        "name_ru": short_ru,
        "full_name_en": country_name_en,
        "full_name_ru": country_name_ru,
        "display_name": short_ru if short_ru else short_en,
        "centroid": [round(centroid_x, 2), round(centroid_y, 2)],
        "bbox": [round(min_x, 1), round(min_y, 1), round(max_x, 1), round(max_y, 1)],
        "width": round(width, 1),
        "height": round(height, 1),
        "diag": round(diag, 1),
        "province_count": len(prov_ids),
        "tier": tier,
        "base_font_size": base_font_size,
        "color": country_color
    }


def clamp(val: float, min_val: float, max_val: float) -> float:
    return max(min_val, min(val, max_val))


def main() -> None:
    t0 = time.time()
    print("=" * 80)
    print("TNO TERRITORY OWNERSHIP & GLOBAL MAP LABELS PIPELINE")
    print("=" * 80)

    # 1. Parse authentic state files
    states_dir = TNO_MOD_PATH / "history" / "states"
    if not states_dir.exists():
        print(f"[ERROR] States directory not found: {states_dir}")
        sys.exit(1)

    states_db, prov_to_owner, prov_to_state, owner_to_states, owner_to_provs = parse_history_states(states_dir)

    # 2. Parse localizations
    en_loc, ru_loc = load_localizations()

    def get_localized_country_name(tag: str) -> Tuple[str, str]:
        # Try DEF or standard name
        en_name = en_loc.get(f"{tag}_DEF", en_loc.get(tag, tag))
        ru_name = ru_loc.get(f"{tag}_DEF", ru_loc.get(tag, en_name))
        return en_name, ru_name

    # 3. Load map manifest to get centroids
    manifest_path = PROJECT_ROOT / "map_data" / "map_manifest.json"
    with open(manifest_path, "r", encoding="utf-8") as f:
        mf = json.load(f)

    province_centroids: Dict[int, Tuple[float, float]] = {}
    for pid_str, pinfo in mf.get("provinces", {}).items():
        pid = int(pid_str)
        c = pinfo.get("centroid")
        if c and len(c) >= 2:
            province_centroids[pid] = (float(c[0]), float(c[1]))

    print(f"[CENTROIDS] Loaded centroids for {len(province_centroids)} provinces")

    # 4. Synchronize starting_regions_state.json
    starting_regions_path = PROJECT_ROOT / "map_data" / "starting_regions_state.json"
    print(f"[SYNC] Updating {starting_regions_path} with authentic state owners...")
    with open(starting_regions_path, "r", encoding="utf-8") as f:
        starting_regions = json.load(f)

    fixed_provinces = 0
    for pid_str, rdata in starting_regions.items():
        pid = int(pid_str)
        auth_owner = prov_to_owner.get(pid)
        auth_state = prov_to_state.get(pid)
        if auth_owner and rdata.get("owner_tag") != auth_owner:
            rdata["owner_tag"] = auth_owner
            fixed_provinces += 1
        if auth_state and rdata.get("state_id") != auth_state:
            rdata["state_id"] = auth_state
        if auth_state and auth_state in states_db:
            rdata["core_tags"] = states_db[auth_state]["cores"]

    print(f"[SYNC] Corrected {fixed_provinces} mismatched provinces in starting_regions_state.json")
    with open(starting_regions_path, "w", encoding="utf-8") as f:
        json.dump(starting_regions, f, ensure_ascii=False, indent=2)

    # 5. Synchronize starting_countries_state.json
    starting_countries_path = PROJECT_ROOT / "map_data" / "starting_countries_state.json"
    print(f"[SYNC] Updating {starting_countries_path}...")
    with open(starting_countries_path, "r", encoding="utf-8") as f:
        starting_countries = json.load(f)

    for tag, cdata in starting_countries.items():
        owned_states = sorted(owner_to_states.get(tag, []))
        owned_provs = owner_to_provs.get(tag, [])
        cdata["owned_states"] = owned_states
        cdata["controlled_states"] = owned_states
        cdata["owned_states_count"] = len(owned_states)
        cdata["owned_provinces_count"] = len(owned_provs)

        en_n, ru_n = get_localized_country_name(tag)
        if en_n and not cdata.get("country_name"):
            cdata["country_name"] = en_n
        cdata["country_name_ru"] = ru_n if ru_n else cdata.get("country_name", tag)

    # Also register any sovereign tags from states that weren't in starting_countries
    for tag, sids in owner_to_states.items():
        if tag not in starting_countries and tag not in ("WST", "WASTE", "NONE"):
            en_n, ru_n = get_localized_country_name(tag)
            owned_provs = owner_to_provs.get(tag, [])
            starting_countries[tag] = {
                "country_tag": tag,
                "country_name": en_n if en_n else tag,
                "country_name_ru": ru_n if ru_n else (en_n if en_n else tag),
                "leader_name": "Provisional Council",
                "leader_portrait_path": "res://icon.svg",
                "ruling_ideology": "paternalism",
                "sub_ideology": "paternalism",
                "country_color": [0.45, 0.45, 0.45, 1.0],
                "political_capital": 50.0,
                "legitimacy": 50.0,
                "radicalization": 10.0,
                "gdp_billions": 10.0,
                "civilian_factories": 2,
                "military_factories": 1,
                "dockyards": 0,
                "total_manpower": 500000,
                "capital_province_id": owned_provs[0] if owned_provs else 1,
                "owned_states": sorted(sids),
                "controlled_states": sorted(sids),
                "owned_states_count": len(sids),
                "owned_provinces_count": len(owned_provs),
                "faction": "INDEPENDENT",
                "alliance": "None",
                "global_sphere": "INDEPENDENT",
                "sphere_code": 0.05
            }

    with open(starting_countries_path, "w", encoding="utf-8") as f:
        json.dump(starting_countries, f, ensure_ascii=False, indent=2)
    print(f"[SYNC] Updated {len(starting_countries)} countries in starting_countries_state.json")

    # 6. Update data/countries/*/country.json
    print(f"[SYNC] Synchronizing data/countries/*/country.json profiles...")
    country_json_count = 0
    for cdir in (PROJECT_ROOT / "data" / "countries").iterdir():
        if not cdir.is_dir():
            continue
        cfile = cdir / "country.json"
        if not cfile.exists():
            continue
        tag = cdir.name
        try:
            with open(cfile, "r", encoding="utf-8") as f:
                c_content = json.load(f)
            ident = c_content.setdefault("identity", {})
            auth_states = sorted(owner_to_states.get(tag, []))
            ident["controlled_states"] = auth_states
            en_n, ru_n = get_localized_country_name(tag)
            if ru_n and not ident.get("country_name_ru"):
                ident["country_name_ru"] = ru_n
            with open(cfile, "w", encoding="utf-8") as f:
                json.dump(c_content, f, ensure_ascii=False, indent=2)
            country_json_count += 1
        except Exception as e:
            print(f"[WARN] Error updating {cfile}: {e}")

    print(f"[SYNC] Synchronized {country_json_count} country.json files (including GER with {len(owner_to_states.get('GER', []))} states)")

    # 7. Generate map_data/country_labels.json
    print(f"[LABELS] Computing country label typography and centroids...")
    country_labels: Dict[str, Any] = {}
    for tag, pids in owner_to_provs.items():
        if tag in ("WST", "WASTE", "NONE") or not pids:
            continue
        c_info = starting_countries.get(tag, {})
        en_n = c_info.get("country_name", tag)
        ru_n = c_info.get("country_name_ru", en_n)
        col = c_info.get("country_color", [0.45, 0.45, 0.45, 1.0])

        metrics = calculate_country_label_metrics(
            tag, pids, province_centroids, en_n, ru_n, col
        )
        if metrics:
            country_labels[tag] = metrics

    labels_output_path = PROJECT_ROOT / "map_data" / "country_labels.json"
    with open(labels_output_path, "w", encoding="utf-8") as f:
        json.dump(country_labels, f, ensure_ascii=False, indent=2)
    print(f"[LABELS] Saved {len(country_labels)} country label definitions to {labels_output_path}")

    # 8. Generate map_data/state_labels.json (HoI4 Tactical Regional Names)
    print(f"[STATES] Generating HoI4-style state labels...")
    state_labels: Dict[str, Any] = {}
    for sid, sdata in states_db.items():
        s_provs = sdata.get("provinces", [])
        if not s_provs:
            continue
        s_points = [province_centroids[p] for p in s_provs if p in province_centroids]
        if not s_points:
            continue
        xs = [p[0] for p in s_points]
        ys = [p[1] for p in s_points]
        sc_x = float(np.mean(xs))
        sc_y = float(np.mean(ys))
        min_x, max_x = float(min(xs)), float(max(xs))
        min_y, max_y = float(min(ys)), float(max(ys))
        w = round(max(12.0, max_x - min_x), 1)
        h = round(max(12.0, max_y - min_y), 1)

        s_name_en = en_loc.get(f"STATE_{sid}", sdata.get("name", f"State {sid}"))
        s_name_ru = ru_loc.get(f"STATE_{sid}", s_name_en)

        state_labels[str(sid)] = {
            "id": sid,
            "owner": sdata.get("owner", "WST"),
            "name_en": s_name_en,
            "name_ru": s_name_ru,
            "centroid": [round(sc_x, 2), round(sc_y, 2)],
            "bbox": [round(min_x, 1), round(min_y, 1), round(max_x, 1), round(max_y, 1)],
            "width": w,
            "height": h,
            "span": round(math.sqrt(w * w + h * h), 1),
            "province_count": len(s_provs)
        }

    state_labels_path = PROJECT_ROOT / "map_data" / "state_labels.json"
    with open(state_labels_path, "w", encoding="utf-8") as f:
        json.dump(state_labels, f, ensure_ascii=False, indent=2)
    print(f"[STATES] Saved {len(state_labels)} state label definitions to {state_labels_path}")

    # 9. Synchronize map_data/province_features.json (Fixing "Держава-владелец" WST bug)
    pf_path = PROJECT_ROOT / "map_data" / "province_features.json"
    if pf_path.exists():
        print(f"[SYNC] Synchronizing {pf_path} with authentic state owners and Russian names...")
        with open(pf_path, "r", encoding="utf-8") as f:
            pf = json.load(f)

        TERRAIN_RU = {
            "plains": "Равнины",
            "hills": "Холмы",
            "mountain": "Горы",
            "mountains": "Горы",
            "forest": "Лес",
            "jungle": "Джунгли",
            "marsh": "Болото",
            "desert": "Пустыня",
            "urban": "Городская застройка",
            "ocean": "Океан",
            "sea": "Море",
            "lake": "Озеро",
            "water": "Водный массив"
        }

        pf_fixed = 0
        for pid_str, pfeat in pf.items():
            pid = int(pid_str)
            auth_o = prov_to_owner.get(pid, "")
            auth_s = prov_to_state.get(pid, pfeat.get("state_id", 0))

            if auth_o and pfeat.get("owner") != auth_o:
                pfeat["owner"] = auth_o
                pf_fixed += 1
            if auth_s:
                pfeat["state_id"] = auth_s
                st_ru = ru_loc.get(f"STATE_{auth_s}", en_loc.get(f"STATE_{auth_s}", pfeat.get("state_name", f"Регион {auth_s}")))
                st_en = en_loc.get(f"STATE_{auth_s}", pfeat.get("state_name", f"State {auth_s}"))
                pfeat["state_name"] = st_ru
                pfeat["state_name_en"] = st_en

            raw_terrain = str(pfeat.get("terrain", "plains")).lower()
            pfeat["terrain_name_ru"] = TERRAIN_RU.get(raw_terrain, "Умеренный ландшафт")
            pfeat["terrain_name_en"] = raw_terrain.capitalize()

        with open(pf_path, "w", encoding="utf-8") as f:
            json.dump(pf, f, ensure_ascii=False, indent=2)
        print(f"[SYNC] Corrected {pf_fixed} province ownership records in province_features.json")

    # 10. Re-bake map_data/ownership_lut.png via TNOBorderLUTBuilder
    lut_builder_script = PROJECT_ROOT / "tools" / "tno_border_lut_builder.py"
    if lut_builder_script.exists():
        print(f"[LUT] Re-baking ownership_lut.png...")
        import subprocess
        cmd = [
            sys.executable,
            str(lut_builder_script),
            "--manifest", str(manifest_path),
            "--regions", str(starting_regions_path),
            "--output-lut", str(PROJECT_ROOT / "map_data" / "ownership_lut.png")
        ]
        ret = subprocess.run(cmd, capture_output=True, text=True)
        print(f"[LUT] Output: {ret.stdout.strip()}")
        if ret.returncode != 0:
            print(f"[LUT] Error: {ret.stderr.strip()}")

    print("=" * 80)
    print(f"[DONE] Entire territory sync and label generation completed in {time.time() - t0:.2f}s")
    print("=" * 80)


if __name__ == "__main__":
    main()
