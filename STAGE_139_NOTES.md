# IVORY — Stage 139

The app was broken. This stage finds out why, fixes it, and takes out the two
things you asked to be gone.

```
tools/run_native_tests.sh     1041 checks across 11 suites, 0 failures
tools/check_all.py            clean except check_size.py (pre-existing)
```

---

## 1. The twenty-two errors were one error

`lang.gd` had three keys defined twice — `"Apply"`, `"Depth"` and
`"Rest pose"`. I added them at stage 138 without noticing they already existed
further down the file. GDScript refuses a dictionary with a repeated key, so:

```
lang.gd fails to parse
  → ui_kit.gd fails to compile
    → audio_bank, audio_track, anim, project_manager, canvas_view, main …
```

Twenty-two errors, one cause.

**And it is the same cause as the missing text.** Not a second bug. Every
label in the app goes through `UiKit.label_for`, `ui_kit.gd` never loaded, so
every label came back empty and the interface came up blank. One repeated
dictionary key emptied the entire application.

The three duplicates are gone. 562 keys, none repeated.

### The checker that would have caught it

`tools/check_lang.py`, added to `check_all.py`. It checks three things:

* **no key twice** — the failure above;
* **every row the same width as the language list** — a row short of one
  language shows as a blank button, not an error, which is the worst kind of
  wrong because it looks deliberate;
* **no empty translation** — same reason.

It reads the language count off the `CODES`/`NAMES` table rather than having
the number written into it, so adding a seventh language does not need an edit
here.

## 2. The circle-with-a-check was the knife

I checked the icon pixel by pixel: `carve_trim.png` is a circle with a tick in
it. That was the knife tool, and the even rows of dots on your canvas were its
dots.

Gone completely — the rail button, `App.Tool.KNIFE`, `canvas_knife.gd`, the
knife brush family and its five variants, the `_draw_cut_points` overlay, the
`KNIFE_POINT_*` constants, the point-placement code in `IvoryBrush`, its tests,
and the icon.

## 3. The blend tool, where you put it

Your icon is in as `assets/icons/color_blend.png`, and the button is
**directly under the brush**.

Under it on purpose: the tool carries every brush shape there is — the same
stamp, read as *how much mixing happens where* rather than as how much ink
lands. A soft round mixes hardest in the middle; chalk mixes through its own
tooth and leaves the pits; the cell network mixes along its strands. It is a
way of using the brush, so it belongs where the hand already is.

Its panel has the five ways of bringing two colours together (mix, gradient,
smudge, average, snap), each with a line saying what it does, plus strength,
size, pick-up, and whether it may touch transparency — off by default, because
a blend tool that quietly erases is one nobody trusts.

The engine underneath is the one from stage 137, unchanged: OKLab, seven rounds
of tests, 57 checks.

**What is not done, plainly:** the dab pass is not yet wired to the layer
surface. Pressing with the tool selected currently does *nothing* to the
drawing rather than the wrong thing — I put an explicit guard in `_press` so it
cannot fall through to the brush's stroke path and paint. Doing nothing is
recoverable; painting an unasked-for stroke on a finished drawing is not.

## 4. Knitting is gone

Twenty-one files deleted — ten GDScript rooms and panels, eight C++ classes
(`IvoryKnit`, `IvoryYarn`, `IvoryWrap`, `IvoryKnitExport`), two test suites and
the icons. `Kind.KNIT` removed from the project kinds, and about a hundred and
thirty call sites cleaned out of `main.gd`, `canvas_view.gd`,
`project_manager.gd`, `vault.gd`, `layer_stack.gd`, the layer panels and the
settings sheets.

Zero references remain. Every checker passes.

## 5. B-spline — I found the actual cause

The room was never calling the solver I built at stage 138. It was still using
`spline.move_point` in GDScript, and that has two faults which compound into
exactly the stutter you describe:

**The curve cannot reach the finger.** A cubic B-spline's basis peaks at about
two thirds. Putting the control point where the finger is moves the curve two
thirds of the way there. The hand keeps going, the curve keeps lagging, and the
correction is reapplied every frame. It is not roughness in the sampling — the
curve is chasing something it is built never to catch.

**The correction lands on the grabbed point**, which need not be the one
governing the place under the finger. When it is not, most of the movement goes
somewhere the person is not looking while a neighbouring bend swings. Read,
fairly, as "it drags other points with it".

Now the room calls `IvorySpline.pull_at` in `MODE_ONE`, which solves

```
dP_i = (target − S(t)) / N_i(t)
```

— the curve lands on the finger **exactly, first time**, and the point it moves
is the one with the largest basis value there, so the correction is the
smallest possible. Because a cubic control point's basis is *identically zero*
outside four knot spans, everything else is not nearly unchanged, it is the
same number. That is checked on the raw floats in `test_spline.cpp`.

One detail that matters for the feel: the parameter is taken once when the grab
starts and held for the whole gesture. Re-deriving it from the finger each
frame would hand the drag to a different part of the curve mid-stroke, which is
the stutter wearing a different hat.

## 6. Canvas size — the triangle is gone

The `▾` was hiding every size in the app behind a target four millimetres
across, at the moment somebody has the least idea what the app can do. A
triangle is not a size: the only way to learn whether the size you want exists
was to open it, and to compare two, to open it twice.

Six tiles now, on the surface — Full HD, Vertical HD, Square 2K, 4K UHD, A4 at
300, and a comic page. Each shows its name, its proportion and its pixels, in
that order: the name is what you are looking for, the proportion is what you
are choosing between, the number is what you check afterwards. Six because six
fits two rows of three on the narrowest phone without shrinking below a
fingertip or scrolling, and a row of sizes that scrolls is a row whose last
item nobody picks.

Beside them, two boxes to type any size. Read on leaving the box as well as on
Enter — on a phone there is often no Enter, and a number typed and then tapped
away from must not be silently discarded.

The full table is still there behind a button that says **All sizes** rather
than a triangle that says nothing.

## 7. Colours — ten squares, no picker

The wheel, the hex pad, the code field and the eyedropper are all gone. All
four were ways of arriving at a colour by *adjusting* something, and on a phone
that is the long way round: the wheel is a ring a few millimetres wide under a
fingertip, and the number you land on is not the number you were aiming at.

Ten squares is one tap, always the same tap, and the same colour every time —
which is what makes a set of drawings look like a set.

The ten are the five that were there plus five filling what those could not
reach: a green, a violet, a warm neutral for skin and wood, the room's own
blue, and a true black kept separate from the near-black ink. The chosen one
wears a gold ring rather than a lightened fill, because on a palette holding
both a near-black and a true black a ring is the only mark visible on either.

## Still outstanding

* the blend tool's dab pass wired to the layer surface (see §3)
* more specialised settings, which you asked for and I have not reached
* `check_size.py`, failing since before stage 137 — chiefly `puppet_warp.gd`
  at 621 lines over
