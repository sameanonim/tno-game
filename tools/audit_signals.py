import os
import re
import json

gd_files = []
for root, _, files in os.walk("."):
    if ".git" in root or ".godot" in root or "addons" in root:
        continue
    for f in files:
        if f.endswith(".gd"):
            gd_files.append(os.path.join(root, f))

# 1. Collect all declared signals
declared_signals = {} # signal_name: [files]
emitted_signals = set()
connected_signals = set()

for fpath in gd_files:
    with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()
    
    # Declared signals: signal my_signal(...)
    for m in re.finditer(r'^\s*signal\s+([a-zA-Z0-9_]+)', content, re.MULTILINE):
        sig = m.group(1)
        declared_signals.setdefault(sig, []).append(fpath.replace("\\", "/"))
        
    # Emitted: my_signal.emit(...) or emit_signal("my_signal", ...)
    for m in re.finditer(r'([a-zA-Z0-9_]+)\.emit\(', content):
        emitted_signals.add(m.group(1))
    for m in re.finditer(r'emit_signal\(["\']([a-zA-Z0-9_]+)["\']', content):
        emitted_signals.add(m.group(1))
        
    # Connected: my_signal.connect(...) or connect("my_signal", ...)
    for m in re.finditer(r'([a-zA-Z0-9_]+)\.connect\(', content):
        connected_signals.add(m.group(1))
    for m in re.finditer(r'connect\(["\']([a-zA-Z0-9_]+)["\']', content):
        connected_signals.add(m.group(1))

# Signals declared and emitted, but never connected anywhere
dead_signals = []
for sig, files in declared_signals.items():
    if sig in emitted_signals and sig not in connected_signals:
        dead_signals.append({"signal": sig, "files": files})

# Signals declared, but never emitted
unemitted_signals = []
for sig, files in declared_signals.items():
    if sig not in emitted_signals:
        unemitted_signals.append({"signal": sig, "files": files})

output = {
    "total_signals_declared": len(declared_signals),
    "dead_signals_count": len(dead_signals),
    "dead_signals": dead_signals,
    "unemitted_signals_count": len(unemitted_signals),
    "unemitted_signals": unemitted_signals
}

with open("tools/audit_signals_report.json", "w", encoding="utf-8") as f:
    json.dump(output, f, indent=2)

print(f"Total declared signals: {len(declared_signals)}")
print(f"Dead signals (emitted but NEVER connected): {len(dead_signals)}")
print(f"Unemitted signals (declared but NEVER emitted): {len(unemitted_signals)}")
