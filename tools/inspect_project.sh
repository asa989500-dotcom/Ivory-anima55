#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 "$ROOT/tools/code_inspector.py" "$ROOT" --json "$ROOT/build/code_inspector_report.json" "$@"
