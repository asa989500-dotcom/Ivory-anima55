class_name TimelinePoseFrames
extends RefCounted
## Duplicate After, for layers that are posed rather than redrawn.
##
## Lifted out of `timeline_panel.gd` at stage 145. The panel still calls
## `_duplicate_pose_forward` and `_carry_pose`; both delegate here.
##
## The rule: the frame button on a rigged layer does not make a blank frame
## and does not merely walk the playhead on. It carries the pose at the
## playhead onto the next frame and puts a key there — the same pose, one
## frame later, as a place to change something. A blank key on a rigged layer
## would be the character collapsing to its rest pose for one frame, which is
## the most alarming thing a timeline can do.

## Carries the pose at the playhead onto the next frame, and moves there.
##
## Returns false when there was no pose to carry — an animation folder with
## nothing rigged inside it, or a bone layer that has not been posed yet — so
## the caller can fall back to simply stepping on.
static func duplicate_pose_forward(host: TimelinePanel) -> bool:
	if host.stack == null or host.player == null or host.clip == null:
		return false
	var index: int = host.stack.active_index
	if index < 0 or index >= host.stack.layers.size():
		return false
	var l: LayerStack.Layer = host.stack.layers[index]
	if l.poses == null or l.poses.is_empty():
		return false
	var frame: int = clampi(int(floor(host.player.frame + 0.000001)), 0,
		maxi(host.clip.length - 1, 0))
	var target: int = frame + 1
	if target >= host.clip.length:
		host.clip.grow_to_fit(host.stack, target)
	var before: Array = host.stack.snapshot_state()
	host._carry_pose(l, frame, target)

	# A Character 360 file moves as one block, so every layer in it has to
	# arrive at the new frame together. Carrying only the layer that
	# happened to be selected would leave the rest of the character a frame
	# behind — the drawing in one place and its own outline in another.
	var gid: int = host.stack.character360_group(index)
	if gid != 0:
		for other in host.stack.layers_in_group(gid):
			if other != l:
				host._carry_pose(other, frame, target)

	host.stack.record_state(UiKit.label_for("Duplicate pose after",
		"تكرار الوضعية للإطار التالي"), before)
	host.player.frame = float(target)
	host.player.onion = true
	host.player.onion_back = maxi(host.player.onion_back, 1)
	host.player.refresh_visuals()
	host.stack.changed.emit()
	host._dirty()
	host.rebuild()
	host._tell_row(UiKit.label_for("Pose duplicated onto the next frame",
		"تم تكرار الوضعية في الإطار التالي"))
	return true

## Duplicate After carries the *pose* forward as well as the drawing.
##
## This is the join between the two halves of the app, and it was missing.
## The bones live on the layer's `poses` track beside the puppet pins, and
## duplicating a frame without them meant the drawing arrived at the new frame
## while the skeleton stayed behind on the old one — so the very next bend
## keyed a pose with no previous key to travel from.
##
## Carried, not blended. Duplicate After exists to give you *the same thing,
## one frame later*, as a place to change something — so the new key is an
## exact copy of the old one and the tween between them is flat until you move
## something. That is what an animator means by duplicating a frame.
##
## Nothing is created for a layer that has no poses. An unrigged drawing stays
## an unrigged drawing, and no empty key appears on the band to be wondered at.
static func carry_pose(l: LayerStack.Layer, frame: int, target: int) -> void:
	if l == null or l.poses == null or l.poses.is_empty():
		return
	if l.poses.has_key(target):
		return
	# Read at `frame` rather than from the key at `frame`: the drawing being
	# duplicated may sit between two keys, and what should carry forward is
	# the pose that was on screen, not the last one that happened to be
	# written down.
	var pose: Dictionary = l.poses.pose_at(float(frame))
	if pose.is_empty():
		return
	var made: RigTrack.RigKey = l.poses.touch(target)
	if pose.has("bones"):
		made.bones = pose["bones"]
	if pose.has("pins"):
		made.pins = pose["pins"]
