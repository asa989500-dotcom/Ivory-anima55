class_name BoneSolver
extends RefCounted
## The three things IVORY's skeleton did not have, ported from SoupIK.
##
## ## Where this comes from
##
## SoupIK — "Souperior 2D Skeleton Modifications" — is ZedManul's Godot addon,
## MIT licensed, 2023. The licence text ships beside this file at
## `docs/SOUPIK_LICENSE.txt`, and it is kept because the licence requires it
## and because attribution is owed whether or not a licence asks.
##
## ## Why it is a port and not the addon
##
## The addon is built out of **nodes**. Its bones are `Bone2D` in a
## `Skeleton2D`, its solvers are `SoupMod` nodes whose *order in the scene
## tree* decides the order they run in, and it reads and writes
## `global_rotation` on live objects every frame.
##
## IVORY's skeleton is not a node tree. A `BoneRig.Bone` is plain data — a
## rest, a turn, a parent index — living in an array on a layer, saved to a
## file, and solved on demand rather than every frame. A drawing gets a
## skeleton; the skeleton is not part of the scene.
##
## Those two designs cannot be glued together. Dropping the addon in would
## have meant a second, parallel skeleton system living beside ours, with its
## own bone class, its own solve order and its own idea of where a bone is —
## which is precisely the two-of-everything problem that `bone_rig.gd` was
## written to end.
##
## So what was taken is the **arithmetic**, which is the valuable part and the
## part that is genuinely hard to get right:
##
##   * **FABRIK** — reaching with a chain of any length. IVORY had closed-form
##     reach for exactly two bones and nothing at all for three or more.
##   * **Joint limits** — an arc a bone may turn within. IVORY had none, so an
##     elbow could bend backwards and a knee could fold the wrong way.
##   * **Second-order settling** — the spring that makes hair and cloth trail
##     behind a movement, with the low-framerate guard that keeps it from
##     exploding on a slow device.
##
## Everything here is static and takes an array of `BoneRig.Bone`. There is
## still one skeleton in this application.

## How near a target counts as reached, in page units. Below this the chain
## stops iterating: further passes move it by less than a pixel and cost as
## much as the first.
const CLOSE_ENOUGH: float = 0.35

# ------------------------------------------------------------------ FABRIK

## Reaching a target with a chain of bones of any length.
##
## ## What this adds
##
## IVORY could already put a hand on a doorknob when the arm was exactly two
## bones, in closed form — see `BoneRig.reach`, which is exact, needs no
## iteration and is still used for that case because nothing beats it there.
##
## Three bones and it had nothing. A finger, a tail, a spine, a hind leg, a
## strand of hair: anything longer than an upper arm and a forearm had to be
## posed one joint at a time, which is the slow way and the reason most people
## give up on rigging.
##
## ## How it works
##
## FABRIK — Forward And Backward Reaching Inverse Kinematics. Two sweeps, and
## the whole idea fits in a sentence each way.
##
## **Backward:** put the tip on the target, then walk down the chain pulling
## each joint to the correct distance from the one after it. Every bone now
## has its right length and the tip is on target; the root has moved, which is
## wrong.
##
## **Forward:** put the root back where it belongs, then walk up doing the
## same thing. Every bone has its right length and the root is right; the tip
## has drifted off target, but by less than before.
##
## Repeat and it converges. Not "usually converges" — it is a sequence of
## projections onto convex sets, so it cannot diverge and cannot oscillate.
## That is why it is the standard answer for a chain, and it is why one pass
## is very nearly enough: after a single sweep the tip is typically within a
## pixel of the target, because a finger moves a small distance between one
## touch event and the next and the chain starts from where it already was.
##
## No trigonometry anywhere. It is all distances and one normalise per joint,
## which is what makes it cheap enough to run on every touch event of every
## frame on a tablet.
##
## `passes` is capped, and the loop leaves early once the tip is close enough,
## so a chain already on target costs one comparison rather than sixteen
## sweeps that move nothing.
##
## Returns false when there is no chain to solve — one bone, or a broken
## parent index — so the caller can fall back to an ordinary swing.
static func reach_chain(bones: Array, index: int, target: Vector2,
		passes: int = 2) -> bool:
	var chain: PackedInt32Array = chain_of(bones, index)
	if chain.size() < 2:
		return false

	# Joint positions, root first, plus the tip. One more point than bones,
	# because a chain of n bones has n+1 joints — the classic off-by-one of
	# every IK implementation ever written.
	var joints: PackedVector2Array = PackedVector2Array()
	var lengths: PackedFloat32Array = PackedFloat32Array()
	for k in chain.size():
		var b: BoneRig.Bone = bones[chain[k]] as BoneRig.Bone
		joints.append(b.a)
		lengths.append(b.length())
	joints.append((bones[chain[chain.size() - 1]] as BoneRig.Bone).b)

	var root: Vector2 = joints[0]
	var span: float = 0.0
	for l in lengths:
		span += l
	if span < 0.001:
		return false

	# Out of reach: there is nothing to iterate towards. The chain
	# straightens at the target and stops, which is what an arm does, and it
	# is worth answering directly because it is the case where FABRIK
	# converges slowest.
	if root.distance_to(target) >= span:
		var way: Vector2 = target - root
		if way.length_squared() < 0.000001:
			way = Vector2.RIGHT
		way = way.normalized()
		for k in lengths.size():
			joints[k + 1] = joints[k] + way * lengths[k]
		return _write_back(bones, chain, joints)

	var last: int = joints.size() - 1
	for _pass in maxi(passes, 1):
		if joints[last].distance_to(target) <= CLOSE_ENOUGH:
			break
		# Backward: the tip goes to the target and the chain follows it down.
		joints[last] = target
		for k in range(last, 0, -1):
			joints[k - 1] = _pull(joints[k], joints[k - 1], lengths[k - 1])
		# Forward: the root goes home and the chain follows it up.
		joints[0] = root
		for k in last:
			joints[k + 1] = _pull(joints[k], joints[k + 1], lengths[k])
	return _write_back(bones, chain, joints)

## `to` moved onto the circle of radius `span` around `from`.
static func _pull(from: Vector2, to: Vector2, span: float) -> Vector2:
	var way: Vector2 = to - from
	if way.length_squared() < 0.000001:
		way = Vector2.RIGHT
	return from + way.normalized() * span

## The chain of bones ending at `index`, roots first.
##
## Walked up the parents and capped, because a rig read from a file could
## carry a cycle and a walk up a cycle does not end. Capped again at a sane
## chain length: a spine of two hundred bones is a corrupt file, not a
## drawing, and solving it would hang the frame rather than fail.
static func chain_of(bones: Array, index: int, most: int = 24) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if index < 0 or index >= bones.size():
		return out
	var at: int = index
	var steps: int = 0
	while at >= 0 and at < bones.size() and steps < most:
		out.append(at)
		at = (bones[at] as BoneRig.Bone).parent
		steps += 1
	out.reverse()
	return out

## Turns solved joint positions back into the turns a bone is stored as.
##
## This is the step the addon does not need and IVORY cannot do without. The
## addon writes `global_rotation` straight onto a live node; here a bone *is*
## its turn relative to its parent, so each solved direction has to be
## measured against the rest heading and against everything above it — and
## then the whole rig is solved once, so that `a` and `b` agree with the turns
## rather than being set beside them.
static func _write_back(bones: Array, chain: PackedInt32Array,
		joints: PackedVector2Array) -> bool:
	for k in chain.size():
		var one: BoneRig.Bone = bones[chain[k]] as BoneRig.Bone
		var span: Vector2 = joints[k + 1] - joints[k]
		if span.length_squared() < 0.000001:
			continue
		var above: float = 0.0
		if one.parent >= 0 and one.parent < bones.size():
			above = (bones[one.parent] as BoneRig.Bone).world_turn
		one.turn = wrapf(span.angle() - one.rest_angle() - above, -PI, PI)
		# Solved as we go rather than all at the end: the next bone's `above`
		# has to be this bone's *new* world turn, not the one it had before
		# this sweep. Doing it after the loop reads a stale parent and the
		# chain lands one joint out — which looks like a rig that nearly
		# works, the worst kind of wrong to find.
		BoneRig.solve(bones)
	limit_all(bones)
	return true

# ------------------------------------------------------------ joint limits

## Holds every bone inside the arc it is allowed to turn through.
##
## ## Why a rig needs this
##
## Without limits a joint is a free hinge, and a free hinge is not a joint.
## An elbow bends one way. A knee bends one way. Reaching for something behind
## a figure, the solver above is perfectly happy to fold an arm backwards
## through the shoulder — it satisfies every distance it was asked about, and
## the result is a drawing with its elbow inside its own chest.
##
## That is the single most common complaint about inverse kinematics, and it
## is not a flaw in the solver. The solver was never told the joint had a
## front and a back.
##
## ## How it is stated
##
## Each bone carries `limit_low` and `limit_high`, in radians, **measured from
## where the bone was drawn**. Not from the world, not from its parent — from
## its own rest. So a limit written for a figure applies unchanged when that
## figure is redrawn at a different angle, and a rig copied to another
## character keeps meaning what it meant.
##
## Wide open by default, so nothing that already worked is suddenly caged.
## Limits are something a person chooses to add to a joint that needs one.
static func limit_all(bones: Array) -> void:
	var touched: bool = false
	for one in bones:
		var b: BoneRig.Bone = one as BoneRig.Bone
		if not b.limited():
			continue
		var held: float = clampf(b.turn, b.limit_low, b.limit_high)
		if absf(held - b.turn) > 0.000001:
			b.turn = held
			touched = true
	if touched:
		BoneRig.solve(bones)

# --------------------------------------------------- second-order settling

## The spring that makes hair, cloth and tails trail behind a movement.
##
## ## What it is
##
## A second-order system — the same arithmetic a suspension spring obeys —
## driven towards the pose the rig has actually been put into. The bone does
## not jump to its target; it accelerates towards it, overshoots a little if
## it is springy, and settles.
##
## Three numbers describe it, and they were chosen because each one is a thing
## a person can picture rather than a coefficient:
##
##   * **frequency** — how fast it responds. High is stiff wire, low is heavy
##     rope.
##   * **damping** — how it arrives. One settles cleanly; below one it
##     wobbles first, which is what hair does.
##   * **reaction** — how eagerly it starts. Above one it overshoots on the
##     way out; below nought it *anticipates*, drawing back before it moves,
##     which is a piece of animation grammar older than computers.
##
## ## The line that matters most
##
## `_stable_k2`. A second-order system integrated with too large a timestep
## does not degrade — it **diverges**, oscillating wider every frame until the
## numbers become infinities and the drawing disappears. That is not a slow
## device looking slightly wrong; it is a slow device destroying the pose.
##
## Clamping k2 against the frame time makes divergence impossible at any
## framerate. A device dropping to fifteen frames a second gets stiffer hair
## instead of an explosion. On a tablet — where the frame time is whatever the
## rest of the app left over — this is the difference between a feature that
## can ship and one that cannot.
##
## Straight from SoupIK, which took it from the standard treatment of second
## order systems in animation. Kept exactly, because the guard is the whole
## point and a re-derivation would only be a chance to get it wrong.
static func settle(bones: Array, delta: float, frequency: float = 3.0,
		damping: float = 0.6, reaction: float = 1.4) -> void:
	if delta <= 0.0 or bones.is_empty():
		return
	var f: float = maxf(frequency, 0.001)
	var k1: float = damping / (PI * f)
	var k2: float = 1.0 / ((TAU * f) * (TAU * f))
	var k3: float = reaction * damping / (TAU * f)
	var stable: float = maxf(k2,
		maxf(delta * delta * 0.5 + delta * k1 * 0.5, delta * k1))

	for one in bones:
		var b: BoneRig.Bone = one as BoneRig.Bone
		if b.soft <= 0.0:
			continue
		var want: float = b.turn
		var gap: float = wrapf(want - b.eased, -PI, PI)
		var aim: float = wrapf(want - b.eased_target, -PI, PI) / delta
		b.eased += b.eased_speed * delta
		b.eased_speed += delta * (gap - k1 * b.eased_speed + k3 * aim) / stable
		b.eased_target = want
		# Blended by `soft` rather than replacing the turn outright, so one
		# strand can trail while the arm it hangs from stays exactly where it
		# was put. A rig where everything wobbles is not a rig.
		b.turn = wrapf(want + (b.eased - want) * clampf(b.soft, 0.0, 1.0),
			-PI, PI)
	limit_all(bones)
	BoneRig.solve(bones)

## Puts the springs at rest, so nothing swings on the first frame after a rig
## is loaded or a pose is jumped to.
static func calm(bones: Array) -> void:
	for one in bones:
		var b: BoneRig.Bone = one as BoneRig.Bone
		b.eased = b.turn
		b.eased_target = b.turn
		b.eased_speed = 0.0

# ----------------------------------------------------- turning with a view

## A limb swung along the arc a turning view would show it travelling.
##
## ## What was asked for
##
## When a figure is seen from the front and an arm swings, the hand travels on
## a **circle** about the shoulder. Turn the view a quarter and that same
## circle is seen edge-on: the hand still travels the same path in the world,
## but on the screen it now moves almost entirely up and down, because the
## part of the circle that pointed at the camera has collapsed to nothing.
##
## That collapse is the whole of what makes a turn read as a turn rather than
## as a slide, and it is not a stylistic choice — a circle seen at angle θ is
## an ellipse whose width is `cos θ` of its height. One cosine.
##
## ## The closing point
##
## An arm does not swing through the body. It swings until it reaches it, and
## then it stops — the "closing point" is the torso, and it is a different
## mass of the same figure.
##
## So the arc is walked rather than jumped to. Each step asks whether the tip
## has arrived somewhere it may not be, and the first refusal ends the swing
## at the last place that was allowed. Walking rather than clamping matters:
## a limb that clamped would pass *through* the torso and reappear stopped on
## the far side whenever the target lay beyond it, which is the one failure a
## viewer notices instantly.
##
## `solid` is asked rather than assumed — the caller knows what its own figure
## is made of — and a swing with nothing to ask simply runs to the end of its
## arc, which is right for a limb with nothing in its way.
##
## ## Cost
##
## `steps` is the only expense and the caller sets it from what the device has
## spare. Sixteen steps is a smooth arc; four is a coarser one that ends in
## the same place, because the stopping test is the same test at every
## resolution. Nothing here allocates and nothing iterates to convergence, so
## the cheap version is the same answer drawn less finely rather than a
## different answer.
static func turn_arc(bones: Array, index: int, sweep: float,
		view_turn: float, solid: Callable = Callable(),
		steps: int = 16) -> void:
	if index < 0 or index >= bones.size():
		return
	var one: BoneRig.Bone = bones[index] as BoneRig.Bone
	var was: float = one.turn
	var flat: float = cos(view_turn)
	var reached: float = 0.0
	var n: int = maxi(steps, 2)

	for k in range(1, n + 1):
		var part: float = float(k) / float(n)
		# The arc as it is *seen*: the sideways half of the swing narrowed by
		# the view, the up-and-down half untouched. At a quarter turn the
		# cosine is nought and the hand rises and falls without appearing to
		# travel across at all, which is exactly what a real arm looks like
		# from the side.
		var here: float = was + sweep * part
		var wide: Vector2 = Vector2.RIGHT.rotated(
			one.rest_angle() + here) * one.length()
		var seen: Vector2 = one.a + Vector2(wide.x * flat, wide.y)
		if solid.is_valid() and bool(solid.call(seen)):
			break
		reached = here
		one.turn = wrapf(here, -PI, PI)

	if reached == 0.0:
		one.turn = was
	limit_all(bones)
	BoneRig.solve(bones)

## How finely an arc should be walked on this device.
##
## The stopping test is the same at every resolution, so a coarse arc ends
## where a fine one ends — only the path there is drawn in fewer places. That
## is why this can be rationed without the pose changing, and it is the reason
## the swing is walked in the first place rather than solved.
static func arc_steps() -> int:
	if Perf.tier == Perf.Tier.HIGH:
		return 20 if Perf.headroom > 0.4 else 12
	if Perf.tier == Perf.Tier.MEDIUM:
		return 10 if Perf.headroom > 0.3 else 6
	return 4
