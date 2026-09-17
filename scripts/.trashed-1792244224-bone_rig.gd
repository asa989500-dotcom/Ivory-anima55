class_name BoneRig
extends RefCounted
## One bone, and every piece of arithmetic done to it — in one place.
##
## ## Why this file exists
##
## There were two bone tools. The B-Spline room had a `Bone` with its own
## swing, its own chaining, its own reach; the room beside it had a
## *different* `Bone` with a different idea of what a joint is. They
## drifted, as two copies of anything do: one grew closed-form reach and the
## other did not, one snapped to quarter turns at one end and the other at
## both. A person moving between the two rooms was moving between two tools
## that looked the same and did not behave the same.
##
## So there is one bone now. Both rooms hold `BoneRig.Bone`, both call the
## functions below, and a correction made here is a correction made
## everywhere. That is what "the same bone tool in every room" has to mean if
## it is to mean anything.
##
## ## Rest, turn, and where a bone actually is
##
## A bone is written down twice and the difference between the two is the
## whole design.
##
## **Where it was laid** — `rest_a` and `rest_b` — never changes while the
## figure is being posed. It is the bone as it was drawn onto the artwork, and
## it is what the skin is weighted against. Nothing in a pose is allowed to
## touch it.
##
## **How far it has turned** — `turn` — is one number: this bone's own
## rotation, measured *in its parent's frame*. Not its position. Not its
## angle in the world. Just how much further round than its parent it has
## gone.
##
## `a` and `b` are neither of those. They are worked out from the two by
## `solve`, and they are the only thing anybody draws.
##
## ## Why not simply store where the ends are
##
## Because a chain does not work if you do. This was the bug: a forearm hung
## from an upper arm used to be *carried* by it — the child's two ends were
## shifted by however far the parent's tip had moved. Shifted, not turned. So
## swing an upper arm ninety degrees and the forearm arrives at the elbow
## still pointing the way it was drawn, sticking out of the arm sideways. The
## drawing under it went one way and the bone went another, and the bone
## appeared to come loose from the figure.
##
## Forward kinematics is the fix and it is not a refinement — it is what a
## skeleton *is*. A child's place is its parent's tip; a child's heading is
## its parent's heading plus its own turn. Rotation carries down the chain
## because rotation is what is carried. An upper arm swung ninety degrees
## takes the forearm, the hand and every finger round with it, each keeping
## its own bend, and every bone stays exactly where it sits on the flesh —
## which is the thing that was asked for and the thing that was missing.
##
## ## What is not here
##
## No angle snapping. A joint turns wherever it is taken, smoothly, and stops
## where the finger stops. This was a right-angle stop, and every professional
## rig disagrees with it: Spine's rotate tool is free by default and reaches
## for a held modifier key to constrain, and a tablet has no modifier key to
## hold. A stop that cannot be released is not a feature, it is a limp — an
## arm that can only point four ways.

## --- the bone palette ---
##
## Ivory. Warm, near-white, and the only thing on a figure drawn in it — a
## bone should be recognisable at a glance across a busy drawing. These lived
## in the turnaround's rig until that room was taken out; they belong here,
## beside the bone itself, so every room that draws a skeleton reads the same
## three colours from the same place and none of them can drift.
const BONE_INK: Color = Color("#173B63")
const BONE_CORE: Color = Color("#2A5B87")
const BONE_EDGE: Color = Color("#0D2742")

## A single bone.
class Bone extends RefCounted:
	## Where the bone was laid on the artwork. Never changed by posing.
	var rest_a: Vector2 = Vector2.ZERO
	var rest_b: Vector2 = Vector2.ZERO
	## This bone's own rotation, in its parent's frame. The entire pose.
	var turn: float = 0.0
	## How far a root bone has been carried bodily. Meaningless on a child —
	## a child's place is its parent's tip.
	var shift: Vector2 = Vector2.ZERO
	## The bone this one hangs from, or -1.
	var parent: int = -1

	## Worked out by `solve`. Read freely; write nothing here.
	var a: Vector2 = Vector2.ZERO
	var b: Vector2 = Vector2.ZERO
	## Heading in the world, rest plus every turn above it. Kept so children
	## do not have to walk back up the chain to find it.
	var world_turn: float = 0.0

	## --- the arc a joint may turn through ---
	##
	## Measured from where the bone was drawn, not from the world and not from
	## the parent, so a limit written for a figure still means the same thing
	## when that figure is redrawn at another angle.
	##
	## Wide open by default. Without a limit a joint is a free hinge, and a
	## free hinge is not a joint: an elbow bends one way, and a solver told
	## only about distances will happily fold an arm backwards through the
	## shoulder to satisfy them. See `BoneSolver.limit_all`.
	var limit_low: float = -PI
	var limit_high: float = PI

	## --- secondary motion ---
	##
	## How much this bone trails behind the pose rather than snapping to it:
	## nought is rigid, one is a strand of hair. The three below are the
	## spring's own working state and are not saved — a pose is where the rig
	## *is*, and where a spring happened to be mid-swing is not part of it.
	var soft: float = 0.0
	var eased: float = 0.0
	var eased_target: float = 0.0
	var eased_speed: float = 0.0

	## --- how wide the drawing is here ---
	##
	## The half-width of the artwork across this bone, in page units, measured
	## once when the bone was laid. Nought means it was never measured — every
	## rig written before this existed — and the drawing falls back to sizing
	## the bone from its own length.
	##
	## Stored rather than measured on demand for one reason: the measurement
	## reads the layer's ink, and the layer's ink is not available everywhere
	## a bone is drawn. The canvas draws a rigged figure's skeleton without
	## ever reading that layer back off its surface, and it must stay that way
	## — reading a surface back is the single most expensive thing this app
	## can do per frame.
	var girth: float = 0.0

	## Whether this joint has been given an arc narrower than a full circle.
	func limited() -> bool:
		return limit_low > -PI + 0.0001 or limit_high < PI - 0.0001

	func length() -> float:
		return rest_a.distance_to(rest_b)

	func rest_angle() -> float:
		var span: Vector2 = rest_b - rest_a
		if span.length_squared() < 0.000001:
			return 0.0
		return span.angle()

	## Back to how it was drawn.
	func rest() -> void:
		turn = 0.0
		shift = Vector2.ZERO
		a = rest_a
		b = rest_b
		world_turn = 0.0

	func posed() -> bool:
		return absf(turn) > 0.0001 or shift.length_squared() > 0.0001

# ------------------------------------------------------------ the solve

## Turns rest and turn into `a` and `b`, for every bone, parents first.
##
## This is the only thing in the app allowed to write a bone's position, and
## everything else — swinging, reaching, loading a pose off the timeline —
## works by setting `turn` and calling this. One place that decides where a
## bone is means the answer cannot disagree with itself.
##
## Cheap enough to run on every drag event: a figure is a few dozen bones and
## each costs a rotation and an addition.
static func solve(bones: Array) -> void:
	for index in order(bones):
		var one: Bone = bones[index] as Bone
		var up: Bone = null
		if one.parent >= 0 and one.parent < bones.size() \
				and one.parent != index:
			up = bones[one.parent] as Bone
		if up == null:
			one.world_turn = one.turn
			one.a = one.rest_a + one.shift
		else:
			one.world_turn = up.world_turn + one.turn
			# Where this bone was laid relative to its parent's tip, turned
			# by however far the parent has turned. Nought for a bone laid at
			# the tip — the ordinary case, an elbow on a shoulder — and the
			# right answer for one laid partway along, which is how a thumb
			# hangs off a hand.
			one.a = up.b + (one.rest_a - up.rest_b).rotated(up.world_turn)
		one.b = one.a + Vector2.RIGHT.rotated(
			one.rest_angle() + one.world_turn) * one.length()

## The order to solve in: every parent before any of its children.
##
## Bones are laid in whatever order the hand laid them, so the array is not
## sorted by depth and cannot be assumed to be. A child solved before its
## parent reads last frame's tip and lags one drag behind — which looks
## exactly like a rig that is nearly working, and is the hardest kind of wrong
## to see.
##
## Depth is counted with a ceiling rather than trusted. A rig loaded from a
## file could carry a cycle — a bone that is its own grandparent — and a walk
## up a cycle does not end.
static func order(bones: Array) -> PackedInt32Array:
	var n: int = bones.size()
	var depth: PackedInt32Array = PackedInt32Array()
	depth.resize(n)
	for i in n:
		var steps: int = 0
		var at: int = (bones[i] as Bone).parent
		while at >= 0 and at < n and steps < n:
			steps += 1
			at = (bones[at] as Bone).parent
		depth[i] = steps

	var out: PackedInt32Array = PackedInt32Array()
	var deepest: int = 0
	for i in n:
		deepest = maxi(deepest, depth[i])
	for level in deepest + 1:
		for i in n:
			if depth[i] == level:
				out.append(i)
	return out

## Whether anything at all has been moved off its rest.
static func moved(bones: Array) -> bool:
	for b in bones:
		if (b as Bone).posed():
			return true
	return false

## Everything back to how it was drawn.
static func rest_all(bones: Array) -> void:
	for b in bones:
		(b as Bone).rest()
	solve(bones)

# ---------------------------------------------------------------- moving

## Points a bone at a place, and lets its children follow.
##
## `which` is the end under the finger: 1 for the tip, 0 for the root. A tip
## turns the bone about its own root, which is what a joint does. A root end
## on a bone with a parent is that parent's tip and belongs to the parent, so
## it is passed up; on a bone with no parent it carries the whole limb bodily,
## because there is nothing above it to turn about.
##
## Smooth by construction: an angle taken straight off the finger, no rounding,
## no steps, no stop. Where the finger goes the bone points.
static func swing(bones: Array, index: int, which: int, to: Vector2) -> void:
	if index < 0 or index >= bones.size():
		return
	var one: Bone = bones[index] as Bone
	if which == 0:
		if one.parent >= 0 and one.parent < bones.size():
			swing(bones, one.parent, 1, to)
			return
		# A root bone dragged by its root end travels. Its tip goes with it,
		# so the bone keeps its heading and its length and simply moves —
		# which is what taking hold of the base of a limb should feel like.
		one.shift += to - one.a
		solve(bones)
		return

	var up: Bone = null
	if one.parent >= 0 and one.parent < bones.size():
		up = bones[one.parent] as Bone
	var span: Vector2 = to - one.a
	if span.length_squared() < 0.000001:
		return
	var base: float = up.world_turn if up != null else 0.0
	one.turn = wrapf(span.angle() - one.rest_angle() - base, -PI, PI)
	solve(bones)

## Reaching, rather than swinging.
##
## Swinging turns one bone about one end. That is exact and it is also the
## slow way to pose an arm: to put a hand on a doorknob you swing the upper
## arm, look, swing the forearm, look, and repeat until the two happen to
## agree. Everybody who has rigged a limb has done this and nobody enjoys it.
##
## Reaching takes the *hand* to the doorknob and works out the elbow. Two
## bones, two known lengths, one known target — the triangle is determined,
## and the only thing left to choose is which way the elbow points, which is a
## property of the limb rather than of the pose. So it is solved in closed
## form: no iteration, no convergence, nothing to tune, and the same answer
## every time for the same input. On a tablet that matters twice, because an
## iterative solver would run on every drag event of every frame.
##
## Lengths are never changed. A target further off than the arm is long
## straightens the arm toward it and stops, which is what an arm does. A
## target closer than the arm can fold holds the tightest fold rather than
## letting the elbow pass through the shoulder.
##
## Returns false when `index` has no parent to make a chain with, so the
## caller can fall back to an ordinary swing.
static func reach(bones: Array, index: int, to: Vector2) -> bool:
	if index < 0 or index >= bones.size():
		return false
	var lower: Bone = bones[index] as Bone
	if lower.parent < 0 or lower.parent >= bones.size():
		return false
	var upper: Bone = bones[lower.parent] as Bone
	var l1: float = upper.length()
	var l2: float = lower.length()
	if l1 < 0.001 or l2 < 0.001:
		return false

	var root: Vector2 = upper.a
	var span: Vector2 = to - root
	var d: float = span.length()
	var far: float = l1 + l2
	if d < 0.000001:
		span = Vector2.RIGHT
		d = 1.0

	var arm: float = 0.0
	var fore: float = 0.0
	if d >= far - 0.000001:
		# Out of reach: straight at it, stopping where the arm ends.
		arm = span.angle()
		fore = arm
	else:
		var inner: float = absf(l1 - l2)
		if d < inner + 0.000001:
			d = inner + 0.000001
		var base: float = span.angle()
		var cos_a: float = clampf(
			(l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
		var side: float = elbow_side(root, upper.b, span)
		arm = base + acos(cos_a) * side
		var elbow: Vector2 = root + Vector2.RIGHT.rotated(arm) * l1
		var rest_span: Vector2 = root + span - elbow
		if rest_span.length_squared() < 0.000001:
			return false
		fore = rest_span.angle()

	var above: float = 0.0
	if upper.parent >= 0 and upper.parent < bones.size():
		above = (bones[upper.parent] as Bone).world_turn
	upper.turn = wrapf(arm - upper.rest_angle() - above, -PI, PI)
	lower.turn = wrapf(fore - lower.rest_angle() - arm, -PI, PI)
	solve(bones)
	return true

## Which side of the shoulder-to-target line the elbow is currently on.
##
## Kept from where the limb already is rather than chosen by a setting: an
## elbow does not change which way it bends halfway through a wave, and asking
## an animator to tick a box for something the arm already knows would be
## asking them to describe the obvious. Returns +1 or -1, never 0 — a limb
## that happens to be perfectly straight has to bend *somewhere*, and one
## consistent side beats a coin toss on every frame.
static func elbow_side(root: Vector2, elbow: Vector2, span: Vector2) -> float:
	var arm: Vector2 = elbow - root
	var cross: float = span.x * arm.y - span.y * arm.x
	return -1.0 if cross < 0.0 else 1.0

# ----------------------------------------------------------- finding one

## The joint under a finger, as `[bone index, which end]`, or empty.
##
## Tips win over root ends, and it is a strict preference rather than a
## distance comparison. Where two bones meet, the parent's tip and the child's
## root sit at exactly the same place, so comparing distances between them
## decides nothing and decides it differently every time the rig is nudged.
## Preferring the tip means taking hold of an elbow turns the upper arm and
## the forearm follows — which is what a person expects from a joint they can
## see is shared, and it is what every rig does.
static func joint_at(bones: Array, at: Vector2, reach_px: float) -> Array:
	var best: Array = []
	var best_d: float = reach_px * reach_px
	var best_tip: bool = false
	for i in bones.size():
		var one: Bone = bones[i] as Bone
		var db: float = at.distance_squared_to(one.b)
		if db <= best_d:
			best_d = db
			best = [i, 1]
			best_tip = true
		if best_tip:
			continue
		var da: float = at.distance_squared_to(one.a)
		if da <= best_d:
			best_d = da
			best = [i, 0]
	return best

## The bone a new one should hang from: the one whose tip it starts nearest.
static func parent_for(bones: Array, at: Vector2, reach_px: float) -> int:
	var best: int = -1
	var best_d: float = reach_px * reach_px
	for i in bones.size():
		var d: float = at.distance_squared_to((bones[i] as Bone).rest_b)
		if d < best_d:
			best_d = d
			best = i
	return best

## How close two bone ends must be to count as one joint.
##
## A fortieth of the drawing's longest side, held between sensible limits.
## Proportional because a skeleton is drawn at whatever size the figure is,
## and a fixed number is either too tight on a large canvas or too loose on a
## small one — and too loose is the worse of the two, because it chains limbs
## that were never joined and the error only shows once something bends.
static func join_reach(longest_side: float) -> float:
	return clampf(longest_side / 40.0, 12.0, 90.0)

## Hangs every bone off whichever one it starts on, for a skeleton that was
## gathered rather than laid — the bones of several layers read into one rig.
static func chain(bones: Array, reach_px: float) -> void:
	# Build the hierarchy from geometry, then weld every accepted child root to
	# its parent tip. This is deliberately done in REST space once, when Apply
	# is pressed: after that every pose is exact forward kinematics, not a
	# repeated proximity guess.
	for i in bones.size():
		var mine: Bone = bones[i] as Bone
		var best: int = -1
		var best_d: float = reach_px * reach_px
		for k in bones.size():
			if k == i:
				continue
			var d: float = mine.rest_a.distance_squared_to(
				(bones[k] as Bone).rest_b)
			if d < best_d:
				best_d = d
				best = k
		mine.parent = best
	_break_cycles(bones)
	# Hard positional attachment. A hand can place an elbow a few pixels away
	# from a forearm root; visually that is one joint, mathematically it must
	# become exactly one point or the child will always look as if it floats.
	for i in order(bones):
		var child: Bone = bones[i] as Bone
		if child.parent < 0 or child.parent >= bones.size():
			continue
		var parent: Bone = bones[child.parent] as Bone
		var delta: Vector2 = parent.rest_b - child.rest_a
		child.rest_a += delta
		child.rest_b += delta
		child.shift = Vector2.ZERO
		child.turn = 0.0
	solve(bones)

## Recalculate and hard-attach a rig after it is placed on artwork. Kept as a
## named entry point so every Apply path uses the same invariant.
static func stabilize_attachment(bones: Array, longest_side: float) -> void:
	chain(bones, join_reach(longest_side))
	for one in bones:
		var bone: Bone = one as Bone
		bone.eased = bone.turn
		bone.eased_target = bone.turn
		bone.eased_speed = 0.0
	solve(bones)

## A bone may not be its own ancestor. Two bones laid tip to tip in a ring
## will each pick the other, and a chain that closes on itself has no root to
## solve from.
static func _break_cycles(bones: Array) -> void:
	var n: int = bones.size()
	for i in n:
		var steps: int = 0
		var at: int = (bones[i] as Bone).parent
		while at >= 0 and at < n and steps <= n:
			if at == i:
				(bones[i] as Bone).parent = -1
				break
			steps += 1
			at = (bones[at] as Bone).parent

# ------------------------------------------------------------- the sensor

## Whether a bone would lie along the drawing rather than across the paper.
##
## A bone has to lie *along* the artwork, not merely start and end on it — an
## arm and a leg both have ink, and a bone joining them would cross the page
## between. So the whole length is walked and every step has to land on
## something. A few misses in a row are forgiven, because an outlined drawing
## is mostly hollow and a stroke's inside is empty paper; a run of them means
## the bone has left the drawing altogether.
##
## `on_ink` is asked rather than assumed, so this one rule serves a room that
## reads a layer, a room that reads a turnaround, and anything added later.
static func fits_on_ink(a: Vector2, b: Vector2, on_ink: Callable) -> bool:
	if not on_ink.is_valid():
		return false
	var span: float = a.distance_to(b)
	if span < 6.0:
		return false
	var steps: int = maxi(int(span / 3.0), 8)
	var misses: int = 0
	@warning_ignore("integer_division")
	var slack: int = maxi(floori(float(steps) / 6.0), 2)
	for i in steps + 1:
		if bool(on_ink.call(a.lerp(b, float(i) / float(steps)))):
			misses = 0
			continue
		misses += 1
		if misses > slack:
			return false
	return true

# ------------------------------------------------------------- writing

## The skeleton, written down so a layer can carry it between sessions.
##
## Both the rest and the pose go in. `ax`/`ay`/`bx`/`by` are where the bone
## was laid; `px`/`py`/`qx`/`qy` are where it stands now. The pose could be
## rebuilt from `turn` alone and is written out anyway, because everything
## that reads a rig without solving it — the canvas overlay, the vault, an
## export — wants the two ends and should not have to run a solver to find
## them.
static func to_rows(bones: Array) -> Array:
	var rows: Array = []
	for b in bones:
		var one: Bone = b as Bone
		rows.append({
			"ax": one.rest_a.x, "ay": one.rest_a.y,
			"bx": one.rest_b.x, "by": one.rest_b.y,
			"px": one.a.x, "py": one.a.y,
			"qx": one.b.x, "qy": one.b.y,
			"turn": one.turn,
			"sx": one.shift.x, "sy": one.shift.y,
			"parent": one.parent,
			"low": one.limit_low, "high": one.limit_high,
			"soft": one.soft,
			"girth": one.girth,
		})
	return rows

## Reads a skeleton back, from a file of any age.
##
## `turn` may be missing — every rig written before this file existed stored
## only the two posed ends — so when it is absent the turn is recovered from
## those ends by `adopt`. A rig saved last month opens posed exactly as it was
## left, which is the only acceptable answer: a format change must never cost
## somebody a pose they had already made.
##
## `hinged` may be present and is ignored. It said an end snapped to quarter
## turns, and nothing snaps now.
static func from_rows(rows: Array) -> Array:
	var bones: Array = []
	for row in rows:
		var one: Bone = Bone.new()
		one.rest_a = Vector2(float(row.get("ax", 0.0)),
			float(row.get("ay", 0.0)))
		one.rest_b = Vector2(float(row.get("bx", 0.0)),
			float(row.get("by", 0.0)))
		one.a = Vector2(float(row.get("px", row.get("ax", 0.0))),
			float(row.get("py", row.get("ay", 0.0))))
		one.b = Vector2(float(row.get("qx", row.get("bx", 0.0))),
			float(row.get("qy", row.get("by", 0.0))))
		one.parent = int(row.get("parent", -1))
		# Defaulted to wide open and rigid, so a rig written before joints
		# could be limited opens with joints that are not.
		one.limit_low = float(row.get("low", -PI))
		one.limit_high = float(row.get("high", PI))
		one.soft = float(row.get("soft", 0.0))
		# Absent in every rig written before bones were sized to the drawing.
		# Nought is the honest answer there and the drawing falls back.
		one.girth = float(row.get("girth", 0.0))
		if row.has("turn"):
			one.turn = float(row["turn"])
			one.shift = Vector2(float(row.get("sx", 0.0)),
				float(row.get("sy", 0.0)))
		bones.append(one)
	_break_cycles(bones)
	var told: bool = not rows.is_empty() and bool(rows[0].has("turn"))
	if told:
		solve(bones)
	else:
		adopt(bones)
	return bones

## Works out each bone's own turn from where its ends have ended up.
##
## Used for a rig saved before turns were written down, and for a skeleton
## gathered out of several layers where the poses were stored as positions.
## Parents first, because a child's turn is measured against its parent's, and
## a parent whose turn is not yet known cannot answer.
static func adopt(bones: Array) -> void:
	for index in order(bones):
		var one: Bone = bones[index] as Bone
		var span: Vector2 = one.b - one.a
		var here: float = one.rest_angle()
		if span.length_squared() > 0.000001:
			here = span.angle()
		var above: float = 0.0
		if one.parent >= 0 and one.parent < bones.size():
			above = (bones[one.parent] as Bone).world_turn
		one.turn = wrapf(here - one.rest_angle() - above, -PI, PI)
		one.world_turn = above + one.turn
		if one.parent < 0:
			one.shift = one.a - one.rest_a
	solve(bones)

## The skeleton as the skin wants it: flat arrays of ends and lengths.
##
## The same bones said a second way, because the skin weights a thousand
## points against every bone on every frame, and unpacking a nested dictionary
## a thousand times a frame to find four numbers is work nobody needs done.
static func rest_skeleton(bones: Array) -> Dictionary:
	var a: PackedVector2Array = PackedVector2Array()
	var b: PackedVector2Array = PackedVector2Array()
	var lengths: PackedFloat32Array = PackedFloat32Array()
	for one in bones:
		var bone: Bone = one as Bone
		a.append(bone.rest_a)
		b.append(bone.rest_b)
		lengths.append(bone.length())
	return {"a": a, "b": b, "len": lengths}

## Where the bones stand now, in the same shape.
static func posed_ends(bones: Array) -> Dictionary:
	var a: PackedVector2Array = PackedVector2Array()
	var b: PackedVector2Array = PackedVector2Array()
	for one in bones:
		var bone: Bone = one as Bone
		a.append(bone.a)
		b.append(bone.b)
	return {"a": a, "b": b}

# ------------------------------------------------------------ bending art

## A mesh of drawing, bent by a skeleton.
##
## ## Why it is here and not in a room
##
## Every room that holds bones eventually has to bend something with them, and
## the rooms that did were doing it their own separate ways. Putting the mesh
## pass beside the bone it belongs to means the next room to want it does not
## write another.
##
## ## Spaces
##
## `unit` is how many page units one mesh unit is worth. A morph mesh is built
## in figure space — feet at the origin, one unit is the standard height —
## while bones are in the page space the room's grid is measured in. So a
## vertex is multiplied out, bent, and divided back. Pass 1.0 for a mesh
## already in page units.
##
## Getting this the wrong way round is the difference between a figure that
## bends and a figure that leaves the screen, which is why the conversion is
## written once, here, rather than at each call.
##
## ## Cost
##
## Nothing at all when no bone has been moved: an unposed skeleton returns the
## mesh it was given, untouched and unduplicated. That matters, because this
## sits in a draw path that runs while a figure is being turned, and a
## turnaround with a skeleton on it must not be slower to spin than one
## without.
static func bend_mesh(mesh: ArrayMesh, bones: Array,
		unit: float = 1.0) -> ArrayMesh:
	if mesh == null or bones.is_empty() or not moved(bones):
		return mesh
	var rest_a: PackedVector2Array = PackedVector2Array()
	var rest_b: PackedVector2Array = PackedVector2Array()
	var now_a: PackedVector2Array = PackedVector2Array()
	var now_b: PackedVector2Array = PackedVector2Array()
	for one in bones:
		var bone: Bone = one as Bone
		rest_a.append(bone.rest_a)
		rest_b.append(bone.rest_b)
		now_a.append(bone.a)
		now_b.append(bone.b)
	return bend_mesh_by(mesh,
		RigSkin.bone_rule(rest_a, rest_b, now_a, now_b), unit)

## The same, given the rule directly.
##
## Split out because a rule does not have to come from bones alone — the
## puppet warp composes one out of pins, and the mesh work below has no
## opinion about where the rule came from, and should not.
static func bend_mesh_by(mesh: ArrayMesh, rule: Callable,
		unit: float = 1.0) -> ArrayMesh:
	if mesh == null or not rule.is_valid() or mesh.get_surface_count() < 1:
		return mesh
	var arrays: Array = mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return mesh
	# Read back without assuming which of the two vertex shapes came out.
	#
	# A surface built from a `PackedVector2Array` is a 2D mesh and reads back
	# as one; a surface built any other way reads back as `PackedVector3Array`
	# with z at nought. Declaring the wrong one of those is not a wrong answer,
	# it is a hard type error at the moment a figure is drawn — so the shape is
	# asked rather than assumed, and written back in whichever shape it arrived.
	var raw: Variant = arrays[Mesh.ARRAY_VERTEX]
	var flat: bool = typeof(raw) == TYPE_PACKED_VECTOR2_ARRAY
	var verts: PackedVector2Array = PackedVector2Array()
	if flat:
		verts = raw
	elif typeof(raw) == TYPE_PACKED_VECTOR3_ARRAY:
		var tall: PackedVector3Array = raw
		verts.resize(tall.size())
		for i in tall.size():
			verts[i] = Vector2(tall[i].x, tall[i].y)
	if verts.is_empty():
		return mesh

	var span: float = maxf(unit, 0.000001)
	var bent: PackedVector2Array = PackedVector2Array()
	bent.resize(verts.size())
	for i in verts.size():
		# The island argument is passed rather than left to a default: a
		# lambda's defaults are not something to lean on, and nought is the
		# right answer here anyway — a turnaround is one drawing, so there is
		# no second figure on the page for a bone to be kept away from.
		var landed: Vector2 = rule.call(verts[i] * span, 0)
		bent[i] = landed / span
	if flat:
		arrays[Mesh.ARRAY_VERTEX] = bent
	else:
		var tall_out: PackedVector3Array = PackedVector3Array()
		tall_out.resize(bent.size())
		for i in bent.size():
			tall_out[i] = Vector3(bent[i].x, bent[i].y, 0.0)
		arrays[Mesh.ARRAY_VERTEX] = tall_out

	var built: ArrayMesh = ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return built

# ------------------------------------------------- staying on the drawing

## How far a rig has to move to be back on the drawing it was laid on.
##
## ## The fault
##
## Bones are written down in page coordinates. That is the right thing to
## store — it is what the skin is weighted against and what every room reads —
## but page coordinates only mean anything *beside the drawing they describe*.
##
## Move the drawing and the numbers do not move with it. A page laid out at a
## different offset, a comic with more than one page, a project reopened after
## its pages were arranged differently: the skeleton keeps the coordinates it
## was given, the figure is somewhere else, and the bones are drawn out to one
## side of the artwork with nothing under them.
##
## ## The fix
##
## A rig now records the drawing's own rectangle at the moment it was
## accepted. Anything reading the rig compares that with where the ink is
## **now** and shifts by the difference. The skeleton is pinned to the
## artwork, not to a coordinate system nobody promised would hold still.
##
## Nought when the rig predates this — an older rig has no rectangle to
## compare, and guessing at one would be worse than leaving it where it is.
static func anchor_shift(rig: Dictionary, ink_now: Rect2i) -> Vector2:
	var was: Array = rig.get("ink", [])
	if was.size() < 4 or ink_now.size.x < 1:
		return Vector2.ZERO
	# --- only when the drawing was *moved*, not when it was changed ---
	#
	# This shift exists to keep a skeleton on its figure when the figure is
	# carried somewhere else. It reads the ink's corner, and the ink's corner
	# also moves when somebody rubs out the top-left of the drawing, or adds
	# a stroke past its old edge — and then the whole skeleton jumped
	# sideways by the width of an eraser stroke, having been laid perfectly
	# and never touched.
	#
	# A move keeps the drawing's size and changes its position. An edit
	# changes its size. So the shift is applied only when the size still
	# matches, within a tolerance for a stroke's own softness — and when it
	# does not, nothing is shifted and the bones stay exactly where they were
	# put, which is the answer that is right far more often.
	var was_size: Vector2 = Vector2(float(was[2]), float(was[3]))
	if was_size.x > 1.0:
		var grew: Vector2 = (Vector2(ink_now.size) - was_size).abs()
		var slack: float = maxf(was_size.x, was_size.y) * 0.06 + 4.0
		if grew.x > slack or grew.y > slack:
			return Vector2.ZERO
	return Vector2(float(ink_now.position.x) - float(was[0]),
		float(ink_now.position.y) - float(was[1]))

## The drawing's own rectangle right now, for comparing against the one a rig
## was laid on. Trimmed to the ink, because `content_bounds` answers in whole
## tiles and a tile boundary moving would read as the drawing moving.
static func ink_of(l: LayerStack.Layer) -> Rect2i:
	if l == null or l.surface == null:
		return Rect2i()
	var box: Rect2 = TextRender.ink_bounds(l.surface)
	return Rect2i(Vector2i(box.position), Vector2i(box.size))
