class_name Perf
extends RefCounted
## What this device can afford, measured rather than assumed.
##
## The honest history of this file: until stage 90 every number in it was
## invented. Six tiles a frame, nine hundred dabs before folding, ninety-six
## megapixels for one picture — written from a feeling about what a phone can
## do, never once timed on one. They quietly decided how the app behaved on
## every device it will ever run on, and nobody could say whether any of them
## was right.
##
## There are now three sources of truth, in order of authority:
##
##   1. **The benchmark** (`PerfBench`) runs once per device and times the
##      operations the app actually spends its frames inside. The starting
##      tier and the memory ceilings come from it.
##   2. **The live counters** (`note` / `mean_ms`) time those same operations
##      in production, so a figure measured on a cold device is corrected by
##      one measured on a hot, throttling one.
##   3. **The frame clock** (`tick`) is the last word: whatever the other two
##      believed, a device dropping frames gets asked for less.
##
## What remains constant here is only what is not device-dependent: a frame is
## 16.7 ms everywhere, and the share of it the app is willing to spend on a
## given job is a design decision rather than a measurement. Those are written
## as slices of a frame, so the reasoning is visible on the page.
##
## Every figure is printable (`report`), which is the part that matters most:
## when something is slow on a device I will never hold, it can be described
## in microseconds instead of adjectives.

enum Tier { LOW, MEDIUM, HIGH }

const SAMPLE: float = 0.5         # seconds per measurement
const DROP_MS: float = 26.0       # slower than this and something must give
const RAISE_MS: float = 13.0      # comfortably fast for a while: ask for more
const PATIENCE_DOWN: int = 2      # samples before easing off
const PATIENCE_UP: int = 8        # and rather more before asking for more

## The design decisions, stated as shares of one frame so they can be argued
## with. These are the only numbers left that are not measured.
const FRAME_MS: float = 16.7
## What may go on waking sleeping tiles in a frame. A little softness for a
## moment costs the eye less than a dropped frame does.
const WAKE_SLICE_MS: float = 3.0
## What a single fold — reading the graphics card back into memory — may cost
## before it is done less often.
const FOLD_TARGET_MS: float = 4.0

static var tier: int = Tier.HIGH

static var _clock: float = 0.0
static var _frames: int = 0
static var _slow: int = 0
static var _quick: int = 0

## How much of a frame is going spare, from -1 (badly over) through 0 (right
## at the edge) to 1 (nothing to do).
##
## The tier says which of three shapes the app takes. This says how much room
## there is inside that shape, and it moves every half-second. Budgets that
## read it stretch on a device with room and tighten on one without, without
## waiting for a tier to change — which is the difference between a fast
## tablet being allowed to *be* fast and merely being labelled HIGH.
static var headroom: float = 0.5

## A budget scaled by the room actually going spare.
##
## `lean` is what a device at the edge of stuttering should get, `rich` what
## one with a whole frame spare should get. Everything between is
## interpolated, so the answer moves continuously rather than in three jumps.
##
## Deliberately asymmetric: it falls to `lean` faster than it climbs to
## `rich`. Being handed too much and stuttering is a fault the person sees;
## being handed too little and looking slightly softer for a second is one
## they do not.
static func afford(lean: float, rich: float) -> float:
	var room: float = clampf(headroom, 0.0, 1.0)
	if headroom < 0.0:
		return lean
	return lean + (rich - lean) * (room * room)

## Fed once per frame by the canvas.
static func tick(delta: float) -> void:
	_clock += delta
	_frames += 1
	if _clock < SAMPLE:
		return
	var average: float = (_clock / float(maxi(_frames, 1))) * 1000.0
	_clock = 0.0
	_frames = 0

	# Headroom: how much of a frame is spare, as a fraction. One at sixty
	# frames a second with nothing to do, nought at the point of stuttering,
	# negative past it. Everything below reads this instead of only the tier,
	# which is what turns three settings into a continuous response.
	#
	# The tier alone could not do it. A flagship tablet and a mid-range phone
	# both land on HIGH and were handed identical budgets, so the fast device
	# was being held to the slow one's ceiling; and a device that had fallen
	# to LOW was given LOW's numbers whether it was missing the frame by one
	# millisecond or by forty. Adaptation that stops at three steps is barely
	# adaptation.
	headroom = clampf((DROP_MS - average) / (DROP_MS - RAISE_MS), -1.0, 1.0)

	if average > DROP_MS:
		# Proportional, not one step at a time. A device at sixty
		# milliseconds a frame is not "a bit slow" — it is four times over
		# budget, and easing off one notch every second while the person
		# watches it stutter is a system taking its time about an emergency.
		# Twice over budget drops a tier at once; three times drops two.
		_slow += 1 if average < DROP_MS * 2.0 else PATIENCE_DOWN
		_quick = 0
	elif average < RAISE_MS:
		_quick += 1
		_slow = 0
	else:
		_slow = 0
		_quick = 0

	if _slow >= PATIENCE_DOWN and tier > Tier.LOW:
		tier -= 2 if average > DROP_MS * 3.0 else 1
		tier = maxi(tier, Tier.LOW)
		_slow = 0
	elif _quick >= PATIENCE_UP and tier < Tier.HIGH:
		tier += 1
		_quick = 0

# ------------------------------------------------------- the measured device

## What `PerfBench` found. Empty until `calibrate` has run, and every reader
## below falls back to a stated default while it is.
static var profile: Dictionary = {}

## Runs the benchmark, or reads the stored result of an earlier run, and sets
## the starting tier from it.
##
## Called once at startup. A first launch costs a few tens of milliseconds;
## every launch after that is one file read.
static func calibrate(force: bool = false) -> void:
	profile = PerfBench.obtain(force)
	tier = _tier_from_profile()
	CelTrack.spill_budget = spill_budget()

## The tier this device starts at.
##
## Before, every device started at HIGH and was demoted only after a full
## second of visibly dropped frames — so the weakest phone spent the first
## second of every launch stuttering, on principle. Now the starting point is
## what the benchmark measured and the frame clock only has to correct it.
##
## The thresholds are arithmetic rather than taste. Waking one tile costs a
## decode plus a composite; if that alone eats most of a frame, the device is
## not a fast one whatever else is true of it.
static func _tier_from_profile() -> int:
	if profile.is_empty():
		return Tier.HIGH
	var per_tile_ms: float = (
		float(profile.get("decode_us", 0)) + float(profile.get("blit_us", 0))
	) / 1000.0
	var memory_mb: int = int(profile.get("memory_mb", -1))

	var by_speed: int = Tier.HIGH
	if per_tile_ms > 6.0:
		by_speed = Tier.LOW
	elif per_tile_ms > 2.5:
		by_speed = Tier.MEDIUM

	var by_memory: int = Tier.HIGH
	if memory_mb > 0:
		if memory_mb < 1600:
			by_memory = Tier.LOW
		elif memory_mb < 3000:
			by_memory = Tier.MEDIUM

	return mini(by_speed, by_memory)

# --------------------------------------------------------- the live counters

## Rolling timings of real operations, keyed by name:
## `{name: {"n": int, "sum": float, "peak": float, "recent": float}}`.
##
## The mean is what the budgets are built on, the peak is there because a
## budget set by the mean still stutters on the worst case, and the count is
## there so a reader can tell a measurement from a coincidence.
static var _ops: Dictionary = {}

## One timing, in microseconds. Cheap enough for a hot path: two dictionary
## lookups and four additions.
static func note(op: String, micros: int) -> void:
	if micros < 0:
		return
	var ms: float = float(micros) / 1000.0
	var row: Dictionary = _ops.get(op, {"n": 0, "sum": 0.0, "peak": 0.0,
		"recent": 0.0})
	row["n"] = int(row["n"]) + 1
	row["sum"] = float(row["sum"]) + ms
	row["peak"] = maxf(float(row["peak"]), ms)
	row["recent"] = ms
	_ops[op] = row

## The common shape: `var t: int = Time.get_ticks_usec()` … `Perf.since("fold", t)`.
static func since(op: String, started_usec: int) -> void:
	note(op, Time.get_ticks_usec() - started_usec)

static func samples(op: String) -> int:
	return int((_ops.get(op, {}) as Dictionary).get("n", 0))

static func mean_ms(op: String) -> float:
	var row: Dictionary = _ops.get(op, {})
	var n: int = int(row.get("n", 0))
	if n <= 0:
		return -1.0
	return float(row.get("sum", 0.0)) / float(n)

static func peak_ms(op: String) -> float:
	return float((_ops.get(op, {}) as Dictionary).get("peak", -1.0))

static func recent_ms(op: String) -> float:
	return float((_ops.get(op, {}) as Dictionary).get("recent", -1.0))

static func reset_counters() -> void:
	_ops.clear()

## The measured cost of an operation in milliseconds: the live figure once
## there is enough of it to trust, the benchmark's figure until then, and a
## stated fallback if neither exists.
##
## Eight samples is the threshold. Below that, one unlucky frame — a
## collection, a notification arriving — moves the mean far enough to change a
## budget, and that is how an adaptive system ends up oscillating instead of
## adapting.
static func _cost_ms(op: String, bench_key: String, fallback: float) -> float:
	if samples(op) >= 8:
		return mean_ms(op)
	if bench_key != "":
		var us: float = float(profile.get(bench_key, -1.0))
		if us > 0.0:
			return us / 1000.0
	return fallback

# ------------------------------------------------------------ what it buys

## Mipmaps are the first thing to go. They cost a full rebuild of a tile
## whenever a stroke settles, and what they buy — clean shrinking — is worth
## having but not worth stuttering for.
static func wants_mipmaps() -> bool:
	return tier == Tier.HIGH

## How many sleeping tiles may be woken in one frame.
##
## On a fast device this stays unlimited: a device holding sixty frames a
## second while waking tiles has proved that it can, and rationing it would
## only make a zoom look soft for no reason.
##
## Below that it is arithmetic. One tile costs a decode; a frame may spend
## `WAKE_SLICE_MS` decoding; the budget is the quotient. A device measured at
## four milliseconds a tile is told one tile, and told it because that is what
## fits — not because six felt like a reasonable number for a middling phone,
## which is what it used to say.
static func wake_budget() -> int:
	if tier == Tier.HIGH and headroom > 0.25:
		return 1 << 20
	if tier == Tier.HIGH:
		# Nominally fast, but currently working hard — a big export running,
		# or a hot device throttling. Rationed on the way down rather than
		# waiting for a whole tier to fall.
		var per_hi: float = _cost_ms("wake", "decode_us", 1.0)
		return clampi(int(WAKE_SLICE_MS / maxf(per_hi, 0.05)), 4, 64)
	var per_tile: float = _cost_ms("wake", "decode_us", 1.0)
	var fits: int = int(WAKE_SLICE_MS / maxf(per_tile, 0.05))
	if tier == Tier.MEDIUM:
		return clampi(fits, 2, 24)
	return clampi(fits, 1, 8)

## Frames per second while nothing is happening.
static func idle_fps() -> int:
	if tier == Tier.LOW:
		return 8 if headroom > 0.0 else 6
	if tier == Tier.HIGH and headroom > 0.6:
		# A device with a whole frame going spare can afford to feel awake.
		# Idling at twelve made a fast tablet answer the first touch after a
		# pause up to eighty milliseconds late, which reads as the app having
		# to be woken rather than being ready.
		return 20
	return 12

## Dabs held on the graphics card before folding them back into memory.
## Folding is a read back from the card, which stalls it, so a slow device
## does it less often and carries more work per frame instead.
static func fold_after() -> int:
	var base: int = 900
	if tier == Tier.HIGH:
		base = 600
	elif tier == Tier.LOW:
		base = 1400
	# The base figures are what this app shipped with for eighty-nine builds.
	# What is new is that they are scaled by what a fold actually costs here:
	# measure one at twelve milliseconds against the four it is allowed, and
	# the app folds three times less often, carrying more work per frame
	# instead. That is the trade this function always claimed to make and was
	# never in a position to make.
	var cost: float = _cost_ms("fold", "", FOLD_TARGET_MS)
	if cost <= 0.0:
		return base
	return clampi(int(float(base) * (cost / FOLD_TARGET_MS)), 300, 4000)

# ------------------------------------------------- what the rig may spend

## How often a posed mesh is re-skinned while a clip plays, in frames.
##
## Posing is two separate costs and they are not the same size. Reading the
## pose is a handful of floats — it happens every frame on every device, so
## the *timing* of an animation is identical everywhere and a scene checked on
## a tablet plays back at the same speed on a phone.
##
## Pushing that pose through the mesh is the expensive half: every vertex of
## the skin re-weighted and re-uploaded. On a slow device that is rationed.
## The result is an animation that holds its shape for a frame at a time
## rather than one that runs slowly — which is the right trade, because a
## viewer forgives a pose held for two frames and does not forgive a scene
## that plays at half speed.
static func rig_solve_stride() -> int:
	if tier == Tier.HIGH:
		return 1
	if tier == Tier.MEDIUM:
		# Every frame when there is room for it. A middling device with a
		# quiet scene was skipping frames it could easily have drawn, on the
		# strength of a label rather than a measurement.
		return 1 if headroom > 0.55 else 2
	return 3 if headroom < 0.2 else 2

## Whether secondary motion — hair and cloth trailing behind the main
## movement — is worth running at all.
##
## It is the first thing to go and the last to come back, because it is the
## only part of a rig nobody asked for directly: it is there to make motion
## look observed rather than drawn. A figure without it still animates. A
## figure that stutters does not.
static func wants_dynamics() -> bool:
	return tier == Tier.HIGH and headroom > 0.1

## How many springs may be carried at once when dynamics do run. Long hair on
## a fast device; a suggestion of it on a middling one.
## Springs are pure script, so this scales with the one thing the benchmark
## measures about script speed rather than about pixels: a fixed arithmetic
## loop. The reference is three milliseconds for twenty thousand steps — a
## device that takes twice that carries half the hair.
static func dynamics_budget() -> int:
	if tier == Tier.MEDIUM:
		return int(afford(24.0, 96.0))
	if tier != Tier.HIGH:
		return 0
	var loop_us: float = float(profile.get("loop_us", -1.0))
	var measured: float = 256.0
	if loop_us > 0.0:
		measured = 256.0 * (3000.0 / loop_us)
	# The benchmark says what this device *can* do; the headroom says what it
	# has spare right now. A tablet twice as fast as the reference and idle
	# carries twice the hair; the same tablet mid-export carries a quarter of
	# it, and neither answer waits for a tier to move.
	return clampi(int(measured * afford(0.25, 1.6)), 16, 1024)

## Whether the timeline may draw the travel between rig keys as a live
## in-between rather than as two dots and a line.
##
## Drawing the tween means solving the pose once per pixel column of the band,
## which is real work for something that is only a hint. On a slow device the
## hint is dropped and the keys are still exactly where they are.
static func wants_tween_preview() -> bool:
	return tier != Tier.LOW

static func name_of_tier() -> String:
	if tier == Tier.HIGH:
		return "high"
	if tier == Tier.MEDIUM:
		return "medium"
	return "low"

# ------------------------------------------------------------ memory budget

## The largest picture this device should be asked to hold in one piece.
##
## Everything expensive in IVORY eventually comes down to one `Image` of some
## size: a page being exported, a set of layers being flattened for a transfer,
## a frame on its way into a GIF. `Image.create_empty` does not fail politely
## when the size is beyond reach — the allocation is made in C++ and the process
## is killed by the operating system, which reaches the user as the app simply
## vanishing with their work in it.
##
## So the size is asked about *before* it is asked for. The tier already tracks
## how hard this device is finding the work it is doing; a phone that has been
## dropping frames is a phone with nothing spare, and the ceiling comes down
## with it. Four bytes a pixel, and headroom left over for the copy that almost
## always has to exist beside it at the moment of writing.
## The ceiling is now a quarter of the device's real memory, where the device
## will say what that is, rather than a number picked per tier. The tier says
## how *fast* a machine is; this question is about how *much* it has, and
## those are not the same machine — a slow tablet with six gigabytes was being
## refused exports it could easily have made.
##
## A quarter, because the copy that has to exist beside the image at the
## moment of writing is a second allocation of the same size, and the
## operating system needs what is left. Measurement can only lower the shipped
## ceiling, never raise it: if the reading is wrong, the failure is a refused
## export rather than a killed app.
static func pixel_ceiling() -> int:
	var ceiling: int = 24000000        # ~96 MB — a device already struggling
	if tier == Tier.MEDIUM:
		ceiling = 48000000             # ~192 MB
	elif tier == Tier.HIGH:
		ceiling = 96000000             # ~384 MB
	var memory_mb: int = int(profile.get("memory_mb", -1))
	if memory_mb > 0:
		# A quarter of physical memory, at four bytes a pixel.
		ceiling = mini(ceiling,
			int(float(memory_mb) * 1048576.0 * 0.25 / 4.0))
	# Never so low that a page the user legitimately made cannot be exported:
	# A4 at 300 dpi is about nine megapixels and has to pass on anything.
	return maxi(ceiling, 12000000)

## The same question for a whole clip rather than one picture.
##
## An animation export holds every rendered frame alive at once, because a GIF
## with one palette and a sprite sheet both need to see all of them before
## writing any. That array, not any single frame, is what actually runs a phone
## out of memory: three hundred Full HD frames is two and a half gigabytes.
##
## Set so the ordinary exports never come near it. A GIF at the eight-hundred
## wide preset is about a third of a megapixel a frame, which is five hundred
## frames on a good device — past the six-hundred cap the exporter already
## applies. Only a full-resolution export of a long scene reaches this, and for
## that case being told "eighty-seven frames, the rest left out" is a far better
## morning than finding the app gone.
static func frame_pixel_budget() -> int:
	var budget: int = 40000000         # ~160 MB
	if tier == Tier.MEDIUM:
		budget = 90000000              # ~360 MB
	elif tier == Tier.HIGH:
		budget = 180000000             # ~720 MB
	var memory_mb: int = int(profile.get("memory_mb", -1))
	if memory_mb > 0:
		# Two fifths of it, at four bytes a pixel.
		budget = mini(budget,
			int(float(memory_mb) * 1048576.0 * 0.4 / 4.0))
	return maxi(budget, 20000000)

## How much of the device's storage the cel spill may hold at once.
##
## Lowered where storage measured slow, because there the spill is barely a
## saving: paging a cel back costs more than the memory it freed, and a long
## scene would spend its time reading rather than drawing. Under about thirteen
## megabytes a second the app is better off carrying the cels in memory.
static func spill_budget() -> int:
	var disk_us: float = float(profile.get("disk_us", -1.0))
	if disk_us <= 0.0:
		return 192 * 1024 * 1024
	# 256 KB written and read back again, as megabytes a second:
	var mb_per_sec: float = 0.5 / (disk_us / 1000000.0)
	if mb_per_sec < 13.0:
		return 32 * 1024 * 1024
	if mb_per_sec < 40.0:
		return 96 * 1024 * 1024
	return 192 * 1024 * 1024

## Whether an image of this size may be attempted.
static func can_hold(size: Vector2i) -> bool:
	if size.x <= 0 or size.y <= 0:
		return false
	if size.x > 16384 or size.y > 16384:
		return false
	return size.x * size.y <= pixel_ceiling()

## The same size, brought inside the ceiling with its proportions kept.
##
## Shrinking rather than refusing, because for an export the honest answer is
## "here it is, smaller than you asked" and for a flatten it is "here is your
## drawing". Refusing outright would be correct and useless. The factor is a
## square root because the ceiling is on area and the scaling is on both sides.
static func fit_within(size: Vector2i) -> Vector2i:
	if can_hold(size):
		return size
	var w: float = float(maxi(size.x, 1))
	var h: float = float(maxi(size.y, 1))
	var k: float = sqrt(float(pixel_ceiling()) / (w * h))
	k = minf(k, minf(16384.0 / w, 16384.0 / h))
	return Vector2i(maxi(int(w * k), 1), maxi(int(h * k), 1))

## An `Image` that is either the size asked for or nothing at all.
##
## The one place `create_empty` should be called from for anything whose size
## comes from user input — a page size typed into a box, a union of layer
## bounds, a frame count times a frame size. Returning null lets the caller say
## something; letting the allocation run lets the operating system say it, and
## it says it by closing the app.
static func make_image(size: Vector2i) -> Image:
	if not can_hold(size):
		return null
	var img: Image = Image.create_empty(size.x, size.y, false,
		Image.FORMAT_RGBA8)
	if img == null:
		return null
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	return img

# ----------------------------------------------------------------- the report

## Everything this file believes, and why, in a form a person can read out.
##
## This exists so that "the timeline is slow" can become "the timeline draw
## measures 31 ms, peak 74, over 900 samples", which is a sentence somebody can
## act on. Shown in the diagnostics sheet, and printed at startup in a debug
## build.
static func report() -> String:
	var lines: Array = []
	lines.append("IVORY performance")
	lines.append("tier      %s" % name_of_tier())
	# The tier says which of three shapes the app is in; this says how
	# much room is going spare inside it, right now. Every budget below
	# is a function of both, so a photograph of this page explains an
	# answer that a tier alone could not.
	lines.append("headroom  %+.2f  (1 = a frame to spare, 0 = at the edge)"
		% headroom)
	lines.append(PerfBench.describe(profile))
	lines.append("")
	lines.append("budgets now in force")
	lines.append("  wake      %d tiles a frame" % wake_budget())
	lines.append("  fold      every %d dabs" % fold_after())
	lines.append("  idle      %d fps" % idle_fps())
	lines.append("  picture   %.1f megapixels" %
		(float(pixel_ceiling()) / 1000000.0))
	lines.append("  clip      %.1f megapixels" %
		(float(frame_pixel_budget()) / 1000000.0))
	lines.append("  spill     %d MB"
		% int(float(spill_budget()) / 1048576.0))
	lines.append("  rig       one solve every %d frames" % rig_solve_stride())
	if _ops.is_empty():
		lines.append("")
		lines.append("measured here: nothing yet")
		return "\n".join(lines)
	lines.append("")
	lines.append("measured here            mean     peak    samples")
	var names: Array = _ops.keys()
	names.sort()
	for op in names:
		lines.append("  %-20s %6.2f   %6.2f   %7d" % [String(op),
			mean_ms(op), peak_ms(op), samples(op)])
	return "\n".join(lines)
