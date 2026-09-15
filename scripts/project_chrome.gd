class_name ProjectChrome
extends Node2D
## Everything drawn around a project rather than inside it.
##
## It sits above every sheet so a frame is never clipped by the paper it
## surrounds, and it draws in world space with widths divided by the zoom,
## so a hairline stays a hairline whether the workspace is at 8% or 800%.

var manager: ProjectManager = null
var zoom: float = 1.0

var _door: Texture2D = null

## Set by the player while a camera track is driving the view. The frame is
## drawn from these rather than from the view's own transform, so what you
## see marked is where the camera is keyed to be — not merely where you have
## panned to.
var camera_on: bool = false
var camera_rect: Rect2 = Rect2()
var camera_angle: float = 0.0

## True while the camera frame is being handled directly on the canvas, so
## its corners are drawn as grips rather than as marks.
var camera_editing: bool = false

func _ready() -> void:
	# High enough to sit above every sheet, low enough to stay under the
	# interface, which lives in a layer of its own.
	z_index = 50
	var path: String = "res://assets/icons/save_close.png"
	if ResourceLoader.exists(path):
		_door = load(path)

func refresh(view_zoom: float) -> void:
	zoom = maxf(view_zoom, 0.0001)
	queue_redraw()

func _draw() -> void:
	if manager == null:
		return
	var f: Font = ThemeDB.fallback_font
	for p in manager.projects:
		if manager.is_hidden(p):
			continue
		if manager.render_rect.size.x > 0.0 and not manager.render_rect.intersects(p.bounds()):
			continue
		_draw_project(p, f)

func _draw_project(p: ProjectManager.Project, f: Font) -> void:
	var b: Rect2 = p.bounds()
	var thin: float = 1.0 / zoom

	# --- the page gaps of a comic get their own outline, so a spread reads
	# --- as several sheets rather than one wide one
	for i in p.pages:
		var r: Rect2 = p.page_rect(i)
		draw_rect(r, p.frame, false, 2.0 * thin)

	var edge: float = 4.0 * thin
	if p.state == ProjectManager.State.OPEN:
		edge = 6.0 * thin
	draw_rect(b.grow(edge * 0.5), p.frame, false, edge)

	# --- favourite: a gold ring outside the frame, never replacing it, so
	# --- the frame colour the user chose survives being marked
	if p.favourite:
		var gold: Color = Color("#e8b64c")
		draw_rect(b.grow(edge * 1.9), gold, false, 3.0 * thin)

	# --- floating projects are dashed, which says "not put down yet"
	if p.state == ProjectManager.State.FLOATING:
		_dashed(b.grow(edge * 3.0), UiKit.ACCENT, 2.5 * thin)

	# --- a sheet being carried is dashed too, for the same reason: it is
	# --- in the air, and the dashes are what say so
	if p == manager.dragging:
		_dashed(b.grow(edge * 3.4), UiKit.ACCENT, 3.0 * thin)

	_draw_title(p, b, f, thin)
	if p == manager.selected and p != manager.active:
		# Single-tap selection highlight. It is intentionally distinct from the
		# open-project frame so selection never implies that the project is open.
		var select_col: Color = Color(0.55, 0.82, 1.0, 0.95)
		draw_rect(b.grow(edge * 2.6), select_col, false, maxf(2.0 * thin, 1.0 / zoom))

	if p == manager.active:
		_draw_camera(p, thin)

	if p.state == ProjectManager.State.CLOSED:
		_draw_veil(p, b, f, thin)

func _draw_title(p: ProjectManager.Project, b: Rect2, f: Font, thin: float) -> void:
	if f == null:
		return
	var size_px: int = maxi(int(18.0 * thin), 1)
	var lift: float = ProjectManager.TITLE_LIFT / zoom
	var strip: Rect2 = Rect2(b.position - Vector2(0.0, lift),
		Vector2(b.size.x, lift))

	# A quiet plate behind the words, so a title stays readable over any
	# paper colour and over whatever sits behind the project on the grid.
	var plate: Color = Color(p.frame.r, p.frame.g, p.frame.b, 0.92)
	draw_rect(Rect2(strip.position, Vector2(strip.size.x, strip.size.y * 0.86)),
		plate, true)

	var pad: float = 10.0 * thin
	var baseline: float = strip.position.y + strip.size.y * 0.6
	draw_string(f, Vector2(strip.position.x + pad, baseline), p.title,
		HORIZONTAL_ALIGNMENT_LEFT, strip.size.x * 0.6, size_px,
		Color(0.97, 0.95, 0.90))

	var tag: String = "%s  ·  %s" % [_kind_word(p.kind), p.created]
	draw_string(f, Vector2(strip.position.x + strip.size.x * 0.6, baseline), tag,
		HORIZONTAL_ALIGNMENT_RIGHT, strip.size.x * 0.4 - pad,
		maxi(int(13.0 * thin), 1), Color(0.80, 0.77, 0.71))

## A closed project shows a veil and a door: it is still there, it is simply
## not costing anything.
func _draw_veil(_p: ProjectManager.Project, b: Rect2, f: Font, thin: float) -> void:
	draw_rect(b, Color(0.09, 0.09, 0.11, 0.55), true)
	var side: float = minf(b.size.x, b.size.y) * 0.16
	side = clampf(side, 24.0 * thin, 160.0 * thin)
	var centre: Vector2 = b.get_center()
	var box: Rect2 = Rect2(centre - Vector2(side, side) * 0.5, Vector2(side, side))
	if _door != null:
		draw_texture_rect(_door, box, false, Color(0.95, 0.93, 0.88, 0.92))
	else:
		draw_rect(box, Color(0.95, 0.93, 0.88, 0.9), false, 3.0 * thin)
	if f != null:
		# The door does not answer a single tap on purpose: one tap is how a
		# sheet is picked out of a crowded workspace, and opening a project
		# is not something that should happen while you are looking for it.
		draw_string(f, Vector2(b.position.x, centre.y + side * 0.95),
			Lang.t("Double tap to open"), HORIZONTAL_ALIGNMENT_CENTER, b.size.x,
			maxi(int(16.0 * thin), 1), Color(0.92, 0.90, 0.85, 0.85))
		draw_string(f, Vector2(b.position.x, centre.y + side * 1.55),
			Lang.t("Hold and drag to move it"), HORIZONTAL_ALIGNMENT_CENTER,
			b.size.x, maxi(int(12.0 * thin), 1), Color(0.86, 0.84, 0.79, 0.60))

## The cinema frame: cream on the edge of what is kept, and everything
## outside it dimmed. It is drawn over the artwork rather than clipping it,
## so the parts about to leave the shot are still visible while you compose.
func _draw_camera(p: ProjectManager.Project, thin: float) -> void:
	if not camera_on or camera_rect.size.x <= 1.0:
		return
	var page: Rect2 = p.bounds()
	var shot: Rect2 = camera_rect

	var veil: Color = Color(0.07, 0.07, 0.09, 0.55)
	var outer: Rect2 = page.grow(maxf(page.size.x, page.size.y))
	# Four bands around the frame rather than a hole in a rectangle, which
	# is the only way to dim the outside without a mask.
	draw_rect(Rect2(outer.position.x, outer.position.y, outer.size.x,
		shot.position.y - outer.position.y), veil, true)
	draw_rect(Rect2(outer.position.x, shot.position.y + shot.size.y,
		outer.size.x, outer.position.y + outer.size.y
			- (shot.position.y + shot.size.y)), veil, true)
	draw_rect(Rect2(outer.position.x, shot.position.y,
		shot.position.x - outer.position.x, shot.size.y), veil, true)
	draw_rect(Rect2(shot.position.x + shot.size.x, shot.position.y,
		outer.position.x + outer.size.x - (shot.position.x + shot.size.x),
		shot.size.y), veil, true)

	var cream: Color = Color("#f3ead6")
	var centre: Vector2 = shot.get_center()
	var ux: Vector2 = Vector2(cos(camera_angle), sin(camera_angle))
	var uy: Vector2 = Vector2(-sin(camera_angle), cos(camera_angle))
	var half_x: Vector2 = ux * shot.size.x * 0.5
	var half_y: Vector2 = uy * shot.size.y * 0.5
	var corners_rot: Array[Vector2] = [centre - half_x - half_y, centre + half_x - half_y, centre + half_x + half_y, centre - half_x + half_y]
	for i in 4:
		draw_line(corners_rot[i], corners_rot[(i + 1) % 4], cream, 2.5 * thin)
	if camera_editing:
		# Grips at the corners, big enough for a finger, so the shot can be
		# framed by dragging it rather than by typing numbers at it.
		for c in corners_rot:
			draw_circle(c, 11.0 * thin, Color(1.0, 1.0, 1.0, 0.92))
			draw_circle(c, 8.0 * thin, cream)
		var rotate_handle: Vector2 = centre - uy * maxf(32.0 * thin, shot.size.y * 0.12)
		draw_line(centre - uy * maxf(8.0 * thin, 16.0 * thin), rotate_handle, cream, 2.0 * thin)
		draw_circle(rotate_handle, 9.0 * thin, Color(0.35, 0.85, 1.0, 0.95))
		draw_circle(centre, 9.0 * thin, Color(1.0, 1.0, 1.0, 0.85))
	# Corner marks, the way a viewfinder is drawn.
	var arm: Vector2 = shot.size * 0.08
	var corners: Array = [
		[shot.position, Vector2(arm.x, 0.0), Vector2(0.0, arm.y)],
		[shot.position + Vector2(shot.size.x, 0.0), Vector2(-arm.x, 0.0), Vector2(0.0, arm.y)],
		[shot.position + shot.size, Vector2(-arm.x, 0.0), Vector2(0.0, -arm.y)],
		[shot.position + Vector2(0.0, shot.size.y), Vector2(arm.x, 0.0), Vector2(0.0, -arm.y)],
	]
	for c in corners:
		draw_line(c[0], c[0] + c[1], cream, 4.0 * thin)
		draw_line(c[0], c[0] + c[2], cream, 4.0 * thin)

func _dashed(r: Rect2, col: Color, width: float) -> void:
	var dash: float = 18.0 / zoom
	var corners: Array = [
		r.position,
		r.position + Vector2(r.size.x, 0.0),
		r.position + r.size,
		r.position + Vector2(0.0, r.size.y),
	]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var span: float = a.distance_to(b)
		if span <= 0.001:
			continue
		var dir: Vector2 = (b - a) / span
		var t: float = 0.0
		while t < span:
			var e: float = minf(t + dash, span)
			draw_line(a + dir * t, a + dir * e, col, width)
			t = e + dash

func _kind_word(kind: int) -> String:
	if kind == ProjectManager.Kind.ANIMATION:
		return Lang.t("Animation")
	if kind == ProjectManager.Kind.COMIC:
		return Lang.t("Comic")
	return Lang.t("Drawing")
