# Stage 89h — the two errors, and the checker that stops this shape of mistake

## The bug

`bspline_room.gd:1567–1568`. Two lines still reading a node I had removed:

```gdscript
if _mesh_node != null:
    _mesh_node.texture = _art_tex
```

Mine. Last stage I found that this node was never assigned and drew the posed
mesh directly instead — which was the right fix — and deleted its declaration.
I missed these two lines, which were its last readers.

GDScript rejects an undeclared identifier at parse time, so it did not break
the B-Spline room. It broke **everything**.

Removed. The texture is read straight off `_art_tex` at draw time now, so there
is nothing left to hand it to.

## Why it happened twice

Two stages, two builds broken, and the same shape both times: **I changed
something and missed one of the places that used it.**

- `save_sprite_sheet` — added a failure path, gave up with the wrong kind of
  nothing
- `_mesh_node` — removed a declaration, left two readers behind

Both are invisible to reading and obvious to a parser. So the answer is not to
be more careful; it is to have something that checks.

## `tools/check_identifiers.py`

Collects every `_name` declared in a file — members, locals, parameters,
loop variables, constants, enum members, inner classes — and flags every `_name`
read that is not among them.

**Only underscore names.** In this codebase a leading underscore always means
"private to this file": never a global class, never an autoload, never a Godot
built-in. That makes the rule exact rather than approximate — if a `_name` is
read here, it must have been declared here. Anything without the underscore is
left alone, because deciding whether a bare name is a global class, an enum
member or a typo needs a real parser, and a checker that guesses is a checker
that gets switched off.

Declarations are gathered across the whole file, inner classes included — a
*superset* of what is really in scope. So it can miss a real error but can never
invent one, which is the safe direction for something that runs on every build.

**Proved, not assumed.** The bug was put back, the checker run, and it reported
both lines:

```
scripts/ui/bspline_room.gd:1567  '_mesh_node' is used but never declared in this file
scripts/ui/bspline_room.gd:1568  '_mesh_node' is used but never declared in this file
--- 2 undeclared identifiers ---   (exit 1)
```

Then the fix was restored and it reports zero.

## `tools/check_all.py`

One command, so there is no way to run three of the four and ship on the fourth:

```
$ python3 tools/check_all.py .
== check_identifiers.py      --- 0 undeclared identifiers ---
== check_returns.py          --- 0 impossible returns ---
== check_continuations.py    --- 0 suspect continuations ---
== check_shadow.py           --- 0 redeclarations ---
All 4 checks passed.
```

It exits non-zero if any of them fails. This runs before every zip from now on,
along with the cross-class symbol sweep.

## Also

The dead name was still sitting in the explanatory comment, so searching the
project for it landed on the explanation instead of coming back empty. Reworded
— a search now finds nothing, which is what "removed" should mean.

Everything from stage 89g is intact: the posed mesh is drawn, posing is
coalesced to one pass a frame, two bones meeting show one joint, the exit is
gold and findable, and the room is the logo's blue.
