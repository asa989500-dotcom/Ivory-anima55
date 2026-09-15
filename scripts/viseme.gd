class_name Viseme
extends RefCounted
## The mouth shapes — as ways of bending, not as drawings.
##
## ## The correction that shaped this file
##
## The first version of this asked the artist for nine mouth drawings. That
## was wrong, and wrong in the way that matters: it hands the artist a form to
## fill in. Nine drawings of a mouth is nine drawings the app demanded, in
## nine shapes the app chose, and a character whose mouth was designed by a
## specification is not that artist's character any more.
##
## **The artist draws one mouth. Their mouth.** Then a plain black ring is
## drawn around it — an ordinary line, nothing special about it — and the ring
## bends, and what is inside the ring bends with it. Every key below is a way
## of bending that ring. None of them is a picture of a mouth, and none of them
## knows or cares what the mouth inside it looks like.
##
## That is why `b`, `m` and `p` close **whatever** is in there. Closing is not
## "show the closed drawing"; it is the ring flattening onto its own middle
## line, and anything inside a flattened ring is flat. A round mouth, a wide
## one, a crooked one drawn by somebody who draws crooked mouths — all of them
## shut, and all of them shut in their own way.
##
## ## Why there are nine and not forty
##
## English has about forty-four sounds. It does not have forty-four *mouths*.
## From outside a face, `p`, `b` and `m` are one closed mouth; `k`, `g` and
## `ng` all happen at the back of the tongue where nothing shows; `s` and `z`
## differ only in whether the throat is switched on. An audience cannot tell
## any of those pairs apart, and animating them separately buys nothing.
##
## So lip sync has always run on a small chart — Preston Blair drew his for
## Fantasia and the industry still works from it. The eight letters in the
## brief were already almost exactly that chart. `SHUT` is the ninth, and it
## is not optional: `m`, `b` and `p` require closed lips *physically*, and
## without it "mama" is spoken with the mouth open throughout.
##
## ## What each key does to the ring
##
## Five numbers, and every one of them is a thing a jaw or a pair of lips
## actually does:
##
##   `wide`  — how far the corners go out, 1 being where they were drawn
##   `tall`  — how far the ring opens, 1 being as drawn
##   `purse` — corners drawn inward and forward, as in `w` and `oo`
##   `drop`  — the whole ring carried down, which is the jaw rather than the lips
##   `shut`  — how far the ring collapses onto its own middle, 1 being closed
##   `jaw`   — how much of the opening happens downward rather than evenly
##   `curl`  — where the corners sit: above the middle for a spread mouth,
##             below it for a rounded one
##
## They are multipliers on the artist's own ring, never absolute sizes. A
## small mouth and a wide mouth both get `A` as "open a good deal wider than
## you drew it", which is the only reading of `A` that survives contact with
## more than one character.
##
## ## The last two, and why they were added
##
## The first five made a mouth that opened and closed correctly and still did
## not look like a mouth, and both reasons are things a face does that a
## rectangle does not.
##
## **A mouth opens downward.** The jaw is hinged behind the ear and the upper
## lip is fixed to the skull, so when a mouth opens, almost all of the
## movement is the bottom lip going down — the top lip barely moves at all.
## Scaling the ring evenly about its middle raises the top lip as far as it
## drops the bottom one, which is the mouth of a puppet with a hinge in the
## wrong place. `jaw` says how much of the opening is spent downward: near
## one for the vowels, where it is nearly all of it, and nought for `T`, where
## the teeth stay where they are.
##
## **The corners are not on a line.** A spread mouth carries its corners up
## and a rounded one carries them down, and it is the single clearest signal
## of which of the two a mouth is doing — clearer than the width, which is why
## `E` and `T` were so easily confused before. `curl` bends the ring's own
## middle line into a shallow arc, so `E` reads as spread and `O` and `W` read
## as rounded even at a glance and even small on screen.

enum Mouth { SHUT, A, E, O, W, T, K, L, R }

## The nine, with what each does to the ring.
##
## Order matters: it is the order the timeline draws them in and the order
## they are numbered on disk, so a key is never inserted into the middle of
## this list — only appended.
##
##   [key, English, Arabic, wide, tall, purse, drop, shut, jaw, curl]
const KEYS: Array = [
	# Lips together. `shut` at 1 does all the work; the rest is what the
	# ring looks like on its way there.
	[Mouth.SHUT, "Shut", "مغلق", 1.00, 1.00, 0.00, 0.00, 1.00, 0.50, 0.00],
	# The widest, tallest thing a mouth does. The jaw is genuinely down, so
	# `drop` is real and not decoration, and nearly all of the opening is the
	# bottom lip travelling.
	[Mouth.A, "A", "ا", 1.10, 1.85, 0.00, 0.16, 0.00, 0.86, -0.05],
	# Corners back and up, barely open. Wider than rest and shorter — and the
	# lift at the corners is what tells it apart from T at a glance.
	[Mouth.E, "E", "ي", 1.28, 0.72, 0.00, 0.02, 0.00, 0.55, 0.30],
	# Round and open: narrower than rest, tall, corners carried down.
	[Mouth.O, "O", "و", 0.72, 1.55, 0.30, 0.10, 0.00, 0.80, -0.22],
	# Pushed forward, small and round. The most pursed of them, and the most
	# turned down at the corners.
	[Mouth.W, "W", "ؤ", 0.55, 0.95, 0.72, 0.02, 0.00, 0.55, -0.32],
	# Teeth showing, only just apart — so the jaw hardly moves and what little
	# opening there is happens at both lips.
	[Mouth.T, "T", "ت", 1.06, 0.52, 0.00, 0.00, 0.00, 0.20, 0.10],
	# Part open and unremarkable — the mouth during every sound that has no
	# shape of its own. Deliberately near rest.
	[Mouth.K, "K", "ك", 1.00, 1.05, 0.05, 0.04, 0.00, 0.70, 0.00],
	# Tongue up behind the top teeth. Opens a little more than T, and the
	# jaw stays put — so what opening there is comes from the bottom lip.
	[Mouth.L, "L", "ل", 0.98, 0.88, 0.00, 0.00, 0.00, 0.75, 0.05],
	# Corners in, slightly round and slightly down.
	[Mouth.R, "R", "ر", 0.80, 0.90, 0.38, 0.02, 0.00, 0.60, -0.15],
]

## How many numbers a shape carries.
const TERMS: int = 7

## The five numbers for a key, as [wide, tall, purse, drop, shut].
## Anything out of range comes back as rest — an unchanged ring, which is the
## only safe answer to "I do not know what this is".
static func shape_of(key: int) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	if key < 0 or key >= KEYS.size():
		out.append_array([1.0, 1.0, 0.0, 0.0, 0.0, 0.5, 0.0])
		return out
	var row: Array = KEYS[key]
	out.append_array([float(row[3]), float(row[4]), float(row[5]),
		float(row[6]), float(row[7]), float(row[8]), float(row[9])])
	return out

## The same shape spoken harder or softer.
##
## `power` of one is the shape as written in the table; below that the mouth
## does less of it. Everything that is a *movement away from rest* is scaled —
## how wide, how tall, how pursed, how far the jaw drops, how the corners
## curl — and closing is not, because a `p` half closed is not a `p`. Lips
## either meet or they do not, and that is the one thing in this file with no
## middle ground.
##
## This is what stops nine poses from reading as nine poses. Every `A` in a
## line was the widest `A` the mouth could make; now the loud one is and the
## tail of a word is not.
static func at_power(shape: PackedFloat32Array, power: float) -> PackedFloat32Array:
	if shape.size() < TERMS:
		return shape
	var amount: float = clampf(power, 0.0, 1.0)
	var out: PackedFloat32Array = shape.duplicate()
	# Toward one, which is the ring exactly as the artist drew it.
	out[0] = 1.0 + (shape[0] - 1.0) * amount
	out[1] = 1.0 + (shape[1] - 1.0) * amount
	out[2] = shape[2] * amount
	out[3] = shape[3] * amount
	out[6] = shape[6] * amount
	return out

## The five numbers part way between two keys.
##
## Lip sync is not a slideshow of poses: a mouth is always travelling from the
## last shape toward the next one, and the frames in between are most of what
## the eye actually sees. Blending the *numbers* rather than cross-fading two
## pictures is the whole reason this file describes bends instead of drawings.
static func blend(from_key: int, to_key: int, t: float) -> PackedFloat32Array:
	var a: PackedFloat32Array = shape_of(from_key)
	var b: PackedFloat32Array = shape_of(to_key)
	var f: float = clampf(t, 0.0, 1.0)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(TERMS)
	# Eased rather than straight.
	#
	# A mouth does not travel between two shapes at a constant speed. It leaves
	# one, moves quickly through the middle, and settles into the next, and a
	# linear blend — which is what this was — gives the flat mechanical slide
	# that makes cheap lip sync look like a machine reading aloud. The curve is
	# the same one every eased key in this app travels on.
	var eased: float = f * f * (3.0 - 2.0 * f)
	for i in TERMS:
		out[i] = a[i] + (b[i] - a[i]) * eased
	return out

## How near two mouths are, from 0 (the same) to 1.
##
## Used to decide when a run of sound is really one held shape, and to soften
## a jump between two shapes that are nothing alike. `A` to `O` is a small
## move — the jaw stays down and the lips round. `SHUT` to `A` is the largest
## move a mouth makes, and it deserves its own frame rather than being passed
## through on the way somewhere else.
const NEAR: Array = [
	#        SHUT   A     E     O     W     T     K     L     R
	[0.00, 1.00, 0.80, 0.85, 0.55, 0.45, 0.65, 0.60, 0.70],  # SHUT
	[1.00, 0.00, 0.45, 0.30, 0.75, 0.60, 0.35, 0.55, 0.60],  # A
	[0.80, 0.45, 0.00, 0.55, 0.70, 0.30, 0.35, 0.40, 0.50],  # E
	[0.85, 0.30, 0.55, 0.00, 0.35, 0.65, 0.40, 0.60, 0.35],  # O
	[0.55, 0.75, 0.70, 0.35, 0.00, 0.70, 0.60, 0.70, 0.30],  # W
	[0.45, 0.60, 0.30, 0.65, 0.70, 0.00, 0.40, 0.25, 0.55],  # T
	[0.65, 0.35, 0.35, 0.40, 0.60, 0.40, 0.00, 0.45, 0.45],  # K
	[0.60, 0.55, 0.40, 0.60, 0.70, 0.25, 0.45, 0.00, 0.50],  # L
	[0.70, 0.60, 0.50, 0.35, 0.30, 0.55, 0.45, 0.50, 0.00],  # R
]

static func apart(a: int, b: int) -> float:
	if a < 0 or b < 0 or a >= KEYS.size() or b >= KEYS.size():
		return 1.0
	return float((NEAR[a] as Array)[b])

static func name_of(key: int) -> String:
	if key < 0 or key >= KEYS.size():
		return "?"
	var row: Array = KEYS[key]
	return UiKit.label_for(String(row[1]), String(row[2]))

# ------------------------------------------------------- what each script says

## Latin letters. Covers English, and serves Spanish, German, French and any
## other language written this way well enough to be worth having before a
## language-specific table exists for it.
const LATIN: Dictionary = {
	"a": Mouth.A, "b": Mouth.SHUT, "c": Mouth.K, "d": Mouth.T, "e": Mouth.E,
	"f": Mouth.T, "g": Mouth.K, "h": Mouth.K, "i": Mouth.E, "j": Mouth.E,
	"k": Mouth.K, "l": Mouth.L, "m": Mouth.SHUT, "n": Mouth.T, "o": Mouth.O,
	"p": Mouth.SHUT, "q": Mouth.W, "r": Mouth.R, "s": Mouth.T, "t": Mouth.T,
	"u": Mouth.W, "v": Mouth.T, "w": Mouth.W, "x": Mouth.K, "y": Mouth.E,
	"z": Mouth.T,
	# Vowels that carry a mark are the same mouth as the ones that do not —
	# an accent changes the sound and not the shape.
	"á": Mouth.A, "à": Mouth.A, "â": Mouth.A, "ä": Mouth.A, "å": Mouth.A,
	"é": Mouth.E, "è": Mouth.E, "ê": Mouth.E, "ë": Mouth.E,
	"í": Mouth.E, "ì": Mouth.E, "î": Mouth.E, "ï": Mouth.E,
	"ó": Mouth.O, "ò": Mouth.O, "ô": Mouth.O, "ö": Mouth.O,
	"ú": Mouth.W, "ù": Mouth.W, "û": Mouth.W, "ü": Mouth.W,
	"ñ": Mouth.T, "ç": Mouth.T, "ß": Mouth.T,
}

## Arabic. The short vowels are marks rather than letters and are usually not
## written at all, so the long vowels carry the work: ا is the open mouth, و
## is the pushed-forward one, ي is the wide one. The emphatic letters —
## ص ض ط ظ — are made further back in the throat than their plain twins and
## look identical from outside, so they go to the same mouths.
const ARABIC: Dictionary = {
	"ا": Mouth.A, "أ": Mouth.A, "إ": Mouth.E, "آ": Mouth.A, "ٱ": Mouth.A,
	"ب": Mouth.SHUT, "م": Mouth.SHUT,
	"ت": Mouth.T, "ث": Mouth.T, "د": Mouth.T, "ذ": Mouth.T, "ز": Mouth.T,
	"س": Mouth.T, "ص": Mouth.T, "ض": Mouth.T, "ط": Mouth.T, "ظ": Mouth.T,
	"ن": Mouth.T, "ف": Mouth.T,
	"ج": Mouth.E, "ش": Mouth.E, "ي": Mouth.E, "ى": Mouth.E, "ئ": Mouth.E,
	"ة": Mouth.E,
	"ح": Mouth.K, "خ": Mouth.K, "ع": Mouth.K, "غ": Mouth.K, "ق": Mouth.K,
	"ك": Mouth.K, "ه": Mouth.K, "ء": Mouth.K,
	"ل": Mouth.L, "ر": Mouth.R,
	"و": Mouth.W, "ؤ": Mouth.W,
	# The marks, for text that carries them.
	"َ": Mouth.A, "ِ": Mouth.E, "ُ": Mouth.W, "ْ": Mouth.SHUT, "ّ": Mouth.K,
}

## Japanese kana. Kana are syllables, so each one already *is* a mouth: the
## vowel it ends on decides the shape, which is why Japanese lip sync is the
## tidiest of the three. Only ま行 and ん close the mouth.
const KANA: Dictionary = {
	"あ": Mouth.A, "か": Mouth.K, "さ": Mouth.T, "た": Mouth.T, "な": Mouth.T,
	"は": Mouth.K, "ま": Mouth.SHUT, "や": Mouth.E, "ら": Mouth.R, "わ": Mouth.W,
	"い": Mouth.E, "き": Mouth.K, "し": Mouth.E, "ち": Mouth.E, "に": Mouth.T,
	"ひ": Mouth.K, "み": Mouth.SHUT, "り": Mouth.R,
	"う": Mouth.W, "く": Mouth.K, "す": Mouth.T, "つ": Mouth.T, "ぬ": Mouth.T,
	"ふ": Mouth.W, "む": Mouth.SHUT, "ゆ": Mouth.W, "る": Mouth.R,
	"え": Mouth.E, "け": Mouth.K, "せ": Mouth.T, "て": Mouth.T, "ね": Mouth.T,
	"へ": Mouth.K, "め": Mouth.SHUT, "れ": Mouth.R,
	"お": Mouth.O, "こ": Mouth.K, "そ": Mouth.T, "と": Mouth.T, "の": Mouth.T,
	"ほ": Mouth.K, "も": Mouth.SHUT, "よ": Mouth.O, "ろ": Mouth.R, "を": Mouth.O,
	"ん": Mouth.SHUT, "っ": Mouth.SHUT, "ー": Mouth.K,
}

## The mouth for one character, in whatever script it is written.
##
## Anything unrecognised — a digit, a symbol, a script with no table yet —
## comes back as `K`, the neutral part-open mouth. That is the right default
## and not a shrug: `K` is what a mouth is doing during every sound that has
## no shape of its own, so an unknown letter borrowing it looks like speech
## rather than like a mistake.
static func of_char(c: String) -> int:
	if c == "":
		return Mouth.SHUT
	var low: String = c.to_lower()
	if LATIN.has(low):
		return int(LATIN[low])
	if ARABIC.has(c):
		return int(ARABIC[c])
	if KANA.has(c):
		return int(KANA[c])
	if c == " " or c == "\t" or c == "\n":
		return Mouth.SHUT
	return Mouth.K

## A whole line of text as a run of mouths, one per character worth speaking.
static func of_text(line: String) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for i in line.length():
		var c: String = line[i]
		if c == " " or c == "\t" or c == "\n":
			out.append(Mouth.SHUT)
			continue
		# Punctuation is not spoken, and a mouth that shapes a comma is a
		# mouth doing something nobody said.
		if not (LATIN.has(c.to_lower()) or ARABIC.has(c) or KANA.has(c)):
			if c.to_lower() == c.to_upper() and not c.is_valid_int():
				continue
		out.append(of_char(c))
	return out

# ---------------------------------------------------------------- smoothing

## How long one mouth may be held before it stops reading as speech.
## Six frames at twenty-four is a quarter of a second, which is about the
## longest a mouth sits still inside a word.
const HOLD_LIMIT: int = 6

## Breaks up a run that would otherwise freeze the mouth.
##
## This is the rule you described: when a stretch of speech is all one shape,
## the mouth stops moving and the whole shot dies — a face frozen mid-word
## reads as a dropped frame, not as talking. Real mouths do not do it either;
## between two identical shapes there is always a small closure as the jaw
## resets, and it is so quick nobody notices it happening and everybody
## notices it missing.
##
## So a held shape gets a closure dropped into it. Not a random one — placed
## at the middle of the run, where a jaw would naturally come back through.
##
## Closures are never placed next to each other, and never on the very first
## or last frame of the run, which would only lengthen the neighbouring hold
## instead of breaking it.
static func settle(run: PackedInt32Array, limit: int = HOLD_LIMIT) -> PackedInt32Array:
	var out: PackedInt32Array = run.duplicate()
	if out.size() < 3 or limit < 2:
		return out
	var start: int = 0
	for i in range(1, out.size() + 1):
		var ended: bool = i == out.size() or out[i] != out[start]
		if not ended:
			continue
		var length: int = i - start
		if length > limit and out[start] != Mouth.SHUT:
			var middle: int = start + int(float(length) / 2.0)
			if middle > start and middle < i - 1:
				out[middle] = Mouth.SHUT
		start = i
	return out

## Removes single frames that nobody can see.
##
## A mouth shape one frame long, between two frames of something else, is a
## flicker. At twenty-four frames a second the eye reads it as noise on the
## face rather than as a sound, and a track full of them looks like a
## malfunction. It is dropped in favour of whichever neighbour it is nearer
## to — nearer as a *mouth*, using the table at the top of this file, not
## nearer in the alphabet.
##
## The exception is `SHUT`. A one-frame closure is a `p` or a `b`, and those
## are genuinely that short — dropping them is how lip sync loses its
## consonants and starts to look like chewing.
static func denoise(run: PackedInt32Array) -> PackedInt32Array:
	var out: PackedInt32Array = run.duplicate()
	for i in range(1, out.size() - 1):
		if out[i] == Mouth.SHUT:
			continue
		if out[i - 1] != out[i + 1] or out[i - 1] == out[i]:
			continue
		# A lone frame surrounded on both sides by one other shape.
		if apart(out[i], out[i - 1]) < 0.5:
			out[i] = out[i - 1]
	return out
