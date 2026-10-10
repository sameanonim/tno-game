#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Intelligent master events indexer:
Preserves correct country ownership (e.g. KOM for komi_*, GER for ger_*, news for news.*)
and indexes all 105k+ events into data/events/events_index.json.
"""

import os
import glob
import json
import time

def extract_tag_from_event_id(event_id: str) -> str:
    eid_lower = event_id.lower()
    if eid_lower.startswith("news."):
        return "NEWS"
    if eid_lower.startswith("komi") or eid_lower.startswith("kom_") or eid_lower.startswith("kom."):
        return "KOM"
    if eid_lower.startswith("usa") or eid_lower.startswith("aat_usa") or eid_lower.startswith("nixon") or eid_lower.startswith("kennedy") or eid_lower.startswith("johnson"):
        return "USA"
    if eid_lower.startswith("ger") or eid_lower.startswith("hitler") or eid_lower.startswith("gcw") or eid_lower.startswith("bormann") or eid_lower.startswith("speer") or eid_lower.startswith("goering") or eid_lower.startswith("heydrich"):
        return "GER"
    if eid_lower.startswith("jap") or eid_lower.startswith("japan") or eid_lower.startswith("yasuda") or eid_lower.startswith("diet"):
        return "JAP"
    if eid_lower.startswith("ita") or eid_lower.startswith("italy") or eid_lower.startswith("ciano") or eid_lower.startswith("scorza"):
        return "ITA"
    if eid_lower.startswith("oms") or eid_lower.startswith("omsk") or eid_lower.startswith("yazov"):
        return "OMS"
    if eid_lower.startswith("wrs") or eid_lower.startswith("zhukov") or eid_lower.startswith("tukhachevsky"):
        return "WRS"
    if eid_lower.startswith("sam") or eid_lower.startswith("vlasov"):
        return "SAM"
    if eid_lower.startswith("zlt") or eid_lower.startswith("zlatoust"):
        return "ZLT"
    if eid_lower.startswith("vor") or eid_lower.startswith("vorkuta"):
        return "VOR"

    # Generic check for <TAG>_ or <TAG>.
    parts = event_id.replace(".", "_").split("_")
    if len(parts) > 1 and len(parts[0]) == 3 and parts[0].isalpha():
        return parts[0].upper()
    return ""

def rebuild_events_index():
    t0 = time.time()
    
    # event_id -> (priority: int, res_path: str)
    # Higher priority wins.
    # Priority scale:
    # 100: Exact Tag match (e.g. komi_friendship.1 in KOM/events.json, news.* in news_events.json)
    # 50: Country native file (if event was found in the matching country)
    # 30: news_events.json / global_events.json
    # 10: Secondary country file
    # 1: Generic dump file (e.g. VEN, SKN, etc.)
    
    scored_index = {}
    
    # 1. News events
    news_path = "data/events/news_events.json"
    if os.path.exists(news_path):
        with open(news_path, "r", encoding="utf-8") as f:
            ndata = json.load(f)
        items = ndata.items() if isinstance(ndata, dict) else [(x.get("id", x.get("event_id", "")), x) for x in ndata if isinstance(x, dict)]
        for eid, _ in items:
            if eid:
                s_eid = str(eid)
                pri = 100 if s_eid.lower().startswith("news.") else 40
                scored_index[s_eid] = (pri, "res://data/events/news_events.json")

    # 2. Country events
    country_dirs = sorted(glob.glob("data/countries/*/events.json"))
    for cfile in country_dirs:
        if os.path.getsize(cfile) <= 5:
            continue
        cfile_norm = cfile.replace("\\", "/")
        res_path = f"res://{cfile_norm}"
        tag = os.path.basename(os.path.dirname(cfile)).upper()

        is_massive_dump = os.path.getsize(cfile) > 5 * 1024 * 1024 # > 5MB e.g. VEN
        
        try:
            with open(cfile, "r", encoding="utf-8") as f:
                cdata = json.load(f)
            items = cdata.items() if isinstance(cdata, dict) else [(x.get("id", x.get("event_id", "")), x) for x in cdata if isinstance(x, dict)]
            for eid, _ in items:
                if not eid:
                    continue
                s_eid = str(eid)
                target_tag = extract_tag_from_event_id(s_eid)
                
                if target_tag == "NEWS":
                    pri = 5
                elif target_tag and target_tag == tag:
                    pri = 100
                elif not is_massive_dump:
                    pri = 20
                else:
                    pri = 2
                
                existing_pri, _ = scored_index.get(s_eid, (0, ""))
                if pri > existing_pri:
                    scored_index[s_eid] = (pri, res_path)
        except Exception as e:
            print(f"Error reading {cfile}: {e}")

    # 3. Global events
    global_path = "data/events/global_events.json"
    if os.path.exists(global_path):
        with open(global_path, "r", encoding="utf-8") as f:
            gdata = json.load(f)
        items = gdata.items() if isinstance(gdata, dict) else [(x.get("id", x.get("event_id", "")), x) for x in gdata if isinstance(x, dict)]
        for eid, _ in items:
            if eid:
                s_eid = str(eid)
                existing_pri, _ = scored_index.get(s_eid, (0, ""))
                if 30 > existing_pri:
                    scored_index[s_eid] = (30, "res://data/events/global_events.json")

    # Build final flat index
    final_index = {eid: path for eid, (pri, path) in scored_index.items()}

    out_file = "data/events/events_index.json"
    print(f"Writing {len(final_index)} accurately mapped events to {out_file}...")
    with open(out_file, "w", encoding="utf-8") as out_f:
        json.dump(final_index, out_f, ensure_ascii=False, indent=2)

    print(f"Rebuild completed in {time.time() - t0:.2f}s! Total unique events: {len(final_index)}")

if __name__ == "__main__":
    rebuild_events_index()
