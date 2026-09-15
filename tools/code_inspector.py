#!/usr/bin/env python3
"""IVORY Code Inspector — one fast, deterministic pre-flight scan.

This is a developer-side code inspection device, not a replacement for Godot's
parser/compiler. It combines the project's structural checkers with native C++
checks and emits both human-readable diagnostics and an optional JSON report.

Usage:
    python3 tools/code_inspector.py .
    python3 tools/code_inspector.py . --json build/code_report.json
    python3 tools/code_inspector.py . --strict
"""
from __future__ import annotations
import argparse, json, os, re, subprocess, sys
from pathlib import Path

SEVERITY = {"INFO": 0, "WARN": 1, "ERROR": 2}


def diag(items, level, path, line, message):
    items.append({"level": level, "path": str(path), "line": int(line or 0), "message": message})


def masked(text: str, is_gd: bool = True) -> str:
    # Keep newlines while hiding strings/comments so delimiter checks do not
    # confuse a comment such as "if (x)" for code.
    out = []
    i = 0
    in_block = False
    in_line = False
    quote = None
    while i < len(text):
        c = text[i]
        n = text[i + 1] if i + 1 < len(text) else ""
        if in_line:
            if c == "\n":
                in_line = False; out.append(c)
            else:
                out.append(" ")
            i += 1; continue
        if in_block:
            if c == "*" and n == "/":
                out.extend("  "); i += 2; in_block = False
            else:
                out.append("\n" if c == "\n" else " "); i += 1
            continue
        if quote:
            if c == "\\":
                out.extend("  "); i += 2; continue
            if c == quote:
                quote = None
            out.append("\n" if c == "\n" else " "); i += 1; continue
        if is_gd and c == "#":
            in_line = True; out.append(" "); i += 1; continue
        if c == "/" and n == "/":
            in_line = True; out.extend("  "); i += 2; continue
        if c == "/" and n == "*":
            in_block = True; out.extend("  "); i += 2; continue
        if c in ('"', "'"):
            quote = c; out.append(" "); i += 1; continue
        out.append(c); i += 1
    return "".join(out)


def check_delimiters(root: Path, items):
    pairs = {')': '(', ']': '[', '}': '{'}
    opens = set(pairs.values())
    for path in list(root.rglob("*.gd")) + list(root.rglob("*.cpp")) + list(root.rglob("*.h")):
        text = path.read_text(encoding="utf-8", errors="replace")
        clean = masked(text, path.suffix == ".gd")
        stack = []
        for ln, line in enumerate(clean.splitlines(), 1):
            for col, c in enumerate(line, 1):
                if c in opens:
                    stack.append((c, ln, col))
                elif c in pairs:
                    if not stack or stack[-1][0] != pairs[c]:
                        diag(items, "ERROR", path.relative_to(root), ln, f"unmatched '{c}' at column {col}")
                    else:
                        stack.pop()
        for c, ln, col in stack[-5:]:
            diag(items, "ERROR", path.relative_to(root), ln, f"unclosed '{c}' at column {col}")


def check_gd_anti_patterns(root: Path, items):
    for path in root.rglob("*.gd"):
        rel = path.relative_to(root)
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        for i, line in enumerate(lines, 1):
            if re.search(r"\b\d+\s*/\s*\d+\b", line) and "float(" not in line:
                diag(items, "WARN", rel, i, "literal integer division may discard the decimal part")
            if re.search(r"\b(var|const)\s+sign\s*[:=]", line):
                diag(items, "WARN", rel, i, "local name 'sign' collides with a built-in function")


def check_native_cpp(root: Path, items):
    src = root / "native" / "ivory" / "src"
    if not src.exists():
        return
    classes = set()
    headers = {}
    for h in src.glob("*.h"):
        text = h.read_text(encoding="utf-8", errors="replace")
        classes.update(re.findall(r"class\s+(Ivory\w+)\s*:", text))
        headers[h.name] = text
        if "#pragma once" not in text and not re.search(r"#ifndef\s+IVORY_", text):
            diag(items, "WARN", h.relative_to(root), 1, "header has no obvious include guard")
    for cpp in src.glob("*.cpp"):
        text = cpp.read_text(encoding="utf-8", errors="replace")
        rel = cpp.relative_to(root)
        if "#include <godot_cpp/" in text and "using namespace godot;" not in text:
            # Not necessarily wrong, but worth a visible note for this project
            # because all native classes are expected to live in godot namespace.
            diag(items, "INFO", rel, 1, "native file uses godot-cpp; namespace qualification should remain explicit or intentional")
        for name in re.findall(r"\b(Ivory\w+)::(\w+)\s*\(", text):
            cls, fn = name
            if cls not in classes:
                diag(items, "ERROR", rel, 1, f"implementation references undeclared native class {cls}")
    # Every registered Ivory class must have a header in the same module.
    reg = src / "register_types.cpp"
    if reg.exists():
        text = reg.read_text(encoding="utf-8", errors="replace")
        for cls in re.findall(r"GDREGISTER_CLASS\((Ivory\w+)\)", text):
            if not any(re.search(r"class\s+" + re.escape(cls) + r"\s*:", h) for h in headers.values()):
                diag(items, "ERROR", reg.relative_to(root), 1, f"registered class {cls} has no matching header")


def check_resources(root: Path, items):
    project = root / "project.godot"
    if not project.exists():
        diag(items, "ERROR", "project.godot", 1, "project.godot is missing")
        return
    text = project.read_text(encoding="utf-8", errors="replace")
    for m in re.finditer(r"res://[^\"\s,\]]+", text):
        rel = m.group(0)[6:]
        if not (root / rel).exists():
            line = text.count("\n", 0, m.start()) + 1
            diag(items, "ERROR", "project.godot", line, f"resource path does not exist: {m.group(0)}")


def run_existing_checks(root: Path, items):
    checks = [
        "check_indent.py", "check_const.py", "check_identifiers.py", "check_scope.py",
        "check_self_calls.py", "check_warnings.py", "check_returns.py",
        "check_continuations.py", "check_shadow.py", "check_native_names.py",
        "check_references.py", "check_size.py",
    ]
    tools = root / "tools"
    for name in checks:
        p = tools / name
        if not p.exists():
            diag(items, "ERROR", f"tools/{name}", 1, "required checker is missing")
            continue
        proc = subprocess.run([sys.executable, str(p), str(root)], capture_output=True, text=True)
        if proc.returncode:
            # Size is project debt, not a correctness failure; all other
            # bundled checkers are load/parse correctness gates.
            level = "WARN" if name == "check_size.py" else "ERROR"
            msg = (proc.stdout + proc.stderr).strip().splitlines()
            diag(items, level, f"tools/{name}", 1, msg[-1] if msg else "checker failed")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root", nargs="?", default=".")
    ap.add_argument("--json", dest="json_path")
    ap.add_argument("--strict", action="store_true", help="treat warnings as failure")
    args = ap.parse_args()
    root = Path(args.root).resolve()
    items = []
    check_delimiters(root, items)
    check_gd_anti_patterns(root, items)
    check_native_cpp(root, items)
    check_resources(root, items)
    run_existing_checks(root, items)
    items.sort(key=lambda x: (SEVERITY[x["level"]], x["path"], x["line"]))
    errors = sum(x["level"] == "ERROR" for x in items)
    warns = sum(x["level"] == "WARN" for x in items)
    print("IVORY CODE INSPECTOR")
    print("=" * 72)
    if not items:
        print("PASS — no diagnostics found.")
    else:
        for x in items:
            loc = f"{x['path']}:{x['line']}" if x["line"] else x["path"]
            print(f"[{x['level']}] {loc} — {x['message']}")
    print("-" * 72)
    print(f"Diagnostics: {len(items)} | errors: {errors} | warnings: {warns}")
    payload = {"root": str(root), "errors": errors, "warnings": warns, "diagnostics": items}
    if args.json_path:
        out = Path(args.json_path)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"JSON report: {out}")
    return 1 if errors or (args.strict and warns) else 0

if __name__ == "__main__":
    raise SystemExit(main())
