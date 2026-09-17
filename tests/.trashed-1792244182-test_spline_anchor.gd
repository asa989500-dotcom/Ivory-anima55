extends "res://tests/test_case.gd"
## Moving one control point, and what it is allowed to touch.
##
## Both faults here were invisible on the gentle bend anybody tries first and
## severe on the sharp one they try second — which is the pattern that makes a
## tool feel unreliable rather than limited.

func title() -> String:
	return "spline anchor"

func run() -> void:
	_a_vertex_stays_between_its_own_points()
	_rest_is_reproduced_exactly()
	_a_bend_does_not_fold_through_itself()
	_the_outside_of_a_bend_is_left_alone()

func _anchors() -> PackedFloat32Array:
	# Five control points, evenly spread along a curve 400 units long.
	return PackedFloat32Array([0.0, 100.0, 200.0, 300.0, 400.0])

func _peg_one(at: float, anchors: PackedFloat32Array) -> Dictionary:
	var where: PackedInt32Array = PackedInt32Array([0])
	var mix: PackedFloat32Array = PackedFloat32Array([0.0])
	var off0: PackedFloat32Array = PackedFloat32Array([0.0])
	var off1: PackedFloat32Array = PackedFloat32Array([0.0])
	SplineAnchor.peg(0, at, anchors, where, mix, off0, off1)
	return {"at": where, "mix": mix, "off0": off0, "off1": off1}

## The heart of it. A vertex sitting between control points 1 and 2 must not
## care what control point 4 is doing — and it used to care about all of them,
## because its coordinate was a distance from the *start* and every point that
## moved changed the curve's length.
func _a_vertex_stays_between_its_own_points() -> void:
	note("a drag four points away moves a vertex not at all")
	var anchors: PackedFloat32Array = _anchors()
	var pegged: Dictionary = _peg_one(150.0, anchors)
	var before: float = SplineAnchor.where_now(0, anchors, pegged["at"],
		pegged["mix"], pegged["off0"], pegged["off1"],
		PackedFloat32Array([150.0]))
	near(before, 150.0, 0.001, "at rest it is where it was bound")

	# The far end of the curve is dragged, lengthening everything past it.
	var moved: PackedFloat32Array = PackedFloat32Array(
		[0.0, 100.0, 200.0, 340.0, 470.0])
	var after: float = SplineAnchor.where_now(0, anchors, pegged["at"],
		pegged["mix"], pegged["off0"], pegged["off1"],
		PackedFloat32Array([150.0]))
	near(after, before, 0.001,
		"and the vertex has not moved, because its own two points have not")

	# Its own neighbour moving *does* move it — the other half of the claim.
	# A vertex that ignored everything would be as wrong as one that followed
	# everything.
	var near_move: PackedFloat32Array = PackedFloat32Array(
		[0.0, 130.0, 230.0, 300.0, 400.0])
	var pulled: float = SplineAnchor.where_now(0, near_move, pegged["at"],
		pegged["mix"], pegged["off0"], pegged["off1"],
		PackedFloat32Array([150.0]))
	ok(absf(pulled - before) > 5.0,
		"its own neighbour moving carries it (%0.1f to %0.1f)"
			% [before, pulled])
	ok(moved.size() == 5, "the far drag was a real change to compare against")

## Whatever else it does, it must give the old answer when nothing has moved.
func _rest_is_reproduced_exactly() -> void:
	note("nothing that already worked changes shape")
	var anchors: PackedFloat32Array = _anchors()
	var worst: float = 0.0
	for step in 41:
		var at: float = float(step) * 10.0
		var pegged: Dictionary = _peg_one(at, anchors)
		var got: float = SplineAnchor.where_now(0, anchors, pegged["at"],
			pegged["mix"], pegged["off0"], pegged["off1"],
			PackedFloat32Array([at]))
		worst = maxf(worst, absf(got - at))
	ok(worst < 0.001,
		"41 places along the curve, all exact (worst %0.6f)" % worst)

## On the inside of a bend the normals converge. Anything sitting further in
## than the centre of that bend lands past it and comes out the other side:
## the inner line crossing the outer one, the whole bend pinching into a knot.
func _a_bend_does_not_fold_through_itself() -> void:
	note("the inside of a sharp bend cannot turn inside out")
	# A spine bending at radius 40, walked in steps of 4.
	var step: float = 4.0
	var turn: float = step / 40.0
	# 45 units in, on a bend of radius 40 — 5 units past the centre.
	var held: float = SplineAnchor.fold_safe(-45.0, turn, step)
	ok(held > -40.0, "it was pulled back from beyond the centre")
	near(40.0 + held, 40.0 * (1.0 - SplineAnchor.SAFE), 0.5,
		"and stopped short of it rather than exactly on it")

	# Nothing that fits is touched.
	near(SplineAnchor.fold_safe(-10.0, turn, step), -10.0, 0.001,
		"an offset well inside the radius is left alone")
	# A straight run has no centre to fold through.
	near(SplineAnchor.fold_safe(-500.0, 0.0, step), -500.0, 0.001,
		"and a straight spine limits nothing at all")

func _the_outside_of_a_bend_is_left_alone() -> void:
	note("outward offsets are never shortened")
	var step: float = 4.0
	var wrong: int = 0
	for k in 24:
		var turn: float = (float(k) - 12.0) * 0.02
		for off in [5.0, 40.0, 90.0, 200.0]:
			var outward: float = off if turn > 0.0 else -off
			if absf(SplineAnchor.fold_safe(outward, turn, step)
					- outward) > 0.001:
				wrong += 1
	eq(wrong, 0,
		"a bend spreads the outside apart, so there is nothing there to fold")
