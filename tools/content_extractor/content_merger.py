#!/usr/bin/env python3
"""
Content Merger & Localization Manager for TNO Layered Content Pipeline.
========================================================================
Manages cascading resolution of files across mod layers:
  Base TNO Mod -> Submods (2WRW, etc.)
and multi-tier localization dictionary with fallback chains:
  [Submod RU] -> [TNO RU] -> [Submod EN] -> [TNO EN]
"""

import fnmatch
import os
import re
from typing import Any, Dict, List, Optional, Tuple, Union


class ClausewitzLexer:
    """Fast regex-based tokenizer for Clausewitz script (.txt)."""
    TOKEN_REGEX = re.compile(
        r'(#.*?$)|'                                # Comments
        r'("(?:\\.|[^"\\])*")|'                    # Quoted strings
        r'([<>!=]=|[<>=])|'                        # Comparison & assignment operators
        r'([{}])|'                                 # Braces
        r'([^\s#{}"=<>!]+)',                       # Bare words/identifiers
        re.MULTILINE
    )

    @classmethod
    def tokenize(cls, text: str) -> List[str]:
        tokens: List[str] = []
        for match in cls.TOKEN_REGEX.finditer(text):
            comment, quoted, op, brace, word = match.groups()
            if comment:
                continue
            elif quoted is not None:
                cleaned = quoted[1:-1].replace('\\"', '"').replace('\\\\', '\\')
                tokens.append(cleaned)
            elif op is not None:
                tokens.append(op)
            elif brace is not None:
                tokens.append(brace)
            elif word is not None:
                tokens.append(word)
        return tokens


class ClausewitzParser:
    """Recursive descent AST parser converting Clausewitz script into Python dicts & lists."""
    def __init__(self, tokens: List[str]):
        self.tokens = tokens
        self.pos = 0
        self.total = len(tokens)

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
            if self.peek() == "}":
                self.consume()
                continue
            self._parse_statement(root)
        return root

    def _parse_statement(self, container: Dict[str, Any]) -> None:
        key = self.consume()
        if key is None:
            return

        op = self.peek()
        if op in ("=", "<", ">", "<=", ">=", "!=", "?="):
            self.consume()  # operator
            val = self._parse_value()
            if op != "=":
                val = {"_op": op, "value": val}
            self._add_key_val(container, key, val)
        else:
            if "_items" not in container:
                container["_items"] = []
            container["_items"].append(key)

    def _parse_value(self) -> Any:
        token = self.peek()
        if token == "{":
            self.consume()  # '{'
            return self._parse_block()
        else:
            tok = self.consume()
            return self._convert_literal(tok)

    def _parse_block(self) -> Any:
        block_dict: Dict[str, Any] = {}
        block_list: List[Any] = []
        is_pure_list = True

        while self.pos < self.total:
            token = self.peek()
            if token == "}":
                self.consume()  # '}'
                break

            next_token = self.peek(1)
            if next_token in ("=", "<", ">", "<=", ">=", "!=", "?="):
                is_pure_list = False
                k = self.consume()
                op = self.consume()
                v = self._parse_value()
                if op != "=":
                    v = {"_op": op, "value": v}
                self._add_key_val(block_dict, k, v)
            elif token == "{":
                is_pure_list = False
                self.consume()
                nested = self._parse_block()
                block_list.append(nested)
            else:
                item = self.consume()
                block_list.append(self._convert_literal(item))

        if is_pure_list and not block_dict:
            return block_list
        if block_list:
            block_dict["_items"] = block_list
        return block_dict

    def _add_key_val(self, target: Dict[str, Any], key: str, val: Any) -> None:
        if key in target:
            existing = target[key]
            if isinstance(existing, list):
                existing.append(val)
            else:
                target[key] = [existing, val]
        else:
            target[key] = val

    @staticmethod
    def _convert_literal(val: Optional[str]) -> Any:
        if val is None:
            return None
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


def parse_clausewitz_text(text: str) -> Dict[str, Any]:
    tokens = ClausewitzLexer.tokenize(text)
    parser = ClausewitzParser(tokens)
    return parser.parse()


def parse_clausewitz_file(file_path: str) -> Dict[str, Any]:
    with open(file_path, "r", encoding="utf-8-sig", errors="replace") as f:
        content = f.read()
    return parse_clausewitz_text(content)


class LocalizationDictionary:
    """
    Paradox .yml localization parser with cascading fallback layers.
    Removes color formatting codes (§Y, §!, etc.) and cleanups whitespace.
    """
    CLEAN_TAGS_RE = re.compile(r'§[A-Za-z0-9!_]')
    ENTRY_RE = re.compile(r'^\s*([A-Za-z0-9_.\-]+):[0-9]*\s*"(.*)"\s*$', re.MULTILINE)

    def __init__(self):
        self.strings: Dict[str, str] = {}
        self.raw_counts: Dict[str, int] = {}

    def load_yml_file(self, file_path: str, override: bool = True) -> int:
        """Parses a single localization YAML file with fast streaming and populates the dictionary."""
        if not os.path.exists(file_path):
            return 0

        added = 0
        try:
            with open(file_path, "r", encoding="utf-8-sig", errors="replace") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    colon_idx = line.find(":")
                    if colon_idx <= 0:
                        continue
                    key = line[:colon_idx].strip()
                    if not override and key in self.strings:
                        continue

                    q1 = line.find('"', colon_idx)
                    q2 = line.rfind('"')
                    if q1 != -1 and q2 > q1:
                        val = line[q1 + 1 : q2]
                        # Strip Paradox color markers like §Y, §!
                        cleaned_val = self.CLEAN_TAGS_RE.sub("", val)
                        cleaned_val = cleaned_val.replace("\\n", "\n").replace('\\"', '"').strip()
                        self.strings[key] = cleaned_val
                        added += 1
        except Exception as e:
            print(f"[WARN] Error parsing loc file {file_path}: {e}")

        return added

    def load_directory(self, dir_path: str, override: bool = True) -> int:
        """Recursively parses all .yml files in a directory."""
        if not os.path.exists(dir_path):
            return 0

        total_added = 0
        for root, _, files in os.walk(dir_path):
            for file in files:
                if file.endswith((".yml", ".yaml")):
                    p = os.path.join(root, file)
                    total_added += self.load_yml_file(p, override=override)
        return total_added

    def get(self, key: str, default: Optional[str] = None) -> str:
        """Lookups key in dictionary, falls back to default or the key itself."""
        if key in self.strings:
            return self.strings[key]
        return default if default is not None else key

    def resolve(self, text: str) -> str:
        """If text is an existing key, resolves it; otherwise returns text as is."""
        if not text:
            return ""
        return self.strings.get(text, text)


class LayeredContentManager:
    """
    Resolves mod file paths and scripts across multiple layered directories.
    Order of layers defines priority: earlier layers are base, later layers override earlier ones.
    Example: [TNO_ROOT, SUBMOD_2WRW_ROOT]
    """
    def __init__(self, content_layers: List[str], loc_layers: Optional[List[Tuple[str, str]]] = None):
        """
        :param content_layers: List of mod root paths in ascending priority.
        :param loc_layers: List of tuples (mod_root, subfolder_lang) in ascending priority.
                           Example: [
                               (tno_dir, 'english'),
                               (submod_dir, 'english'),
                               (tno_ru_dir, 'russian'),
                               (submod_ru_dir, 'russian')
                           ]
        """
        self.layers = [os.path.abspath(p) for p in content_layers if os.path.exists(p)]
        self.loc_layers = loc_layers or []
        self.loc_dict = LocalizationDictionary()
        self._init_localization()

    def _init_localization(self) -> None:
        """Populates localization in priority order (later layers override earlier ones)."""
        print(f"[ContentMerger] Initializing localization layers ({len(self.loc_layers)} layers)...")
        total_strings = 0
        for root_dir, lang in self.loc_layers:
            loc_dir = os.path.join(root_dir, "localisation", lang)
            if not os.path.exists(loc_dir):
                loc_dir = os.path.join(root_dir, "localisation")
            if os.path.exists(loc_dir):
                cnt = self.loc_dict.load_directory(loc_dir, override=True)
                total_strings += cnt
                print(f"  + Loaded {cnt} entries from {loc_dir}")
        print(f"[ContentMerger] Total active localized strings: {len(self.loc_dict.strings)}")

    def resolve_file(self, relative_path: str) -> Optional[str]:
        """
        Searches for relative_path across layers from highest priority (last) to lowest (first).
        Returns the absolute path of the first match found, or None.
        """
        normalized_rel = os.path.normpath(relative_path)
        for layer in reversed(self.layers):
            candidate = os.path.join(layer, normalized_rel)
            if os.path.exists(candidate) and os.path.isfile(candidate):
                return candidate
        return None

    def get_merged_files(self, relative_subfolder: str, pattern: str = "*.txt") -> Dict[str, str]:
        """
        Scans relative_subfolder across all layers.
        Returns a dict mapping {relative_file_path: absolute_file_path},
        where higher priority layers override lower ones.
        """
        merged_map: Dict[str, str] = {}
        normalized_sub = os.path.normpath(relative_subfolder)

        # Iterate from lowest priority to highest, overriding map keys
        for layer in self.layers:
            target_dir = os.path.join(layer, normalized_sub)
            if not os.path.exists(target_dir):
                continue

            for root, _, files in os.walk(target_dir):
                for f in files:
                    if fnmatch.fnmatch(f, pattern):
                        abs_p = os.path.join(root, f)
                        rel_p = os.path.relpath(abs_p, layer)
                        # Normalize key with forward slashes for cross-platform stability
                        rel_key = rel_p.replace("\\", "/")
                        merged_map[rel_key] = abs_p

        return merged_map

    def parse_script_file(self, relative_path: str) -> Optional[Dict[str, Any]]:
        """Resolves file with cascading priority and parses it into Clausewitz AST."""
        abs_p = self.resolve_file(relative_path)
        if abs_p is None:
            return None
        return parse_clausewitz_file(abs_p)

    def get_loc(self, key: str, default: Optional[str] = None) -> str:
        """Shorthand to retrieve a localized string."""
        return self.loc_dict.get(key, default)

    def resolve_loc(self, key_or_literal: str) -> str:
        """Shorthand to resolve a localized string if key exists."""
        return self.loc_dict.resolve(key_or_literal)
