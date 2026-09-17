class_name CanvasMarks
extends RefCounted
## Selecting, lifting, transforming, cutting and pasting — the whole of it.
##
## Lifted whole out of `canvas_view.gd` by `tools/lift_module.py`. Not a line
## of the behaviour was rewritten in the move; every function arrived exactly
## as it was, with each reference to the canvas made explicit through `p`, and
## `canvas_view.gd` kept a one-line delegate for each so that main.gd, the
## tool panels and the transfer all still call `copy_selection` and
## `paste_clipboard` the way they always did.
##
## Why this block. Of the three files you named, `canvas_view.gd` was the
## worst at three and a half thousand lines, and this was the largest part of
## it that talks mostly to itself: marks, the floating selection, its handles,
## the clipboard and the placement of an incoming drawing are one subject, and
## almost every caller of these was another one of these.
##
## What makes the move safe is not care, it is `tools/check_references.py`.
## It resolves every `p.<member>` here against what `CanvasView` actually
## declares, on every build. Rename a field in the canvas and forget this file
## exists, and the next check names the line. That is the failure you have
## been paying for repeatedly, and it is now a machine's job.

static func _native_guard() -> Object:
	return Native.selection_guard() if Native.has_selection_guard() else null

static func _valid_mark(p: CanvasView) -> bool:
	if p._mark_points.size() < 2:
		return false
	var guard: Object = _native_guard()
	if guard != null:
		var report: Dictionary = guard.validate_mark(p._mark_points, int(App.select_shape), p.MAX_LIFT)
		if not bool(report.get("ok", false)):
			p.notice.emit(Lang.t("Invalid selection", "تحديد غير صالح"))
			return false
	# Second wall: cheap GDScript finite/bounds check remains active even when
	# the native extension is present. The two paths therefore cannot silently
	# disagree about NaN/Inf input.
	for point in p._mark_points:
		if not is_finite(point.x) or not is_finite(point.y):
			return false
	return true

static func begin_mark(p: CanvasView, w: Vector2) -> void:
	if App.select_shape == App.SelectShape.POLY:
		p._mark_points.append(w)
		p._marking = true
		p.overlay.queue_redraw()
		return
	p._marking = true
	p._mark_points = PackedVector2Array()
	p._mark_points.append(w)
	p._mark_points.append(w)
	p.overlay.queue_redraw()

static func continue_mark(p: CanvasView, w: Vector2) -> void:
	if App.select_shape == App.SelectShape.LASSO:
		if p._mark_points.is_empty() or p._mark_points[p._mark_points.size() - 1].distance_to(w) \
				> p.LASSO_STEP / maxf(p.view_zoom, 0.0001):
			p._mark_points.append(w)
	elif App.select_shape == App.SelectShape.POLY:
		if p._mark_points.size() > 0:
			p._mark_points[p._mark_points.size() - 1] = w
	else:
		if p._mark_points.size() >= 2:
			p._mark_points[1] = w
	p.overlay.queue_redraw()

static func end_mark(p: CanvasView, _w: Vector2) -> void:
	p._marking = false
	if App.select_shape == App.SelectShape.POLY:
		p.overlay.queue_redraw()
		p.selection_changed.emit()
		return
	p.lift_selection()

## Closes a dotted selection and lifts whatever it contains.
static func close_selection(p: CanvasView) -> void:
	if App.select_shape == App.SelectShape.POLY and p._mark_points.size() >= 3:
		p.lift_selection()

static func clear_marks(p: CanvasView) -> void:
	p._mark_points.clear()
	p._marking = false
	p.overlay.queue_redraw()
	p.selection_changed.emit()

static func has_marks(p: CanvasView) -> bool:
	return p._mark_points.size() >= 2

## Cuts the marked pixels out of the active layer and holds them as a
## floating piece the user can move, scale and turn.
static func lift_selection(p: CanvasView, keep_original: bool = false) -> bool:
	if not _valid_mark(p):
		p.clear_marks()
		return false
	var surface: PaintSurface = p.active_surface()
	if surface == null or p.layers == null or p._mark_points.size() < 2:
		return false
	var shape: int = App.select_shape
	var box: Rect2i = SelectionMask.bounds_of(p._mark_points)
	if shape == App.SelectShape.RECT or shape == App.SelectShape.ELLIPSE:
		box = Rect2i(
			Vector2i(int(floor(minf(p._mark_points[0].x, p._mark_points[1].x))),
				int(floor(minf(p._mark_points[0].y, p._mark_points[1].y)))),
			Vector2i(int(absf(p._mark_points[1].x - p._mark_points[0].x)),
				int(absf(p._mark_points[1].y - p._mark_points[0].y))))
	if box.size.x < 2 or box.size.y < 2:
		p.clear_marks()
		return false
	if box.size.x > p.MAX_LIFT or box.size.y > p.MAX_LIFT:
		p.clear_marks()
		return false

	var img: Image = surface.read_region(box)
	if img == null:
		p.clear_marks()
		return false

	var mask: PackedByteArray
	if shape == App.SelectShape.RECT:
		mask = SelectionMask.full(box.size.x, box.size.y)
	elif shape == App.SelectShape.ELLIPSE:
		mask = SelectionMask.ellipse(box.size.x, box.size.y)
	else:
		mask = SelectionMask.polygon(p._mark_points, box.position, box.size.x, box.size.y)

	if not SelectionMask.apply(img, mask):
		# The shape was drawn but there is no ink inside it on *this* layer.
		#
		# Said out loud rather than swallowed. This failed silently — the
		# marquee simply vanished on release — and silence here is the
		# difference between "I selected empty paper" and "the selection tool
		# is broken". The commonest cause is having the wrong layer active:
		# the drawing is plainly there on the screen, and it belongs to a
		# layer that is not the one being cut from.
		p.clear_marks()
		p.notice.emit(Lang.t(
			"Nothing on this layer inside the selection",
			"لا شيء على هذه الطبقة داخل التحديد"))
		return false

	var owner: LayerStack.Layer = p.layers.active()
	if owner == null:
		p.clear_marks()
		return false
	p._sel_snapshot = {}
	p._sel_layer = owner.id
	# Whether this lift took the whole drawing or only a piece of it.
	#
	# It decides one thing: whether the layer's skeleton travels with it. A
	# selection of part of a figure says nothing about where the bones under
	# the rest of it should go, and moving those would be moving bones the
	# user never touched.
	surface.flush()
	var whole: Rect2i = surface.content_bounds()
	p._sel_whole_layer = Rect2i()
	if whole.size.x > 0 and whole.size.y > 0 and box.encloses(whole):
		p._sel_whole_layer = whole
	if not keep_original:
		p._snapshot_rect(surface, box)
		surface.erase_masked(box, mask)

	p._distort_base = img.duplicate()
	p._sel_tex = ImageTexture.create_from_image(img)
	p._sel_size = Vector2(float(box.size.x), float(box.size.y))
	p._sel_center = Vector2(box.position) + p._sel_size * 0.5
	p._sel_rot = 0.0
	p._sel_scale = 1.0
	p.sel_active = true
	p._mark_points.clear()
	p.overlay.queue_redraw()
	p.selection_changed.emit()
	return true

static func selection_transform(p: CanvasView) -> Transform2D:
	var cs: float = cos(p._sel_rot) * p._sel_scale
	var sn: float = sin(p._sel_rot) * p._sel_scale
	var xf: Transform2D = Transform2D(Vector2(cs, sn), Vector2(-sn, cs), p._sel_center)
	return xf.translated_local(-p._sel_size * 0.5)

static func sel_corners(p: CanvasView) -> Array:
	var xf: Transform2D = p.selection_transform()
	return [
		xf * Vector2.ZERO,
		xf * Vector2(p._sel_size.x, 0.0),
		xf * p._sel_size,
		xf * Vector2(0.0, p._sel_size.y),
	]

static func rotate_handle(p: CanvasView) -> Vector2:
	var c: Array = p._sel_corners()
	var top: Vector2 = ((c[0] as Vector2) + (c[1] as Vector2)) * 0.5
	var up: Vector2 = Vector2(sin(p._sel_rot), -cos(p._sel_rot))
	return top + up * (34.0 / maxf(p.view_zoom, 0.0001))

static func hit_handle(p: CanvasView, screen: Vector2) -> int:
	if not p.sel_active:
		return p.Grab.NONE
	var reach: float = p.HANDLE_HIT * App.ui_scale
	# No turning a drawing that is still being placed. A rotation has to be
	# resampled into every piece separately, and six pieces each turned through
	# an angle do not compose back into the single picture the box was showing —
	# the preview would be a promise the landing could not keep. Move it, size
	# it, put it down; then turn it with the selection tool, which can.
	if p._placing == null \
			and p.canvas_to_screen(p._rotate_handle()).distance_to(screen) <= reach:
		return p.Grab.ROTATE
	for c in p._sel_corners():
		if p.canvas_to_screen(c).distance_to(screen) <= reach:
			return p.Grab.SCALE
	# inside the box?
	var local: Vector2 = p.selection_transform().affine_inverse() * p.screen_to_canvas(screen)
	if local.x >= 0.0 and local.y >= 0.0 and local.x <= p._sel_size.x and local.y <= p._sel_size.y:
		return p.Grab.MOVE
	return p.Grab.NONE

static func start_grab(p: CanvasView, kind: int, screen: Vector2) -> void:
	if not p.sel_active or p._sel_tex == null:
		p._grab = p.Grab.NONE
		return
	var guard: Object = _native_guard()
	if guard != null:
		var report: Dictionary = guard.validate_transform(p._sel_center, p._sel_size, p._sel_scale, p._sel_rot, p.MAX_LIFT)
		if not bool(report.get("ok", false)):
			p._grab = p.Grab.NONE
			p.notice.emit(Lang.t("Selection transform blocked", "تم منع تحويل التحديد"))
			return
	p._grab = kind
	p._grab_start = p.screen_to_canvas(screen)
	p._grab_centre = p._sel_center
	p._grab_scale = p._sel_scale
	p._grab_rot = p._sel_rot
	if kind == p.Grab.ROTATE:
		p._grab_ref = (p._grab_start - p._sel_center).angle() - p._sel_rot
	elif kind == p.Grab.SCALE:
		p._grab_ref = maxf(p._grab_start.distance_to(p._sel_center), 0.001)

static func update_grab(p: CanvasView, screen: Vector2) -> void:
	var w: Vector2 = p.screen_to_canvas(screen)
	if p._grab == p.Grab.MOVE:
		p._sel_center = p._grab_centre + (w - p._grab_start)
	elif p._grab == p.Grab.ROTATE:
		p._sel_rot = (w - p._sel_center).angle() - p._grab_ref
	elif p._grab == p.Grab.SCALE:
		var now: float = maxf(w.distance_to(p._sel_center), 0.001)
		p._sel_scale = clampf(p._grab_scale * (now / p._grab_ref), 0.02, 40.0)
	p.overlay.queue_redraw()

## Drops the floating piece onto its layer for good.
static func commit_selection(p: CanvasView) -> void:
	if not p.sel_active:
		return
	var guard: Object = _native_guard()
	if guard != null:
		var report: Dictionary = guard.validate_transform(p._sel_center, p._sel_size, p._sel_scale, p._sel_rot, p.MAX_LIFT)
		if not bool(report.get("ok", false)):
			p.notice.emit(Lang.t("Selection transform blocked", "تم منع تحويل التحديد"))
			return
	# A drawing arriving from another project is not stamped onto the layer
	# under it — it becomes its own layers, which is the whole point of having
	# been asked "one layer or several".
	if p._placing != null:
		p._commit_placement()
		return
	var surface: PaintSurface = p.layers.surface_by_id(p._sel_layer)
	if surface == null:
		surface = p.active_surface()
	if surface != null and p._sel_tex != null:
		var corners: Array = p._sel_corners()
		var lo: Vector2 = corners[0]
		var hi: Vector2 = corners[0]
		for c in corners:
			lo.x = minf(lo.x, (c as Vector2).x)
			lo.y = minf(lo.y, (c as Vector2).y)
			hi.x = maxf(hi.x, (c as Vector2).x)
			hi.y = maxf(hi.y, (c as Vector2).y)
		p._snapshot_rect(surface, Rect2i(
			Vector2i(int(floor(lo.x)) - 2, int(floor(lo.y)) - 2),
			Vector2i(int(hi.x - lo.x) + 4, int(hi.y - lo.y) + 4)))
		# Enlarged pieces are resampled properly before they are put down.
		#
		# The transform hands the whole job to the GPU, which stretches with
		# a bilinear filter — a blur with a good name. A small selection
		# scaled up and committed came back looking photographed through a
		# window, and the damage is permanent because it is now pixels.
		#
		# So anything growing by more than a fifth is resampled through
		# Lanczos at its final size first, and the transform is left with
		# only the turning and the placing to do. Below a fifth it is not
		# worth the work: the filter and the resample agree to within less
		# than the eye can see at that ratio.
		var place: Transform2D = p.selection_transform()
		var tex: Texture2D = p._sel_tex
		var grow: float = maxf(place.x.length(), place.y.length())
		if grow > 1.2 and p._sel_tex != null:
			var src: Image = p._sel_tex.get_image()
			if src != null:
				var want: Vector2i = Vector2i(
					int(round(p._sel_size.x * place.x.length())),
					int(round(p._sel_size.y * place.y.length())))
				# Guarded: a selection dragged to an absurd size would
				# otherwise try to allocate it, and the GPU stretch is the
				# right answer past the point where a resample stops being
				# affordable.
				if want.x > 0 and want.y > 0 \
						and want.x <= p.MAX_LIFT and want.y <= p.MAX_LIFT:
					var big: Image = Distort.rescale(src, want)
					if big != null:
						tex = ImageTexture.create_from_image(big)
						place = Transform2D(place.get_rotation(),
							Vector2.ONE, place.get_skew(), place.origin)
						surface.blit_transformed(tex, place, Vector2(want))
						p._settle_in = 3
						p._carry_rig_with_selection()
						p.history.push_pixels(
							UiKit.label_for("Place selection", "تثبيت تحديد"),
							p._sel_layer, p._sel_snapshot)
						p._sel_snapshot = {}
						p._drop_floating()
						return
		surface.blit_transformed(tex, place, p._sel_size)
		p._settle_in = 3
	p._carry_rig_with_selection()
	p.history.push_pixels(UiKit.label_for("Place selection", "تثبيت تحديد"),
		p._sel_layer, p._sel_snapshot)
	p._sel_snapshot = {}
	p._drop_floating()

## Takes a rigged layer's skeleton with its drawing.
##
## Only when the whole layer was lifted. A selection of part of a drawing says
## nothing about where the bones under the rest of it should go, and guessing
## would be worse than leaving them: it would move bones the user never
## touched. So the rig follows only a gesture that plainly meant the whole
## figure — which is what lifting everything and putting it down somewhere
## else means.
static func carry_rig_with_selection(p: CanvasView) -> void:
	if p.layers == null or p._sel_whole_layer == Rect2i():
		return
	var l: LayerStack.Layer = null
	for one in p.layers.layers:
		if one.id == p._sel_layer:
			l = one
			break
	if l == null or l.rig.is_empty():
		return
	var factor: float = maxf(p._sel_scale, 0.001)
	# Where the middle of the lifted piece was, and where it has been put.
	# The bones are in page coordinates, so the shift is what carries a
	# skeleton scaled about the origin back to the drawing it belongs to.
	var was: Vector2 = Vector2(p._sel_whole_layer.position) \
		+ Vector2(p._sel_whole_layer.size) * 0.5
	p.layers.transform_rig(l, factor, p._sel_center - was * factor)

## The skeleton of the layer being worked on, drawn over the drawing it holds.
##
## The rig was already surviving Apply — `_apply` writes it to `layer.rig`, the
## vault saves it, `transform_rig` moves it with the layer. Everything kept it
## and nothing *showed* it, so from where the user stands the bones simply did
## not come back from the room. There was no bug in the transfer; there was no
## drawing code at the end of it.
##
## Only the active layer's, and only when the rig has bones. A page with six
## rigged characters on six layers would otherwise be a thicket of ivory
## sticks, and the one you are working on is the one you need to see.
static func draw_layer_rig(p: CanvasView) -> void:
	if p.layers == null or p.overlay == null:
		return
	var l: LayerStack.Layer = p.layers.active()
	if l == null or not l.visible or l.rig.is_empty():
		return
	var sticks: Array = l.rig.get("bones", [])
	# Mid-drag the rig on the layer is still the *last* pose — it is only
	# written when the finger lifts — so while a joint is being held the live
	# skeleton is read instead. Without this the drawing bends under spindles
	# that have not moved, which reads exactly like bones coming loose from
	# the figure they belong to.
	if BoneHandle.posing():
		var live: Array = BoneHandle.live_bones()
		if not live.is_empty():
			sticks = BoneRig.to_rows(live)
	if sticks.is_empty():
		return

	# Shifted onto the drawing, if the drawing has moved since the bones were
	# laid on it. See `BoneRig.anchor_shift` — this is what stops a skeleton
	# from being drawn off to one side of the figure it belongs to.
	var home: Vector2 = BoneRig.anchor_shift(l.rig, BoneRig.ink_of(l))

	# The same three the rig rooms use, read from where they are defined so
	# the skeleton on the canvas cannot drift into being a second palette.
	var ink: Color = BoneRig.BONE_INK
	var pale: Color = BoneRig.BONE_CORE
	var edge: Color = BoneRig.BONE_EDGE
	# Sized in screen pixels, so the skeleton stays the same weight under the
	# finger however far the canvas is zoomed — the bones are a control, not
	# part of the picture.
	var dot: float = maxf(6.0 * App.ui_scale, 5.0)
	var joints: PackedVector2Array = PackedVector2Array()

	for row in sticks:
		var one: Dictionary = row
		# The posed ends, `p`/`q` — where the bone actually is now. `a`/`b`
		# are the rest pose it was built in, which is not where it is.
		# `overlay` is a child of `world`, so it already receives the camera
		# transform (zoom/pan/rotation). Feeding screen coordinates into it
		# applied that transform a second time, making the skeleton appear to
		# float above/follow the camera during zoom, pan or rotation.
		# Overlay drawing must stay in world/canvas coordinates.
		var a: Vector2 = home + Vector2(float(one.get("px", 0.0)),
			float(one.get("py", 0.0)))
		var b: Vector2 = home + Vector2(float(one.get("qx", 0.0)),
			float(one.get("qy", 0.0)))
		var dir: Vector2 = b - a
		var span: float = dir.length()
		if span < 1.0:
			continue
		dir = dir / span
		var side: Vector2 = Vector2(-dir.y, dir.x)
		var wide: float = clampf(span * 0.14, 4.0, 15.0)
		var neck: Vector2 = a + dir * (span * 0.22)
		p.overlay.draw_colored_polygon(PackedVector2Array([
			a, neck + side * wide, b, neck - side * wide]),
			Color(ink.r, ink.g, ink.b, 0.12))
		p.overlay.draw_polyline(PackedVector2Array([a, neck + side * wide, b,
			neck - side * wide, a]), ink, 1.25)
		# Gathered rather than drawn here, so two bones meeting at a joint put
		# one marker there — the same rule the room follows.
		for at in [a, b]:
			var seen: bool = false
			for k in joints.size():
				if joints[k].distance_to(at) <= dot:
					seen = true
					break
			if not seen:
				joints.append(at)

	for at in joints:
		p.overlay.draw_circle(at, dot * 0.82, pale)
		p.overlay.draw_arc(at, dot * 0.82, 0.0, TAU, 18, edge, 1.35)
	_draw_held_cross(p, dot, ink, pale, edge)

## The cross through the joint currently in the hand.
##
## ## Why a circle was not enough
##
## A joint marker was a circle, and a circle says only "something is here". It
## does not say which way the bone runs, so it does not say how a drag will be
## read — and a control whose response cannot be predicted before touching it
## is a control learned by trial.
##
## The cross names the two motions. One arm lies **along** the bone: pull that
## way and the limb reaches out or draws in, keeping every length, the joints
## between working themselves out. The other lies **square** to it: push that
## way and the limb swings. Both were always there — a drag has always been
## read as a whole vector — and nothing on the screen ever said so.
##
## ## Why only on touch
##
## A figure with twenty joints would be forty lines standing still over the
## drawing, and the one thing a rig overlay must not do is hide the artwork
## under it. So the cross belongs to the joint in the hand and to no other: it
## appears the moment one is taken hold of and is gone the moment it is let
## go, which is exactly when it is worth the ink.
##
## The two arms are drawn differently on purpose. The swing arm is solid,
## because swinging is the ordinary thing and the ordinary thing should look
## like the default; the reach arm is dashed, because reaching changes the
## whole chain and a control with further consequences should not look
## identical to one without.
static func _draw_held_cross(p: CanvasView, dot: float, ink: Color,
		pale: Color, edge: Color) -> void:
	var axes: Array = BoneHandle.held_cross()
	if axes.size() < 2:
		return
	# The overlay is already inside the transformed world. Do not convert
	# this point to screen space a second time.
	var at: Vector2 = BoneHandle.held_at()
	var along: Vector2 = (axes[0] as Vector2)
	var across: Vector2 = (axes[1] as Vector2)
	var arm: float = dot * 4.2

	# Square to the bone: swing. One clean line.
	p.overlay.draw_line(at - across * arm, at + across * arm,
		Color(ink.r, ink.g, ink.b, 0.30), 4.0)
	p.overlay.draw_line(at - across * arm, at + across * arm, pale, 1.7)

	# Along the bone: reach. Dashed by hand rather than with a dash width,
	# which `draw_line` has no notion of — five short strokes each side.
	for side in [-1.0, 1.0]:
		for k in 5:
			var from: float = arm * (float(k) * 0.2 + 0.04) * side
			var to: float = arm * (float(k) * 0.2 + 0.15) * side
			p.overlay.draw_line(at + along * from, at + along * to,
				Color(pale.r, pale.g, pale.b, 0.85), 1.7)

	# The joint itself, marked louder than its neighbours so the one under
	# the finger is never in doubt.
	p.overlay.draw_circle(at, dot * 1.25, pale)
	p.overlay.draw_arc(at, dot * 1.25, 0.0, TAU, 20, edge, 2.2)

## Throws the floating piece away and puts the pixels back where they were.
static func cancel_selection(p: CanvasView) -> void:
	if not p.sel_active:
		return
	if not p._sel_snapshot.is_empty():
		p._restore(p._sel_layer, p._sel_snapshot)
	p._sel_snapshot = {}
	p._drop_floating()

static func drop_floating(p: CanvasView) -> void:
	p.sel_active = false
	p._sel_tex = null
	p._distort_base = null
	p._grab = p.Grab.NONE
	p.overlay.queue_redraw()
	p.selection_changed.emit()

## Hands an image to the selection machinery instead of stamping it down.
## A picture almost never lands where it is finally wanted, and arriving as
## a floating piece means it can be moved, turned and scaled before it
## becomes part of the layer — with Cancel still meaning cancel.
static func float_image(p: CanvasView, img: Image, layer_id: int, centre: Vector2) -> bool:
	if img == null or p.layers == null:
		return false
	if p.sel_active:
		p.commit_selection()
	var copy: Image = Image.create_empty(img.get_width(), img.get_height(),
		false, Image.FORMAT_RGBA8)
	copy.copy_from(img)
	p._distort_base = copy.duplicate()
	p._sel_tex = ImageTexture.create_from_image(copy)
	p._sel_size = Vector2(float(copy.get_width()), float(copy.get_height()))
	p._sel_center = centre
	p._sel_rot = 0.0
	p._sel_scale = 1.0
	p._sel_whole_layer = Rect2i()
	p._sel_layer = layer_id
	p._sel_snapshot = {}
	p.sel_active = true
	p.overlay.queue_redraw()
	p.selection_changed.emit()
	return true

static func set_distort(p: CanvasView, kind: int, amount: float) -> void:
	p.distort_kind = kind
	p.distort_amount = clampf(amount, -1.0, 1.0)
	if p.sel_active and p._distort_base != null and Native.has_distort():
		var engine: Object = Native.distort()
		var warped: Image = engine.apply(p._distort_base, kind, p.distort_amount)
		if warped != null:
			p._sel_tex = ImageTexture.create_from_image(warped)
	if p.sel_active:
		p._sync_floating()
		p.overlay.queue_redraw()

## Rubs a shape out of the marked part.
##
## Uses the same bounds, snapshot and undo path the lift already uses, rather
## than a second set of nearly-identical helpers — a trim that recorded undo
## its own way would be a trim that undoes differently from everything else.
static func trim_selection(p: CanvasView, cut_kind: int, keep_inside: bool) -> bool:
	var surface: PaintSurface = p.active_surface()
	if surface == null or p.layers == null or p._mark_points.size() < 2:
		return false
	var box: Rect2i = SelectionMask.bounds_of(p._mark_points)
	if App.select_shape == App.SelectShape.RECT \
			or App.select_shape == App.SelectShape.ELLIPSE:
		box = Rect2i(
			Vector2i(int(floor(minf(p._mark_points[0].x, p._mark_points[1].x))),
				int(floor(minf(p._mark_points[0].y, p._mark_points[1].y)))),
			Vector2i(int(absf(p._mark_points[1].x - p._mark_points[0].x)),
				int(absf(p._mark_points[1].y - p._mark_points[0].y))))
	if box.size.x < 2 or box.size.y < 2:
		p.clear_marks()
		return false

	var l: LayerStack.Layer = p.layers.active()
	if l == null:
		return false
	surface.flush()
	p._sel_snapshot = {}
	p._snapshot_rect(surface, box)
	var img: Image = surface.read_region(box)
	if img == null:
		return false
	Distort.trim(img, box.position, cut_kind,
		Rect2(Vector2(box.position), Vector2(box.size)), keep_inside)
	# `replace` rather than blend: the point of a trim is the pixels that are
	# now empty, and blending an empty pixel over a full one leaves the full
	# one exactly where it was.
	surface.blit_image(img, Vector2(box.position), true)
	p._push_undo(l.id, p._sel_snapshot,
		UiKit.label_for("Trim", "قص"))
	p._sel_snapshot = {}
	p.clear_marks()
	return true

## Writes down where the clipboard came from, alongside what is in it.
##
## The picture alone is not quite enough. "Paste onto a layer of its own" has
## to call that layer something, and *Layer 9* tells the user nothing about
## what landed on it — where the name of the layer it was taken from tells them
## exactly. It costs one string and it is the difference between a stack of
## numbered layers and a stack you can read.
static func note_clip(p: CanvasView) -> void:
	App.clip_from = ""
	if p.layers == null:
		return
	var l: LayerStack.Layer = p.layers.active()
	if l != null:
		App.clip_from = l.title

static func copy_selection(p: CanvasView) -> bool:
	if p.layers == null:
		return false
	if p.sel_active and p._sel_tex != null:
		App.clipboard = p._sel_tex.get_image()
		p._note_clip()
		p.selection_changed.emit()
		return true
	if p.has_marks():
		# The marks are put back afterwards. Copying used to clear them —
		# `p.lift_selection` empties the outline as part of turning it into a
		# floating piece — so copying a shape and then cutting the same shape
		# meant drawing the shape twice. Copying is the one operation here that
		# changes nothing, and it should leave the screen as it found it.
		var held: PackedVector2Array = p._mark_points.duplicate()
		if p.lift_selection(true):
			App.clipboard = p._sel_tex.get_image()
			p._note_clip()
			p._drop_floating()
			p._mark_points = held
			p.overlay.queue_redraw()
			p.selection_changed.emit()
			return true
		p._mark_points = held
		return false
	# nothing marked: take the whole layer
	var surface: PaintSurface = p.active_surface()
	if surface == null:
		return false
	surface.flush()
	var box: Rect2i = surface.content_bounds()
	if box.size.x <= 0 or box.size.y <= 0:
		return false
	if box.size.x > p.MAX_LIFT or box.size.y > p.MAX_LIFT:
		var centre: Vector2i = box.position + Vector2i(box.size.x >> 1, box.size.y >> 1)
		var half: int = int(float(p.MAX_LIFT) * 0.5)
		box = Rect2i(centre - Vector2i(half, half), Vector2i(p.MAX_LIFT, p.MAX_LIFT))
	var img: Image = surface.read_region(box)
	if img == null:
		return false
	App.clipboard = img
	p._note_clip()
	p.selection_changed.emit()
	return true

## Copy, and take it away — as one undoable act.
##
## Cut existed only as "copy, then rub out by hand", which is two gestures and
## two entries in the history for one intention. Every route through this ends
## with exactly one entry on the stack, so one press of undo brings the pixels
## back whatever was marked when it was cut.
static func cut_selection(p: CanvasView) -> bool:
	if p.layers == null or not p.layers.can_draw():
		return false

	if p.sel_active and p._sel_tex != null:
		# Already lifted, which means the layer has already lost these pixels
		# and the record of losing them is already in hand. Keeping the picture
		# and dropping the piece is the whole of the cut.
		App.clipboard = p._sel_tex.get_image()
		p._note_clip()
		if not p._sel_snapshot.is_empty():
			p._push_undo(p._sel_layer, p._sel_snapshot,
				UiKit.label_for("Cut", "قص"))
			p._sel_snapshot = {}
		p._drop_floating()
		return true

	if p.has_marks():
		if not p.lift_selection(false):
			return false
		App.clipboard = p._sel_tex.get_image()
		p._note_clip()
		p._push_undo(p._sel_layer, p._sel_snapshot, UiKit.label_for("Cut", "قص"))
		p._sel_snapshot = {}
		p._drop_floating()
		return true

	# Nothing marked, so the whole layer — the same rule Copy follows, which
	# is what makes the pair predictable. `clear_layer` files its own entry.
	if not p.copy_selection():
		return false
	p.layers.clear_layer(p.layers.active_index)
	return true

static func paste_clipboard(p: CanvasView) -> bool:
	if App.clipboard == null or p.layers == null:
		return false
	if p.sel_active:
		p.commit_selection()
	var img: Image = Image.create_empty(App.clipboard.get_width(),
		App.clipboard.get_height(), false, Image.FORMAT_RGBA8)
	img.copy_from(App.clipboard)
	p._sel_tex = ImageTexture.create_from_image(img)
	p._sel_size = Vector2(float(img.get_width()), float(img.get_height()))
	p._sel_center = p.screen_to_canvas(p.size * 0.5)
	p._sel_rot = 0.0
	p._sel_scale = 1.0
	p._sel_layer = p.layers.active().id
	p._sel_snapshot = {}
	p.sel_active = true
	p.overlay.queue_redraw()
	p.selection_changed.emit()
	return true

## Floats a drawing brought in from another project, ready to be placed.
##
## `float_image` does the whole of the work — it is already the way a picture
## enters this app without committing itself, and an imported photograph and a
## transferred drawing want exactly the same thing from the user: put me where
## I go. The only addition is remembering *what* is floating, so that pressing
## outside the box lands layers rather than stamping pixels.
##
## The box opens exactly where the fitting put the drawing — centred on the
## page, its proportions kept — so a user who is happy with that can press once
## and be done, and a user who is not can drag from a sensible starting place
## instead of hunting for the picture.
static func begin_placement(p: CanvasView, landing: DrawTransfer.Landing) -> bool:
	if landing == null or landing.preview == null:
		return false
	if p.sel_active:
		p.commit_selection()
	if not p.float_image(landing.preview, -1, landing.home()):
		return false
	p._placing = landing
	p.notice.emit(UiKit.label_for("Place it, then tap outside to fix it",
		"ضعها، ثم اضغط خارجها لتثبيتها"))
	p.overlay.queue_redraw()
	return true

## Puts the carried drawing down where the box was left.
##
## The transform is read off the box before anything is dropped, because
## `_drop_floating` clears the numbers it is made of. Landing before dropping
## would be the other obvious order and it would place every transfer at the
## origin.
static func commit_placement(p: CanvasView) -> void:
	var landing: DrawTransfer.Landing = p._placing
	var place: Transform2D = p.selection_transform()
	p._placing = null
	p._drop_floating()
	if landing == null or p.layers == null:
		return
	var told: Dictionary = DrawTransfer.land(p.projects, landing, place)
	if bool(told["ok"]):
		p.history_changed.emit()
		p.project_changed.emit()
		p.queue_redraw()
	p.notice.emit(String(told["message"]))

## Gives up on a drawing that was on its way in.
##
## Reachable from a tool change or leaving the project — anywhere the box would
## otherwise be abandoned on screen with nothing able to commit it. Nothing was
## written to the target, so there is nothing to undo.
static func cancel_placement(p: CanvasView) -> void:
	if p._placing == null:
		return
	p._placing = null
	p._drop_floating()
	p.notice.emit(UiKit.label_for("Transfer cancelled", "أُلغي النقل"))

## Paste onto a layer of its own.
##
## The ordinary paste lands on whatever layer is selected, which is right when
## you are assembling something and wrong when you are bringing a piece in from
## somewhere else — a figure copied out of another project has no business
## sharing a layer with the background it happened to arrive next to.
##
## Two entries end up on the history rather than one, and deliberately: a layer
## appeared, and then a picture was put on it. They are two things the user can
## see, they happened in that order, and undo should take them back in that
## order. The piece is still floating when this returns, so it can be moved,
## turned and scaled — or cancelled outright — before it becomes pixels.
static func paste_as_new_layer(p: CanvasView) -> bool:
	if App.clipboard == null or p.layers == null:
		return false
	if p.sel_active:
		p.commit_selection()
	var fresh: LayerStack.Layer = p.layers.add_layer_here()
	if fresh == null:
		p.notice.emit(UiKit.label_for("No room for another layer",
			"لا مكان لطبقة أخرى"))
		return false
	if App.clip_from != "":
		fresh.title = App.clip_from
	return p.paste_clipboard()

## Lays down a solid shape in the bucket's colour. Not a stroke that happens
## to close: the interior is filled outright, which is what anyone reaching
## for a bucket and a rectangle is asking for.
static func commit_fill_shape(p: CanvasView) -> void:
	var surface: PaintSurface = p.active_surface()
	if surface == null or p.layers == null or not p.layers.can_draw():
		return
	var r: Rect2 = Rect2(p._shape_a, p._shape_b - p._shape_a).abs()
	if r.size.x < 2.0 or r.size.y < 2.0:
		return
	var box: Rect2i = Rect2i(Vector2i(r.position.floor()), Vector2i(r.size.ceil()))
	if box.size.x > 4096 or box.size.y > 4096:
		return

	var mask: PackedByteArray = fill_mask(box.size.x, box.size.y)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(box.size.x * box.size.y * 4)
	var ink: Color = App.fill_ink
	var a: int = int(clampf(ink.a, 0.0, 1.0) * 255.0)
	# Premultiplied, like everything else the canvas holds.
	var cr: int = int(clampf(ink.r, 0.0, 1.0) * float(a))
	var cg: int = int(clampf(ink.g, 0.0, 1.0) * float(a))
	var cb: int = int(clampf(ink.b, 0.0, 1.0) * float(a))
	for i in range(box.size.x * box.size.y):
		if mask[i] == 0:
			continue
		var o: int = i * 4
		bytes[o] = cr
		bytes[o + 1] = cg
		bytes[o + 2] = cb
		bytes[o + 3] = a
	var img: Image = Image.create_empty(box.size.x, box.size.y, false, Image.FORMAT_RGBA8)
	img.set_data(box.size.x, box.size.y, false, Image.FORMAT_RGBA8, bytes)

	var snap: Dictionary = {}
	p._collect(surface, box, snap)
	surface.blit_image(img, Vector2(box.position))
	p.history.push_pixels(UiKit.label_for("Fill", "ملء"), p.layers.active().id, snap)

## The shape a fill takes, as a mask of the given size.
##
## Takes no canvas: it reads the chosen shape off the app's settings and
## produces a mask, and nothing about the drawing enters into it. The lift
## handed it one anyway, which Godot then reported as a parameter that is
## never used.
static func fill_mask(w: int, h: int) -> PackedByteArray:
	if App.fill_shape == App.FillShape.ELLIPSE:
		return SelectionMask.ellipse(w, h)
	if App.fill_shape == App.FillShape.RECT:
		return SelectionMask.full(w, h)
	var pts: PackedVector2Array = PackedVector2Array()
	var fw: float = float(w)
	var fh: float = float(h)
	if App.fill_shape == App.FillShape.TRIANGLE:
		pts.append(Vector2(fw * 0.5, 0.0))
		pts.append(Vector2(fw, fh))
		pts.append(Vector2(0.0, fh))
	elif App.fill_shape == App.FillShape.DIAMOND:
		pts.append(Vector2(fw * 0.5, 0.0))
		pts.append(Vector2(fw, fh * 0.5))
		pts.append(Vector2(fw * 0.5, fh))
		pts.append(Vector2(0.0, fh * 0.5))
	else:
		var c: Vector2 = Vector2(fw * 0.5, fh * 0.5)
		for i in range(10):
			var t: float = TAU * float(i) / 10.0 - PI * 0.5
			var reach: float = 0.5 if i % 2 == 0 else 0.21
			pts.append(c + Vector2(cos(t) * fw * reach, sin(t) * fh * reach))
	return SelectionMask.polygon(pts, Vector2i.ZERO, w, h)
