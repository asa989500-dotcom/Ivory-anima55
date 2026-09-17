extends "res://tests/test_case.gd"
## The fill bucket, run for real against drawn shapes.
##
## This case exists because of what it found. Every static checker in `tools/`
## passed on a version of `flood_fill.gd` in which one line sat outside its
## `else`, marking the entire coarse map as linework — so the bucket returned
## "nothing is enclosed" on every tap on every drawing and painted nothing,
## ever. Four checkers read that file and none of them could see it, because
## it is not a spelling mistake or a missing name; it is a correct sentence
## that says the wrong thing.
##
## The only thing that catches a bug like that is running the code, so this
## draws real circles into a real image and taps them.

func title() -> String:
	return "flood fill"

## Stands in for the paint surface. The fill only ever asks it for a region.
class Sheet:
	extends RefCounted
	var img: Image

	func _init(side: int) -> void:
		img = Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.0, 0.0, 0.0, 0.0))

	## Anything outside the sheet reads as empty canvas, which is what the
	## real surface does with a region past the edge of what is drawn.
	func read_region(box: Rect2i) -> Image:
		var out: Image = Image.create_empty(box.size.x, box.size.y, false,
			Image.FORMAT_RGBA8)
		out.fill(Color(0.0, 0.0, 0.0, 0.0))
		var here: Rect2i = Rect2i(Vector2i.ZERO, img.get_size())
		var shared: Rect2i = here.intersection(box)
		if shared.size.x > 0 and shared.size.y > 0:
			out.blit_rect(img, shared, shared.position - box.position)
		return out

	## A ring of ink, optionally with a gap cut out of it.
	func ring(centre: Vector2i, radius: float, thickness: int,
			gap_degrees: float) -> void:
		var steps: int = 3000
		for i in range(steps):
			var degrees: float = 360.0 * float(i) / float(steps)
			if degrees < gap_degrees:
				continue
			var a: float = deg_to_rad(degrees)
			for t in range(-thickness, thickness + 1):
				var x: int = int(round(float(centre.x)
					+ (radius + float(t)) * cos(a)))
				var y: int = int(round(float(centre.y)
					+ (radius + float(t)) * sin(a)))
				if x >= 0 and y >= 0 and x < img.get_width() \
						and y < img.get_height():
					img.set_pixel(x, y, Color(0.06, 0.06, 0.08, 1.0))

func run() -> void:
	# The tests run without the autoloaded settings object, so the two dials
	# the fill reads are told what to be.
	FloodFill.tolerance_hint = 56
	FloodFill.creep_hint = 2

	_fills_a_closed_shape()
	_bridges_a_hairline_gap()
	_refuses_open_canvas()
	_refuses_a_shape_broken_wide_open()

	FloodFill.tolerance_hint = -1
	FloodFill.creep_hint = -1

func _tap(sheet: Sheet, at: Vector2) -> Variant:
	return FloodFill.run(sheet, at, Color(0.8, 0.2, 0.2, 1.0),
		Vector2(400.0, 400.0), 1.0, Vector2(400.0, 400.0))

func _fills_a_closed_shape() -> void:
	note("a closed circle fills, and the fill stays inside it")
	var sheet: Sheet = Sheet.new(512)
	sheet.ring(Vector2i(256, 256), 120.0, 1, 0.0)
	var got: Variant = _tap(sheet, Vector2(256.0, 256.0))
	not_null(got, "tapping inside a closed circle fills it")
	if got == null:
		return
	var result: Dictionary = got
	var painted: Image = result["image"]
	not_null(painted, "and hands back a picture")
	eq(String(FloodFill.last.get("outcome", "")), "filled",
		"and says so in the diagnosis")

	# A circle of radius 120 holds about 45,000 pixels. Far fewer means the
	# fill stopped short; far more means it escaped the outline — which is
	# the "it overruns the curve" complaint, now measurable.
	var pixels: int = int(FloodFill.last.get("pixels", 0))
	between(float(pixels), 38000.0, 52000.0,
		"the area filled is the area of the circle")

	# A closed shape should need no bridging at all.
	eq(int(FloodFill.last.get("bridge", -1)), 0,
		"a closed shape is filled without bridging anything")

func _bridges_a_hairline_gap() -> void:
	note("a hair-thin gap is closed by the app, with no slider")
	var sheet: Sheet = Sheet.new(512)
	sheet.ring(Vector2i(256, 256), 120.0, 1, 1.2)   # a gap a few pixels wide
	var got: Variant = _tap(sheet, Vector2(256.0, 256.0))
	not_null(got, "a circle with a hairline gap still fills")
	between(float(FloodFill.last.get("pixels", 0)), 38000.0, 52000.0,
		"and fills the shape rather than the whole page")

func _refuses_open_canvas() -> void:
	note("tapping open space does nothing at all")
	var sheet: Sheet = Sheet.new(512)
	var got: Variant = _tap(sheet, Vector2(256.0, 256.0))
	is_null(got, "an empty canvas is not filled")
	eq(String(FloodFill.last.get("outcome", "")), "open",
		"and the reason is recorded")

func _refuses_a_shape_broken_wide_open() -> void:
	note("a shape with a real hole in it is not guessed at")
	var sheet: Sheet = Sheet.new(512)
	sheet.ring(Vector2i(256, 256), 120.0, 1, 40.0)  # a quarter of it missing
	var got: Variant = _tap(sheet, Vector2(256.0, 256.0))
	is_null(got, "a wide-open shape is left alone")
