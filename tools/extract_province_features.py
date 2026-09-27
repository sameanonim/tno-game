#!/usr/bin/env python3
"""
================================================================================
TNO PROVINCE FEATURES & MAP ASSETS EXTRACTOR
================================================================================
Extracts granular provincial features from the TNO mod and project manifests:
1. Buildings (map/buildings.txt):
   - Naval bases & ports (levels/presence)
   - Air bases (airfields)
   - Bunkers (land & coastal forts)
   - Supply nodes & hubs
   - Industrial facilities & nuclear reactors
2. Railways & Logistics (map/railways.txt, map/supply_nodes.txt):
   - Track networks with levels 1..5
   - Supply node locations
3. Victory Points & Localized City Names:
   - Extracted from map_manifest.json and extracted_tno_data/localization.sqlite
4. Terrain & Geographic Modifiers:
   - Plains, Mountains, Hills, Forests, Marshes, Desert, Urban, etc.
   - River crossings from map/rivers.bmp
5. Asset Conversion:
   - map/rivers.bmp -> map_data/rivers_mask.png
   - map/world_normal.bmp -> map_data/world_normal.png
================================================================================
"""

import argparse
import csv
import json
import os
from pathlib import Path
import re
import sqlite3
import sys
import time
from typing import Any, Dict, List, Optional, Set, Tuple

try:
    from PIL import Image
    import numpy as np
except ImportError:
    print("[ERROR] Pillow and NumPy are required. Install via: pip install pillow numpy", file=sys.stderr)
    sys.exit(1)


DEFAULT_MOD_PATH = Path(r"F:\SteamLibrary\steamapps\workshop\content\394360\2438003901")
PROJECT_ROOT = Path(__file__).resolve().parent.parent
MAP_DATA_DIR = PROJECT_ROOT / "map_data"
EXTRACTED_DATA_DIR = PROJECT_ROOT / "extracted_tno_data"


def convert_rivers_texture(mod_path: Path, output_path: Path) -> bool:
    """
    Converts map/rivers.bmp (5120x2560 indexed or RGB) into a clean, optimized
    rivers_mask.png where:
    - River paths (pixels with green, blue, yellow, red flow indices) are encoded
    - Water/ocean is 0, background land is 0
    - Non-zero values represent river flow intensity
    """
    rivers_bmp = mod_path / "map" / "rivers.bmp"
    if not rivers_bmp.exists():
        print(f"[WARN] rivers.bmp not found at {rivers_bmp}")
        return False

    print(f"[TEXTURES] Converting {rivers_bmp} -> {output_path}...")
    start_t = time.time()
    
    img = Image.open(rivers_bmp).convert("RGB")
    width, height = img.size
    img_np = np.array(img, dtype=np.uint8)

    # In HoI4 rivers.bmp:
    # 255, 255, 255 = land (no river)
    # 0, 225, 255 or various shades of blue = ocean / water bodies / estuaries
    # 0, 255, 0 = river source or river channel
    # 255, 0, 0 = river start
    # 255, 255, 0 = river split
    # Any pixel that is NOT pure white (255, 255, 255) and NOT pure sea (0, 225, 255) is a river!
    
    r = img_np[:, :, 0]
    g = img_np[:, :, 1]
    b = img_np[:, :, 2]

    # Mask of land (white: 255, 255, 255)
    is_white = (r >= 250) & (g >= 250) & (b >= 250)
    
    # Mask of pure sea in rivers.bmp: (0, 225, 255) or similar cyan/blue
    is_pure_sea = (r == 0) & (g >= 220) & (b >= 250)

    # River pixel is neither land background nor pure sea
    is_river = (~is_white) & (~is_pure_sea)

    # Output grayscale / alpha mask
    river_mask = np.zeros((height, width), dtype=np.uint8)
    river_mask[is_river] = 255

    mask_img = Image.fromarray(river_mask, mode="L")
    mask_img.save(output_path, "PNG", optimize=True)

    print(f"[TEXTURES] River mask saved ({width}x{height}) in {time.time() - start_t:.2f}s, size: {os.path.getsize(output_path):,} bytes")
    return True


def convert_normal_map_texture(mod_path: Path, output_path: Path) -> bool:
    """
    Converts map/world_normal.bmp (2560x1280) into an optimized world_normal.png
    used by the fragment shader for dynamic relief / hillshading.
    """
    normal_bmp = mod_path / "map" / "world_normal.bmp"
    if not normal_bmp.exists():
        print(f"[WARN] world_normal.bmp not found at {normal_bmp}")
        return False

    print(f"[TEXTURES] Converting {normal_bmp} -> {output_path}...")
    start_t = time.time()
    
    img = Image.open(normal_bmp).convert("RGB")
    img.save(output_path, "PNG", optimize=True)
    print(f"[TEXTURES] Normal map saved ({img.size[0]}x{img.size[1]}) in {time.time() - start_t:.2f}s, size: {os.path.getsize(output_path):,} bytes")
    return True


def load_localized_vp_names(sqlite_path: Path) -> Dict[int, Dict[str, str]]:
    """
    Loads city/victory point localized names from localization.sqlite.
    Keys are VICTORY_POINTS_<pid>.
    """
    vp_names: Dict[int, Dict[str, str]] = {}
    if not sqlite_path.exists():
        print(f"[WARN] SQLite db not found: {sqlite_path}")
        return vp_names

    print(f"[DATA] Loading VP city names from {sqlite_path}...")
    conn = sqlite3.connect(sqlite_path)
    c = conn.cursor()
    c.execute("SELECT lang, key, clean_value FROM localization WHERE key LIKE 'VICTORY_POINTS_%'")
    for lang, key, val in c.fetchall():
        match = re.match(r"VICTORY_POINTS_(\d+)", key)
        if match:
            pid = int(match.group(1))
            if pid not in vp_names:
                vp_names[pid] = {}
            if lang == "russian":
                vp_names[pid]["ru"] = val
            elif lang == "english":
                vp_names[pid]["en"] = val
            else:
                vp_names[pid][lang] = val

    conn.close()
    print(f"[DATA] Loaded localized names for {len(vp_names)} victory points.")
    return vp_names


def parse_buildings(mod_path: Path) -> Dict[int, Dict[str, Any]]:
    """
    Parses map/buildings.txt:
    Each line format:
    state_id;building_type;x;y;z;rotation;province_id
    Aggregates per-province building counts/levels.
    """
    buildings_path = mod_path / "map" / "buildings.txt"
    prov_buildings: Dict[int, Dict[str, Any]] = {}
    if not buildings_path.exists():
        print(f"[WARN] buildings.txt not found at {buildings_path}")
        return prov_buildings

    print(f"[DATA] Parsing {buildings_path}...")
    with open(buildings_path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            parts = line.strip().split(";")
            if len(parts) < 7:
                continue
            try:
                sid = int(parts[0])
                btype = parts[1].strip()
                pid = int(parts[6])
            except ValueError:
                continue

            if pid <= 0:
                continue

            if pid not in prov_buildings:
                prov_buildings[pid] = {
                    "naval_base": 0,
                    "air_base": 0,
                    "bunker": 0,
                    "coastal_bunker": 0,
                    "supply_node": 0,
                    "radar_station": 0,
                    "nuclear_reactor": 0,
                    "arms_factory": 0,
                    "industrial_complex": 0,
                    "dockyard": 0
                }

            entry = prov_buildings[pid]
            if btype in ("naval_base", "naval_supply_hub", "floating_harbor"):
                entry["naval_base"] += 1
            elif btype == "air_base":
                entry["air_base"] += 1
            elif btype in ("bunker", "stronghold_network"):
                entry["bunker"] += 1
            elif btype == "coastal_bunker":
                entry["coastal_bunker"] += 1
            elif btype == "supply_node":
                entry["supply_node"] += 1
            elif btype == "radar_station":
                entry["radar_station"] += 1
            elif btype in ("nuclear_reactor", "nuclear_reactor_spawn"):
                entry["nuclear_reactor"] += 1
            elif btype == "arms_factory":
                entry["arms_factory"] += 1
            elif btype == "industrial_complex":
                entry["industrial_complex"] += 1
            elif btype == "dockyard":
                entry["dockyard"] += 1

    print(f"[DATA] Aggregated building entries for {len(prov_buildings)} provinces.")
    return prov_buildings


def parse_railways(mod_path: Path) -> List[Dict[str, Any]]:
    """
    Parses map/railways.txt:
    Each line format:
    <level> <count> <prov1> <prov2> ...
    """
    railways_path = mod_path / "map" / "railways.txt"
    railways: List[Dict[str, Any]] = []
    if not railways_path.exists():
        return railways

    print(f"[DATA] Parsing {railways_path}...")
    with open(railways_path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            tokens = line.strip().split()
            if len(tokens) < 3:
                continue
            try:
                level = int(tokens[0])
                count = int(tokens[1])
                provinces = [int(p) for p in tokens[2:2 + count]]
                if len(provinces) >= 2:
                    railways.append({
                        "level": level,
                        "provinces": provinces
                    })
            except ValueError:
                continue

    print(f"[DATA] Parsed {len(railways)} railway lines.")
    return railways


def parse_supply_nodes(mod_path: Path) -> Set[int]:
    """
    Parses map/supply_nodes.txt:
    Each line format:
    <level> <province_id>
    """
    nodes_path = mod_path / "map" / "supply_nodes.txt"
    nodes: Set[int] = set()
    if not nodes_path.exists():
        return nodes

    with open(nodes_path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            tokens = line.strip().split()
            if len(tokens) >= 2 and tokens[1].isdigit():
                nodes.add(int(tokens[1]))

    print(f"[DATA] Parsed {len(nodes)} supply nodes.")
    return nodes


def get_terrain_tactical_modifiers(terrain: str) -> Dict[str, Any]:
    """
    Returns combat and movement modifiers based on terrain type.
    """
    t = terrain.lower().strip()
    table = {
        "plains": {
            "name_ru": "Равнины",
            "name_en": "Plains",
            "defense": 0,
            "attack_penalty": 0,
            "movement_cost": 1.0,
            "raid_vulnerability": 1.2
        },
        "forest": {
            "name_ru": "Лесной массив",
            "name_en": "Forest",
            "defense": 20,
            "attack_penalty": -15,
            "movement_cost": 1.4,
            "raid_vulnerability": 0.8
        },
        "hills": {
            "name_ru": "Холмистая гряда",
            "name_en": "Hills",
            "defense": 25,
            "attack_penalty": -20,
            "movement_cost": 1.3,
            "raid_vulnerability": 0.9
        },
        "mountain": {
            "name_ru": "Горный хребет",
            "name_en": "Mountains",
            "defense": 50,
            "attack_penalty": -40,
            "movement_cost": 2.0,
            "raid_vulnerability": 0.5
        },
        "marsh": {
            "name_ru": "Болотистая топь",
            "name_en": "Marsh / Swamps",
            "defense": 15,
            "attack_penalty": -30,
            "movement_cost": 1.8,
            "raid_vulnerability": 0.6
        },
        "desert": {
            "name_ru": "Пустыня / Пустоши",
            "name_en": "Desert",
            "defense": 0,
            "attack_penalty": -5,
            "movement_cost": 1.2,
            "raid_vulnerability": 1.1
        },
        "jungle": {
            "name_ru": "Джунгли",
            "name_en": "Jungle",
            "defense": 30,
            "attack_penalty": -25,
            "movement_cost": 1.7,
            "raid_vulnerability": 0.7
        },
        "urban": {
            "name_ru": "Городская агломерация",
            "name_en": "Urban Area",
            "defense": 35,
            "attack_penalty": -25,
            "movement_cost": 1.1,
            "raid_vulnerability": 0.7
        },
        "lakes": {
            "name_ru": "Внутренний водоем",
            "name_en": "Inland Water / Lake",
            "defense": 0,
            "attack_penalty": -99,
            "movement_cost": 9.9,
            "raid_vulnerability": 0.0
        }
    }
    return table.get(t, {
        "name_ru": "Умеренный ландшафт",
        "name_en": "Terrain",
        "defense": 0,
        "attack_penalty": 0,
        "movement_cost": 1.0,
        "raid_vulnerability": 1.0
    })


def build_province_features_database(
    mod_path: Path,
    map_manifest_path: Path,
    sqlite_path: Path,
    output_features_json: Path,
    output_railways_json: Path
) -> None:
    """
    Builds the unified province features database and railway graph.
    """
    print(f"[PIPELINE] Loading map manifest from {map_manifest_path}...")
    with open(map_manifest_path, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    vp_loc = load_localized_vp_names(sqlite_path)
    buildings = parse_buildings(mod_path)
    railways = parse_railways(mod_path)
    supply_nodes = parse_supply_nodes(mod_path)

    states = manifest.get("states", {})
    provinces = manifest.get("provinces", {})

    prov_to_state: Dict[int, int] = {}
    state_vps: Dict[int, int] = {}
    for sid_str, s_info in states.items():
        sid = int(sid_str)
        for p in s_info.get("provinces", []):
            prov_to_state[int(p)] = sid
        for pid_s, vp_val in s_info.get("victory_points", {}).items():
            state_vps[int(pid_s)] = int(vp_val)

    features_db: Dict[str, Any] = {}
    major_cities_count = 0

    print(f"[PIPELINE] Compiling features for {len(provinces)} provinces...")
    for pid_str, p_meta in provinces.items():
        pid = int(pid_str)
        if pid <= 0:
            continue

        sid = p_meta.get("state_id") or prov_to_state.get(pid, 0)
        s_info = states.get(str(sid), {})

        terrain_type = p_meta.get("terrain", "plains")
        terrain_mod = get_terrain_tactical_modifiers(terrain_type)

        b_info = buildings.get(pid, {
            "naval_base": 0,
            "air_base": 0,
            "bunker": 0,
            "coastal_bunker": 0,
            "supply_node": 1 if pid in supply_nodes else 0,
            "radar_station": 0,
            "nuclear_reactor": 0,
            "arms_factory": 0,
            "industrial_complex": 0,
            "dockyard": 0
        })
        if pid in supply_nodes and b_info.get("supply_node", 0) == 0:
            b_info["supply_node"] = 1

        vp_val = state_vps.get(pid, 0)
        city_names = vp_loc.get(pid, {})
        name_ru = city_names.get("ru", "")
        name_en = city_names.get("en", "")
        if not name_ru and not name_en and vp_val > 0:
            name_en = f"City {pid}"

        is_capital = False
        owner_tag = s_info.get("owner", "")
        if vp_val >= 25:
            major_cities_count += 1
            if owner_tag in ("KOM", "GER", "USA", "JAP", "ITA", "ENG", "RUS", "TYU", "OMS", "SVE") and vp_val >= 30:
                is_capital = True

        entry: Dict[str, Any] = {
            "id": pid,
            "state_id": sid,
            "state_name": s_info.get("name", f"State {sid}"),
            "owner": owner_tag,
            "is_coastal": p_meta.get("is_coastal", False),
            "terrain": terrain_type,
            "terrain_name_ru": terrain_mod["name_ru"],
            "terrain_name_en": terrain_mod["name_en"],
            "defense_bonus": terrain_mod["defense"],
            "attack_penalty": terrain_mod["attack_penalty"],
            "movement_cost": terrain_mod["movement_cost"],
            "raid_vulnerability": terrain_mod["raid_vulnerability"],
            "centroid": p_meta.get("centroid", [0.0, 0.0]),
            "pixel_area": p_meta.get("pixel_area", 0),
            "vp": vp_val,
            "city_name_ru": name_ru,
            "city_name_en": name_en,
            "is_capital": is_capital,
            "buildings": b_info,
            "state_resources": s_info.get("resources", {}),
            "state_category": s_info.get("category", "rural"),
            "state_manpower": s_info.get("manpower", 0),
            "state_ic": s_info.get("industrial_capacity", 0.0),
            "state_infrastructure": s_info.get("infrastructure", 0)
        }

        if p_meta.get("type") in ("sea", "lake") and vp_val == 0 and sum(b_info.values()) == 0:
            features_db[str(pid)] = {
                "id": pid,
                "type": p_meta.get("type"),
                "is_coastal": False,
                "terrain": p_meta.get("type"),
                "centroid": p_meta.get("centroid", [0.0, 0.0])
            }
        else:
            features_db[str(pid)] = entry

    print(f"[PIPELINE] Saving features DB to {output_features_json}...")
    with open(output_features_json, "w", encoding="utf-8") as f:
        json.dump(features_db, f, ensure_ascii=False, indent=1)

    print(f"[PIPELINE] Saving railways to {output_railways_json}...")
    with open(output_railways_json, "w", encoding="utf-8") as f:
        json.dump(railways, f, ensure_ascii=False, indent=1)

    print(f"[PIPELINE] Successfully compiled {len(features_db)} province features, {major_cities_count} major cities, {len(railways)} railway routes.")


def main():
    parser = argparse.ArgumentParser(description="Extract TNO Province Features and Convert Map Textures")
    parser.add_argument("--mod-path", type=Path, default=DEFAULT_MOD_PATH, help="Path to TNO mod root")
    parser.add_argument("--validate", action="store_true", help="Validate output files only")
    args = parser.parse_args()

    mod_path = args.mod_path
    if not mod_path.exists():
        print(f"[ERROR] Mod path does not exist: {mod_path}")
        sys.exit(1)

    map_manifest_path = MAP_DATA_DIR / "map_manifest.json"
    sqlite_path = EXTRACTED_DATA_DIR / "localization.sqlite"
    features_json = MAP_DATA_DIR / "province_features.json"
    railways_json = MAP_DATA_DIR / "railways.json"
    rivers_png = MAP_DATA_DIR / "rivers_mask.png"
    normal_png = MAP_DATA_DIR / "world_normal.png"

    if args.validate:
        if features_json.exists() and rivers_png.exists() and normal_png.exists() and railways_json.exists():
            print("[VALIDATION] All map assets exist and are valid.")
            sys.exit(0)
        else:
            print("[VALIDATION] Missing some assets.")
            sys.exit(1)

    print("================================================================================")
    print("STARTING TNO PROVINCE FEATURES & MAP TEXTURES PIPELINE")
    print("================================================================================")

    convert_rivers_texture(mod_path, rivers_png)
    convert_normal_map_texture(mod_path, normal_png)

    build_province_features_database(
        mod_path=mod_path,
        map_manifest_path=map_manifest_path,
        sqlite_path=sqlite_path,
        output_features_json=features_json,
        output_railways_json=railways_json
    )

    print("================================================================================")
    print("PIPELINE COMPLETED SUCCESSFULLY!")
    print("================================================================================")


if __name__ == "__main__":
    main()
