# Stage 69 — the audio half, and three bugs the tests caught

## `scripts/lip_sync.gd` — sound in, mouth shapes out

**Said plainly first: this is not speech recognition.** Nothing in it knows
what word is being said and nothing in it could be taught to. It hears how
open the mouth must be and roughly where in the mouth the sound is made, and
picks the nearest of the nine. That is what Papagayo's automatic mode does and
what every lip-sync tool did before machine transcription existed — and it is
enough, because you are going to look at the result anyway, and correcting six
frames in a sentence is a different job from keying two hundred by hand.

Saying that out loud matters. A tool that claims to recognise speech and then
produces a mouth merely *open at the right times* has lied to its user, who
spends an afternoon wondering what they did wrong.

**What it can honestly hear — two axes, and only two:**

| axis | from | how reliable |
|---|---|---|
| how **open** | loudness | very — it is what makes speech look like speech even when every shape is wrong |
| how **round** | the balance between two frequency bands | good — the second formant moves a long way when the lips round |
| plus: **hiss** | quiet + crossing zero constantly | unmistakable; this is how `s f th` are found |

`b`, `m`, `p` are *silence with the lips together*. The gap is found; which of
the three it was is not — and does not need to be, because all three are the
same closed mouth. **This is the one place where working on shapes instead of
phonemes is an outright advantage.**

`l`, `r` and `k` are all mid-open and mid-round, so this will confuse them.
They are the three you will correct, and the three an audience is least likely
to notice. Better to name that than to let you discover it.

**WAV only, and why:** `AudioStreamWAV.data` *is* the audio and Godot hands it
over. Ogg and MP3 are compressed, and Godot does not expose a decoder to
scripts. Converting a file is one step for you; a decoder written in GDScript
would be slower than the conversion and worse at it.

---

## Three real bugs, all caught by testing before they shipped

I want these on the record, because each one would have survived a demo.

**1. Normalising the spectrum per track destroyed the thing it measured.**

I scaled `low` and `high` each against their own maximum across the recording.
It looks symmetrical. It is destructive: on a line spoken in one steady vowel,
both maxima come from that vowel, both ratios become 1, and every frame reports
a perfectly balanced spectrum. The classifier answered **`A` for the entire
track** — an open mouth flapping through a whole sentence, which is exactly the
failure the file exists to prevent.

A balance between two bands is already a ratio. A ratio has no scale to
normalise, and normalising it removes the only thing it carries. *Loudness* is
normalised per recording — so a quiet performance still opens the mouth all the
way on its loudest syllable — and the spectrum is not.

**2. Five lone probes left gaps a whole formant could fall through.**

A Goertzel probe is narrow. A vowel whose second formant sat at 2600 Hz, between
probes at 2100 and 3100, registered as having almost no high energy and was
classified as a **rounded** mouth. It is the opposite of what that vowel is.

Each region is now sampled at four and six nearby frequencies and averaged, so
it behaves as a band rather than a line, and nothing can fall between two probes.

**3. A plain fraction was too compressed to threshold on.**

Across a set of test vowels the fraction gave `0.013` for a rounded one and
`0.055` for a spread one — a real fourfold difference squeezed into four
hundredths, where no threshold separates them without also separating things
that are the same.

Formant relationships are ratios of frequencies and behave logarithmically.
Measured that way, those same four vowels become **0.05, 0.38, 0.70, 0.87** —
a scale a threshold can live on.

## Verified — fifteen checks, all passing

silence closes the mouth · a hiss reads as teeth · round and spread vowels
give different mouths · a quiet take and a loud take of the same line give the
same mouths · a short gap becomes a closure (a `p`) · frame counts match the
sound exactly at three durations · an empty track, pure silence, and a
one-sample track all behave · every value returned is a real mouth

---

## What is still not done — and why I stopped here

**The canvas pose path.** Layers are drawn as a grid of tiled `Sprite2D`s, and
the B-Spline room deforms by baking through a `SubViewport` — far too heavy per
frame. Making poses live means a `MeshInstance2D` that draws the layer's art
through the rig's vertices, and hiding the tiles while posed. It is the keystone:
it unblocks poses during playback, **onion skin showing poses**, and the mouth
ring actually bending the mouth on canvas.

**Buttons** for the ring, the sound link, and `stick`.

I did not attempt the rendering subsystem this stage, and the reason is in the
section above. Three bugs surfaced in one file of maths I would otherwise have
called finished — two of them producing output that *looked* like working lip
sync. A new rendering path written blind, on top of that, is how a stage lands
broken and takes the working parts with it.

**What I would do next, in order:** the canvas mesh path, alone, as its own
stage — because everything left is waiting behind it, and it is the one piece
where I would most want you to open the project and tell me what you see.

## Files touched

new `lip_sync.gd`

Static analysis clean: use-before-declaration 0, brackets balanced, no
duplicate functions, no unused parameters, no shadowing, no global-name
collisions, no dead references.
