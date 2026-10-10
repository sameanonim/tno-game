#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Batch enriches and normalizes all narrative event JSON files:
- Resolves raw keys or empty titles/descs using strings_ru.json (fallback: strings_en.json)
- Cleans Paradox color codes (§Y, §!, etc.)
- Ensures all events have at least 1 valid option (adds "ПРИНЯТЬ К СВЕДЕНИЮ" if empty)
- Normalizes options from dict/array into clean array
"""

import os
import glob
import json
import re
import time

COLOR_TAG_REGEX = re.compile(r"§[A-Za-z0-9!_,\^%\-\+=]")
COLOR_TAG_FALLBACK = re.compile(r"§.")

def clean_paradox(text: str) -> str:
    if not text or "§" not in text:
        return text or ""
    c = COLOR_TAG_REGEX.sub("", text)
    if "§" in c:
        c = COLOR_TAG_FALLBACK.sub("", c)
    return c.strip()

def load_loc_dict(path: str) -> dict:
    if not os.path.exists(path):
        return {}
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data.get("strings", {})

def enrich_all_events():
    t0 = time.time()
    print("Loading localization dictionaries...")
    ru_strings = load_loc_dict("data/localization/strings_ru.json")
    en_strings = load_loc_dict("data/localization/strings_en.json")
    print(f"Loaded RU ({len(ru_strings)} keys), EN ({len(en_strings)} keys)")

    def get_loc(k: str) -> str:
        if not k:
            return ""
        val = ru_strings.get(k, en_strings.get(k, ""))
        return clean_paradox(val) if val else ""

    files_to_process = []
    files_to_process.extend(glob.glob("data/countries/*/events.json"))
    files_to_process.append("data/events/news_events.json")
    files_to_process.append("data/events/global_events.json")

    total_events_updated = 0
    total_titles_fixed = 0
    total_descs_fixed = 0
    total_opts_fixed = 0
    files_modified = 0

    opt_letters = ["a", "b", "c", "d", "e", "f", "g", "h"]

    for fpath in files_to_process:
        if os.path.getsize(fpath) <= 5:
            continue
        try:
            with open(fpath, "r", encoding="utf-8") as f:
                raw_data = json.load(f)
        except Exception as e:
            continue

        is_dict = isinstance(raw_data, dict)
        items = list(raw_data.items()) if is_dict else list(enumerate(raw_data))
        file_changed = False

        for k, ev in items:
            if not isinstance(ev, dict):
                continue
            eid = str(ev.get("event_id", ev.get("id", k if is_dict else "")))
            if not eid:
                continue

            # 1. Title
            cur_title = clean_paradox(str(ev.get("title", ev.get("name", ""))))
            is_loc_key = not cur_title or (
                " " not in cur_title and (
                    cur_title.endswith(".t") or cur_title.endswith(".title") or
                    cur_title.endswith(".name") or cur_title.startswith("GFX_") or
                    cur_title.startswith("tno_")
                )
            )
            if is_loc_key:
                resolved_t = get_loc(cur_title) or get_loc(eid + ".t") or get_loc(eid + ".title") or get_loc(eid + ".name")
                if resolved_t:
                    ev["title"] = resolved_t
                    file_changed = True
                    total_titles_fixed += 1
                elif not cur_title:
                    ev["title"] = "ДОНЕСЕНИЕ: " + eid.upper().replace(".", " / ")
                    file_changed = True
                    total_titles_fixed += 1
                else:
                    ev["title"] = cur_title
            else:
                if cur_title != ev.get("title"):
                    ev["title"] = cur_title
                    file_changed = True

            # 2. Description
            cur_desc = clean_paradox(str(ev.get("description", ev.get("desc", ev.get("text", "")))))
            is_desc_key = not cur_desc or (
                " " not in cur_desc and (
                    cur_desc.endswith(".d") or cur_desc.endswith(".desc")
                )
            )
            if is_desc_key:
                resolved_d = get_loc(cur_desc) or get_loc(eid + ".d") or get_loc(eid + ".desc")
                if resolved_d:
                    ev["description"] = resolved_d
                    ev["desc"] = resolved_d
                    file_changed = True
                    total_descs_fixed += 1
                elif not cur_desc:
                    ev["description"] = f"Экстренная депеша по обстановке в регионе [{eid}]. Требуется решение ставки."
                    ev["desc"] = ev["description"]
                    file_changed = True
                    total_descs_fixed += 1
                else:
                    ev["description"] = cur_desc
                    ev["desc"] = cur_desc
            else:
                if cur_desc != ev.get("description") or cur_desc != ev.get("desc"):
                    ev["description"] = cur_desc
                    ev["desc"] = cur_desc
                    file_changed = True

            # 3. Options
            raw_opts = ev.get("options", ev.get("option", []))
            opts_list = []
            if isinstance(raw_opts, dict):
                opts_list = [v for v in raw_opts.values() if isinstance(v, dict)]
            elif isinstance(raw_opts, list):
                opts_list = raw_opts

            norm_opts = []
            for o_idx, opt in enumerate(opts_list):
                if isinstance(opt, dict):
                    opt_copy = dict(opt)
                    otext = clean_paradox(str(opt_copy.get("text", opt_copy.get("name", ""))))
                    nkey = str(opt_copy.get("name_key", ""))
                    suffix = opt_letters[o_idx] if o_idx < len(opt_letters) else str(o_idx)

                    if not otext or (" " not in otext and (otext.endswith("." + suffix) or otext == nkey)):
                        resolved_opt = get_loc(otext) or get_loc(nkey) or get_loc(f"{eid}.{suffix}")
                        if resolved_opt:
                            otext = resolved_opt
                        elif not otext:
                            otext = "ПРИНЯТЬ К СВЕДЕНИЮ" if o_idx == 0 else f"ВАРИАНТ {o_idx + 1}"

                    opt_copy["text"] = otext
                    opt_copy["name"] = otext
                    norm_opts.append(opt_copy)
                else:
                    norm_opts.append(opt)

            if not norm_opts:
                norm_opts.append({
                    "name": "ПРИНЯТЬ К СВЕДЕНИЮ",
                    "text": "ПРИНЯТЬ К СВЕДЕНИЮ",
                    "name_key": "OK",
                    "effects": {}
                })
                total_opts_fixed += 1
                file_changed = True

            ev["options"] = norm_opts
            total_events_updated += 1

        if file_changed:
            files_modified += 1
            with open(fpath, "w", encoding="utf-8") as out_f:
                json.dump(raw_data, out_f, ensure_ascii=False, indent=2)

    print(f"Batch enrichment completed in {time.time() - t0:.2f}s:")
    print(f"  Files modified: {files_modified}")
    print(f"  Total events evaluated: {total_events_updated}")
    print(f"  Titles enriched: {total_titles_fixed}")
    print(f"  Descriptions enriched: {total_descs_fixed}")
    print(f"  Empty option fallbacks injected: {total_opts_fixed}")

if __name__ == "__main__":
    enrich_all_events()
