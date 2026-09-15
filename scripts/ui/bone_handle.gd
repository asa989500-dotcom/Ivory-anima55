class_name BoneHandle
extends RefCounted
## Posing a rigged layer by dragging its joints, on the canvas itself.
##
## ## The gap this closes
##
## A layer could be given a skeleton and there was nowhere to *use* it without
## going back into a room. The canvas drew the joints — `canvas_marks` has
## drawn them for several stages — and nothing on the canvas ever listened for
## a finger landing on one. They were a picture of a control rather than a
## control.
##
## So: lay the bones on a layer, accept them, and from that moment the drawing
## is moved by taking hold of its own joints where it sits. No room, no mode,
## no tool to select first. That is the whole of what was asked for by "it is
## moved by its own points", and it is also how Moho, Spine and every rig
## before them behave — you pose the thing where it lives.
##
## ## Why the drawing follows without being redrawn
##
## Nothing is stamped into the layer while it is being posed. A `RigSkin` — a
## mesh carrying a picture of the layer — stands in front of it and bends,
## while the layer behind is hidden and untouched. Posing a figure must not be
## capable of damaging the drawing, and the only way to guarantee that is for
## the drawing never to be written to.
##
## The skin is put on once, at the moment the first joint is caught, and
## reshaped after that. Building it means reading the layer's pixels back off
## its surface, which is precisely the thing that must not happen per frame.
##
## ## Why it is static
##
## `canvas_view.gd` is one of the longest files in the project and the
## discipline there is that it may not grow. This is the whole feature; the
## canvas holds three fields and calls three functions.

## What is being dragged, if anything: `[layer id, bone index, which end]`.
static var _grab: Array = []
## The bones of the layer being posed, live, as `BoneRig.Bone`.
static var _bones: Array = []
## Whether this drag has actually moved anything, so a tap that misses costs
## nothing and a tap that lands does not write an identical pose back.
static var _moved: bool = false
## Ignore sub-pixel aim changes. A joint is a structural control; reacting to
## every digitizer quantisation step is what produces the visible micro-shake.
const MOTION_EPS_PX: float = 0.8
static var _last_target: Vector2 = Vector2.INF
## The document before this drag began, held so the whole drag is one entry
## on the undo stack.
static var _before: Array = []
## How far the drawing has moved since these bones were laid on it, so the
## skeleton is found and drawn where the figure actually is.
static var _home: Vector2 = Vector2.ZERO

## How long the figure has to be left alone after a pose before that pose
## becomes a keyframe with a mark on the band.
##
## ## Why a pose is not keyed the instant a finger lifts
##
## It used to be, and the result was a band filling up with keys nobody had
## asked for. Posing a figure is not one movement: it is a shoulder, then the
## elbow, then the shoulder again because the elbow changed how it looked,
## then the wrist. Every one of those lifts wrote a key on the current frame.
## They all land on the same frame, so each simply overwrote the last, and the
## band showed a mark for a frame the person had not finished deciding about —
## and when they *did* move to another frame, they found keys behind them they
## did not remember making.
##
## A second of stillness is the difference between adjusting and deciding. The
## pose is on the figure the whole time — nothing waits, nothing springs back,
## and the timeline knows about it — but the *mark* only appears once the hand
## has stopped, which is what makes a mark mean "this frame is one I chose".
const KEY_DWELL_MS: int = 1000

## The pose waiting to become a key: the layer, the frame, and when the hand
## last let go. Empty when there is nothing pending.
static var _pending_layer: int = -1
static var _pending_frame: int = -1
static var _pending_since: int = 0

## How near a finger must be to catch a joint, in screen pixels.
##
## Larger than the room's own reach, because out here the joint is competing
## with a brush: a near miss in a room does nothing, and a near miss on the
## canvas draws a line across the figure. Being generous costs a stroke that
## has to be started again a few pixels further off; being mean costs a
## drawing with a stroke through it.
const GRAB_PX: float = 26.0

## Whether this layer is one that gets posed rather than drawn on.
static func rigged(l: LayerStack.Layer) -> bool:
	if l == null or not l.visible or l.locked:
		return false
	return not (l.rig as Dictionary).get("bones", []).is_empty()

static func posing() -> bool:
	return not _grab.is_empty()

# ------------------------------------------------------------------- input

## Takes hold of a joint under the finger, if there is one.
##
## Returns true when the canvas should treat this touch as a pose and keep
## every tool away from it. False means nothing was near enough and the finger
## goes on to mean whatever it usually means.
static func grab(view: CanvasView, screen: Vector2, touch_only: bool = true) -> bool:
	if not touch_only:
		return false
	drop(view)
	# A filter carrying the velocity of the last drag would fling the first
	# frame of the next one. Bone joints are controls, not ink, so they get a
	# slightly steadier native one-euro profile than freehand drawing.
	# Bones are structural controls, not ink. A small screen-space deadband
	# rejects digitizer tremor while the one-euro filter keeps real motion live.
	_aim.configure(1.35, 0.018, 1.6, 3.5, MOTION_EPS_PX)
	_aim.reset()
	if view == null or view.layers == null:
		return false
	var l: LayerStack.Layer = view.layers.active()
	if not rigged(l):
		return false

	var bones: Array = BoneRig.from_rows((l.rig as Dictionary)["bones"])
	if bones.is_empty():
		return false
	# The same shift the overlay draws with, so what is under the finger is
	# what is under the mark. These two disagreeing is worse than either being
	# wrong: the skeleton would be visible in one place and grabbable in
	# another.
	_home = BoneRig.anchor_shift(l.rig as Dictionary, BoneRig.ink_of(l))
	# The reach is measured on the screen and converted, so the target is the
	# same size under the finger at every zoom. In canvas units it would be a
	# hand's width zoomed out and nothing at all zoomed in.
	var reach: float = UiKit.s(GRAB_PX) / maxf(view.view_zoom, 0.000001)
	var found: Array = BoneRig.joint_at(bones,
		view.screen_to_canvas(screen) - _home, reach)
	if found.is_empty():
		return false

	# --- the stand-in is wanted, and is not required ---
	#
	# This used to refuse the grab outright when the skin could not be built,
	# and that single line is the whole of "the bones cannot be moved after
	# they are added". A skin is built by reading the layer's pixels back off
	# its surface, and that fails for perfectly ordinary reasons — the surface
	# not yet mounted on the frame the finger landed on, a layer whose art is
	# still being loaded, a device that refused the texture. In every one of
	# those cases the *skeleton* was fine and the pose was refused anyway, so
	# the joints sat there looking like controls and did nothing when touched.
	#
	# A missing skin costs the live preview of the drawing bending. It does
	# not cost the pose: the bones move, the pose is written, and the picture
	# catches up the moment a skin can be built. Refusing the whole gesture to
	# avoid a missing preview is trading the feature for the animation of the
	# feature.
	view.layers.wear_skin(l, 32 if Perf.rig_solve_stride() == 1 else 16)
	_bones = bones
	# The native solver, if the library is here. It is handed the skeleton
	# once per grab and asked hundreds of times per grab, which is the whole
	# reason it is worth crossing the boundary for at all.
	_fast = Native.bones()
	if _fast != null:
		_hand_over()
	_grab = [l.id, int(found[0]), int(found[1])]
	_moved = false
	_last_target = Vector2.INF
	# The document as it stands, taken now and kept until the finger lifts.
	#
	# One entry for one gesture. A joint dragged across the screen fires
	# hundreds of events and is one thing the person did, so recording per
	# event would bury every earlier action under a wall of identical steps
	# and make undo useless exactly where it is most wanted.
	_before = view.layers.snapshot_state()
	return true

## Follows the finger. Smooth by construction — the angle is taken straight
## off the touch with nothing rounded and no step to fall into.
## What the finger meant, from what the screen reported.
##
## A joint is a control being *aimed*, not a record of where a hand went — so
## it gets the jitter taken off and the panel's own latency taken back, the
## same treatment a warp pin gets. Ink is deliberately not given this: a stroke
## that ran ahead of the finger would be ink that was never drawn. See
## `touch_lead.gd`.
static var _aim: TouchLead = TouchLead.new()

## The C++ skeleton for this drag, or nothing. See `native.gd` — every caller
## asks whether it is there rather than asking Godot, and the GDScript below
## is what runs when it is not.
static var _fast: Object = null

## Hands the bones over to the native solver.
##
## Flat arrays, because that is what crosses the boundary cheaply: three
## parallel arrays rather than a dozen objects, built once here and read
## thousands of times over there.
static func _hand_over() -> void:
	if _fast == null:
		return
	var head: PackedVector2Array = PackedVector2Array()
	var tail: PackedVector2Array = PackedVector2Array()
	var parent: PackedInt32Array = PackedInt32Array()
	var lo: PackedFloat32Array = PackedFloat32Array()
	var hi: PackedFloat32Array = PackedFloat32Array()
	for one in _bones:
		var b: BoneRig.Bone = one as BoneRig.Bone
		head.append(b.a)
		tail.append(b.b)
		parent.append(b.parent)
		# An unlimited joint is handed a full turn either way, which the
		# native side spots and skips. A limit of exactly pi would be a real
		# limit and would cost a comparison per bone per solve for nothing.
		lo.append(b.limit_low if b.limited() else -TAU)
		hi.append(b.limit_high if b.limited() else TAU)
	_fast.set_skeleton(head, tail, parent)
	_fast.set_limits(lo, hi)

## Reads the solved skeleton back onto the GDScript bones.
##
## ## Why the positions are not simply copied across
##
## `a` and `b` are *derived*. `BoneRig.solve` is the only thing in the app
## allowed to write them, from `turn` and `shift`, and everything that saves,
## loads, keys or interpolates a pose reads those two and not the positions.
## Writing `a` and `b` straight from the solver would therefore look right on
## screen and be gone the next time anything called `solve` — which is every
## frame of playback and every load from disk. The pose would appear to take
## and then silently revert, which is a worse bug than not moving at all.
##
## So the solved positions are turned back into turns, and `solve` is asked to
## re-derive the positions from those. One source of truth, and the native
## side stays a calculator rather than becoming a second place a pose lives.
static func _read_back() -> void:
	if _fast == null:
		return
	var head: PackedVector2Array = _fast.head()
	var tail: PackedVector2Array = _fast.tail()
	var count: int = mini(_bones.size(), mini(head.size(), tail.size()))
	# Parents before children: a child's turn is measured against its
	# parent's heading, so the parent's has to be known first.
	var world: PackedFloat32Array = PackedFloat32Array()
	world.resize(_bones.size())
	world.fill(0.0)
	for index in BoneRig.order(_bones):
		if index >= count:
			continue
		var b: BoneRig.Bone = _bones[index] as BoneRig.Bone
		var span: Vector2 = tail[index] - head[index]
		if span.length_squared() < 0.000001:
			continue
		var heading: float = span.angle() - b.rest_angle()
		world[index] = heading
		if b.parent >= 0 and b.parent < _bones.size():
			b.turn = heading - world[b.parent]
		else:
			b.turn = heading
			# Only a root carries a bodily shift. A child's place is its
			# parent's tip and is worked out rather than stored.
			b.shift = head[index] - b.rest_a
	BoneRig.solve(_bones)

static func drag(view: CanvasView, screen: Vector2, pressure: float = 1.0) -> void:
	if _grab.is_empty() or view == null:
		return
	var index: int = int(_grab[1])
	var which: int = int(_grab[2])
	_aim.sample_pressure(pressure)
	var to: Vector2 = view.screen_to_canvas(_aim.at(screen)) - _home
	var target_screen: Vector2 = view.canvas_to_screen(to + _home)
	if _last_target != Vector2.INF and target_screen.distance_squared_to(_last_target) < MOTION_EPS_PX * MOTION_EPS_PX:
		return
	_last_target = target_screen

	if _fast != null:
		# One call for the whole solve. The chain is walked, reached and
		# re-hung on the other side of the boundary, so a drag costs one
		# crossing per touch event rather than one per bone per event.
		var handled: bool = false
		if which == 1 and (_bones[index] as BoneRig.Bone).parent >= 0:
			var current_bone: BoneRig.Bone = _bones[index] as BoneRig.Bone
			var parent_bone: BoneRig.Bone = _bones[current_bone.parent] as BoneRig.Bone
			# The pole is taken from the current elbow, not from a fixed screen
			# direction. This preserves the existing bend through the straight
			# singularity and prevents midpoint/two-pole sign chatter.
			var pole: Vector2 = parent_bone.b
			handled = _fast.reach_pole(index, to, pole,
				3 if Perf.headroom > 0.5 else 1)
		if not handled:
			_fast.swing(index, which, to)
		_fast.limit_all()
		_read_back()
		_moved = true
		_show(view)
		return

	# Dragging the far end of a bone that hangs from others is a *reach*: the
	# hand goes where the finger goes and the joints between work themselves
	# out. Anything else is a plain swing.
	#
	# Which reach depends on how long the chain is, and both are here because
	# neither is better everywhere:
	#
	#   **Two bones** — closed form. One triangle, solved exactly, the same
	#   answer every time for the same input, no iteration and nothing to
	#   tune. Nothing beats it for an upper arm and a forearm, which is most
	#   of what anybody rigs.
	#
	#   **Three or more** — FABRIK. A finger, a tail, a spine, a hind leg: a
	#   triangle cannot describe them and IVORY previously had no answer at
	#   all, so they had to be posed one joint at a time. See
	#   `BoneSolver.reach_chain`.
	#
	# Passes are rationed by what the device has spare. A chain starts each
	# event from where the last one left it and a finger travels a few pixels
	# between events, so one sweep is very nearly convergence already; the
	# extra passes are polish, and polish is the right thing to drop first on
	# a device that is struggling.
	var done: bool = false
	if which == 1 and (_bones[index] as BoneRig.Bone).parent >= 0:
		var chain: PackedInt32Array = BoneSolver.chain_of(_bones, index)
		if chain.size() > 2:
			done = BoneSolver.reach_chain(_bones, index, to,
				3 if Perf.headroom > 0.5 else 1)
		else:
			var lower: BoneRig.Bone = _bones[index] as BoneRig.Bone
			var upper: BoneRig.Bone = _bones[lower.parent] as BoneRig.Bone
			# Keep the current bend side through the near-straight singularity.
			done = BoneRig.reach(_bones, index, to)
	if not done:
		BoneRig.swing(_bones, index, which, to)
	# Held inside whatever arc each joint is allowed. Without this the solver
	# is free to fold an elbow backwards through a shoulder to satisfy a
	# distance, which is the single commonest complaint about inverse
	# kinematics everywhere and is not the solver's fault: it was never told
	# the joint had a front and a back.
	BoneSolver.limit_all(_bones)
	_moved = true
	_show(view)

## Lets go, and writes the pose onto the layer.
##
## The pose is kept. Letting go and having the figure spring back to where it
## was drawn would make every adjustment a thing you have to hold — and the
## bones are part of the drawing now, so where they stand is part of what the
## drawing is.
static func release(view: CanvasView) -> void:
	if _grab.is_empty():
		return
	if _moved and view != null and view.layers != null:
		var l: LayerStack.Layer = view.layers.by_id(int(_grab[0]))
		if l != null:
			view.layers.record_state(
				UiKit.label_for("Pose", "تحريك العظام"), _before)
			var doc: Dictionary = (l.rig as Dictionary).duplicate(true)
			doc["bones"] = BoneRig.to_rows(_bones)
			# Rebuilt from the same bones rather than carried over, so the
			# flat arrays the skin reads can never fall out of step with the
			# skeleton they came from.
			doc["bones_rest"] = BoneRig.rest_skeleton(_bones)
			l.rig = doc
			# Held, not written. See `KEY_DWELL_MS`: the pose is on the
			# figure and on the layer from this moment, but it does not
			# become a mark on the band until the hand has been off it for
			# a second. Moving the same joint again inside that second
			# simply restarts the clock, so a minute of adjusting one pose
			# leaves one key rather than forty.
			_pending_layer = l.id
			_pending_frame = 0
			if view.player != null:
				_pending_frame = maxi(int(floor(view.player.frame + 0.000001)), 0)
			_pending_since = Time.get_ticks_msec()
			# --- and it is written to disk ---
			#
			# This one line is the whole of "everything goes back to how it
			# was when I come back to the app". Nothing else here was wrong:
			# `vault.gd` has always saved a layer's rig, `record_state` has
			# always put the pose on the undo stack, and both worked. But
			# neither of them tells the project it has unsaved work in it, and
			# autosave only ever writes projects that say they have. So a
			# figure could be posed all afternoon, every pose correctly
			# recorded in memory, and none of it reached the file — the app
			# reopened showing the last pose that happened to be saved for
			# some *other* reason, which is exactly the report of bones that
			# forget themselves.
			#
			# Marked on release rather than on every drag event, because a
			# drag is one thing the person did and a hundred writes a second
			# is not a save policy.
			if view.projects != null:
				view.projects.mark_dirty(view.projects.active)
	_grab = []
	_moved = false
	_before = []
	_fast = null
	_last_target = Vector2.INF
	if view != null and view.overlay != null:
		view.overlay.queue_redraw()

## Writes the pose that was just made into the layer's own timeline track.
##
## ## The gap this closes
##
## Posing on the canvas wrote the bones onto the layer and stopped there. The
## only thing in the app that ever wrote a *key* was the B-Spline room — so a
## figure posed where it lives had one pose, the last one, and moving the
## playhead did nothing at all. Bones and the timeline were two features that
## did not know about each other, and the missing line between them was this
## one. Bend the arm at frame 1, walk to frame 20, bend it again, and the app
## fills in every frame between: that is the whole of bone animation, and it
## was one call away.
##
## ## Only where a key means something
##
## Nothing is written when there is no scene to write into, and nothing is
## written on the first pose of a track that has none — the *rest* is already
## the pose at every frame, and a lone key at frame 12 saying "as drawn" is a
## key that changes nothing and has to be found and deleted later.
##
## The first key on an empty track therefore lays two: one at frame nought
## holding the drawing as it rests, and one here holding what was just done.
## That is what makes the very first bend a movement rather than a jump — the
## figure travels from where it was drawn to where it was put, across every
## frame between, without anybody having had to key the start.
static func _key_it(view: CanvasView, l: LayerStack.Layer) -> void:
	if view.player == null or view.projects == null:
		return
	if view.projects.active == null or view.projects.active.clip == null:
		return
	var frame: int = maxi(int(floor(view.player.frame + 0.000001)), 0)
	if l.poses == null:
		l.poses = RigTrack.new()
	if l.poses.is_empty():
		if frame == 0:
			# The only pose there is. Keying it alone would be a track with
			# one key in it, which plays as a figure that never moves.
			RigTrack.take_bones(l.poses, 0, BoneRig.from_rows(
				(l.rig as Dictionary).get("bones", [])))
			_rest_key(l)
			return
		_rest_key(l)
	RigTrack.take_bones(l.poses, frame, _bones)
	if view.puppet_active and view.puppet != null \
			and not view.puppet.pins.is_empty():
		RigTrack.take_pins(l.poses, frame, view.puppet.pins)
	# The ghosts are rebuilt only when their signature changes, and the
	# signature is made of the onion settings and the current frame — none of
	# which move when a pose is keyed on the frame already being looked at. So
	# a new pose would go on being ghosted as the old one until something else
	# happened to invalidate them. Forgetting them here is the one line that
	# makes onion skin follow a rig as it is posed.
	view.player.forget_ghosts()
	view.player.refresh_visuals()

## Called every frame by the canvas. Writes the waiting key once the hand has
## been still long enough.
##
## Cheap: two integer comparisons when there is nothing pending, which is
## almost always.
static func tick(view: CanvasView) -> void:
	if _pending_layer < 0:
		return
	if Time.get_ticks_msec() - _pending_since < KEY_DWELL_MS:
		return
	var layer_id: int = _pending_layer
	_pending_layer = -1
	if view == null or view.layers == null:
		return
	var l: LayerStack.Layer = view.layers.by_id(layer_id)
	if l == null:
		return
	_key_it(view, l)

## True while a pose is on the figure but has not yet become a key.
##
## The band asks, so it can show the frame as being worked on — a hollow mark
## rather than a filled one — instead of showing nothing at all and leaving
## the person wondering whether the movement took.
static func pending_key_frame(layer_id: int) -> int:
	if _pending_layer != layer_id:
		return -1
	return _pending_frame

## Writes any waiting key at once.
##
## Called when the moment to wait for has passed: the playhead moved, the
## layer changed, the project is being saved or closed. Waiting a second more
## in any of those cases would lose the pose, and the whole point of the delay
## is to avoid clutter, not to risk work.
static func flush(view: CanvasView) -> void:
	if _pending_layer < 0:
		return
	_pending_since = 0
	tick(view)

## Frame nought, holding the figure exactly as it was drawn.
static func _rest_key(l: LayerStack.Layer) -> void:
	if l.poses.has_key(0):
		return
	var flat: Array = BoneRig.from_rows((l.rig as Dictionary).get("bones", []))
	BoneRig.rest_all(flat)
	RigTrack.take_bones(l.poses, 0, flat)

## Ends any pose in progress, leaving the figure showing the pose that is
## actually recorded on it.
##
## Not the same as taking the stand-in away. The stand-in is how a posed layer
## is *seen*; shedding it here would drop the figure flat the instant a finger
## lifted, and the pose would still be on the layer with no sign of it on the
## screen. So the drag state is cleared and the picture is put back in step
## with the rig.
static func drop(view: CanvasView) -> void:
	# Whatever was waiting is written now rather than abandoned. `drop` is
	# called when the canvas changes underneath the pose — a different layer,
	# a different project — and a pose that vanished because the person tapped
	# elsewhere within the second would be the worst possible reading of a
	# feature meant to reduce clutter.
	flush(view)
	_grab = []
	_bones = []
	_fast = null
	_moved = false
	_before = []
	restore(view)

## Shows the active layer standing in whatever pose its rig records.
##
## Called after a skeleton is accepted and after a drag is abandoned, and safe
## to call at any other time: a layer with no bones is left completely alone,
## which means this can be reached for without first asking whether it
## applies.
static func restore(view: CanvasView) -> void:
	if view == null or view.layers == null:
		return
	var l: LayerStack.Layer = view.layers.active()
	if not rigged(l):
		return
	var bones: Array = BoneRig.from_rows((l.rig as Dictionary)["bones"])
	if bones.is_empty():
		return
	if not BoneRig.moved(bones):
		# Laid flat and never moved: there is nothing to stand in for, so the
		# layer draws itself and costs nothing.
		view.layers.shed_skin(l)
		return
	_bend(view, l, bones)

# ------------------------------------------------------------------ drawing

## Bends the stand-in to where the bones now are.
##
## Weighted by island, so a skeleton drawn on one figure cannot take hold of
## another drawing sharing the layer with it — see `RigSkin._read_islands`.
static func _show(view: CanvasView) -> void:
	if view == null or view.layers == null or _grab.is_empty():
		return
	var l: LayerStack.Layer = view.layers.by_id(int(_grab[0]))
	if l == null:
		return
	_bend(view, l, _bones)

## One layer's stand-in, bent to one set of bones.
static func _bend(view: CanvasView, l: LayerStack.Layer,
		bones: Array) -> void:
	var skin: RigSkin = l.skin
	if skin == null or not is_instance_valid(skin):
		skin = view.layers.wear_skin(l,
			32 if Perf.rig_solve_stride() == 1 else 16)
		if skin == null:
			return
	var rest: Dictionary = BoneRig.rest_skeleton(bones)
	var now: Dictionary = BoneRig.posed_ends(bones)
	var rest_a: PackedVector2Array = rest["a"]
	var rest_b: PackedVector2Array = rest["b"]
	# One call for the whole skin rather than one per point. See
	# `RigSkin.pose_bones` — the weighting is unchanged and the islands are
	# still what stop a skeleton on one figure taking hold of the drawing
	# beside it.
	skin.pose_bones(rest_a, rest_b, now["a"], now["b"])
	# Character 360 is a rigged *file*, not one magic layer: every drawing
	# inside its group receives the same master skeleton. Each member keeps its
	# own skin cache, so only vertices are updated; pixels are never copied.
	if l.is_character360 and l.group_id != 0:
		for member in view.layers.layers:
			if member == l or member.group_id != l.group_id or member.surface == null:
				continue
			if member.is_bone_layer or member.is_character360_motion:
				continue
			var member_skin: RigSkin = member.skin
			if member_skin == null or not is_instance_valid(member_skin):
				member_skin = view.layers.wear_skin(member, 32 if Perf.rig_solve_stride() == 1 else 16)
			if member_skin != null:
				member_skin.pose_bones(rest_a, rest_b, now["a"], now["b"])
	if view.overlay != null:
		view.overlay.queue_redraw()

## Whichever joint is under the finger right now, in canvas units, so the
## overlay can mark it. Empty while nothing is held.
static func held_at() -> Vector2:
	if _grab.is_empty():
		return Vector2.ZERO
	var one: BoneRig.Bone = _bones[int(_grab[1])] as BoneRig.Bone
	return _home + (one.b if int(_grab[2]) == 1 else one.a)

## The cross drawn through the held joint: the bone's own direction, and the
## direction square to it. Empty while nothing is held.
##
## ## What the second line is for
##
## A joint marker is a circle, and a circle says only "something is here". It
## does not say which way the bone runs, so it does not say which way a drag
## will be read — and a control whose response you cannot predict before you
## touch it is a control you learn by trial.
##
## The moment a joint is taken hold of, a cross appears through it. One arm
## lies **along** the bone: pull that way and the limb reaches out or draws
## in, its length unchanged, the joints between working themselves out. The
## other arm lies **square** to it: push that way and the limb swings. Both
## motions were always available — the drag has always been read as a whole
## vector — but there was nothing on the screen that said so.
##
## It appears on touch and not before, deliberately. A figure with twenty
## joints would be a thicket of forty lines standing still, and the one thing
## a rig overlay must not do is hide the drawing underneath it. The cross is
## drawn for the joint in the hand and for no other.
static func held_cross() -> Array:
	if _grab.is_empty():
		return []
	var one: BoneRig.Bone = _bones[int(_grab[1])] as BoneRig.Bone
	var span: Vector2 = one.b - one.a
	if span.length_squared() < 0.000001:
		span = Vector2.RIGHT
	var along: Vector2 = span.normalized()
	return [along, Vector2(-along.y, along.x)]

## The bones as they stand mid-drag, so the canvas draws the skeleton where it
## actually is rather than where the layer last recorded it.
##
## Without this the spindles would sit at the last written pose until the
## finger lifted — the drawing bending under a skeleton that had not moved,
## which is the exact complaint the bones do not stay in the drawing.
static func live_bones() -> Array:
	return _bones
