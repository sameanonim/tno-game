"""
Clausewitz Script Lexer, AST Parser and TNO Focus Tree Transpiler
=================================================================
Senior Engine Architecture implementation for importing and compiling
Hearts of Iron IV / TNO mod script files into declarative AST and Godot resources.

Handles:
- Comments (#) and multi-encoding files (UTF-8, UTF-8-BOM, CP1252, Latin-1)
- Preprocessor variables (@var_name = val)
- Duplicate keys in identical scopes (e.g. repeated prerequisite, completion_reward)
- Comparison operators in statements (<, >, <=, >=, ==, !=, =)
- Comma-free identifier lists (members = { GER USA ITA })
- Trigger AST synthesis (AND, OR, NOT trees)
- Effect instruction compilation
- Localization YML extraction with Paradox §X...§! -> Godot BBCode [color=...]...[/color]
"""

from pathlib import Path
import re
from typing import Any, Dict, List, Optional, Tuple, Union


class ClausewitzLexer:
    """High-performance regular-expression based lexer for Clausewitz script."""

    TOKEN_REGEX = re.compile(
        r'("(?:\\.|[^"\\])*")|'                    # Group 1: Quoted string literal
        r'(#[^\r\n]*)|'                            # Group 2: Single-line comment
        r'([<>!=]=|[<>=])|'                        # Group 3: Comparison and assignment operators
        r'([{}])|'                                 # Group 4: Braces
        r'(@[a-zA-Z0-9_]+)|'                       # Group 5: Preprocessor variable definition/usage
        r'([^\s#{}"=<>!]+)',                       # Group 6: Word / literal / identifier
        re.MULTILINE
    )

    @classmethod
    def tokenize(cls, text: str) -> List[str]:
        tokens: List[str] = []
        for match in cls.TOKEN_REGEX.finditer(text):
            quoted, comment, op, brace, prep_var, word = match.groups()
            if comment is not None:
                continue
            if quoted is not None:
                cleaned = quoted[1:-1].replace('\\"', '"').replace('\\\\', '\\')
                tokens.append(f'"{cleaned}"')
            elif op is not None:
                tokens.append(op)
            elif brace is not None:
                tokens.append(brace)
            elif prep_var is not None:
                tokens.append(prep_var)
            elif word is not None:
                tokens.append(word)
        return tokens


class ClausewitzParser:
    """
    Parser that resolves preprocessor variables (@vars), preserves duplicate keys as lists,
    detects inline comparisons, and produces normalized nested structures.
    """

    def __init__(self, tokens: List[str]):
        self.tokens: List[str] = tokens
        self.pos: int = 0
        self.total: int = len(tokens)
        self.variables: Dict[str, Any] = {}

    def peek(self, offset: int = 0) -> Optional[str]:
        idx = self.pos + offset
        if idx < self.total:
            return self.tokens[idx]
        return None

    def consume(self) -> Optional[str]:
        if self.pos < self.total:
            tok = self.tokens[self.pos]
            self.pos += 1
            return tok
        return None

    def parse(self) -> Dict[str, Any]:
        root: Dict[str, Any] = {}
        while self.pos < self.total:
            tok = self.peek()
            if tok == "}":
                self.consume()
                continue
            self._parse_statement(root)
        return root

    def _parse_statement(self, container: Dict[str, Any]) -> None:
        key = self.consume()
        if key is None:
            return

        # Preprocessor variable definition: @my_var = 12
        if key.startswith("@"):
            if self.peek() == "=":
                self.consume()
                val = self._parse_value()
                self.variables[key] = val
                return

        op = self.peek()
        if op in ("=", "<", ">", "<=", ">=", "!=", "=="):
            self.consume()
            val = self._parse_value()

            if op != "=":
                val = {"_op": op, "var": key, "val": val}

            self._append_key_val(container, key, val)
        else:
            # Standalone identifier or list item
            if "_items" not in container:
                container["_items"] = []
            container["_items"].append(self._resolve_literal(key))

    def _parse_value(self) -> Any:
        tok = self.peek()
        if tok == "{":
            self.consume()
            return self._parse_block()
        val = self.consume()
        return self._resolve_literal(val)

    def _parse_block(self) -> Any:
        block_dict: Dict[str, Any] = {}
        block_list: List[Any] = []
        is_pure_list = True

        while self.pos < self.total:
            tok = self.peek()
            if tok == "}":
                self.consume()
                break

            next_tok = self.peek(1)
            if next_tok in ("=", "<", ">", "<=", ">=", "!=", "=="):
                is_pure_list = False
                key = self.consume()
                op = self.consume()
                val = self._parse_value()
                if op != "=":
                    val = {"_op": op, "var": key, "val": val}
                self._append_key_val(block_dict, key, val)
            elif tok == "{":
                is_pure_list = False
                self.consume()
                sub = self._parse_block()
                block_list.append(sub)
            else:
                item = self.consume()
                block_list.append(self._resolve_literal(item))

        if is_pure_list and not block_dict:
            return block_list
        if block_list:
            block_dict["_items"] = block_list
        return block_dict

    def _append_key_val(self, target: Dict[str, Any], key: str, val: Any) -> None:
        if key in target:
            existing = target[key]
            if isinstance(existing, list):
                existing.append(val)
            else:
                target[key] = [existing, val]
        else:
            target[key] = val

    def _resolve_literal(self, val: Optional[str]) -> Any:
        if val is None:
            return None
        # Substitute preprocessor variable
        if val.startswith("@") and val in self.variables:
            return self.variables[val]

        if val.startswith('"') and val.endswith('"'):
            return val[1:-1]

        low = val.lower()
        if low == "yes":
            return True
        if low == "no":
            return False

        if val.isdigit() or (val.startswith("-") and val[1:].isdigit()):
            try:
                return int(val)
            except ValueError:
                pass
        try:
            if "." in val:
                return float(val)
        except ValueError:
            pass

        return val


class ASTBuilder:
    """
    Transforms parsed raw Clausewitz script objects into strongly typed ASTs
    for trigger conditions and effect instructions.
    """

    @classmethod
    def build_trigger_ast(cls, raw: Any) -> Dict[str, Any]:
        """
        Converts a trigger block (e.g. available = { ... }) into an AND/OR/NOT AST.
        Format:
        {
            "type": "AND" | "OR" | "NOT",
            "children": [ ... ]
        }
        or Leaf:
        {
            "op": "<op_name>",
            ...params
        }
        """
        children = cls._build_trigger_children(raw)
        if len(children) == 1 and children[0].get("type") in ("AND", "OR", "NOT"):
            return children[0]
        return {"type": "AND", "children": children}

    @classmethod
    def _build_trigger_children(cls, raw: Any) -> List[Dict[str, Any]]:
        if not raw:
            return []

        if isinstance(raw, list):
            children: List[Dict[str, Any]] = []
            for item in raw:
                children.extend(cls._build_trigger_children(item))
            return children

        if not isinstance(raw, dict):
            return []

        children = []
        for key, val in raw.items():
            if key == "_items":
                continue

            # Boolean grouping
            key_upper = key.upper()
            if key_upper in ("AND", "OR", "NOT"):
                val_list = val if isinstance(val, list) else [val]
                group_children: List[Dict[str, Any]] = []
                for v in val_list:
                    group_children.extend(cls._build_trigger_children(v))
                children.append({"type": key_upper, "children": group_children})
                continue

            # Handle comparisons like days > 30 or check_variable = { var > 10 }
            val_items = val if isinstance(val, list) else [val]
            for v in val_items:
                if isinstance(v, dict) and "_op" in v:
                    children.append({
                        "op": "compare",
                        "var": v.get("var", key),
                        "cmp": v.get("_op", "=="),
                        "val": v.get("val")
                    })
                elif key == "check_variable":
                    children.append(cls._parse_check_variable(v))
                elif key in ("has_country_flag", "has_global_flag", "has_completed_focus", "tag", "is_puppet", "has_idea"):
                    children.append({
                        "op": key,
                        "target": str(v)
                    })
                elif key in ("num_of_factories", "political_power", "stability", "war_support"):
                    if isinstance(v, dict) and "_op" in v:
                        children.append({
                            "op": key,
                            "cmp": v.get("_op", ">="),
                            "val": v.get("val", 0)
                        })
                    else:
                        children.append({
                            "op": key,
                            "cmp": ">=",
                            "val": v
                        })
                elif key == "date":
                    if isinstance(v, dict) and "_op" in v:
                        children.append({"op": "date", "cmp": v.get("_op", ">="), "val": str(v.get("val"))})
                    else:
                        children.append({"op": "date", "cmp": ">=", "val": str(v)})
                else:
                    # Generic / nested trigger or scope trigger
                    if isinstance(v, dict):
                        sub_children = cls._build_trigger_children(v)
                        children.append({
                            "op": key,
                            "scope": key,
                            "sub_tree": {"type": "AND", "children": sub_children}
                        })
                    else:
                        children.append({
                            "op": key,
                            "target": v
                        })

        return children

    @classmethod
    def _parse_check_variable(cls, v: Any) -> Dict[str, Any]:
        """Parses Clausewitz check_variable = { which = var value > 10 } or check_variable = { var > 10 }."""
        if isinstance(v, dict):
            if "_op" in v:
                return {
                    "op": "check_variable",
                    "var": v.get("which", v.get("var", "")),
                    "cmp": v.get("_op", ">="),
                    "val": v.get("val", 0)
                }
            if len(v) == 1:
                inner_k, inner_v = next(iter(v.items()))
                if isinstance(inner_v, dict) and "_op" in inner_v:
                    return {
                        "op": "check_variable",
                        "var": inner_k,
                        "cmp": inner_v.get("_op", ">="),
                        "val": inner_v.get("val", 0)
                    }
                if isinstance(inner_v, (int, float, str)):
                    return {
                        "op": "check_variable",
                        "var": inner_k,
                        "cmp": ">=",
                        "val": inner_v
                    }
            var_name = v.get("which", v.get("var", ""))
            cmp_op = v.get("compare", v.get("_op", ">="))
            val = v.get("value", v.get("val", 0))
            if isinstance(val, dict) and "_op" in val:
                cmp_op = val.get("_op", cmp_op)
                val = val.get("val", 0)
            return {
                "op": "check_variable",
                "var": var_name,
                "cmp": cmp_op,
                "val": val
            }
        return {"op": "check_variable", "var": str(v), "cmp": ">", "val": 0}

    @classmethod
    def build_effects_list(cls, raw: Any) -> List[Dict[str, Any]]:
        """
        Converts effect blocks (completion_reward, select_effect) into a list of
        ClausewitzInstruction dictionaries:
        {
            "command": "add_political_power",
            "args": {"value": 50},
            "scope_target": ""
        }
        """
        instructions: List[Dict[str, Any]] = []
        if not raw or not isinstance(raw, dict):
            return instructions

        for cmd, arg_val in raw.items():
            if cmd == "_items":
                continue

            values = arg_val if isinstance(arg_val, list) else [arg_val]
            for v in values:
                scope_target = ""
                args = {}

                if isinstance(v, dict):
                    args = v
                elif isinstance(v, (int, float, str, bool)):
                    args = {"value": v}

                instructions.append({
                    "command": cmd,
                    "args": args,
                    "scope_target": scope_target
                })

        return instructions


class LocalizationColorTransformer:
    """
    Translates Clausewitz color codes to Godot BBCode.
    Paradox:
      §Ytext§! -> [color=yellow]text[/color]
      §Rtext§! -> [color=red]text[/color]
      §Gtext§! -> [color=green]text[/color]
      §Otext§! -> [color=orange]text[/color]
      §Wtext§! -> [color=white]text[/color]
      §Btext§! -> [color=cornflower_blue]text[/color]
      §Ctext§! -> [color=cyan]text[/color]
    """

    COLOR_MAP = {
        "Y": "yellow",
        "R": "red",
        "G": "green",
        "O": "orange",
        "W": "white",
        "B": "cornflower_blue",
        "C": "cyan",
        "H": "khaki",
        "L": "purple",
        "T": "light_gray",
    }

    TAG_PATTERN = re.compile(r'§([A-Za-z!])')

    @classmethod
    def paradox_to_bbcode(cls, text: str) -> str:
        if not text or "§" not in text:
            return text

        result = []
        open_tags = 0
        last_idx = 0

        for match in cls.TAG_PATTERN.finditer(text):
            result.append(text[last_idx:match.start()])
            code = match.group(1).upper()
            last_idx = match.end()

            if code == "!":
                if open_tags > 0:
                    result.append("[/color]")
                    open_tags -= 1
            elif code in cls.COLOR_MAP:
                color_name = cls.COLOR_MAP[code]
                result.append(f"[color={color_name}]")
                open_tags += 1

        result.append(text[last_idx:])

        # Close any leftover tags
        while open_tags > 0:
            result.append("[/color]")
            open_tags -= 1

        return "".join(result)


class LocalizationParser:
    """Parses Paradox HoI4 YML localization files."""

    LINE_PATTERN = re.compile(r'^\s*([a-zA-Z0-9_\-\.]+):[0-9]*\s*"(.*)"\s*$', re.MULTILINE)

    @classmethod
    def parse_yml_text(cls, text: str) -> Dict[str, str]:
        loc: Dict[str, str] = {}
        for match in cls.LINE_PATTERN.finditer(text):
            key = match.group(1)
            raw_val = match.group(2)
            # Unescape
            cleaned = raw_val.replace('\\"', '"').replace('\\n', '\n')
            bbcode_val = LocalizationColorTransformer.paradox_to_bbcode(cleaned)
            loc[key] = bbcode_val
        return loc

    @classmethod
    def parse_file(cls, path: Union[str, Path]) -> Dict[str, str]:
        path = Path(path)
        for enc in ("utf-8-sig", "utf-8", "cp1252", "latin-1"):
            try:
                with open(path, "r", encoding=enc) as f:
                    return cls.parse_yml_text(f.read())
            except (UnicodeDecodeError, UnicodeError):
                continue
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return cls.parse_yml_text(f.read())


class FocusTreeCompiler:
    """
    Compiles raw Clausewitz focus tree dictionary into normalized FocusTreeData dictionary
    compatible with Godot 4 Resource serialization.
    """

    @classmethod
    def compile_tree(cls, raw_tree: Dict[str, Any], tree_id: str = "") -> Dict[str, Any]:
        tree_obj = raw_tree.get("focus_tree", raw_tree)
        actual_id = tree_id or str(tree_obj.get("id", "unknown_tree"))
        country_tag = ""

        # Extract country tag if present
        country_filter = tree_obj.get("country", {})
        if isinstance(country_filter, dict):
            modifier = country_filter.get("modifier", {})
            if isinstance(modifier, dict):
                country_tag = str(modifier.get("tag", ""))

        raw_focuses = tree_obj.get("focus", [])
        if isinstance(raw_focuses, dict):
            raw_focuses = [raw_focuses]

        compiled_nodes: Dict[str, Any] = {}

        for f in raw_focuses:
            if not isinstance(f, dict):
                continue
            f_id = str(f.get("id", ""))
            if not f_id:
                continue

            node_data = cls._compile_focus_node(f)
            compiled_nodes[f_id] = node_data

        # 1. Resolve relative_position_id chains into absolute grid_coord [x, y]
        raw_coords: Dict[str, Tuple[int, int, str]] = {
            fid: (node["raw_x"], node["raw_y"], node["relative_position_id"])
            for fid, node in compiled_nodes.items()
        }

        memo_pos: Dict[str, Tuple[int, int]] = {}

        def resolve_pos(fid: str, visited: Optional[Set[str]] = None) -> Tuple[int, int]:
            if fid in memo_pos:
                return memo_pos[fid]
            if visited is None:
                visited = set()
            if fid in visited or fid not in raw_coords:
                rx, ry = raw_coords.get(fid, (0, 0, ""))[:2]
                return rx, ry
            visited.add(fid)
            rx, ry, parent_id = raw_coords[fid]
            if not parent_id or parent_id not in raw_coords:
                memo_pos[fid] = (rx, ry)
                return rx, ry
            px, py = resolve_pos(parent_id, visited)
            final_pos = (px + rx, py + ry)
            memo_pos[fid] = final_pos
            return final_pos

        for fid, node in compiled_nodes.items():
            ax, ay = resolve_pos(fid)
            node["grid_coord"] = [ax, ay]

        # 2. Guarantee bidirectional symmetrization of mutually_exclusive references
        for fid, node in compiled_nodes.items():
            for mex in node.get("mutually_exclusive", []):
                if mex in compiled_nodes:
                    if fid not in compiled_nodes[mex]["mutually_exclusive"]:
                        compiled_nodes[mex]["mutually_exclusive"].append(fid)

        return {
            "tree_id": actual_id,
            "country_tag": country_tag,
            "nodes": compiled_nodes,
            "shared_focus_branches": []
        }

    @classmethod
    def _compile_focus_node(cls, f: Dict[str, Any]) -> Dict[str, Any]:
        f_id = str(f.get("id", ""))
        text_id = str(f.get("text", f_id))
        desc_id = str(f.get("desc", f"{f_id}_desc"))
        icon_path = str(f.get("icon", ""))
        x = int(f.get("x", 0))
        y = int(f.get("y", 0))
        cost = float(f.get("cost", 10.0))
        relative_id = str(f.get("relative_position_id", ""))
        custom_tooltip = str(f.get("custom_effect_tooltip", ""))

        raw_cii = f.get("cancel_if_invalid", "yes")
        if isinstance(raw_cii, str):
            cancel_if_invalid = raw_cii.lower() not in ("no", "false")
        elif isinstance(raw_cii, bool):
            cancel_if_invalid = raw_cii
        else:
            cancel_if_invalid = True

        # Prerequisites: multiple prerequisite blocks = AND, within each block = OR
        prereqs: List[List[str]] = []
        raw_prereqs = f.get("prerequisite", [])
        if isinstance(raw_prereqs, dict):
            raw_prereqs = [raw_prereqs]

        for p_block in raw_prereqs:
            if isinstance(p_block, dict):
                focus_refs = p_block.get("focus", [])
                if isinstance(focus_refs, (str, int)):
                    focus_refs = [str(focus_refs)]
                elif isinstance(focus_refs, list):
                    focus_refs = [str(x) for x in focus_refs]
                if focus_refs:
                    prereqs.append(focus_refs)

        # Mutually exclusive
        mut_ex: List[str] = []
        raw_mut = f.get("mutually_exclusive", [])
        if isinstance(raw_mut, dict):
            raw_mut = [raw_mut]
        for m_block in raw_mut:
            if isinstance(m_block, dict):
                m_focuses = m_block.get("focus", [])
                if isinstance(m_focuses, (str, int)):
                    mut_ex.append(str(m_focuses))
                elif isinstance(m_focuses, list):
                    mut_ex.extend([str(x) for x in m_focuses])

        # Available trigger AST
        avail_raw = f.get("available", {})
        available_ast = ASTBuilder.build_trigger_ast(avail_raw)

        # Bypass trigger AST
        bypass_raw = f.get("bypass", {})
        bypass_ast = ASTBuilder.build_trigger_ast(bypass_raw)

        # Allow branch dynamic condition AST (allow_branch = { ... })
        allow_branch_raw = f.get("allow_branch", {})
        allow_branch_ast = ASTBuilder.build_trigger_ast(allow_branch_raw)

        # Completion rewards
        reward_raw = f.get("completion_reward", {})
        completion_effects = ASTBuilder.build_effects_list(reward_raw)

        # Midway effects (TNO specific)
        midway_effects: Dict[float, List[Dict[str, Any]]] = {}
        midway_raw = f.get("tno_midway_effects", f.get("midway_effect", {}))
        if midway_raw:
            midway_effects[0.5] = ASTBuilder.build_effects_list(midway_raw)

        return {
            "id": f_id,
            "text_id": text_id,
            "desc_id": desc_id,
            "icon_path": icon_path,
            "raw_x": x,
            "raw_y": y,
            "grid_coord": [x, y],
            "relative_position_id": relative_id,
            "cost": cost,
            "cancel_if_invalid": cancel_if_invalid,
            "custom_tooltip_id": custom_tooltip,
            "prerequisites": prereqs,
            "mutually_exclusive": mut_ex,
            "available_ast": available_ast,
            "bypass_ast": bypass_ast,
            "allow_branch_ast": allow_branch_ast,
            "on_completion_effects": completion_effects,
            "tno_midway_effects": midway_effects
        }


class ClausewitzEventParser:
    """Parses Hearts of Iron IV event files into structured GameEvent dictionaries."""

    @classmethod
    def parse_events(cls, text: str) -> List[Dict[str, Any]]:
        tokens = ClausewitzLexer.tokenize(text)
        parser = ClausewitzParser(tokens)
        raw = parser.parse()

        events_list: List[Dict[str, Any]] = []
        raw_events = raw.get("country_event", [])
        if isinstance(raw_events, dict):
            raw_events = [raw_events]

        for ev in raw_events:
            if not isinstance(ev, dict):
                continue
            ev_id = str(ev.get("id", ""))
            if not ev_id:
                continue

            title_id = str(ev.get("title", ""))
            desc_id = str(ev.get("desc", ""))
            picture = str(ev.get("picture", ""))
            is_triggered_only = str(ev.get("is_triggered_only", "no")).lower() in ("yes", "true")

            trigger_ast = ASTBuilder.build_trigger_ast(ev.get("trigger", {}))
            immediate_effects = ASTBuilder.build_effects_list(ev.get("immediate", {}))

            raw_options = ev.get("option", [])
            if isinstance(raw_options, dict):
                raw_options = [raw_options]

            options: List[Dict[str, Any]] = []
            for idx, opt in enumerate(raw_options):
                if not isinstance(opt, dict):
                    continue
                opt_name = str(opt.get("name", f"{ev_id}.{chr(97 + idx)}"))
                ai_chance = 100
                raw_chance = opt.get("ai_chance", {})
                if isinstance(raw_chance, dict) and "factor" in raw_chance:
                    try:
                        ai_chance = int(float(raw_chance["factor"]))
                    except (ValueError, TypeError):
                        ai_chance = 100

                # Exclude meta keys when extracting option rewards
                opt_copy = dict(opt)
                opt_copy.pop("name", None)
                opt_copy.pop("ai_chance", None)
                opt_copy.pop("trigger", None)

                rewards = ASTBuilder.build_effects_list(opt_copy)
                options.append({
                    "id": f"opt_{idx + 1}",
                    "title": opt_name,
                    "ai_weight": ai_chance,
                    "rewards": rewards
                })

            events_list.append({
                "event_id": ev_id,
                "title_id": title_id,
                "desc_id": desc_id,
                "picture": picture,
                "is_triggered_only": is_triggered_only,
                "trigger_ast": trigger_ast,
                "immediate_effects": immediate_effects,
                "options": options
            })

        return events_list


def parse_and_compile_clausewitz(text: str, tree_id: str = "") -> Dict[str, Any]:
    """All-in-one entry point for parsing and compiling raw Clausewitz script to FocusTree dict."""
    tokens = ClausewitzLexer.tokenize(text)
    parser = ClausewitzParser(tokens)
    raw = parser.parse()
    return FocusTreeCompiler.compile_tree(raw, tree_id)


def transpile_tno_bundle(focus_script: str, loc_yml: str = "", events_script: str = "", tree_id: str = "") -> Dict[str, Any]:
    """Transpiles a complete TNO national content package (Focuses + Localisation + Events)."""
    focus_tree = parse_and_compile_clausewitz(focus_script, tree_id)
    localization = LocalizationParser.parse_yml_text(loc_yml) if loc_yml else {}
    events = ClausewitzEventParser.parse_events(events_script) if events_script else []

    return {
        "tree": focus_tree,
        "localization": localization,
        "events": events
    }
