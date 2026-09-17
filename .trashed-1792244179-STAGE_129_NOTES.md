# Stage 129 — two parse errors, and a way to stop discovering them one at a time

## What was actually broken

Godot reported six errors in `main.gd`. Five of them described nothing wrong.

**`main.gd:1331`** — a `connect(func() ...)` block indented to one tab inside an
`elif` branch that runs at two. The one-tab line closed the branch early, so
line 1334 was an indent with no block to be inside, and everything after it
was read as class body. Hence "unexpected `elif`", "unexpected Indent",
"unexpected `return`", "expected end of file" — all of them consequences.

**`ui/layers_panel.gd:202`** — the same feature, the same shape of mistake. The
`connect(` opened for `add_bone_layer` was never closed:

```gdscript
add_bone_layer.pressed.connect(func() -> void:
    var made: LayerStack.Layer = stack.add_bone_layer_here()
    if made != null:
        _close_settings()          # ← the ) belongs here
head.add_child(add_bone_layer)
```

Godot would have reported this one at the **end of the file**, over nine
hundred lines from the mistake, and only after `main.gd` was fixed and the
project reloaded — because it reports one file at a time.

Both faults arrived with the bone-layer feature and neither is in anything the
last two stages touched. They were sitting in the project waiting for a parse.

## Why a checker rather than two fixes

Fixing the two takes a minute. The problem is the loop: Godot gives the first
error in the first file, a cascade of false ones after it, and nothing at all
about the second file until the first is clean and the project is loaded
again. On a phone that is a round trip per fault.

`tools/check_structure.py` and `tools/check_references.py` read every `.gd` at
once, need no Godot and no network, and report causes rather than cascades.
Both run clean on the project now.

The structural one knows the thing a naive version gets wrong, and I know
because I wrote the naive version first: a **logical** line spans several
physical ones, and only the first carries meaningful indentation. Judging a
wrapped `func` signature by the indentation of its last line produced 1,837
complaints, all false. Judged properly: two, both real.

It also catches unbalanced brackets at end of file, which is how the
`layers_panel.gd` fault was found rather than guessed at.

The reference checker compares `ClassName.member` against what that class
declares, and catches duplicate `class_name` and duplicate `func` in one file —
both of which Godot refuses outright.

## What they do not do

Not a parser, no type checking. A wrong argument count, a misspelt local, an
`int` where a `Vector2` was wanted — Godot finds those and these do not. What
these catch is the class of mistake that stops a file loading at all, which is
the class that costs a trip to the device to find.
