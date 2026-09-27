"""
National Focus / Directive Trees Extractor for TNO to Godot 4.
Parses common/national_focus/*.txt into structured tree graphs with layout coordinates.
"""

import glob
import json
import os
import sys
import time
from typing import Any, Dict, List, Optional

from .clausewitz import parse_clausewitz_file


def parse_focus_node(raw_focus: Dict[str, Any], loc_dict: Optional[Dict[str, str]] = None) -> Optional[Dict[str, Any]]:
    """
    Parses a single focus node inside a focus_tree.
    """
    if not isinstance(raw_focus, dict):
        return None

    focus_id = raw_focus.get("id")
    if not focus_id:
        return None

    icon = raw_focus.get("icon", "")
    cost = raw_focus.get("cost", 10)
    x = raw_focus.get("x", 0)
    y = raw_focus.get("y", 0)
    relative_position_id = raw_focus.get("relative_position_id")

    # Prerequisites can be list of dicts: prerequisite = { focus = A focus = B }
    raw_prereqs = raw_focus.get("prerequisite", [])
    if isinstance(raw_prereqs, dict):
        raw_prereqs = [raw_prereqs]

    prerequisites = []
    for pr in raw_prereqs:
        if isinstance(pr, dict):
            f_val = pr.get("focus")
            if isinstance(f_val, list):
                prerequisites.append(f_val)
            elif isinstance(f_val, str):
                prerequisites.append([f_val])

    # Mutually exclusive: mutually_exclusive = { focus = X focus = Y }
    raw_mutex = raw_focus.get("mutually_exclusive", [])
    if isinstance(raw_mutex, dict):
        raw_mutex = [raw_mutex]

    mutually_exclusive = []
    for m in raw_mutex:
        if isinstance(m, dict):
            f_val = m.get("focus")
            if isinstance(f_val, list):
                mutually_exclusive.extend(f_val)
            elif isinstance(f_val, str):
                mutually_exclusive.append(f_val)

    available = raw_focus.get("available", {})
    bypass = raw_focus.get("bypass", {})
    completion_reward = raw_focus.get("completion_reward", {})
    ai_will_do = raw_focus.get("ai_will_do", {})

    # Localized text
    name_text = ""
    desc_text = ""
    if loc_dict:
        name_text = loc_dict.get(str(focus_id), "")
        desc_text = loc_dict.get(f"{focus_id}_desc", "")

    return {
        "id": str(focus_id),
        "name_text": name_text,
        "desc_text": desc_text,
        "icon": str(icon),
        "cost": cost,
        "x": x,
        "y": y,
        "relative_position_id": relative_position_id,
        "prerequisites": prerequisites,
        "mutually_exclusive": mutually_exclusive,
        "available": available,
        "bypass": bypass,
        "completion_reward": completion_reward,
        "ai_will_do": ai_will_do
    }


def parse_focus_tree(tree_data: Dict[str, Any], loc_dict: Optional[Dict[str, str]] = None) -> Optional[Dict[str, Any]]:
    """
    Parses a full focus_tree block.
    """
    if not isinstance(tree_data, dict):
        return None

    tree_id = tree_data.get("id")
    if not tree_id:
        return None

    country_trigger = tree_data.get("country", {})
    default = bool(tree_data.get("default", False))

    raw_focuses = tree_data.get("focus", [])
    if isinstance(raw_focuses, dict):
        raw_focuses = [raw_focuses]

    focus_nodes = {}
    for f in raw_focuses:
        node = parse_focus_node(f, loc_dict)
        if node:
            focus_nodes[node["id"]] = node

    # Compute absolute positions for nodes with relative_position_id
    for fid, node in focus_nodes.items():
        rel_id = node.get("relative_position_id")
        if rel_id and rel_id in focus_nodes:
            parent = focus_nodes[rel_id]
            node["abs_x"] = node["x"] + parent.get("abs_x", parent["x"])
            node["abs_y"] = node["y"] + parent.get("abs_y", parent["y"])
        else:
            node["abs_x"] = node["x"]
            node["abs_y"] = node["y"]

    return {
        "id": str(tree_id),
        "default": default,
        "country": country_trigger,
        "total_focuses": len(focus_nodes),
        "focuses": focus_nodes
    }


def extract_focus_trees(
    tno_root: str,
    output_dir: str,
    loc_dict: Optional[Dict[str, str]] = None
) -> Dict[str, Dict[str, Any]]:
    """
    Extracts all focus trees from common/national_focus/*.txt into focus_trees.json.
    """
    os.makedirs(output_dir, exist_ok=True)
    t0 = time.time()
    focus_dir = os.path.join(tno_root, "common", "national_focus")

    print(f"[FOCUS] Scanning national focus directory: {focus_dir}")
    focus_files = glob.glob(os.path.join(focus_dir, "*.txt"))
    print(f"[FOCUS] Found {len(focus_files)} focus tree files")

    all_trees: Dict[str, Dict[str, Any]] = {}
    total_nodes = 0

    for fpath in focus_files:
        try:
            parsed = parse_clausewitz_file(fpath)
            raw_tree = parsed.get("focus_tree")
            if raw_tree:
                if isinstance(raw_tree, dict):
                    raw_tree = [raw_tree]
                for tree_item in raw_tree:
                    tree = parse_focus_tree(tree_item, loc_dict)
                    if tree:
                        all_trees[tree["id"]] = tree
                        total_nodes += tree["total_focuses"]
        except Exception as err:
            print(f"[FOCUS] [WARN] Failed to parse {fpath}: {err}", file=sys.stderr)

    out_path = os.path.join(output_dir, "focus_trees.json")
    print(f"[FOCUS] Exporting {len(all_trees)} focus trees ({total_nodes} focuses) to: {out_path}")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(all_trees, f, ensure_ascii=False, indent=2)

    elapsed = time.time() - t0
    print(f"[FOCUS] Done in {elapsed:.2f}s ({len(all_trees)} trees, {total_nodes} nodes)")
    return all_trees
