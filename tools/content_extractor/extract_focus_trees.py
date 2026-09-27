#!/usr/bin/env python3
"""
Focus Trees & Directives Graph Extractor for TNO (Godot 4).
===========================================================
Parses national focus trees across mod layers, converts days to turns,
resolves relative coordinates, validates DAG acyclicity,
translates completion rewards using opcode patterns, converts goal icons to PNG,
and exports everything into 'data/extracted/directives_trees.json'.
"""

import json
import os
import re
from typing import Any, Dict, List, Optional, Set, Tuple

from .content_merger import LayeredContentManager, parse_clausewitz_file
from .asset_converter import AssetConverter


class FocusTreesExtractor:
    """Extracts, verifies, and transforms HoI4 focus trees into Godot DirectiveResources."""

    def __init__(self, content_mgr: LayeredContentManager, asset_conv: AssetConverter, patterns_file: str):
        self.content_mgr = content_mgr
        self.asset_conv = asset_conv
        self.patterns_file = patterns_file
        self.effect_opcodes: Dict[str, str] = {}
        self._load_patterns()

        # Shared focuses pool: {shared_focus_id: parsed_focus_dict}
        self.shared_focuses: Dict[str, Dict[str, Any]] = {}
        # Tag -> Trees: {tag: {tree_id: list_of_directives}}
        self.directives_by_tag: Dict[str, Dict[str, Any]] = {}

    def _load_patterns(self) -> None:
        """Loads opcode translation mapping from patterns_registry.json."""
        default_opcodes = {
            "add_political_power": "MOD_PC",
            "add_stability": "MOD_STABILITY",
            "add_war_support": "MOD_WAR_SUPPORT",
            "set_country_flag": "SET_FLAG",
            "clr_country_flag": "CLR_FLAG",
            "country_event": "FIRE_EVENT",
            "news_event": "FIRE_NEWS",
            "add_manpower": "MOD_MANPOWER",
            "add_equipment_to_stockpile": "MOD_STOCKPILE",
            "transfer_state": "TRANSFER_STATE",
            "set_rule": "SET_RULE"
        }
        if os.path.exists(self.patterns_file):
            try:
                with open(self.patterns_file, "r", encoding="utf-8") as f:
                    reg = json.load(f)
                    self.effect_opcodes = reg.get("opcodes", {}).get("effects", default_opcodes)
            except Exception as e:
                print(f"[WARN] Failed loading patterns registry: {e}")
                self.effect_opcodes = default_opcodes
        else:
            self.effect_opcodes = default_opcodes

    def run(self, out_json_path: str) -> Dict[str, Any]:
        print("=" * 70)
        print(">>> [EXTRACTOR] FOCUS TREES & DIRECTIVES PIPELINE STARTING")
        print("=" * 70)

        # 1. First pass: Gather all shared_focus items across all layers
        self._scan_shared_focuses()

        # 2. Second pass: Parse focus trees
        self._scan_focus_trees()

        # 3. Export to JSON
        os.makedirs(os.path.dirname(os.path.abspath(out_json_path)), exist_ok=True)
        export_payload = {
            "meta": {
                "version": "1.0.0",
                "generator": "TNO Directives Graph Pipeline",
                "total_tags": len(self.directives_by_tag),
                "export_time": "2026-09-21"
            },
            "trees_by_tag": self.directives_by_tag
        }

        with open(out_json_path, "w", encoding="utf-8") as f:
            json.dump(export_payload, f, ensure_ascii=False, indent=2)

        print(f"[EXTRACTOR] Directives trees saved successfully -> {out_json_path}")
        print(f"            Total national graphs exported: {len(self.directives_by_tag)}")
        return export_payload

    def _scan_shared_focuses(self) -> None:
        """Finds all shared_focus definitions in common/national_focus/ across layers."""
        print("[EXTRACTOR] Indexing shared_focus blocks across layers...")
        focus_files = self.content_mgr.get_merged_files("common/national_focus", pattern="*.txt")
        count = 0

        for rel_p, abs_p in focus_files.items():
            try:
                data = parse_clausewitz_file(abs_p)
                s_focuses = data.get("shared_focus", [])
                if isinstance(s_focuses, dict):
                    s_focuses = [s_focuses]
                elif not isinstance(s_focuses, list):
                    s_focuses = []

                for sf in s_focuses:
                    if isinstance(sf, dict) and "id" in sf:
                        self.shared_focuses[sf["id"]] = sf
                        count += 1
            except Exception as e:
                print(f"[WARN] Error scanning shared focuses in {rel_p}: {e}")

        print(f"[EXTRACTOR] Indexed {count} shared focus definitions.")

    def _scan_focus_trees(self) -> None:
        """Parses all focus_tree blocks in common/national_focus/ across layers."""
        print("[EXTRACTOR] Parsing national focus trees across layers...")
        focus_files = self.content_mgr.get_merged_files("common/national_focus", pattern="*.txt")

        for rel_p, abs_p in focus_files.items():
            try:
                data = parse_clausewitz_file(abs_p)
                trees = data.get("focus_tree", [])
                if isinstance(trees, dict):
                    trees = [trees]
                elif not isinstance(trees, list):
                    trees = []

                for tree in trees:
                    if isinstance(tree, dict):
                        self._process_focus_tree(tree, rel_p)
            except Exception as e:
                print(f"[WARN] Error parsing focus tree file {rel_p}: {e}")

    def _process_focus_tree(self, tree_data: Dict[str, Any], file_path: str) -> None:
        tree_id = tree_data.get("id", "")
        country_block = tree_data.get("country", {})

        # Determine target country TAG
        tag = self._determine_tag_for_tree(tree_id, country_block, file_path)
        if not tag:
            return

        # Collect focuses (both direct focus and shared_focus references)
        direct_focuses = tree_data.get("focus", [])
        if isinstance(direct_focuses, dict):
            direct_focuses = [direct_focuses]
        elif not isinstance(direct_focuses, list):
            direct_focuses = []

        shared_refs = tree_data.get("shared_focus", [])
        if isinstance(shared_refs, str):
            shared_refs = [shared_refs]
        elif not isinstance(shared_refs, list):
            shared_refs = []

        all_raw_focuses: List[Dict[str, Any]] = []
        all_raw_focuses.extend(direct_focuses)

        for s_ref in shared_refs:
            if isinstance(s_ref, str) and s_ref in self.shared_focuses:
                all_raw_focuses.append(self.shared_focuses[s_ref])

        if not all_raw_focuses:
            return

        # Transform into Directive nodes
        directives_list: List[Dict[str, Any]] = []
        directives_by_id: Dict[str, Dict[str, Any]] = {}

        for rf in all_raw_focuses:
            if not isinstance(rf, dict) or "id" not in rf:
                continue
            directive = self._transform_focus_to_directive(rf)
            directives_list.append(directive)
            directives_by_id[directive["directive_id"]] = directive

        # Resolve relative positions (relative_position_id)
        self._resolve_relative_coordinates(directives_by_id)

        # Validate DAG and break cycles if any
        self._validate_and_sanitize_dag(directives_by_id)

        if tag not in self.directives_by_tag:
            self.directives_by_tag[tag] = {
                "country_tag": tag,
                "primary_tree_id": tree_id,
                "trees": {}
            }

        self.directives_by_tag[tag]["trees"][tree_id] = {
            "tree_id": tree_id,
            "directives_count": len(directives_list),
            "directives": list(directives_by_id.values())
        }

    def _determine_tag_for_tree(self, tree_id: str, country_block: Any, file_path: str) -> Optional[str]:
        # 1. Check modifier tag in country block
        if isinstance(country_block, dict):
            modifier = country_block.get("modifier", {})
            if isinstance(modifier, dict) and "tag" in modifier:
                return str(modifier["tag"])
            elif isinstance(modifier, list):
                for m in modifier:
                    if isinstance(m, dict) and "tag" in m:
                        return str(m["tag"])

        # 2. Check prefix in tree_id (e.g. OMS_reunification_tree -> OMS)
        parts = tree_id.split("_")
        if parts and len(parts[0]) == 3 and parts[0].isupper():
            return parts[0]

        # 3. Check filename (e.g. 2WRW_Omsk.txt -> OMS, GER.txt -> GER)
        base = os.path.basename(file_path).upper()
        if "OMSK" in base or "OMS" in base:
            return "OMS"
        if "SHUKSHIN" in base or "NOV" in base:
            return "NOV"
        if "WRS" in base or "WRRF" in base:
            return "WRS"
        if "KOMI" in base or "KOM" in base:
            return "KOM"
        if "GER" in base:
            return "GER"
        if "USA" in base:
            return "USA"
        if "JAP" in base:
            return "JAP"
        if "TYU" in base:
            return "TYU"
        if "SVE" in base:
            return "SVE"

        match = re.match(r"^([A-Z0-9]{3})\b", base)
        if match:
            return match.group(1)

        return None

    def _transform_focus_to_directive(self, rf: Dict[str, Any]) -> Dict[str, Any]:
        focus_id = str(rf.get("id"))
        
        # Localized Title & Description
        title_key = rf.get("text", focus_id)
        desc_key = rf.get("description", f"{focus_id}_desc")
        
        loc_title = self.content_mgr.get_loc(title_key, focus_id.replace("_", " ").title())
        loc_desc = self.content_mgr.get_loc(desc_key, "")

        # Icon conversion
        icon_ref = rf.get("icon", "")
        godot_icon = "res://icon.svg"
        if icon_ref:
            godot_icon = self.asset_conv.convert_goal_icon(str(icon_ref), focus_id)

        # Cost conversion (HoI4 cost in weeks -> turn count)
        cost_raw = float(rf.get("cost", 7.0))
        # Standard: 7-10 weeks in HoI4 = 3-4 turns in weekly mode, 2 turns in monthly mode
        turns = max(1, int(round(cost_raw * 0.45))) if cost_raw <= 20 else max(1, int(round(cost_raw / 14.0)))

        # Prerequisites
        prereqs: List[str] = []
        raw_prereq = rf.get("prerequisite", [])
        if isinstance(raw_prereq, dict):
            raw_prereq = [raw_prereq]
        elif not isinstance(raw_prereq, list):
            raw_prereq = []

        for p_block in raw_prereq:
            if isinstance(p_block, dict) and "focus" in p_block:
                f_target = p_block["focus"]
                if isinstance(f_target, list):
                    prereqs.extend([str(x) for x in f_target])
                else:
                    prereqs.append(str(f_target))

        # Mutually exclusive
        mutually_exclusive: List[str] = []
        raw_mutex = rf.get("mutually_exclusive", [])
        if isinstance(raw_mutex, dict):
            raw_mutex = [raw_mutex]
        elif not isinstance(raw_mutex, list):
            raw_mutex = []

        for m_block in raw_mutex:
            if isinstance(m_block, dict) and "focus" in m_block:
                m_target = m_block["focus"]
                if isinstance(m_target, list):
                    mutually_exclusive.extend([str(x) for x in m_target])
                else:
                    mutually_exclusive.append(str(m_target))

        # Rewards mapping with opcodes
        rewards = self._transform_rewards(rf.get("completion_reward", {}))

        # Grid position
        x = int(rf.get("x", 0))
        y = int(rf.get("y", 0))
        relative_id = rf.get("relative_position_id")

        return {
            "directive_id": focus_id,
            "title": loc_title,
            "description": loc_desc,
            "category": self._classify_category(focus_id, rewards),
            "icon_path": godot_icon,
            "icon_symbol": self._get_icon_symbol(focus_id),
            "grid_position": [x, y],
            "relative_position_id": str(relative_id) if relative_id else None,
            "turns_required": turns,
            "cost_initial_cap": 1,
            "cost_initial_pc": round(turns * 4.0, 1),
            "cost_money_per_turn_billions": round(turns * 0.04, 2),
            "prerequisites": prereqs,
            "mutually_exclusive_with": mutually_exclusive,
            "required_flags": [],
            "completion_effects": rewards
        }

    def _resolve_relative_coordinates(self, directives_by_id: Dict[str, Dict[str, Any]]) -> None:
        """Resolves relative_position_id to produce absolute (x, y) coordinates for rendering."""
        resolved: Set[str] = set()

        def resolve_node(did: str, depth: int = 0) -> Tuple[int, int]:
            if depth > 20:
                return (0, 0)
            d = directives_by_id.get(did)
            if not d:
                return (0, 0)
            if did in resolved:
                return tuple(d["grid_position"])

            rel_id = d.get("relative_position_id")
            if rel_id and rel_id in directives_by_id and rel_id != did:
                parent_x, parent_y = resolve_node(rel_id, depth + 1)
                d["grid_position"][0] += parent_x
                d["grid_position"][1] += parent_y

            resolved.add(did)
            return tuple(d["grid_position"])

        for d_id in list(directives_by_id.keys()):
            resolve_node(d_id)

    def _validate_and_sanitize_dag(self, directives_by_id: Dict[str, Dict[str, Any]]) -> None:
        """
        Validates the directed graph. If a cycle is detected, breaks the offending edge
        to prevent runtime infinite loops in Godot UI.
        """
        # State: 0 = unvisited, 1 = visiting, 2 = visited
        state: Dict[str, int] = {d_id: 0 for d_id in directives_by_id}

        def dfs(node: str, path: List[str]) -> bool:
            state[node] = 1
            node_data = directives_by_id.get(node)
            if not node_data:
                state[node] = 2
                return False

            prereqs = list(node_data.get("prerequisites", []))
            for p in prereqs:
                if p not in directives_by_id:
                    continue
                if state[p] == 1:
                    print(f"[WARN] Cycle detected in focus graph: {' -> '.join(path + [node, p])}")
                    print(f"       Breaking prerequisite edge '{p}' on node '{node}'")
                    node_data["prerequisites"].remove(p)
                elif state[p] == 0:
                    dfs(p, path + [node])

            state[node] = 2
            return False

        for node_id in directives_by_id:
            if state[node_id] == 0:
                dfs(node_id, [])

    def _transform_rewards(self, raw_rewards: Any) -> Dict[str, Any]:
        """Translates Clausewitz reward block into structured opcode operations."""
        structured: Dict[str, Any] = {}
        if not isinstance(raw_rewards, dict):
            return {"raw_effect": str(raw_rewards)}

        for k, v in raw_rewards.items():
            opcode = self.effect_opcodes.get(k)
            if opcode:
                structured[opcode] = v
            elif k == "add_political_power":
                structured["MOD_PC"] = v
            elif k == "add_stability":
                structured["MOD_STABILITY"] = v
            elif k == "add_war_support":
                structured["MOD_WAR_SUPPORT"] = v
            elif k == "set_country_flag":
                structured["SET_FLAG"] = v
            elif k == "country_event":
                structured["FIRE_EVENT"] = v
            elif k == "custom_effect_tooltip":
                structured["TOOLTIP"] = self.content_mgr.get_loc(str(v), str(v))
            else:
                structured[k] = v

        return structured

    def _classify_category(self, focus_id: str, rewards: Dict[str, Any]) -> str:
        low = focus_id.lower()
        if "army" in low or "milit" in low or "trial" in low or "defense" in low or "war" in low:
            return "military"
        elif "econ" in low or "plan" in low or "foundry" in low or "industr" in low or "invest" in low:
            return "economy"
        elif "party" in low or "soviet" in low or "politic" in low or "decree" in low:
            return "politics"
        elif "intel" in low or "kgb" in low or "abwehr" in low or "spy" in low:
            return "intelligence"
        return "doctrine"

    def _get_icon_symbol(self, focus_id: str) -> str:
        cat = self._classify_category(focus_id, {})
        match cat:
            case "military":
                return "[⚔]"
            case "economy":
                return "[🏭]"
            case "politics":
                return "[⚖]"
            case "intelligence":
                return "[👁]"
            case _:
                return "[★]"
