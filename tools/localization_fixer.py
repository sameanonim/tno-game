#!/usr/bin/env python3
"""
TNO & Submods Localization Fixer & Audit Pipeline
=================================================
Autonomous production-ready pipeline for auditing, cleaning, repairing,
normalizing, and modularizing Hearts of Iron IV / TNO localization data
for turn-based geopolitics strategy in Godot 4.

Key Capabilities:
1. Encoding auto-detection (UTF-8-BOM, UTF-8, CP1251, Latin-1).
2. Clausewitz YAML syntax repair:
   - Multiline string stitching and unclosed quote handling.
   - Elimination of Clausewitz color tags (§Y, §!, §R, §G, §B, §C, etc.).
   - Interior quote conversion to typography quotes (« » / “ ”) or safe escaping.
   - Normalization of whitespace, non-breaking spaces (\u00a0), and zero-width chars.
3. Canonical token normalization:
   - [Root.GetName], [This.GetLeader], [GetDateText], [?global.var] -> {country_name}, {leader_name}, {date}, {var}.
4. Recursive reference resolution ($OTHER_KEY$ / $OTHER_KEY|H$):
   - Cycle detection and maximum recursion depth safeguards.
   - Dynamic template variables ($COUNT$, $DAYS$, $NAME$) -> {count}, {days}, {name}.
5. Layered cascade merging:
   - Submod RU (Priority) > TNO Official RU > Submod EN (Fallback) > Base TNO EN.
   - Merging with existing project UI localization keys.
6. Game Key Audit:
   - Cross-referencing against game events, focus trees/directives, and countries.
7. Modular exports:
   - Global: strings_ru.json, strings_en.json (and ru.json, en.json).
   - Country packages: data/countries/<TAG>/localisation/ru.json & en.json.
   - SQLite DB: data/localization/localization_db.sqlite with O(1) indexed lookups.
   - Audit report: Console output + markdown file.
"""

import argparse
import glob
import json
import os
import re
import sqlite3
import sys
import time
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple, Union

# Ensure console supports utf-8 output without crashing on Windows
if sys.stdout and hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
if sys.stderr and hasattr(sys.stderr, "reconfigure"):
    try:
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass


# ==============================================================================
# DATA MODELS & AUDIT STATS
# ==============================================================================

@dataclass
class AuditMetrics:
    total_files_scanned: int = 0
    files_per_encoding: Counter = field(default_factory=Counter)
    total_raw_keys_parsed: int = 0
    duplicate_keys_overridden: int = 0
    unclosed_quotes_repaired: int = 0
    multiline_strings_stitched: int = 0
    interior_quotes_fixed: int = 0
    color_tags_stripped: int = 0
    tokens_normalized: int = 0
    dollar_refs_resolved: int = 0
    dollar_refs_unresolved: int = 0
    circular_refs_prevented: int = 0
    untranslated_fallbacks_used: int = 0
    missing_game_keys: List[str] = field(default_factory=list)
    critical_errors: List[str] = field(default_factory=list)


# ==============================================================================
# REGEX & CANONICAL REPLACEMENTS
# ==============================================================================

# Match language header, e.g.: l_russian: or l_english:
HEADER_RE = re.compile(r'^\s*l_([a-zA-Z0-9_\-]+)\s*:', re.IGNORECASE)

# Match start of a key definition: KEY:0 "TEXT or KEY: "TEXT or KEY "TEXT
KEY_START_RE = re.compile(r'^\s*([a-zA-Z0-9_.\-]+)\s*(?::[0-9]*)?\s*"(.*)$')

# Clausewitz color codes: §Y, §!, §R, §G, §B, §C, §H, §O, §L, §W, §g, §t, §=, §, etc.
COLOR_TAG_RE = re.compile(r'§[A-Za-z0-9!_,\^\%\-\+=]')
COLOR_TAG_ANY_RE = re.compile(r'§.')

# Nested Clausewitz reference pattern: $KEY_NAME$ or $KEY_NAME|H$ or $KEY_NAME|Y$
DOLLAR_REF_RE = re.compile(r'\$([a-zA-Z0-9_.\-]+)(?:\|[a-zA-Z0-9!_]+)?\$')

# Standard HoI4 Token map to canonical project format
HOI4_TOKEN_MAP = {
    # Country tokens
    r'\[(?i:root\.getnamedefcap|root\.getnamedef|root\.getname|this\.getname|this\.getnamedef|from\.owner\.getnamedef|from\.getname|from\.getnamedef)\]': '{country_name}',
    r'\[(?i:root\.getadjectivecap|root\.getadjective|this\.getadjective)\]': '{country_adj}',
    # Leader tokens
    r'\[(?i:root\.getleader|this\.getleader|getleader)\]': '{leader_name}',
    # Date & time tokens
    r'\[(?i:getdatetext|getdate|root\.getdatetext)\]': '{date}',
    r'\[(?i:getyear)\]': '{year}',
    r'\[(?i:getmonth)\]': '{month}',
    r'\[(?i:getday)\]': '{day}',
    # Generic Clausewitz script variables
    r'\[\?(?:global\.)?([a-zA-Z0-9_]+)\]': r'{\1}',
}

# HoI4 template variables that often appear as $COUNT$, $NAME$, $STATE$, etc.
TEMPLATE_VARS_MAP = {
    "COUNT": "{count}",
    "DAYS": "{days}",
    "HOURS": "{hours}",
    "NAME": "{name}",
    "STATE": "{state}",
    "REGION": "{region}",
    "TARGET": "{target}",
    "VALUE": "{value}",
    "VAL": "{value}",
    "NUM": "{amount}",
    "AMOUNT": "{amount}",
    "LEADER": "{leader_name}",
    "COUNTRY": "{country_name}",
    "TITLE": "{title}",
    "YEAR": "{year}",
    "MONTH": "{month}",
    "DAY": "{day}",
    "MAX": "{max}",
    "MIN": "{min}",
}


# ==============================================================================
# LEXER & SYNTAX SANITIZER
# ==============================================================================

class LocalizationSanitizer:
    """
    Sanitizes raw Clausewitz / TNO text into clean, modern typography and
    canonical placeholders.
    """

    @staticmethod
    def strip_color_tags(text: str, metrics: Optional[AuditMetrics] = None) -> str:
        if "§" not in text:
            return text
        matches = len(COLOR_TAG_RE.findall(text))
        if metrics and matches > 0:
            metrics.color_tags_stripped += matches
        cleaned = COLOR_TAG_RE.sub('', text)
        if "§" in cleaned:
            cleaned = COLOR_TAG_ANY_RE.sub('', cleaned)
        return cleaned

    @staticmethod
    def fix_interior_quotes(text: str, lang: str = "ru", metrics: Optional[AuditMetrics] = None) -> str:
        """
        Converts unescaped inner double quotes into proper typography quotes:
        Russian: « and »
        English: “ and ” (or safely escaped \")
        """
        if '"' not in text:
            return text

        parts = text.split('"')
        if len(parts) <= 1:
            return text

        if metrics:
            metrics.interior_quotes_fixed += (len(parts) - 1)

        result_pieces = [parts[0]]
        open_quote = True

        for piece in parts[1:]:
            if lang == "ru":
                quote_char = "«" if open_quote else "»"
            else:
                quote_char = "“" if open_quote else "”"
            open_quote = not open_quote
            result_pieces.append(quote_char + piece)

        return "".join(result_pieces)

    @staticmethod
    def normalize_tokens(text: str, metrics: Optional[AuditMetrics] = None) -> str:
        """
        Converts old HoI4 brackets and variables to canonical {param} tokens.
        """
        if "[" not in text and "$" not in text:
            return text

        original = text
        for pattern, replacement in HOI4_TOKEN_MAP.items():
            text = re.sub(pattern, replacement, text)

        # Handle remaining [Token.Subtoken] or [Token]
        def _token_sub(m: re.Match) -> str:
            token = m.group(1).lower().replace(".", "_")
            return f"{{{token}}}"

        text = re.sub(r'\[([a-zA-Z0-9_.]+)\]', _token_sub, text)

        if metrics and text != original:
            metrics.tokens_normalized += 1

        return text

    @staticmethod
    def clean_whitespaces_and_controls(text: str) -> str:
        """
        Cleans non-breaking spaces, zero-width characters, and normalized line breaks.
        """
        # Non-breaking spaces and zero-width characters
        text = text.replace('\u00a0', ' ').replace('\xa0', ' ')
        text = text.replace('\ufeff', '').replace('\u200b', '').replace('\u200e', '').replace('\u200f', '')
        # Carriage returns
        text = text.replace('\r\n', '\n').replace('\r', '\n')
        # Unescape common escaped sequences
        text = text.replace('\\n', '\n').replace('\\t', '\t')
        return text


class ClausewitzLocLexer:
    """
    Resilient Lexer and Parser for Clausewitz .yml localization files.
    Tolerates unclosed quotes, broken escapes, multiline values, and encoding quirks.
    """

    def __init__(self, metrics: AuditMetrics):
        self.metrics = metrics

    def read_file_with_encoding_detection(self, file_path: Path) -> Tuple[str, str]:
        """
        Attempts to read the file using UTF-8-BOM, UTF-8, CP1251, or Latin-1.
        Returns: (file_content, detected_encoding)
        """
        raw_bytes = file_path.read_bytes()

        # Check UTF-8 BOM
        if raw_bytes.startswith(b'\xef\xbb\xbf'):
            self.metrics.files_per_encoding["UTF-8-BOM"] += 1
            return raw_bytes[3:].decode('utf-8', errors='replace'), "UTF-8-BOM"

        # Try standard UTF-8
        try:
            content = raw_bytes.decode('utf-8')
            self.metrics.files_per_encoding["UTF-8"] += 1
            return content, "UTF-8"
        except UnicodeDecodeError:
            pass

        # Try Windows-1251 (standard Russian codepage)
        try:
            content = raw_bytes.decode('cp1251')
            self.metrics.files_per_encoding["CP1251"] += 1
            return content, "CP1251"
        except UnicodeDecodeError:
            pass

        # Fallback to Latin-1
        content = raw_bytes.decode('latin-1', errors='replace')
        self.metrics.files_per_encoding["Latin-1-Fallback"] += 1
        return content, "Latin-1"

    def parse_file(self, file_path: Path, forced_lang: Optional[str] = None) -> Tuple[str, Dict[str, str]]:
        """
        Parses a single .yml localization file.
        Returns (language_code, {key: sanitized_value}).
        """
        content, _ = self.read_file_with_encoding_detection(file_path)
        lines = content.splitlines()

        detected_lang = forced_lang or "en"
        # Check first lines for language header
        for i in range(min(15, len(lines))):
            line_str = lines[i].strip()
            header_match = HEADER_RE.match(line_str)
            if header_match:
                hdr = header_match.group(1).lower()
                if "russ" in hdr:
                    detected_lang = "ru"
                elif "germ" in hdr:
                    detected_lang = "de"
                elif "engl" in hdr:
                    detected_lang = "en"
                else:
                    detected_lang = hdr
                break

        # Line-by-line parsing state machine
        entries: Dict[str, str] = {}
        in_multiline = False
        current_key = ""
        current_val_parts: List[str] = []

        for line_num, line in enumerate(lines, start=1):
            stripped = line.strip()

            # Skip comments when not accumulating a multiline string
            if not in_multiline:
                if not stripped or stripped.startswith('#'):
                    continue
                # Skip language headers
                if HEADER_RE.match(stripped):
                    continue

                # Match key definition
                key_match = KEY_START_RE.match(line)
                if key_match:
                    key, rest = key_match.groups()
                    current_key = key
                    self.metrics.total_raw_keys_parsed += 1

                    # Look for the closing quote
                    # Check if line ends with quote or quote before comment #
                    cleaned_rest = rest
                    # Check trailing comment
                    has_trailing_comment = False
                    comment_idx = cleaned_rest.rfind('#')
                    if comment_idx != -1:
                        # Ensure # is after closing quote
                        last_quote = cleaned_rest.rfind('"')
                        if last_quote != -1 and comment_idx > last_quote:
                            cleaned_rest = cleaned_rest[:comment_idx].rstrip()
                            has_trailing_comment = True

                    # Check if line ends with escaped quote typo like \" at end of line
                    if cleaned_rest.endswith('\\"'):
                        cleaned_rest = cleaned_rest[:-2] + '"'

                    if cleaned_rest.endswith('"'):
                        # Contained entirely on this single line
                        raw_value = cleaned_rest[:-1]
                        sanitized = self._sanitize_entry(raw_value, detected_lang)
                        if current_key in entries:
                            self.metrics.duplicate_keys_overridden += 1
                        entries[current_key] = sanitized
                        current_key = ""
                    else:
                        # Multiline string starts
                        in_multiline = True
                        current_val_parts = [cleaned_rest]
                else:
                    # Line without key definition; could be malformed line or syntax error
                    pass

            else:
                # We are in multiline mode
                # Check if this line actually starts a brand new key (meaning previous key lacked a closing quote)
                new_key_match = KEY_START_RE.match(line)
                if new_key_match or HEADER_RE.match(stripped):
                    # Previous multiline string was unclosed!
                    self.metrics.unclosed_quotes_repaired += 1
                    raw_value = "\n".join(current_val_parts)
                    sanitized = self._sanitize_entry(raw_value, detected_lang)
                    entries[current_key] = sanitized

                    # Reset and parse current line normally
                    in_multiline = False
                    current_key = ""
                    current_val_parts = []

                    if new_key_match:
                        key, rest = new_key_match.groups()
                        current_key = key
                        self.metrics.total_raw_keys_parsed += 1
                        if rest.strip().endswith('"'):
                            raw_value = rest.strip()[:-1]
                            sanitized = self._sanitize_entry(raw_value, detected_lang)
                            entries[current_key] = sanitized
                            current_key = ""
                        else:
                            in_multiline = True
                            current_val_parts = [rest]
                    continue

                # Continue accumulating multiline
                self.metrics.multiline_strings_stitched += 1
                cleaned_line = line.rstrip()

                # Check trailing comment
                comment_idx = cleaned_line.rfind('#')
                if comment_idx != -1:
                    last_quote = cleaned_line.rfind('"')
                    if last_quote != -1 and comment_idx > last_quote:
                        cleaned_line = cleaned_line[:comment_idx].rstrip()

                if cleaned_line.endswith('\\"'):
                    cleaned_line = cleaned_line[:-2] + '"'

                if cleaned_line.endswith('"'):
                    # Found the closing quote of the multiline block!
                    current_val_parts.append(cleaned_line[:-1])
                    in_multiline = False
                    raw_value = "\n".join(current_val_parts)
                    sanitized = self._sanitize_entry(raw_value, detected_lang)
                    if current_key in entries:
                        self.metrics.duplicate_keys_overridden += 1
                    entries[current_key] = sanitized
                    current_key = ""
                    current_val_parts = []
                else:
                    current_val_parts.append(cleaned_line)

        # Final cleanup if ended while still in multiline
        if in_multiline and current_key:
            self.metrics.unclosed_quotes_repaired += 1
            raw_value = "\n".join(current_val_parts)
            sanitized = self._sanitize_entry(raw_value, detected_lang)
            entries[current_key] = sanitized

        return detected_lang, entries

    def _sanitize_entry(self, text: str, lang: str) -> str:
        text = LocalizationSanitizer.clean_whitespaces_and_controls(text)
        text = LocalizationSanitizer.strip_color_tags(text, self.metrics)
        text = LocalizationSanitizer.fix_interior_quotes(text, lang, self.metrics)
        text = LocalizationSanitizer.normalize_tokens(text, self.metrics)
        return text.strip()


# ==============================================================================
# RECURSIVE REFERENCE RESOLVER ($KEY$)
# ==============================================================================

class NestedReferenceResolver:
    """
    Resolves Clausewitz nested string references ($KEY$ or $KEY|H$) recursively,
    with strict safeguards against infinite loops and circular dependencies.
    """

    def __init__(self, metrics: AuditMetrics, max_depth: int = 10):
        self.metrics = metrics
        self.max_depth = max_depth

    def resolve_dictionary(
        self,
        db: Dict[str, str],
        fallback_db: Optional[Dict[str, str]] = None
    ) -> Dict[str, str]:
        """
        Resolves all nested references in the given dictionary.
        """
        resolved_db: Dict[str, str] = {}
        for key, val in db.items():
            if "$" in val:
                resolved_db[key] = self._resolve_string(val, key, db, fallback_db, set(), 0)
            else:
                resolved_db[key] = val
        return resolved_db

    def _resolve_string(
        self,
        text: str,
        root_key: str,
        primary_db: Dict[str, str],
        fallback_db: Optional[Dict[str, str]],
        visited: Set[str],
        depth: int
    ) -> str:
        if "$" not in text or depth > self.max_depth:
            return text

        def _sub_match(match: re.Match) -> str:
            ref_key = match.group(1)

            # Check if this reference is a dynamic template variable
            if ref_key.upper() in TEMPLATE_VARS_MAP:
                self.metrics.dollar_refs_resolved += 1
                return TEMPLATE_VARS_MAP[ref_key.upper()]

            # Check cycle
            if ref_key in visited or ref_key == root_key:
                self.metrics.circular_refs_prevented += 1
                self.metrics.critical_errors.append(
                    f"Circular reference detected: '{root_key}' -> '${ref_key}$'"
                )
                return f"{{{ref_key.lower()}}}"

            # Look up in primary db
            target_val = primary_db.get(ref_key)
            if target_val is None and fallback_db:
                target_val = fallback_db.get(ref_key)

            if target_val is not None:
                self.metrics.dollar_refs_resolved += 1
                if "$" in target_val:
                    new_visited = visited | {ref_key}
                    return self._resolve_string(
                        target_val, root_key, primary_db, fallback_db, new_visited, depth + 1
                    )
                return target_val

            # Key not found in localization dictionaries
            self.metrics.dollar_refs_unresolved += 1
            # Gracefully convert to placeholder token
            return f"{{{ref_key.lower()}}}"

        resolved = DOLLAR_REF_RE.sub(_sub_match, text)
        return resolved


# ==============================================================================
# GAME KEY AUDITOR
# ==============================================================================

class GameKeyAuditor:
    """
    Audits localization keys against actual usage in game JSONs:
    - events/ (titles, descriptions, options)
    - countries/ (names, leaders, descriptions, country events)
    - directives/ / focus trees
    """

    def __init__(self, game_data_dir: Path):
        self.game_data_dir = game_data_dir

    def collect_requested_keys(self) -> Set[str]:
        requested: Set[str] = set()
        if not self.game_data_dir.exists():
            return requested

        # 1. Scan events/
        events_dir = self.game_data_dir / "events"
        if events_dir.exists():
            for fpath in events_dir.glob("*.json"):
                self._extract_keys_from_json(fpath, requested)

        # 2. Scan extracted/ (directives_trees.json, etc.)
        extracted_dir = self.game_data_dir / "extracted"
        if extracted_dir.exists():
            for fpath in extracted_dir.glob("*.json"):
                self._extract_keys_from_json(fpath, requested)

        # 3. Scan countries/
        countries_dir = self.game_data_dir / "countries"
        if countries_dir.exists():
            for fpath in countries_dir.glob("**/*.json"):
                # Skip localization subfolders in countries
                if "localisation" in fpath.parts:
                    continue
                self._extract_keys_from_json(fpath, requested)

        return requested

    def _extract_keys_from_json(self, file_path: Path, out_keys: Set[str]) -> None:
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            self._walk_and_collect(data, out_keys)
        except Exception:
            pass

    def _walk_and_collect(self, obj: Any, out_keys: Set[str]) -> None:
        if isinstance(obj, dict):
            for k, v in obj.items():
                if k in ("title", "desc", "text", "name", "country_name", "leader_name", "spirit_id", "tag"):
                    if isinstance(v, str) and v and not v.startswith("{") and len(v) < 80:
                        # Potential key
                        if re.match(r'^[A-Za-z0-9_.\-]+$', v):
                            out_keys.add(v)
                self._walk_and_collect(v, out_keys)
        elif isinstance(obj, list):
            for item in obj:
                self._walk_and_collect(item, out_keys)


# ==============================================================================
# MAIN PIPELINE & LAYER CASCADE
# ==============================================================================

class LocalizationFixerPipeline:
    """
    Orchestrates scanning, parsing, cascading, auditing, and exporting.
    """

    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.metrics = AuditMetrics()
        self.lexer = ClausewitzLocLexer(self.metrics)
        self.resolver = NestedReferenceResolver(self.metrics)
        self.output_dir = Path(args.output_dir).resolve()
        self.countries_dir = Path(args.countries_dir).resolve()
        self.game_data_dir = Path(args.game_data).resolve()

        # Database layers
        self.base_tno_en: Dict[str, str] = {}
        self.submod_en: Dict[str, str] = {}
        self.tno_ru: Dict[str, str] = {}
        self.submod_ru: Dict[str, str] = {}

        # Merged final dictionaries
        self.final_en: Dict[str, str] = {}
        self.final_ru: Dict[str, str] = {}

    def run(self) -> int:
        t_start = time.time()
        self._print_header("TNO LOCALIZATION AUDIT & NORMALIZATION PIPELINE")

        # 1. Scan and Parse Layers
        self._load_layers()

        # 2. Merge Cascades
        self._cascade_merge()

        # 3. Resolve Nested References
        self._resolve_references()

        # 4. Integrate Existing Project UI Strings
        self._merge_existing_project_strings()

        # 5. Audit Game Keys
        self._audit_game_keys()

        # 6. Export Target Deliverables
        self._export_data()

        # 7. Generate Audit Report
        report_path = self._generate_report(time.time() - t_start)

        # 8. Strict Mode Validation Check
        if self.args.strict and self.metrics.critical_errors:
            print(f"\n[PIPELINE] [STRICT MODE FAILED] Encountered {len(self.metrics.critical_errors)} critical errors.")
            return 1

        print("\n[PIPELINE] Localization audit and normalization completed successfully.")
        print(f"[PIPELINE] Audit Report written to: {report_path}")
        return 0

    def _print_header(self, title: str) -> None:
        print("=" * 80)
        print(f"  {title}")
        print("=" * 80)

    def _scan_directory(self, base_path: Optional[str], target_lang: str) -> Dict[str, str]:
        if not base_path:
            return {}
        p = Path(base_path)
        if not p.exists():
            print(f"[PIPELINE] [WARN] Source path does not exist: {base_path}")
            return {}

        # Look for localisation subfolder if root was passed
        loc_dir = p / "localisation" if (p / "localisation").is_dir() else p

        files = list(loc_dir.glob("**/*.yml")) + list(loc_dir.glob("**/*.yaml"))
        self.metrics.total_files_scanned += len(files)
        print(f"[PIPELINE] Scanning {len(files)} files in: {loc_dir}")

        aggregated: Dict[str, str] = {}
        for f in files:
            lang, entries = self.lexer.parse_file(f, forced_lang=target_lang)
            for k, v in entries.items():
                aggregated[k] = v

        print(f"           -> Loaded {len(aggregated):,} unique keys ({target_lang})")
        return aggregated

    def _load_layers(self) -> None:
        print("\n[STEP 1/6] Loading source mod layers...")
        # Layer 1: Base TNO EN (Fallback EN)
        self.base_tno_en = self._scan_directory(self.args.tno_mod, "en")
        # Layer 2: Submod EN (2WRW)
        self.submod_en = self._scan_directory(self.args.submod, "en")
        # Layer 3: Official TNO Russian
        self.tno_ru = self._scan_directory(self.args.tno_ru, "ru")
        # Layer 4: Submod Russian (2WRW)
        self.submod_ru = self._scan_directory(self.args.submod_ru, "ru")

    def _cascade_merge(self) -> None:
        print("\n[STEP 2/6] Performing layered cascade merge...")
        # English: Submod EN overrides Base TNO EN
        self.final_en = dict(self.base_tno_en)
        self.final_en.update(self.submod_en)

        # Russian: Submod RU overrides Official TNO RU
        base_ru = dict(self.tno_ru)
        base_ru.update(self.submod_ru)

        # Fallback handling: for every key in EN that lacks RU translation,
        # copy EN text into RU database
        self.final_ru = dict(base_ru)
        mark = self.args.mark_untranslated

        for k, en_val in self.final_en.items():
            if k not in self.final_ru:
                self.metrics.untranslated_fallbacks_used += 1
                if mark:
                    self.final_ru[k] = f"[UNTRANSLATED] {en_val}"
                else:
                    self.final_ru[k] = en_val

        print(f"           -> Total EN keys: {len(self.final_en):,}")
        print(f"           -> Total RU keys: {len(self.final_ru):,} (including {self.metrics.untranslated_fallbacks_used:,} EN fallbacks)")

    def _resolve_references(self) -> None:
        print("\n[STEP 3/6] Recursively resolving nested string references ($KEY$)...")
        self.final_en = self.resolver.resolve_dictionary(self.final_en)
        self.final_ru = self.resolver.resolve_dictionary(self.final_ru, fallback_db=self.final_en)
        print(f"           -> Resolved references: {self.metrics.dollar_refs_resolved:,}")
        print(f"           -> Circular references prevented: {self.metrics.circular_refs_prevented:,}")

    def _merge_existing_project_strings(self) -> None:
        """
        Preserves custom UI strings present in data/localization/strings_ru.json
        (e.g., SYS_TITLE, BTN_END_TURN, PREVIEW_CRISIS_BODY).
        """
        print("\n[STEP 4/6] Integrating existing project UI localization keys...")
        project_ru = self.output_dir / "strings_ru.json"
        project_en = self.output_dir / "strings_en.json"

        def _merge_file(target_file: Path, target_dict: Dict[str, str]):
            if target_file.exists():
                try:
                    with open(target_file, "r", encoding="utf-8") as f:
                        data = json.load(f)
                        strings = data.get("strings", {})
                        count = 0
                        for k, v in strings.items():
                            target_dict[k] = v
                            count += 1
                        print(f"           -> Merged {count} custom UI keys from {target_file.name}")
                except Exception as e:
                    print(f"[PIPELINE] [WARN] Could not read {target_file}: {e}")

        _merge_file(project_ru, self.final_ru)
        _merge_file(project_en, self.final_en)

    def _audit_game_keys(self) -> None:
        print("\n[STEP 5/6] Auditing game data key usage...")
        auditor = GameKeyAuditor(self.game_data_dir)
        requested_keys = auditor.collect_requested_keys()
        print(f"           -> Found {len(requested_keys):,} string keys referenced in game data")

        missing_ru = []
        for k in requested_keys:
            if k not in self.final_ru:
                missing_ru.append(k)

        self.metrics.missing_game_keys = sorted(missing_ru)
        print(f"           -> Missing keys in RU database: {len(missing_ru):,}")

    def _export_data(self) -> None:
        print("\n[STEP 6/6] Exporting deliverables (JSON, Country Packs, SQLite DB)...")
        self.output_dir.mkdir(parents=True, exist_ok=True)

        # 1. Global JSONs
        ru_payload = {
            "locale": "ru",
            "name": "Русский",
            "pack_id": "RUS_LOC_PACK_TNO_NORMALIZED",
            "total_strings": len(self.final_ru),
            "status": "ACTIVE",
            "strings": self.final_ru
        }
        en_payload = {
            "locale": "en",
            "name": "English",
            "pack_id": "ENG_LOC_PACK_TNO_NORMALIZED",
            "total_strings": len(self.final_en),
            "status": "READY",
            "strings": self.final_en
        }

        # Write strings_ru.json & strings_en.json
        with open(self.output_dir / "strings_ru.json", "w", encoding="utf-8") as f:
            json.dump(ru_payload, f, ensure_ascii=False, indent=2)
        with open(self.output_dir / "strings_en.json", "w", encoding="utf-8") as f:
            json.dump(en_payload, f, ensure_ascii=False, indent=2)

        # Write aliases ru.json & en.json
        with open(self.output_dir / "ru.json", "w", encoding="utf-8") as f:
            json.dump(ru_payload, f, ensure_ascii=False, indent=2)
        with open(self.output_dir / "en.json", "w", encoding="utf-8") as f:
            json.dump(en_payload, f, ensure_ascii=False, indent=2)

        print(f"           -> Exported global strings_ru.json ({len(self.final_ru):,} keys)")
        print(f"           -> Exported global strings_en.json ({len(self.final_en):,} keys)")

        # 2. Modular Country Packages
        country_tags = self._collect_country_tags()
        exported_countries = 0

        for tag in country_tags:
            tag_prefix = f"{tag}_"
            ru_tag_strings = {}
            en_tag_strings = {}

            # Collect keys starting with TAG_ or exactly TAG
            for k, v in self.final_ru.items():
                if k == tag or k.startswith(tag_prefix):
                    ru_tag_strings[k] = v

            for k, v in self.final_en.items():
                if k == tag or k.startswith(tag_prefix):
                    en_tag_strings[k] = v

            if ru_tag_strings or en_tag_strings:
                country_loc_dir = self.countries_dir / tag / "localisation"
                country_loc_dir.mkdir(parents=True, exist_ok=True)

                c_ru = {
                    "locale": "ru",
                    "country_tag": tag,
                    "total_strings": len(ru_tag_strings),
                    "strings": ru_tag_strings
                }
                c_en = {
                    "locale": "en",
                    "country_tag": tag,
                    "total_strings": len(en_tag_strings),
                    "strings": en_tag_strings
                }

                with open(country_loc_dir / "ru.json", "w", encoding="utf-8") as f:
                    json.dump(c_ru, f, ensure_ascii=False, indent=2)
                with open(country_loc_dir / "en.json", "w", encoding="utf-8") as f:
                    json.dump(c_en, f, ensure_ascii=False, indent=2)
                exported_countries += 1

        print(f"           -> Exported modular packages for {exported_countries} countries in {self.countries_dir}")

        # 3. SQLite Database
        if self.args.export_sqlite:
            self._export_sqlite()

    def _collect_country_tags(self) -> List[str]:
        tags = []
        if self.countries_dir.exists():
            for item in self.countries_dir.iterdir():
                if item.is_dir() and len(item.name) == 3 and item.name.isupper():
                    tags.append(item.name)
        return sorted(tags)

    def _export_sqlite(self) -> None:
        db_path = self.output_dir / "localization_db.sqlite"
        print(f"           -> Building indexed SQLite database: {db_path}...")
        if db_path.exists():
            db_path.unlink()

        conn = sqlite3.connect(str(db_path))
        cur = conn.cursor()

        cur.execute("PRAGMA synchronous = OFF;")
        cur.execute("PRAGMA journal_mode = MEMORY;")

        cur.execute("""
            CREATE TABLE strings (
                key TEXT PRIMARY KEY,
                ru TEXT,
                en TEXT
            );
        """)
        cur.execute("CREATE INDEX idx_strings_key ON strings(key);")

        all_keys = set(self.final_ru.keys()) | set(self.final_en.keys())
        batch_data = []

        for k in all_keys:
            r_val = self.final_ru.get(k, "")
            e_val = self.final_en.get(k, "")
            batch_data.append((k, r_val, e_val))

        cur.executemany("INSERT INTO strings (key, ru, en) VALUES (?, ?, ?);", batch_data)
        conn.commit()
        conn.close()

        size_mb = db_path.stat().st_size / (1024 * 1024)
        print(f"           -> SQLite DB created: {len(all_keys):,} rows, {size_mb:.2f} MB")

    def _generate_report(self, duration_sec: float) -> Path:
        all_keys_count = len(set(self.final_ru.keys()) | set(self.final_en.keys()))
        ru_native_count = len(self.final_ru) - self.metrics.untranslated_fallbacks_used
        ru_coverage_pct = (ru_native_count / max(1, len(self.final_en))) * 100.0

        print("\n" + "=" * 80)
        print("  LOCALIZATION AUDIT & NORMALIZATION SUMMARY")
        print("=" * 80)
        print(f"  Execution Time:               {duration_sec:.2f} seconds")
        print(f"  Files Scanned:                {self.metrics.total_files_scanned:,}")
        for enc, count in self.metrics.files_per_encoding.items():
            print(f"    - {enc:22}: {count:,} files")
        print(f"  Raw Keys Parsed:              {self.metrics.total_raw_keys_parsed:,}")
        print(f"  Duplicate Overrides:          {self.metrics.duplicate_keys_overridden:,}")
        print("-" * 80)
        print("  SYNTAX & REPAIR STATS:")
        print(f"  - Multiline Strings Stitched: {self.metrics.multiline_strings_stitched:,}")
        print(f"  - Unclosed Quotes Repaired:   {self.metrics.unclosed_quotes_repaired:,}")
        print(f"  - Interior Quotes Fixed («»): {self.metrics.interior_quotes_fixed:,}")
        print(f"  - Color Tags Stripped (§Y...):{self.metrics.color_tags_stripped:,}")
        print(f"  - Tokens Normalized (HoI4):   {self.metrics.tokens_normalized:,}")
        print(f"  - Dollar Refs Resolved ($K$): {self.metrics.dollar_refs_resolved:,}")
        print(f"  - Circular Refs Blocked:      {self.metrics.circular_refs_prevented:,}")
        print("-" * 80)
        print("  COVERAGE & AUDIT STATS:")
        print(f"  - Total Unique Keys:          {all_keys_count:,}")
        print(f"  - English Keys:               {len(self.final_en):,}")
        print(f"  - Russian Native Translated:  {ru_native_count:,}")
        print(f"  - Fallback Untranslated Keys: {self.metrics.untranslated_fallbacks_used:,}")
        print(f"  - RU vs EN Native Coverage:   {ru_coverage_pct:.1f}%")
        print(f"  - Missing Game Keys:          {len(self.metrics.missing_game_keys):,}")
        print("=" * 80)

        # Write markdown report
        report_path = self.output_dir / "localization_audit_report.md"
        with open(report_path, "w", encoding="utf-8") as f:
            f.write("# TNO Localization Audit & Normalization Report\n\n")
            f.write(f"**Date:** {time.strftime('%Y-%m-%d %H:%M:%S')}  \n")
            f.write(f"**Execution Duration:** {duration_sec:.2f} seconds  \n\n")

            f.write("## 1. Executive Summary\n\n")
            f.write("| Metric | Value |\n")
            f.write("| :--- | :--- |\n")
            f.write(f"| **Total Files Scanned** | {self.metrics.total_files_scanned:,} |\n")
            f.write(f"| **Total Unique Keys** | {all_keys_count:,} |\n")
            f.write(f"| **English Keys** | {len(self.final_en):,} |\n")
            f.write(f"| **Russian Native Keys** | {ru_native_count:,} |\n")
            f.write(f"| **Untranslated Fallback Keys** | {self.metrics.untranslated_fallbacks_used:,} |\n")
            f.write(f"| **Translation Coverage (RU/EN)** | **{ru_coverage_pct:.1f}%** |\n\n")

            f.write("## 2. Syntax Cleaning & Normalization\n\n")
            f.write("| Repair Category | Count |\n")
            f.write("| :--- | :--- |\n")
            f.write(f"| Multiline Strings Stitched | {self.metrics.multiline_strings_stitched:,} |\n")
            f.write(f"| Unclosed Quotes Repaired | {self.metrics.unclosed_quotes_repaired:,} |\n")
            f.write(f"| Interior Quotes Fixed (`« »`) | {self.metrics.interior_quotes_fixed:,} |\n")
            f.write(f"| Clausewitz Color Tags Stripped (`§.`) | {self.metrics.color_tags_stripped:,} |\n")
            f.write(f"| HoI4 Tokens Normalized to `{'{param}'}` | {self.metrics.tokens_normalized:,} |\n")
            f.write(f"| Nested `$KEY$` References Resolved | {self.metrics.dollar_refs_resolved:,} |\n")
            f.write(f"| Circular References Prevented | {self.metrics.circular_refs_prevented:,} |\n\n")

            f.write("## 3. Top Missing Keys Requested by Game\n\n")
            if self.metrics.missing_game_keys:
                f.write(f"Found **{len(self.metrics.missing_game_keys)}** keys requested by game data but absent from text catalogs.\n\n")
                f.write("| # | Missing Key Name |\n")
                f.write("| :--- | :--- |\n")
                for idx, mk in enumerate(self.metrics.missing_game_keys[:50], start=1):
                    f.write(f"| {idx} | `{mk}` |\n")
                if len(self.metrics.missing_game_keys) > 50:
                    f.write(f"| ... | *and {len(self.metrics.missing_game_keys) - 50} more keys* |\n")
            else:
                f.write("All game data keys are present in localization databases.\n")

        return report_path


# ==============================================================================
# CLI ENTRY POINT
# ==============================================================================

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="TNO & Submods Localization Fixer & Audit Pipeline for Godot 4",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument(
        "--tno-mod",
        default=r"F:\SteamLibrary\steamapps\workshop\content\394360\2438003901",
        help="Path to base TNO mod root or localisation folder"
    )
    parser.add_argument(
        "--submod",
        default=r"F:\SteamLibrary\steamapps\workshop\content\394360\3579472890",
        help="Path to 2WRW submod root or localisation folder"
    )
    parser.add_argument(
        "--tno-ru",
        default=r"F:\SteamLibrary\steamapps\workshop\content\394360\2351077206",
        help="Path to official TNO Russian translation mod"
    )
    parser.add_argument(
        "--submod-ru",
        default=r"F:\SteamLibrary\steamapps\workshop\content\394360\3753104676",
        help="Path to 2WRW Russian translation submod"
    )
    parser.add_argument(
        "--game-data",
        default="data",
        help="Path to Godot game project data/ directory"
    )
    parser.add_argument(
        "--output-dir",
        default="data/localization",
        help="Destination directory for global localization JSONs and SQLite DB"
    )
    parser.add_argument(
        "--countries-dir",
        default="data/countries",
        help="Path to data/countries/ directory for modular country packs"
    )
    parser.add_argument(
        "--export-sqlite",
        action="store_true",
        default=True,
        help="Generate localization_db.sqlite"
    )
    parser.add_argument(
        "--mark-untranslated",
        action="store_true",
        default=False,
        help="Prefix untranslated English fallbacks in RU database with [UNTRANSLATED]"
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        default=False,
        help="Exit with non-zero code if critical syntax errors or circular references occur"
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    pipeline = LocalizationFixerPipeline(args)
    sys.exit(pipeline.run())


if __name__ == "__main__":
    main()
