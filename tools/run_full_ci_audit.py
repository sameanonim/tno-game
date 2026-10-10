import subprocess
import sys
import time

GODOT_BIN = r"E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"

TESTS = [
    {
        "name": "GDScript Compilation & Parse Check (126 scripts)",
        "cmd": [GODOT_BIN, "--headless", "-s", "tools/test_compile_all.gd"]
    },
    {
        "name": "Automated Master Unit Test Suite (15 suites, 244 assertions)",
        "cmd": [GODOT_BIN, "--headless", "-s", "tests/run_all_tests.gd"]
    },
    {
        "name": "MCP Architecture & Subsystems Audit (6/6 checks)",
        "cmd": [GODOT_BIN, "--headless", "-s", "tools/run_mcp_audit.gd"]
    },
    {
        "name": "Zero-Dead-Signals & Signal Hygiene Audit",
        "cmd": [sys.executable, "tools/audit_signals.py"]
    },
    {
        "name": "Zero-Hardcoded Cyrillic UI Strings Audit",
        "cmd": [sys.executable, "tools/audit_hardcoded_strings.py"]
    },
    {
        "name": "Data Symmetry & Dirty Delta Caching Audit",
        "cmd": [sys.executable, "tools/audit_data_symmetry.py"]
    },
    {
        "name": "Static Typing Coverage Audit",
        "cmd": [sys.executable, "tools/audit_static_typing.py"]
    }
]

def main():
    print("=" * 80, flush=True)
    print(">>> TNO-GAME MASTER CI/CD QUALITY GATE AUDIT <<<", flush=True)
    print("=" * 80, flush=True)
    
    total = len(TESTS)
    passed = 0
    start_time = time.time()
    
    for i, test in enumerate(TESTS, 1):
        print(f"\n[{i}/{total}] RUNNING: {test['name']}...", flush=True)
        t0 = time.time()
        res = subprocess.run(test["cmd"], capture_output=True, text=True, encoding="utf-8", errors="ignore")
        elapsed = time.time() - t0
        
        # Check success
        if res.returncode == 0:
            passed += 1
            print(f"  -> PASSED in {elapsed:.2f}s", flush=True)
        else:
            print(f"  -> FAILED with exit code {res.returncode} in {elapsed:.2f}s", flush=True)
            print("STDOUT:", flush=True)
            print(res.stdout[-1000:] if len(res.stdout) > 1000 else res.stdout, flush=True)
            print("STDERR:", flush=True)
            print(res.stderr[-1000:] if len(res.stderr) > 1000 else res.stderr, flush=True)
            sys.exit(1)
            
    total_elapsed = time.time() - start_time
    print("\n" + "=" * 80, flush=True)
    print(f">>> ALL {passed}/{total} MASTER CI/CD AUDIT SUITES PASSED! Total time: {total_elapsed:.2f}s <<<", flush=True)
    print("=" * 80, flush=True)

if __name__ == "__main__":
    main()
