import re

with open('core/data/country_state.gd', 'r', encoding='utf-8') as f:
    content = f.read()

lines = content.splitlines()
class_vars = []
in_func = False
for line in lines:
    stripped = line.strip()
    if re.match(r'^(static\s+)?func\s+', line):
        in_func = True
    elif not in_func:
        m = re.match(r'^(?:@export[a-zA-Z0-9_]*(\([^)]*\))?\s+)?var\s+([a-zA-Z0-9_]+)', line)
        if m:
            class_vars.append(m.group(2))

# Extract to_dict body
to_dict_match = re.search(r'func to_dict\(\)\s*->\s*Dictionary:(.*?)(?=\nfunc |\nstatic func |\Z)', content, re.DOTALL)
to_dict_body = to_dict_match.group(1) if to_dict_match else ""

# Extract from_dict body
from_dict_match = re.search(r'static func from_dict\(data:\s*Dictionary\)\s*->\s*CountryState:(.*?)(?=\nfunc |\nstatic func |\Z)', content, re.DOTALL)
from_dict_body = from_dict_match.group(1) if from_dict_match else ""

missing_to = []
for v in class_vars:
    # Look for "v": or 'v': in to_dict
    if f'"{v}"' not in to_dict_body and f"'{v}'" not in to_dict_body:
        missing_to.append(v)

missing_from = []
for v in class_vars:
    # Look for "v" in from_dict (e.g. .get("v") or ["v"] or state.v =)
    pattern = rf'["\']{v}["\']|state\.{v}\s*='
    if not re.search(pattern, from_dict_body):
        missing_from.append(v)

print(f"Total CountryState variables: {len(class_vars)}")
print(f"Missing in to_dict ({len(missing_to)}): {missing_to}")
print(f"Missing in from_dict ({len(missing_from)}): {missing_from}")
