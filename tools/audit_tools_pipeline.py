import os
import re

tools_to_check = [
    "tools/data_optimizer.py",
    "tools/focus_tree_pipeline.py",
    "tools/focus_pipeline.py",
    "tools/focus_tree_compiler.py",
    "tools/content_modularizer.py",
    "tools/data_decoupler.py",
    "tools/clausewitz_parser.py"
]

results = {}
for t in tools_to_check:
    if not os.path.exists(t):
        results[t] = {"error": "missing"}
        continue
    with open(t, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()
        
    has_bom = "utf-8-sig" in content or "utf_8_sig" in content
    has_clausewitz = "clausewitz" in content.lower() or "{" in content
    has_try_except = "try:" in content
    has_json = "json.dump" in content or "json.load" in content
    
    results[t] = {
        "lines": len(content.splitlines()),
        "has_utf8_bom_handling": has_bom,
        "has_try_except": has_try_except,
        "has_json": has_json
    }

for k, v in results.items():
    print(k, v)
