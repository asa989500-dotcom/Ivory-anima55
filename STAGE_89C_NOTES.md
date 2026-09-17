# Stage 89c — the new errors, and the touch space

## The errors

### `tool_panels.gd:177` — `LIGHT_NAMES` does not exist

It never did. The library keeps **one** table, `SPECIAL_NAMES`, keyed by family
id, and Light is one of five families in it.

Reading that table instead of a name invented for Light alone fixes the error
**and repairs four families that were silently wrong**: Cloud, Foliage, Skydust
and Sketch each carry their own five words — Thunderhead, Frond, Fireflies,
Charcoal — and the shape buttons were showing every one of them as
"Plain / Fine / Broad / Rough / Soft", while the brush list two panels away
named them correctly. It is now the same table `_build` uses to name the
presets, so the two can no longer disagree.

### `snapped` shadows a built-in

`snapped()` is a global GDScript function. The local hid it, so the next person
wanting real snapping in that function would get a Vector2 back from what looks
like a call. Renamed to `pinned`.

### The last integer division

`anim_player.gd:454`, `int(packed.size() / 3)`. Now `int(float(...) / 3.0)` —
same value, no warning.

**Sweeps after: 0 integer divisions, 0 shadowing, 0 unresolved symbols.**

> These surfaced only now because compilation used to stop at `distort.gd`.
> Each fix uncovers the next layer; this is the expected shape of it.

---

## The space — built precisely

Godot already routes a press to the topmost control that accepts one, so a tap
on a button is the button's and a tap on bare canvas is the canvas's. That part
always worked. Two things it does not cover, and **both reach the user as the
drawing going wrong rather than as a mis-tap**:

### 1. The system gesture strips — and the cut-off strokes

Android reserves a band along the bottom for the navigation bar, and on gesture
navigation a strip down **each side** for the back swipe. A stroke that *begins*
inside one is not a stroke: a few events arrive, then the OS decides the gesture
was meant for it and stops delivering. The app sees a pointer that goes quiet.

**The user sees a line that cuts itself off partway.**

That is the stage-11 complaint — *"strokes sometimes cut themselves off
mid-draw"* — reported as a drawing bug and very likely never a drawing bug at
all. It cannot be won once it has begun, so `TouchSpace.may_begin` refuses to
*start* there.

**A stroke already running is never touched.** The system claims a gesture it
saw the beginning of, so once the finger is drawing, the strip is ordinary
screen and a long diagonal into the corner finishes properly. Refusing
mid-stroke would break long diagonals for nothing.

On a 412×915 phone reporting a 48 dp navigation bar, **84% of the screen still
starts a stroke**, and 100% of it continues one.

Desktop is exempt entirely — no back-gesture inset, no navigation bar, and
reserving the edges would take the sides of the canvas away from a mouse that
was never going to lose that argument.

### 2. Panels are not solid to touch

A floating card is rounded, padded and separated. The corners, the margins and
the gaps between its rows **are not controls** — a press there falls straight
through and draws a mark inside what the user sees as a solid opaque panel.
That is the drawing area fighting the controls, exactly.

Panels now register their whole footprint, refreshed on every layout so a panel
that grows a row cannot leave a stale rect behind, and released on close. This
one applies on desktop too: a mouse falls through a gap just as a finger does.

### Touch targets — checked, already correct

`make_tool_button` is 52 dp and `make_text_button` 44 dp, both above the 44–48 dp
floor every platform's guidance settles on. `TouchSpace.reachable` exists for
any control that needs raising without changing how it looks, but nothing in the
existing rail needed it. **Reporting this rather than changing it**: a sweep that
finds the code already right is a result too.

---

## Still not verified on a device

Everything above is reasoned from platform behaviour and checked arithmetically.
The one thing I cannot do from here is *use* it. If a specific button is still
fighting the brush, a screenshot of that spot turns this into a measured fix.
