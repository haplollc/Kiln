#!/usr/bin/env python3
"""Run KilnBench on each input with a time limit; print one summary line per input
and write the rows to the JSON path given as the first argument."""
import json, subprocess, sys, os
out = sys.argv[1]
bench = os.path.join(os.path.dirname(__file__), "KilnBench/.build/release/KilnBench")
rows = []
for path in sys.argv[2:]:
    name = os.path.basename(path)
    try:
        p = subprocess.run([bench, path], capture_output=True, text=True, timeout=25)
        lines = [l for l in p.stdout.splitlines() if l.startswith("@@KILNBENCH@@")]
        row = json.loads(lines[0][len("@@KILNBENCH@@"):]) if lines else {"file": name, "valid": False, "errors": [f"crashed (exit {p.returncode})"]}
    except subprocess.TimeoutExpired:
        row = {"file": name, "valid": False, "hung": True, "errors": ["hung: no result after 25 s"]}
    rows.append(row)
    status = "PASS" if row.get("valid") else ("HUNG" if row.get("hung") else "FAIL")
    print(f"{name:24} {status}  view={row.get('hasView')} rendered={row.get('rendered')}")
    for e in row.get("errors", [])[:3]: print("     ERR ", e[:200])
    for w in row.get("warnings", [])[:3]: print("     WARN", w[:170])
json.dump(rows, open(out, "w"), indent=1)
