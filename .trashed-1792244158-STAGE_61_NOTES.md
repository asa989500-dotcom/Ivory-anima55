# Stage 61 — the line-88 fault, and a pass over `tool_panels.gd`

## The error you photographed

```
Error at (88, 9): Identifier "relabel" not declared in the current scope.
Line 88 (CONFUSABLE_LOCAL_USAGE): The identifier "relabel" will be shadowed below in the block.
```

Both messages were about one mistake, not two.

In GDScript a lambda captures the names it can see **at the moment it is
written**, not at the moment it runs. `pick` was written above `relabel` and
called it. At the moment `pick` was built there was no `relabel` yet, so the
name inside it pointed at nothing — that is the error. The warning was the
compiler noticing that a `relabel` *does* appear further down the same block,
and telling you the name means two different things in one function.

Moving `relabel` (and the two small helpers it now leans on) above `pick`
clears both. Nothing else was needed for the file to compile.

## Whole-project sweep

A scope-aware check was run over every `.gd` file in the project — all of
`scripts/` and `scripts/ui/`, a little over eight thousand lines.

- `tool_panels.gd` was the only file with a use-before-declaration.
- No calls to methods that do not exist on any project class.
- No duplicated function names within a file.
- No mixed tabs and spaces anywhere.

## What else was repaired in `tool_panels.gd`

**Faults that had not surfaced yet**

- `pick` took parameters named `family` and `shape`, and the loops below
  declared locals with the same two names. Same species as the `relabel`
  fault. Renamed to `at_family` / `at_shape`.
- The brush index is clamped on the way in. That index outlives the list it
  points into — the library has grown from eight presets to forty across
  builds — and a stale index would have indexed past the end of the button
  array and taken the panel down before it ever appeared.
- The symmetry-count buttons decided which one was lit by comparing their own
  printed **labels**. Two counts that happened to render the same string would
  have lit together. They compare numbers now.

**Things that were quietly wrong**

- *Brush size and opacity.* Every preset carries its own defaults, and `App`
  applies them the instant the brush changes. The two sliders never heard
  about it: they went on showing the previous brush's numbers while the canvas
  painted with the new one's, and the first touch of a slider snapped the size
  to something nobody asked for. They follow the choice now.
- *The Light note.* It was written inside the pick handler, so opening the
  panel with Light already selected showed nothing at all. It is its own
  callable now and runs on the way in as well.
- *The harmony chips.* They were restated only when the wheel itself was
  touched. Taking a colour off the canvas with the dropper, or off the recent
  row, left five chips suggesting partners for the colour before last.
- *The recent colours.* One sweep across the hue ring filed every colour it
  passed through as a choice, so twelve slots meant for the colours of the
  drawing filled with the path a thumb took. `App.set_ink_live` sets the
  colour without recording it; only the colour the finger settles on is filed.
  `ColorWheelControl` gained a `released` signal to mark that moment.
- *The wheel marker crawling under the finger.* The panel writes `App`'s
  colour back into the wheel, and mid-drag that is the wheel's own value
  returning through Oklab and out again. The small loss each way was enough to
  drag the marker off the finger. `is_adjusting()` skips the write-back.
- *Puppet warp, Grid.* Opened at a flat 34 whatever the mesh actually was, so
  the first touch rebuilt it at an unasked-for density. `PuppetWarp.cells`
  now reports the real value.

**Buttons that answered a press with silence**

A button that does nothing reads as a broken app, not as a button that did not
apply. These are dimmed instead: *Draw the curve* and *Clear points* outside
curve mode, *Paste* with an empty clipboard, *Undo the last pull* with nothing
to undo, and the three depth controls with no pin chosen. Tolerance and Tuck
dim together when the fill shape is not *Between lines*.

**Weight**

Typing in the text tool re-rendered the whole text layer on every keystroke —
a full re-shape and re-blit per letter, and a fast typist outruns it. The
redraw waits for a breath in the typing now. The last keystroke always gets
its redraw, a tenth of a second later.

**Shape of the file**

Five panels each carried their own copy of the same twelve lines: build the
buttons, remember which index means what, then a second loop wiring each press
to un-press the others. Five copies is five chances to get it subtly wrong,
and one of them had already drifted. They share one `_choice` helper now.

## Files touched

- `scripts/ui/tool_panels.gd` — rewritten
- `scripts/ui/ui_kit.gd` — `slider_set`, so a row can be moved from code with
  its readout
- `scripts/ui/color_wheel_control.gd` — `released`, `is_adjusting`
- `scripts/app_state.gd` — `set_ink_live`, `set_fill_ink_live`
- `scripts/puppet_warp.gd` — `cells`

## One honest caveat

There is no Godot binary and no network in the environment this was fixed in,
so the verification was static analysis of the source, not a real compile. It
is reliable for exactly the class of fault you photographed. Open the project
once and confirm the error counter reads zero before building on top of it.
