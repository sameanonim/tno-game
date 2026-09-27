#!/usr/bin/env python3
"""
tools/map_preprocessor.py: TNO & Clausewitz Map Preprocessing Pipeline
======================================================================
Prepares raster and vector assets for the Godot 4 CRT Terminal Grand Strategy Map:
1. Converts provinces.bmp + definition.csv into uncompressed/lossless provinces_mask.png
   with 24-bit RGB ID packing: R = id & 0xFF, G = (id >> 8) & 0xFF, B = (id >> 16) & 0xFF.
2. Vectorized calculation of screen centroids [x, y], pixel areas, and Bounding Boxes.
3. Converts heightmap.bmp into a normalized 8-bit single-channel height_map.png.
4. Extracts river network from rivers.bmp into rivers_mask.png with width classification
   (minor, standard, major) and calculates transborder river barriers.
5. Exports production manifest data/map_manifest.json with all province topology and geometry.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

import numpy as np
from PIL import Image

try:
    from scipy.ndimage import find_objects
    SCIPY_AVAILABLE = True
except ImportError:
    SCIPY_AVAILABLE = False


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] [MAP_PREPROCESSOR] {msg}", flush=True)


def parse_definition_csv(csv_path: str) -> Tuple[
    Dict[Tuple[int, int, int], int],
    Dict[int, Dict[str, Any]],
    int
]:
    """
    Parses HoI4/TNO definition.csv:
    province_id;R;G;B;terrain_type;is_coastal;continent;weather...
    """
    if not os.path.exists(csv_path):
        raise FileNotFoundError(f"Definitions file not found: {csv_path}")

    log(f"Loading definitions from: {csv_path}")
    rgb_to_id: Dict[Tuple[int, int, int], int] = {}
    provinces_meta: Dict[int, Dict[str, Any]] = {}
    max_province_id = 0

    with open(csv_path, mode="r", encoding="utf-8-sig", errors="replace") as f:
        reader = csv.reader(f, delimiter=";")
        for row in reader:
            if not row or len(row) < 4:
                continue
            row = [cell.strip() for cell in row]
            if row[0].startswith("#") or not row[0].isdigit():
                continue

            try:
                prov_id = int(row[0])
                r = int(row[1])
                g = int(row[2])
                b = int(row[3])
            except ValueError:
                continue

            terrain_type = row[4].lower() if len(row) > 4 and row[4] else "plains"
            is_coastal = False
            if len(row) > 5 and row[5]:
                is_coastal = row[5].lower() in ("true", "1", "yes")

            rgb = (r, g, b)
            rgb_to_id[rgb] = prov_id

            provinces_meta[prov_id] = {
                "id": prov_id,
                "rgb": [r, g, b],
                "terrain_type": terrain_type,
                "is_coastal": is_coastal,
            }

            if prov_id > max_province_id:
                max_province_id = prov_id

    log(f"Parsed {len(provinces_meta)} province definitions (Max ID: {max_province_id})")
    return rgb_to_id, provinces_meta, max_province_id


def load_state_assignments(
    states_dir: Optional[str],
    starting_regions_path: Optional[str]
) -> Dict[int, int]:
    """
    Loads province_id -> state_id mapping from history/states or starting_regions_state.json.
    """
    province_to_state: Dict[int, int] = {}

    if starting_regions_path and os.path.exists(starting_regions_path):
        log(f"Reading state mappings from JSON: {starting_regions_path}")
        try:
            with open(starting_regions_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, dict):
                    for k, val in data.items():
                        if isinstance(val, dict):
                            pid = int(val.get("province_id", k))
                            sid = int(val.get("state_id", val.get("region_id", 0)))
                            if sid > 0:
                                province_to_state[pid] = sid
        except Exception as e:
            log(f"Warning: Failed to parse {starting_regions_path}: {e}")

    if states_dir and os.path.exists(states_dir) and os.path.isdir(states_dir):
        log(f"Scanning Clausewitz state files in: {states_dir}")
        for fname in os.listdir(states_dir):
            if not fname.endswith(".txt"):
                continue
            fpath = os.path.join(states_dir, fname)
            try:
                with open(fpath, "r", encoding="utf-8", errors="replace") as f:
                    content = f.read()

                # Extract id = <state_id>
                import re
                id_match = re.search(r"\bid\s*=\s*(\d+)", content)
                if not id_match:
                    continue
                state_id = int(id_match.group(1))

                # Extract provinces = { 1 2 3 ... }
                prov_block = re.search(r"provinces\s*=\s*\{([^}]+)\}", content)
                if prov_block:
                    tokens = prov_block.group(1).split()
                    for tok in tokens:
                        if tok.isdigit():
                            province_to_state[int(tok)] = state_id
            except Exception:
                continue

    log(f"Total province-to-state mappings loaded: {len(province_to_state)}")
    return province_to_state


def convert_provinces_raster(
    bmp_path: str,
    rgb_to_id: Dict[Tuple[int, int, int], int],
    max_id: int
) -> Tuple[np.ndarray, int, int]:
    """
    Converts provinces.bmp RGB pixels into a 2D uint32 array of province IDs using
    vectorized NumPy searchsorted for maximum throughput.
    """
    if not os.path.exists(bmp_path):
        raise FileNotFoundError(f"Provinces bitmap not found: {bmp_path}")

    log(f"Opening provinces bitmap: {bmp_path}")
    t0 = time.time()
    img = Image.open(bmp_path).convert("RGB")
    width, height = img.size
    img_np = np.array(img, dtype=np.uint8)
    log(f"Loaded bitmap dimensions: {width}x{height} in {time.time() - t0:.2f}s")

    # Encode (R, G, B) into a 24-bit integer
    packed_rgb = (
        (img_np[:, :, 0].astype(np.uint32) << 16) |
        (img_np[:, :, 1].astype(np.uint32) << 8) |
        img_np[:, :, 2].astype(np.uint32)
    )

    lut_keys: List[int] = []
    lut_vals: List[int] = []
    for (r, g, b), pid in rgb_to_id.items():
        key = (r << 16) | (g << 8) | b
        lut_keys.append(key)
        lut_vals.append(pid)

    lut_k_arr = np.array(lut_keys, dtype=np.uint32)
    lut_v_arr = np.array(lut_vals, dtype=np.uint32)

    sorter = np.argsort(lut_k_arr)
    sorted_keys = lut_k_arr[sorter]
    sorted_vals = lut_v_arr[sorter]

    flat_packed = packed_rgb.ravel()
    indices = np.searchsorted(sorted_keys, flat_packed)
    indices = np.clip(indices, 0, len(sorted_keys) - 1)

    matched = (sorted_keys[indices] == flat_packed)
    prov_ids_flat = np.zeros(flat_packed.shape, dtype=np.uint32)
    prov_ids_flat[matched] = sorted_vals[indices[matched]]

    unmatched_count = int(np.count_nonzero(~matched))
    if unmatched_count > 0:
        log(f"Warning: {unmatched_count} pixels did not match definition.csv (defaulted to ID 0)")

    prov_ids_2d = prov_ids_flat.reshape((height, width))
    log(f"Vectorized ID lookup completed in {time.time() - t0:.2f}s")
    return prov_ids_2d, width, height


def compute_geometry(
    prov_ids: np.ndarray,
    width: int,
    height: int,
    max_id: int
) -> Tuple[
    np.ndarray,  # centroids: shape (max_id + 1, 2)
    np.ndarray,  # counts: shape (max_id + 1,)
    np.ndarray   # bboxes: shape (max_id + 1, 4) -> [min_x, min_y, max_x, max_y]
]:
    """
    Computes screen centroids [x, y], pixel counts (area), and bounding boxes.
    Utilizes scipy.ndimage.find_objects when available, or vectorized scan.
    """
    log("Computing screen centroids, areas, and bounding boxes...")
    t0 = time.time()
    flat_ids = prov_ids.ravel()
    flat_x = np.tile(np.arange(width, dtype=np.float32), height)
    flat_y = np.repeat(np.arange(height, dtype=np.float32), width)

    counts = np.bincount(flat_ids, minlength=max_id + 1)
    sum_x = np.bincount(flat_ids, weights=flat_x, minlength=max_id + 1)
    sum_y = np.bincount(flat_ids, weights=flat_y, minlength=max_id + 1)

    centroids = np.zeros((max_id + 1, 2), dtype=np.float32)
    valid = counts > 0
    centroids[valid, 0] = np.round(sum_x[valid] / counts[valid], 2)
    centroids[valid, 1] = np.round(sum_y[valid] / counts[valid], 2)

    bboxes = np.zeros((max_id + 1, 4), dtype=np.int32)

    if SCIPY_AVAILABLE:
        slices = find_objects(prov_ids.astype(np.int32), max_label=max_id)
        for idx, slc in enumerate(slices):
            pid = idx + 1
            if slc is not None:
                slice_y, slice_x = slc
                bboxes[pid, 0] = slice_x.start
                bboxes[pid, 1] = slice_y.start
                bboxes[pid, 2] = slice_x.stop - 1
                bboxes[pid, 3] = slice_y.stop - 1
    else:
        # Fallback pure NumPy row-by-row bounding box detection
        min_x = np.full(max_id + 1, width, dtype=np.int32)
        min_y = np.full(max_id + 1, height, dtype=np.int32)
        max_x = np.zeros(max_id + 1, dtype=np.int32)
        max_y = np.zeros(max_id + 1, dtype=np.int32)

        for y in range(height):
            row = prov_ids[y, :]
            u_pids = np.unique(row)
            for p in u_pids:
                if p == 0:
                    continue
                if y < min_y[p]:
                    min_y[p] = y
                if y > max_y[p]:
                    max_y[p] = y

        for x in range(width):
            col = prov_ids[:, x]
            u_pids = np.unique(col)
            for p in u_pids:
                if p == 0:
                    continue
                if x < min_x[p]:
                    min_x[p] = x
                if x > max_x[p]:
                    max_x[p] = x

        bboxes[:, 0] = min_x
        bboxes[:, 1] = min_y
        bboxes[:, 2] = max_x
        bboxes[:, 3] = max_y

    log(f"Geometry calculated for {np.count_nonzero(valid)} active provinces in {time.time() - t0:.2f}s")
    return centroids, counts, bboxes


def process_heightmap(heightmap_path: str, output_path: str) -> None:
    """
    Normalizes heightmap.bmp into single-channel 8-bit height_map.png.
    """
    if not os.path.exists(heightmap_path):
        log(f"Warning: heightmap not found at {heightmap_path}. Generating flat heightmap.")
        img = Image.new("L", (5120, 2560), color=32)
        img.save(output_path, "PNG")
        return

    log(f"Processing heightmap: {heightmap_path}")
    t0 = time.time()
    h_img = Image.open(heightmap_path).convert("L")
    h_arr = np.array(h_img, dtype=np.uint8)

    # Normalize contrast if heightmap has restricted elevation scale
    min_v, max_v = int(np.min(h_arr)), int(np.max(h_arr))
    if max_v > min_v and (max_v - min_v) < 180:
        norm_arr = (((h_arr - min_v) / float(max_v - min_v)) * 255.0).astype(np.uint8)
        out_img = Image.fromarray(norm_arr, mode="L")
    else:
        out_img = h_img

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    out_img.save(output_path, "PNG", optimize=True)
    log(f"Saved normalized heightmap to {output_path} in {time.time() - t0:.2f}s")


def process_rivers(
    rivers_path: str,
    output_mask_path: str,
    prov_ids: np.ndarray,
    max_id: int
) -> Tuple[np.ndarray, Dict[int, List[int]]]:
    """
    Classifies river widths from rivers.bmp into rivers_mask.png:
    - 254, 255: Land / ocean -> 0 (no river)
    - 0..4: Minor rivers / sources -> 85 (tier 1)
    - 5..8: Standard rivers -> 170 (tier 2)
    - 9+: Major rivers -> 255 (tier 3)

    Also detects river borders between adjacent provinces.
    """
    height, width = prov_ids.shape
    river_borders: Dict[int, Set[int]] = {i: set() for i in range(max_id + 1)}

    if not os.path.exists(rivers_path):
        log(f"Warning: rivers.bmp not found at {rivers_path}. Creating blank river mask.")
        blank = Image.new("L", (width, height), color=0)
        blank.save(output_mask_path, "PNG")
        return np.zeros((height, width), dtype=np.uint8), {k: [] for k in river_borders}

    log(f"Processing hydrography from: {rivers_path}")
    t0 = time.time()
    r_img = Image.open(rivers_path)
    r_raw = np.array(r_img, dtype=np.uint8)

    # Clausewitz river classification
    is_river = (r_raw != 254) & (r_raw != 255)
    classified_rivers = np.zeros_like(r_raw, dtype=np.uint8)

    tier1 = is_river & (r_raw <= 4)
    tier2 = is_river & (r_raw > 4) & (r_raw <= 8)
    tier3 = is_river & (r_raw > 8)

    classified_rivers[tier1] = 85
    classified_rivers[tier2] = 170
    classified_rivers[tier3] = 255

    os.makedirs(os.path.dirname(output_mask_path), exist_ok=True)
    out_img = Image.fromarray(classified_rivers, mode="L")
    out_img.save(output_mask_path, "PNG", optimize=True)
    log(f"Saved classified rivers mask to {output_mask_path} (Rivers coverage: {np.count_nonzero(is_river)} px)")

    # Vectorized river borders detection
    log("Calculating transborder river barriers...")
    # Vertical boundaries
    v_diff = (prov_ids[:-1, :] != prov_ids[1:, :]) & (is_river[:-1, :] | is_river[1:, :])
    p_top = prov_ids[:-1, :][v_diff]
    p_bot = prov_ids[1:, :][v_diff]
    valid_v = (p_top > 0) & (p_bot > 0) & (p_top != p_bot)
    pairs_v = np.stack([p_top[valid_v], p_bot[valid_v]], axis=-1)

    # Horizontal boundaries
    h_diff = (prov_ids[:, :-1] != prov_ids[:, 1:]) & (is_river[:, :-1] | is_river[:, 1:])
    p_left = prov_ids[:, :-1][h_diff]
    p_right = prov_ids[:, 1:][h_diff]
    valid_h = (p_left > 0) & (p_right > 0) & (p_left != p_right)
    pairs_h = np.stack([p_left[valid_h], p_right[valid_h]], axis=-1)

    if pairs_v.size > 0 or pairs_h.size > 0:
        all_pairs = np.vstack([p for p in (pairs_v, pairs_h) if p.size > 0])
        all_pairs = np.sort(all_pairs, axis=1)
        unique_pairs = np.unique(all_pairs, axis=0)

        for p1, p2 in unique_pairs:
            p1_int, p2_int = int(p1), int(p2)
            if p1_int <= max_id and p2_int <= max_id:
                river_borders[p1_int].add(p2_int)
                river_borders[p2_int].add(p1_int)

    log(f"Transborder river pairs identified in {time.time() - t0:.2f}s")
    clean_river_borders = {k: sorted(list(v)) for k, v in river_borders.items()}
    return classified_rivers, clean_river_borders


def export_provinces_mask(
    prov_ids: np.ndarray,
    output_path: str
) -> None:
    """
    Saves uncompressed / lossless provinces_mask.png with 24-bit RGB packed IDs:
    R = id & 0xFF, G = (id >> 8) & 0xFF, B = (id >> 16) & 0xFF.
    """
    log(f"Exporting provinces mask to: {output_path}")
    t0 = time.time()
    out_r = (prov_ids & 0xFF).astype(np.uint8)
    out_g = ((prov_ids >> 8) & 0xFF).astype(np.uint8)
    out_b = ((prov_ids >> 16) & 0xFF).astype(np.uint8)

    height, width = prov_ids.shape
    out_np = np.stack([out_r, out_g, out_b], axis=-1)
    mask_img = Image.fromarray(out_np, mode="RGB")

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    mask_img.save(output_path, "PNG", compress_level=1)
    log(f"Provinces mask saved successfully in {time.time() - t0:.2f}s")


def build_manifest(
    output_path: str,
    provinces_meta: Dict[int, Dict[str, Any]],
    centroids: np.ndarray,
    counts: np.ndarray,
    bboxes: np.ndarray,
    river_borders: Dict[int, List[int]],
    province_to_state: Dict[int, int],
    width: int,
    height: int,
    max_id: int
) -> None:
    """
    Compiles data/map_manifest.json linking:
    province_id -> {state_id, centroid: [x, y], bbox, area, is_coastal, terrain_type, river_borders: []}
    """
    log(f"Assembling map manifest: {output_path}")
    t0 = time.time()
    manifest_provinces: Dict[str, Any] = {}

    for pid in range(1, max_id + 1):
        if counts[pid] == 0 and pid not in provinces_meta:
            continue

        meta = provinces_meta.get(pid, {})
        centroid = [float(centroids[pid, 0]), float(centroids[pid, 1])]
        bbox = [
            int(bboxes[pid, 0]),
            int(bboxes[pid, 1]),
            int(bboxes[pid, 2]),
            int(bboxes[pid, 3])
        ]
        area = int(counts[pid])
        state_id = province_to_state.get(pid, 0)
        is_coastal = bool(meta.get("is_coastal", False))
        terrain = str(meta.get("terrain_type", "plains"))
        rivers = river_borders.get(pid, [])

        manifest_provinces[str(pid)] = {
            "state_id": state_id,
            "centroid": centroid,
            "bbox": bbox,
            "area": area,
            "is_coastal": is_coastal,
            "terrain_type": terrain,
            "river_borders": rivers
        }

    manifest = {
        "metadata": {
            "generator": "tools/map_preprocessor.py",
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
            "width": width,
            "height": height,
            "total_provinces": len(manifest_provinces),
            "max_province_id": max_id
        },
        "provinces": manifest_provinces
    }

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)

    log(f"Manifest written with {len(manifest_provinces)} provinces in {time.time() - t0:.2f}s")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Clausewitz / TNO to Godot 4 Map Preprocessor"
    )
    # Default fallbacks pointing to local or workshop paths
    default_base = "F:/SteamLibrary/steamapps/workshop/content/394360/2438003901"
    default_map = f"{default_base}/map"

    parser.add_argument(
        "--bmp",
        default=os.path.join(default_map, "provinces.bmp") if os.path.exists(default_map) else "map_data/provinces.bmp",
        help="Path to provinces.bmp"
    )
    parser.add_argument(
        "--def",
        dest="definition_path",
        default=os.path.join(default_map, "definition.csv") if os.path.exists(default_map) else "map_data/definition.csv",
        help="Path to definition.csv"
    )
    parser.add_argument(
        "--heightmap",
        default=os.path.join(default_map, "heightmap.bmp") if os.path.exists(default_map) else "map_data/heightmap.bmp",
        help="Path to heightmap.bmp"
    )
    parser.add_argument(
        "--rivers",
        default=os.path.join(default_map, "rivers.bmp") if os.path.exists(default_map) else "map_data/rivers.bmp",
        help="Path to rivers.bmp"
    )
    parser.add_argument(
        "--states-dir",
        default=os.path.join(default_base, "history/states") if os.path.exists(default_base) else None,
        help="Path to history/states folder"
    )
    parser.add_argument(
        "--regions-json",
        default="map_data/starting_regions_state.json",
        help="Path to starting_regions_state.json"
    )
    parser.add_argument(
        "--out-dir",
        default="map_data",
        help="Output directory for generated assets (default: map_data)"
    )

    args = parser.parse_args()

    log("=" * 60)
    log("STARTING TNO MAP PREPROCESSOR PIPELINE")
    log("=" * 60)

    # 1. Parse definition.csv
    rgb_to_id, provinces_meta, max_id = parse_definition_csv(args.definition_path)

    # 2. State assignments
    state_map = load_state_assignments(args.states_dir, args.regions_json)

    # 3. Vectorized raster processing
    prov_ids, width, height = convert_provinces_raster(args.bmp, rgb_to_id, max_id)

    # 4. Geometry calculation
    centroids, counts, bboxes = compute_geometry(prov_ids, width, height, max_id)

    # 5. Export provinces_mask.png
    mask_out = os.path.join(args.out_dir, "provinces_mask.png")
    export_provinces_mask(prov_ids, mask_out)

    # 6. Process heightmap
    hmap_out = os.path.join(args.out_dir, "height_map.png")
    process_heightmap(args.heightmap, hmap_out)

    # 7. Process rivers
    rivers_out = os.path.join(args.out_dir, "rivers_mask.png")
    _, river_borders = process_rivers(args.rivers, rivers_out, prov_ids, max_id)

    # 8. Compile manifest
    manifest_out = os.path.join(args.out_dir, "map_manifest.json")
    build_manifest(
        manifest_out,
        provinces_meta,
        centroids,
        counts,
        bboxes,
        river_borders,
        state_map,
        width,
        height,
        max_id
    )

    log("=" * 60)
    log("MAP PREPROCESSING COMPLETED SUCCESSFULLY")
    log("=" * 60)


if __name__ == "__main__":
    main()
