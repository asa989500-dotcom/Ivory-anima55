class_name BSplineRoomDraw
extends RefCounted
## Everything the B-spline room paints: its grid, the artwork behind it, the
## gold frame, the curve and the bones on top.
##
## Lifted out of `bspline_room.gd` at stage 145 to bring that file back under
## the size the project allows. Every function is the one that was there,
## unchanged; `BSplineRoom` keeps a one-line delegate for each, so nothing
## that called them moved.
##
## The one mechanical change: `draw_line` and its neighbours are methods on
## the node, so they are now reached through `host`.

## A measured grid, labelled in the page's own units. The room is for precise
## work, and precise work needs to be able to answer ’ without
## guessing.
static func draw_grid(host: BSplineRoom) -> void:
	# A step that stays legible at any zoom: as the page grows on screen the
	# grid subdivides, and as it shrinks the fine lines drop out rather than
	# collapsing into a grey wash.
	var want: float = 64.0 / maxf(host._zoom, 0.000001)
	var step: float = pow(10.0, floor(log(maxf(want, 1.0)) / log(10.0)))
	for mult in [1.0, 2.0, 5.0, 10.0]:
		if step * mult >= want:
			step *= mult
			break

	var top_left: Vector2 = host.to_page(Vector2.ZERO)
	var bottom_right: Vector2 = host.to_page(host._board.size)
	var f: Font = UiKit.font if UiKit.font != null else ThemeDB.fallback_font

	var x: float = floor(top_left.x / step) * step
	while x <= bottom_right.x:
		var sx: float = host.to_screen(Vector2(x, 0.0)).x
		var bold: bool = absf(fmod(x, step * 5.0)) < 0.001
		host._board.draw_line(Vector2(sx, 0.0), Vector2(sx, host._board.size.y),
			host.GRID_BOLD if bold else host.GRID_INK, 1.0)
		if bold and f != null:
			host._board.draw_string(f, Vector2(sx + 3.0, 14.0), "%d" % int(round(x)),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, host.AXIS_INK)
		x += step

	var y: float = floor(top_left.y / step) * step
	while y <= bottom_right.y:
		var sy: float = host.to_screen(Vector2(0.0, y)).y
		var bold_y: bool = absf(fmod(y, step * 5.0)) < 0.001
		host._board.draw_line(Vector2(0.0, sy), Vector2(host._board.size.x, sy),
			host.GRID_BOLD if bold_y else host.GRID_INK, 1.0)
		if bold_y and f != null:
			host._board.draw_string(f, Vector2(4.0, sy - 3.0), "%d" % int(round(y)),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, host.AXIS_INK)
		y += step

	# The origin, drawn as axes so X and Y are readable directions rather than
	# a wall of squares.
	var o: Vector2 = host.to_screen(Vector2.ZERO)
	host._board.draw_line(Vector2(0.0, o.y), Vector2(host._board.size.x, o.y), host.AXIS_INK, 1.6)
	host._board.draw_line(Vector2(o.x, 0.0), Vector2(o.x, host._board.size.y), host.AXIS_INK, 1.6)
	if f != null:
		host._board.draw_string(f, o + Vector2(6.0, -6.0), "0,0",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, host.AXIS_INK)
		host._board.draw_string(f, Vector2(host._board.size.x - 22.0, o.y - 6.0), "X",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, host.AXIS_INK)
		host._board.draw_string(f, Vector2(o.x + 6.0, 22.0), "Y",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, host.AXIS_INK)

## The drawing, bent by whatever the rig is currently doing to it.
##
## This is the fix for ’.
##
## Everything was already right except the last step. `_pose` computes the
## deformed vertex positions into `_now` on every drag, correctly, and
## `_push_mesh` builds a mesh from them — but `_push_mesh` begins with
## `if <that node> == null: return`, and **the node it tested was never
## assigned anywhere in the file**. It was declared, read in two places, and
## never given a value. So every posed vertex was computed and thrown away, and this
## function drew the flat rest texture over the top of nothing.
##
## Drawing the mesh directly is better than resurrecting that node. The
## vertices live in page coordinates and the page-to-screen map is a pure
## scale and offset, so one `Transform2D` carries them — no second node to
## keep in step with the pan, the zoom and the board's own redraws, and the
## rig can never again be a frame behind what the finger is doing.
static func draw_art(host: BSplineRoom) -> void:
	if host._art_tex == null:
		return
	if host._bent != null:
		host._board.draw_mesh(host._bent, host._art_tex,
			Transform2D(0.0, Vector2(host._zoom, host._zoom), 0.0, host._pan))
		return
	# No rig yet, or a drawing too small to mesh: the plain picture, which is
	# exactly what it looks like undeformed anyway.
	var at: Vector2 = host.to_screen(Vector2(host._ink_rect.position))
	var box: Rect2 = Rect2(at, Vector2(host._ink_rect.size) * host._zoom)
	host._board.draw_texture_rect(host._art_tex, box, false, Color(1, 1, 1, 0.92))

## The gold frame is the page itself — what the canvas will actually keep.
## Anything outside it exists here and nowhere else.
static func draw_frame(host: BSplineRoom) -> void:
	var box: Rect2 = Rect2(host.to_screen(Vector2(host.page.position)),
		Vector2(host.page.size) * host._zoom)
	host._board.draw_rect(box, Color(host.GOLD.r, host.GOLD.g, host.GOLD.b, 0.10), true)
	host._board.draw_rect(box, host.GOLD, false, 2.4)
	var corner: float = minf(box.size.x, box.size.y) * 0.06
	for c in [[box.position, Vector2(1, 1)],
			[Vector2(box.end.x, box.position.y), Vector2(-1, 1)],
			[Vector2(box.position.x, box.end.y), Vector2(1, -1)],
			[box.end, Vector2(-1, -1)]]:
		var p: Vector2 = c[0]
		var d: Vector2 = c[1]
		host._board.draw_line(p, p + Vector2(corner * d.x, 0.0), host.GOLD, 4.0)
		host._board.draw_line(p, p + Vector2(0.0, corner * d.y), host.GOLD, 4.0)

static func draw_curve_legacy(host: BSplineRoom) -> void:
	if host.spline == null or host.spline.size() == 0:
		return
	# The control polygon, faint: it is the handle, not the shape.
	if host.spline.size() > 1:
		for i in range(1, host.spline.size()):
			host._board.draw_line(host.to_screen(host.spline.points[i - 1]),
				host.to_screen(host.spline.points[i]),
				Color(host.IVORY.r, host.IVORY.g, host.IVORY.b, 0.22), 1.0)

	if host.spline.ready():
		var walk: PackedVector2Array = host.spline.walk(maxi(host.spline.size() * 24, 48))
		var line: PackedVector2Array = PackedVector2Array()
		for p in walk:
			line.append(host.to_screen(p))
		if line.size() > 1:
			host._board.draw_polyline(line, Color(0.06, 0.20, 0.25, 0.60), 5.0)
			host._board.draw_polyline(line, host.GOLD, 2.6)

	for i in host.spline.size():
		var s: Vector2 = host.to_screen(host.spline.points[i])
		var corner: bool = host.spline.sharpness(i) > 0
		host._board.draw_circle(s + Vector2(1, 2), 9.0, Color(0, 0, 0, 0.35))
		if corner:
			# A corner point is square, because what it does to the curve is
			# categorically different from what a smooth one does.
			host._board.draw_rect(Rect2(s - Vector2(8, 8), Vector2(16, 16)), host.IVORY, true)
			host._board.draw_rect(Rect2(s - Vector2(8, 8), Vector2(16, 16)),
				Color("#8A7C58"), false, 2.0)
		else:
			host._board.draw_circle(s, 8.0, host.IVORY)
			host._board.draw_arc(s, 8.0, 0.0, TAU, 20, Color("#8A7C58"), 2.0)
		if i == host._grab:
			host._board.draw_arc(s, 13.0, 0.0, TAU, 24, host.GOLD, 2.0)

static func draw_bones(host: BSplineRoom) -> void:
	if host._bone_drawing:
		var from: Vector2 = host.to_screen(host._bone_from)
		var to: Vector2 = host._board.get_local_mouse_position()
		if not host._touches.is_empty():
			to = host._touches[host._touches.keys()[0]]
		var ok: bool = host.bone_fits(host._bone_from, host.to_page(to))
		host._board.draw_line(from, to,
			host.BONE_INK if ok else Color(0.85, 0.35, 0.30, 0.85), 3.0)

	# Bodies first, every joint afterwards.
	#
	# A chained bone begins exactly where its parent ends, so drawing each
	# bone complete put two markers on the same spot — the child’s end, one on top of the other, reading as two joints where
	# the skeleton has one. Two limbs joined at the elbow should show *an
	# elbow*, and it should be a single thing you can take hold of.
	#
	# Splitting the drawing in two fixes it without touching the rig: the
	# spindles are laid down, then the joints are gathered, coincident ones
	# folded together, and each surviving place marked once.
	for i in host.bones.size():
		var b: BoneRig.Bone = host.bones[i] as BoneRig.Bone
		host._draw_spindle(host.to_screen(b.a), host.to_screen(b.b))
	host._draw_joints()

## Every joint in the skeleton, each place marked exactly once.
##
## Coincidence is measured on screen rather than on the page, because that is
## where the two markers would have overlapped: a gap the eye cannot resolve
## is a gap that should read as one joint however far the room is zoomed in.
static func draw_joints(host: BSplineRoom) -> void:
	var spots: Array = []
	var near: float = maxf(UiKit.s(9.0), 6.0)
	for i in host.bones.size():
		var b: BoneRig.Bone = host.bones[i] as BoneRig.Bone
		for at in [host.to_screen(b.a), host.to_screen(b.b)]:
			var found: bool = false
			for k in spots.size():
				if (spots[k] as Vector2).distance_to(at) <= near:
					found = true
					break
			if not found:
				spots.append(at)
	for k in spots.size():
		host._draw_joint(spots[k])

## Drawn as a real bone shape rather than a line: a tapered spindle with a
## joint at each end, so which way it runs and where it pivots are both
## readable without a legend.
## The tapered spindle, and nothing else. Joints are drawn separately so that
## two bones meeting at a place put one marker there rather than two.
static func draw_spindle(host: BSplineRoom, a: Vector2, b: Vector2) -> void:
	var dir: Vector2 = b - a
	var span: float = dir.length()
	if span < 1.0:
		return
	dir = dir / span
	var side: Vector2 = Vector2(-dir.y, dir.x)
	var wide: float = clampf(span * 0.14, 4.0, 15.0)
	var neck: Vector2 = a + dir * (span * 0.22)

	var body: PackedVector2Array = PackedVector2Array([
		a, neck + side * wide, b, neck - side * wide])
	host._board.draw_colored_polygon(body, Color(host.BONE_INK.r, host.BONE_INK.g, host.BONE_INK.b, 0.42))
	host._board.draw_polyline(PackedVector2Array([a, neck + side * wide, b,
		neck - side * wide, a]), host.BONE_INK, 1.8)

## One joint, drawn per *place* rather than per bone end, so two bones meeting
## put one marker there.
##
## One shape, because there is one kind of joint. The square used to mean a
## right-angle stop and there is no such thing here any more — a legend with
## one entry in it is not a legend.
static func draw_joint(host: BSplineRoom, at: Vector2) -> void:
	var wide: float = maxf(UiKit.s(9.0), 6.0)
	host._board.draw_circle(at, wide * 0.78, host.IVORY)
	host._board.draw_arc(at, wide * 0.78, 0.0, TAU, 20, Color("#8A7C58"), 2.0)
