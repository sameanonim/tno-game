#!/usr/bin/env python3
"""
compile_superevents_catalog.py:
Извлекает локализации (русский и английский), сопоставляет с файлами артов (.png)
и аудиотреков (.ogg) супер-событий TNO и компилирует data/events/superevents_catalog.json.
"""

import os
import re
import json

RU_YML = r"F:\SteamLibrary\steamapps\workshop\content\394360\2351077206\localisation\russian\TNO_Super_Events_l_russian.yml"
EN_YML = r"F:\SteamLibrary\steamapps\workshop\content\394360\2438003901\localisation\english\TNO_Super_Events_l_english.yml"

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ART_DIR = os.path.join(PROJECT_ROOT, "assets", "gfx", "interface", "superevents")
AUDIO_DIR = os.path.join(PROJECT_ROOT, "assets", "audio", "superevents")
OUTPUT_JSON = os.path.join(PROJECT_ROOT, "data", "events", "superevents_catalog.json")


def parse_yml(file_path):
    if not os.path.exists(file_path):
        return {}
    data = {}
    with open(file_path, "r", encoding="utf-8-sig", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or line.startswith("l_"):
                continue
            m = re.match(r"^([A-Za-z0-9_]+):\d*\s*\"(.*)\"$", line)
            if m:
                key, val = m.group(1), m.group(2)
                val = val.replace('\\"', '"').replace("\\n", "\n")
                data[key] = val
    return data


def main():
    ru_dict = parse_yml(RU_YML)
    en_dict = parse_yml(EN_YML)

    art_files = os.listdir(ART_DIR) if os.path.exists(ART_DIR) else []
    audio_files = os.listdir(AUDIO_DIR) if os.path.exists(AUDIO_DIR) else []

    print(f"Loaded {len(ru_dict)} RU keys, {len(en_dict)} EN keys.")
    print(f"Available assets: {len(art_files)} PNGs, {len(audio_files)} OGGs.")

    all_keys = set(ru_dict.keys()).union(en_dict.keys())
    base_ids = set()
    for k in all_keys:
        if k.endswith("_D") or k.endswith("_A") or k.endswith("_D_1") or k.endswith("_D_2") or k.endswith("_D_3"):
            continue
        base_ids.add(k)

    catalog = {}

    for eid in sorted(base_ids):
        title_ru = ru_dict.get(eid, "")
        title_en = en_dict.get(eid, "")
        title = title_ru if title_ru else title_en
        if not title:
            continue

        desc_ru = ru_dict.get(f"{eid}_D", "") or ru_dict.get(f"{eid}_D_1", "")
        desc_en = en_dict.get(f"{eid}_D", "") or en_dict.get(f"{eid}_D_1", "")

        opt_ru = ru_dict.get(f"{eid}_A", "")
        opt_en = en_dict.get(f"{eid}_A", "")

        clean_name = eid.lower()
        if clean_name.startswith("tno_se_"):
            clean_name = clean_name[7:]
        elif clean_name.startswith("se_"):
            clean_name = clean_name[3:]

        # Handle reunification vs unification alias
        alt_unif = clean_name.replace("reunification", "unification")
        alt_reunif = clean_name.replace("unification", "reunification")
        no_underscore = clean_name.replace("_", "")

        # Candidates for Art
        matched_art = ""
        art_candidates = [
            f"{clean_name}.png",
            f"{no_underscore}.png",
            f"{alt_unif}.png",
            f"{clean_name}_super.png",
            f"{alt_unif}_super.png",
            f"{clean_name}_unification.png",
            f"{clean_name}_unification_super.png",
        ]
        # Short tag resolution (e.g. wrrf_tukh -> wrrf_tukh_unification_super.png)
        parts = clean_name.split("_")
        if len(parts) >= 2:
            art_candidates.append(f"{parts[-2]}_{parts[-1]}_unification_super.png")
            art_candidates.append(f"{parts[-1]}_unification_super.png")

        for c in art_candidates:
            if c in art_files:
                matched_art = f"res://assets/gfx/interface/superevents/{c}"
                break

        if not matched_art:
            for af in art_files:
                af_base = af.lower().replace(".png", "")
                if af_base == clean_name or af_base == alt_unif or af_base == no_underscore:
                    matched_art = f"res://assets/gfx/interface/superevents/{af}"
                    break

        # Candidates for Audio OGG
        matched_audio = ""
        audio_candidates = [
            f"tno_se_{clean_name}.ogg",
            f"tno_se_{no_underscore}.ogg",
            f"tno_se_{alt_unif}.ogg",
            f"tno_se_{alt_reunif}.ogg",
            f"tno_se_russian_unification_{clean_name}.ogg",
            f"tno_se_{clean_name}_unification.ogg",
        ]
        # Also try subpart matching for russian unifications
        if "reunification" in clean_name or "unification" in clean_name:
            subpart = clean_name.replace("russian_reunification_", "").replace("russian_unification_", "")
            audio_candidates.append(f"tno_se_russian_unification_{subpart}.ogg")
            # Handle tukha abbreviation
            if "tukha" in subpart:
                audio_candidates.append("tno_se_russian_unification_wrrf_tukha.ogg")

        for c in audio_candidates:
            if c in audio_files:
                matched_audio = f"res://assets/audio/superevents/{c}"
                break

        if not matched_audio:
            for aud in audio_files:
                aud_base = aud.lower().replace(".ogg", "").replace("tno_se_", "")
                if aud_base == clean_name or aud_base == alt_unif or aud_base == no_underscore:
                    matched_audio = f"res://assets/audio/superevents/{aud}"
                    break

        catalog[eid] = {
            "id": eid,
            "title_ru": title_ru,
            "title_en": title_en,
            "quote_ru": desc_ru,
            "quote_en": desc_en,
            "option_ru": opt_ru,
            "option_en": opt_en,
            "art_path": matched_art if matched_art else "res://assets/gfx/interface/superevents/russian_reunification.png",
            "audio_path": matched_audio
        }

    os.makedirs(os.path.dirname(OUTPUT_JSON), exist_ok=True)
    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)

    matched_cnt = sum(1 for v in catalog.values() if v["audio_path"])
    print(f"Catalog compiled: {len(catalog)} events, {matched_cnt} with authentic audio tracks!")


if __name__ == "__main__":
    main()
