import os
import re

ui_dir = "ui"
hardcoded_texts = []

for root, _, files in os.walk(ui_dir):
    for f in files:
        if f.endswith(".gd"):
            fpath = os.path.join(root, f)
            with open(fpath, "r", encoding="utf-8") as file:
                lines = file.readlines()
            for idx, line in enumerate(lines, 1):
                # Look for .text = "..." where string contains Cyrillic or words and not tr(
                m = re.search(r'\.text\s*=\s*("([^"]+)"|\'([^\']+)\')', line)
                if m:
                    txt = m.group(2) or m.group(3)
                    # Check if text contains letters and isn't formatted with tr(
                    if any(c in 'абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ' for c in txt):
                        if "tr(" not in line and "tr_key" not in line:
                            hardcoded_texts.append({
                                "file": fpath.replace("\\", "/"),
                                "line": idx,
                                "text": txt
                            })

import json

print(f"Total hardcoded cyrillic .text assignments: {len(hardcoded_texts)}")
with open("tools/audit_hardcoded_report.json", "w", encoding="utf-8") as f:
    json.dump(hardcoded_texts, f, indent=2, ensure_ascii=False)

for item in hardcoded_texts[:10]:
    safe_text = item['text'].encode('ascii', errors='replace').decode('ascii')
    print(f"{item['file']}:{item['line']} -> {safe_text}")
