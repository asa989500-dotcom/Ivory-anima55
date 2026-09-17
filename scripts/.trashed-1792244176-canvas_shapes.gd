class_name CanvasShapes
extends RefCounted
## Straight lines, chains and polylines: where a shape begins and where it
## ends.
##
## Lifted out of `canvas_view.gd` at stage 153, unchanged apart from being
## given the canvas by name instead of by `self`. That file is one of the
## project's long-standing debts and the size ledger's rule is that a long file
## may grow only if the growth is paid for out of another — so the panel
## confinement it gained is paid for here.
##
## It lifts along a real seam. Everything in it is about the two ends of a
## shape being dragged out, and nothing else in the canvas needs to know how a
## chain decides which end to start from.

static func begin(host: CanvasView, w: Vector2) -> void:
	if App.shape_mode == App.Shape.CHAIN:
		# The free one, then every one after it — beginning wherever on the
		# drawing your finger came down, not only at the last line's tip.
		#
		# The far end of the previous line still wins when you are near it,
		# because that is the common case and it should be the easiest: it
		# is checked first and only beaten by something genuinely closer.
		if host.chain_live:
			var tip: float = w.distance_to(host.chain_anchor)
			# Not `snapped`: GDScript has a built-in function by that name,
			# and a local that hides it means the next person to want real
			# snapping in this function gets a Vector2 back from what looks
			# like a call.
			var pinned: Vector2 = host.chain_snap(w)
			host._shape_a = host.chain_anchor if tip <= w.distance_to(pinned) \
				else pinned
		else:
			host._shape_a = host.chain_snap(w)
		host._shape_b = w
		host._shape_active = true
		host.overlay.queue_redraw()
		return
	if App.shape_mode == App.Shape.POLYLINE:
		host._poly_drag = host._nearest_point(w)
		if host._poly_drag < 0:
			host.poly_points.append(w)
			host._poly_drag = host.poly_points.size() - 1
		host._shape_active = true
		host.overlay.queue_redraw()
		return
	host._shape_active = true
	host._shape_a = w
	host._shape_b = w
	host.overlay.queue_redraw()

static func finish(host: CanvasView, w: Vector2) -> void:
	if App.current_tool == App.Tool.FILL:
		host._shape_b = w
		host._shape_active = false
		host._commit_fill_shape()
		return
	if App.shape_mode == App.Shape.POLYLINE:
		host._poly_drag = -1
		host._shape_active = false
		host.overlay.queue_redraw()
		return
	if App.shape_mode == App.Shape.CHAIN:
		host._shape_b = w
		host._shape_active = false
		# A tap that went nowhere is a tap, not a line. Without this a
		# stray touch would lay a zero-length segment and move the anchor
		# on top of itself, which looks like the chain has stopped working.
		if host._shape_a.distance_to(host._shape_b) < 0.75:
			host.overlay.queue_redraw()
			return
		host.commit_shape()
		host.chain_marks.append(host._shape_a)
		host.chain_marks.append(host._shape_b)
		host.chain_anchor = host._shape_b
		host.chain_live = true
		host.overlay.queue_redraw()
		return
	host._shape_b = ShapeGeometry.corrected_endpoint(App.shape_mode, host._shape_a, w)
	host._shape_active = false
	host.commit_shape()

## Lets go of the chain, so the next line is free again.
##
## Called from the panel's own button, and whenever the tool or the layer
## changes — a chain that survived a change of layer would start the next
## line from a point on a drawing that is no longer in front of you.
## Whether a hand is in the middle of something.
##
## Asked by the autosave before it writes: a save is tens of milliseconds of
## disk work, and putting that in the middle of a stroke puts a visible hitch
## in the stroke. It is also exactly when the timer is most likely to come
## round, because drawing is when documents become dirty in the first place.
##
## Every gesture that would be spoiled by a pause is here, not only drawing.
## A pin being pulled, a selection being dragged, a shape being stretched and
## the writing being turned all move under the finger, and all of them show a
## hitch the same way. A save that waits a second for any of them costs
## nothing; one that does not costs the mark being made.
