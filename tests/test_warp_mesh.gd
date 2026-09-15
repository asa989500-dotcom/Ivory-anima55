extends "res://tests/test_case.gd"
## The warp mesh, and the two faults that tore drawings apart.
##
## Both were invisible in a screenshot of a simple shape and obvious on a
## finished drawing, which is the worst combination there is: the thing that
## gets tested by hand is the thing that never fails.
##
## Neither needs a screen. `Image` is a plain datatype and the mesh functions
## are pure, so a hairline stroke can be drawn into an image here, put through
## the same map the warp uses, and the answer checked — which is the only
## honest way to know that a stroke one pixel wide is still there.

func title() -> String:
	return "warp mesh"

func run() -> void:
	_a_hairline_is_not_lost()
	_a_lone_dot_is_not_lost()
	_blank_paper_is_still_blank()
	_a_loose_piece_is_carried_not_abandoned()

## One pixel wide, on a canvas big enough that a cell covers a thousand.
##
## The exact case that broke: shrinking this to a 34-cell map with a single
## bilinear resize samples about one pixel in thirty, and a line one pixel
## wide falls between the samples. Every cell along it came back empty, so no
## triangles were built there, so the stroke was not in the mesh — and what is
## not in the mesh is not drawn.
func _a_hairline_is_not_lost() -> void:
	note("a one-pixel stroke still puts cells on the map")
	var art: Image = Image.create_empty(1024, 1024, false, Image.FORMAT_RGBA8)
	art.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in 1024:
		art.set_pixel(512, y, Color(0.05, 0.04, 0.03, 1.0))

	var map: PackedByteArray = WarpMesh.ink_map(art, 34, 34, 0.004)
	eq(map.size(), 34 * 34, "the map is the size that was asked for")
	var lit: int = 0
	for v in map:
		if v != 0:
			lit += 1
	# A vertical line down the middle should light roughly one column of 34.
	# Anything near nought is the old fault; anything near the whole map
	# would mean the floor had been dropped so far that blank paper counts.
	ok(lit >= 20, "the stroke is found down the map, not lost (%d cells)" % lit)
	ok(lit <= 34 * 8, "and it has not smeared across the whole map (%d)" % lit)

## A single dot, which is the hardest thing on the page to keep.
func _a_lone_dot_is_not_lost() -> void:
	note("a dot two pixels across survives the reduction")
	var art: Image = Image.create_empty(800, 800, false, Image.FORMAT_RGBA8)
	art.fill(Color(0.0, 0.0, 0.0, 0.0))
	for dy in 2:
		for dx in 2:
			art.set_pixel(400 + dx, 120 + dy, Color(0.1, 0.1, 0.1, 1.0))
	var map: PackedByteArray = WarpMesh.ink_map(art, 40, 40, 0.004)
	var lit: int = 0
	for v in map:
		if v != 0:
			lit += 1
	ok(lit >= 1, "the dot put at least one cell on the map")

## The other direction. A floor low enough to catch a hairline must not be so
## low that an empty layer meshes edge to edge — that would cost every warp on
## a mostly-blank page a full grid of triangles solved to move nothing.
func _blank_paper_is_still_blank() -> void:
	note("an empty patch does not fill the map by accident")
	var art: Image = Image.create_empty(600, 600, false, Image.FORMAT_RGBA8)
	art.fill(Color(0.0, 0.0, 0.0, 0.0))
	# A small blot in one corner, so the image is not wholly empty — a wholly
	# empty one is meshed everywhere on purpose, and would prove nothing.
	for y in range(4, 20):
		for x in range(4, 20):
			art.set_pixel(x, y, Color(0.0, 0.0, 0.0, 1.0))
	var map: PackedByteArray = WarpMesh.ink_map(art, 30, 30, 0.004)
	var lit: int = 0
	for v in map:
		if v != 0:
			lit += 1
	ok(float(lit) < 30.0 * 30.0 / 3.0,
		"most of a nearly-blank page stayed off the map (%d of 900)" % lit)

## A piece of drawing with no path to the pin.
##
## Strokes that do not quite touch, a dot over an i, an eye inside a face —
## each is its own island in a mesh built on ink. They used to keep the
## distance `FAR`, which weighed nothing, which meant the warp handed the
## vertex back unmoved: the face bent and the eyes stayed behind.
func _a_loose_piece_is_carried_not_abandoned() -> void:
	note("ink no path reaches is carried by the pins near it")
	var rest: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(10.0, 0.0), Vector2(20.0, 0.0),
		Vector2(400.0, 0.0)])
	var far: PackedFloat32Array = PackedFloat32Array([0.0, 10.0, 20.0,
		WarpMesh.FAR])

	WarpMesh.bridge_islands(far, Vector2.ZERO, rest, 240.0)
	ok(far[3] < WarpMesh.FAR, "the loose piece has a distance at last")
	near(far[3], 640.0, 0.01,
		"and it is the straight line plus the cost of the crossing")
	near(far[2], 20.0, 0.01, "connected ink was not touched")
	ok(far[3] > far[2],
		"ink you can walk to still outranks ink you have to jump to")
