import os
import re

ui_nodes = ["Control", "Button", "Label", "RichTextLabel", "Panel", "OptionButton", "TextureRect", "ColorRect", "TabContainer"]
violations = []

for root, _, files in os.walk("core"):
    for f in files:
        if f.endswith(".gd"):
            fpath = os.path.join(root, f).replace("\\", "/")
            with open(fpath, "r", encoding="utf-8", errors="ignore") as file:
                lines = file.readlines()
            for idx, line in enumerate(lines, 1):
                # Ignore comments
                stripped = line.strip()
                if stripped.startswith("#"):
                    continue
                for node_type in ui_nodes:
                    if re.search(rf'\b{node_type}\b', line):
                        # Exclude harmless occurrences or check context
                        violations.append({
                            "file": fpath,
                            "line": idx,
                            "node": node_type,
                            "content": stripped
                        })

print(f"Total UI node references in core/: {len(violations)}")
for v in violations[:15]:
    print(f"{v['file']}:{v['line']} [{v['node']}] -> {v['content']}")
