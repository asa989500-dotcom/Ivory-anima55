extends "res://tests/test_case.gd"
## The clip's clock, and the curve the B-Spline room is built on.
##
## The frame-rate unit is the feature with the most arithmetic behind it and
## the least visible failure mode: get it wrong and a scene simply plays at
## the wrong speed, which nobody notices until it is exported.

func title() -> String:
	return "clip clock and curves"

func run() -> void:
	_a_plain_clip_runs_at_its_own_rate()
	_a_unit_stretches_time_in_place()
	_units_do_not_overlap()
	_a_curve_passes_through_its_ends()
	_a_curve_walks_smoothly()

func _clip(fps: int) -> Anim.Clip:
	var c: Anim.Clip = Anim.Clip.new()
	c.fps = fps
	return c

func _a_plain_clip_runs_at_its_own_rate() -> void:
	note("with no units, a frame is one over the frame rate")
	var c: Anim.Clip = _clip(24)
	near(c.time_of(0), 0.0, 0.0001, "the scene starts at zero")
	near(c.time_of(24), 1.0, 0.0001, "twenty-four frames is one second")
	near(c.time_of(12), 0.5, 0.0001, "and twelve is half of it")
	near(c.span_seconds(0, 23), 1.0, 0.0001, "a whole second, counted inclusively")

## The rule you gave, in one test: six frames at two a second is three
## seconds, and *what follows starts that much later* — the unit stretches
## time in place rather than lengthening the band.
func _a_unit_stretches_time_in_place() -> void:
	note("six frames at two a second is three seconds")
	var c: Anim.Clip = _clip(24)
	c.add_unit(0, 5, 2)
	near(c.span_seconds(0, 5), 3.0, 0.0001, "the unit itself lasts three seconds")
	eq(c.rate_at(3), 2, "and runs at two frames a second inside it")
	eq(c.rate_at(9), 24, "while the scene outside it is unchanged")

	note("and everything after it starts three seconds later")
	var plain: Anim.Clip = _clip(24)
	near(c.time_of(6) - plain.time_of(6), 3.0 - 6.0 / 24.0, 0.0001,
		"frame six is later by exactly what the unit added")
	near(c.time_of(30) - plain.time_of(30), c.time_of(6) - plain.time_of(6),
		0.0001, "and every later frame is shifted by the same amount, no more")

	note("a unit may also speed a stretch up")
	var fast: Anim.Clip = _clip(12)
	fast.add_unit(0, 11, 60)
	near(fast.span_seconds(0, 11), 12.0 / 60.0, 0.0001,
		"twelve frames at sixty a second is a fifth of a second")

	note("the rate a unit may hold is bounded at both ends")
	var bounded: Anim.Clip = _clip(24)
	var one: Anim.Unit = bounded.add_unit(0, 3, 900)
	eq(one.fps, Anim.MAX_UNIT_FPS, "a mistyped rate is clamped, not obeyed")
	var slow: Anim.Unit = bounded.add_unit(10, 13, 0)
	eq(slow.fps, Anim.MIN_UNIT_FPS, "and so is a rate of nothing")

func _units_do_not_overlap() -> void:
	note("a unit knows which frames belong to it")
	var c: Anim.Clip = _clip(24)
	var a: Anim.Unit = c.add_unit(4, 9, 6)
	eq(a.count(), 6, "four to nine inclusive is six frames")
	ok(a.holds(4) and a.holds(9), "both ends belong to it")
	not_ok(a.holds(3) or a.holds(10), "and neither neighbour does")
	eq(c.unit_at(7), a, "a frame inside it finds it")
	is_null(c.unit_at(11), "and a frame outside finds nothing")
	eq(c.segment_end(7), 10, "the rate stops being this rate at ten")

func _a_curve_passes_through_its_ends() -> void:
	note("a spline starts where its first point is and ends at its last")
	var s: BSpline = BSpline.new()
	for p in [Vector2(0, 0), Vector2(50, -80), Vector2(150, 60),
			Vector2(220, 0)]:
		s.add_point(p)
	ok(s.ready(), "four points is enough to be a curve")
	eq(s.size(), 4, "and it kept all four")
	var start: Vector2 = s.at(0.0)
	var finish: Vector2 = s.at(s.span_max())
	near(start.distance_to(Vector2(0, 0)), 0.0, 0.75,
		"the curve begins at the first point")
	near(finish.distance_to(Vector2(220, 0)), 0.0, 0.75,
		"and ends at the last")

	note("moving a point moves the curve and nothing else")
	var before: Vector2 = s.at(s.span_max() * 0.1)
	s.move_point(3, Vector2(400, 0))
	var after: Vector2 = s.at(s.span_max() * 0.1)
	near(before.distance_to(after), 0.0, 40.0,
		"the far end of the curve barely notices")
	near(s.at(s.span_max()).distance_to(Vector2(400, 0)), 0.0, 0.75,
		"while the end it belongs to follows exactly")

func _a_curve_walks_smoothly() -> void:
	note("walking a curve gives evenly spaced points and no jumps")
	var s: BSpline = BSpline.new()
	for p in [Vector2(0, 0), Vector2(60, 90), Vector2(160, -40),
			Vector2(260, 40), Vector2(320, 0)]:
		s.add_point(p)
	var walk: PackedVector2Array = s.walk(64)
	ok(walk.size() >= 32, "the walk produced points")
	var longest: float = 0.0
	var shortest: float = 1000000.0
	for i in range(1, walk.size()):
		var step: float = walk[i].distance_to(walk[i - 1])
		longest = maxf(longest, step)
		shortest = minf(shortest, step)
	ok(longest < 60.0, "no single step jumps across the drawing")
	ok(shortest >= 0.0, "and none of them goes backwards")

	note("removing a point leaves a curve behind rather than a crash")
	s.remove_point(2)
	eq(s.size(), 4, "one fewer point")
	ok(s.ready(), "and still a curve")
	s.remove_point(0)
	s.remove_point(0)
	s.remove_point(0)
	not_ok(s.ready(), "one point is not a curve")
	not_null(s.at(0.0), "and asking for a position still answers something")
