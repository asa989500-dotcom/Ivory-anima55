# Two checks to run before opening the editor

Godot reports the **first** parse error in a file and then a cascade of
nonsense after it — one missing indent produced six errors in `main.gd`, five
of which described nothing wrong. And it reports one file at a time, so a
second broken file is not seen until the first is fixed and the project is
loaded again. Both of the faults found in stage 129 were of that shape.

These two scripts read every `.gd` in the project at once and report the causes
rather than the cascade. Neither needs Godot, godot-cpp or a network.

```
python3 tools/check_structure.py scripts
python3 tools/check_references.py
```

## `check_structure.py`

Indentation and brackets. It knows the one thing a naive checker gets wrong:
a **logical** line can span several physical ones, and only the first carries
indentation that means anything — a wrapped `func` signature is indented deeper
than its own body, and that is correct. Inside brackets, spaces are alignment
rather than indentation and are left alone.

It reports:

* a line indented where nothing opened a block for it
* a line ending in `:` with nothing indented under it
* a tab-indented file using spaces at the start of a real statement
* a file that ends with brackets still open — which is how the missing `)` in
  `layers_panel.gd` was found. Godot reported that one at the *end* of the
  file, over nine hundred lines from the actual mistake.

## `check_references.py`

`ClassName.member` against what that class actually declares, plus duplicate
`class_name` declarations and duplicate `func` names within one file — both of
which Godot refuses outright.

Engine-inherited names (`new`, `call`, `connect`, `free` and the rest) are
listed in `BUILT_IN` and skipped. If a legitimate inherited method is ever
reported, add it there rather than loosening the check.

## What they do not do

They are not a parser and they do not type-check. A wrong argument count, a
misspelt local, an integer handed where a `Vector2` was wanted — Godot finds
those and these do not. What these catch is the class of mistake that makes
Godot refuse to load the file at all, which is the class that costs a round
trip to the device to discover.


## `code_inspector.py` — the code inspection device

Run `python3 tools/code_inspector.py .` before opening the editor. It performs
a pre-flight pass over GDScript, C++ and `project.godot`, then runs the existing
static checkers and can save a machine-readable report with `--json`. Errors
fail the command; legacy file-size debt is reported as a warning so the device
does not confuse maintainability debt with a parser/compiler fault.

For a build-oriented one-command check:

```
bash tools/inspect_project.sh
```

The report is written to `build/code_inspector_report.json`.
