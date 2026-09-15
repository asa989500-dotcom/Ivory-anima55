extends "res://tests/test_case.gd"
## The performance model, including the benchmark that now feeds it.
##
## The point of these is not that the numbers are right — a budget cannot be
## right or wrong, only well or badly chosen — but that the arithmetic that
## turns a measurement into a budget holds together, and that a device with
## no measurement at all still gets a sane answer.

func title() -> String:
	return "performance"

var _saved_profile: Dictionary = {}
var _saved_tier: int = 0

func run() -> void:
	_saved_profile = Perf.profile
	_saved_tier = Perf.tier

	_the_benchmark_actually_measures_something()
	_a_profile_survives_being_stored()
	_the_tier_follows_the_measurement()
	_budgets_follow_the_measurement()
	_image_sizes_are_refused_before_they_kill_the_app()
	_the_counters_add_up()

	Perf.profile = _saved_profile
	Perf.tier = _saved_tier

## The benchmark is run for real here — which makes this the one test that
## takes a measurable amount of time, and the one that would notice if a
## Godot release changed what `save_png_to_buffer` costs.
func _the_benchmark_actually_measures_something() -> void:
	note("the benchmark runs and comes back with real times")
	var doc: Dictionary = PerfBench.run()
	ok(int(doc.get("alloc_us", 0)) > 0, "allocating a page took some time")
	ok(int(doc.get("encode_us", 0)) > 0, "so did encoding a tile")
	ok(int(doc.get("decode_us", 0)) > 0, "so did decoding one")
	ok(int(doc.get("loop_us", 0)) > 0, "and so did the arithmetic loop")
	ok(int(doc.get("disk_us", 0)) != 0, "storage was reachable")
	eq(int(doc.get("v", 0)), PerfBench.PROFILE_VERSION, "stamped with a version")
	ok(PerfBench.describe(doc).length() > 40, "and describes itself in words")

	# Nobody should ever wait for this. A tenth of a second is already
	# generous for something that runs before the first frame.
	var spent: float = float(doc.get("alloc_us", 0)) \
		+ float(doc.get("encode_us", 0)) + float(doc.get("decode_us", 0)) \
		+ float(doc.get("blit_us", 0)) + float(doc.get("loop_us", 0))
	ok(spent < 500000.0, "the whole benchmark costs under half a second")

func _a_profile_survives_being_stored() -> void:
	note("a measurement is made once and read back for ever after")
	var doc: Dictionary = {"v": PerfBench.PROFILE_VERSION, "decode_us": 1234,
		"memory_mb": 4096}
	PerfBench.save_profile(doc)
	var back: Dictionary = PerfBench.load_profile()
	eq(int(back.get("decode_us", 0)), 1234, "read back as written")

	# A profile from an older version of the benchmark means something
	# different and must be re-measured rather than misread.
	PerfBench.save_profile({"v": PerfBench.PROFILE_VERSION + 5,
		"decode_us": 9999})
	ok(PerfBench.load_profile().is_empty(), "a stale profile is ignored")
	PerfBench.forget_profile()
	ok(PerfBench.load_profile().is_empty(), "and can be forgotten")

func _the_tier_from(decode_us: int, blit_us: int, memory_mb: int) -> int:
	Perf.profile = {"decode_us": decode_us, "blit_us": blit_us,
		"memory_mb": memory_mb}
	return Perf._tier_from_profile()

func _the_tier_follows_the_measurement() -> void:
	note("the starting tier is measured rather than assumed")
	eq(_the_tier_from(400, 300, 8192), Perf.Tier.HIGH,
		"a fast device with room starts high")
	eq(_the_tier_from(3000, 1000, 8192), Perf.Tier.MEDIUM,
		"a device spending 4 ms a tile starts in the middle")
	eq(_the_tier_from(7000, 1000, 8192), Perf.Tier.LOW,
		"a device spending 8 ms a tile starts low")
	eq(_the_tier_from(400, 300, 1200), Perf.Tier.LOW,
		"a fast device with no memory still starts low")
	eq(_the_tier_from(400, 300, 2048), Perf.Tier.MEDIUM,
		"and a middling amount of memory holds it in the middle")

	Perf.profile = {}
	eq(Perf._tier_from_profile(), Perf.Tier.HIGH,
		"with nothing measured, assume the best and let the frame clock argue")

func _budgets_follow_the_measurement() -> void:
	note("the budgets are arithmetic on the measurement, not opinions")
	Perf.reset_counters()
	Perf.profile = {"decode_us": 4000, "blit_us": 500, "memory_mb": 4096,
		"loop_us": 3000, "disk_us": 20000}
	Perf.tier = Perf.Tier.MEDIUM
	eq(Perf.wake_budget(), 2,
		"at 4 ms a tile and 3 ms to spend, the budget is one tile — floored at two")

	Perf.profile["decode_us"] = 250
	eq(Perf.wake_budget(), 12, "at a quarter of a millisecond, twelve fit")

	Perf.tier = Perf.Tier.HIGH
	ok(Perf.wake_budget() > 1000,
		"a device holding sixty frames a second is not rationed")

	note("folding is done less often where a fold costs more")
	Perf.reset_counters()
	Perf.tier = Perf.Tier.HIGH
	var quick: int = Perf.fold_after()
	for _i in range(12):
		Perf.note("fold", 12000)         # 12 ms a fold
	var slow: int = Perf.fold_after()
	ok(slow > quick, "a slow fold means more dabs between folds")
	between(float(slow), 1600.0, 1900.0, "three times as many, and clamped")

	note("the spill ceiling comes down on slow storage")
	Perf.profile["disk_us"] = 200000     # 2.5 MB/s
	eq(Perf.spill_budget(), 32 * 1024 * 1024, "a slow disk gets a small ceiling")
	Perf.profile["disk_us"] = 5000       # 100 MB/s
	eq(Perf.spill_budget(), 192 * 1024 * 1024, "a fast one gets the full ceiling")

func _image_sizes_are_refused_before_they_kill_the_app() -> void:
	note("an impossible picture is refused rather than allocated")
	Perf.tier = Perf.Tier.HIGH
	Perf.profile = {"memory_mb": 4096}
	ok(Perf.can_hold(Vector2i(2480, 3508)), "A4 at 300 dpi passes on anything")
	not_ok(Perf.can_hold(Vector2i(40000, 40000)), "a mistyped size does not")
	not_ok(Perf.can_hold(Vector2i(0, 100)), "nor does a size of nothing")
	is_null(Perf.make_image(Vector2i(40000, 40000)),
		"and no allocation is attempted for it")
	not_null(Perf.make_image(Vector2i(64, 64)), "an ordinary size is made")

	note("an oversized picture is shrunk with its proportions kept")
	var want: Vector2i = Vector2i(30000, 15000)
	var fitted: Vector2i = Perf.fit_within(want)
	ok(Perf.can_hold(fitted), "the fitted size passes")
	near(float(fitted.x) / float(fitted.y), 2.0, 0.02,
		"and is still twice as wide as it is tall")
	eq(Perf.fit_within(Vector2i(100, 100)), Vector2i(100, 100),
		"a size that already fits is left alone")

func _the_counters_add_up() -> void:
	note("the live counters, which is what makes the numbers arguable")
	Perf.reset_counters()
	eq(Perf.samples("nothing"), 0, "an unmeasured operation has no samples")
	eq(Perf.mean_ms("nothing"), -1.0, "and no mean")
	Perf.note("thing", 1000)
	Perf.note("thing", 3000)
	eq(Perf.samples("thing"), 2, "two samples")
	near(Perf.mean_ms("thing"), 2.0, 0.001, "mean of 1 ms and 3 ms")
	near(Perf.peak_ms("thing"), 3.0, 0.001, "peak of the two")
	Perf.note("thing", -5)
	eq(Perf.samples("thing"), 2, "a negative reading is not a sample")
	ok(Perf.report().length() > 100, "the report has something to say")
	Perf.reset_counters()
