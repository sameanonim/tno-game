# -*- coding: utf-8 -*-
import sys
import re

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")

file_path = "ui/screens/terminal_main.gd"

with open(file_path, "r", encoding="utf-8") as f:
    lines = f.readlines()

new_lines = []
modified_count = 0

for idx, line in enumerate(lines, 1):
    # Check if this line has .text = ... with cyrillic and not tr(
    if ".text" in line and any(c in 'абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ' for c in line) and "tr(" not in line and "tr_key" not in line and "_tr_str" not in line:
        # Pattern 1: label_log.text = "STRING" % [args]
        m_pct_list = re.search(r'(\s*)([a-zA-Z0-9_.]+)\.text\s*=\s*"([^"]+)"\s*%\s*(\[[^\]]+\])', line)
        # Pattern 2: label_log.text = "STRING" % single_arg
        m_pct_single = re.search(r'(\s*)([a-zA-Z0-9_.]+)\.text\s*=\s*"([^"]+)"\s*%\s*([^,\n\r]+)', line)
        # Pattern 3: label_log.text = "STRING" + ...
        m_concat = re.search(r'(\s*)([a-zA-Z0-9_.]+)\.text\s*=\s*"([^"]+)"\s*\+\s*(.+)', line)
        # Pattern 4: label_log.text = "STRING"
        m_simple = re.search(r'(\s*)([a-zA-Z0-9_.]+)\.text\s*=\s*"([^"]+)"\s*$', line)

        indent = line[:len(line) - len(line.lstrip())]
        
        if m_pct_list:
            var_name = m_pct_list.group(2)
            fmt_str = m_pct_list.group(3)
            args_str = m_pct_list.group(4)
            key = "UI_AUTO_GEN_" + str(idx)
            new_line = f'{indent}{var_name}.text = _tr_str("{key}", {{}}, "{fmt_str}") % {args_str}\n'
            new_lines.append(new_line)
            modified_count += 1
        elif m_pct_single:
            var_name = m_pct_single.group(2)
            fmt_str = m_pct_single.group(3)
            arg_str = m_pct_single.group(4).strip()
            key = "UI_AUTO_GEN_" + str(idx)
            new_line = f'{indent}{var_name}.text = _tr_str("{key}", {{}}, "{fmt_str}") % ({arg_str})\n'
            new_lines.append(new_line)
            modified_count += 1
        elif m_concat:
            var_name = m_concat.group(2)
            fmt_str = m_concat.group(3)
            rest_str = m_concat.group(4).strip()
            key = "UI_AUTO_GEN_" + str(idx)
            new_line = f'{indent}{var_name}.text = _tr_str("{key}", {{}}, "{fmt_str}") + {rest_str}\n'
            new_lines.append(new_line)
            modified_count += 1
        elif m_simple:
            var_name = m_simple.group(2)
            fmt_str = m_simple.group(3)
            key = "UI_AUTO_GEN_" + str(idx)
            new_line = f'{indent}{var_name}.text = _tr_str("{key}", {{}}, "{fmt_str}")\n'
            new_lines.append(new_line)
            modified_count += 1
        else:
            print(f"UNMATCHED line {idx}: {repr(line.strip())}")
            new_lines.append(line)
    else:
        new_lines.append(line)

print(f"Total modified lines in terminal_main.gd: {modified_count}")

with open(file_path, "w", encoding="utf-8") as f:
    f.writelines(new_lines)
