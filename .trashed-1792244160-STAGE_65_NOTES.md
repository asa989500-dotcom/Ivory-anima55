# Stage 65 — tangled lines, marks on the compass, and where 360 belongs

## 1. Tangled lines

Straight lines that arrive already joined. Only the first is drawn freely;
after that each new line starts exactly where the last one ended, so you place
**one** point instead of two and the corners meet exactly rather than nearly.

It is in the compass, as you asked, with its own mark.

**Why it is not the curve tool renamed.** The curve gathers points and commits
one smoothed run when you press *Draw*. A chain commits each straight segment
the moment it is drawn — so what is on the canvas is always everything you
have made so far, and stopping is simply not drawing the next one. Nothing to
press, nothing to lose if you walk away mid-shape.

Underneath it *is* the shape tool, deliberately: it inherits your brush, your
colour, your pressure and your undo without a line of new code for any of them.

Three details that decide whether it feels right:

- **The live end is drawn on the canvas** — a small ringed dot where the next
  line will start. Without it the tool is guesswork after the first line: you
  know a chain is running but not from which corner, and the two ends of a
  short segment are a thumb's width apart.
- **A tap that goes nowhere is a tap, not a line.** A stray touch would
  otherwise lay a zero-length segment and move the anchor onto itself, which
  looks exactly like the chain has stopped working.
- **The chain lets go when you change tools.** Reaching for the brush ends the
  run, so coming back later starts a fresh line instead of springing one out of
  a corner you no longer remember choosing. There is also *Start a new chain*
  in the shapes panel, for letting go without changing tools.

`App.Shape.CHAIN` was **appended** to the enum, never inserted — those numbers
are written into saved projects, and inserting one would have turned every
saved Rect into an Ellipse.

## 2. The compass now has marks as well as names

Your four icons are in, under the project's own naming:

| your file | installed as | row |
|---|---|---|
| `B-SPLINE/icons8-sculpture-64.png` | `bspline.png` | B-Spline |
| `tangled lines/icons8-window-64.png` | `tangled_lines.png` | Tangled lines |
| `txt/icons8-text-64.png` | `text_tool.png` | Text |
| `360 character/icons8-panorama-64.png` | `character360.png` | Character 360 |

Both the mark and the name, never one alone: **the mark carries the meaning
after the first week and the name carries it on the first day.** An icon by
itself has to be learnt before it helps; a name by itself has to be read every
single time. The rows follow the same shape the settings menu already uses, so
the app does not suddenly have two kinds of list.

## 3. Character 360 now appears only in animation projects

Removed from drawing and comic projects; B-Spline stays in all three.

The reasoning, so it holds up later: Character 360 builds a figure that is
**read at a moment in time** — eight poses, the in-betweens filled in, scrubbed
like a model. A still page has no moments to scrub. Offering it there was
offering a door onto nothing: the room would open and there would be no
timeline to send the turn to. Bending a drawing, by contrast, is as useful on a
comic panel as in a scene, so B-Spline is offered everywhere.

## 4. Getting close enough to rig

Two numbers in the 360 room were quietly making careful work impossible.

**The zoom ceiling was 16×.** That sounds generous until you try to put a child
point on a knuckle: at sixteen times, a knuckle on a full-figure turnaround is
still a few pixels across and the point lands on the finger beside it. Rigging
happens at the scale of the *joint*, not of the figure. The ceiling is now
**64×**. The floor came down to 0.02 as well, because the way back out matters
just as much — after working on a hand you want the whole figure in one
gesture, not four pinches.

**The grab radius was measured in page units** — 24 of them. That is a
different thing from what it looks like, and it fails at both ends: zoomed out
it caught everything within a hand's width; zoomed in — exactly when you are
working carefully — it shrank to nothing and the point you were reaching for
could not be caught at all.

It is now measured **on the screen** and scaled for the device, so the grab is
the same size under your finger at every zoom: a little under half a
centimetre, which is the width of a fingertip's contact patch and the figure
the platform guidelines settle on. Connect gets a slightly wider one than
Build, because joining two things already placed is a coarser act than placing
them.

Orbit was already its own mode, separate from Build, Connect and Test — so that
separation you asked for exists; what it needed was for the other modes to be
usable at close range, which is what the two numbers above fix.

---

## What I have not done, and why I am telling you rather than pretending

You asked for a great deal more in this message, and some of it is genuinely
large:

- **The AI filling in what it never saw** — soles of feet built automatically
  from the last colour up the foot, so a figure seen from below is coloured
  rather than hollow. This is real work: it needs the silhouette read per pose,
  the boundary colour sampled along the cut, and a fill that respects the
  figure's own shading. It is a good idea and I do not want to fake it with
  something that smears the bottom pixel row downward.
- **Base bones forming automatically on the eight poses.**
- **Bone animation tied to the timeline's *duplicate after* button** — the
  ground for this is already in from stage 63 (`RigTrack`, `record_key`), and
  what remains is the timeline wiring.
- **Comics, ordinary drawing, and the brushes.**

There is no Godot in this environment, so anything I write blind I cannot
check — and the last two stages were both a reminder of what that costs. What
I did this time is what I could verify: a small tool built on a path that
already works, four icons, a gate, and two numbers.

Tell me which of the four above matters most and I will take that one properly
next, the way `RigTrack` was taken — designed against the existing grain,
tested where testing is possible, and honest about the rest.

## Files touched

`app_state.gd` (CHAIN appended) · `canvas_view.gd` (chain state, press,
release, preview, tool-change break) · `tool_panels.gd` (compass rebuilt with
icon rows, shapes panel gains Tangled and *Start a new chain*) · `main.gd`
(compass gate, `begin_tangled_lines`) · `room360.gd` (zoom range, screen-sized
grab) · four icons into `assets/icons/`

Static analysis clean: use-before-declaration 0, brackets balanced, no
duplicate functions, no unused parameters, no shadowing, no global-name
collisions.
