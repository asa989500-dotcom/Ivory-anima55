# Stage 89b — the errors, the placement box, and the memory ceiling

## 1. The thirteen errors in the screenshots

### The one that stopped everything

`distort.gd:233` — `Image.INTERPOLATE_AREA` **does not exist in Godot**. It is an
OpenCV name. Nothing compiled while it was there.

Replaced with `INTERPOLATE_TRILINEAR`, which is what Godot means for shrinking:
it builds mipmaps first, so every source pixel contributes instead of three
quarters being thrown away — the artefact area-averaging exists to avoid.

**The same wrong name was in `exporters.gd` twice more**, at lines 315 and 692.
They had not been reported yet only because compilation stopped before reaching
them. Both fixed.

### Shadowing

| where | what | why it mattered |
|---|---|---|
| `layer_stack.gd` | `scale` shadows `Node2D.scale` | read as though the rig were resized by moving the stack — the one thing it must not do |
| `rig_skin.gd` | `mesh` shadows `MeshInstance2D.mesh` | made the two lines after it read as assigning something to itself |
| `anim.gd` | parameter `reach` hides `reach()` three functions above | a trap for whoever next writes `reach(stack)` in that body and gets an integer |

### Integer division — removed, not silenced

Sixteen sites across the whole project. A warning you have decided to ignore is
a warning you will go on ignoring when it is finally telling you something, so
none of these are suppressed.

In the transfer compositor they are gone entirely: `_by255` computes
`round(v / 255)` as `(t + (t >> 8)) >> 8` with `t = v + 128`. **Checked against
all 65,026 possible inputs, not sampled — zero mismatches.** The largest product
that can reach it is 255 × 255 = 65,025, inside the range where the identity
holds.

Everywhere else the numerator became an explicit `float`. Truncation toward zero
is identical in both, so no value changed. One site — a grid row from a slot
number — is genuinely a whole-number division and is marked
`@warning_ignore("integer_division")` with a note saying why.

**Final sweep: 0 integer divisions, 0 shadowing warnings, 0 unresolved symbols.**

---

## 2. The placement box

The transfer used to finish the moment the last question was answered, so the
drawing landed where the arithmetic put it — centred, which is the only sensible
guess and is a guess.

`DrawTransfer.run` is now `prepare` and `land`. The arithmetic still runs to the
end; it just stops before the page. What comes back is the pieces at their final
resolution and one flattened picture of them. Then the target project is
**opened and focused**, and that picture floats in it.

**It rides the ordinary selection box.** Same handles, same rule that pressing
outside puts it down — that box is already the thing in this app meaning "not
committed yet, move me", and teaching a second gesture for the same idea would
be the wrong kind of new. The rule you asked for was already in the code at
`canvas_view.gd:1107`; nothing had to be invented for it.

What changes is what *committing* means. A floating selection stamps itself onto
the layer beneath. This one asks `DrawTransfer.land` to lay its pieces down as
the layers they were — one layer or several, as chosen — at wherever the box was
left. Still one undo entry for the whole arrival.

Verified: an untouched box lands the drawing exactly where the fitting put it;
moved, every piece keeps its offset to the pixel; scaled to 0.6, six pieces stay
aligned to within nothing at all.

**One decision, and it is a real one: no rotation while placing.** A rotation
must be resampled into each piece separately, and six pieces each turned through
an angle do not compose back into the picture the box was showing — the preview
would be a promise the landing could not keep. The rotate handle is hidden while
placing and returns immediately afterwards, where the selection tool can turn
the landed layer properly.

Leaving focus cancels a placement rather than stranding handles over a page that
is no longer under them. Nothing was written, so it costs nothing.

The tool switches to Select automatically on arrival — otherwise the first
stroke meant to nudge the drawing would draw a line across it.

---

## 3. Memory

`Image.create_empty` **does not fail politely.** The allocation happens in C++
and the operating system kills the process, which reaches the user as the app
vanishing with their work in it. So sizes are now asked about before they are
asked for.

`Perf.pixel_ceiling` / `can_hold` / `fit_within` / `make_image`, tied to the
performance tier already being tracked — a phone that has been dropping frames
is a phone with nothing spare.

**Calibrated against real pages, not guessed.** My first numbers refused an A4
page at 300 dpi on a slower device, which would have been a worse bug than the
one being fixed:

| | Mpx | LOW | MEDIUM | HIGH |
|---|---|---|---|---|
| Full HD | 2.1 | ok | ok | ok |
| A4 300 dpi | 8.7 | ok | ok | ok |
| A3 300 dpi | 17.4 | ok | ok | ok |
| 8-page spread | 48.6 | shrunk | shrunk | ok |
| 40-page spread | 243 | shrunk | shrunk | shrunk |

A spread **shrinks rather than refusing**: "here is your comic, smaller than the
pages are" is a real answer; "this comic cannot be exported" is not.

### The frames array — the actual crash

`render_frames` keeps every rendered frame alive at once, because a GIF with one
palette and a sprite sheet both need to see all of them. Three hundred Full HD
frames is two and a half gigabytes, in one go, in the middle of an export the
user has been waiting on.

Now budgeted. Repeats cost nothing — a drawing held for two seconds is appended
by reference, so only new renders count. Calibrated so ordinary exports never
come near it:

| | LOW | MEDIUM | HIGH |
|---|---|---|---|
| GIF 800-wide preset | 111 | 250 | 500 |
| WebP 960 preset | 77 | 173 | 347 |
| full-size Full HD | 19 | 43 | 86 |

The exporter's own caps are 600 / 400 / 256 frames, so the presets never reach
the budget at all. Only a full-resolution export of a long scene does — and for
that, being told "eighty-six frames, the rest left out" is a far better morning
than finding the app gone.

**And it says so.** `Exporters.last_short_by` is read after every export and
becomes part of the sentence. A scene that silently exports two thirds of itself
is the worst kind of bug: the file opens, it plays, and it is wrong.

### Flood fill

Already bounded at 3000 a side, but that is nine million cells and it holds
several byte maps of them at once — the allocation that ends a session on a
weak phone. The window now moves with the tier (1400 / 2200 / 3000). The search
itself does not get smaller: it always runs on a coarse map about 200 across, so
a tighter window costs reach past the page edge, which was never being used.

### PSD

`render_page` can now return null, and the PSD writer used the result
unchecked. It turns out `_raw_plane` already handles null by writing a
transparent plane — so a PSD would lose only its preview composite while keeping
every layer, which is what the format is for. Documented rather than changed:
losing the thumbnail beats losing the export.

---

## Not done

**UI/UX overlap between the drawing area and the controls.** You are right that
it needs testing rather than reasoning, and I could not test it — I have no
device here, and guessing at hit-boxes I cannot see would be the kind of change
that looks like work and creates bugs. If you send screenshots of where the
brush is fighting a button, that becomes a real fix instead of a guess.

## Checks

- Both repo linters clean; 52 scripts structurally clean.
- Every `Class.member` reference across the project resolved — 0 unresolved.
- 504 translation keys, 0 duplicates; 4 new strings in all seven languages.
- `_by255` exhaustively verified; placement transform verified for move, scale
  and multi-piece alignment; memory ceilings verified against five real page
  sizes and four export presets.
