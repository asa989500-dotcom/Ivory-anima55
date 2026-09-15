extends "res://tests/test_case.gd"
## The bone, checked rather than trusted.
##
## Every claim made for the rewritten skeleton is a claim about arithmetic —
## that a chain carries rotation, that a limb keeps its length at every angle,
## that nothing snaps, that a pose read back off a file is the pose that was
## saved. All four are the kind of thing that looks right on a screen for the
## one pose you happened to try and is wrong at a hundred and seventy degrees.
##
## The one that matters most is the first. `_carry_children` used to *shift* a
## child bone by however far its parent's tip had moved, and a shift is not a
## rotation: swing an upper arm ninety degrees and the forearm arrived at the
## elbow still pointing the way it was drawn. That is the whole of the
## complaint that bones do not stay inside the drawing, and the check below is
## the exact case, with the number a shift would have produced written beside
## the number a rotation does.

func title() -> String:
	return "bones"

func run() -> void:
	_a_chain_carries_rotation()
	_limbs_keep_their_length()
	_nothing_snaps()
	_a_pose_survives_a_round_trip()
	_a_bone_may_not_be_its_own_ancestor()

## An arm: shoulder to elbow, elbow to wrist, wrist to hand.
func _arm() -> Array:
	var bones: Array = []
	var upper: BoneRig.Bone = BoneRig.Bone.new()
	upper.rest_a = Vector2(0.0, 0.0)
	upper.rest_b = Vector2(100.0, 0.0)
	bones.append(upper)
	var fore: BoneRig.Bone = BoneRig.Bone.new()
	fore.rest_a = Vector2(100.0, 0.0)
	fore.rest_b = Vector2(180.0, 0.0)
	fore.parent = 0
	bones.append(fore)
	var hand: BoneRig.Bone = BoneRig.Bone.new()
	hand.rest_a = Vector2(180.0, 0.0)
	hand.rest_b = Vector2(210.0, 0.0)
	hand.parent = 1
	bones.append(hand)
	BoneRig.solve(bones)
	return bones

func _a_chain_carries_rotation() -> void:
	note("a swung parent turns its children instead of dragging them")
	var arm: Array = _arm()
	var upper: BoneRig.Bone = arm[0]
	var fore: BoneRig.Bone = arm[1]
	var hand: BoneRig.Bone = arm[2]

	# Straight down: a quarter turn, the angle the old code was worst at.
	BoneRig.swing(arm, 0, 1, Vector2(0.0, 100.0))

	near(upper.b.x, 0.0, 0.001, "the upper arm points down")
	near(upper.b.y, 100.0, 0.001, "the upper arm keeps its length")
	near(fore.a.distance_to(upper.b), 0.0, 0.001,
		"the forearm sits on the elbow")
	# The number that matters. A shift would put the forearm's tip at
	# (80, 100) — pointing the way it was drawn, sticking out sideways. A
	# rotation puts it at (0, 180), in line with the arm above it.
	near(fore.b.x, 0.0, 0.001,
		"the forearm turned with the arm rather than being shifted along it")
	near(fore.b.y, 180.0, 0.001, "and it is where a turned forearm belongs")
	near(hand.a.distance_to(fore.b), 0.0, 0.001,
		"the hand is still attached to the wrist")

func _limbs_keep_their_length() -> void:
	note("no angle changes a bone's length")
	var arm: Array = _arm()
	var want: PackedFloat32Array = PackedFloat32Array()
	for one in arm:
		want.append((one as BoneRig.Bone).length())
	var wrong: int = 0
	for step in 52:
		var turn: float = float(step) * TAU / 52.0
		BoneRig.swing(arm, 0, 1, Vector2.RIGHT.rotated(turn) * 100.0)
		var elbow: Vector2 = (arm[1] as BoneRig.Bone).a
		BoneRig.swing(arm, 1, 1,
			elbow + Vector2.RIGHT.rotated(turn * 2.0) * 80.0)
		for i in arm.size():
			var one: BoneRig.Bone = arm[i] as BoneRig.Bone
			if absf(one.a.distance_to(one.b) - want[i]) > 0.01:
				wrong += 1
	eq(wrong, 0, "156 bone-poses and not one limb stretched or shrank")

func _nothing_snaps() -> void:
	note("a joint turns wherever it is taken — no angle it jumps to")
	var arm: Array = _arm()
	var seen: Dictionary = {}
	for step in 200:
		var turn: float = deg_to_rad(float(step) * 0.37)
		BoneRig.swing(arm, 0, 1, Vector2.RIGHT.rotated(turn) * 100.0)
		seen[snappedf((arm[0] as BoneRig.Bone).turn, 0.000001)] = true
	# A right-angle stop would answer four of these, whatever was asked for.
	eq(seen.size(), 200,
		"200 small drags gave 200 different angles, not four")

func _a_pose_survives_a_round_trip() -> void:
	note("a rig written to a file opens standing where it was left")
	var arm: Array = _arm()
	BoneRig.swing(arm, 0, 1, Vector2(30.0, 95.0))
	var elbow: Vector2 = (arm[1] as BoneRig.Bone).a
	BoneRig.swing(arm, 1, 1, elbow + Vector2(-70.0, 40.0))

	var rows: Array = BoneRig.to_rows(arm)
	var back: Array = BoneRig.from_rows(rows)
	eq(back.size(), arm.size(), "every bone came back")
	var drift: float = 0.0
	for i in arm.size():
		var was: BoneRig.Bone = arm[i] as BoneRig.Bone
		var now: BoneRig.Bone = back[i] as BoneRig.Bone
		drift = maxf(drift, was.a.distance_to(now.a))
		drift = maxf(drift, was.b.distance_to(now.b))
	ok(drift < 0.01, "and every bone came back to the same place")

	# The same, for a file written before turns were recorded: only the four
	# endpoints, no `turn`, no `sx`/`sy`. The pose has to be recovered from
	# the positions alone or somebody loses work they had already done.
	var old: Array = []
	for row in rows:
		var trimmed: Dictionary = (row as Dictionary).duplicate()
		trimmed.erase("turn")
		trimmed.erase("sx")
		trimmed.erase("sy")
		# And a key from the version that had a right-angle stop, which must
		# be read past rather than choked on.
		trimmed["hinged"] = true
		old.append(trimmed)
	var older: Array = BoneRig.from_rows(old)
	var old_drift: float = 0.0
	for i in arm.size():
		var was2: BoneRig.Bone = arm[i] as BoneRig.Bone
		var now2: BoneRig.Bone = older[i] as BoneRig.Bone
		old_drift = maxf(old_drift, was2.b.distance_to(now2.b))
	ok(old_drift < 0.01,
		"a rig saved before turns existed opens in the pose it was saved in")

func _a_bone_may_not_be_its_own_ancestor() -> void:
	note("a chain that closes on itself is opened rather than hung on")
	var ring: Array = []
	for i in 3:
		var one: BoneRig.Bone = BoneRig.Bone.new()
		one.rest_a = Vector2.RIGHT.rotated(float(i) * TAU / 3.0) * 50.0
		one.rest_b = Vector2.RIGHT.rotated(float(i + 1) * TAU / 3.0) * 50.0
		ring.append(one)
	# Each hangs off the next, all the way round.
	(ring[0] as BoneRig.Bone).parent = 2
	(ring[1] as BoneRig.Bone).parent = 0
	(ring[2] as BoneRig.Bone).parent = 1
	var rows: Array = BoneRig.to_rows(ring)
	var read: Array = BoneRig.from_rows(rows)
	var roots: int = 0
	for one in read:
		if (one as BoneRig.Bone).parent < 0:
			roots += 1
	ok(roots >= 1, "the ring was opened, so the rig has something to solve from")
	# And it solves — which is the real test. A cycle left in place is an
	# endless walk up the parents, and the app would simply stop.
	BoneRig.solve(read)
	BoneRig.swing(read, 0, 1, Vector2(0.0, 60.0))
	ok(true, "and posing it returns")
