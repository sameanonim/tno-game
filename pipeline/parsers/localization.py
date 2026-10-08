"""
Paradox Localization (.yml) Parser
==================================
Handles UTF-8-BOM encoding, Paradox formatting tags, and language namespaces.
"""

from pathlib import Path
import re
from typing import Dict, Optional, Tuple, Union


# Regex to match Paradox localization line: KEY:0 "Text" or KEY: "Text"
LOC_LINE_RE = re.compile(r'^\s*([A-Za-z0-9_.\-]+):[0-9]*\s*"(.*)"\s*$')

# Regex to strip Paradox color tags (§Y, §!, §R, §G, §B, etc.) and icon tags (£name)
COLOR_TAG_RE = re.compile(r'§[A-Za-z0-9!_]')
ICON_TAG_RE = re.compile(r'£[A-Za-z0-9_]+')


def clean_loc_string(raw_text: str, keep_icons: bool = False) -> str:
    """Cleans color tags, quotes and formatting characters."""
    if not raw_text:
        return ""
    cleaned = raw_text.replace('\\"', '"').replace('\\n', '\n')
    cleaned = COLOR_TAG_RE.sub('', cleaned)
    if not keep_icons:
        cleaned = ICON_TAG_RE.sub('', cleaned)
    return cleaned.strip()


def parse_loc_text(text: str) -> Tuple[str, Dict[str, str]]:
    """
    Parses a single localization file content.
    Returns (language_tag, {key: clean_text}).
    """
    language = "english"
    entries: Dict[str, str] = {}

    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        if stripped.startswith("l_") and stripped.endswith(":"):
            language = stripped[2:-1].lower()
            continue

        match = LOC_LINE_RE.match(line)
        if match:
            key, raw_val = match.groups()
            entries[key] = clean_loc_string(raw_val)

    return language, entries


def parse_loc_file(file_path: Union[str, Path]) -> Tuple[str, Dict[str, str]]:
    """Parses a localization file with robust encoding."""
    path = Path(file_path)
    for enc in ("utf-8-sig", "utf-8", "cp1252", "latin-1"):
        try:
            with open(path, "r", encoding=enc) as f:
                content = f.read()
            return parse_loc_text(content)
        except (UnicodeDecodeError, UnicodeError):
            continue

    with open(path, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()
    return parse_loc_text(content)
