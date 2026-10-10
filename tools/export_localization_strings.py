#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Exports clean Russian and English localization dictionaries from localization_db.json
into data/localization/strings_ru.json and data/localization/strings_en.json.
Also strips Paradox formatting codes like §Y, §!, etc.
"""

import os
import re
import json
import time

LOCALIZATION_DIR = "data/localization"
DB_PATH = os.path.join(LOCALIZATION_DIR, "localization_db.json")

# Match Paradox color tags: §Y, §!, §R, §G, §B, §C, §H, §O, §L, §W, etc.
COLOR_TAG_REGEX = re.compile(r"§[A-Za-z0-9!_,\^%\-\+=]")
COLOR_TAG_FALLBACK = re.compile(r"§.")

def clean_paradox_text(text: str) -> str:
    if not text or "§" not in text:
        return text
    cleaned = COLOR_TAG_REGEX.sub("", text)
    if "§" in cleaned:
        cleaned = COLOR_TAG_FALLBACK.sub("", cleaned)
    return cleaned

def export_locales(target_locales=("russian", "english")):
    t0 = time.time()
    print(f"Reading and extracting {target_locales} from {DB_PATH}...")
    
    extracted = {loc: {} for loc in target_locales}
    cur_locale = None
    
    with open(DB_PATH, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            l = line.strip()
            if not l:
                continue
            
            # Check for locale block start, e.g. "russian": { or "english": {
            if l.startswith('"') and l.endswith('": {') and cur_locale is None:
                loc_name = l.split('"')[1]
                if loc_name in target_locales:
                    cur_locale = loc_name
                    print(f"  -> Found section: {cur_locale}")
                continue
            
            # Check for section end
            if cur_locale and (l.startswith("},") or l == "}"):
                print(f"  -> Finished section: {cur_locale} with {len(extracted[cur_locale])} strings.")
                cur_locale = None
                continue
            
            # Key-value line inside target locale
            if cur_locale and l.startswith('"'):
                try:
                    colon_idx = l.find('": "')
                    if colon_idx != -1:
                        key = l[1:colon_idx]
                        # Trim trailing comma and quote
                        val_str = l[colon_idx + 4:]
                        if val_str.endswith(","):
                            val_str = val_str[:-1]
                        if val_str.endswith('"'):
                            val_str = val_str[:-1]
                        
                        # Unescape json string
                        try:
                            # Safely unescape standard escapes
                            val_decoded = json.loads('"' + val_str + '"')
                        except Exception:
                            val_decoded = val_str.replace('\\"', '"').replace('\\n', '\n').replace('\\\\', '\\')
                        
                        val_cleaned = clean_paradox_text(val_decoded)
                        extracted[cur_locale][key] = val_cleaned
                except Exception:
                    continue

    locale_map = {
        "russian": "ru",
        "english": "en"
    }

    for loc_name, strings in extracted.items():
        short_code = locale_map.get(loc_name, loc_name)
        out_path = os.path.join(LOCALIZATION_DIR, f"strings_{short_code}.json")
        print(f"Writing {len(strings)} strings to {out_path}...")
        payload = {
            "locale": short_code,
            "version": "1.0",
            "strings": strings
        }
        with open(out_path, "w", encoding="utf-8") as out_f:
            json.dump(payload, out_f, ensure_ascii=False, indent=2)
        print(f"Saved {out_path} ({os.path.getsize(out_path)} bytes).")

    print(f"Done in {time.time() - t0:.2f} seconds.")

if __name__ == "__main__":
    export_locales()
