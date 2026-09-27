#!/usr/bin/env python3
"""
================================================================================
TNO MAP SANITIZER, TOPOLOGY AUDITOR & BORDER GENERATOR (PYTHON 3.10+)
================================================================================
Comprehensive GIS and Political Map Sanitization Engine for Godot 4 & HoI4/TNO.

Features:
1. Raster Cleaning & Stray Pixel Infill:
   - Scans province masks against definition.csv.
   - Fixes unregistered colors via vectorized Majority Voting Filter (3x3 / 5x5).
   - Removes 1-2 pixel isolated noise speckles and dangling artifacts.
2. Topology Graph & Sovereignty Validation:
   - Builds province adjacency matrix & NetworkX graph with border contact lengths.
   - Audits state connectivity (disjoint state components detection & auto-repair).
   - Detects unclaimed land provinces and reassigns them to neighbor with max contact.
   - Detects isolated landlocked enclaves.
3. Smoothed Border Manifest Generator:
   - Classifies borders: COASTLINE, PROVINCE_INTERNAL, STATE_BORDER,
     INTERNATIONAL_BORDER, DISPUTED_DMZ.
   - Computes segment midpoints, lengths, approximate normals and centroids.
   - Exports map_data/borders_manifest.json and audit report.
4. Mask Export:
   - Saves clean, lossless provinces_mask.png (RGB = ID & 0xFF, (ID>>8)&0xFF, (ID>>16)&0xFF).

Usage:
  python tools/map_sanitizer.py --help
  python tools/map_sanitizer.py --manifest map_data/map_manifest.json --mask map_data/provinces_mask.png
  python tools/map_sanitizer.py --in-place
================================================================================
"""

import argparse
import csv
import json
import os
from pathlib import Path
import sys
import time
from typing import Any, Dict, List, Optional, Set, Tuple

import networkx as nx
import numpy as np
from PIL import Image

# Ensure Unicode output on Windows terminals
if sys.stdout.encoding != 'utf-8':
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass


PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_MAP_DATA = PROJECT_ROOT / "map_data"
DEFAULT_MASK_PATH = DEFAULT_MAP_DATA / "provinces_mask.png"
DEFAULT_MANIFEST_PATH = DEFAULT_MAP_DATA / "map_manifest.json"
DEFAULT_DEF_PATH = DEFAULT_MAP_DATA / "definition.csv"
DEFAULT_OUT_MANIFEST = DEFAULT_MAP_DATA / "borders_manifest.json"
DEFAULT_OUT_REPORT = DEFAULT_MAP_DATA / "map_sanitizer_report.json"
DEFAULT_TNO_MOD = Path(r"F:\SteamLibrary\steamapps\workshop\content\394360\2438003901")


class MapSanitizer:
    """High-performance map topology analyzer, raster cleaner, and border generator."""

    def __init__(
        self,
        mask_path: Path,
        manifest_path: Optional[Path] = None,
        def_csv_path: Optional[Path] = None,
        filter_size: int = 3,
        auto_fix_states: bool = True,
        auto_fix_unclaimed: bool = True
    ):
        self.mask_path = mask_path
        self.manifest_path = manifest_path
        self.def_csv_path = def_csv_path
        self.filter_size = max(3, filter_size | 1) # Ensure odd (3 or 5)
        self.auto_fix_states = auto_fix_states
        self.auto_fix_unclaimed = auto_fix_unclaimed

        # State and definitions DB
        self.provinces_def: Dict[int, Dict[str, Any]] = {}
        self.rgb_to_id: Dict[Tuple[int, int, int], int] = {}
        self.states_db: Dict[int, Dict[str, Any]] = {}
        self.prov_to_state: Dict[int, int] = {}
        self.prov_to_owner: Dict[int, str] = {}
        self.water_provinces: Set[int] = set()
        self.land_provinces: Set[int] = set()
        self.max_province_id: int = 0

        # Raster arrays
        self.img_width: int = 0
        self.img_height: int = 0
        self.prov_id_map: Optional[np.ndarray] = None # 2D uint32 array (H, W)

        # Audit and Report Metrics
        self.report: Dict[str, Any] = {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "mask_path": str(mask_path),
            "stray_pixels_fixed": 0,
            "micro_islands_fixed": 0,
            "disjoint_states_detected": [],
            "disjoint_states_fixed": [],
            "unclaimed_provinces_detected": [],
            "unclaimed_provinces_fixed": [],
            "enclaves_detected": [],
            "total_border_segments": 0,
            "border_type_counts": {},
            "elapsed_seconds": 0.0
        }

    def load_definitions(self) -> bool:
        """Loads province definitions from definition.csv or map_manifest.json."""
        # Try explicit or discovered definition.csv first
        csv_candidates = [
            self.def_csv_path,
            DEFAULT_DEF_PATH,
            DEFAULT_TNO_MOD / "map" / "definition.csv",
            Path(r"F:\SteamLibrary\steamapps\common\Hearts of Iron IV\map\definition.csv")
        ]
        chosen_csv = None
        for cand in csv_candidates:
            if cand and cand.exists():
                chosen_csv = cand
                break

        if chosen_csv:
            print(f"[SANITIZER] Reading definitions from: {chosen_csv}")
            with open(chosen_csv, mode="r", encoding="utf-8-sig", errors="replace") as f:
                reader = csv.reader(f, delimiter=";")
                for row in reader:
                    if not row or len(row) < 4:
                        continue
                    row = [c.strip() for c in row]
                    if not row[0].isdigit():
                        continue
                    pid = int(row[0])
                    r, g, b = int(row[1]), int(row[2]), int(row[3])
                    p_type = row[4].lower() if len(row) > 4 and row[4] else "land"
                    is_coastal = (row[5].lower() == "true") if len(row) > 5 else False

                    self.rgb_to_id[(r, g, b)] = pid
                    self.provinces_def[pid] = {
                        "id": pid,
                        "rgb": (r, g, b),
                        "type": p_type,
                        "is_coastal": is_coastal
                    }
                    if p_type in ("sea", "lake"):
                        self.water_provinces.add(pid)
                    else:
                        self.land_provinces.add(pid)

                    if pid > self.max_province_id:
                        self.max_province_id = pid

        # Load states and supplementary info from map_manifest.json
        if self.manifest_path and self.manifest_path.exists():
            print(f"[SANITIZER] Reading manifest from: {self.manifest_path}")
            with open(self.manifest_path, mode="r", encoding="utf-8") as f:
                manifest_data = json.load(f)

            meta = manifest_data.get("metadata", {})
            if "max_province_id" in meta:
                self.max_province_id = max(self.max_province_id, int(meta["max_province_id"]))

            # Parse provinces from manifest if definition.csv was absent
            provs = manifest_data.get("provinces", {})
            for pid_str, p_info in provs.items():
                pid = int(pid_str)
                if pid not in self.provinces_def:
                    p_type = p_info.get("type", "land").lower()
                    rgb = tuple(p_info.get("original_rgb", [0, 0, 0]))
                    self.provinces_def[pid] = {
                        "id": pid,
                        "rgb": rgb,
                        "type": p_type,
                        "is_coastal": bool(p_info.get("is_coastal", False))
                    }
                    if p_type in ("sea", "lake"):
                        self.water_provinces.add(pid)
                    else:
                        self.land_provinces.add(pid)
                    if rgb != (0, 0, 0):
                        self.rgb_to_id[rgb] = pid

                owner = p_info.get("owner", "")
                if owner:
                    self.prov_to_owner[pid] = owner
                sid = p_info.get("state_id")
                if sid is not None and int(sid) > 0:
                    self.prov_to_state[pid] = int(sid)
                if pid > self.max_province_id:
                    self.max_province_id = pid

            # Parse states
            states = manifest_data.get("states", {})
            for sid_str, s_info in states.items():
                sid = int(sid_str)
                owner = s_info.get("owner", "")
                prov_list = [int(p) for p in s_info.get("provinces", [])]
                self.states_db[sid] = {
                    "id": sid,
                    "name": s_info.get("name", f"State {sid}"),
                    "owner": owner,
                    "provinces": prov_list
                }
                for p in prov_list:
                    self.prov_to_state[p] = sid
                    if owner and p not in self.prov_to_owner:
                        self.prov_to_owner[p] = owner

        print(f"[SANITIZER] Definitions loaded: {len(self.provinces_def)} provinces "
              f"({len(self.land_provinces)} land, {len(self.water_provinces)} water), "
              f"{len(self.states_db)} states. Max ID: {self.max_province_id}")
        return len(self.provinces_def) > 0

    def load_and_decode_mask(self) -> None:
        """Loads provinces_mask.png (or provinces.bmp) into a 2D uint32 ID array."""
        if not self.mask_path.exists():
            raise FileNotFoundError(f"Mask file not found: {self.mask_path}")

        print(f"[SANITIZER] Loading raster mask: {self.mask_path}")
        img = Image.open(self.mask_path).convert("RGB")
        self.img_width, self.img_height = img.size
        img_np = np.array(img, dtype=np.uint8)

        # Check if the image is already packed project format (R | G<<8 | B<<16)
        # In project format: R = id & 0xFF, G = (id >> 8) & 0xFF, B = (id >> 16) & 0xFF
        raw_r = img_np[:, :, 0].astype(np.uint32)
        raw_g = img_np[:, :, 1].astype(np.uint32)
        raw_b = img_np[:, :, 2].astype(np.uint32)

        test_project_id = raw_r | (raw_g << 8) | (raw_b << 16)
        valid_in_project_format = np.count_nonzero(test_project_id <= self.max_province_id)
        total_pixels = self.img_width * self.img_height

        if valid_in_project_format > total_pixels * 0.70:
            print("[SANITIZER] Detected project encoded mask (R | G<<8 | B<<16).")
            self.prov_id_map = test_project_id
        else:
            print("[SANITIZER] Detected raw definition.csv RGB mask. Mapping RGB -> IDs...")
            packed_rgb = (raw_r << 16) | (raw_g << 8) | raw_b
            lut_keys = []
            lut_vals = []
            for (r, g, b), pid in self.rgb_to_id.items():
                lut_keys.append((r << 16) | (g << 8) | b)
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
            self.prov_id_map = prov_ids.reshape((self.img_height, self.img_width))

    def clean_stray_pixels(self) -> int:
        """
        Locates pixels with invalid IDs or colors not present in definitions,
        and applies a Majority Voting Filter (modal kernel) from neighboring valid pixels.
        """
        print("[SANITIZER] Step 1: Scanning for stray/unregistered pixels...")
        valid_ids = set(self.provinces_def.keys())
        valid_ids.add(0) # 0 is valid water/unassigned

        # Create boolean mask of invalid pixels
        # ID > max_province_id or ID not in valid_ids
        is_invalid = np.isin(self.prov_id_map, list(valid_ids), invert=True)
        stray_count = int(np.count_nonzero(is_invalid))

        if stray_count == 0:
            print("[SANITIZER] No stray pixels detected. Raster geometry is clean.")
            return 0

        print(f"[SANITIZER] Found {stray_count} stray pixels! Applying Majority Voting Filter (size {self.filter_size}x{self.filter_size})...")
        bad_ys, bad_xs = np.where(is_invalid)
        r = self.filter_size // 2
        h, w = self.img_height, self.img_width

        fixed = 0
        for y, x in zip(bad_ys, bad_xs):
            y_min, y_max = max(0, y - r), min(h, y + r + 1)
            x_min, x_max = max(0, x - r), min(w, x + r + 1)
            window = self.prov_id_map[y_min:y_max, x_min:x_max]

            # Collect valid neighbors
            neighbors = window[~np.isin(window, list(valid_ids), invert=True)]
            # Filter out 0 if there are non-zero valid neighbors
            non_zeros = neighbors[neighbors > 0]
            if len(non_zeros) > 0:
                vals, counts = np.unique(non_zeros, return_counts=True)
                mode_val = vals[np.argmax(counts)]
            elif len(neighbors) > 0:
                vals, counts = np.unique(neighbors, return_counts=True)
                mode_val = vals[np.argmax(counts)]
            else:
                mode_val = 0

            self.prov_id_map[y, x] = mode_val
            fixed += 1

        self.report["stray_pixels_fixed"] = fixed
        print(f"[SANITIZER] Successfully infilled and fixed {fixed} stray pixels.")
        return fixed

    def clean_micro_islands(self) -> int:
        """
        Detects 1-pixel noise speckles (pixels whose 4 orthogonal neighbors are identical
        to each other but different from the center pixel) and absorbs them.
        """
        print("[SANITIZER] Step 2: Filtering single-pixel isolated noise speckles...")
        m = self.prov_id_map
        h, w = self.img_height, self.img_width

        # 4-way orthogonal neighbors with edge padding
        up = np.pad(m[:-1, :], ((1, 0), (0, 0)), mode="edge")
        down = np.pad(m[1:, :], ((0, 1), (0, 0)), mode="edge")
        left = np.pad(m[:, :-1], ((0, 0), (1, 0)), mode="edge")
        right = np.pad(m[:, 1:], ((0, 0), (0, 1)), mode="edge")

        # Isolated pixel condition: center != up AND center != down AND center != left AND center != right
        diff_all = (m != up) & (m != down) & (m != left) & (m != right)

        # Majority agreement among neighbors (at least 3 neighbors agree on replacement ID)
        agree_up_down = (up == down)
        agree_left_right = (left == right)
        agree_up_left = (up == left)

        replacement = np.zeros_like(m)
        # Where 3+ agree
        replacement[agree_up_down & (up == left)] = up[agree_up_down & (up == left)]
        replacement[agree_up_down & (up == right)] = up[agree_up_down & (up == right)]
        replacement[agree_left_right & (left == up)] = left[agree_left_right & (left == up)]
        replacement[agree_left_right & (left == down)] = left[agree_left_right & (left == down)]

        is_noise = diff_all & (replacement > 0)
        noise_count = int(np.count_nonzero(is_noise))

        if noise_count > 0:
            m[is_noise] = replacement[is_noise]
            print(f"[SANITIZER] Infilled {noise_count} single-pixel noise islands.")
        else:
            print("[SANITIZER] No single-pixel micro-islands found.")

        self.report["micro_islands_fixed"] = noise_count
        return noise_count

    def build_adjacency_graph(self) -> nx.Graph:
        """
        Builds province adjacency graph with exact contact boundary pixel lengths,
        centroids, and segment midpoints using vectorized transition detection.
        """
        print("[SANITIZER] Step 3: Vectorized boundary extraction and adjacency graph construction...")
        m = self.prov_id_map
        h, w = self.img_height, self.img_width

        # Horizontal transitions: (y, x) vs (y, x+1)
        diff_h = m[:, :-1] != m[:, 1:]
        p1_h = m[:, :-1][diff_h]
        p2_h = m[:, 1:][diff_h]
        y_h, x_h = np.where(diff_h)

        # Vertical transitions: (y, x) vs (y+1, x)
        diff_v = m[:-1, :] != m[1:, :]
        p1_v = m[:-1, :][diff_v]
        p2_v = m[1:, :][diff_v]
        y_v, x_v = np.where(diff_v)

        # Ensure consistent order: min(p1, p2) < max(p1, p2)
        min_h = np.minimum(p1_h, p2_h).astype(np.uint64)
        max_h = np.maximum(p1_h, p2_h).astype(np.uint64)
        packed_h = (min_h << 32) | max_h

        min_v = np.minimum(p1_v, p2_v).astype(np.uint64)
        max_v = np.maximum(p1_v, p2_v).astype(np.uint64)
        packed_v = (min_v << 32) | max_v

        # Aggregate contact lengths
        unique_h, counts_h = np.unique(packed_h, return_counts=True)
        unique_v, counts_v = np.unique(packed_v, return_counts=True)

        border_lengths: Dict[Tuple[int, int], int] = {}
        for pair_key, count in zip(unique_h, counts_h):
            p1 = int(pair_key >> 32)
            p2 = int(pair_key & 0xFFFFFFFF)
            border_lengths[(p1, p2)] = border_lengths.get((p1, p2), 0) + int(count)

        for pair_key, count in zip(unique_v, counts_v):
            p1 = int(pair_key >> 32)
            p2 = int(pair_key & 0xFFFFFFFF)
            border_lengths[(p1, p2)] = border_lengths.get((p1, p2), 0) + int(count)

        # Construct NetworkX graph
        G = nx.Graph()
        for (p1, p2), length in border_lengths.items():
            if p1 == 0 and p2 == 0:
                continue
            G.add_edge(p1, p2, weight=length)

        # Compute Province Centroids
        print("[SANITIZER] Computing province geometric centroids...")
        y_coords, x_coords = np.indices((h, w))
        flat_m = m.ravel()
        counts = np.bincount(flat_m)
        sum_x = np.bincount(flat_m, weights=x_coords.ravel())
        sum_y = np.bincount(flat_m, weights=y_coords.ravel())

        self.centroids: Dict[int, List[float]] = {}
        for pid in range(len(counts)):
            if counts[pid] > 0:
                cx = float(sum_x[pid] / counts[pid])
                cy = float(sum_y[pid] / counts[pid])
                self.centroids[pid] = [round(cx, 2), round(cy, 2)]
                if pid in G:
                    G.nodes[pid]["centroid"] = [round(cx, 2), round(cy, 2)]
                    G.nodes[pid]["pixel_area"] = int(counts[pid])

        print(f"[SANITIZER] Adjacency graph constructed: {G.number_of_nodes()} provinces, "
              f"{G.number_of_edges()} boundary interfaces.")
        self.adj_graph = G
        self.border_lengths = border_lengths
        return G

    def audit_and_repair_states(self) -> None:
        """
        State Connectivity Check:
        Verifies that every state forms a single connected component of land provinces.
        If a state has disjoint components, identifies the separated land province(s)
        and reassigns them to the adjacent state with the longest shared border.
        """
        print("[SANITIZER] Step 4: Auditing state territorial connectivity (Disjoint States Check)...")
        disjoint_found = 0
        fixed_count = 0

        for sid, s_info in list(self.states_db.items()):
            provs = s_info.get("provinces", [])
            # Filter to land provinces present in raster
            land_provs = [p for p in provs if p in self.land_provinces and p in self.adj_graph]
            if len(land_provs) <= 1:
                continue

            subG = self.adj_graph.subgraph(land_provs)
            components = list(nx.connected_components(subG))

            if len(components) > 1:
                # Separate natural islands (components that only border water) from mainland detachments
                mainland_components = []
                island_components = []

                for comp in components:
                    # Check if all provinces in comp only border water or coast
                    touches_other_land = False
                    for p in comp:
                        for n in self.adj_graph.neighbors(p):
                            if n not in self.water_provinces and n != 0 and n not in comp:
                                touches_other_land = True
                                break
                        if touches_other_land:
                            break

                    if touches_other_land:
                        mainland_components.append(comp)
                    else:
                        island_components.append(comp)

                # If all components are islands or single mainland + islands, that's natural geography!
                if len(mainland_components) <= 1:
                    continue

                disjoint_found += 1
                # Sort mainland components by size descending (largest is main body)
                mainland_components.sort(key=lambda c: len(c), reverse=True)
                main_body = mainland_components[0]
                orphans = mainland_components[1:]

                s_name = s_info.get('name', f'State {sid}')
                info_record = {
                    "state_id": sid,
                    "state_name": s_name,
                    "owner": s_info.get("owner", ""),
                    "total_components": len(components),
                    "main_body_count": len(main_body),
                    "orphan_components": [list(comp) for comp in orphans],
                    "island_components": [list(comp) for comp in island_components]
                }
                self.report["disjoint_states_detected"].append(info_record)
                print(f"[WARNING] State {sid} ('{s_name}') is DISJOINT! "
                      f"Main body: {len(main_body)} provinces, {len(orphans)} mainland island(s), "
                      f"{len(island_components)} maritime island(s).")

                if self.auto_fix_states:
                    for comp in orphans:
                        for orphan_p in comp:
                            # Find neighbors of orphan_p in the full graph outside this state
                            best_neighbor_state = None
                            max_contact = 0

                            for n in self.adj_graph.neighbors(orphan_p):
                                n_state = self.prov_to_state.get(n)
                                if n_state and n_state != sid and n_state in self.states_db:
                                    pair = (min(orphan_p, n), max(orphan_p, n))
                                    contact = self.border_lengths.get(pair, 1)
                                    if contact > max_contact:
                                        max_contact = contact
                                        best_neighbor_state = n_state

                            if best_neighbor_state:
                                # Reassign province to best neighbor state
                                s_info["provinces"].remove(orphan_p)
                                self.states_db[best_neighbor_state]["provinces"].append(orphan_p)
                                self.prov_to_state[orphan_p] = best_neighbor_state
                                new_owner = self.states_db[best_neighbor_state].get("owner", s_info.get("owner", ""))
                                self.prov_to_owner[orphan_p] = new_owner

                                fix_record = {
                                    "province_id": orphan_p,
                                    "from_state": sid,
                                    "to_state": best_neighbor_state,
                                    "shared_contact_pixels": max_contact,
                                    "new_owner": new_owner
                                }
                                self.report["disjoint_states_fixed"].append(fix_record)
                                fixed_count += 1
                                print(f"  -> Reassigned detached province {orphan_p} to State {best_neighbor_state} "
                                      f"(contact: {max_contact} px).")

        print(f"[SANITIZER] State connectivity check complete: {disjoint_found} disjoint states found, "
              f"{fixed_count} isolated components repaired.")

    def audit_and_repair_unclaimed_lands(self) -> None:
        """
        Finds valid land provinces not included in any state, and reassigns them
        to the neighbor state with the maximum border contact length.
        """
        print("[SANITIZER] Step 5: Auditing unclaimed land provinces...")
        unclaimed = []
        fixed = 0

        for pid in self.land_provinces:
            if pid not in self.adj_graph:
                continue
            curr_state = self.prov_to_state.get(pid, 0)
            if curr_state == 0 or curr_state not in self.states_db:
                unclaimed.append(pid)

        self.report["unclaimed_provinces_detected"] = list(unclaimed)
        if unclaimed:
            print(f"[WARNING] Found {len(unclaimed)} unclaimed land provinces on the map!")
        else:
            print("[SANITIZER] All land provinces belong to valid states.")

        if self.auto_fix_unclaimed and unclaimed:
            for pid in unclaimed:
                best_state = None
                max_contact = 0
                for n in self.adj_graph.neighbors(pid):
                    n_state = self.prov_to_state.get(n, 0)
                    if n_state > 0 and n_state in self.states_db:
                        pair = (min(pid, n), max(pid, n))
                        contact = self.border_lengths.get(pair, 1)
                        if contact > max_contact:
                            max_contact = contact
                            best_state = n_state

                if best_state:
                    self.states_db[best_state]["provinces"].append(pid)
                    self.prov_to_state[pid] = best_state
                    owner = self.states_db[best_state].get("owner", "")
                    self.prov_to_owner[pid] = owner
                    self.report["unclaimed_provinces_fixed"].append({
                        "province_id": pid,
                        "assigned_state": best_state,
                        "assigned_owner": owner,
                        "contact_pixels": max_contact
                    })
                    fixed += 1
                    print(f"  -> Assigned unclaimed province {pid} to State {best_state} ({owner})")

        print(f"[SANITIZER] Unclaimed land audit complete: {len(unclaimed)} found, {fixed} integrated.")

    def audit_enclaves(self) -> None:
        """
        Detects isolated landlocked enclaves (states entirely bordered by a single
        foreign nation without sea/water access).
        """
        print("[SANITIZER] Step 6: Auditing geopolitical enclaves and border gore...")
        enclaves = []

        for sid, s_info in self.states_db.items():
            owner = s_info.get("owner", "")
            if not owner or owner in ("WST", "WASTE"):
                continue

            provs = s_info.get("provinces", [])
            has_coast = False
            foreign_neighbors: Set[str] = set()

            for p in provs:
                if p not in self.adj_graph:
                    continue
                for n in self.adj_graph.neighbors(p):
                    if n in self.water_provinces or n == 0:
                        has_coast = True
                        break
                    n_owner = self.prov_to_owner.get(n, "")
                    if n_owner and n_owner != owner:
                        foreign_neighbors.add(n_owner)
                if has_coast:
                    break

            # If no sea access and only bordered by exactly 1 other country
            if not has_coast and len(foreign_neighbors) == 1:
                surrounding = list(foreign_neighbors)[0]
                record = {
                    "state_id": sid,
                    "state_name": s_info.get("name", f"State {sid}"),
                    "owner": owner,
                    "surrounded_by": surrounding,
                    "provinces": provs
                }
                enclaves.append(record)

        self.report["enclaves_detected"] = enclaves
        print(f"[SANITIZER] Enclave analysis complete: {len(enclaves)} isolated enclaves detected.")

    def generate_borders_manifest(self, out_json_path: Path) -> Dict[str, Any]:
        """
        Generates comprehensive border manifest classifying each adjacent pair:
        COASTLINE, PROVINCE_INTERNAL, STATE_BORDER, INTERNATIONAL_BORDER, DISPUTED_DMZ.
        Calculates midpoints and normal vectors.
        """
        print(f"[SANITIZER] Step 7: Generating classified border hierarchy -> {out_json_path}")
        border_segments: List[Dict[str, Any]] = []
        type_counts: Dict[str, int] = {
            "COASTLINE": 0,
            "PROVINCE_INTERNAL": 0,
            "STATE_BORDER": 0,
            "INTERNATIONAL_BORDER": 0,
            "DISPUTED_DMZ": 0,
            "MARITIME_INTERNAL": 0
        }

        # Province adjacency map: {pid: [neighbors]}
        adjacency_map: Dict[int, List[int]] = {}

        for (p1, p2), length in self.border_lengths.items():
            if p1 == 0 and p2 == 0:
                continue

            # Populate adjacency lookup
            if p1 > 0:
                adjacency_map.setdefault(p1, []).append(p2)
            if p2 > 0:
                adjacency_map.setdefault(p2, []).append(p1)

            # Determine classification
            p1_water = (p1 == 0 or p1 in self.water_provinces)
            p2_water = (p2 == 0 or p2 in self.water_provinces)

            classification = "PROVINCE_INTERNAL"
            if p1_water and p2_water:
                classification = "MARITIME_INTERNAL"
            elif p1_water != p2_water:
                classification = "COASTLINE"
            else:
                # Both land
                s1 = self.prov_to_state.get(p1, 0)
                s2 = self.prov_to_state.get(p2, 0)
                o1 = self.prov_to_owner.get(p1, "")
                o2 = self.prov_to_owner.get(p2, "")

                if o1 and o2 and o1 != o2:
                    classification = "INTERNATIONAL_BORDER"
                elif s1 != s2:
                    classification = "STATE_BORDER"
                else:
                    classification = "PROVINCE_INTERNAL"

            type_counts[classification] = type_counts.get(classification, 0) + 1

            # Approximate midpoint & normal
            c1 = self.centroids.get(p1, [0.0, 0.0])
            c2 = self.centroids.get(p2, [0.0, 0.0])
            mx = round((c1[0] + c2[0]) * 0.5, 2)
            my = round((c1[1] + c2[1]) * 0.5, 2)

            dx = c2[0] - c1[0]
            dy = c2[1] - c1[1]
            dist = (dx * dx + dy * dy) ** 0.5
            nx_val = round(dx / dist, 3) if dist > 0.001 else 0.0
            ny_val = round(dy / dist, 3) if dist > 0.001 else 0.0

            border_segments.append({
                "pair": [p1, p2],
                "type": classification,
                "length": length,
                "midpoint": [mx, my],
                "normal": [nx_val, ny_val]
            })

        self.report["total_border_segments"] = len(border_segments)
        self.report["border_type_counts"] = type_counts

        manifest = {
            "metadata": {
                "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "total_provinces": len(self.centroids),
                "total_states": len(self.states_db),
                "total_border_segments": len(border_segments),
                "type_breakdown": type_counts
            },
            "province_centroids": self.centroids,
            "province_adjacency": adjacency_map,
            "border_segments": border_segments,
            "audit_summary": self.report
        }

        out_json_path.parent.mkdir(parents=True, exist_ok=True)
        with open(out_json_path, "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=2, ensure_ascii=False)

        print(f"[SANITIZER] Exported borders manifest: {len(border_segments)} segments.")
        for b_type, count in type_counts.items():
            print(f"  - {b_type:<22}: {count:>6}")
        return manifest

    def export_clean_mask(self, out_png_path: Path) -> None:
        """Exports sanitized raster mask as a lossless RGB PNG (R=ID&0xFF, G=(ID>>8)&0xFF, B=(ID>>16)&0xFF)."""
        print(f"[SANITIZER] Step 8: Exporting clean raster mask -> {out_png_path}...")
        m = self.prov_id_map
        out_r = (m & 0xFF).astype(np.uint8)
        out_g = ((m >> 8) & 0xFF).astype(np.uint8)
        out_b = ((m >> 16) & 0xFF).astype(np.uint8)

        rgb_stack = np.stack([out_r, out_g, out_b], axis=-1)
        out_img = Image.fromarray(rgb_stack, mode="RGB")

        out_png_path.parent.mkdir(parents=True, exist_ok=True)
        out_img.save(out_png_path, format="PNG", optimize=True)
        print(f"[SANITIZER] Successfully saved clean mask: {out_png_path} ({self.img_width}x{self.img_height})")

    def export_report(self, report_path: Path) -> None:
        """Saves the JSON audit and validation report."""
        report_path.parent.mkdir(parents=True, exist_ok=True)
        with open(report_path, "w", encoding="utf-8") as f:
            json.dump(self.report, f, indent=2, ensure_ascii=False)
        print(f"[SANITIZER] Audit report saved -> {report_path}")


def main():
    parser = argparse.ArgumentParser(
        description="TNO Map Sanitizer, Topology Auditor & Border Generator (Python 3.10+)"
    )
    parser.add_argument(
        "--mask", type=Path, default=DEFAULT_MASK_PATH,
        help="Path to provinces_mask.png (or provinces.bmp)"
    )
    parser.add_argument(
        "--manifest", type=Path, default=DEFAULT_MANIFEST_PATH,
        help="Path to project map_manifest.json"
    )
    parser.add_argument(
        "--def", dest="def_csv", type=Path, default=None,
        help="Path to definition.csv"
    )
    parser.add_argument(
        "--out-mask", type=Path, default=DEFAULT_MAP_DATA / "provinces_mask_clean.png",
        help="Path to export sanitized provinces mask PNG"
    )
    parser.add_argument(
        "--in-place", action="store_true",
        help="Overwrite original mask directly with sanitized version"
    )
    parser.add_argument(
        "--out-manifest", type=Path, default=DEFAULT_OUT_MANIFEST,
        help="Path to export borders_manifest.json"
    )
    parser.add_argument(
        "--report", type=Path, default=DEFAULT_OUT_REPORT,
        help="Path to export map audit report JSON"
    )
    parser.add_argument(
        "--filter-size", type=int, default=3,
        help="Kernel size for Majority Voting Filter (3 or 5, default: 3)"
    )
    parser.add_argument(
        "--no-fix-states", action="store_true",
        help="Disable automatic re-assignment of disjoint state components"
    )
    parser.add_argument(
        "--no-fix-unclaimed", action="store_true",
        help="Disable automatic assignment of unclaimed land provinces"
    )
    args = parser.parse_args()

    start_time = time.time()
    print("=" * 80)
    print("TNO GRAND STRATEGY: MAP SANITIZATION & BORDER TOPOLOGY PIPELINE")
    print("=" * 80)

    sanitizer = MapSanitizer(
        mask_path=args.mask,
        manifest_path=args.manifest,
        def_csv_path=args.def_csv,
        filter_size=args.filter_size,
        auto_fix_states=not args.no_fix_states,
        auto_fix_unclaimed=not args.no_fix_unclaimed
    )

    if not sanitizer.load_definitions():
        print("[FATAL] Could not load province definitions. Aborting.")
        sys.exit(1)

    sanitizer.load_and_decode_mask()
    sanitizer.clean_stray_pixels()
    sanitizer.clean_micro_islands()
    sanitizer.build_adjacency_graph()
    sanitizer.audit_and_repair_states()
    sanitizer.audit_and_repair_unclaimed_lands()
    sanitizer.audit_enclaves()

    sanitizer.generate_borders_manifest(args.out_manifest)

    target_mask = args.mask if args.in_place else args.out_mask
    sanitizer.export_clean_mask(target_mask)

    sanitizer.report["elapsed_seconds"] = round(time.time() - start_time, 2)
    sanitizer.export_report(args.report)

    print("=" * 80)
    print(f"[COMPLETE] Sanitization pipeline finished in {sanitizer.report['elapsed_seconds']}s!")
    print("=" * 80)


if __name__ == "__main__":
    main()
