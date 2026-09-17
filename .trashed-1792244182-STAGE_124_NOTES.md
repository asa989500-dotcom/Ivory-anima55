# IVORY Stage 124 — three errors, and the hole that let one of them through

## The errors

**1. `Function "knit_room()" not found in base self.`** — `main.gd` called
`knit_room()` in two places and one more through `KnitBar`. Nothing anywhere
declared it. The accessor was simply missing; `knit_rooms` (the dictionary it
was meant to read) was there, unused.

Written now, and written properly rather than as a one-liner, because there is
a real decision inside it. A `KnitRoom` is *not* the board — the board lives on
the project and is what gets saved. The room is everything around it: the hand
mid-gesture, and the undo stack. Making a fresh one per call would throw that
away on every draw, so undo would appear to work and quietly do nothing, which
is worse than no undo at all. One room per project, kept under the project's
id.

It also does the thing that is easy to miss: undo and redo replace the board
object outright, so the project has to be pointed at whichever board the room
is holding now. Without that, an undo shows on screen and is not what gets
written to disk.

`forget_knit_room()` releases it on close and on delete, so a long session that
opens twenty pieces is not still carrying twenty undo stacks.

**2. `SHADOWED_VARIABLE_BASE_CLASS` at line 1141** — `spawn_wool_character`
took a parameter called `size`, which `Control` already has. Renamed to `page`.
The compiler is right to complain: while that parameter is in scope the
function cannot read its own node's size, and that is a bug waiting for
somebody to find at three in the morning.

**3. `INTEGER_DIVISION` at line 2055** — `whole / 60` in `_format_export_time`.
Integer division was what was meant, so the fix is to say so in a way the
compiler can see: divide as a float and floor it. The same pattern in
`timeline_audio.gd`'s clock is fixed too.

## The hole

All ten checkers passed on code that would not run. That is worth more
attention than the bug.

- `check_identifiers.py` only examines names starting with an underscore,
  because for a bare name it cannot tell a missing method from a global class
  or an enum member. `knit_room` has no underscore, so it was never looked at.
- `check_references.py` resolves `Other.thing()` — a call with a class in front
  of it. A call on the current class has nothing in front of it, so there was
  nothing to resolve.

Between those two rules sat a hole exactly the shape of *an unqualified call to
a method that does not exist* — which is one of the most ordinary mistakes
there is: you rename a function, or you write the call first and never come
back.

**`tools/check_self_calls.py`** fills it. It examines only calls — `name(` —
never bare names, so an enum member or a constant is never mistaken for a
missing method. Signals count as declared (a `signal closed()` declaration
reads exactly like a call), annotations are stripped, and inherited methods
come from a list of what this project's classes actually extend. That list is a
superset of what is really in scope, which means the checker can miss a real
error and can never invent one — the safe direction for something that runs on
every build.

It was tested against the actual bug: renaming `knit_room` makes it report both
call sites and fail.

`check_all.py` now runs eleven checks.

## Also

`main.gd` went over its line budget while gaining the accessor, so the audio
import section — the picker, the format list, the flash messages and the
playback wiring — moved to `scripts/ui/audio_import.gd`. It is a good seam:
everything in it is about *files on a phone*, and none of it is about IVORY's
own state beyond "which layer asked".

All eleven checks pass.
