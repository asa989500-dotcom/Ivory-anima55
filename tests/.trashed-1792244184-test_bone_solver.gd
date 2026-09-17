extends "res://tests/test_case.gd"
## The three things ported from SoupIK, checked rather than trusted.
##
## Each one is a claim about arithmetic that looks right on a screen for the
## one pose anybody thinks to try. A chain that converges *most* of the time,
## a joint limit that holds except at the wrap-around, a spring that is stable
## at sixty frames and explodes at fifteen — all three are invisible by hand
## and obvious here.

func title() -> String:
	return "bone solver"

func run() -> void:
	_a_long_chain_reaches()
	_a_chain_keeps_its_lengths()
	_out_of_reach_straightens()
	_a_joint_holds_its_arc()
	_the_spring_is_stable_at_any_framerate()

## A tail: five bones in a line, each shorter than the last.
func _tail() -> Array:
	var bones: Array = []
	var at: float = 0.0
	var span: float = 60.0
	for i in 5:
		var b: BoneRig.Bone = BoneRig.Bone.new()
		b.rest_a = Vector2(at, 0.0)
		b.rest_b = Vector2(at + span, 0.0)
		b.parent = i - 1
		bones.append(b)
		at += span
		span *= 0.85
	BoneRig.solve(bones)
	return bones

func _a_long_chain_reaches() -> void:
	note("five bones put their tip on a target the old solver could not reach")
	var tail: Array = _tail()
	var tip: int = tail.size() - 1
	# Well inside reach, and a long way off the rest heading, so a solver that
	# merely nudged would be caught.
	var target: Vector2 = Vector2(70.0, 120.0)
	var done: bool = BoneSolver.reach_chain(tail, tip, target, 8)
	ok(done, "the chain solved")
	var landed: Vector2 = (tail[tip] as BoneRig.Bone).b
	ok(landed.distance_to(target) < 2.0,
		"the tip arrived, %0.2f units out" % landed.distance_to(target))

	# And the closed-form two-bone reach is untouched by any of this: it is
	# still what a two-bone chain uses, and it is still exact.
	var arm: Array = []
	var upper: BoneRig.Bone = BoneRig.Bone.new()
	upper.rest_b = Vector2(100.0, 0.0)
	arm.append(upper)
	var fore: BoneRig.Bone = BoneRig.Bone.new()
	fore.rest_a = Vector2(100.0, 0.0)
	fore.rest_b = Vector2(180.0, 0.0)
	fore.parent = 0
	arm.append(fore)
	BoneRig.solve(arm)
	ok(BoneRig.reach(arm, 1, Vector2(40.0, 90.0)), "two bones still reach")

func _a_chain_keeps_its_lengths() -> void:
	note("no target stretches a bone")
	var tail: Array = _tail()
	var want: PackedFloat32Array = PackedFloat32Array()
	for one in tail:
		want.append((one as BoneRig.Bone).length())
	var wrong: int = 0
	for step in 40:
		var turn: float = float(step) * TAU / 40.0
		var far: float = 40.0 + float(step) * 4.0
		BoneSolver.reach_chain(tail, tail.size() - 1,
			Vector2.RIGHT.rotated(turn) * far, 4)
		for i in tail.size():
			var b: BoneRig.Bone = tail[i] as BoneRig.Bone
			if absf(b.a.distance_to(b.b) - want[i]) > 0.05:
				wrong += 1
	eq(wrong, 0, "200 bone-poses, near and far, and nothing stretched")

func _out_of_reach_straightens() -> void:
	note("a target further off than the chain is long straightens it")
	var tail: Array = _tail()
	var span: float = 0.0
	for one in tail:
		span += (one as BoneRig.Bone).length()
	var far: Vector2 = Vector2(0.0, span * 4.0)
	BoneSolver.reach_chain(tail, tail.size() - 1, far, 4)
	var tip: Vector2 = (tail[tail.size() - 1] as BoneRig.Bone).b
	var root: Vector2 = (tail[0] as BoneRig.Bone).a
	near(root.distance_to(tip), span, 0.5,
		"it reached its full length and stopped there")
	# Straight means every joint on the line from root to tip.
	var bent: float = 0.0
	for one in tail:
		var b: BoneRig.Bone = one as BoneRig.Bone
		bent = maxf(bent, absf(b.a.x - root.x))
	ok(bent < 0.5, "and it is pointing at the target, not curled")

func _a_joint_holds_its_arc() -> void:
	note("a limited joint cannot be driven outside its arc, at any angle")
	var arm: Array = _tail()
	var elbow: BoneRig.Bone = arm[2] as BoneRig.Bone
	elbow.limit_low = 0.0
	elbow.limit_high = deg_to_rad(120.0)
	ok(elbow.limited(), "the joint knows it is limited")
	var broke: int = 0
	for step in 60:
		var turn: float = float(step) * TAU / 60.0
		BoneSolver.reach_chain(arm, arm.size() - 1,
			Vector2.RIGHT.rotated(turn) * 150.0, 4)
		if elbow.turn < -0.001 or elbow.turn > deg_to_rad(120.0) + 0.001:
			broke += 1
	eq(broke, 0, "60 targets all round the compass and it never bent backwards")

	# A joint nobody limited is still free. A limit that arrived by default
	# would cage every rig ever made in this app.
	var free: BoneRig.Bone = arm[1] as BoneRig.Bone
	ok(not free.limited(), "an untouched joint is still a free one")

func _the_spring_is_stable_at_any_framerate() -> void:
	note("secondary motion settles instead of exploding on a slow device")
	# The failure this guards against is not "looks wrong on a slow device".
	# A second-order system integrated with too large a step *diverges* —
	# wider every frame until the numbers are infinities and the drawing is
	# gone. Fifteen frames a second is an ordinary tablet under load.
	for rate in [60.0, 30.0, 15.0, 8.0]:
		var tail: Array = _tail()
		for one in tail:
			(one as BoneRig.Bone).soft = 1.0
		BoneSolver.calm(tail)
		(tail[2] as BoneRig.Bone).turn = 1.2
		var worst: float = 0.0
		for _frame in 200:
			BoneSolver.settle(tail, 1.0 / rate, 6.0, 0.4, 1.6)
			for one in tail:
				var b: BoneRig.Bone = one as BoneRig.Bone
				worst = maxf(worst, absf(b.eased_speed))
		ok(worst < 1000.0 and is_finite(worst),
			"at %d fps the spring stayed finite (worst speed %0.1f)"
				% [int(rate), worst])
