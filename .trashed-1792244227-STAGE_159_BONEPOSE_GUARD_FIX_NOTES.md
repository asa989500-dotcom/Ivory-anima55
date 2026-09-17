# IVORY Stage 159 — Bone Drag Guard, Actually Wired Through

Stage 158 added a per-drag stability guard to `IvoryBonePose` (deadband and a
hard cap on how far one call may move a joint's remembered target). It was
computed correctly and then thrown away: `reach()` and the final joint
placement both used the raw, unguarded target, so the guard had zero effect
on anything the person could see. Two things followed from that, and both are
fixed here.

## What was wrong

1. **The guard was dead code in practice.** `drag()` computed a limited
   `goal`, wrote it into `now_[joint]` once, and then immediately called
   `reach(joint, to, ...)` with the raw target and finished with
   `now_[joint] = to`. Whatever the deadband/max-step math produced never
   survived to the output. A lag spike or a stray large touch delta reached
   the rig exactly as if no guard existed.

2. **The limb could tear away from the guarded joint.** `carry_descendants`
   moved the joint's children by the raw delta (`to - was`) while the joint
   itself had only moved by the guarded delta. Whenever the guard actually
   held a joint back, its children would not — visible as a rip at the joint
   on exactly the kind of jump the guard exists to catch.

3. **One filter served the whole rig.** `stable_target_` /
   `stable_velocity_` / `stable_ready_` were single fields, not per joint.
   Dragging joint A and then joint B handed B the leftover target and
   velocity from A, which (once bug 1 is fixed and the guard actually
   matters) would make B crawl toward its own finger instead of arriving
   there.

Confirmed by running the fix's regression checks against the *original*
stage-158 source before touching anything: a drag capped at 50px moved the
joint 7006px in one call. Compiling and running the existing 61-check suite
for `IvoryBonePose` against the original source passed unchanged, which is
why the bug was invisible until traced by hand — nothing existing exercised
`configure_stability` at all.

## What changed

- `stable_target_` and `stable_ready_` are now `std::vector`s, one entry per
  joint, sized and reset alongside the skeleton itself.
- `drag()` guards the raw target into `goal` and then uses `goal` — not
  `to` — for the joint's own position, for `carry_descendants`, for
  `reach()`, and for the final placement. The guard is now the thing that
  actually happens, not a number computed alongside it.
- Any joint moved by something other than its own drag — carried by a
  parent's drag, turned by the ring, or overwritten by `set_positions` —
  has its guard invalidated, so the next direct drag on it snaps cleanly to
  where it now sits instead of crawling there from a stale remembered
  target.
- `stable_velocity_` is removed: it was decayed on every deadband hit but
  never read by anything that shaped motion. Keeping dead state that looks
  load-bearing is worse than not having it.

## Verified

- The existing `native/ivory/tests/test_bonepose.cpp` suite: 61 checks, 0
  failures, unchanged behaviour.
- Two checks added to the same file: one confirms a drag capped at 50px
  actually lands within 50px (was 7006px on the original source), and that
  a carried descendant does not tear away from a guarded joint; the other
  confirms dragging one joint does not disturb a different joint's own
  guard. 64 checks total, 0 failures, compiles clean with `-Wall -Wextra`.
- No other native file touches `IvoryBonePose`'s internals — only
  `register_types.cpp` references the class, and only to bind it — so
  nothing outside this file could be affected by the change.

## What is not here

Puppet Warp's existing drawing-bounds and foldover safeguards are untouched,
as stage 158 already noted. This stage is scoped to the one class whose
stability feature did not do what its own configuration implied.
