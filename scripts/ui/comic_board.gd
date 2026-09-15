class_name ComicBoard
extends RefCounted
## Cutting a comic page into frames, and choosing which one to draw in.
##
## ## The two things this does, and why they are one tool
##
## **Cutting** makes the frames. **Choosing** says which frame the next stroke
## belongs to. They are separate ideas and they live together because they are
## the same gesture on the same picture: a finger on a page either draws a cut
## or picks a frame, and which it does is the mode the panel is in.
##
## ## The five shapes
##
## `LINE` is the one that does the work, and it is worth saying why. Every
## page in the reference sheet is straight cuts — a comic page is divided, not
## decorated, and the divisions are lines because a line is what a division
## *is*. The other four take a bite out of a frame and become a frame
## themselves, which is what an inset panel is.
##
## The cut line is infinite but the **gesture** is not, and the rule joining
## them is the whole of "you need not cut all the way across": a panel is cut
## when the drag *touches* it. Drag halfway into the left half and the left
## half splits; the right half was never touched and is left bit for bit as it
## was. See `ComicPage.cut_line`.
##
## ## Why confinement is a property of the page and not of the layer
##
## Because a frame is not a layer. Somebody who cuts a page into six and then
## merges two of them has changed a boundary, not thrown away six layers of
## work — and a system that made each frame a layer would have to answer what
## happens to the drawing when the boundary moves. Nothing should happen to
## it. The drawing is where it was; the frame it shows through has changed.
##
## What confinement actually does is refuse paint outside the chosen frame, at
## the one place in the app where paint is committed. See
## `PaintSurface.stamp`.

enum Mode { OFF, CUT, PICK }

static var mode: int = Mode.OFF
## Which of the five shapes a cut makes.
static var shape: int = ComicPage.Cut.LINE
static var on_done: Callable = Callable()
static var on_change: Callable = Callable()

static var _drawing: bool = false
static var _from: Vector2 = Vector2.ZERO
static var _to: Vector2 = Vector2.ZERO
static var _free: PackedVector2Array = PackedVector2Array()
## The project-local region used by closed-shape cutters. Keeping the cutter in
## the same local coordinate space as the page prevents it from becoming a
## screen-space object that floats when the camera pans or zooms.
static var _cut_region: Rect2 = Rect2()
## Smoothing for the cut, so a line drawn with a thumb comes out straight.
static var _aim: TouchLead = TouchLead.new()

static func busy() -> bool:
	return _drawing

static func _done() -> void:
	mode = Mode.OFF
	release_quietly()
	if on_done.is_valid():
		on_done.call()

# ------------------------------------------------------------- the page

static func page_of(view: CanvasView) -> ProjectManager.Page:
	if view == null or view.projects == null:
		return null
	var p: ProjectManager.Project = view.projects.active
	if p == null or p.kind != ProjectManager.Kind.COMIC:
		return null
	return p.page_at(p.active_page)

## The panel layout of the page being looked at, made on demand.
##
## Made rather than required, so a comic started before this existed opens
## with one frame rather than with none — and a page with no frames at all
## would confine every stroke to nowhere.
static func layout(view: CanvasView) -> ComicPage:
	var page: ProjectManager.Page = page_of(view)
	if page == null:
		return null
	if page.frames == null:
		var p: ProjectManager.Project = view.projects.active
		page.frames = ComicPage.fresh(p.page)
	return page.frames

## Canvas coordinates and page coordinates are the same coordinates.
##
## ## The offset that put the panels beside the drawing
##
## This is the fault where the cutter's frames sit off to one side of the page
## instead of on it, and where a stroke inside a visible frame is refused
## because the app thinks it landed outside one.
##
## There are two ways to name a point on a page in this app, and they are
## already the same:
##
##   * `CanvasView.screen_to_canvas()` subtracts `canvas_origin()`, and
##     `canvas_origin()` is `p.origin + p.page_offset(active_page)`.
##   * `ProjectManager.page_rect(i).position` is `origin + page_offset(i)`.
##
## The same expression, written in two files. So a point that has been through
## `screen_to_canvas` is **already** page-local, and the overlay these frames
## are drawn into is a child of World positioned at `canvas_origin()`, so its
## own draw coordinates are page-local as well.
##
## What was here subtracted `page_rect().position` from a point that had
## already had it subtracted, and added it back to a point that was already
## going to have it added by the overlay's own transform. Every frame was
## therefore drawn exactly one page origin away from the page, and every hit
## test asked about a point one page origin away from the finger. On page one
## of a project sitting at the workspace origin the offset is zero and
## everything looks right, which is why this survived: it only appears once
## the project has been moved, or on any page but the first.
##
## The conversion is kept as a named function rather than deleted, because
## "these two spaces are the same" is a fact about this app that is worth
## being able to point at — and because if a future page ever does sit
## somewhere else, this is the one place that has to change.
static func page_origin(view: CanvasView) -> Vector2:
	# Deliberately zero. See above: the offset is applied by the overlay's
	# transform and by `screen_to_canvas`, and applying it here as well is
	# what displaced the frames.
	if view == null:
		return Vector2.ZERO
	return Vector2.ZERO

static func to_page(view: CanvasView, w: Vector2) -> Vector2:
	return w - page_origin(view)

static func from_page(view: CanvasView, local: Vector2) -> Vector2:
	return local + page_origin(view)

# --------------------------------------------------------------- the hand

static func grab(view: CanvasView, screen: Vector2) -> bool:
	release_quietly()
	_cut_region = Rect2()
	if mode == Mode.OFF:
		return false
	var sheet: ComicPage = layout(view)
	if sheet == null:
		return false
	var w: Vector2 = to_page(view, view.screen_to_canvas(screen))

	if mode == Mode.PICK:
		# Choosing is done on the press rather than the release. There is
		# nothing to drag and nothing to change your mind about halfway, and
		# waiting for the lift makes a choice feel like it did not take.
		var hit: int = sheet.panel_at(w)
		# Pressing the chosen one again lets it go. A control that can only
		# ever select needs a second control beside it to deselect, and the
		# second control is always the one nobody finds.
		sheet.chosen = -1 if hit == sheet.chosen else hit
		_announce(view)
		return true

	# Closed-shape cutters are page furniture, not free-floating screen
	# overlays. They must start inside the comic frame and remain inside it
	# for the entire gesture. The actual geometry engine still clips the cut to
	# the touched panel, but this extra constraint keeps the visible guide
	# physically attached to the project frame instead of hanging outside it.
	if shape != ComicPage.Cut.LINE:
		_cut_region = _project_frame(view)
		if _cut_region.size.x < 1.0 or _cut_region.size.y < 1.0:
			return false
		if not _cut_region.has_point(w):
			_flash_miss(view)
			return false

	_aim.reset()
	_drawing = true
	_from = w
	_to = w
	_free = PackedVector2Array([w])
	return true

static func drag(view: CanvasView, screen: Vector2) -> void:
	if not _drawing:
		return
	# The same lead-in smoothing the drawing tools use. A cut is a line
	# somebody meant to be straight, and the raw touch stream is not.
	_to = to_page(view, view.screen_to_canvas(_aim.at(screen)))
	if shape != ComicPage.Cut.LINE and not _cut_region.has_point(_to):
		_to = Vector2(
			clampf(_to.x, _cut_region.position.x, _cut_region.end.x),
			clampf(_to.y, _cut_region.position.y, _cut_region.end.y))
	if shape == ComicPage.Cut.FREE:
		if _free.is_empty() \
				or _free[-1].distance_to(_to) > 4.0:
			_free.append(_to)
	if view.overlay != null:
		view.overlay.queue_redraw()

static func release(view: CanvasView) -> void:
	if not _drawing:
		release_quietly()
		return
	_drawing = false
	var sheet: ComicPage = layout(view)
	if sheet == null:
		_done()
		return

	# --- undo, before anything changes ---
	#
	# The layout is copied onto the page's own history alongside the layers,
	# so one press of undo takes back a cut exactly as it takes back a stroke.
	# Binding it here rather than inside `ComicPage` is deliberate: the model
	# should not know what an undo stack is, and the one place that knows a
	# gesture has finished is the one place that can record it.
	var before: ComicPage = sheet.copy()
	var changed: bool = false

	if shape == ComicPage.Cut.LINE:
		changed = sheet.cut_line(_from, _to)
	elif shape == ComicPage.Cut.FREE:
		changed = sheet.cut_shape(ComicPage.Cut.FREE, Rect2(), _free)
	else:
		changed = sheet.cut_shape(shape, _box())

	if changed:
		_record(view, before)
		# The chosen frame's index is meaningless after a cut — the list has
		# been rebuilt and index four is a different frame. Cleared rather
		# than guessed at, because a stale choice confines drawing to a frame
		# nobody picked, which is the most confusing failure this could have.
		sheet.chosen = -1
		_announce(view)
	else:
		_flash_miss(view)

	_free = PackedVector2Array()
	_cut_region = Rect2()
	if view != null and view.overlay != null:
		view.overlay.queue_redraw()

static func release_quietly() -> void:
	_drawing = false
	_free = PackedVector2Array()
	_cut_region = Rect2()

static func unpick() -> void:
	release_quietly()

## The visible comic frame in page-local coordinates.
##
## This is intentionally the same margin used by `ComicPage.reset()`. The
## cutter therefore has one parent coordinate system with the page: pan/zoom
## transform both together, while the cutter itself never receives screen
## coordinates or a second camera transform.
static func _project_frame(view: CanvasView) -> Rect2:
	var p: ProjectManager.Project = view.projects.active if view != null and view.projects != null else null
	if p == null or p.kind != ProjectManager.Kind.COMIC:
		return Rect2()
	var m: float = minf(ComicPage.MARGIN, minf(p.page.x, p.page.y) * 0.12)
	return Rect2(Vector2(m, m), Vector2(
		maxf(p.page.x - m * 2.0, 8.0),
		maxf(p.page.y - m * 2.0, 8.0)))

## The box a shape cut fills: the drag's two corners.
static func _box() -> Rect2:
	return Rect2(Vector2(minf(_from.x, _to.x), minf(_from.y, _to.y)),
		(_to - _from).abs())

static func _announce(view: CanvasView) -> void:
	if view != null and view.overlay != null:
		view.overlay.queue_redraw()
	if on_change.is_valid():
		on_change.call()

static func _record(view: CanvasView, before: ComicPage) -> void:
	var page: ProjectManager.Page = page_of(view)
	if page == null or page.history == null:
		return
	# The step describes the state *before* the cut, which is the contract
	# `History.push` states and is why `before` was taken at the top of
	# `release` rather than here.
	page.history.push(UiKit.label_for("Cut a panel", "قصّ إطار"),
		[{"t": "frames", "owner": page, "state": before.to_dict()}])
	if view.projects != null:
		view.projects.mark_dirty(view.projects.active)

static func _flash_miss(view: CanvasView) -> void:
	# Said out loud rather than silently ignored. A cut that lands on nothing
	# looks identical to a cut that failed, and somebody who thinks the tool
	# is broken stops using it.
	var host: Node = view.get_parent() if view != null else null
	while host != null and not host.has_method("_flash"):
		host = host.get_parent()
	if host != null:
		host.call("_flash", UiKit.label_for(
			"That cut did not cross a panel",
			"هذا القصّ لم يعبر أيّ إطار"))

# --------------------------------------------------------------- drawing

const FRAME_INK: Color = Color("#1B1C22")
const CHOSEN_INK: Color = Color("#E8B64C")
const CUT_INK: Color = Color("#E8B64C")

## Every frame on the page, and the cut being drawn.
##
## Drawn by the canvas overlay in screen space, so the borders stay the same
## weight at every zoom — a panel border is a printed line of a fixed weight,
## not a thing that gets thicker as you look closer.
static func draw(view: CanvasView) -> void:
	if view == null or view.overlay == null:
		return
	var sheet: ComicPage = layout(view)
	if sheet == null:
		return

	# IMPORTANT: Overlay is a child of World and is positioned at
	# `canvas_origin()`. Its draw coordinates are therefore PAGE-LOCAL. The
	# previous implementation converted them to screen coordinates first, then
	# let World apply pan/zoom a second time. That double transform is exactly
	# what made the cutter appear detached from the project frame (as in the
	# supplied screenshot).
	var thin: float = maxf(UiKit.s(1.8) / maxf(view.view_zoom, 0.0001), 0.15)

	for i in sheet.panels.size():
		var poly: PackedVector2Array = sheet.panels[i]
		if poly.size() < 3:
			continue
		var ring: PackedVector2Array = PackedVector2Array()
		for v in poly:
			ring.append(from_page(view, v))
		ring.append(ring[0])
		var picked: bool = (i == sheet.chosen)
		if picked:
			view.overlay.draw_colored_polygon(
				ring.slice(0, ring.size() - 1),
				Color(CHOSEN_INK.r, CHOSEN_INK.g, CHOSEN_INK.b, 0.10))
		view.overlay.draw_polyline(ring,
			CHOSEN_INK if picked else FRAME_INK,
			thin * (1.7 if picked else 1.0), true)

	if not _drawing:
		return
	_draw_pending(view, thin)

static func _draw_pending(view: CanvasView, thin: float) -> void:
	var ghost: Color = Color(CUT_INK.r, CUT_INK.g, CUT_INK.b, 0.85)
	if shape == ComicPage.Cut.LINE:
		var a: Vector2 = from_page(view, _from)
		var b: Vector2 = from_page(view, _to)
		var run: Vector2 = b - a
		if run.length() > 1.0:
			# The line is conceptually infinite, but the visible guide is clipped
			# to the comic frame. It can never visually escape the page.
			var far: Vector2 = run.normalized() * 10000.0
			view.overlay.draw_line(a - far, b + far,
				Color(CUT_INK.r, CUT_INK.g, CUT_INK.b, 0.28), thin)
		view.overlay.draw_line(a, b, ghost, thin * 1.6)
		return
	if shape == ComicPage.Cut.FREE:
		if _free.size() < 2:
			return
		var path: PackedVector2Array = PackedVector2Array()
		for v in _free:
			path.append(from_page(view, v))
		path.append(path[0])
		view.overlay.draw_polyline(path, ghost, thin * 1.4, true)
		return
	var poly: PackedVector2Array = ComicPage.shape_polygon(shape, _box(),
		PackedVector2Array())
	if poly.size() < 3:
		return
	var ring: PackedVector2Array = PackedVector2Array()
	for v in poly:
		ring.append(from_page(view, v))
	ring.append(ring[0])
	view.overlay.draw_polyline(ring, ghost, thin * 1.4, true)

