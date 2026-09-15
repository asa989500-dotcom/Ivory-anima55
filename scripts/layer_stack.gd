class_name LayerStack
extends Node2D
## The ordered pile of drawing layers, with folders.
##
## `layers` is one flat array in draw order: index 0 is the bottom of the
## picture, the last index is the top. A layer belonging to a folder carries
## that folder's id, and members of the same folder are always kept next to
## each other — so the flat array stays the single truth about what covers
## what, and folders are a view onto it rather than a second structure that
## could drift out of step.
##
## Nothing here destroys a layer. Removing one moves it off-stage into
## `_detached`, where it sleeps compressed until either the history brings
## it back or the history forgets it. That is what lets deleting a layer be
## as undoable as drawing a line.

signal changed()
signal active_changed(index: int)

const MAX_LAYERS: int = 24
const MAX_GROUPS: int = 8

class Layer:
	## The drawings of this layer, one per frame, in memory. A frame is the
	## same layer at another moment — it never becomes a layer of its own.
	var cels: CelTrack = CelTrack.new()
	var id: int = 0
	var title: String = ""
	var surface: PaintSurface = null
	var visible: bool = true
	var opacity: float = 1.0
	var locked: bool = false
	var group_id: int = 0
	## The bottom plate. It can be emptied but never removed, moved or
	## foldered, so the stack always has ground to stand on.
	var is_background: bool = false
	var thumb: ImageTexture = null
	## Written rather than drawn. The words and how they are set are kept
	## beside the pixels, so the layer can be restyled later instead of being
	## erased and typed again.
	## A light layer: it adds to what is beneath instead of covering it.
	var glow: bool = false
	## The stretch of the scene this layer exists for.
	##
	## A layer added at frame forty is a layer that did not exist at frame
	## thirty-nine, and one taken away at frame forty is one that *did*. This
	## is the whole of "each frame has its own layers": the stack is still one
	## list, because a drawing has to live somewhere and shuffling whole
	## stacks per frame would multiply everything by the length of the scene —
	## but each layer knows when it came and when it went, and the frames
	## outside that are exactly as they were.
	##
	## `gone_at` of -1 means it never goes.
	var born_at: int = 0
	var gone_at: int = -1

	## Whether this layer is part of the scene at a given frame.
	func alive_at(frame: int) -> bool:
		if frame < born_at:
			return false
		return gone_at < 0 or frame < gone_at

	## --- secondary motion ---
	##
	## Whether anything on this figure trails behind the pose rather than
	## snapping to it: hair, a cloak, a tail, a loose sleeve.
	##
	## Off by default, and deliberately. Secondary motion applied to a figure
	## nobody asked it for is a drawing that will not hold still, and the
	## commonest complaint about it in every package that has it is that it
	## arrived switched on.
	##
	## The bone says how *much* it follows (`BoneRig.Bone.soft`); these three
	## say what kind of thing it is, because a ponytail and a heavy cloak
	## differ in their weight rather than in which strand is loose.
	var dangle: bool = false
	## How quickly it responds. High is stiff wire, low is heavy rope.
	var dangle_speed: float = 3.0
	## How it arrives. One settles cleanly; below one it wobbles first, which
	## is what hair does.
	var dangle_damp: float = 0.55
	## How eagerly it starts. Above one it overshoots on the way out; below
	## nought it draws back before it moves, which is a piece of animation
	## grammar older than computers.
	var dangle_swing: float = 1.4
	## How much of the skeleton is shown, 0 to 1. Never drawn into the
	## pixels; it only governs what is put on screen over the drawing.
	var show_bones: float = 1.0
	## A bone-motion layer is a protected motion-only surface: anything placed
	## on it is treated as an object to move, never as fresh paint.
	var is_bone_layer: bool = false
	## A two-view Character 360 layer. Geometry comes only from front + side PNGs.
	var is_character360: bool = false
	var is_character360_motion: bool = false
	var character360_state: Dictionary = {}
	## Non-destructive object transform used only by motion-only layers.
	## The raster itself is never resampled while posing.
	var motion_position: Vector2 = Vector2.ZERO
	var motion_rotation: float = 0.0
	var motion_scale: float = 1.0
	var is_text: bool = false
	var text_state: Dictionary = {}
	## Where the writing sits and how far it is turned. Kept apart from the
	## pixels so it can be moved and turned any number of times without the
	## letters being resampled once — every move re-renders from the words,
	## so text never softens the way a rotated picture of text does.
	var text_at: Vector2 = Vector2.ZERO
	var text_turn: float = 0.0
	## How large the writing is drawn, as a multiple of the size in
	## `text_state`, and how big it came out at that size.
	##
	## ## Why the box is stored and not measured
	##
	## It used to be measured from the ink every time it was needed — walk
	## the layer, find the darkest extent, call that the box. Two faults came
	## out of that, and they are the two complaints about the text tool.
	##
	## The box **jumped** the moment the writing was re-rendered, because
	## descenders, a halo or a wider glyph move where the ink ends. Nothing
	## had been resized; the ruler had changed.
	##
	## And a corner grip could not resize anything, because there was nothing
	## to resize: the box was an observation about pixels, and you cannot
	## drag an observation.
	##
	## So the box is a fact the layer carries. It changes when somebody
	## changes it and at no other time.
	var text_scale: float = 1.0
	var text_size: Vector2 = Vector2.ZERO
	## The curve and bones this layer was last posed with. Kept on the layer
	## so returning to the B-Spline room finds the figure standing where it
	## was left rather than flat again.
	var rig: Dictionary = {}
	## And the poses that rig takes over time.
	##
	## Beside `cels`, and for the same reason: `cels` is what this layer is
	## drawn as at each moment, `poses` is what it is bent into. A layer may
	## carry either, both, or neither — a rigged cut-out has poses and one
	## drawing; a hand-drawn walk has drawings and no poses; a mouth chart
	## has neither and is switched instead.
	var poses: RigTrack = RigTrack.new()

	## The black ring drawn round this layer's mouth, if one was drawn.
	##
	## Null on every layer that is not a mouth, which is nearly all of them —
	## a layer carries this the way it carries a rig: only once it has been
	## given one.
	var mouth_ring: MouthRing = null
	## The bent stand-in for this layer while it is being posed, if any.
	##
	## Live state, never saved: it is a picture of the layer plus a mesh, and
	## both are rebuilt from the layer itself whenever posing begins. Writing
	## it down would only be a way of keeping a stale copy of a drawing.
	var skin: RigSkin = null
	## Which mouth shape this layer is holding right now, as a Viseme.Mouth.
	## Live state rather than saved state: it is worked out from the sound
	## every frame, so writing it down would only be a way of disagreeing
	## with the sound later.
	## Source WAV linked to this layer; used by timeline playback/lip-sync and MP4 audio export.
	var sound_path: String = ""
	var mouth_now: int = 0
	## One mouth per frame, read off the linked sound. Empty on every layer
	## that has no sound, which is nearly all of them.
	var mouths: PackedInt32Array = PackedInt32Array()
	## How hard each of those mouths is spoken, from nothing to one.
	##
	## Kept beside the shapes rather than folded into them, because they are
	## two different facts: *which* mouth this is, and how much of it. Nine
	## shapes played at full strength every time is a puppet — every `A` in a
	## line as wide as the mouth can go, whether it is a shout or the tail of
	## a word.
	var mouth_power: PackedFloat32Array = PackedFloat32Array()

class Group:
	var id: int = 0
	var title: String = ""
	var visible: bool = true
	var opacity: float = 1.0
	var collapsed: bool = false
	var node: Node2D = null
	## An animation folder. It reads the bones of every layer inside it and
	## treats them as one skeleton, so an arm layer and a body layer move
	## together as a figure — while staying the separate layers they are. The
	## folder holds the rig; it never merges the drawings.
	var is_animation: bool = false

	## A switch folder: exactly one layer inside it is visible at a time.
	##
	## This is how a mouth chart works, and an eye chart, and a hand chart.
	## Twelve mouth shapes go in one folder, and the folder shows the one the
	## dialogue needs. Without it, lip sync means twelve visibility toggles
	## per syllable and there is no such thing as a fast expression change —
	## which is most of what makes a rig usable in production rather than
	## impressive in a demo.
	##
	## Note what it is *not*: it is not a new kind of layer, and it does not
	## merge or move anything. A switch folder is an ordinary folder that
	## answers one extra question when the stack works out what is visible.
	## Turn it off and every layer inside comes back exactly as it was.
	var is_switch: bool = false
	## Which member is showing, counted from the top of the folder as the
	## layers panel draws it. Clamped on read rather than on write, so
	## deleting a layer can never leave this pointing at nothing.
	var switch_index: int = 0

var layers: Array[Layer] = []
var groups: Array[Group] = []
var active_index: int = 0

## While one layer is being looked at on its own, everything else steps
## aside. Kept here rather than in the panel, because _apply_looks rewrites
## visibility on every change and would otherwise stomp on it.
var solo_id: int = 0

## Which folder the panel is pointing at, or 0 when a layer is. Kept apart
## from `active_index` because "the folder is selected" and "a layer inside
## it is selected" have to lead to different things when a new layer is
## added, and one number cannot say both.
var active_group: int = 0

var history: History = null

var _detached: Dictionary = {}      # layer id -> Layer, waiting in the wings
var _next_layer_id: int = 1
var _next_group_id: int = 1

func _ready() -> void:
	if layers.is_empty():
		var bg: Layer = _spawn_layer()
		bg.is_background = true
		bg.title = "Background"
		layers.append(bg)
		var first: Layer = _spawn_layer()
		layers.append(first)
		active_index = 1
		_rebuild()

# ------------------------------------------------------------------ access

func active() -> Layer:
	if layers.is_empty():
		return null
	return layers[clampi(active_index, 0, layers.size() - 1)]

func active_surface() -> PaintSurface:
	var l: Layer = active()
	if l == null:
		return null
	return l.surface

func by_id(id: int) -> Layer:
	for l in layers:
		if l.id == id:
			return l
	if _detached.has(id):
		return _detached[id]
	return null

func surface_by_id(id: int) -> PaintSurface:
	for l in layers:
		if l.id == id:
			return l.surface
	return null

func group_by_id(id: int) -> Group:
	for g in groups:
		if g.id == id:
			return g
	return null

## Whether the active layer will take a mark from a tool.
##
## ## A layer with a skeleton in it is not a layer you paint on
##
## Once bones have been put through a drawing, that drawing is a *puppet*: it
## has a rest pose the skeleton was bound to, and its pixels on screen are a
## stand-in bent to wherever the bones now are. Painting into it puts new ink
## on the rest pose — which appears, if it appears at all, somewhere the pose
## has moved it to and not where the finger was. Erasing takes ink off a
## drawing the eye is not looking at. Neither is a thing anybody meant.
##
## It was only the purpose-made motion layer that was protected, so a rig
## drawn onto an ordinary layer left it open to every brush in the rail. Now
## the rig itself is what closes it: add bones and the layer is for moving
## until the bones come out again, at which point it is an ordinary layer with
## no ceremony required.
func can_draw() -> bool:
	var l: Layer = active()
	if l == null or l.is_bone_layer or not l.visible or l.locked:
		return false
	# The same rule as `CanvasView._brush_layer_allowed`, and it has to stay
	# the same rule.
	#
	# This test used to be `not l.rig.is_empty()`: any layer with a skeleton
	# refused every drawing tool, for ever. That is the report where the
	# brushes and the fill stop working and the only way on is a new layer —
	# and a rig arrives on a layer in more ways than the rule allowed for:
	# quick bones tried on a figure, a whole layer lifted and put down again
	# with `carry_rig_with_selection`, a return from the Character 360 room.
	#
	# Fixing it in `CanvasView` alone was not enough and made things worse for
	# a while: the canvas said yes and this said no, so the brush was offered
	# and then did nothing. Both are here now, and only a control surface
	# refuses — a bone layer above, and the two Character 360 layers below,
	# none of which holds paintable pixels.
	if l.is_character360 or l.is_character360_motion:
		return false
	var g: Group = group_by_id(l.group_id)
	if g != null and not g.visible:
		return false
	return true

## Flat index of the highest member of a folder, or -1 if it has none.
## Whether this layer is allowed to gain new frames.
##
## A rigged figure is animated by moving its bones, not by drawing it again.
## Once bones are on a layer, a button that makes a fresh blank frame is not
## a help — it is a way to end up with a skeleton posed on one frame and an
## empty page on the next, which reads as the character vanishing. So on a
## rigged layer, and on everything inside an animation folder, the frame
## button stops making frames and only walks between the ones already there.
##
## Nothing is ever removed by this. It withholds an action; it does not undo
## one.
func frames_locked(l: Layer) -> bool:
	if l == null:
		return false
	if l.is_bone_layer or not l.rig.is_empty():
		return true
	var g: Group = group_by_id(l.group_id)
	return g != null and g.is_animation

func active_frames_locked() -> bool:
	if layers.is_empty():
		return false
	return frames_locked(layers[clampi(active_index, 0, layers.size() - 1)])

## Every layer inside a folder, bottom first.
func layers_in_group(id: int) -> Array:
	var out: Array = []
	for l in layers:
		if l.group_id == id:
			out.append(l)
	return out

## Whether a folder has anything rigged inside it worth gathering.
func group_has_rig(id: int) -> bool:
	for l in layers_in_group(id):
		if not l.rig.is_empty():
			return true
	return false

func group_top_index(id: int) -> int:
	var top: int = -1
	for i in layers.size():
		if layers[i].group_id == id:
			top = i
	return top

## The drawings inside a folder, bottom first — the order a switch channel
## counts in.
func members_of(id: int) -> Array:
	var out: Array = []
	for l in layers:
		if l.group_id == id:
			out.append(l)
	return out

# --------------------------------------------------------------- posed skins

## Puts a bent stand-in in front of a layer, and hides the layer behind it.
##
## The layer is not modified and nothing is written to it — playing an
## animation must not change the drawing. When the skin goes away the surface
## comes back exactly as it was, because it was never touched.
##
## Returns null when the layer has nothing on it to bend.
func wear_skin(l: Layer, cells: int = 32) -> RigSkin:
	if l == null or l.surface == null:
		return null
	if l.skin != null and is_instance_valid(l.skin):
		return l.skin
	var made: RigSkin = RigSkin.new()
	# A Character 360 layer is bound more finely — the same reason the puppet
	# rigging is, and it matters more here because bones bend harder than
	# pins do. The figure is long thin strands running right across it, and
	# a strand crossing a coarse cell comes out of a bend with a straight
	# piece in the middle of the curve. Denser cells put vertices along the
	# yarn, so the bend is carried by the strand and the character moves the
	# way a rigged figure moves rather than the way a photograph of one does.
	var want: int = cells
	if l.title.to_lower().contains("character 360"):
		want = maxi(cells, 56)
	if not made.bind_layer(l, want):
		made.queue_free()
		return null
	# Beside the surface and in its place in the order, so a posed layer
	# still draws above the ones below it and beneath the ones above.
	var host: Node = l.surface.get_parent()
	if host == null:
		made.queue_free()
		return null
	host.add_child(made)
	host.move_child(made, l.surface.get_index())
	made.z_index = l.surface.z_index
	l.surface.visible = false
	l.skin = made
	return made

## Takes the stand-in away and gives the layer back.
func shed_skin(l: Layer) -> void:
	if l == null:
		return
	if l.skin != null and is_instance_valid(l.skin):
		l.skin.queue_free()
	l.skin = null
	if l.surface != null:
		# Only the skin ever hid it, so it is safe to simply restore it —
		# a layer hidden by the user is hidden through `visible` on the
		# Layer, which `_apply_looks` owns and this never touches.
		l.surface.visible = true

## Every skin dropped at once. Called when playback stops or a room closes:
## a skin outliving the thing that posed it is a drawing frozen in a pose
## nobody can now change.
func shed_all_skins() -> void:
	for l in layers:
		shed_skin(l)

func member_count(id: int) -> int:
	var n: int = 0
	for l in layers:
		if l.group_id == id:
			n += 1
	return n

# ---------------------------------------------------------- switch folders

## Turns a folder into a chart, or back into an ordinary folder.
##
## Turning it on does not touch a single layer. Turning it off does not
## restore anything either — because nothing was taken away: the layers kept
## their own `visible` flags the whole time, and `_apply_looks` simply stopped
## asking about them. That is the reason this is a folder flag and not a new
## layer type. A mouth chart that has to be dismantled to be edited is a
## mouth chart nobody edits.
func set_switch(id: int, on: bool) -> void:
	var g: Group = group_by_id(id)
	if g == null or g.is_switch == on:
		return
	g.is_switch = on
	_apply_looks()
	changed.emit()

## Which member of a chart is showing. Clamped against the folder's real
## contents on every read, so deleting the layer a chart was pointing at
## shows its neighbour instead of showing nothing.
func switch_index(id: int) -> int:
	var g: Group = group_by_id(id)
	if g == null:
		return 0
	var n: int = member_count(id)
	if n <= 0:
		return 0
	return clampi(g.switch_index, 0, n - 1)

## `announce` is false while a clip is playing.
##
## Changing which member a chart shows is two separate things: rewriting
## visibility, which is a handful of booleans, and telling the rest of the app
## the stack changed — which rebuilds the layers panel. During playback a
## mouth chart steps several times a second, and rebuilding a panel that many
## times a second to redraw rows nobody is looking at is exactly the kind of
## waste that heats a tablet for nothing. The pixels still change on every
## step; only the announcement is withheld.
func set_switch_index(id: int, index: int, announce: bool = true) -> void:
	var g: Group = group_by_id(id)
	if g == null or not g.is_switch:
		return
	var n: int = member_count(id)
	if n <= 0:
		return
	# Wraps rather than stops. Stepping through a mouth chart is a loop by
	# nature, and a chart that jams at its last shape makes the animator
	# reach for the first one by hand every cycle.
	var want: int = ((index % n) + n) % n
	if want == g.switch_index:
		return
	g.switch_index = want
	_apply_looks()
	if announce:
		changed.emit()

func step_switch(id: int, by: int) -> void:
	set_switch_index(id, switch_index(id) + by)

## Whether this layer is the one its chart is currently showing. A layer in
## an ordinary folder, or in none, always answers yes — it is not in a chart,
## so a chart has nothing to say about it.
func switch_shows(l: Layer) -> bool:
	var g: Group = group_by_id(l.group_id)
	if g == null or not g.is_switch:
		return true
	var mates: Array = members_of(g.id)
	var want: int = switch_index(g.id)
	return want < mates.size() and (mates[want] as Layer).id == l.id

# ------------------------------------------------------------------ record

func _snapshot() -> Array:
	return [{"t": "arrangement", "state": capture_arrangement()}]

func _record(label: String, steps: Array) -> void:
	if history != null:
		history.push(label, steps)

## Records one change to a layer's own state — its skeleton, its pose, where
## its writing sits — as an ordinary undo entry.
##
## Undo covered two things: tiles of pixels, and the arrangement of layers.
## Everything else a layer carries was invisible to it. The arrangement
## snapshot now carries all of it (see `capture_arrangement`), so the only
## thing missing was somebody to call this at the moment it changes. Public,
## so the rooms that edit a rig can reach it: snapshot **before** the change,
## make the change, then hand the snapshot here.
##
## One entry per finished gesture, never per event — a joint dragged across
## the screen is one thing the person did and has to be one tap to undo.
func record_state(label: String, before: Array) -> void:
	_record(label, before)

## The document's state as it stands, for a caller about to change it.
func snapshot_state() -> Array:
	return _snapshot()

# --------------------------------------------------------- layer structure

func _spawn_layer() -> Layer:
	var l: Layer = Layer.new()
	l.id = _next_layer_id
	_next_layer_id += 1
	l.title = "Layer %d" % l.id
	l.surface = PaintSurface.new()
	l.surface.name = "Layer_%d" % l.id
	add_child(l.surface)
	return l

## `group_id` of -1 means "wherever the current layer lives", which is
## almost always what someone adding a layer means.
## Announcing that the *set* of layers has changed, not just which one is
## chosen.
##
## ## The two signals, and why the difference mattered
##
## `active_changed` says "a different layer is selected now". `changed` says
## "the list itself is different". They are not the same fact and they do not
## have the same audience: the layers panel redraws its list either way, and
## the timeline only rebuilds its rows on `changed`, because rebuilding a row
## per layer per selection change would be work for nothing.
##
## Adding a layer changes **both**, and only the first was ever sent. So a new
## layer appeared in the layers panel, appeared in the timeline's own layer
## chooser — that reads the stack directly — and did not appear as a **row in
## the timeline**, because nothing had told the timeline its list was out of
## date. It arrived later, whenever some unrelated edit happened to emit
## `changed`, which is exactly the "the timeline is slow to notice a new
## layer" it looked like from outside. It was not slow. It had not been told.
##
## Five functions had it: adding, duplicating, removing, moving and merging —
## every one of them a change to the set.
func _announce_set() -> void:
	changed.emit()
	active_changed.emit(active_index)

## Refused outright on a project that has no layers — see
## `ProjectManager.Project.uses_layers`. A guard rather than a hidden button,
## because a button can be missed and a stray call cannot: nothing should be
## able to put a layer where one does not belong by any route at all.
func add_layer(at: int = -1, group_id: int = -1) -> Layer:
	if not allows_layers:
		return null
	if layers.size() >= MAX_LAYERS:
		return null
	var before: Array = _snapshot()
	var l: Layer = _spawn_layer()
	# Born where the scene is standing. A layer added at frame forty did not
	# exist at frame thirty-nine, and the frames before it are none of its
	# business — which is what stops adding a layer from reaching backwards
	# and changing work that was already finished.
	l.born_at = maxi(shown_frame, 0)

	if group_id >= 0:
		l.group_id = group_id
	elif not layers.is_empty():
		var near: Layer = layers[clampi(active_index, 0, layers.size() - 1)]
		if not near.is_background:
			l.group_id = near.group_id

	var index: int = layers.size()
	if at >= 0:
		index = clampi(at, 1, layers.size())
	layers.insert(index, l)
	active_index = index
	active_group = l.group_id
	_rebuild()
	_record(UiKit.label_for("New layer", "طبقة جديدة"), before)
	_announce_set()
	return l

## New layers land above the current one. If a folder is what is selected,
## the layer goes above the whole folder and stays outside it — putting it
## inside would mean a folder could never be built on top of.
## Set once when the project is built.
var allows_layers: bool = true

func character360_group(index: int) -> int:
	return LayerCharacter360.character360_group(self, index)

func in_character360_file(index: int) -> bool:
	return LayerCharacter360.in_character360_file(self, index)

func character360_motion_layer(gid: int) -> Layer:
	return LayerCharacter360.character360_motion_layer(self, gid)

## New layers land above the current one.
##
## Two cases, and the button in the panel does not have to know which:
##
##   * inside a Character 360 file — the layer joins the file, is marked as
##     Character 360 content and is bound to the file's motion layer, so
##     whatever is drawn on it is carried by the same bones as everything
##     else in that file. It is a normal drawing layer: brush, fill, eraser
##     and selection all work on it. The motion layer is the only thing in
##     there that refuses ink, and it was not made by this function.
##
##   * a folder is what is selected — the layer goes above the whole folder
##     and stays outside it, because otherwise a folder could never be built
##     on top of. A Character 360 file that is *collapsed and selected as a
##     file* is still a folder, and this rule wins: to add into the file,
##     select a layer inside it.
func add_layer_here() -> Layer:
	if active_group != 0:
		var top: int = group_top_index(active_group)
		if top >= 0:
			return add_layer(top + 1, 0)

	var gid: int = character360_group(active_index)
	if gid != 0:
		var made: Layer = add_layer(active_index + 1, gid)
		if made != null:
			made.is_character360 = true
			made.is_character360_motion = false
			made.is_bone_layer = false
			made.title = "Character 360 layer %d" % made.id
			var motion: Layer = character360_motion_layer(gid)
			if motion != null:
				made.character360_state = {
					"format": "ivory.character360.member.v2",
					"motion_layer": motion.id,
					"file_group": gid,
					"master_rig": true,
					"local_rig_enabled": true,
					"local_rig": {"bones": [], "smart_bones": []},
				}
				# Same skeleton, same rest pose. The sub-layer does not own
				# a rig of its own — it is posed by the file's — but it has
				# to carry a copy so exporting, saving and the timeline all
				# see a complete layer rather than one with a hole in it.
				made.rig = motion.rig.duplicate(true)
			changed.emit()
		return made

	return add_layer(active_index + 1)

## Creates a dedicated motion-only layer. Its pixels are still ordinary raster
## content so imported/cut-out art remains lossless, but the canvas treats the
## whole layer as an object: no brush, fill, shape, eraser or selection can
## write into it.
##
## Called by the Character 360 builder and by nothing else. There is no button
## anywhere that reaches this: a layer nobody can draw on is not something a
## finger should be able to create by mistake, which is exactly what the
## second `+` in the layers panel used to do.
func add_bone_layer_here() -> Layer:
	var l: Layer = add_layer_here()
	if l == null:
		return null
	l.is_bone_layer = true
	l.title = "Bone Motion %d" % l.id
	changed.emit()
	return l

## A copy dropped in directly above the original — the quickest safety net
## there is before trying something risky.
func duplicate_layer(index: int) -> Layer:
	if index < 0 or index >= layers.size() or layers.size() >= MAX_LAYERS:
		return null
	var before: Array = _snapshot()
	var src: Layer = layers[index]
	var copy: Layer = _spawn_layer()
	copy.title = src.title + " copy"
	copy.opacity = src.opacity
	copy.visible = src.visible
	copy.group_id = src.group_id
	copy.is_bone_layer = src.is_bone_layer
	copy.is_character360 = src.is_character360
	copy.is_character360_motion = src.is_character360_motion
	copy.character360_state = src.character360_state.duplicate(true)
	copy.motion_position = src.motion_position
	copy.motion_rotation = src.motion_rotation
	copy.motion_scale = src.motion_scale
	copy.surface.blend_from(src.surface, 1.0)
	# A copy of a rigged layer has to be one too.
	#
	# Copying the pixels alone gave a picture of a character: a layer that
	# looked right, could not be posed, and had lost every bone in it.
	# Everything that makes the layer what it is comes across — its
	# skeleton, its lip-sync ring and its pose track, and the rules that
	# keep its frames locked.
	# The copy exists for the same stretch of the scene the original does. A
	# duplicate born at the frame it was made on would be missing from every
	# frame its source appears in, which is never what duplicating means.
	copy.born_at = src.born_at
	copy.gone_at = src.gone_at
	copy.rig = src.rig.duplicate(true)
	copy.glow = src.glow
	copy.is_text = src.is_text
	copy.text_state = src.text_state.duplicate(true)
	copy.text_at = src.text_at
	copy.text_turn = src.text_turn
	copy.text_scale = src.text_scale
	copy.text_size = src.text_size
	copy.locked = src.locked
	copy.dangle = src.dangle
	copy.dangle_speed = src.dangle_speed
	copy.dangle_damp = src.dangle_damp
	copy.dangle_swing = src.dangle_swing
	copy.show_bones = src.show_bones
	if src.mouth_ring != null:
		copy.mouth_ring = MouthRing.from_dict(src.mouth_ring.to_dict())
	copy.mouths = src.mouths.duplicate()
	copy.mouth_power = src.mouth_power.duplicate()
	if src.poses != null and not src.poses.is_empty():
		copy.poses = RigTrack.from_dict(src.poses.to_dict())

	layers.insert(index + 1, copy)
	active_index = index + 1
	active_group = 0
	_rebuild()
	_record(UiKit.label_for("Duplicate layer", "نسخة مطابقة"), before)
	_announce_set()
	return copy

func can_remove(index: int) -> bool:
	if index < 0 or index >= layers.size():
		return false
	if layers[index].is_background:
		return false
	return layers.size() > 1

## Moves and resizes a layer's skeleton along with its drawing.
##
## The bones of a rigged layer are stored in the page's own coordinates, so a
## drawing scaled or moved by the selection tools used to leave its skeleton
## exactly where it was: the picture grew and the bones stayed the size they
## were, the picture slid across the page and the bones did not follow. The
## layer came away looking rigged and posing like something else.
##
## Every point in the rig goes through the same transform the pixels did —
## the rest positions, the posed positions, the spline the bones were drawn
## along, and the lengths, which scale but do not translate because a length
## is a distance and not a place.
func transform_rig(l: Layer, factor: float, shift: Vector2) -> void:
	if l == null or l.rig.is_empty():
		return
	# Not `scale`: this class is a Node2D and `scale` is already its own
	# transform. Shadowing it here reads as though the rig were being resized
	# by moving the stack, which is the one thing this must not do.
	var factor_safe: float = maxf(factor, 0.001)
	var doc: Dictionary = l.rig.duplicate(true)
	var moved: Array = []
	for row in doc.get("bones", []):
		var one: Dictionary = row
		for pair in [["ax", "ay"], ["bx", "by"], ["px", "py"], ["qx", "qy"]]:
			if not one.has(pair[0]):
				continue
			one[pair[0]] = float(one[pair[0]]) * factor_safe + shift.x
			one[pair[1]] = float(one[pair[1]]) * factor_safe + shift.y
		moved.append(one)
	if not moved.is_empty():
		doc["bones"] = moved

	var rest: Dictionary = doc.get("bones_rest", {})
	if not rest.is_empty():
		for key in ["a", "b"]:
			var pts: PackedVector2Array = rest.get(key, PackedVector2Array())
			for i in pts.size():
				pts[i] = pts[i] * factor_safe + shift
			rest[key] = pts
		var lens: PackedFloat32Array = rest.get("len", PackedFloat32Array())
		for i in lens.size():
			lens[i] = lens[i] * factor_safe
		rest["len"] = lens
		doc["bones_rest"] = rest

	var spline_pts: Array = doc.get("points", [])
	var again: Array = []
	for pt in spline_pts:
		var xy: Array = pt
		if xy.size() >= 2:
			again.append([float(xy[0]) * factor_safe + shift.x,
				float(xy[1]) * factor_safe + shift.y])
	if not again.is_empty():
		doc["points"] = again
	l.rig = doc
	# The poses are angles about pivots, and the pivots have just moved. A
	# track measured against the old skeleton would snap the drawing back to
	# where it used to stand the moment it was played.
	if l.poses != null and not l.poses.is_empty():
		l.poses = RigTrack.new()

## Takes a layer out of the scene from a given frame onward.
##
## The drawings before that frame are left exactly alone. Deleting a layer
## outright used to take it out of the whole scene, past and future together —
## so a layer added for one shot and no longer wanted could not be got rid of
## without also emptying it out of the forty frames it had already been in.
##
## Returns false when there is nothing before the frame to keep, in which case
## the caller should simply delete the layer.
func retire_layer(index: int, from_frame: int) -> bool:
	if index < 0 or index >= layers.size():
		return false
	var l: Layer = layers[index]
	if from_frame <= l.born_at:
		return false
	if l.cels.is_empty() or l.cels.last_frame() < from_frame:
		# Nothing on it before this point either. Retiring it would leave an
		# empty layer sitting in the list for no reason.
		return false
	var before: Array = _snapshot()
	l.gone_at = from_frame
	_rebuild()
	_record(UiKit.label_for("Retire layer", "إنهاء طبقة"), before)
	changed.emit()
	return true

func remove_layer(index: int) -> void:
	if not can_remove(index):
		return
	var before: Array = _snapshot()
	_detach(layers[index])
	layers.remove_at(index)
	var next: int = active_index
	if active_index >= index:
		next = active_index - 1
	active_index = clampi(next, 0, maxi(layers.size() - 1, 0))
	active_group = 0
	_rebuild()
	_record(UiKit.label_for("Delete layer", "حذف طبقة"), before)
	_announce_set()

## Moves a layer to a new slot and, at the same time, into or out of a
## folder. Both happen at once because doing them one after the other would
## leave the array in a state that breaks the folder-members-are-adjacent
## rule in between.
func relocate(from: int, to: int, group_id: int) -> void:
	if from < 0 or from >= layers.size():
		return
	var l: Layer = layers[from]
	if l.is_background:
		return
	var dest: int = clampi(to, 1, layers.size())
	if dest > from:
		dest -= 1
	dest = clampi(dest, 1, maxi(layers.size() - 1, 1))
	if dest == from and l.group_id == group_id:
		return
	var before: Array = _snapshot()
	layers.remove_at(from)
	l.group_id = group_id
	layers.insert(dest, l)
	active_index = layers.find(l)
	active_group = 0
	_rebuild()
	_record(UiKit.label_for("Move layer", "نقل طبقة"), before)
	_announce_set()

func set_active(index: int) -> void:
	var i: int = clampi(index, 0, maxi(layers.size() - 1, 0))
	active_group = 0
	active_index = i
	active_changed.emit(active_index)

func set_active_group(id: int) -> void:
	active_group = id
	active_changed.emit(active_index)

func set_visible_at(index: int, on: bool) -> void:
	if index < 0 or index >= layers.size():
		return
	var before: Array = _snapshot()
	layers[index].visible = on
	_apply_looks()
	_record(UiKit.label_for("Show or hide", "إظهار وإخفاء"), before)
	changed.emit()

## Silent on purpose: this fires on every slider tick. The panel records one
## history entry when the finger lifts, so undoing a fade is one tap rather
## than two hundred.
func set_opacity_at(index: int, value: float) -> void:
	if index < 0 or index >= layers.size():
		return
	layers[index].opacity = clampf(value, 0.0, 1.0)
	_apply_looks()

## Light or paint. Changing it costs nothing but a swapped material, so it
## can be turned on after the fact on a layer already drawn.
func set_glow_at(index: int, on: bool) -> void:
	if index < 0 or index >= layers.size():
		return
	layers[index].glow = on
	_apply_looks()
	changed.emit()

func set_locked_at(index: int, on: bool) -> void:
	if index < 0 or index >= layers.size():
		return
	var before: Array = _snapshot()
	layers[index].locked = on
	_record(UiKit.label_for("Lock layer", "قفل طبقة"), before)
	changed.emit()

## Merging changes pixels *and* structure, so both go into one entry and one
## tap takes the whole thing back.
func merge_down(index: int) -> bool:
	if index <= 0 or index >= layers.size():
		return false
	var upper: Layer = layers[index]
	var lower: Layer = layers[index - 1]
	# Motion-only layers are deliberately never merged. Merging would turn an
	# object into ordinary paint (or ordinary paint into an object layer),
	# violating the layer's contract.
	if upper.is_bone_layer or lower.is_bone_layer:
		return false

	var touched: Dictionary = {}
	for c in upper.surface.get_tile_coords():
		touched[c] = lower.surface.snapshot_tile(c)
	var steps: Array = [
		{"t": "pixels", "layer": lower.id, "tiles": touched},
		{"t": "arrangement", "state": capture_arrangement()},
	]

	lower.surface.blend_from(upper.surface, upper.opacity if upper.visible else 0.0)
	_detach(upper)
	layers.remove_at(index)
	active_index = clampi(index - 1, 0, maxi(layers.size() - 1, 0))
	active_group = 0
	_rebuild()
	_record(UiKit.label_for("Merge layers", "دمج طبقتين"), steps)
	_announce_set()
	return true

func clear_layer(index: int) -> void:
	if index < 0 or index >= layers.size():
		return
	var l: Layer = layers[index]
	var tiles: Dictionary = {}
	for c in l.surface.get_tile_coords():
		tiles[c] = l.surface.snapshot_tile(c)
	l.surface.clear_all()
	_record(UiKit.label_for("Erase layer", "مسح طبقة"),
		[{"t": "pixels", "layer": l.id, "tiles": tiles}])
	changed.emit()

# --------------------------------------------------------- group structure

## Folders are never created empty: the selected layer walks in with them.
## That also lets a folder simply dissolve when its last member leaves,
## which removes a whole class of "empty folder in the way" problems.
func group_layer(index: int) -> Group:
	if index < 0 or index >= layers.size() or groups.size() >= MAX_GROUPS:
		return null
	var l: Layer = layers[index]
	if l.is_background or l.group_id != 0:
		return null
	var before: Array = _snapshot()
	var g: Group = Group.new()
	g.id = _next_group_id
	_next_group_id += 1
	g.title = "Group %d" % g.id
	g.node = Node2D.new()
	g.node.name = "Group_%d" % g.id
	add_child(g.node)
	groups.append(g)
	l.group_id = g.id
	_rebuild()
	_record(UiKit.label_for("New folder", "مجلد جديد"), before)
	changed.emit()
	return g

func ungroup_layer(index: int) -> void:
	if index < 0 or index >= layers.size() or layers[index].group_id == 0:
		return
	var before: Array = _snapshot()
	layers[index].group_id = 0
	_rebuild()
	_record(UiKit.label_for("Out of folder", "إخراج من مجلد"), before)
	changed.emit()

func set_group_visible(id: int, on: bool) -> void:
	var g: Group = group_by_id(id)
	if g == null:
		return
	var before: Array = _snapshot()
	g.visible = on
	_apply_looks()
	_record(UiKit.label_for("Show or hide folder", "إظهار مجلد"), before)
	changed.emit()

## Silent for the same reason as layer opacity — see set_opacity_at.
func set_group_opacity(id: int, value: float) -> void:
	var g: Group = group_by_id(id)
	if g == null:
		return
	g.opacity = clampf(value, 0.0, 1.0)
	_apply_looks()

## Folding is a way of looking, not a change to the picture, so it stays out
## of the history. Undo should never spend a tap on it.
func set_group_collapsed(id: int, on: bool) -> void:
	var g: Group = group_by_id(id)
	if g == null:
		return
	g.collapsed = on
	changed.emit()

## Empties a folder without touching the drawings inside it.
func dissolve_group(id: int) -> void:
	if group_by_id(id) == null:
		return
	var before: Array = _snapshot()
	for l in layers:
		if l.group_id == id:
			l.group_id = 0
	if active_group == id:
		active_group = 0
	_rebuild()
	_record(UiKit.label_for("Remove folder", "إزالة مجلد"), before)
	changed.emit()

func set_solo(id: int) -> void:
	solo_id = id
	_apply_looks()
	changed.emit()

# ------------------------------------------------------- arrangement state

func _character360_meta(state: Dictionary) -> Dictionary:
	return LayerArrangement.character360_meta(state)

func capture_arrangement() -> Dictionary:
	return LayerArrangement.capture_arrangement(self)

func apply_arrangement(state: Dictionary) -> void:
	LayerArrangement.apply_arrangement(self, state)

# --------------------------------------------------------------- off-stage

func _detach(l: Layer) -> void:
	if l == null or _detached.has(l.id):
		return
	l.surface.settle()
	l.surface.sleep_all()
	if l.surface.get_parent() != null:
		l.surface.get_parent().remove_child(l.surface)
	_detached[l.id] = l

func _reattach(l: Layer) -> void:
	_detached.erase(l.id)
	if l.surface.get_parent() == null:
		add_child(l.surface)

## Called by the history once it no longer remembers a layer.
func purge_detached(keep: Dictionary) -> void:
	for id in _detached.keys():
		if keep.has(id):
			continue
		var l: Layer = _detached[id]
		_detached.erase(id)
		l.surface.dispose()
		# And whatever this layer's frames left on disk.
		#
		# Without it the spill folder grows by a file per cel per session and
		# nothing ever takes them away — which is the "clearing memory only
		# frees it for a moment" complaint one level further down, in a place
		# where nobody would think to look for it. A layer that redo can no
		# longer reach is a layer whose drawings are gone for good.
		if l.cels != null:
			l.cels.drop_spill()

# ------------------------------------------------------------ housekeeping

func _rebuild() -> void:
	_pack_groups()
	_drop_empty_groups()
	_reparent()
	_apply_motion_transforms()
	_apply_looks()

## Motion-layer transforms are node transforms, never raster edits. This keeps
## rotation and scale perfectly reversible and prevents repeated drags from
## softening the artwork.
func _apply_motion_transforms() -> void:
	for l in layers:
		if l.surface == null:
			continue
		if not l.is_bone_layer:
			l.surface.position = Vector2.ZERO
			l.surface.rotation = 0.0
			l.surface.scale = Vector2.ONE
			continue
		l.surface.rotation = l.motion_rotation
		l.surface.scale = Vector2.ONE * maxf(l.motion_scale, 0.001)
		l.surface.position = l.motion_position

## Pulls every folder's members together at the position of its lowest
## member, keeping their relative order. Called after any structural change,
## so nothing else in this file has to think about the adjacency rule.
func _pack_groups() -> void:
	var out: Array[Layer] = []
	var taken: Dictionary = {}
	for l in layers:
		if taken.has(l.id):
			continue
		if l.group_id == 0:
			out.append(l)
			taken[l.id] = true
			continue
		for m in layers:
			if m.group_id == l.group_id and not taken.has(m.id):
				out.append(m)
				taken[m.id] = true
	layers = out

func _drop_empty_groups() -> void:
	for i in range(groups.size() - 1, -1, -1):
		var g: Group = groups[i]
		if member_count(g.id) > 0:
			continue
		if active_group == g.id:
			active_group = 0
		if g.node != null:
			g.node.queue_free()
		groups.remove_at(i)

## Puts every surface under the right parent, then orders the parents and
## their children to match the flat array exactly.
func _reparent() -> void:
	for l in layers:
		var want: Node = self
		if l.group_id != 0:
			var g: Group = group_by_id(l.group_id)
			if g != null and g.node != null:
				want = g.node
		var had: Node = l.surface.get_parent()
		if had != want:
			if had != null:
				had.remove_child(l.surface)
			want.add_child(l.surface)

	var order: Array[Node] = []
	var seen: Dictionary = {}
	for l in layers:
		if l.group_id == 0:
			order.append(l.surface)
		elif not seen.has(l.group_id):
			seen[l.group_id] = true
			var order_group: Group = group_by_id(l.group_id)
			if order_group != null and order_group.node != null:
				order.append(order_group.node)
	# Moved only where the order actually differs.
	#
	# `move_child` is a scene-tree operation: it re-indexes the children and
	# marks the canvas dirty. Calling it for every layer on every structural
	# change meant that adding one layer to a stack of twenty did twenty of
	# them, nineteen of which put a node exactly where it already was. That
	# is most of what made adding a layer feel slow, and none of it did
	# anything.
	for i in order.size():
		if order[i].get_index() != i:
			move_child(order[i], i)

	for g in groups:
		if g.node == null:
			continue
		var slot: int = 0
		for l in layers:
			if l.group_id == g.id:
				g.node.move_child(l.surface, slot)
				slot += 1

## A layer's final look is its own settings folded together with its
## folder's. Dimming a folder dims everything inside it, which is exactly
## what a folder is for.
## How sharp each layer currently is, 0 soft to 1 sharp. Written by the
## timeline whenever the playhead or the focus lines move.
var focus_sharpness: Dictionary = {}
var _blur_shader: Shader = null

## Depth of field, put on the layers.
##
## A folder speaks for everything under it: one focus line on the top layer of
## a folder makes the whole folder the subject, because a figure drawn across
## body, arm and head is one thing in the shot even though it is three layers
## in the stack. Asking for a line on each would be asking the artist to
## repeat what the folder already says.
func apply_focus(clip: Variant, frame: int) -> void:
	focus_sharpness.clear()
	if clip == null or not clip.focus_live(frame):
		for l in layers:
			_set_blur(l, 0.0)
		return

	# A folder is sharp if anything inside it is.
	var folder_sharp: Dictionary = {}
	for l in layers:
		if l.group_id == 0:
			continue
		var sharp: float = clip.focus_at(l.id, frame)
		if not folder_sharp.has(l.group_id):
			folder_sharp[l.group_id] = sharp
		else:
			folder_sharp[l.group_id] = maxf(float(folder_sharp[l.group_id]), sharp)

	# The aperture belongs to the shot, not to the layer being softened: one
	# camera is looking at all of them, and two layers blurred through two
	# different irises in one frame would be two cameras. So the blade count
	# comes from whichever focus line is running here.
	var iris: int = clip.aperture_at(frame)
	for l in layers:
		var sharp: float = clip.focus_at(l.id, frame)
		if l.group_id != 0 and folder_sharp.has(l.group_id):
			sharp = maxf(sharp, float(folder_sharp[l.group_id]))
		focus_sharpness[l.id] = sharp
		_set_blur(l, 1.0 - sharp, iris)

## The blur is a material on the layer itself, so it costs nothing at all
## while the radius is zero — which is every frame of every project that is
## not using depth of field.
func _set_blur(l: Layer, amount: float, blades: int = 6) -> void:
	if l == null or l.surface == null:
		return
	if amount > 0.004 and _blur_shader == null:
		_blur_shader = load("res://shaders/lens_blur.gdshader") as Shader
	l.surface.set_blur(amount, _blur_shader, blades)

func _apply_looks() -> void:
	for l in layers:
		var alpha: float = l.opacity
		var shown: bool = l.visible
		var g: Group = group_by_id(l.group_id)
		if g != null:
			alpha *= g.opacity
			shown = shown and g.visible
		# A chart shows one member. Asked before solo, so that looking at a
		# single layer on its own still overrides everything — solo is a
		# thing the user is doing right now, and it should win.
		if g != null and g.is_switch and not switch_shows(l):
			shown = false
		if solo_id != 0:
			shown = l.id == solo_id
			alpha = l.opacity
		# ...and not outside the stretch of the scene this layer exists for.
		#
		# Asked here as well as in `show_frame` because this runs whenever
		# anything about a layer's appearance changes, and it runs *after* —
		# so without this line, opening the layers panel on a frame before a
		# layer was added would bring it back.
		if not l.alive_at(shown_frame):
			shown = false
		l.surface.visible = shown
		# Premultiplied pixels dim on every channel at once, so fading a
		# layer uses the same number in all four. Touching alpha alone would
		# leave colours too strong for the alpha carrying them and the layer
		# would look bruised instead of faint.
		l.surface.modulate = Color(alpha, alpha, alpha, alpha)
		l.surface.set_glow(l.glow)

# ------------------------------------------------------------- whole stack

func begin_frames(index: int, first_frame: int = 0) -> bool:
	if index < 0 or index >= layers.size():
		return false
	var l: Layer = layers[index]
	if l.cels.has_frame(first_frame):
		l.cels.load_into(l.surface, first_frame)
		return true
	l.cels.capture_surface(l.surface, first_frame)
	return true

## Which frame the stack is currently standing on.
##
## Kept because appearance is decided in one place and the frame is decided in
## another, and a layer's lifetime is a fact about both.
var shown_frame: int = 0

func show_frame(at: int, write_back: bool = true) -> void:
	shown_frame = at
	for l in layers:
		l.cels.show_frame(l.surface, at, write_back)
		# The working set follows the playhead.
		#
		# Drawings far from where the animator is standing go to disk and come
		# back the moment anything asks for them. Done here rather than on a
		# timer because this is the one place that knows where "here" is, and
		# a scene is only ever expensive in the direction you have walked away
		# from. A short clip is left alone entirely.
		l.cels.page_around(at)
		# A layer only shows across the stretch of the scene it exists for.
		#
		# Hidden rather than emptied, which is the whole reason this can be
		# undone by simply changing two numbers: the drawings on a retired
		# layer are still there, and stepping back to a frame before it was
		# retired shows them again exactly as they were.
		if l.surface != null:
			l.surface.visible = l.visible and l.alive_at(at) \
				and (l.skin == null or not is_instance_valid(l.skin))

## Inserts one blank animation frame across every layer. All drawings and
## holds from the insertion point onward move together, so the scene stays
## synchronized.
func insert_blank_frame_after(frame: int) -> void:
	commit_all_cels()
	for l in layers:
		# Do not convert a non-animated static layer into an animated layer.
		# Existing animation tracks all shift together so timing remains aligned.
		if not l.cels.is_empty():
			l.cels.insert_blank_after(l.surface, frame)
	changed.emit()

func commit_all_cels() -> void:
	for l in layers:
		l.cels.commit(l.surface)

func update_view(view_world: Rect2, zoom: float) -> void:
	for l in layers:
		l.surface.update_view(view_world, zoom)

func flush_all() -> void:
	for l in layers:
		l.surface.flush()

func settle_all() -> void:
	for l in layers:
		l.surface.settle()
		var keep: Array = []
		if l.cels.loaded >= 0:
			keep.append(l.cels.loaded)
		l.cels.prune_cache(keep)

## What the eye sees at one point: every visible layer, bottom to top.
func sample(world_pos: Vector2) -> Color:
	var out: Color = Color(0.0, 0.0, 0.0, 0.0)
	for l in layers:
		if not l.surface.visible:
			continue
		var alpha: float = l.surface.modulate.a
		if alpha <= 0.001:
			continue
		var c: Color = l.surface.sample(world_pos)
		c.a *= alpha
		if c.a <= 0.0:
			continue
		var a: float = c.a + out.a * (1.0 - c.a)
		if a <= 0.0:
			continue
		out = Color(
			(c.r * c.a + out.r * out.a * (1.0 - c.a)) / a,
			(c.g * c.a + out.g * out.a * (1.0 - c.a)) / a,
			(c.b * c.a + out.b * out.a * (1.0 - c.a)) / a,
			a)
	return out

## Flattened pixels of a region — what the fill tool reads, so a fill on a
## clean layer still respects linework drawn on the layer below.
func read_region(rect: Rect2i) -> Image:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return null
	var out: Image = Image.create_empty(rect.size.x, rect.size.y, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.0, 0.0, 0.0, 0.0))
	for l in layers:
		if not l.surface.visible or l.surface.modulate.a <= 0.001:
			continue
		l.surface.read_region(rect, out)
	return out

# -------------------------------------------------------------- thumbnails

func refresh_thumb(index: int, px: int = 96) -> void:
	if index < 0 or index >= layers.size():
		return
	var l: Layer = layers[index]
	var box: Rect2i = l.surface.content_bounds()
	if box.size.x <= 0 or box.size.y <= 0:
		l.thumb = null
		return
	# Keep the read cheap no matter how far the drawing sprawls.
	var limit: int = 4096
	if maxi(box.size.x, box.size.y) > limit:
		var centre: Vector2i = box.position + Vector2i(roundi(float(box.size.x) * 0.5), roundi(float(box.size.y) * 0.5))
		var half: int = int(float(limit) * 0.5)
		box = Rect2i(centre - Vector2i(half, half), Vector2i(limit, limit))
	var img: Image = l.surface.read_region(box)
	if img == null:
		l.thumb = null
		return
	img.resize(px, px, Image.INTERPOLATE_BILINEAR)
	if l.thumb == null:
		l.thumb = ImageTexture.create_from_image(img)
	else:
		l.thumb.update(img)

func refresh_all_thumbs(px: int = 96) -> void:
	for i in layers.size():
		refresh_thumb(i, px)

# ----------------------------------------------------------------- display

## The panel's row list, top of the picture first. Each entry is either
## {"kind": "group", "gid": n} or {"kind": "layer", "index": n}.
func display_rows() -> Array:
	var rows: Array = []
	var i: int = layers.size() - 1
	while i >= 0:
		var l: Layer = layers[i]
		if l.group_id == 0:
			rows.append({"kind": "layer", "index": i})
			i -= 1
			continue
		var bottom: int = i
		while bottom - 1 >= 0 and layers[bottom - 1].group_id == l.group_id:
			bottom -= 1
		var g: Group = group_by_id(l.group_id)
		rows.append({"kind": "group", "gid": l.group_id})
		if g == null or not g.collapsed:
			for k in range(i, bottom - 1, -1):
				rows.append({"kind": "layer", "index": k})
		i = bottom - 1
	return rows
