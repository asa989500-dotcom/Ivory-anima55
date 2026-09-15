# Stage 145 — smart bones, the 2.5D deformer, and one plus sign fewer

Three things happened in this pass: the errors that stopped the project
loading were fixed, two new C++ modules were written for the Character 360
rig, and the layers panel lost the button it should never have had.

---

## 1. The errors that stopped the project loading

Six parse errors and four warnings, all of them from two habits.

### `var x := ...` where the compiler cannot work out the type

```
Error at (198, 18): Cannot infer the type of "state" variable
because the value doesn't have a set type.
```

`:=` asks the compiler to work the type out, and it can only do that when
the right-hand side already has one. Three shapes never do:

| shape | why |
|---|---|
| `model.export_state()` where `model` is `Object` | the compiler does not know which class, so does not know what the method returns |
| `a if c else b` | a ternary has no static type in GDScript, even when both sides do |
| `d["k"]` on an untyped container | the result is `Variant` |

Every one of these parses fine on its own and fails at load, which is the
worst way to find out — the whole script fails, and so does every class that
mentions it.

Fixed by writing the type down, which is what this project asks for anyway:

| file | line | fix |
|---|---|---|
| `scripts/ui/character360_builder.gd` | 198 | `var state: Dictionary = model.export_state()` |
| `scripts/ui/character360_builder.gd` | 120 | `var picker: FileDialog = ...` |
| `tests/test_text_tool.gd` | 39, 43, 52, 69 | `Rect2` / `Rect2` / `float` / `float` |

### Broken indentation in a vendored addon

`addons/gde_gozen/video_playback.gd:391` — `Expected indented block after
"if" block`. Four `print()` lines inside `_sync_audio_video` had lost their
indentation. Repaired by finding every line whose block opener is not
followed by anything deeper, which found those four and nothing else.

Worth recording that the first attempt at this was wrong: a rule of "indent
to match the previous line" also re-indented two correct lines that happened
to follow a deeper block. The rule that works is narrower — only a line whose
*opener* ends in a colon and which is not deeper than that opener.

### The warnings

| warning | where | fix |
|---|---|---|
| `SHADOWED_VARIABLE_BASE_CLASS: size` | `character360_builder.gd` `_make_rig` | the parameter was shadowing `Control.size`; renamed `art_size` |
| `CONFUSABLE_LOCAL_DECLARATION: rows` | same file | inner one renamed `native_rows` |
| `"l" is declared below in the parent block` | `move_tool.gd` `commit` | hoisted to one declaration at the top |
| `"before" is declared below in the parent block` | same | same |

### The missing `.so` files

The errors about `libivory.android.template_debug.arm64.so` and
`libgozen...so` are **not** a fault in the code. They are the GDExtension
binaries, which have to be built for arm64 before the app will load them.
`tools/build_native.sh` does that. Until it is run, every native class is
absent and the app falls back to GDScript throughout — which is by design
and is why every module in `native/` has a GDScript fallback.

---

## 2. A new detector: `tools/check_inference.py`

Added to `check_all.py`, so the error above cannot come back.

It catches the three shapes listed in the table above. Verified against
hand-made examples: it finds all three and leaves `var ok := 1 + 2` alone.

```
probe.gd:3  `var state :=` — `model` is Object; `export_state()` has no
            known return type.  Write the type: `var state: <Type> = ...`
```

---

## 3. `IvorySmartBone` — smart bones, the Moho model

**2003 checks, 0 failures** (`native/ivory/tests/test_smartbone.cpp`)

A smart bone is not a cleverer bone. It is a **dial**: one bone whose angle
drives a stored correction to the rest of the rig.

The problem it solves is the oldest one in rigging. Bend an elbow ninety
degrees with any skinning method at all and the inside of the joint pinches,
because the shape the artist wants at ninety degrees is not a smooth function
of the shape at zero — it is a *different drawing*, and no interpolation of
transforms will invent it. So: let the artist fix it by hand once, store the
fix, and fade it in whenever the elbow passes through that angle. In every
shot, forever.

Four decisions, each documented at length in `ivory_smartbone.h`:

1. **Keys are on driver angles, not on frames.** Keyed on the timeline, a
   correction is only right in the shot it was authored for. Keyed on the
   driver's angle, it is right every time.
2. **Corrections are added, never substituted.** A build without the library
   still poses correctly, only without the corrections — the rule the whole
   native layer follows.
3. **Between keys it interpolates exactly; past the ends it holds.**
   Catmull–Rom passes through every key, so the artist gets the shape they
   authored. Past the last key it holds rather than extrapolating: a cubic
   run past its data grows without bound, and that is a limb turning inside
   out the moment somebody drags further than the artist tested.
4. **A dial may not drive its own driver, at any remove.** That is a feedback
   loop that oscillates at the frame rate — on screen, the rig starts shaking
   for no reason. `set_key_bone` walks the dial graph and refuses it, at the
   moment of authoring, which is the only place it can be explained.

`set_overshoot(false)` gives the monotone answer for a mechanical joint.
Worth knowing, and the bench found it: a dial authored the sensible way —
steadily rising, or a single peak — never overshoots even in the mode that
permits it. Overshoot needs a plateau with a rise on either side.

---

## 4. `IvoryDeform` — the 2.5D deformer

**427 checks, 0 failures** (`native/ivory/tests/test_deform.cpp`)

Five stages, each answering one of the complaints:

| stage | what it fixes |
|---|---|
| blend the transforms in the log, not the results | the wrist collapsing when twisted (the candy-wrapper) |
| depth and foreshortening | "it slides instead of turning" — a nose at depth 30 travels six times as far as a cheek at depth 5 |
| bulge | the inside of an elbow squeezing to nothing |
| ARAP relaxation + a hard strain limiter | **the shape breaking during motion** |
| a one-pole filter with a coefficient from the frame time | "the motion is nervous" |

With depth at nought, bulge at nought, no relaxation and no smoothing, it
returns exactly what plain skinning returns — and there is a test that
asserts that, so nothing here can be blamed for a regression in the base rig.

### Measured

| | before | after |
|---|---|---|
| worst edge, 99° bend | 188% | **49%** |
| mean strain | 8.2% | **1.6%** |
| joint width at 135° | — | 74% of rest (does not collapse) |
| drift over 1000 held frames | — | **0.00000 px** |
| exact on a rigid rotation | — | distortion 0.00000003 |
| full-size mesh, 2000 points / 7642 edges | — | mean 1.016, distortion 0.056 |

The remaining worst-case edge is one or two triangles at the crease, and it
is **not a fault in this code** — the deformer is exact on rigid rotations
and on uniform scales, so what is left is the intrinsic pinch of linear blend
skinning. Which is precisely why smart bones exist.
`test_a_smart_bone_fixes_what_skinning_cannot` demonstrates it: a stored
correction takes the mean strain from 4.9% to 2.3%.

### Four bugs the bench found in my own code

The tests were not decoration. They caught, in order:

1. **A read past the end of an array.** Calling `set_weights` before
   `set_bones` left a weight table of the wrong length, which `solve` then
   read past. An API that is only correct when called in one particular
   order will be called in the other one. The raw table is now kept and
   re-shaped whenever either changes.
2. **The relaxation diverged.** A full correction per edge sent the mesh to
   thirty times its size in four passes, because a point in a triangulated
   grid has eight edges on it. Corrections are now accumulated per point and
   their mean applied, with over-relaxation at 1.6.
3. **The anchor blend was wrong.** Rotating about the blended joint applies
   one rotation to a point that two different rotations should have been
   applied to — measured as a 60% compression across the joint. Replaced with
   a true similarity blend.
4. **A segfault** in the strain limiter when relaxation was turned off and
   the scratch arrays had never been sized.

### Touch

`pick` uses the larger of a physical minimum — a fingertip is about nine
millimetres and no amount of zoom changes that — and a share of the local
mesh spacing. And once something is caught it stays caught until the finger
lifts, however far it wanders: a drag that silently changes what it is
dragging is worse than one that goes somewhere unhelpful.

### Undo

A bounded ring, budgeted in **bytes rather than steps**, because the same
hundred steps are nothing on a mesh of forty points and thirty megabytes on
a mesh of forty thousand. Undoing also drops the smoothing state — undoing
and then watching the drawing slide back over a quarter of a second is not
undoing.

---

## 5. The layers panel: one plus sign fewer

There were two `+` buttons a few pixels apart with the same icon. One made an
ordinary layer; the other quietly made a bone layer, which is a layer nobody
can draw on. It is gone.

The remaining button reads where the selection is and decides for itself:

- **inside a Character 360 file** → a Character 360 sub-layer, already bound
  to that file's motion bones, and a normal drawing layer in every other
  respect;
- **anywhere else** → an ordinary layer;
- **a folder is selected** → above the folder and outside it, so a folder can
  still be built on top of.

Bone layers are no longer something a finger can create. The Character 360
builder makes exactly one, for the file it builds, and that is the only way
one comes into existence. It still refuses ink.

The builder now puts the character and its motion layer in **one folder** — a
Character 360 *file*. That folder is what makes the rule above work.

New in `layer_stack.gd`, lifted into `scripts/layer_character360.gd`:
`character360_group`, `in_character360_file`, `character360_motion_layer`.

---

## 6. The timeline: duplicate, never blank

On a rigged layer the frame button used to walk the playhead on and leave the
skeleton behind, so the next bend keyed a pose with nothing before it to
travel from — and the character snapped into place instead of moving into it.

It now does **Duplicate After**: the pose at the playhead is carried onto the
next frame and a key is placed there. The same pose, one frame later, as a
place to change something.

Never a blank key. A blank key on a rigged layer is a character collapsing to
its rest pose for one frame, which is the most alarming thing a timeline can
do.

And a Character 360 file moves as one block, so **every layer in the file**
arrives at the new frame together. Carrying only the selected one would leave
the drawing in one place and its own outline in another.

Covered by the usual undo/redo through `snapshot_state` / `record_state`.

Lifted into `scripts/ui/timeline_pose_frames.gd`.

---

## 7. Housekeeping

The size checker refused to record the new work, and it was right to: the
ledger had been stale since before this stage. Rather than rewrite it, the
debt was paid down.

Nine sections lifted into their own files, unchanged, each leaving a
one-line delegate so no caller anywhere moved:

| new file | from |
|---|---|
| `scripts/layer_arrangement.gd` | `layer_stack.gd` |
| `scripts/layer_character360.gd` | `layer_stack.gd` |
| `scripts/ui/timeline_pose_frames.gd` | `timeline_panel.gd` |
| `scripts/puppet_warp_draw.gd` | `puppet_warp.gd` |
| `scripts/puppet_warp_arap.gd` | `puppet_warp.gd` |
| `scripts/puppet_warp_build.gd` | `puppet_warp.gd` |
| `scripts/puppet_warp_pins.gd` | `puppet_warp.gd` |
| `scripts/ui/bspline_room_draw.gd` | `bspline_room.gd` |
| `scripts/canvas_view_draw.gd` | `canvas_view.gd` |
| `scripts/canvas_view_gesture.gd` | `canvas_view.gd` |

Total debt: **6999 → 5889**, with every file inside its own limit for the
first time in a while.

One thing to know about `tools/lift_module.py`, found the hard way: it
mangles a multi-byte UTF-8 character in a comment into three stray bytes,
including NULs, which is a parse error with no useful message attached. Two
files were hit and repaired. Anything lifted in future should be checked
with `grep -c -aP "\x00"` immediately afterwards.

---

## Where things stand

```
All 15 checks passed.

pass  test_comic                 (99 checks)
pass  test_store                 (36 checks)
pass  test_lang                  (66 checks)
pass  test_brush                (124 checks)
pass  test_blend                 (57 checks)
pass  test_pose                  (73 checks)
pass  test_arbiter               (63 checks)
pass  test_field                 (32 checks)
pass  test_spline                (93 checks)
pass  test_depth                (310 checks)
pass  test_rig360               (110 checks)
pass  test_character360_ultra    (70 checks)
pass  test_smartbone           (2003 checks)     <- new
pass  test_deform               (427 checks)     <- new

--- all native tests passed ---
```

## Not done

The new C++ classes are registered and reachable from GDScript through
`Native.smartbone()` and `Native.deform()`, but the Character 360 room does
not yet call them — it still uses `IvorySkin` and `RigSkin`. Wiring the room's
posing path onto `IvoryDeform`, and giving the timeline a way to author a
dial, is the next piece of work.

And `libivory.android.template_debug.arm64.so` still has to be built with
`tools/build_native.sh` before any of the native path runs on the tablet.
