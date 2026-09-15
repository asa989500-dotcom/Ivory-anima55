# IVORY Stage 122 — the wool becomes a material

## First, the `.so`

**I could not build it.** Not a refusal — this machine has no network access,
and the five submodules the native library is made of (FFmpeg, godot-cpp,
libvpx, libaom, emsdk) are empty folders in the archive. There is also no
Android NDK here. A cross-compiled FFmpeg cannot be produced without either.

What is here instead is `tools/build_native.sh`, which does the whole thing in
one command on a machine that *does* have the network:

    export ANDROID_NDK_ROOT=/path/to/ndk
    tools/build_native.sh android release arm64

It fetches the submodules shallow, builds, and drops the result straight into
`addons/gde_gozen/bin/` — which is the path `gozen.gdextension` already names,
so there is nothing to wire up afterwards.

The C++ from stage 121 is unchanged and still needs that build to run:
`GoZenAudio::decode_to_wav()`, and the `preset` / `audio_kbps` arguments on
`GoZenMP4Encoder::open()`. Brackets balance; it cannot be compiled here to say
more than that.

---

## The wool, from your list

I did **2, 3, 6, 7 and part of 8**. Below is what each one actually became,
and after that, honestly, what I did not do and why.

### 2 — Yarn as a material, not a mesh 🥈

New file: `knit_yarn.gd`.

A strand now records its **rest length** — how much yarn is between its two
pins — taken at the moment it is laid, and never changed by anything that
moves a pin afterwards. That single number is the whole difference. Before,
moving a pin moved the end of a line, which is a rubber band; that is exactly
why a moved arm looked like a photograph being stretched.

The five properties you asked for, per yarn type:

| | stretch | bend | twist | compression | elasticity |
|---|---|---|---|---|---|
| Roving | 0.20 | 1.00 | 0.05 | 0.46 | 0.40 |
| Ribbon | 0.02 | 0.30 | 0.00 | 0.08 | 0.90 |
| Twist | 0.04 | 0.40 | 0.85 | 0.14 | 0.88 |

Ribbon is nearly inextensible; roving gives a fifth of its length before it
argues. What happens on screen:

- **Ends pulled apart** → slack is taken up, then it goes taut, then the
  fibres catch the light along the run. That highlight is the cue that says
  *tension*, which the eye cannot read from length alone.
- **Ends pushed together** → the slack has to go somewhere, so it bows. Depth
  comes from the shallow-arc relation — height ≈ √(3·slack·span/8) — so a
  little slack over a long run is a gentle curve and the same slack over a
  short one is a loop.
- **Compressed** → it gets fatter, and pulled it gets thinner. A bundle of
  fibres under tension is narrower than the same bundle at rest.
- **Twist** → a spun cord pushed together does not simply bow, it wanders,
  because the twist has to go somewhere too. That coil grows with compression
  and vanishes as it is pulled straight.

**It is not a simulation, exactly as you asked.** Everything is closed form:
given two ends and a rest length, the shape is calculated, not iterated
towards. One square root and fourteen points. It is identical every time it is
asked, so it does not flicker during a scrub, and a taut strand short-circuits
to two points and costs nothing.

Each strand also carries its own `give`, so one run can be stiffer or looser
than its yarn normally is.

### 3 — Crossings that survive movement 🥉

This was the right call and it is now done properly.

Crossings used to be worked out entirely from where the strands are *now*.
Correct for a still board, wrong the moment anything moves: turn a character
and two strands cross at a different place, in a different order along the
run, possibly the other way round — so a strand plainly in front would flip
behind mid-turn. That is not a small visual error; it is the figure coming
apart.

Now: **which strand is on top is decided once, when the second is laid, and
written down.** `KnitBoard.Cross` is a fact about two strands. *Where* they
cross is still worked out from current geometry, because that genuinely does
change; the relationship does not. A stays over B through any deformation.

This needed strands to have real identity, so `Strand.id` exists — a crossing
recorded against "strand 7" was quietly becoming a crossing against whichever
strand slid into that place when one was deleted.

`set_over(a, b, on_top)` is public, because that is the thing a future control
flips: tap a crossing, the strand underneath comes over, and it stays over in
every pose afterwards. Old boards read as before — an unrecorded pair falls
back to "later strand in front".

### 6 — The yarn itself

- **Bouclé** now actually loops. Each loop is a full round of yarn standing
  proud of the core, drawn with its underside first so the core reads as
  passing behind it, plus the pinch where it leaves the core. Its detail rises
  with zoom, which is the moment somebody looks at it.
- **Roving** grows a halo of escaped fibres — deterministic, or a still board
  shimmers. Only close up; at distance a fringe is dirt on the screen.
- **Ribbon** has a face and an edge now: the bright band is the face catching
  the light, the dark line on the far side is its thickness seen nearly edge
  on. That is what makes it a strip of material rather than a wide flat yarn.
- Yarn is drawn along its curve, piece by piece, each with its own normal. One
  normal for a bent strand puts the highlight outside the curve at one end and
  inside at the other, which reads as the yarn turning over mid-run.

### 7 — Groups

`KnitBoard.Group`: a name, a switch, a lock. Hair, face, body, left arm,
clothes. Hidden strands are not drawn and not picked; locked ones are not
picked either, which is the one thing a lock is for. They do not nest — a part
of a character is a part of a character.

### 8 — Performance, partly

Dragging a pin used to throw the entire crossing cache away *every frame* — a
full quadratic pass per finger movement.

`forget_crossings_near(area)` now discards only strands whose run overlaps the
box swept by the change. The test is geometric on purpose: the obvious case is
the strands tied to the pin, but the one that catches people out is the
opposite direction — a strand nowhere near it can suddenly be crossed by one
that moved. A strand across the far side of a large piece is untouched, which
on a figure of several thousand strands is nearly all of them.

The cache is keyed by strand id rather than list position, so deleting one
strand no longer hands its answer to whatever takes its place.

---

## What I did not do, and why

**4 — Character 360 for wool.** Not built, deliberately. At stage 109 you
asked for Character 360 to be deleted entirely — the feature, its code and its
assets — and it was. Building a 360 system for wool would put it back through
a side door. If you want it back, say so and it goes back as a decision rather
than as a side effect of a wool request.

**5 — Pin types.** Not done. It is a real feature (fixed / bone / rotation /
stretch / feature pins) and it belongs on top of the bone rig, not beside it —
which means it wants a session of its own rather than a corner of this one.

**9 — Wool-specific undo.** Not done. It is the right idea and it is a large
one: every operation you listed needs an inverse, and doing half of it is
worse than none, because a history with holes in it is a history nobody
trusts.

**10 — Export into the rest of IVORY.** Not done. Note that the foundation for
it did land here: with stable strand ids, recorded crossings, rest lengths and
groups, a wool character now has everything a rig needs to attach to. That was
missing before and was the actual blocker.

---

All ten checkers pass.
