class_name AiBridge
extends RefCounted
## Where the model meets the canvas.
##
## The joining, and only the joining: taking the drawing off a layer, putting
## a picture back onto one, and opening the design room. Everything about
## tokens, waiting, retrying and decoding is in `ai_assistant.gd`, and
## everything about the conversation is in `ai_room.gd`.
##
## It is a separate file because `tools/check_size.py` said so. Adding the AI
## joining to `main.gd` pushed it a hundred and seventy lines past its
## recorded ceiling and the build stopped — which is precisely what that
## ledger is for, on its first real outing. The section came straight back out
## with `tools/lift_module.py` and `main.gd` is the size it was.
##
## The lift also found a fault in the lifting tool, which is worth writing
## down: the rewrite was reaching inside string literals, so `open_panel =
## "ai"` became `open_panel = "p.ai"` and `call_deferred("_fit_panel_to_content")`
## — a method named as text — was pointed at a method that does not exist.
## Both parse. Both fail on a tablet. The tool now puts strings aside before
## it rewrites anything, and `call_deferred` is on the list of inherited calls
## it knows to prefix.

## The drawing on a layer, as an ordinary picture the model can be shown.
##
## The whole layer, cropped to what is actually drawn — sending the empty
## space around a sketch wastes most of the resolution the model has to work
## with, and a figure in the corner of a blank sheet comes back as a figure in
## the corner of a blank sheet.
static func layer_sketch(host: MainRoom, index: int) -> Image:
	var p: ProjectManager.Project = host.current_project()
	if p == null or p.stack == null:
		return null
	if index < 0 or index >= p.stack.layers.size():
		return null
	var l: LayerStack.Layer = p.stack.layers[index]
	if l.surface == null:
		return null
	var whole: Rect2i = l.surface.content_bounds()
	if whole.size.x <= 1 or whole.size.y <= 1:
		return null
	# A little air around it, so an outline is not cut off at the edge.
	whole = whole.grow(int(maxf(float(maxi(whole.size.x, whole.size.y))
		* 0.04, 8.0)))
	return l.surface.read_region(whole)

## Improving the drawing on a layer — the entrance in the layer's own
## settings.
##
## The words are deliberately about *drawing* rather than about subject
## matter. What was asked for is cleaner linework and a steadier sense of
## where the shapes are going, not a different picture, so the description
## says exactly that and the strength is kept low enough that the drawing
## stays the artist's.
static func improve_layer(host: MainRoom, index: int) -> void:
	if host.ai == null:
		return
	var sketch: Image = host._layer_sketch(index)
	if sketch == null:
		host._flash(UiKit.label_for("There is nothing drawn on that layer",
			"لا يوجد رسم على تلك الطبقة"))
		return
	host._improving = index
	host._close_panel()
	host.ai.improve(sketch, "clean refined line art of the same drawing, "
		+ "smooth confident strokes, corrected proportions and perspective, "
		+ "the same subject, the same composition, the same colours, "
		+ "crisp inking, transparent background",
		0.38, {"from": "layer"})
	host._flash(UiKit.label_for("Improving — it will arrive on a new layer",
		"جارٍ التحسين — ستصل على طبقة جديدة"))

## Where an answer goes, once it arrives.
static func on_ai_picture(host: MainRoom, _id: int, picture: Image, _texture: ImageTexture,
		job: Dictionary) -> void:
	var tag: Dictionary = job.get("tag", {})
	if String(tag.get("from", "")) != "layer":
		return
	host._place_ai_picture(picture, true)

## An AI picture onto the canvas.
##
## An improvement lands on **a layer of its own, called the improvement
## layer**, never on top of the drawing it came from. It is an ordinary layer
## in every respect — it can be drawn on, hidden, merged, deleted — and the
## name is there only so it can be told apart at a glance. That is the whole
## of the protection the artist needs: the original is still underneath,
## untouched, and the two can be compared by tapping the eye.
static func place_ai_picture(host: MainRoom, picture: Image, own_layer: bool) -> void:
	if picture == null:
		return
	var p: ProjectManager.Project = host.current_project()
	if p == null or p.stack == null:
		host._flash(UiKit.label_for("Open a project first", "افتح مشروعاً أولاً"))
		return
	var stack: LayerStack = p.stack
	# `active_index`, not `active`: the second is the method that returns
	# the Layer, and naming it without its brackets hands over a Callable
	# rather than a number.
	var index: int = stack.active_index
	if own_layer:
		var made: LayerStack.Layer = stack.add_layer()
		if made == null:
			host._flash(UiKit.label_for("There was no room for another layer",
				"لا مجال لطبقة أخرى"))
			return
		made.title = UiKit.label_for("Improvement layer", "طبقة التحسين")
		index = stack.layers.find(made)
		if index < 0:
			index = stack.active_index
	stack.set_active(index)

	# Sized to sit inside the page, like every other picture arriving from
	# outside, and floating rather than fixed — it is a proposal until the
	# artist puts it down.
	var art: Image = picture.duplicate()
	var room: Vector2 = p.page * 0.92
	var factor: float = minf(room.x / maxf(float(art.get_width()), 1.0),
		room.y / maxf(float(art.get_height()), 1.0))
	if factor < 0.999:
		art.resize(maxi(int(float(art.get_width()) * factor), 1),
			maxi(int(float(art.get_height()) * factor), 1),
			Image.INTERPOLATE_LANCZOS)
	host.view.float_image(art, stack.layers[index].id, p.page * 0.5)
	host.view.projects.mark_dirty(p)
	host._improving = -1
	host._flash(UiKit.label_for("Drag it, then Place", "حرّكها ثم ثبّت"))

## The design room, from the compass.
static func open_ai_room(host: MainRoom) -> void:
	host._close_panel()
	if host.ai == null:
		return
	host._ai_room = AiRoom.new()
	host._ai_room.build(host.ai)
	host._ai_room.closed.connect(host._close_panel)
	host._ai_room.wants_place.connect(func(picture: Image) -> void:
		host._place_ai_picture(picture, true))
	host._ai_room.wants_import.connect(func() -> void:
		host._import_for_ai = true
		host._ask_for_image(-1))
	# The room asks the canvas for the drawing rather than reaching into it,
	# and the answer comes back in the basket it passed in.
	host._ai_room.wants_layer_sketch.connect(func(basket: Array) -> void:
		var p: ProjectManager.Project = host.current_project()
		if p == null or p.stack == null:
			return
		basket.append(host._layer_sketch(p.stack.active_index)))

	host._show_shade(true)
	host.panel_host = host._ai_room
	host.panel_host.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	host.panel_host.set_meta("desired_width", UiKit.s(420.0))
	host._ui.add_child(host.panel_host)
	host.panel_host.resized.connect(host._layout)
	host.open_panel = "ai"
	host._fit_panel_to_content()
	host._layout()
	host.call_deferred("_fit_panel_to_content")
