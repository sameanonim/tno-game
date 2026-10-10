"""
National Focus / Directive Trees Extractor for TNO to Godot 4.
Parses common/national_focus/*.txt into structured tree graphs with layout coordinates.
"""

import glob
import json
import os
import sys
import time
from typing import Any, Dict, List, Optional, Set, Tuple

from .clausewitz import parse_clausewitz_file


def parse_focus_node(raw_focus: Dict[str, Any], loc_dict: Optional[Dict[str, str]] = None) -> Optional[Dict[str, Any]]:
    """
    Parses a single focus node inside a focus_tree or shared_focus block.
    """
    if not isinstance(raw_focus, dict):
        return None

    focus_id = raw_focus.get("id")
    if not focus_id or not isinstance(focus_id, str):
        return None

    icon = str(raw_focus.get("icon", ""))
    cost = raw_focus.get("cost", 10)
    try:
        cost = float(cost)
    except (ValueError, TypeError):
        cost = 10.0

    try:
        x = int(raw_focus.get("x", 0))
        y = int(raw_focus.get("y", 0))
    except (ValueError, TypeError):
        x, y = 0, 0

    relative_position_id = raw_focus.get("relative_position_id")
    if relative_position_id and not isinstance(relative_position_id, str):
        relative_position_id = str(relative_position_id)

    # Prerequisites: outer list = AND, inner list = OR
    raw_prereqs = raw_focus.get("prerequisite", [])
    if isinstance(raw_prereqs, dict):
        raw_prereqs = [raw_prereqs]

    prerequisites = []
    for pr in raw_prereqs:
        if isinstance(pr, dict):
            f_val = pr.get("focus")
            if isinstance(f_val, list):
                group = [str(item) for item in f_val if isinstance(item, (str, int))]
                if group:
                    prerequisites.append(group)
            elif isinstance(f_val, (str, int)):
                prerequisites.append([str(f_val)])

    # Mutually exclusive
    raw_mutex = raw_focus.get("mutually_exclusive", [])
    if isinstance(raw_mutex, dict):
        raw_mutex = [raw_mutex]

    mutually_exclusive = []
    for m in raw_mutex:
        if isinstance(m, dict):
            f_val = m.get("focus")
            if isinstance(f_val, list):
                for item in f_val:
                    if isinstance(item, (str, int)):
                        mutually_exclusive.append(str(item))
            elif isinstance(f_val, (str, int)):
                mutually_exclusive.append(str(f_val))

    available = raw_focus.get("available", {})
    bypass = raw_focus.get("bypass", {})
    allow_branch = raw_focus.get("allow_branch", {})
    completion_reward = raw_focus.get("completion_reward", {})
    ai_will_do = raw_focus.get("ai_will_do", {})
    custom_tooltip = raw_focus.get("custom_effect_tooltip", "")

    raw_cii = raw_focus.get("cancel_if_invalid", True)
    if isinstance(raw_cii, str):
        cancel_if_invalid = raw_cii.lower() not in ("no", "false")
    else:
        cancel_if_invalid = bool(raw_cii)

    # Localized text
    text_key = str(raw_focus.get("text", focus_id))
    name_text = loc_dict.get(text_key, text_key) if loc_dict else text_key
    desc_key = f"{focus_id}_desc"
    desc_text = loc_dict.get(desc_key, "") if loc_dict else ""

    return {
        "id": str(focus_id),
        "text_id": text_key,
        "name_text": name_text,
        "desc_id": desc_key,
        "desc_text": desc_text,
        "icon": icon,
        "icon_path": icon,
        "cost": cost,
        "x": x,
        "y": y,
        "raw_grid_coord": [x, y],
        "grid_coord": [x, y],
        "coordinates_resolved": False,
        "relative_position_id": relative_position_id,
        "prerequisites": prerequisites,
        "mutually_exclusive": mutually_exclusive,
        "available": available,
        "bypass": bypass,
        "allow_branch": allow_branch,
        "allow_branch_ast": allow_branch if isinstance(allow_branch, dict) else {},
        "cancel_if_invalid": cancel_if_invalid,
        "custom_tooltip_id": str(custom_tooltip) if custom_tooltip else "",
        "completion_reward": completion_reward,
        "ai_will_do": ai_will_do
    }


def parse_focus_tree(
    tree_data: Dict[str, Any],
    shared_pool: Dict[str, Dict[str, Any]],
    children_map: Dict[str, List[str]],
    loc_dict: Optional[Dict[str, str]] = None
) -> Optional[Dict[str, Any]]:
    """
    Parses a full focus_tree block, resolving shared focuses and relative coordinates.
    """
    if not isinstance(tree_data, dict):
        return None

    tree_id = tree_data.get("id")
    if not tree_id:
        return None

    country_trigger = tree_data.get("country", {})
    default = bool(tree_data.get("default", False))

    tree_nodes: Dict[str, Dict[str, Any]] = {}

    # 1. Direct focuses
    raw_focuses = tree_data.get("focus", [])
    if isinstance(raw_focuses, dict):
        raw_focuses = [raw_focuses]
    for f in raw_focuses:
        node = parse_focus_node(f, loc_dict)
        if node:
            tree_nodes[node["id"]] = node

    # 2. Roots of shared focuses
    raw_shared = tree_data.get("shared_focus", [])
    if not isinstance(raw_shared, list):
        raw_shared = [raw_shared]

    roots = []
    for r in raw_shared:
        if isinstance(r, str):
            roots.append(r)
        elif isinstance(r, dict):
            s_id = r.get("id")
            if s_id and isinstance(s_id, str):
                roots.append(s_id)

    # 3. BFS traversal starting from direct nodes and shared roots
    queue = list(tree_nodes.keys())
    for r in roots:
        if r in shared_pool and r not in tree_nodes:
            tree_nodes[r] = dict(shared_pool[r])
            queue.append(r)

    seen = set(tree_nodes.keys())
    while queue:
        curr = queue.pop(0)
        for child_id in children_map.get(curr, []):
            if child_id not in seen and child_id in shared_pool:
                seen.add(child_id)
                tree_nodes[child_id] = dict(shared_pool[child_id])
                queue.append(child_id)

    # 4. Resolve relative positions into absolute coordinates
    memo_pos: Dict[str, Tuple[int, int]] = {}

    def resolve_pos(fid: str, visited: Optional[Set[str]] = None) -> Tuple[int, int]:
        if fid in memo_pos:
            return memo_pos[fid]
        if visited is None:
            visited = set()
        if fid in visited or fid not in tree_nodes:
            n = tree_nodes.get(fid, {})
            return int(n.get("x", 0)), int(n.get("y", 0))
        visited.add(fid)
        n = tree_nodes[fid]
        rx = int(n.get("x", 0))
        ry = int(n.get("y", 0))
        parent_id = n.get("relative_position_id")
        if parent_id and parent_id in tree_nodes:
            px, py = resolve_pos(parent_id, visited)
            final_pos = (px + rx, py + ry)
        else:
            final_pos = (rx, ry)
        memo_pos[fid] = final_pos
        return final_pos

    for fid, node in tree_nodes.items():
        ax, ay = resolve_pos(fid)
        node["abs_x"] = ax
        node["abs_y"] = ay
        node["grid_coord"] = [ax, ay]
        node["raw_grid_coord"] = [int(node.get("x", 0)), int(node.get("y", 0))]
        node["coordinates_resolved"] = True

    # 5. Symmetrize mutually exclusive links
    for fid, node in tree_nodes.items():
        for mex in node.get("mutually_exclusive", []):
            if mex in tree_nodes:
                if fid not in tree_nodes[mex].get("mutually_exclusive", []):
                    tree_nodes[mex].setdefault("mutually_exclusive", []).append(fid)

    return {
        "id": str(tree_id),
        "tree_id": str(tree_id),
        "default": default,
        "country": country_trigger,
        "total_focuses": len(tree_nodes),
        "focuses": tree_nodes,
        "nodes": tree_nodes
    }


def extract_focus_trees(
    tno_root: str,
    output_dir: str,
    loc_dict: Optional[Dict[str, str]] = None
) -> Dict[str, Dict[str, Any]]:
    """
    Extracts all focus trees from common/national_focus/*.txt into focus_trees.json,
    fully indexing and resolving all shared_focus branches.
    """
    os.makedirs(output_dir, exist_ok=True)
    t0 = time.time()
    focus_dir = os.path.join(tno_root, "common", "national_focus")

    print(f"[FOCUS] Scanning national focus directory: {focus_dir}")
    focus_files = glob.glob(os.path.join(focus_dir, "*.txt"))
    print(f"[FOCUS] Found {len(focus_files)} focus tree files")

    # Pass 1: Parse and index all shared_focus blocks
    shared_pool: Dict[str, Dict[str, Any]] = {}
    children_map: Dict[str, List[str]] = {}
    parsed_files: List[Tuple[str, Dict[str, Any]]] = []

    for fpath in focus_files:
        try:
            parsed = parse_clausewitz_file(fpath)
            parsed_files.append((fpath, parsed))
            sf_list = parsed.get("shared_focus", [])
            if isinstance(sf_list, dict):
                sf_list = [sf_list]
            for sf in sf_list:
                if isinstance(sf, dict):
                    node = parse_focus_node(sf, loc_dict)
                    if node:
                        fid = node["id"]
                        shared_pool[fid] = node

                        # Index prerequisites -> child
                        for group in node.get("prerequisites", []):
                            for p in group:
                                children_map.setdefault(p, []).append(fid)
                        # Index relative_position_id -> child
                        rel = node.get("relative_position_id")
                        if rel:
                            children_map.setdefault(rel, []).append(fid)
        except Exception as err:
            print(f"[FOCUS] [WARN] Failed to parse {fpath}: {err}", file=sys.stderr)

    print(f"[FOCUS] Indexed {len(shared_pool)} shared_focus definitions across VFS")

    # Pass 2: Extract each focus_tree and cascade its shared focuses
    all_trees: Dict[str, Dict[str, Any]] = {}
    total_nodes = 0

    for fpath, parsed in parsed_files:
        raw_tree = parsed.get("focus_tree")
        if raw_tree:
            if isinstance(raw_tree, dict):
                raw_tree = [raw_tree]
            for tree_item in raw_tree:
                tree = parse_focus_tree(tree_item, shared_pool, children_map, loc_dict)
                if tree and tree["total_focuses"] > 0:
                    all_trees[tree["id"]] = tree
                    total_nodes += tree["total_focuses"]

    out_path = os.path.join(output_dir, "focus_trees.json")
    print(f"[FOCUS] Exporting {len(all_trees)} focus trees ({total_nodes} focuses) to: {out_path}")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(all_trees, f, ensure_ascii=False, indent=2)

    elapsed = time.time() - t0
    print(f"[FOCUS] Done in {elapsed:.2f}s ({len(all_trees)} trees, {total_nodes} nodes)")
    return all_trees
