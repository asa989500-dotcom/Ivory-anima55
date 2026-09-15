class_name AnimPlayer
extends Node
## Drives the animation clock independently from the render clock.
##
## The playhead is continuous so camera keys can interpolate smoothly, while
## raster cels are sampled only when the displayed frame actually changes.
## This avoids reloading/compressing the same cel on every rendered frame.

signal frame_changed(frame: float)
signal frame_index_changed(frame: int)
signal playing_changed(on: bool)
signal camera_moved(offset: Vector2, zoom: float, rotation: float)
## A layer's rig wants putting into a new pose. Emitted with the blended pose
## rather than with a frame number, so whoever is holding that layer's mesh —
## the B-Spline room, the bone room, or the canvas — does the skinning, and
## this class stays what it says it is: a clock, not a renderer.
signal rig_posed(layer_id: int, pose: Dictionary)

## Strong, flat, and opposite each other on the wheel. A ghost has to be
## told apart from the ink underneath it at a glance and from the ghost on
## the other side of the playhead just as fast, so the two defaults are a
## complementary pair rather than two tints of the same idea.
const ONION_BACK: Color = Color(0.94, 0.16, 0.26, 0.52)
const ONION_FORWARD: Color = Color(0.10, 0.72, 0.94, 0.50)
const FRAME_EPSILON: float = 0.000001

var clip: Anim.Clip = null
var stack: LayerStack = null

var frame: float = 0.0
var playing: bool = false
var looping: bool = true

var onion: bool = false
var onion_back: int = 2
var onion_forward: int = 1
var onion_back_tint: Color = ONION_BACK
var onion_forward_tint: Color = ONION_FORWARD
## Kept so older saved projects still load and still round-trip, but no
## longer painted with: the two chosen colours are the whole scheme.
var onion_highlight_tint: Color = Color(1.0, 0.78, 0.22, 0.42)

var _ghosts: Node2D = null
var _shown_frame: int = -1
var _onion_signature: int = 0
var _last_camera_offset: Vector2 = Vector2.INF
var _last_camera_zoom: float = -1.0
var _last_camera_rotation: float = 999.0
## Counts frames so the mesh solve can be rationed on a slow device without
## rationing the clock. See `_pose_rigs`.
var _solve_beat: int = 0

## --- secondary motion ---
##
## How much real time the springs are allowed to integrate on this pass, and
## the live skeletons they are integrated on.
##
## The step is nought except during playback, which is the whole guard: a
## timeline scrubbed by hand must not set hair swinging, or dragging back and
## forth would leave the figure moving after the finger stopped — which reads
## as the drawing being unstable rather than as physics.
##
## The skeletons are kept between frames because a spring *is* its own state:
## rebuilding the bones each pass would restart every swing from rest sixty
## times a second, which is exactly no swing at all. Keyed by layer id and
## dropped whenever the rig on that layer changes shape.
var _soft_step: float = 0.0
var _soft: Dictionary = {}
var _character360_rigs: Dictionary = {}

func _last_frame() -> int:
	return maxi((clip.length if clip != null else 1) - 1, 0)

func _ready() -> void:
	set_process(true)

func bind(new_clip: Anim.Clip, new_stack: LayerStack) -> void:
	stop()
	clip = new_clip
	stack = new_stack
	frame = 0.0
	_shown_frame = -1
	# A different scene entirely: nothing cached about the last one can mean
	# anything here, and a layer id from the old stack could collide with one
	# from the new.
	forget_ghosts()
	# The springs belong to the skeletons of the scene being left. A layer id
	# from the old stack could collide with one from the new, and a swing
	# half-finished on a character nobody is looking at any more is not state
	# worth carrying across.
	_soft.clear()
	_character360_rigs.clear()
	_soft_step = 0.0
	_last_camera_offset = Vector2.INF
	_last_camera_zoom = -1.0
	_last_camera_rotation = 999.0
	_clear_ghosts()
	apply(true, true)

## Everything drawn again from scratch.
##
## Called after anything that may have changed a drawing rather than merely
## moved the playhead — an undo, a paste, a frame removed, a rig taken off. So
## the cached ghosts go too: this is precisely the moment a cached drawing
## could be a picture of something that no longer exists.
func refresh_visuals() -> void:
	if clip == null or stack == null:
		return
	forget_ghosts()
	apply(true, false)

func _process(delta: float) -> void:
	if not playing or clip == null:
		return

	# Playback runs inside the chosen range, not from nought to the end of
	# everything. Watching a six-frame action in the middle of a long scene
	# should not mean sitting through everything in front of it first.
	var span: Vector2i = clip.play_span(stack)
	var start: float = float(span.x)
	var end: float = float(span.y) + 1.0
	if frame < start - 0.001 or frame > end:
		frame = start
	frame = _advance(frame, delta, end)

	if frame >= end:
		if looping:
			var run: float = maxf(end - start, 0.001)
			frame = start + fmod(frame - start, run)
		else:
			frame = maxf(end - 1.0, start)
			playing = false
			playing_changed.emit(false)

	# During playback the current cel was committed before play started.
	# Switching cels therefore never performs a CPU readback/compression pass.
	_dangle(delta)
	apply(false, false)
	frame_changed.emit(frame)

## Hair, cloth and tails catching up with the movement they were dragged into.
##
## ## Why it is a number here and the work happens in `_show_pose`
##
## Secondary motion is not a second pose laid over the first. It is the *same*
## pose arriving late, so it belongs exactly where the pose is turned into a
## shape — one place that decides where a bone is, which is the rule the whole
## rig is built on. Running it as a separate pass afterwards meant settling a
## skeleton that had already been drawn, and the drawing was always one frame
## behind the bones inside it.
##
## So this pass records only how much real time to spend, and `_show_pose`
## spends it on the layers that actually have something loose on them.
##
## Clamped rather than trusted. A frame that took a quarter of a second — a
## project opening, a texture upload, the app coming back from the background
## — would otherwise be integrated as a quarter second of swing, and
## everything soft would lurch at exactly the moment the app was already
## stuttering.
func _dangle(delta: float) -> void:
	_soft_step = minf(maxf(delta, 0.0), 1.0 / 20.0) if playing else 0.0

## Moves the playhead by a slice of real time, at whatever rate each stretch
## of the band runs at.
##
## The scene has one rate and a frame-rate unit has another, so a rendered
## frame can begin outside a unit and end inside it. Multiplying the whole
## slice by one rate would put the playhead in the wrong place every time a
## boundary is crossed — a small error, but one that accumulates over a scene
## until sound and picture no longer line up.
##
## So the slice is spent segment by segment: as much of it as fits before the
## rate changes, then the remainder at the new rate. Bounded, because a scene
## made of one-frame units must not be able to turn one rendered frame into an
## unbounded loop — sixteen boundaries in a sixtieth of a second is already
## far past anything an animator can see.
func _advance(from_frame: float, delta: float, end: float) -> float:
	var here: float = from_frame
	var left: float = maxf(delta, 0.0)
	var guard: int = 0
	while left > 0.0 and guard < 16:
		guard += 1
		var index: int = int(floor(here + FRAME_EPSILON))
		var rate: float = float(maxi(clip.rate_at(index), 1))
		var edge: float = float(clip.segment_end(index))
		var room: float = (edge - here) / rate
		if room <= 0.0:
			# Standing exactly on a boundary. Step across it by the smallest
			# amount that changes which segment we are in, so the next turn
			# of the loop reads the rate on the far side.
			here = edge + FRAME_EPSILON
			continue
		if room >= left or edge >= end:
			here += left * rate
			break
		here = edge
		left -= room
	return here

# ------------------------------------------------------------- transport

## Starts playing, from the beginning unless the head is already somewhere it
## makes sense to continue from.
##
## ## What was uneven about it
##
## Play began from wherever `frame` happened to be, and `frame` is a float the
## scrub bar writes. Land a finger anywhere on the ruler and it holds a
## fraction — 0.62, 1.4 — so pressing play started part-way into a frame and
## the first frame of the run was shown for a fraction of its length before
## the second arrived. That is the uneven start: not the wrong frame, a
## *partial* one, and it looked like the timeline skipping to 1 or 2.
##
## And a head sitting one frame *before* the range, or a whole run past its
## end, simply started from wherever it was and ran out immediately.
##
## ## What it does now
##
## Snapped to a whole frame, always — nothing begins mid-frame. Then: a head
## genuinely inside the range continues from there, because a person who put
## it in the middle meant to watch from the middle, and looping brings it
## round to the start on its own. A head anywhere else goes to the first
## frame, which is what "play" means when nothing says otherwise.
func play() -> void:
	if clip == null or playing:
		return
	if stack != null:
		stack.commit_all_cels()
	var span: Vector2i = clip.play_span(stack)
	var start: float = float(span.x)
	var end: float = float(span.y) + 1.0
	var here: float = floor(frame + 0.0001)
	frame = here if (here >= start and here < end - 0.001) else start
	playing = true
	playing_changed.emit(true)
	apply(false, false)

func stop() -> void:
	if not playing:
		return
	playing = false
	playing_changed.emit(false)

func toggle() -> void:
	if playing:
		stop()
	else:
		play()

func seek(to: float) -> void:
	if clip == null:
		return
	var end: float = float(_last_frame())
	frame = clampf(to, 0.0, end)
	# A manual seek can happen immediately after drawing, so write the current
	# cel back before replacing the live surface.
	apply(true, true)
	frame_changed.emit(frame)

func step(by: int) -> void:
	if clip == null or stack == null:
		return
	var current: int = clampi(int(floor(frame + FRAME_EPSILON)), 0, maxi(clip.length - 1, 0))
	if by == 0:
		return

	if by > 0:
		# Next moves. It only makes a frame when there is nothing ahead to
		# move to.
		#
		# It used to ask whether the destination held a cel of its own, and
		# make a blank one whenever it did not — so walking forward through a
		# scene laid a trail of empty frames between the drawings already
		# there. Two things count as "something ahead": a drawing holding
		# through the destination, and any drawing further along the layer.
		# Only past the last of them is Next also the thing that adds one.
		var target: int = current + 1
		if target >= clip.length:
			clip.grow_to_fit(stack, target)
		# A rigged layer is animated by posing, so Next only ever walks here.
		var waiting: bool = _something_ahead(current) \
			or (stack != null and stack.active_frames_locked())
		if not waiting:
			_ensure_editable_frame(target)
			# Entering a newly made blank frame shows the drawing before it
			# through onion skin. The drawing itself is never copied.
			if _has_editable_frame(current):
				onion = true
				onion_back = maxi(onion_back, 1)
		_onion_signature = 0
		seek(float(target))
		return

	# Previous never invents, inserts, or duplicates a cel. It simply moves to
	# the existing previous frame position.
	var target_back: int = maxi(current - 1, 0)
	if target_back != current:
		seek(float(target_back))

## Whether the layer still has drawing after this moment — either one holding
## through the next frame, or one waiting further along.
func _something_ahead(current: int) -> bool:
	if stack == null or stack.layers.is_empty():
		return false
	var index: int = clampi(stack.active_index, 0, stack.layers.size() - 1)
	var track: CelTrack = stack.layers[index].cels
	if track.is_empty():
		return false
	if track.frame_showing(current + 1) >= 0:
		return true
	for f in track.frames():
		if int(f) > current:
			return true
	return false

func _has_editable_frame(at: int) -> bool:
	if stack == null or stack.layers.is_empty():
		return false
	var index: int = clampi(stack.active_index, 0, stack.layers.size() - 1)
	return stack.layers[index].cels.has_frame(at)

func _ensure_editable_frame(at: int) -> void:
	if stack == null or stack.layers.is_empty():
		return
	var index: int = clampi(stack.active_index, 0, stack.layers.size() - 1)
	var layer: LayerStack.Layer = stack.layers[index]
	if layer.cels.has_frame(at):
		if layer.cels.loaded != at:
			layer.cels.load_into(layer.surface, at)
		return
	if layer.cels.is_empty():
		layer.cels.capture_surface(layer.surface, 0)
		if at == 0:
			layer.cels.load_into(layer.surface, 0)
			return
	layer.cels.add_frame(layer.surface, at, false)

func ensure_editable_for_stroke() -> void:
	if clip == null or stack == null:
		return
	var at: int = clampi(int(floor(frame + FRAME_EPSILON)), 0, _last_frame())
	_ensure_editable_frame(at)
	if at > 0 and stack.active() != null and stack.active().cels.frame_showing(at - 1) >= 0:
		onion = true
		_onion_signature = 0
		_update_onion(at)

## Lands on the nearest actual drawing rather than walking through holds.
func step_to_drawing(way: int) -> void:
	if stack == null:
		return
	var here: int = int(floor(frame + FRAME_EPSILON))
	var best: int = -1
	for l in stack.layers:
		for f in l.cels.frames():
			var one: int = int(f)
			if way > 0 and one > here and (best < 0 or one < best):
				best = one
			elif way < 0 and one < here and (best < 0 or one > best):
				best = one
	if best >= 0:
		seek(float(best))

# ---------------------------------------------------------------- showing

## Updates raster content only when the integer display frame changes, while
## camera interpolation remains continuous at the render rate.
func apply(force: bool = false, write_back: bool = true) -> void:
	if clip == null or stack == null:
		return

	var shown: int = clampi(int(floor(frame + FRAME_EPSILON)), 0,
		_last_frame())
	if force or shown != _shown_frame:
		stack.show_frame(shown, write_back)
		_shown_frame = shown
		_update_onion(shown)
		frame_index_changed.emit(shown)

	_pose_rigs(shown, force)
	_shape_mouths(shown)

	var eye: Dictionary = clip.camera_at(frame)
	if not eye.is_empty():
		var offset: Vector2 = eye["offset"]
		var zoom: float = float(eye["zoom"])
		var rotation: float = float(eye.get("rotation", 0.0))
		if force or offset.distance_squared_to(_last_camera_offset) > 0.000001 \
				or absf(zoom - _last_camera_zoom) > 0.000001 \
				or absf(rotation - _last_camera_rotation) > 0.000001:
			_last_camera_offset = offset
			_last_camera_zoom = zoom
			_last_camera_rotation = rotation
			camera_moved.emit(offset, zoom, rotation)

## Puts every rigged layer into the pose its own track asks for, and every
## switch folder onto the member the clip asks for.
##
## Two different costs, handled differently, and the difference is the whole
## reason this reads the way it does.
##
## **Switching is free.** It is one integer compare per folder and a
## visibility flag. It runs on every frame on every device, always, because a
## mouth that changes shape a frame late is a mouth that is out of sync — and
## there is nothing to gain by delaying something this cheap.
##
## **Posing is not free.** Reading the pose is: a handful of floats blended,
## and that also runs every frame everywhere, so the *timing* of an animation
## is identical on every device and a scene checked on a tablet plays at the
## same speed on a phone. But pushing that pose through a mesh — every vertex
## re-weighted and re-uploaded — is the expensive half, and on a slow device
## it is emitted only every second or third frame.
##
## The result is an animation that holds a pose for a frame at a time rather
## than one that plays slowly. That is the right way round: a viewer forgives
## a held pose and does not forgive a scene running at half speed.
func _pose_rigs(shown: int, force: bool) -> void:
	# --- charts, every frame ---
	for g in stack.groups:
		var folder: LayerStack.Group = g
		if not folder.is_switch:
			continue
		var want: int = clip.swap_at(folder.id, shown, folder.switch_index)
		if want != folder.switch_index:
			# Quietly while playing: the drawing changes, the layers panel is
			# not rebuilt several times a second to redraw rows nobody is
			# watching during playback.
			stack.set_switch_index(folder.id, want, not playing)

	# --- poses, rationed ---
	_solve_beat += 1
	var stride: int = maxi(Perf.rig_solve_stride(), 1)
	if not force and playing and _solve_beat % stride != 0:
		return
	for l in stack.layers:
		var one: LayerStack.Layer = l
		if one.poses == null or one.poses.is_empty():
			continue
		var pose: Dictionary = one.poses.pose_at(frame)
		if pose.is_empty():
			continue
		_show_pose(one, pose)
		rig_posed.emit(one.id, pose)

## Draws the pose, rather than only announcing it.
##
## Until now this class read the right pose at the right moment and emitted
## it, and the canvas went on drawing the layer flat — because a layer is a
## grid of tiled sprites and a grid of sprites cannot bend. A `RigSkin` can:
## it stands in front of the layer holding the same picture on a mesh, and
## the mesh moves.
##
## The skin is put on once and reshaped after that, never rebuilt. Building it
## means reading the layer's pixels back off the surface, which is the one
## thing that must not happen every frame.
## Bends every linked mouth to the sound at this frame.
##
## Two mouths are read, not one: the shape at this frame and the shape at the
## next, blended by how far into the frame we are. A mouth in speech is always
## travelling — the frames between two shapes are most of what the eye sees,
## and snapping from one to the next is what makes cheap lip sync look like
## chattering teeth.
func _shape_mouths(shown: int) -> void:
	for one in stack.layers:
		var l: LayerStack.Layer = one
		var mouth_source: LayerStack.Layer = l
		# Character 360 keeps its own mouth deformation in the same live mesh.
		# If the artist created the mouth on a companion layer, borrow only the
		# viseme/ring data from that layer; never copy or bake its pixels.
		if l.is_character360 and (l.mouths.is_empty() or l.mouth_ring == null):
			for candidate in stack.layers:
				if candidate.group_id == l.group_id and not candidate.mouths.is_empty() \
						and candidate.mouth_ring != null and candidate.mouth_ring.is_ready():
					mouth_source = candidate
					break
		if mouth_source.mouths.is_empty() or mouth_source.mouth_ring == null \
				or not mouth_source.mouth_ring.is_ready():
			continue
		var here: int = clampi(shown, 0, mouth_source.mouths.size() - 1)
		var next: int = mini(here + 1, mouth_source.mouths.size() - 1)
		var into: float = clampf(frame - floor(frame), 0.0, 1.0)
		var shape: PackedFloat32Array = Viseme.blend(mouth_source.mouths[here],
			mouth_source.mouths[next], into)
		# How hard it is spoken travels with which shape it is, and travels
		# the same way — blended between this frame and the next, so a
		# syllable swells and falls instead of stepping.
		if mouth_source.mouth_power.size() == mouth_source.mouths.size():
			shape = Viseme.at_power(shape, lerpf(mouth_source.mouth_power[here],
				mouth_source.mouth_power[next], into))
		l.mouth_now = mouth_source.mouths[here]

		var skin: RigSkin = l.skin
		if skin == null or not is_instance_valid(skin):
			skin = stack.wear_skin(l, 32 if Perf.rig_solve_stride() == 1 else 16)
			if skin == null:
				continue
		skin.reshape(RigSkin.mouth_rule(mouth_source.mouth_ring, shape))

func _character360_controller(l: LayerStack.Layer) -> Object:
	if not l.is_character360:
		return null
	var rows: Array = l.character360_state.get("turn_discs", [])
	# The cache was keyed on the layer alone, so editing the discs left the
	# old skeleton in place until the project was rebound. Keyed on their
	# shape as well, an edit simply misses the cache and rebuilds.
	var mark: int = _disc_signature(rows)
	var cached: Variant = _character360_rigs.get(l.id)
	if cached is Array and cached.size() == 2 and int(cached[0]) == mark:
		var held: Variant = cached[1]
		if held != null:
			return held
	var c: Object = Native.character360_rig()
	if c == null:
		# No compiled library on this device. The GDScript controller does
		# the same blend, so Character 360 turns either way.
		c = Character360RigFallback.new()
	for row in rows:
		if row is Dictionary:
			c.add_disc(deg_to_rad(float(row.get("angle", 0.0))))
	_character360_rigs[l.id] = [mark, c]
	return c

func _disc_signature(rows: Array) -> int:
	var mark: int = rows.size() * 92821
	for row in rows:
		if row is Dictionary:
			mark = mark * 31 + int(round(float(row.get("angle", 0.0)) * 64.0))
	return mark

func _apply_character360_runtime(l: LayerStack.Layer, skin: RigSkin,
		packed: PackedFloat32Array, _rest_a: PackedVector2Array,
		_rest_b: PackedVector2Array) -> void:
	if not l.is_character360:
		return
	var controller: Object = _character360_controller(l)
	if controller == null:
		return
	if not skin._character360_discs:
		skin.set_character360_discs(l.character360_state)
	# The first/root driver is the stable view dial. Artists can later change
	# this in the motion layer without changing the stored disc artwork.
	var yaw: float = 0.0
	if packed.size() >= 3:
		yaw = packed[2]
	var weights: PackedFloat32Array = controller.disc_weights(yaw)
	skin.set_character360_disc_weights(weights)

func _apply_character360_onion(l: LayerStack.Layer, skin: RigSkin,
		rest_a: PackedVector2Array, rest_b: PackedVector2Array,
		shown: int) -> void:
	if not onion or not l.is_character360 or clip == null:
		skin._clear_pose_onion()
		return
	# GDScript has no `cond ? a : b`. Written out as guards, which also gives
	# somewhere to put the checks the one-liner was missing: a layer whose
	# `poses` track was never made, and an onion whose back/forward counts
	# the user set to nought.
	var prev: int = shown - 1
	var next: int = shown + 1
	var back_pose: Dictionary = {}
	var fwd_pose: Dictionary = {}
	if l.poses != null and clip.length > 0:
		if onion_back > 0 and prev >= 0:
			back_pose = l.poses.pose_at(float(prev))
		if onion_forward > 0 and next < clip.length:
			fwd_pose = l.poses.pose_at(float(next))
	var ba: PackedVector2Array = PackedVector2Array()
	var bb: PackedVector2Array = PackedVector2Array()
	var fa: PackedVector2Array = PackedVector2Array()
	var fb: PackedVector2Array = PackedVector2Array()
	if not back_pose.is_empty() and back_pose.has("bones"):
		var bp: PackedFloat32Array = back_pose["bones"]
		ba = _ends_of(bp, l.rig.get("bones_rest", {}).get("len", PackedFloat32Array()), true)
		bb = _ends_of(bp, l.rig.get("bones_rest", {}).get("len", PackedFloat32Array()), false)
	if not fwd_pose.is_empty() and fwd_pose.has("bones"):
		var fp: PackedFloat32Array = fwd_pose["bones"]
		fa = _ends_of(fp, l.rig.get("bones_rest", {}).get("len", PackedFloat32Array()), true)
		fb = _ends_of(fp, l.rig.get("bones_rest", {}).get("len", PackedFloat32Array()), false)
	skin.set_character360_onion(rest_a, rest_b, ba, bb, fa, fb, onion_back_tint, onion_forward_tint)

func _show_pose(l: LayerStack.Layer, pose: Dictionary) -> void:
	if not pose.has("bones"):
		return
	var packed: PackedFloat32Array = pose["bones"]
	if packed.size() < 3:
		return
	var skin: RigSkin = l.skin
	if skin == null or not is_instance_valid(skin):
		# Coarser on a slow device. The pose is the same either way; only
		# how finely the picture follows it changes, and a slightly faceted
		# bend running at speed beats a smooth one that stutters.
		skin = stack.wear_skin(l, 32 if Perf.rig_solve_stride() == 1 else 16)
		if skin == null:
			return
	var rest: Dictionary = l.rig.get("bones_rest", {})
	if rest.is_empty():
		return
	var rest_a: PackedVector2Array = rest.get("a", PackedVector2Array())
	var rest_b: PackedVector2Array = rest.get("b", PackedVector2Array())
	var lengths: PackedFloat32Array = rest.get("len", PackedFloat32Array())
	var heads: PackedVector2Array = _ends_of(packed, lengths, true)
	var tails: PackedVector2Array = _ends_of(packed, lengths, false)
	# Hair, cloth and tails arriving late. Only on a layer that was told it
	# has something loose on it, and only while playing — see `_dangle`.
	if l.dangle and _soft_step > 0.0:
		var trailed: Array = _trail(l, packed)
		if trailed.size() == 2:
			heads = trailed[0]
			tails = trailed[1]
	# By island, so a skeleton drawn on one figure cannot take hold of another
	# drawing sharing the layer with it — see `RigSkin._read_islands`.
	skin.reshape_by_island(RigSkin.bone_rule(rest_a, rest_b, heads, tails,
		skin.bone_islands(rest_a, rest_b)))
	_apply_character360_runtime(l, skin, packed, rest_a, rest_b)
	_apply_character360_onion(l, skin, rest_a, rest_b, int(floor(frame)))

## The pose this frame asks for, softened by whatever on this figure is loose.
##
## ## What the spring is given, and why it is not the packed pose
##
## A key holds each bone as a pivot and a world angle. A spring cannot work on
## those: a world angle already contains every turn above it in the chain, so
## settling one would make a hand lag behind the arm *and* behind its own lag,
## and the further down a chain a bone sat the more it would drift. The pose
## is therefore laid onto a real skeleton and `adopt` recovers each bone's own
## turn in its parent's frame, which is the one quantity a spring may be run
## on. `BoneSolver.settle` blends by `BoneRig.Bone.soft`, so nought is a skull
## that does not move at all and one is the tip of a ponytail.
##
## ## Why the skeleton is kept
##
## Because the spring is its state. `eased`, `eased_target` and `eased_speed`
## are where the swing has got to, and a skeleton rebuilt every frame would be
## a swing restarted every frame — which is a figure that never moves at all.
## It is dropped and rebuilt only when the rig changes shape, and calmed on
## the way in so nothing lurches on the first frame after a rig is loaded.
##
## Returns the two ends of every bone, or an empty array when there is nothing
## soft here — in which case the caller uses the pose exactly as keyed, and
## nothing has cost anything.
func _trail(l: LayerStack.Layer, packed: PackedFloat32Array) -> Array:
	var rows: Array = l.rig.get("bones", [])
	if rows.is_empty():
		return []
	var bones: Array = _soft.get(l.id, [])
	if bones.size() != rows.size():
		bones = BoneRig.from_rows(rows)
		BoneSolver.calm(bones)
		_soft[l.id] = bones
	# Nothing on this figure is loose. Cheaper to find out here, once, than
	# to run a spring over a rigid skeleton and get the pose back unchanged.
	var loose: bool = false
	for one in bones:
		if (one as BoneRig.Bone).soft > 0.0:
			loose = true
			break
	if not loose:
		return []
	RigTrack.lay_bones(bones, packed)
	BoneRig.adopt(bones)
	BoneSolver.settle(bones, _soft_step, l.dangle_speed, l.dangle_damp,
		l.dangle_swing)
	var heads: PackedVector2Array = PackedVector2Array()
	var tails: PackedVector2Array = PackedVector2Array()
	heads.resize(bones.size())
	tails.resize(bones.size())
	for i in bones.size():
		var b: BoneRig.Bone = bones[i]
		heads[i] = b.a
		tails[i] = b.b
	return [heads, tails]

## The two ends of every bone in a packed pose.
##
## A key holds each bone as a pivot and an angle — see the head of
## `rig_track.gd` for why it is not two points — so the far end is rebuilt
## from the bone's own rest length. That is what keeps a limb exactly as long
## at every in-between as it was drawn.
static func _ends_of(packed: PackedFloat32Array, lengths: PackedFloat32Array,
		want_pivot: bool) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var n: int = int(float(packed.size()) / 3.0)
	out.resize(n)
	for i in n:
		var pivot: Vector2 = Vector2(packed[i * 3], packed[i * 3 + 1])
		if want_pivot:
			out[i] = pivot
			continue
		var reach: float = lengths[i] if i < lengths.size() else 0.0
		out[i] = pivot + Vector2.RIGHT.rotated(packed[i * 3 + 2]) * reach
	return out

func _update_onion(shown: int) -> void:
	var back: int = clampi(onion_back, 0, 8)
	var ahead: int = clampi(onion_forward, 0, 8)
	var signature: int = hash([onion, back, ahead,
		onion_back_tint, onion_forward_tint, onion_highlight_tint, shown])
	if signature == _onion_signature:
		return
	_onion_signature = signature
	_lay_onion(shown)

func _clear_ghosts() -> void:
	if _ghosts != null:
		_ghosts.queue_free()
		_ghosts = null

## Textures already built for onion skinning, keyed by layer and by which
## drawing of that layer they are.
##
## This is the difference between stepping through a scene and grinding
## through it. Frame-by-frame work is stepping — a drawing, a step, a drawing,
## a step, all day — and every step used to throw every ghost away and upload
## every one of them to the graphics card again. Four layers with three
## drawings behind and one ahead is sixteen texture uploads per tap of the
## arrow, for pictures that have not changed since the last tap.
##
## They are the *committed* drawings, which is what makes caching them safe:
## a cel becomes a new image when it is committed, never by being edited in
## place, so a cached texture cannot go stale while it is being looked at. The
## one that *can* change — the drawing under the hand right now — is never a
## ghost, because a ghost of the frame you are on is not drawn at all.
var _ghost_cache: Dictionary = {}

## Forgets every cached ghost. Called when the drawings themselves may have
## changed underneath — a different project, a different page, an undo.
func forget_ghosts() -> void:
	_ghost_cache.clear()
	_onion_signature = 0

func _ghost_texture(l: LayerStack.Layer, which: int) -> ImageTexture:
	var key: String = "%d:%d" % [l.id, which]
	var had: Variant = _ghost_cache.get(key)
	if had != null and is_instance_valid(had):
		return had
	var img: Image = l.cels.image_of(which)
	if img == null:
		return null
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	# Bounded. A long scene stepped end to end would otherwise hold every
	# drawing in it on the graphics card at once, and the whole point of a
	# cel being compressed on the layer is that they are not all resident.
	if _ghost_cache.size() > 48:
		_ghost_cache.clear()
	_ghost_cache[key] = tex
	return tex

func _lay_onion(here: int) -> void:
	_clear_ghosts()
	if not onion or stack == null:
		return
	var back: int = clampi(onion_back, 0, 8)
	var ahead: int = clampi(onion_forward, 0, 8)
	if back == 0 and ahead == 0:
		return

	_ghosts = Node2D.new()
	_ghosts.name = "Onion"
	_ghosts.z_index = 5
	stack.add_child(_ghosts)

	# Behind is one colour and ahead is another, all the way out. The
	# nearest drawing on each side is the strongest, not a third colour:
	# a hue that appeared only on the closest frame meant the two colours
	# the user actually chose were the two they could never see.
	for step_back in range(1, back + 1):
		_ghost_at(here - step_back, onion_back_tint, step_back, back, here)
	for step_on in range(1, ahead + 1):
		_ghost_at(here + step_on, onion_forward_tint, step_on, ahead, here)

## How faint the furthest ghost is drawn, as a share of the nearest.
##
## The run is spread evenly between full strength and this, **whatever the
## count is**. The old sum divided by the span rather than by the gaps in it,
## so with two frames behind the further one came out at 0.69 and with eight
## the furthest came out at 0.46 — the more you asked to see, the less the
## spacing told you, and at two frames the two were nearly identical.
##
## Now three frames read as three distinct depths and eight read as eight,
## because the first is always full and the last is always this. That is what
## makes a run of ghosts say *how far away* rather than merely *not now*.
const GHOST_FAINTEST: float = 0.24

func _ghost_at(at: int, tint: Color, step_away: int, span: int,
		home: int) -> void:
	if at < 0 or _ghosts == null:
		return
	# Spread across the gaps, not across the count: with one ghost there are
	# no gaps and it is simply the nearest, at full strength.
	var gaps: int = maxi(span - 1, 1)
	var fade: float = lerpf(1.0, GHOST_FAINTEST,
		float(step_away - 1) / float(gaps)) if span > 1 else 1.0
	for l in stack.layers:
		if not l.visible:
			continue
		# A posed figure is the case this used to miss entirely.
		#
		# The loop below asks `cels` which drawing is showing, and skips the
		# layer when it is the same drawing as the current frame. On an
		# ordinary layer that is exactly right: same drawing, nothing to
		# ghost. On a **rigged** layer it is wrong, and wrong in the way that
		# makes onion skin appear not to work at all.
		#
		# A rigged figure is drawn once. Every pose after that is a key in
		# `l.poses` over the *same* cel — usually the only cel the layer has.
		# So `frame_showing` returns the same number for every frame in the
		# scene, the test above fires on every layer, and the whole feature
		# quietly does nothing. That is the report: onion skin never works
		# with the quick bones.
		#
		# The skeleton is what changed, so the skeleton is what is ghosted.
		_ghost_rig_at(l, at, tint, fade)
		if l.cels.is_empty():
			continue
		var which: int = l.cels.frame_showing(at)
		var current: int = l.cels.frame_showing(home)
		if which < 0 or which == current:
			continue
		var tex: ImageTexture = _ghost_texture(l, which)
		if tex == null:
			continue
		var ghost: Sprite2D = Sprite2D.new()
		ghost.centered = false
		ghost.position = Vector2(l.cels.origin_of(which))
		ghost.texture = tex
		# The drawing's shape in the chosen colour — see `ghost_material`.
		ghost.material = ghost_material()
		ghost.modulate = Color(tint.r, tint.g, tint.b, tint.a * fade)
		_ghosts.add_child(ghost)

## How thick a ghosted bone is drawn, in page units before zoom.
const GHOST_BONE_W: float = 3.0

## The skeleton this layer was standing in at another frame, in the onion
## colour.
##
## ## Why the bones and not the bent drawing
##
## Ghosting the artwork as it would look in that pose means running the skin
## for every ghost on every layer on every redraw — the deformation the live
## figure already costs, times the number of ghosts. On a phone that is the
## difference between stepping through a scene and waiting for it.
##
## The skeleton answers the question anyone is actually asking of onion skin
## while posing: where was the arm a frame ago, and where is it going. It is a
## few lines, it costs nothing, and it reads more clearly over a drawing than a
## second copy of that drawing would.
##
## The colours are the ones already chosen for behind and ahead, and the fade
## is the same fade — a ghosted pose sits in the same run of depths as a
## ghosted drawing, so three frames back is three frames back whichever kind of
## layer it is on.
func _ghost_rig_at(l: LayerStack.Layer, at: int, tint: Color, fade: float) -> void:
	if l.poses == null or l.poses.is_empty():
		return
	if at < 0 or _ghosts == null:
		return
	var pose: Dictionary = l.poses.pose_at(float(at))
	var flat: PackedFloat32Array = pose.get("bones", PackedFloat32Array())
	if flat.is_empty():
		return
	# The pose is stored as a flat block of numbers; the rig it belongs to says
	# how many bones that is and how they hang together.
	var bones: Array = BoneRig.from_rows((l.rig as Dictionary).get("bones", []))
	if bones.is_empty():
		return
	RigTrack.lay_bones(bones, flat)
	BoneRig.solve(bones)

	var ink: Color = Color(tint.r, tint.g, tint.b, tint.a * fade)
	for one in bones:
		var bone: BoneRig.Bone = one as BoneRig.Bone
		if bone == null:
			continue
		if bone.a.distance_to(bone.b) < 0.5:
			continue
		var line: Line2D = Line2D.new()
		line.points = PackedVector2Array([bone.a, bone.b])
		line.width = GHOST_BONE_W
		line.default_color = ink
		# Rounded, so a chain of bones reads as one limb rather than as a row
		# of separate sticks.
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		_ghosts.add_child(line)

## Draws a cel as a flat silhouette in whatever colour it is modulated with.
##
## ## Why a shader, and why the colour picker did nothing without one
##
## A ghost used to be the drawing itself with `modulate` set to the onion
## colour. `modulate` **multiplies**, and a drawing is mostly black ink — and
## black multiplied by red is black. Multiplied by blue it is also black.
##
## So the two colours were being applied correctly and faithfully to every
## pixel, and the result was the same dark grey drawing either way. Every
## control worked; nothing on screen ever changed. Somebody could sit and
## move that colour picker through the whole spectrum and reasonably conclude
## the app was ignoring them.
##
## What a ghost has to be is the drawing's **shape** filled with the colour,
## which multiplication cannot express at all — the ink's own colour has to be
## discarded rather than combined with. Two lines of shader, and they are the
## difference between a feature and a control that lies.
##
## Alpha carries the shape and is the only thing read from the texture. The
## output is premultiplied to match the blend mode, so a soft edge on a cel
## stays a soft edge on its ghost instead of fringing dark.
static var _ghost_mat: ShaderMaterial = null

static func ghost_material() -> ShaderMaterial:
	if _ghost_mat != null:
		return _ghost_mat
	var sh: Shader = Shader.new()
	# Written as joined lines rather than as a block string: a block string
	# holding tabs makes the indentation checker read the shader as GDScript
	# that has lost its way, and a checker that cries wolf on correct code is
	# a checker people learn to skip.
	sh.code = "\n".join([
		"shader_type canvas_item;",
		"render_mode blend_premul_alpha;",
		"void fragment() {",
		"	float shape = texture(TEXTURE, UV).a;",
		"	float a = shape * COLOR.a;",
		"	COLOR = vec4(COLOR.rgb * a, a);",
		"}",
	])
	_ghost_mat = ShaderMaterial.new()
	_ghost_mat.shader = sh
	return _ghost_mat
