class_name Dismiss
extends RefCounted
## Tap away from a floating panel and it goes away.
##
## ## Why this is a shared thing and not a line in each panel
##
## `main.gd` has had this behaviour for a long time, and it works: a full-rect
## `Control` sits behind whatever is mounted, and a tap that both starts and
## ends on it closes the panel. But it belongs to `main.gd`, so only panels
## that go through `_mount` get it. Every panel built anywhere else — a size
## chooser floating over a form, a colour popover, a small chooser hung off a
## button — has to be closed with the button that opened it, and the first
## thing anybody does is tap somewhere else and wonder why the panel is still
## there.
##
## So the behaviour is lifted out to here, where a panel gets it in one line:
##
##     Dismiss.watch(pop, func() -> void: pop.visible = false)
##
## ## Both ends of the tap, not just the press
##
## Closing on the press alone is the obvious build and it is wrong for a
## reason that only shows up on a phone. A finger scrolling a list inside the
## panel drifts past the panel's edge and releases out here — and the panel
## the person was reading vanishes under their finger. So a tap only counts if
## the press and the release are both outside and close together. A drift is
## not a tap.
##
## ## What it deliberately does not do
##
## It does not dim, block or grey anything. The catcher is fully transparent
## and exists only to notice a tap. A panel that wants a dimmed backdrop can
## put one there itself; making that decision here would force it on every
## small popover in the app.

## How far the finger may travel between press and release and still be a tap.
## Rather more than a mouse would need, because a finger on glass never lands
## and lifts in exactly the same place.
const SLIP: float = 28.0

## Watches for a tap outside `panel` and calls `on_close` when one happens.
##
## The catcher is added as a sibling directly beneath the panel in its parent,
## so it covers everything the panel does not and nothing the panel does. It
## lives and dies with the panel: freeing the panel frees this too, and there
## is nothing for the caller to clean up.
##
## Returns the catcher, for the rare caller that wants to move or disable it.
static func watch(panel: Control, on_close: Callable) -> Control:
	if panel == null or not on_close.is_valid():
		return null
	var parent: Node = panel.get_parent()
	if parent == null:
		return null

	var catcher: Control = Control.new()
	catcher.name = "DismissCatcher"
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	# Transparent. This is a listener, not a curtain.
	catcher.modulate = Color(1, 1, 1, 0)
	catcher.z_index = maxi(panel.z_index - 1, 0)
	catcher.top_level = panel.top_level

	var state: Dictionary = {"armed": false, "from": Vector2.ZERO}
	catcher.gui_input.connect(func(event: InputEvent) -> void:
		if not panel.is_inside_tree() or not panel.visible:
			return
		var pressed: bool = false
		var down: bool = false
		var at: Vector2 = Vector2.ZERO
		if event is InputEventScreenTouch:
			var touch: InputEventScreenTouch = event
			pressed = true
			down = touch.pressed
			at = touch.position
		elif event is InputEventMouseButton:
			var click: InputEventMouseButton = event
			if click.button_index != MOUSE_BUTTON_LEFT:
				return
			pressed = true
			down = click.pressed
			at = click.position
		if not pressed:
			return
		if down:
			state["from"] = at
			state["armed"] = true
			return
		if not bool(state["armed"]):
			return
		state["armed"] = false
		# A drift is not a tap. See the note at the top of the file.
		if Vector2(state["from"]).distance_to(at) <= UiKit.s(SLIP):
			on_close.call())

	parent.add_child(catcher)
	# Directly under the panel: above whatever the panel is floating over, so
	# a tap there is caught rather than reaching through, and below the panel
	# itself, so a tap on the panel is never caught.
	var seat: int = maxi(panel.get_index(), 0)
	parent.move_child(catcher, seat)

	# The catcher belongs to the panel. When the panel goes, so does this —
	# otherwise a transparent, input-stopping rectangle is left over the whole
	# screen and nothing anywhere responds, which is a fault that is very hard
	# to look at and see.
	panel.tree_exiting.connect(func() -> void:
		if is_instance_valid(catcher):
			catcher.queue_free())

	# A panel that is hidden rather than freed should not keep catching taps.
	panel.visibility_changed.connect(func() -> void:
		if is_instance_valid(catcher):
			catcher.visible = panel.visible)
	catcher.visible = panel.visible
	return catcher
