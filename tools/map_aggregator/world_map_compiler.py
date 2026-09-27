#!/usr/bin/env python3
"""
World Map Compiler & GIS Data Pipeline for Godot 4.
Performs layered VFS cascading merge, raster GIS vector processing,
topological graph generation, state/country aggregation, and integrity auditing.
"""

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time
from typing import Any, Dict, List, Optional, Set, Tuple

import numpy as np
from PIL import Image
try:
    import scipy.ndimage
    SCIPY_AVAILABLE = True
except ImportError:
    SCIPY_AVAILABLE = False

from .config import PipelineConfig, SourceLayer
from .clausewitz_state_parser import (
    ClausewitzParser,
    ClausewitzStateParser,
    ClausewitzTokenizer,
    StateData,
    load_localization_db,
    parse_clausewitz_file,
    read_clausewitz_text,
)


class WorldMapCompiler:
    """Master orchestrator for map compilation, layered overrides, and GIS generation."""

    def __init__(self, config: PipelineConfig):
        self.config = config
        self.loc_db: Dict[str, str] = {}
        self.provinces_def: Dict[int, Dict[str, Any]] = {}
        self.rgb_to_id: Dict[Tuple[int, int, int], int] = {}
        self.states_db: Dict[int, StateData] = {}
        self.countries_db: Dict[str, Dict[str, Any]] = {}
        self.country_colors: Dict[str, List[float]] = {}
        self.adjacencies_extra: Dict[int, Set[int]] = {}
        self.audit_report: Dict[str, Any] = {}

    # ==========================================================================
    # 1. VFS RESOLUTION & LOCALIZATION
    # ==========================================================================
    def resolve_highest_priority_file(self, rel_subpath: str) -> Optional[Tuple[Path, SourceLayer]]:
        """Finds the first existing file traversing layers from highest priority to lowest."""
        for layer in self.config.get_layers_highest_first():
            candidate = layer.get_subpath(*rel_subpath.split("/"))
            if candidate.exists() and candidate.is_file():
                return candidate, layer
        return None

    def load_localizations(self) -> None:
        """Loads and merges localization files (EN / RU) across all layers."""
        print("[PIPELINE] Loading localization databases...")
        loc_dirs = []
        for l in sorted(self.config.loc_layers, key=lambda x: x.priority):
            loc_dirs.append(l.root_path)
        # Also check localisation subfolder in data layers
        for layer in self.config.get_layers_lowest_first():
            sub_loc = layer.get_subpath("localisation")
            if sub_loc.exists() and sub_loc.is_dir():
                loc_dirs.append(sub_loc)

        self.loc_db = load_localization_db(loc_dirs)
        print(f"[PIPELINE] Loaded {len(self.loc_db)} localization keys.")

    # ==========================================================================
    # 2. DEFINITION.CSV MERGING (LAYERED OVERRIDE)
    # ==========================================================================
    def merge_definitions(self) -> None:
        """
        Parses definition.csv cascading from lowest priority (Vanilla) to highest (Submod).
        Higher priority layers overwrite conflicting province IDs.
        """
        print("[PIPELINE] Cascading definition.csv across layers...")
        self.provinces_def.clear()
        self.rgb_to_id.clear()

        layer_stats: Dict[str, int] = {}

        for layer in self.config.get_layers_lowest_first():
            def_path = layer.get_subpath("map", "definition.csv")
            if not def_path.exists():
                continue

            count = 0
            with open(def_path, mode="r", encoding="utf-8-sig", errors="replace") as f:
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

                    prov_type = row[4] if len(row) > 4 and row[4] else "land"
                    is_coastal = (row[5].lower() == "true") if len(row) > 5 else False
                    terrain = row[6] if len(row) > 6 and row[6] else "unknown"
                    continent = int(row[7]) if len(row) > 7 and row[7].isdigit() else 0

                    rgb = (r, g, b)
                    self.rgb_to_id[rgb] = prov_id
                    self.provinces_def[prov_id] = {
                        "id": prov_id,
                        "rgb": [r, g, b],
                        "type": prov_type,
                        "is_coastal": is_coastal,
                        "terrain": terrain,
                        "continent": continent,
                        "source_layer": layer.name,
                        "state_id": None
                    }
                    count += 1
            layer_stats[layer.name] = count
            print(f"  -> Layer [{layer.name}]: Loaded/Updated {count} definitions.")

        self.audit_report["definitions_layer_counts"] = layer_stats
        print(f"[PIPELINE] Total unique province definitions: {len(self.provinces_def)}")

    # ==========================================================================
    # 3. STRAITS & ADJACENCIES.CSV
    # ==========================================================================
    def parse_adjacencies_csv(self) -> None:
        """Parses map/adjacencies.csv (straits, canals, water crossings) across layers."""
        self.adjacencies_extra.clear()
        resolved = self.resolve_highest_priority_file("map/adjacencies.csv")
        if not resolved:
            return

        adj_path, layer = resolved
        print(f"[PIPELINE] Loading extra adjacencies from [{layer.name}]: {adj_path}")
        with open(adj_path, mode="r", encoding="utf-8-sig", errors="replace") as f:
            reader = csv.reader(f, delimiter=";")
            for row in reader:
                if not row or len(row) < 3:
                    continue
                row = [c.strip() for c in row]
                if not row[0].isdigit() or not row[1].isdigit():
                    continue

                p_from = int(row[0])
                p_to = int(row[1])
                adj_type = row[2].lower()

                # Accept sea/canal/river connections
                if adj_type in ["sea", "canal", "river", "land"]:
                    if p_from not in self.adjacencies_extra:
                        self.adjacencies_extra[p_from] = set()
                    if p_to not in self.adjacencies_extra:
                        self.adjacencies_extra[p_to] = set()
                    self.adjacencies_extra[p_from].add(p_to)
                    self.adjacencies_extra[p_to].add(p_from)

        print(f"[PIPELINE] Loaded {sum(len(v) for v in self.adjacencies_extra.values()) // 2} extra strait/canal connections.")

    # ==========================================================================
    # 4. RASTER MAP COMPILATION & GIS TOPOLOGY (NUMPY / SCIPY)
    # ==========================================================================
    def process_raster_map(self, output_png_path: Path) -> Tuple[np.ndarray, int, int]:
        """
        Converts provinces.bmp into provinces_mask.png (Lossless RGB)
        where R = id & 0xFF, G = (id >> 8) & 0xFF, B = (id >> 16) & 0xFF.
        Returns the 2D province ID grid (height, width).
        """
        resolved = self.resolve_highest_priority_file("map/provinces.bmp")
        if not resolved:
            raise FileNotFoundError("Could not find map/provinces.bmp in any active layer!")

        bmp_path, layer = resolved
        print(f"[GIS] Processing raster map from [{layer.name}]: {bmp_path}")
        t0 = time.time()

        img = Image.open(bmp_path).convert("RGB")
        width, height = img.size
        img_np = np.array(img, dtype=np.uint8)

        # Pack 24-bit RGB into single uint32: (R << 16) | (G << 8) | B
        packed_rgb = (
            (img_np[:, :, 0].astype(np.uint32) << 16) |
            (img_np[:, :, 1].astype(np.uint32) << 8) |
            img_np[:, :, 2].astype(np.uint32)
        )

        # Build fast lookup array
        lut_keys = []
        lut_vals = []
        for (r, g, b), pid in self.rgb_to_id.items():
            key = (r << 16) | (g << 8) | b
            lut_keys.append(key)
            lut_vals.append(pid)

        lut_keys_arr = np.array(lut_keys, dtype=np.uint32)
        lut_vals_arr = np.array(lut_vals, dtype=np.uint32)

        sorter = np.argsort(lut_keys_arr)
        sorted_keys = lut_keys_arr[sorter]
        sorted_vals = lut_vals_arr[sorter]

        flat_packed = packed_rgb.ravel()
        indices = np.searchsorted(sorted_keys, flat_packed)
        indices = np.clip(indices, 0, len(sorted_keys) - 1)

        matched = (sorted_keys[indices] == flat_packed)
        id_grid_flat = np.zeros(flat_packed.shape, dtype=np.uint32)
        id_grid_flat[matched] = sorted_vals[indices[matched]]

        unmatched_count = int(np.count_nonzero(~matched))
        unmatched_unique_colors = []
        if unmatched_count > 0:
            unmatched_packed = np.unique(flat_packed[~matched])
            for up in unmatched_packed[:20]:
                r = int((up >> 16) & 0xFF)
                g = int((up >> 8) & 0xFF)
                b = int(up & 0xFF)
                unmatched_unique_colors.append([r, g, b])

        self.audit_report["unmatched_pixels_count"] = unmatched_count
        self.audit_report["unmatched_sample_colors"] = unmatched_unique_colors

        id_grid = id_grid_flat.reshape((height, width))

        # Save Lossless 24-bit PNG mask
        output_png_path.parent.mkdir(parents=True, exist_ok=True)
        out_r = (id_grid & 0xFF).astype(np.uint8)
        out_g = ((id_grid >> 8) & 0xFF).astype(np.uint8)
        out_b = ((id_grid >> 16) & 0xFF).astype(np.uint8)
        out_np = np.stack([out_r, out_g, out_b], axis=-1)
        out_img = Image.fromarray(out_np, mode="RGB")
        out_img.save(output_png_path, format="PNG", optimize=False)

        # Calculate SHA256 checksum
        mask_bytes = output_png_path.read_bytes()
        sha256_hash = hashlib.sha256(mask_bytes).hexdigest()
        self.audit_report["mask_sha256"] = sha256_hash
        self.audit_report["mask_resolution"] = {"width": width, "height": height}

        print(f"[GIS] Generated Lossless mask ({width}x{height}) in {time.time() - t0:.2f}s -> {output_png_path}")
        print(f"      SHA256: {sha256_hash}")
        if unmatched_count > 0:
            print(f"      [WARN] {unmatched_count} ghost pixels detected (mapped to ID 0)!")

        return id_grid, width, height

    def compute_raster_topology(
        self, id_grid: np.ndarray, width: int, height: int
    ) -> Dict[int, Dict[str, Any]]:
        """
        Computes geometric centroids, bounding boxes, areas, and 4-way adjacency
        lists for all provinces directly from the 2D pixel grid.
        """
        print("[GIS] Computing centroids, bounding boxes, and topological graph...")
        t0 = time.time()

        max_id = max(self.provinces_def.keys()) if self.provinces_def else int(np.max(id_grid))
        flat_grid = id_grid.ravel()

        # 1. Pixel area (counts)
        counts = np.bincount(flat_grid, minlength=max_id + 1)

        # 2. Centroids via weighted coordinates
        y_coords, x_coords = np.indices((height, width), dtype=np.float32)
        sum_x = np.bincount(flat_grid, weights=x_coords.ravel(), minlength=max_id + 1)
        sum_y = np.bincount(flat_grid, weights=y_coords.ravel(), minlength=max_id + 1)

        safe_counts = np.maximum(counts, 1)
        cx_arr = sum_x / safe_counts
        cy_arr = sum_y / safe_counts

        # 3. Bounding boxes
        bboxes: Dict[int, List[int]] = {}
        if SCIPY_AVAILABLE:
            slices = scipy.ndimage.find_objects(id_grid, max_label=max_id)
            for idx, slc in enumerate(slices, start=1):
                if slc is not None:
                    # slc is (slice(y_min, y_max), slice(x_min, x_max))
                    bboxes[idx] = [int(slc[1].start), int(slc[0].start), int(slc[1].stop), int(slc[0].stop)]
        else:
            # Fallback if scipy not present
            for pid in self.provinces_def.keys():
                bboxes[pid] = [0, 0, width, height]

        # 4. Adjacency Graph from Boundary Pixel Scanning
        # Horizontal neighbor pairs
        h_diff = (id_grid[:, :-1] != id_grid[:, 1:])
        p_left = id_grid[:, :-1][h_diff]
        p_right = id_grid[:, 1:][h_diff]

        # Vertical neighbor pairs
        v_diff = (id_grid[:-1, :] != id_grid[1:, :])
        p_top = id_grid[:-1, :][v_diff]
        p_bottom = id_grid[1:, :][v_diff]

        c_p1 = np.concatenate([p_left, p_top])
        c_p2 = np.concatenate([p_right, p_bottom])

        # Exclude border with background (ID 0)
        valid_mask = (c_p1 > 0) & (c_p2 > 0) & (c_p1 != c_p2)
        v_p1 = c_p1[valid_mask]
        v_p2 = c_p2[valid_mask]

        min_p = np.minimum(v_p1, v_p2)
        max_p = np.maximum(v_p1, v_p2)
        packed_edges = (min_p.astype(np.int64) << 32) | max_p.astype(np.int64)
        unique_edges = np.unique(packed_edges)

        adj_graph: Dict[int, Set[int]] = {pid: set() for pid in self.provinces_def.keys()}
        for edge in unique_edges:
            p1 = int(edge >> 32)
            p2 = int(edge & 0xFFFFFFFF)
            if p1 in adj_graph:
                adj_graph[p1].add(p2)
            if p2 in adj_graph:
                adj_graph[p2].add(p1)

        # Merge extra connections (straits, canals) from map/adjacencies.csv
        for p1, neighbors in self.adjacencies_extra.items():
            if p1 in adj_graph:
                for p2 in neighbors:
                    if p2 in adj_graph:
                        adj_graph[p1].add(p2)
                        adj_graph[p2].add(p1)

        # 5. Populate Province Metadata
        topology_result: Dict[int, Dict[str, Any]] = {}
        for pid in self.provinces_def.keys():
            area = int(counts[pid]) if pid < len(counts) else 0
            cx = float(round(cx_arr[pid], 2)) if pid < len(cx_arr) else 0.0
            cy = float(round(cy_arr[pid], 2)) if pid < len(cy_arr) else 0.0
            bbox = bboxes.get(pid, [int(cx), int(cy), int(cx), int(cy)])
            neighbors = sorted(adj_graph.get(pid, []))

            topology_result[pid] = {
                "centroid": [cx, cy],
                "bbox": bbox,
                "pixel_area": area,
                "neighbors": neighbors
            }

        print(f"[GIS] Topology built in {time.time() - t0:.2f}s ({len(unique_edges)} borders detected).")
        return topology_result

    # ==========================================================================
    # 5. STATES MERGING (LAYERED OVERRIDE BY STATE_ID)
    # ==========================================================================
    def merge_states(self) -> None:
        """
        Parses all history/states/*.txt files across layers.
        Priority: Submod (30) > TNO (20) > Vanilla (10).
        Overrides occur based on integer state_id!
        """
        print("[PIPELINE] Cascading state files (history/states/*.txt)...")
        self.states_db.clear()
        state_source_counts: Dict[str, int] = {}

        # Scan lowest to highest priority so higher overrides lower
        for layer in self.config.get_layers_lowest_first():
            states_dir = layer.get_subpath("history", "states")
            if not states_dir.exists() or not states_dir.is_dir():
                continue

            count = 0
            for fpath in states_dir.glob("*.txt"):
                if self.config.is_ignored(fpath.name):
                    continue
                state_obj = ClausewitzStateParser.parse_state_file(fpath, layer.name, self.loc_db)
                if state_obj:
                    self.states_db[state_obj.state_id] = state_obj
                    count += 1

            state_source_counts[layer.name] = count
            print(f"  -> Layer [{layer.name}]: Parsed {count} state files.")

        self.audit_report["state_source_counts"] = state_source_counts

        # Final ownership breakdown by layer
        layer_breakdown: Dict[str, int] = {}
        for s in self.states_db.values():
            layer_breakdown[s.source_layer] = layer_breakdown.get(s.source_layer, 0) + 1
        self.audit_report["final_states_by_layer"] = layer_breakdown

        print(f"[PIPELINE] Active states after override: {len(self.states_db)}")
        for l_name, num in sorted(layer_breakdown.items()):
            print(f"     Layer [{l_name}]: {num} active states in final game state.")

    # ==========================================================================
    # 6. COUNTRY METRICS & COLORS
    # ==========================================================================
    def load_country_colors(self) -> None:
        """Parses common/countries/colors.txt to extract country RGB palette."""
        print("[PIPELINE] Parsing country colors...")
        self.country_colors.clear()

        resolved = self.resolve_highest_priority_file("common/countries/colors.txt")
        if not resolved:
            return

        colors_file, layer = resolved
        content = read_clausewitz_text(colors_file)
        tokens = ClausewitzTokenizer.tokenize(content)
        parser = ClausewitzParser(tokens)
        parsed = parser.parse()

        for tag, data in parsed.items():
            if isinstance(data, dict):
                col_block = data.get("color")
                rgb_items = None
                if isinstance(col_block, list) and len(col_block) >= 3:
                    rgb_items = col_block
                elif isinstance(col_block, dict):
                    rgb_items = col_block.get("rgb", col_block.get("_items", []))

                if isinstance(rgb_items, list) and len(rgb_items) >= 3:
                    try:
                        r = float(rgb_items[0]) / 255.0
                        g = float(rgb_items[1]) / 255.0
                        b = float(rgb_items[2]) / 255.0
                        self.country_colors[tag.upper()] = [r, g, b, 1.0]
                    except (ValueError, TypeError):
                        pass

        print(f"[PIPELINE] Loaded {len(self.country_colors)} country colors.")

    def compile_countries(self) -> Dict[str, Dict[str, Any]]:
        """Compiles macro-state country records corresponding to Godot 4 CountryState."""
        print("[PIPELINE] Compiling starting countries state...")
        countries: Dict[str, Dict[str, Any]] = {}

        # 1. Aggregate state-level statistics per country tag
        tag_stats: Dict[str, Dict[str, Any]] = {}
        for s in self.states_db.values():
            owner = s.owner
            if not owner:
                continue
            if owner not in tag_stats:
                tag_stats[owner] = {
                    "factories_civ": 0,
                    "factories_mil": 0,
                    "dockyards": 0,
                    "total_ic": 0.0,
                    "population": 0,
                    "states_count": 0,
                    "provinces_count": 0
                }
            ts = tag_stats[owner]
            ts["factories_civ"] += s.industrial_complex
            ts["factories_mil"] += s.arms_factory
            ts["dockyards"] += s.dockyard
            ts["total_ic"] += s.calculated_ic
            ts["population"] += s.manpower
            ts["states_count"] += 1
            ts["provinces_count"] += len(s.provinces)

        # 2. Parse country politics from history/countries/
        country_politics: Dict[str, Dict[str, Any]] = {}
        for layer in self.config.get_layers_lowest_first():
            hist_c_dir = layer.get_subpath("history", "countries")
            if not hist_c_dir.exists() or not hist_c_dir.is_dir():
                continue

            for fpath in hist_c_dir.glob("*.txt"):
                basename = fpath.stem
                tag_match = re.match(r"^([A-Z0-9]{3})", basename)
                if not tag_match:
                    continue
                tag = tag_match.group(1).upper()
                try:
                    tree = parse_clausewitz_file(fpath)
                    pol = tree.get("set_politics", {})
                    ruling = "Authoritarian Socialism"
                    if isinstance(pol, dict):
                        ruling = str(pol.get("ruling_party", ruling))

                    capital = tree.get("capital", 0)
                    stab = float(tree.get("set_stability", 0.6))
                    war_sup = float(tree.get("set_war_support", 0.5))

                    country_politics[tag] = {
                        "capital_province_id": capital if isinstance(capital, int) else 0,
                        "ruling_ideology": ruling,
                        "stability": stab,
                        "war_support": war_sup
                    }
                except Exception:
                    pass

        # 3. Assemble unified CountryState dictionaries
        for tag, st in tag_stats.items():
            c_name = self.loc_db.get(tag, tag)
            pol = country_politics.get(tag, {})
            color = self.country_colors.get(tag, [0.4, 0.4, 0.4, 1.0])

            # Toolbox economic estimations
            gdp_approx = round(float(st["total_ic"]) * 1.8 + float(st["population"]) * 0.000035, 2)

            countries[tag] = {
                "country_tag": tag,
                "country_name": c_name,
                "leader_name": "Provisional Council",
                "leader_portrait_path": "res://icon.svg",
                "ruling_ideology": pol.get("ruling_ideology", "Nationalism"),
                "sub_ideology": pol.get("ruling_ideology", "Nationalism"),
                "country_color": color,
                "political_capital": 100.0,
                "legitimacy": float(round(pol.get("stability", 0.6) * 100.0, 1)),
                "radicalization": float(round((1.0 - pol.get("stability", 0.6)) * 40.0, 1)),
                "gdp_billions": max(1.0, gdp_approx),
                "civilian_factories": st["factories_civ"],
                "military_factories": st["factories_mil"],
                "dockyards": st["dockyards"],
                "total_manpower": st["population"],
                "capital_province_id": pol.get("capital_province_id", 0),
                "owned_states_count": st["states_count"],
                "owned_provinces_count": st["provinces_count"]
            }

        print(f"[PIPELINE] Successfully compiled {len(countries)} countries.")
        return countries

    # ==========================================================================
    # 7. MANIFEST, STARTING REGIONS & AUDIT
    # ==========================================================================
    def build_and_export_all(self) -> None:
        """Runs the entire compilation process and writes all output artifacts."""
        t_start = time.time()
        print("================================================================================")
        print(" TNO WORLD MAP AGGREGATOR & DATA COMPILER (GODOT 4)")
        print("================================================================================")

        out_mask_png = self.config.target_output_dir / "provinces_mask.png"
        out_manifest = self.config.target_output_dir / "map_manifest.json"
        out_starting_regions = self.config.target_output_dir / "starting_regions_state.json"
        out_starting_countries = self.config.target_output_dir / "starting_countries_state.json"
        out_audit_log = self.config.target_output_dir / "integrity_audit.json"

        # 1. Localizations & Definitions
        self.load_localizations()
        self.merge_definitions()
        self.parse_adjacencies_csv()

        # 2. Raster processing & Topology
        id_grid, width, height = self.process_raster_map(out_mask_png)
        topology = self.compute_raster_topology(id_grid, width, height)

        # 3. States & Countries
        self.merge_states()
        self.load_country_colors()
        countries_data = self.compile_countries()

        # 4. Link States to Provinces & Compute State Geometries
        prov_to_state: Dict[int, int] = {}
        for sid, s in self.states_db.items():
            for pid in s.provinces:
                prov_to_state[pid] = sid

        # Check for unassigned land provinces
        unassigned_land: List[int] = []
        for pid, pdef in self.provinces_def.items():
            if pdef["type"] == "land" and pid not in prov_to_state:
                unassigned_land.append(pid)

        self.audit_report["unassigned_land_provinces_count"] = len(unassigned_land)
        self.audit_report["unassigned_land_samples"] = unassigned_land[:30]

        # Compute state centroids (weighted center of mass of child provinces)
        state_manifest_dict: Dict[str, Any] = {}
        starting_regions_dict: Dict[str, Any] = {}

        for sid, s in sorted(self.states_db.items()):
            state_pids = s.provinces
            state_area = 0
            state_min_x, state_min_y = 999999, 999999
            state_max_x, state_max_y = -1, -1
            sum_scx, sum_scy = 0.0, 0.0

            for pid in state_pids:
                p_top = topology.get(pid)
                if p_top:
                    p_area = max(1, p_top["pixel_area"])
                    state_area += p_area
                    sum_scx += p_top["centroid"][0] * p_area
                    sum_scy += p_top["centroid"][1] * p_area
                    bbox = p_top["bbox"]
                    state_min_x = min(state_min_x, bbox[0])
                    state_min_y = min(state_min_y, bbox[1])
                    state_max_x = max(state_max_x, bbox[2])
                    state_max_y = max(state_max_y, bbox[3])

            st_cx = round(sum_scx / max(1, state_area), 2)
            st_cy = round(sum_scy / max(1, state_area), 2)
            st_bbox = [
                0 if state_min_x == 999999 else state_min_x,
                0 if state_min_y == 999999 else state_min_y,
                width if state_max_x == -1 else state_max_x,
                height if state_max_y == -1 else state_max_y
            ]

            state_manifest_dict[str(sid)] = {
                "id": sid,
                "name": s.localized_name,
                "owner": s.owner,
                "cores": s.cores,
                "claims": s.claims,
                "manpower": s.manpower,
                "industrial_capacity": s.calculated_ic,
                "infrastructure": s.infrastructure,
                "provinces": s.provinces,
                "centroid": [st_cx, st_cy],
                "bbox": st_bbox,
                "pixel_area": state_area,
                "resources": s.resources,
                "category": s.state_category,
                "victory_points": s.victory_points,
                "source_layer": s.source_layer
            }

            # Prepare Godot RegionData records for each province in this state
            primary_pid = state_pids[0] if state_pids else sid
            for pid in state_pids:
                pdef = self.provinces_def.get(pid, {})
                terrain = pdef.get("terrain", "plains")
                reg_record = s.to_region_data_dict(pid, terrain)
                starting_regions_dict[str(pid)] = reg_record

        # 5. Populate Provinces in Manifest
        provinces_manifest_dict: Dict[str, Any] = {}
        for pid, pdef in sorted(self.provinces_def.items()):
            p_top = topology.get(pid, {
                "centroid": [0.0, 0.0],
                "bbox": [0, 0, 0, 0],
                "pixel_area": 0,
                "neighbors": []
            })
            assigned_sid = prov_to_state.get(pid)
            provinces_manifest_dict[str(pid)] = {
                "id": pid,
                "rgb": pdef["rgb"],
                "state_id": assigned_sid,
                "type": pdef["type"],
                "is_coastal": pdef["is_coastal"],
                "terrain": pdef["terrain"],
                "continent": pdef["continent"],
                "centroid": p_top["centroid"],
                "bbox": p_top["bbox"],
                "pixel_area": p_top["pixel_area"],
                "neighbors": p_top["neighbors"]
            }

        # 6. Output JSON Manifest
        manifest_payload = {
            "metadata": {
                "version": "2.0.0",
                "engine": "Godot 4",
                "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "map_size": {"width": width, "height": height},
                "total_provinces": len(provinces_manifest_dict),
                "total_states": len(state_manifest_dict),
                "total_countries": len(countries_data),
                "max_province_id": max(self.provinces_def.keys()) if self.provinces_def else 0,
                "mask_sha256": self.audit_report.get("mask_sha256", "")
            },
            "states": state_manifest_dict,
            "provinces": provinces_manifest_dict
        }

        print(f"[EXPORT] Writing map manifest -> {out_manifest}")
        with open(out_manifest, "w", encoding="utf-8") as f:
            json.dump(manifest_payload, f, ensure_ascii=False, indent=2)

        print(f"[EXPORT] Writing starting regions -> {out_starting_regions}")
        with open(out_starting_regions, "w", encoding="utf-8") as f:
            json.dump(starting_regions_dict, f, ensure_ascii=False, indent=2)

        print(f"[EXPORT] Writing starting countries -> {out_starting_countries}")
        with open(out_starting_countries, "w", encoding="utf-8") as f:
            json.dump(countries_data, f, ensure_ascii=False, indent=2)

        # Mirror starting states/countries to config.data_export_dir as well
        self.config.data_export_dir.mkdir(parents=True, exist_ok=True)
        mirror_reg = self.config.data_export_dir / "starting_regions_state.json"
        mirror_cnt = self.config.data_export_dir / "starting_countries_state.json"
        with open(mirror_reg, "w", encoding="utf-8") as f:
            json.dump(starting_regions_dict, f, ensure_ascii=False, indent=2)
        with open(mirror_cnt, "w", encoding="utf-8") as f:
            json.dump(countries_data, f, ensure_ascii=False, indent=2)

        # 7. Write Audit Report
        self.audit_report["execution_time_seconds"] = round(time.time() - t_start, 2)
        self.audit_report["output_files"] = {
            "mask_png": str(out_mask_png),
            "map_manifest": str(out_manifest),
            "starting_regions": str(out_starting_regions),
            "starting_countries": str(out_starting_countries)
        }
        with open(out_audit_log, "w", encoding="utf-8") as f:
            json.dump(self.audit_report, f, ensure_ascii=False, indent=2)

        # 8. Display Console Audit Report
        self.print_audit_summary()

    def print_audit_summary(self) -> None:
        """Outputs rich integrity audit table and diagnosis to console."""
        print("\n" + "=" * 80)
        print("                     INTEGRITY AUDIT & VALIDATION REPORT")
        print("=" * 80)
        print(f"Mask Resolution:      {self.audit_report.get('mask_resolution', {}).get('width')} x {self.audit_report.get('mask_resolution', {}).get('height')}")
        print(f"Mask SHA-256 Checksum:{self.audit_report.get('mask_sha256')}")
        print(f"Total Execution Time: {self.audit_report.get('execution_time_seconds')} seconds\n")

        print("--- DEFINITIONS OVERRIDE STATS ---")
        for layer, cnt in self.audit_report.get("definitions_layer_counts", {}).items():
            print(f"  * {layer:<15}: {cnt:>6} definitions loaded/overridden")

        print("\n--- STATES OVERRIDE STATS ---")
        final_by_layer = self.audit_report.get("final_states_by_layer", {})
        for layer, cnt in self.audit_report.get("state_source_counts", {}).items():
            active_cnt = final_by_layer.get(layer, 0)
            print(f"  * {layer:<15}: {cnt:>6} states in files | {active_cnt:>6} in final state ({active_cnt/max(1, sum(final_by_layer.values()))*100:.1f}%)")

        print("\n--- GEOMETRIC & TOPOLOGICAL INTEGRITY ---")
        ghost_pixels = self.audit_report.get("unmatched_pixels_count", 0)
        if ghost_pixels == 0:
            print("  [PASS] Ghost Pixels: 0 (Every pixel strictly matches definition.csv)")
        else:
            print(f"  [WARN] Ghost Pixels: {ghost_pixels} unmatched pixels!")
            samples = self.audit_report.get("unmatched_sample_colors", [])
            print(f"         Sample colors (RGB): {samples}")

        unassigned = self.audit_report.get("unassigned_land_provinces_count", 0)
        if unassigned == 0:
            print("  [PASS] Unassigned Land: 0 (All land provinces mapped to states)")
        else:
            print(f"  [INFO] Unassigned Land Provinces: {unassigned} provinces (e.g. wastelands/islands)")
            samples = self.audit_report.get("unassigned_land_samples", [])
            print(f"         Sample Province IDs: {samples}")

        print("=" * 80 + "\n")


# ==============================================================================
# 8. COMMAND LINE ENTRYPOINT
# ==============================================================================
def main():
    parser = argparse.ArgumentParser(description="TNO World Map Aggregator & GIS Compiler for Godot 4")
    parser.add_argument("--vanilla", help="Path to HoI4 Vanilla directory")
    parser.add_argument("--mod", help="Path to TNO Mod directory")
    parser.add_argument("--submod", help="Path to Submod directory")
    parser.add_argument("--loc-mod", help="Path to Russian TNO Localisation directory")
    parser.add_argument("--loc-submod", help="Path to Russian Submod Localisation directory")
    parser.add_argument("--out", help="Target output directory for map_manifest & mask")
    parser.add_argument("--data-out", help="Target output directory for JSON data")
    args = parser.parse_args()

    cfg = PipelineConfig.create_default(
        vanilla_dir=args.vanilla,
        mod_dir=args.mod,
        submod_dir=args.submod,
        loc_mod_dir=args.loc_mod,
        loc_submod_dir=args.loc_submod,
        target_output_dir=args.out,
        data_export_dir=args.data_out
    )

    compiler = WorldMapCompiler(cfg)
    compiler.build_and_export_all()


if __name__ == "__main__":
    main()
