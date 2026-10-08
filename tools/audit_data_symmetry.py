import os
import re
import json

def analyze_class_file(fpath):
    with open(fpath, 'r', encoding='utf-8') as f:
        content = f.read()

    lines = content.splitlines()
    class_vars = []
    
    # Grab vars before first func or class-level vars
    in_func = False
    for line in lines:
        stripped = line.strip()
        if re.match(r'^(static\s+)?func\s+', line):
            in_func = True
        elif not in_func:
            m = re.match(r'^(?:@export[a-zA-Z0-9_]*(\([^)]*\))?\s+)?var\s+([a-zA-Z0-9_]+)', line)
            if m:
                class_vars.append(m.group(2))

    # Find to_dict
    to_dict_match = re.search(r'func to_dict\([^)]*\)[^:]*:(.*?)(?=\nfunc |\nstatic func |\Z)', content, re.DOTALL)
    to_keys = set()
    if to_dict_match:
        to_keys = set(re.findall(r'["\']([a-zA-Z0-9_]+)["\']\s*:', to_dict_match.group(1)))

    # Find from_dict
    from_dict_match = re.search(r'func from_dict\([^)]*\)[^:]*:(.*?)(?=\nfunc |\nstatic func |\Z)', content, re.DOTALL)
    from_keys = set()
    if from_dict_match:
        from_keys = set(re.findall(r'data\.get\(["\']([a-zA-Z0-9_]+)["\']', from_dict_match.group(1)))
        from_keys.update(re.findall(r'data\[["\']([a-zA-Z0-9_]+)["\']\]', from_dict_match.group(1)))

    missing_in_to = [v for v in class_vars if v not in to_keys]
    missing_in_from = [v for v in class_vars if v not in from_keys]
    
    # Check save_to_json_file / load_from_json_file
    has_save_file = "func save_to_json_file" in content or "func save_to_file" in content
    has_load_file = "func load_from_json_file" in content or "func load_from_file" in content

    return {
        "file": fpath,
        "class_vars_count": len(class_vars),
        "class_vars": class_vars,
        "has_to_dict": bool(to_dict_match),
        "has_from_dict": bool(from_dict_match),
        "missing_in_to_dict": missing_in_to,
        "missing_in_from_dict": missing_in_from,
        "has_save_file": has_save_file,
        "has_load_file": has_load_file
    }

files = [
    'core/data/country_state.gd',
    'core/data/region_data.gd',
    'core/data/game_event.gd',
    'core/data/directive_resource.gd',
    'core/data/leader_resource.gd',
    'core/data/tech_resource.gd',
    'core/data/frontline.gd',
    'core/data/operational_axis.gd',
    'core/data/agent_resource.gd',
    'core/data/covert_operation_resource.gd',
    'core/data/party_data.gd',
    'core/data/law_resource.gd',
    'core/data/societal_metric_resource.gd',
    'core/data/germany_content_bundle.gd'
]

results = {}
for f in files:
    if os.path.exists(f):
        results[f] = analyze_class_file(f)

print(json.dumps(results, indent=2))
