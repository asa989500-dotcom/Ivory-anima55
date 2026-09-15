#!/usr/bin/env python3
"""Regression guard for Stretchy Studio's model3 export scope/indentation."""
from pathlib import Path
import re
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
path = root / "scripts/stretchy_studio_standalone.gd"
text = path.read_text(encoding="utf-8")
lines = text.splitlines()

try:
    start = next(i for i, line in enumerate(lines) if line.startswith("func _export_model3() -> void:"))
except StopIteration:
    print("FAIL: _export_model3() not found")
    raise SystemExit(1)

end = len(lines)
for i in range(start + 1, len(lines)):
    if lines[i].startswith("func ") or lines[i].startswith("static func "):
        end = i
        break
body = lines[start:end]

checks = [
    ("texture_files declared at function scope", any(line == "\tvar texture_files: Array = []" for line in body)),
    ("layer loop exists", any(line == "\tfor l in document[\"layers\"]:" for line in body)),
    ("only texture append is inside layer loop", any(line == "\t\ttexture_files.append(String(l[\"name\"]).get_basename() + \".png\")" for line in body)),
    ("json_text declared at function scope", any(line.startswith("\tvar json_text: String =") for line in body)),
    ("filename declared at function scope", any(line.startswith("\tvar filename: String =") for line in body)),
    ("plan declared at function scope", any(line.startswith("\tvar plan_export_file: Dictionary =") for line in body)),
    ("dialog condition at function scope", any(line == "\tif plan_export_file[\"needs_dialog\"]:" for line in body)),
    ("save branch remains paired", any(line == "\telse:" for line in body)),
    ("dialog writes json_text", any("write_text(path.get_base_dir(), path.get_file(), json_text)" in line for line in body)),
    ("non-dialog writes json_text", any("smart_save_text(filename, json_text)" in line for line in body)),
    ("no loop-nested export setup", not any(line.startswith("\t\tvar json_text") or line.startswith("\t\tvar filename") or line.startswith("\t\tvar plan_export_file") for line in body)),
]

# The fallback must not use the old stale `result` identifier.
joined = "\n".join(body)
checks.append(("no stale bare result export report", not bool(re.search(r"_report_export\(result\)\\s*$", joined, re.M))))

failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(("PASS" if ok else "FAIL") + "  " + name)
print(f"STRETCHY EXPORT REGRESSION GUARD / {len(checks)} CHECKS / {len(failed)} FAILURES")
raise SystemExit(1 if failed else 0)
