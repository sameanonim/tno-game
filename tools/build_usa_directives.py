#!/usr/bin/env python3
"""
Build and validate complete, canonical USA focus trees, manifest, and icons for Godot 4.
"""

from collections import deque
import json
import os
from pathlib import Path
import shutil

PROJECT_ROOT = Path(__file__).resolve().parent.parent
USA_DIR = PROJECT_ROOT / "data" / "countries" / "USA" / "directives"
TREES_DIR = USA_DIR / "trees"
ICONS_DIR = USA_DIR / "icons"
GOALS_DIR = PROJECT_ROOT / "assets" / "gfx" / "interface" / "goals"


def sanitize_dag(nodes: dict) -> dict:
    """Ensures no dangling prerequisites, no self-references, and valid DAG."""
    # 1. Clean dangling prerequisites
    for fid, node in nodes.items():
        valid_prereqs = [p for p in node.get("prerequisites", []) if p in nodes and p != fid]
        node["prerequisites"] = list(dict.fromkeys(valid_prereqs))
        cleaned_groups = []
        for g in node.get("prerequisites_groups", []):
            vg = [p for p in g if p in nodes and p != fid]
            if vg:
                cleaned_groups.append(list(dict.fromkeys(vg)))
        node["prerequisites_groups"] = cleaned_groups

    # 2. Mutually exclusive symmetrization
    for fid, node in nodes.items():
        node["mutually_exclusive"] = [m for m in node.get("mutually_exclusive", []) if m in nodes and m != fid]
        for excl in list(node["mutually_exclusive"]):
            if fid not in nodes[excl].get("mutually_exclusive", []):
                nodes[excl].setdefault("mutually_exclusive", []).append(fid)
        node["mutually_exclusive"] = list(dict.fromkeys(node["mutually_exclusive"]))

    # 3. Kahn's algorithm cycle check
    in_degree = {k: 0 for k in nodes}
    adj = {k: [] for k in nodes}
    for fid, node in nodes.items():
        for p in node.get("prerequisites", []):
            adj[p].append(fid)
            in_degree[fid] += 1

    queue = deque([k for k, d in in_degree.items() if d == 0])
    topo = []
    while queue:
        curr = queue.popleft()
        topo.append(curr)
        for nxt in adj[curr]:
            in_degree[nxt] -= 1
            if in_degree[nxt] == 0:
                queue.append(nxt)

    if len(topo) < len(nodes):
        unresolved = [k for k, d in in_degree.items() if d > 0]
        print(f"[WARN] Breaking cycles for {len(unresolved)} nodes")
        for bad_id in unresolved:
            nodes[bad_id]["prerequisites"] = []
            nodes[bad_id]["prerequisites_groups"] = []

    return nodes


def resolve_icon(node: dict, goals_dir: Path, icons_dir: Path) -> str:
    raw_icon = node.get("raw_icon", "")
    clean = raw_icon.removeprefix("GFX_")
    
    # Try finding in goals dir
    candidates = [
        f"{clean}.png",
        f"{raw_icon}.png",
        f"{clean.removeprefix('focus_')}.png",
        f"focus_{clean}.png"
    ]
    
    for c in candidates:
        src = goals_dir / c
        if src.exists():
            dst = icons_dir / f"{clean}.png"
            if not dst.exists():
                shutil.copy2(src, dst)
            return f"res://data/countries/USA/directives/icons/{clean}.png"

    # If already in icons dir
    if (icons_dir / f"{clean}.png").exists():
        return f"res://data/countries/USA/directives/icons/{clean}.png"

    return "res://icon.svg"


def main():
    print("=" * 70)
    print(" BUILDING CANONICAL USA FOCUS TREES AND MANIFEST")
    print("=" * 70)

    USA_DIR.mkdir(parents=True, exist_ok=True)
    TREES_DIR.mkdir(parents=True, exist_ok=True)
    ICONS_DIR.mkdir(parents=True, exist_ok=True)

    # 1. Load TNO_USA_shared (168 nodes)
    shared_file = TREES_DIR / "TNO_USA_shared.json"
    with open(shared_file, "r", encoding="utf-8") as f:
        shared_data = json.load(f)
    all_shared_nodes = shared_data["nodes"]

    # McCormack nodes (12 nodes)
    mccormack_root = "USA_mccormack_against_the_npp"
    mccormack_nodes = {}
    
    # Find all descendants of McCormack
    children_map = {}
    for nid, node in all_shared_nodes.items():
        for p in node.get("prerequisites", []):
            children_map.setdefault(p, []).append(nid)

    mc_queue = [mccormack_root]
    mc_seen = set()
    while mc_queue:
        curr = mc_queue.pop(0)
        if curr in mc_seen or curr not in all_shared_nodes:
            continue
        mc_seen.add(curr)
        mccormack_nodes[curr] = json.loads(json.dumps(all_shared_nodes[curr]))
        for ch in children_map.get(curr, []):
            mc_queue.append(ch)

    print(f"McCormack nodes identified: {len(mccormack_nodes)}")

    # Nixon 1962 Starting Tree: everything else in all_shared_nodes (excluding McCormack and JFK standalone branch)
    # Note: JFK nodes in TNO only exist if JFK survives or in alternate, but Nixon 1962 contains Nixon + SAW + Military
    jfk_root = "USA_the_jfk_presidency"
    jfk_seen = set()
    jfk_queue = [jfk_root]
    while jfk_queue:
        curr = jfk_queue.pop(0)
        if curr in jfk_seen or curr not in all_shared_nodes:
            continue
        jfk_seen.add(curr)
        for ch in children_map.get(curr, []):
            jfk_queue.append(ch)

    print(f"JFK nodes identified: {len(jfk_seen)}")

    nixon_nodes = {}
    for nid, node in all_shared_nodes.items():
        if nid not in mccormack_nodes and nid not in jfk_seen:
            nixon_nodes[nid] = json.loads(json.dumps(node))

    print(f"Nixon 1962 nodes: {len(nixon_nodes)}")

    if "USA_the_nixon_presidency" in nixon_nodes:
        nixon_nodes["USA_the_nixon_presidency"]["available_ast"] = {
            "operator": "AND",
            "conditions": [
                {"type": "tag", "tag": "USA"}
            ]
        }

    # In Nixon tree: ensure USA_wiretap_the_NPP completes with LOAD_FOCUS_TREE to McCormack
    if "USA_wiretap_the_NPP" in nixon_nodes:
        wt = nixon_nodes["USA_wiretap_the_NPP"]
        wt["completion_rewards"] = [
            {"opcode": "MOD_PC", "value": 25.0},
            {"opcode": "SET_FLAG", "flag": "USA_nixon_resigned", "value": True},
            {"opcode": "LOAD_FOCUS_TREE", "tree_id": "tree_USA_mccormack", "keep_completed": True},
            {"opcode": "FIRE_EVENT", "event_id": "nixon.10", "days": 1}
        ]

    # In Nixon tree: CRA passing/veto rewards
    if "USA_the_1962_civil_rights_act" in nixon_nodes:
        cra = nixon_nodes["USA_the_1962_civil_rights_act"]
        cra["completion_rewards"] = [
            {"opcode": "MOD_PC", "value": 50.0},
            {"opcode": "SET_FLAG", "flag": "USA_civil_rights_passed", "value": True},
            {"opcode": "CLR_FLAG", "flag": "USA_civil_rights_crisis"},
            {"opcode": "FIRE_EVENT", "event_id": "USA_sen_bill.101", "days": 1}
        ]

    if "USA_veto_the_civil_rights_act" in nixon_nodes:
        veto = nixon_nodes["USA_veto_the_civil_rights_act"]
        veto["completion_rewards"] = [
            {"opcode": "MOD_PC", "value": 30.0},
            {"opcode": "SET_FLAG", "flag": "USA_civil_rights_blocked", "value": True},
            {"opcode": "CLR_FLAG", "flag": "USA_anti_civil_rights_demonstrations"}
        ]

    # Ensure CRA mutually exclusive branches are directly selectable upon completing dilemma
    for cra_fid in ["USA_begin_integration", "USA_toe_the_middle_line", "USA_bend_to_the_segregationists"]:
        if cra_fid in nixon_nodes and "available_ast" in nixon_nodes[cra_fid]:
            conds = nixon_nodes[cra_fid]["available_ast"].get("conditions", [])
            conds = [c for c in conds if not (c.get("type") == "has_country_flag" and str(c.get("flag", "")).endswith("_flag"))]
            nixon_nodes[cra_fid]["available_ast"]["conditions"] = conds

    # Ensure icons
    for n in nixon_nodes.values():
        n["icon_path"] = resolve_icon(n, GOALS_DIR, ICONS_DIR)
    for n in mccormack_nodes.values():
        n["icon_path"] = resolve_icon(n, GOALS_DIR, ICONS_DIR)

    # Sanitize DAGs
    nixon_nodes = sanitize_dag(nixon_nodes)
    mccormack_nodes = sanitize_dag(mccormack_nodes)

    # In McCormack tree: passing of the torch prepares 1964 election
    if "USA_mccormack_passing_of_the_torch" in mccormack_nodes:
        pot = mccormack_nodes["USA_mccormack_passing_of_the_torch"]
        pot["completion_rewards"] = [
            {"opcode": "MOD_PC", "value": 50.0},
            {"opcode": "MOD_STABILITY", "value": 0.05},
            {"opcode": "SET_FLAG", "flag": "USA_1964_elections_ready", "value": True},
            {"opcode": "FIRE_EVENT", "event_id": "usa_election.1964", "days": 1}
        ]

    # Save tree_USA_1962.json and tree.json
    tree_1962_payload = {
        "tree_id": "tree_USA_1962",
        "title": "Администрация Никсона (1962)",
        "country_tag": "USA",
        "stage_category": "PROLOGUE",
        "is_starting_tree": True,
        "activation_ast": {
            "operator": "AND",
            "conditions": [
                {"type": "tag", "tag": "USA"},
                {"type": "not_has_country_flag", "flag": "USA_nixon_resigned"}
            ]
        },
        "total_directives": len(nixon_nodes),
        "nodes": nixon_nodes
    }

    with open(USA_DIR / "tree_USA_1962.json", "w", encoding="utf-8") as f:
        json.dump(tree_1962_payload, f, ensure_ascii=False, indent=2)

    with open(USA_DIR / "tree.json", "w", encoding="utf-8") as f:
        json.dump(tree_1962_payload, f, ensure_ascii=False, indent=2)

    print(f"Exported tree_USA_1962.json ({len(nixon_nodes)} directives)")

    # Save tree_USA_mccormack.json
    tree_mccormack_payload = {
        "tree_id": "tree_USA_mccormack",
        "title": "Администрация Маккормака (1963-1964)",
        "country_tag": "USA",
        "stage_category": "LEADERSHIP",
        "is_starting_tree": False,
        "activation_ast": {
            "operator": "OR",
            "conditions": [
                {"type": "has_country_flag", "flag": "USA_nixon_resigned"},
                {"type": "has_country_flag", "flag": "USA_mccormack_presidency"}
            ]
        },
        "total_directives": len(mccormack_nodes),
        "nodes": mccormack_nodes
    }

    with open(USA_DIR / "tree_USA_mccormack.json", "w", encoding="utf-8") as f:
        json.dump(tree_mccormack_payload, f, ensure_ascii=False, indent=2)

    print(f"Exported tree_USA_mccormack.json ({len(mccormack_nodes)} directives)")

    # 1964 Candidate trees
    candidates = [
        ("tree_USA_1964_LBJ", "TNO_USA_LBJ_shared.json", "Президентство Линдона Джонсона (1964, РДП)", "USA_president_lbj"),
        ("tree_USA_1964_WFB", "TNO_USA_WFB_shared.json", "Президентство Уоллеса Беннетта (1964, РДП)", "USA_president_bennett"),
        ("tree_USA_1964_WAL", "TNO_USA_WAL_shared.json", "Президентство Джорджа Уоллеса (1964, НФП)", "USA_president_wallace"),
        ("tree_USA_1964_MCS", "TNO_USA_MCS_shared.json", "Президентство Маргарет Чейз Смит (1964, НФП)", "USA_president_mcs"),
        ("tree_USA_1964_RFK", "TNO_USA_RFK_shared.json", "Президентство Роберта Кеннеди (1964, НФП)", "USA_president_rfk"),
    ]

    manifest_trees = [
        {
            "tree_id": "tree_USA_1962",
            "title": "Администрация Никсона (1962)",
            "stage_category": "PROLOGUE",
            "is_starting_tree": True,
            "total_directives": len(nixon_nodes),
            "activation_ast": tree_1962_payload["activation_ast"],
            "path": "res://data/countries/USA/directives/tree_USA_1962.json",
            "file_path": "res://data/countries/USA/directives/tree_USA_1962.json"
        },
        {
            "tree_id": "tree_USA_mccormack",
            "title": "Администрация Маккормака (1963-1964)",
            "stage_category": "LEADERSHIP",
            "is_starting_tree": False,
            "total_directives": len(mccormack_nodes),
            "activation_ast": tree_mccormack_payload["activation_ast"],
            "path": "res://data/countries/USA/directives/tree_USA_mccormack.json",
            "file_path": "res://data/countries/USA/directives/tree_USA_mccormack.json"
        }
    ]

    trees_index = [
        {
            "tree_id": "tree_USA_1962",
            "stage_category": "PROLOGUE",
            "is_starting_tree": True,
            "total_directives": len(nixon_nodes),
            "path": "res://data/countries/USA/directives/tree_USA_1962.json"
        },
        {
            "tree_id": "tree_USA_mccormack",
            "stage_category": "LEADERSHIP",
            "is_starting_tree": False,
            "total_directives": len(mccormack_nodes),
            "path": "res://data/countries/USA/directives/tree_USA_mccormack.json"
        }
    ]

    for tid, src_filename, title, pres_flag in candidates:
        src_path = TREES_DIR / src_filename
        if not src_path.exists():
            print(f"[WARN] Candidate tree source not found: {src_path}")
            continue

        with open(src_path, "r", encoding="utf-8") as f:
            cdata = json.load(f)

        cnodes = sanitize_dag(cdata.get("nodes", {}))
        for n in cnodes.values():
            n["icon_path"] = resolve_icon(n, GOALS_DIR, ICONS_DIR)

        cpayload = {
            "tree_id": tid,
            "title": title,
            "country_tag": "USA",
            "stage_category": "LEADERSHIP",
            "is_starting_tree": False,
            "activation_ast": {
                "operator": "AND",
                "conditions": [
                    {"type": "tag", "tag": "USA"},
                    {"type": "has_country_flag", "flag": pres_flag}
                ]
            },
            "total_directives": len(cnodes),
            "nodes": cnodes
        }

        with open(USA_DIR / f"{tid}.json", "w", encoding="utf-8") as f:
            json.dump(cpayload, f, ensure_ascii=False, indent=2)

        manifest_trees.append({
            "tree_id": tid,
            "title": title,
            "stage_category": "LEADERSHIP",
            "is_starting_tree": False,
            "total_directives": len(cnodes),
            "activation_ast": cpayload["activation_ast"],
            "path": f"res://data/countries/USA/directives/{tid}.json",
            "file_path": f"res://data/countries/USA/directives/{tid}.json"
        })

        trees_index.append({
            "tree_id": tid,
            "stage_category": "LEADERSHIP",
            "is_starting_tree": False,
            "total_directives": len(cnodes),
            "path": f"res://data/countries/USA/directives/{tid}.json"
        })

        print(f"Exported {tid}.json ({len(cnodes)} directives)")

    manifest_payload = {
        "country_tag": "USA",
        "starting_tree_id": "tree_USA_1962",
        "total_trees": len(manifest_trees),
        "trees": manifest_trees,
        "transitions": [
            {
                "source_tree": "tree_USA_1962",
                "target_tree": "tree_USA_mccormack",
                "trigger_type": "focus_completion",
                "trigger_id": "USA_wiretap_the_NPP",
                "keep_completed": True,
                "condition": {}
            },
            {
                "source_tree": "tree_USA_1962",
                "target_tree": "tree_USA_mccormack",
                "trigger_type": "event",
                "trigger_id": "nixon.10",
                "keep_completed": True,
                "condition": {}
            },
            {
                "source_tree": "tree_USA_mccormack",
                "target_tree": "tree_USA_1964_LBJ",
                "trigger_type": "event",
                "trigger_id": "usa_election.1964_lbj",
                "keep_completed": True,
                "condition": {"type": "has_country_flag", "flag": "USA_president_lbj"}
            },
            {
                "source_tree": "tree_USA_mccormack",
                "target_tree": "tree_USA_1964_WFB",
                "trigger_type": "event",
                "trigger_id": "usa_election.1964_bennett",
                "keep_completed": True,
                "condition": {"type": "has_country_flag", "flag": "USA_president_bennett"}
            },
            {
                "source_tree": "tree_USA_mccormack",
                "target_tree": "tree_USA_1964_WAL",
                "trigger_type": "event",
                "trigger_id": "usa_election.1964_wallace",
                "keep_completed": True,
                "condition": {"type": "has_country_flag", "flag": "USA_president_wallace"}
            },
            {
                "source_tree": "tree_USA_mccormack",
                "target_tree": "tree_USA_1964_MCS",
                "trigger_type": "event",
                "trigger_id": "usa_election.1964_mcs",
                "keep_completed": True,
                "condition": {"type": "has_country_flag", "flag": "USA_president_mcs"}
            },
            {
                "source_tree": "tree_USA_mccormack",
                "target_tree": "tree_USA_1964_RFK",
                "trigger_type": "event",
                "trigger_id": "usa_election.1964_rfk",
                "keep_completed": True,
                "condition": {"type": "has_country_flag", "flag": "USA_president_rfk"}
            }
        ]
    }

    with open(USA_DIR / "trees_manifest.json", "w", encoding="utf-8") as f:
        json.dump(manifest_payload, f, ensure_ascii=False, indent=2)

    with open(USA_DIR / "trees_index.json", "w", encoding="utf-8") as f:
        json.dump(trees_index, f, ensure_ascii=False, indent=2)

    print(f"trees_manifest.json and trees_index.json saved with {len(manifest_trees)} stages and {len(manifest_payload['transitions'])} transitions.")


if __name__ == "__main__":
    main()
