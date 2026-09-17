# Stage 64 — eighty-eight errors, one word

Your instinct was right, and it was right for a better reason than "a few
lines". It was **one word**, used thirty-four times.

## What happened

I named the inner class holding one rig pose `Key`.

`Key` is a **global enum in Godot** — the one that carries `KEY_A`,
`KEY_ESCAPE`, `KEY_SHIFT`. A global enum outranks an inner class of the same
name, so every `var k: Key` in `rig_track.gd` was declared as *the keyboard
enum*, not as my class. From there the compiler was simply telling the truth,
over and over:

```
Cannot get property from enum value.        ← k.frame  (enums have no .frame)
Cannot call function on enum value.         ← k.is_empty()
Cannot return value of type "null" ...      ← an enum can't be null
Cannot assign a value of type Key to
        variable "k" with specified type Key   ← my Key vs Godot's Key
```

That last line is the whole diagnosis printed in one sentence: two different
things called `Key`, and the compiler picking the other one.

Thirty-four uses of the name across three or four property accesses each is
eighty-eight complaints. Renaming the class to `RigKey` clears every one of
them. No logic changed — not a single line of the interpolation, the switching
or the IK. The maths that was tested and passed is the same maths.

## Making sure it cannot happen again

A name that silently loses to a Godot global is a trap that gives no warning
until it gives eighty-eight. So the whole project was swept against Godot's
global enums and its common global class names — every `class`, every
`class_name`, every `enum`.

**Result: no other collisions.** For the record, the inner class names now in
the project are:

```
Bone   Clip   Focus   Group   Joint   Layer   Page   Pin
Pose   Preset Project RigKey  Ring    Shot    Swap   TextSheet
```

`Joint` is worth a note: it *was* a global class in Godot 3, and would have
collided. In Godot 4 it was renamed `Joint3D`, so the bare name is free — which
is why it has been compiling all along.

## One thing found while re-reading

Not an error, and it would not have shown up as one — it would have shown up
as heat.

`set_switch_index` emitted `changed`, which rebuilds the layers panel. During
playback a mouth chart steps several times a second, so a lip-synced scene
would have rebuilt that whole panel several times a second to redraw rows
nobody is looking at while a clip plays.

It now takes an `announce` flag, and playback passes `false`. The drawing still
changes on every single step — only the announcement is withheld. Scrubbing and
editing by hand still announce, because then the panel *is* what you are
looking at.

## Verified again after the rename

- use-before-declaration: **0**
- bracket balance across all 43 scripts: **0 problems**
- duplicate function names: **none**
- unused parameters: **none**
- integer-division warnings: **none**
- shadowed built-ins or base-class properties: **none**
- mixed tabs and spaces: **none**
- global-name collisions: **none**

## Honest note

Renaming a type is the one kind of change static analysis catches well, and
this one it catches completely: every use of the name is in one file and every
one of them moved together. But it remains static analysis, not a compile.
Open the project and check the counter — it should read zero. If anything
remains, it will be something new rather than a remnant of this, and the
screenshots you send are what makes that quick to find.

Files touched: `rig_track.gd` (rename only), `bspline_room.gd` (one type
reference), `layer_stack.gd` and `anim_player.gd` (the `announce` flag).
