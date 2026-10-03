import os
import re

dirs_to_process = ["core", "scripts", "ui"]
converted_count = 0
modified_files = set()

# Safe string regex: strictly opening quote, any non-quote or escaped char, closing quote. No operators, no concatenation.
RE_SAFE_STRING = re.compile(r'^(?:"[^"\\]*(?:\\.[^"\\]*)*"|\'[^\'\\]*(?:\\.[^\'\\]*)*\')$')
# Safe integer
RE_SAFE_INT = re.compile(r'^-?\d+$')
# Safe float
RE_SAFE_FLOAT = re.compile(r'^-?\d+\.\d+(?:f)?$')
# Safe built-in constructors
RE_SAFE_BUILTIN = re.compile(r'^(?:Color|Vector2|Vector2i|Vector3|Vector3i|Rect2|Rect2i|Transform2D|Transform3D)\([^)]*\)$')
# Safe known engine node/control classes with 0-arg .new()
SAFE_CLASSES = {
    "Node", "Node2D", "Control", "Label", "Button", "TextureRect", "ColorRect",
    "HBoxContainer", "VBoxContainer", "PanelContainer", "ScrollContainer", "MarginContainer",
    "GridContainer", "BoxContainer", "CenterContainer", "ProgressBar", "CheckButton",
    "CheckBox", "OptionButton", "LineEdit", "TextEdit", "RichTextLabel", "Tree",
    "ItemList", "TabBar", "TabContainer", "HSeparator", "VSeparator", "Panel",
    "Timer", "AudioStreamPlayer", "Sprite2D", "ConfigFile", "RegEx", "ImageTexture"
}

for d in dirs_to_process:
    for root, _, files in os.walk(d):
        for f in files:
            if not f.endswith(".gd"):
                continue
            fpath = os.path.join(root, f)
            with open(fpath, "r", encoding="utf-8") as infile:
                lines = infile.readlines()
            
            new_lines = []
            file_modified = False
            in_func = False
            
            for line in lines:
                stripped = line.strip()
                if re.match(r'^(static\s+)?func\s+', line):
                    in_func = True
                
                # We only convert local variables inside functions
                if in_func:
                    # Match local untyped variable: \s*var <name> = <val>
                    m = re.match(r'^(\s*var\s+([a-zA-Z0-9_]+))\s*=\s*(.+)$', line)
                    if m and ":=" not in line and not stripped.startswith("#"):
                        prefix = m.group(1)
                        var_name = m.group(2)
                        val = m.group(3).strip()
                        
                        # Verify prefix has no explicit type
                        if not re.search(r'var\s+[a-zA-Z0-9_]+\s*:\s*[a-zA-Z0-9_\[\]]+', prefix):
                            is_safe = False
                            if RE_SAFE_INT.match(val):
                                is_safe = True
                            elif RE_SAFE_FLOAT.match(val):
                                is_safe = True
                            elif val in ("true", "false"):
                                is_safe = True
                            elif RE_SAFE_STRING.match(val):
                                is_safe = True
                            elif val in ("[]", "{}"):
                                is_safe = True
                            elif RE_SAFE_BUILTIN.match(val):
                                is_safe = True
                            else:
                                new_m = re.match(r'^([A-Z][a-zA-Z0-9_]*)\.new\(\)$', val)
                                if new_m and new_m.group(1) in SAFE_CLASSES:
                                    is_safe = True
                            
                            if is_safe:
                                line = f"{prefix} := {val}\n"
                                converted_count += 1
                                file_modified = True
                
                new_lines.append(line)
            
            if file_modified:
                with open(fpath, "w", encoding="utf-8", newline="\n") as outfile:
                    outfile.writelines(new_lines)
                modified_files.add(fpath.replace("\\", "/"))

print(f"Strict safe type inference applied to {converted_count} variables across {len(modified_files)} files.")
