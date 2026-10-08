import os
import re
import json

# Collect all vars of CountryState
with open("core/data/country_state.gd", "r", encoding="utf-8") as f:
    cs_content = f.read()

cs_vars = []
for line in cs_content.splitlines():
    if line.startswith("func "):
        break
    m = re.match(r'^(?:@export[a-zA-Z0-9_]*(\([^)]*\))?\s+)?var\s+([a-zA-Z0-9_]+)', line.strip())
    if m:
        cs_vars.append(m.group(2))

# Collect all files in core/systems/
systems_content = ""
for root, _, files in os.walk("core/systems"):
    for f in files:
        if f.endswith(".gd"):
            with open(os.path.join(root, f), "r", encoding="utf-8", errors="ignore") as sys_file:
                systems_content += sys_file.read() + "\n"

# Check which vars are never referenced in core/systems
unread_vars = []
for v in cs_vars:
    # Look for .v or ["v"] or "v"
    pattern = rf'\b{v}\b'
    matches = len(re.findall(pattern, systems_content))
    if matches == 0:
        unread_vars.append(v)

print(f"Total CountryState vars: {len(cs_vars)}")
print(f"CountryState vars never mentioned in core/systems ({len(unread_vars)}): {unread_vars}")

# Do the same for RegionData
with open("core/data/region_data.gd", "r", encoding="utf-8") as f:
    rd_content = f.read()

rd_vars = []
for line in rd_content.splitlines():
    if line.startswith("func "):
        break
    m = re.match(r'^(?:@export[a-zA-Z0-9_]*(\([^)]*\))?\s+)?var\s+([a-zA-Z0-9_]+)', line.strip())
    if m:
        rd_vars.append(m.group(2))

unread_rd_vars = []
for v in rd_vars:
    pattern = rf'\b{v}\b'
    matches = len(re.findall(pattern, systems_content))
    if matches == 0:
        unread_rd_vars.append(v)

print(f"Total RegionData vars: {len(rd_vars)}")
print(f"RegionData vars never mentioned in core/systems ({len(unread_rd_vars)}): {unread_rd_vars}")
