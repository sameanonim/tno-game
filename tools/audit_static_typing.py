import os
import re

dirs_to_check = ["core", "scripts", "ui"]
untyped_funcs = []
untyped_params = []
untyped_vars = []

for d in dirs_to_check:
    for root, _, files in os.walk(d):
        for f in files:
            if f.endswith(".gd"):
                fpath = os.path.join(root, f).replace("\\", "/")
                with open(fpath, "r", encoding="utf-8", errors="ignore") as file:
                    lines = file.readlines()
                for idx, line in enumerate(lines, 1):
                    # Check func signature: func foo(a, b) -> void:
                    fm = re.match(r'^\s*(static\s+)?func\s+([a-zA-Z0-9_]+)\s*\((.*?)\)(\s*->\s*([a-zA-Z0-9_\[\],\s]+))?:', line)
                    if fm:
                        fname = fm.group(2)
                        params_str = fm.group(3).strip()
                        ret_type = fm.group(4)
                        if not ret_type:
                            untyped_funcs.append(f"{fpath}:{idx} func {fname} without return type")
                        if params_str:
                            for p in params_str.split(","):
                                p = p.strip()
                                if p and not p.startswith("..."):
                                    # p may be "a: int" or "a = 5" or "a"
                                    if ":" not in p:
                                        untyped_params.append(f"{fpath}:{idx} param '{p}' in func {fname}")
                    # Check untyped var declaration: var foo = ...
                    vm = re.match(r'^\s*(?:@export[a-zA-Z0-9_]*(\([^)]*\))?\s+)?var\s+([a-zA-Z0-9_]+)\s*(?:=\s*(.+))?$', line)
                    if vm and not fm:
                        vname = vm.group(2)
                        # check if line has type: var x: int
                        if not re.search(r'var\s+[a-zA-Z0-9_]+\s*:\s*[a-zA-Z0-9_\[\]]+', line):
                            # if it has := it is inferred
                            if ":=" not in line and not line.strip().startswith("#"):
                                untyped_vars.append(f"{fpath}:{idx} var {vname}")

print(f"Total untyped func return types: {len(untyped_funcs)}")
print(f"Total untyped parameters: {len(untyped_params)}")
print(f"Total untyped variables (no : Type and no :=): {len(untyped_vars)}")
