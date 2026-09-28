import os
import re
import json

def audit_military():
    fpath = "core/systems/military_engine.gd"
    if not os.path.exists(fpath):
        return {"error": "not found"}
    with open(fpath, "r", encoding="utf-8") as f:
        code = f.read()
    
    # Check for stockpile deduction, manpower deduction, axes advancement
    has_stockpile_deduction = "infantry_weapons_stockpile" in code and ("-=" in code or "maxi" in code)
    has_manpower_deduction = "manpower_pool" in code and ("-=" in code or "maxi" in code)
    has_axis_progress = "progress" in code and ("+=" in code or "-=" in code)
    has_smuta_raids = "execute_smuta_raid" in code or "raid" in code
    has_frontline_sim = "simulate_frontlines" in code
    
    return {
        "has_stockpile_deduction": has_stockpile_deduction,
        "has_manpower_deduction": has_manpower_deduction,
        "has_axis_progress": has_axis_progress,
        "has_smuta_raids": has_smuta_raids,
        "has_frontline_sim": has_frontline_sim,
        "size_lines": len(code.splitlines())
    }

def audit_economy():
    fpath = "core/systems/economy_engine.gd"
    if not os.path.exists(fpath):
        return {"error": "not found"}
    with open(fpath, "r", encoding="utf-8") as f:
        code = f.read()
        
    has_real_gdp_growth = "gdp_growth" in code or "real_gdp_growth" in code
    has_inflation = "inflation_rate" in code
    has_central_bank = "central_bank_rate" in code
    has_money_printing = "money_printing" in code
    has_austerity = "is_austerity_active" in code
    has_randf = "randf(" in code or "randf_range(" in code
    
    return {
        "has_real_gdp_growth": has_real_gdp_growth,
        "has_inflation": has_inflation,
        "has_central_bank": has_central_bank,
        "has_money_printing": has_money_printing,
        "has_austerity": has_austerity,
        "has_randf": has_randf,
        "size_lines": len(code.splitlines())
    }

def audit_events():
    fpath = "core/systems/event_manager.gd"
    if not os.path.exists(fpath):
        return {"error": "not found"}
    with open(fpath, "r", encoding="utf-8") as f:
        code = f.read()
        
    # Check opcode dispatch
    matches_opcodes = re.findall(r'["\']([A-Z_]+)["\']\s*:', code)
    has_fallback = "else:" in code or "_:" in code or "push_warning" in code
    has_patterns_registry = "patterns_registry.json" in code
    
    return {
        "has_patterns_registry": has_patterns_registry,
        "has_fallback": has_fallback,
        "opcodes_sample": list(set(matches_opcodes))[:15],
        "size_lines": len(code.splitlines())
    }

def audit_focus():
    fpath = "core/systems/focus_stage_controller.gd"
    if not os.path.exists(fpath):
        return {"error": "not found"}
    with open(fpath, "r", encoding="utf-8") as f:
        code = f.read()
        
    has_load_tree = "LOAD_FOCUS_TREE" in code
    has_allow_branch = "allow_branch" in code
    has_bypass = "bypass" in code
    has_stage_cascade = "stage" in code
    
    return {
        "has_load_tree": has_load_tree,
        "has_allow_branch": has_allow_branch,
        "has_bypass": has_bypass,
        "has_stage_cascade": has_stage_cascade,
        "size_lines": len(code.splitlines())
    }

def audit_espionage():
    fpath = "core/systems/espionage_engine.gd"
    if not os.path.exists(fpath):
        return {"error": "not found"}
    with open(fpath, "r", encoding="utf-8") as f:
        code = f.read()
        
    has_black_budget = "black_budget" in code
    has_counter_intel = "domestic_security" in code or "counter" in code
    has_sabotage = "SABOTAGE" in code
    has_steal_tech = "STEAL_TECH" in code
    
    return {
        "has_black_budget": has_black_budget,
        "has_counter_intel": has_counter_intel,
        "has_sabotage": has_sabotage,
        "has_steal_tech": has_steal_tech,
        "size_lines": len(code.splitlines())
    }

print("MILITARY:", audit_military())
print("ECONOMY:", audit_economy())
print("EVENTS:", audit_events())
print("FOCUS:", audit_focus())
print("ESPIONAGE:", audit_espionage())
