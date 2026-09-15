class_name CanvasViewDraw
extends RefCounted
## The canvas overlay: the rig on the active layer, the loupe, the marks and
## the floating gizmos.
##
## Lifted out of `canvas_view.gd` at stage 145. That file had grown two
## hundred lines past what the project allows and this is the part with no
## bearing on input or on the document — it only paints what the rest has
## already decided. `CanvasView` keeps a delegate for each function.
##
## Two mechanical changes came with the move, both because these were methods
## on a node and are now not: `draw_line` and friends go through `host`, and
## so does `size`, which is the Control's own.

static func draw_layer_rig(host: CanvasView) -> void:
	CanvasMarks.draw_layer_rig(host)

static func draw_loupe(host: CanvasView) -> void:
	if not host._picking:
		return
	var side: float = UiKit.s(112.0)
	var lift: float = UiKit.s(96.0)
	var centre: Vector2 = Vector2(
		clampf(host._pick_screen.x, side * 0.5 + 4.0, maxf(host.size.x - side * 0.5 - 4.0, side)),
		clampf(host._pick_screen.y - lift, side * 0.5 + 4.0, maxf(host.size.y - side * 0.5 - 4.0, side)))
	var box: Rect2 = Rect2(centre - Vector2(side, side) * 0.5, Vector2(side, side))

	host._loupe.draw_rect(box.grow(UiKit.s(3.0)), Color(1.0, 1.0, 1.0, 0.95), true)
	if host._pick_tex != null:
		host._loupe.draw_texture_rect(host._pick_tex, box, false)
	else:
		host._loupe.draw_rect(box, Color(0.98, 0.97, 0.95, 1.0), true)

	var cell: float = side / 15.0
	var mid: Rect2 = Rect2(centre - Vector2(cell, cell) * 0.5, Vector2(cell, cell))
	host._loupe.draw_rect(mid, Color(0.0, 0.0, 0.0, 0.85), false, UiKit.s(1.5))
	host._loupe.draw_rect(mid.grow(UiKit.s(1.5)), Color(1.0, 1.0, 1.0, 0.85), false, UiKit.s(1.0))

	var chip: Rect2 = Rect2(box.position.x, box.position.y + box.size.y + UiKit.s(6.0),
		box.size.x, UiKit.s(24.0))
	host._loupe.draw_rect(chip, Color(0.11, 0.11, 0.13, 0.92), true)
	host._loupe.draw_rect(Rect2(chip.position + Vector2(UiKit.s(4.0), UiKit.s(4.0)),
		Vector2(UiKit.s(16.0), UiKit.s(16.0))), host._pick_color, true)
	var f: Font = ThemeDB.fallback_font
	if f != null:
		host._loupe.draw_string(f, chip.position + Vector2(UiKit.s(26.0), UiKit.s(17.0)),
			"#" + host._pick_color.to_html(false).to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(UiKit.s(12.0)), Color(0.85, 0.83, 0.78))
	host._loupe.draw_line(Vector2(centre.x, box.position.y + box.size.y),
		host._pick_screen, Color(1.0, 1.0, 1.0, 0.5), UiKit.s(1.5))

static func draw_overlay(host: CanvasView) -> void:
	ComicBoard.draw(host)
	host._draw_layer_rig()
	# Asked of the layers rather than of a remembered number, so the box is
	# on screen whenever a text layer is, and gone whenever one is not.
	if host.text_layer() != null:
		host.draw_text_box()
	MoveTool.draw_on(host)
	if host.symmetry_enabled:
		var c_screen: Vector2 = host.canvas_to_screen(host.symmetry_center)
		var axis_len: float = maxf(host.size.x, host.size.y) * 0.8
		var thick: float = maxf(2.0, 2.0 * App.ui_scale
			/ maxf(host.view_zoom, 0.001))
		# One line for every *pair* of repeats, not one line however many
		# ways the stroke goes. Six-way symmetry is three lines through the
		# centre, like a snowflake — which is what the drawing does and what
		# the guide should have been showing all along. An odd count has no
		# opposite for its last arm, so it gets a spoke rather than a line.
		var arms: int = maxi(host.symmetry_count, 2)
		var pairs: int = int(float(arms) / 2.0) if arms % 2 == 0 else arms
		var span: float = PI if arms % 2 == 0 else TAU
		for i in pairs:
			var a: float = host.symmetry_angle + span * float(i) / float(pairs)
			var d: Vector2 = Vector2(cos(a), sin(a))
			var lead: bool = i == 0
			host.overlay.draw_line(c_screen - d * (axis_len if arms % 2 == 0 else 0.0),
				c_screen + d * axis_len,
				Color(0.3, 0.75, 1.0, 0.82 if lead else 0.4), thick)
		var dir: Vector2 = Vector2(cos(host.symmetry_angle), sin(host.symmetry_angle))
		var handle: Vector2 = c_screen + dir * (host.SYM_HANDLE_PX * App.ui_scale)
		# Drawn at the host.size it is grabbed at, so what the eye aims for and
		# what the finger catches are the same thing.
		host.overlay.draw_circle(c_screen, 13.0 * App.ui_scale,
			Color(1.0, 0.8, 0.25, 0.95))
		host.overlay.draw_circle(handle, 12.0 * App.ui_scale,
			Color(0.4, 0.9, 1.0, 0.95))
		host.overlay.draw_arc(handle, 12.0 * App.ui_scale, 0.0, TAU, 20,
			Color(0.05, 0.1, 0.16, 0.8), 2.0)

	var accent: Color = Color(0.15, 0.45, 0.9, 0.9)
	var w: float = 1.5 / maxf(host.view_zoom, 0.0001)

	if host._shape_active and App.current_tool == App.Tool.FILL:
		var shape_rect: Rect2 = Rect2(host._shape_a, host._shape_b - host._shape_a).abs()
		host.overlay.draw_rect(shape_rect, App.fill_ink, false, w * 1.5)
	elif host._shape_active and App.shape_mode != App.Shape.FREE \
			and App.shape_mode != App.Shape.POLYLINE:
		var pts: PackedVector2Array = host._shape_points()
		if pts.size() >= 2:
			host.overlay.draw_polyline(pts, accent, w)
	if App.shape_mode == App.Shape.POLYLINE and host.poly_points.size() > 0:
		if host.poly_points.size() >= 2:
			host.overlay.draw_polyline(host._smooth_polyline(host.poly_points), accent, w)
		var point_radius: float = 6.0 / maxf(host.view_zoom, 0.0001)
		for point in host.poly_points:
			host.overlay.draw_circle(point, point_radius, Color(1.0, 1.0, 1.0, 0.95))
			host.overlay.draw_arc(point, point_radius, 0.0, TAU, 20, accent, w)

	# The live end of a chain, so you can see where the next line will start
	# from before you commit to drawing it. Without this the tool is guesswork
	# after the first line — you know a chain is running, but not from which
	# corner, and the two ends of a short segment are a thumb's width apart.
	if App.shape_mode == App.Shape.CHAIN and host.chain_live \
			and App.current_tool == App.Tool.SHAPE:
		# The lines already laid, drawn faintly — so it is visible what a new
		# line may catch onto, before you commit to reaching for it.
		var i: int = 0
		while i + 1 < host.chain_marks.size():
			host.overlay.draw_line(host.chain_marks[i], host.chain_marks[i + 1],
				Color(accent.r, accent.g, accent.b, 0.28), w * 0.8)
			i += 2
		var hold: float = 7.0 / maxf(host.view_zoom, 0.0001)
		host.overlay.draw_circle(host.chain_anchor, hold, Color(1.0, 1.0, 1.0, 0.92))
		host.overlay.draw_arc(host.chain_anchor, hold, 0.0, TAU, 22, accent, w * 1.4)

	host._draw_marks(w)
	host._draw_floating(w)

static func draw_marks(host: CanvasView, w: float) -> void:
	if host._mark_points.size() < 2:
		return
	var mark: Color = Color(0.1, 0.1, 0.12, 0.9)
	var shape: int = App.select_shape
	var pts: PackedVector2Array = PackedVector2Array()
	if shape == App.SelectShape.RECT or shape == App.SelectShape.ELLIPSE:
		pts = host._outline(shape == App.SelectShape.RECT, shape == App.SelectShape.ELLIPSE,
			false, false, host._mark_points[0], host._mark_points[1], PackedVector2Array())
	else:
		pts = host._mark_points.duplicate()
		if pts.size() >= 3:
			pts.append(pts[0])
	if pts.size() >= 2:
		host.overlay.draw_polyline(pts, mark, w * 1.4)
		host.overlay.draw_polyline(pts, Color(1.0, 1.0, 1.0, 0.85), w * 0.6)
	if shape == App.SelectShape.POLY:
		var r: float = 5.0 / maxf(host.view_zoom, 0.0001)
		for p in host._mark_points:
			host.overlay.draw_circle(p, r, Color(1.0, 1.0, 1.0, 0.95))
			host.overlay.draw_arc(p, r, 0.0, TAU, 16, mark, w)

static func draw_floating(host: CanvasView, w: float) -> void:
	if not host.sel_active or host._sel_tex == null:
		return
	var c: Array = host._sel_corners()
	var ring: PackedVector2Array = PackedVector2Array()
	for corner in c:
		ring.append(corner)
	ring.append(c[0])
	host.overlay.draw_polyline(ring, Color(0.1, 0.1, 0.12, 0.9), w * 1.4)
	host.overlay.draw_polyline(ring, Color(1.0, 1.0, 1.0, 0.9), w * 0.6)

	var hr: float = 9.0 / maxf(host.view_zoom, 0.0001)
	for corner in c:
		host.overlay.draw_circle(corner, hr, Color(1.0, 1.0, 1.0, 0.97))
		host.overlay.draw_arc(corner, hr, 0.0, TAU, 20, UiKit.ACCENT, w * 1.6)

	var rot: Vector2 = host._rotate_handle()
	var top: Vector2 = ((c[0] as Vector2) + (c[1] as Vector2)) * 0.5
	host.overlay.draw_line(top, rot, Color(1.0, 1.0, 1.0, 0.8), w)
	host.overlay.draw_circle(rot, hr, Color(1.0, 1.0, 1.0, 0.97))
	host.overlay.draw_arc(rot, hr, 0.0, TAU, 20, UiKit.ACCENT, w * 1.6)
