"""
Map and State Grid Extractor for TNO to Godot 4.
Parses:
  - map/definition.csv (RGB -> province_id, type, coastal, terrain, continent)
  - map/provinces.bmp (Converted to lossless provinces_mask.png with encoded IDs)
  - history/states/*.txt (State metadata, ownership, cores, claims, buildings, VPs)

Outputs:
  - map_manifest.json
  - provinces_mask.png
"""

import csv
import glob
import json
import os
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from PIL import Image
import numpy as np

from .clausewitz import parse_clausewitz_file


def parse_definition_csv(csv_path: str) -> Tuple[Dict[Tuple[int, int, int], int], Dict[int, Dict[str, Any]], int]:
    """
    Parses map/definition.csv.
    Format: province_id;R;G;B;type;coastal;terrain;continent
    """
    rgb_to_id: Dict[Tuple[int, int, int], int] = {}
    provinces_meta: Dict[int, Dict[str, Any]] = {}
    max_id = 0

    if not os.path.exists(csv_path):
        raise FileNotFoundError(f"Definition file not found: {csv_path}")

    with open(csv_path, mode="r", encoding="utf-8-sig", errors="replace") as f:
        reader = csv.reader(f, delimiter=";")
        for row in reader:
            if not row or len(row) < 4:
                continue
            row = [c.strip() for c in row]
            if row[0].startswith("#") or not row[0].isdigit():
                continue

            try:
                prov_id = int(row[0])
                r = int(row[1])
                g = int(row[2])
                b = int(row[3])
            except ValueError:
                continue

            prov_type = row[4] if len(row) > 4 else "land"
            is_coastal = (row[5].lower() == "true") if len(row) > 5 else False
            terrain = row[6] if len(row) > 6 else "unknown"
            continent = int(row[7]) if len(row) > 7 and row[7].isdigit() else 0

            rgb = (r, g, b)
            rgb_to_id[rgb] = prov_id
            provinces_meta[prov_id] = {
                "id": prov_id,
                "rgb": [r, g, b],
                "type": prov_type,
                "is_coastal": is_coastal,
                "terrain": terrain,
                "continent": continent,
                "state_id": None
            }

            if prov_id > max_id:
                max_id = prov_id

    return rgb_to_id, provinces_meta, max_id


def convert_provinces_bmp(
    bmp_path: str,
    rgb_to_id: Dict[Tuple[int, int, int], int],
    output_png_path: str
) -> Tuple[int, int, int]:
    """
    Converts 24-bit provinces.bmp to provinces_mask.png where RGB channels store:
      R = id & 0xFF
      G = (id >> 8) & 0xFF
      B = (id >> 16) & 0xFF
    """
    img = Image.open(bmp_path).convert("RGB")
    width, height = img.size
    img_np = np.array(img, dtype=np.uint8)

    # Pack 24-bit integer
    packed_rgb = (
        (img_np[:, :, 0].astype(np.uint32) << 16) |
        (img_np[:, :, 1].astype(np.uint32) << 8) |
        img_np[:, :, 2].astype(np.uint32)
    )

    lut_keys = []
    lut_vals = []
    for (r, g, b), pid in rgb_to_id.items():
        key = (r << 16) | (g << 8) | b
        lut_keys.append(key)
        lut_vals.append(pid)

    lut_keys = np.array(lut_keys, dtype=np.uint32)
    lut_vals = np.array(lut_vals, dtype=np.uint32)

    sorter = np.argsort(lut_keys)
    sorted_keys = lut_keys[sorter]
    sorted_vals = lut_vals[sorter]

    flat_packed = packed_rgb.ravel()
    indices = np.searchsorted(sorted_keys, flat_packed)
    indices = np.clip(indices, 0, len(sorted_keys) - 1)

    matched = sorted_keys[indices] == flat_packed
    prov_ids = np.zeros(flat_packed.shape, dtype=np.uint32)
    prov_ids[matched] = sorted_vals[indices[matched]]

    unmatched_count = int(np.count_nonzero(~matched))

    out_r = (prov_ids & 0xFF).astype(np.uint8)
    out_g = ((prov_ids >> 8) & 0xFF).astype(np.uint8)
    out_b = ((prov_ids >> 16) & 0xFF).astype(np.uint8)

    out_np = np.stack([out_r, out_g, out_b], axis=-1).reshape((height, width, 3))
    out_img = Image.fromarray(out_np, mode="RGB")
    out_img.save(output_png_path, format="PNG", optimize=False)

    return width, height, unmatched_count


def parse_state_files(states_dir: str) -> Dict[int, Dict[str, Any]]:
    """
    Parses all state files in history/states/*.txt.
    """
    states: Dict[int, Dict[str, Any]] = {}
    pattern = os.path.join(states_dir, "*.txt")
    file_list = glob.glob(pattern)

    for file_path in file_list:
        try:
            parsed = parse_clausewitz_file(file_path)
            state_data = parsed.get("state")
            if not isinstance(state_data, dict):
                continue

            state_id = state_data.get("id")
            if state_id is None:
                continue

            name = state_data.get("name", f"STATE_{state_id}")
            manpower = state_data.get("manpower", 0)
            category = state_data.get("state_category", "rural")
            resources = state_data.get("resources", {})
            if isinstance(resources, list):
                # Flatten list of resource blocks if any
                flat_res = {}
                for r in resources:
                    if isinstance(r, dict):
                        flat_res.update(r)
                resources = flat_res

            history_block = state_data.get("history", {})
            owner = None
            cores = []
            claims = []
            victory_points = []
            buildings = {}

            if isinstance(history_block, dict):
                owner = history_block.get("owner")
                
                # Cores
                raw_cores = history_block.get("add_core_of", [])
                if isinstance(raw_cores, list):
                    cores = [c for c in raw_cores if isinstance(c, str)]
                elif isinstance(raw_cores, str):
                    cores = [raw_cores]

                # Claims
                raw_claims = history_block.get("add_claim_by", [])
                if isinstance(raw_claims, list):
                    claims = [c for c in raw_claims if isinstance(c, str)]
                elif isinstance(raw_claims, str):
                    claims = [raw_claims]

                # Victory Points
                raw_vps = history_block.get("victory_points", [])
                if isinstance(raw_vps, list):
                    # Could be list of lists: [[11804, 3], [11891, 3]] or [11804, 3]
                    if len(raw_vps) > 0 and isinstance(raw_vps[0], list):
                        for vp in raw_vps:
                            if len(vp) >= 2:
                                victory_points.append({"province_id": vp[0], "points": vp[1]})
                    elif len(raw_vps) >= 2 and isinstance(raw_vps[0], int):
                        for i in range(0, len(raw_vps) - 1, 2):
                            victory_points.append({"province_id": raw_vps[i], "points": raw_vps[i+1]})

                # Buildings
                raw_buildings = history_block.get("buildings", {})
                if isinstance(raw_buildings, dict):
                    for k, v in raw_buildings.items():
                        if k != "_items":
                            buildings[k] = v

            # Provinces
            provs_block = state_data.get("provinces", [])
            provinces = []
            if isinstance(provs_block, list):
                provinces = [p for p in provs_block if isinstance(p, int)]
            elif isinstance(provs_block, dict) and "_items" in provs_block:
                provinces = [p for p in provs_block["_items"] if isinstance(p, int)]

            states[state_id] = {
                "id": state_id,
                "name": name,
                "manpower": manpower,
                "category": category,
                "resources": resources,
                "owner": owner,
                "cores": cores,
                "claims": claims,
                "victory_points": victory_points,
                "buildings": buildings,
                "provinces": provinces
            }
        except Exception as err:
            print(f"[WARN] Error parsing state file {file_path}: {err}", file=sys.stderr)

    return states


def extract_map_data(
    tno_root: str,
    output_dir: str,
    generate_mask: bool = True
) -> Dict[str, Any]:
    """
    Orchestrates full map and state extraction.
    """
    os.makedirs(output_dir, exist_ok=True)
    t0 = time.time()

    def_csv = os.path.join(tno_root, "map", "definition.csv")
    prov_bmp = os.path.join(tno_root, "map", "provinces.bmp")
    states_dir = os.path.join(tno_root, "history", "states")

    print(f"[MAP] Parsing province definitions from: {def_csv}")
    rgb_to_id, provinces_meta, max_id = parse_definition_csv(def_csv)

    mask_width, mask_height = 0, 0
    if generate_mask:
        mask_png = os.path.join(output_dir, "provinces_mask.png")
        print(f"[MAP] Converting raster map {prov_bmp} -> {mask_png}")
        mask_width, mask_height, unmatched = convert_provinces_bmp(prov_bmp, rgb_to_id, mask_png)
        if unmatched > 0:
            print(f"[MAP] [WARN] {unmatched} pixels with unknown color palette mapped to province 0")

    print(f"[MAP] Parsing state files from: {states_dir}")
    states = parse_state_files(states_dir)

    # Link provinces with states
    for state_id, sdata in states.items():
        for pid in sdata["provinces"]:
            if pid in provinces_meta:
                provinces_meta[pid]["state_id"] = state_id

    manifest = {
        "metadata": {
            "version": "1.0.0",
            "extracted_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "map_size": {"width": mask_width, "height": mask_height},
            "total_provinces": len(provinces_meta),
            "max_province_id": max_id,
            "total_states": len(states)
        },
        "states": {str(sid): s for sid, s in sorted(states.items())},
        "provinces": {str(pid): p for pid, p in sorted(provinces_meta.items())}
    }

    manifest_path = os.path.join(output_dir, "map_manifest.json")
    print(f"[MAP] Writing map manifest to: {manifest_path}")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)

    elapsed = time.time() - t0
    print(f"[MAP] Done in {elapsed:.2f}s ({len(states)} states, {len(provinces_meta)} provinces)")
    return manifest
