class_name RigSkin
extends MeshInstance2D
## A layer, drawn bent.
##
## ## The gap this closes
##
## Everything built over the last several stages could pose a layer and none
## of it could *show* the pose on the canvas. `RigTrack` held the poses,
## `AnimPlayer` read them at the right moment and emitted them, the B-Spline
## room could bend a figure and the mouth ring could bend a mouth — and the
## canvas went on drawing the layer flat, because a layer is drawn as a grid
## of tiled sprites and a grid of sprites cannot bend.
##
## The B-Spline room got around that by *baking*: it renders the deformed mesh
## into a `SubViewport`, reads the pixels back, and stamps them into the
## layer. That is right for committing a pose and hopeless for playing one —
## a viewport render and a texture readback per frame per layer is a cost of
## an entirely different order from drawing a mesh.
##
## So the pose is not baked while it plays. This node sits where the layer's
## surface sits, holds the layer's art as one texture, and draws it through a
## mesh whose points move. The surface is hidden while it is showing. Nothing
## is written to the layer, which is the other half of why this is right:
## playing an animation should not modify the drawing.
##
## ## Why the mesh is regular and even
##
## No adaptive subdivision and nothing to place. The deformations here — a
## bone bending a limb, a ring closing a mouth — are smooth everywhere, so
## there is nowhere that deserves more points than anywhere else, and a grid
## of two densities meeting would show the seam between them. Graph paper is
## the right shape for this problem.
##
## Thirty-two cells across is past the point where a bend looks faceted at the
## size these things are drawn, and it is 1089 points — nothing to move once a
## frame, and the same triangles and texture coordinates every time, so only
## the positions are ever rebuilt.

## Which layer this is standing in for.
var layer_id: int = 0
## Where the captured art sits in the world, and how big it is.
var rect: Rect2i = Rect2i()
## Cells across. Held rather than assumed, so a caller may ask for a coarser
## skin on a slow device without this class having to know why.
var cells: int = 32

var _rest: PackedVector2Array = PackedVector2Array()
var _uv: PackedVector2Array = PackedVector2Array()
var _tris: PackedInt32Array = PackedInt32Array()
var _live: PackedVector2Array = PackedVector2Array()
var _mesh: ArrayMesh = null
## Which separate drawing each mesh point belongs to. See `_read_islands`.
var _island: PackedInt32Array = PackedInt32Array()
var _disc_nodes: Array[MeshInstance2D] = []
var _disc_angles: PackedFloat32Array = PackedFloat32Array()
var _disc_weights: PackedFloat32Array = PackedFloat32Array()
var _character360_discs := false

## How hard the volume-repair pass (below) pulls a thinned joint back out.
## 0 turns it off. 1 asks it to fully restore the joint's rest area, which is
## more correction than a drag needs when the pose is only lightly bent — see
## `pose_bones` for why a middling value is the one actually used.
const VOLUME_REPAIR_STRENGTH: float = 0.55
## Jacobi passes the repair runs per pose. Two is enough for a correction to
## reach a joint's immediate ring of neighbours without paying for a solve
## every frame; see `ivory_skin.cpp::preserve_volume`.
const VOLUME_REPAIR_PASSES: int = 2


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# The same material the bake uses. A layer's pixels are stored with the
	# colour already multiplied by the alpha, and drawing them without saying
	# so gives every soft edge a dark rim — the classic halo that looks like
	# bad anti-aliasing and is actually the wrong blend mode.
	material = PaintSurface.premultiplied_material()

## Takes a picture of the layer and builds the mesh over it.
##
## Called once when posing begins, not per frame. The capture is the expensive
## part — it is a region read off the surface — and it is exactly what must
## *not* happen every frame.
##
## Returns false when the layer has nothing on it. A skin over an empty layer
## would be a mesh of transparent pixels doing work for no picture.
## Installs the optional multi-disc artwork without baking. Each disc shares
## the same live ArrayMesh, so a pose changes vertices once and all angle
## drawings follow it. Opacity is the GPU blend weight calculated by the
## native Character 360 controller.
func set_character360_discs(state: Dictionary) -> void:
	_clear_disc_nodes()
	_character360_discs = false
	var rows: Array = state.get("turn_discs", [])
	if rows.is_empty():
		self_modulate.a = 1.0
		return
	for row in rows:
		if not row is Dictionary or not row.has("png"):
			continue
		var bytes: PackedByteArray = row["png"]
		var img := Image.new()
		if img.load_png_from_buffer(bytes) != OK:
			continue
		var node := MeshInstance2D.new()
		node.texture_filter = texture_filter
		node.texture = ImageTexture.create_from_image(img)
		node.material = material
		node.position = Vector2.ZERO
		node.z_index = 1
		node.modulate = Color(1, 1, 1, 0)
		add_child(node)
		_disc_nodes.append(node)
		_disc_angles.append(float(row.get("angle", 0.0)))
	_disc_weights.resize(_disc_nodes.size())
	for i in _disc_weights.size():
		_disc_weights[i] = 0.0
	_character360_discs = _disc_nodes.size() > 0
	if _character360_discs:
		self_modulate.a = 0.0
		_apply_disc_mesh()
	else:
		self_modulate.a = 1.0

func set_character360_disc_weights(weights: PackedFloat32Array) -> void:
	if not _character360_discs:
		return
	for i in _disc_weights.size():
		_disc_weights[i] = weights[i] if i < weights.size() else 0.0
	_apply_disc_weights()

func clear_character360_discs() -> void:
	_clear_disc_nodes()
	_character360_discs = false
	self_modulate.a = 1.0

func _clear_disc_nodes() -> void:
	for n in _disc_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_disc_nodes.clear()
	_disc_angles = PackedFloat32Array()
	_disc_weights = PackedFloat32Array()

## Shows exactly one reference drawing at a time — the one whose weight is
## highest — instead of cross-fading every nearby pose on top of each other.
## A left/right pose change now reads as switching to the next PNG the
## artist drew, not as two or three drawings blended into a ghost.
func _apply_disc_weights() -> void:
	if _disc_nodes.is_empty():
		return
	var best_i := 0
	var best_w := -1.0
	for i in _disc_weights.size():
		if _disc_weights[i] > best_w:
			best_w = _disc_weights[i]
			best_i = i
	for i in _disc_nodes.size():
		_disc_nodes[i].modulate = Color(1, 1, 1, 1.0 if i == best_i else 0.0)

func _apply_disc_mesh() -> void:
	if _mesh == null:
		return
	for n in _disc_nodes:
		if is_instance_valid(n):
			n.mesh = _mesh
	_apply_disc_weights()

func bind_layer(l: LayerStack.Layer, want_cells: int = 32) -> bool:
	if l == null or l.surface == null:
		return false
	l.surface.flush()
	var box: Rect2i = l.surface.content_bounds()
	if box.size.x < 2 or box.size.y < 2:
		return false
	var art: Image = l.surface.read_region(box)
	if art == null:
		return false

	layer_id = l.id
	rect = box
	cells = maxi(want_cells, 2)
	texture = ImageTexture.create_from_image(art)
	_rest = MouthRing.rest_grid(box, cells)
	_uv = MouthRing.grid_uv(cells)
	_tris = MouthRing.grid_tris(cells)
	_live = _rest.duplicate()
	_island = _read_islands(art)
	_rebuild()
	return true

## Which separate drawing each point of the mesh belongs to.
##
## Nought means empty paper. Everything else is an island number, and two
## points carry the same number only if you could walk from one to the other
## without leaving the ink.
##
## This is what stops a skeleton reaching across the page. A layer is one
## picture as far as the canvas is concerned, but an artist very often puts
## two things on it — a figure and the prop beside it, two characters in one
## shot, a hand drawn off to the side to be positioned later. Bones drawn on
## one of them used to drag the others along, because weight was decided by
## distance alone and the other drawing was *near*.
##
## Found by flooding a coarse occupancy grid rather than the pixels. Eight-
## connected, at the same resolution as the mesh, which is exactly the
## resolution the answer is wanted at — and a thirty-two square grid is a
## thousand cells, so this costs nothing at bind time.
func _read_islands(art: Image) -> PackedInt32Array:
	# The same answer, read by the C++ half when it is there — one pass over
	# the raw bytes and one flood fill, instead of a bound engine call and a
	# four-float `Color` per sample. Everything below is what runs when it is
	# not there, and it is not dead code: it is what a checkout with no `bin/`
	# runs. See `scripts/native.gd`.
	var fast: Object = Native.skin()
	if fast != null:
		var got: PackedInt32Array = fast.call("read_islands", art, cells)
		if got.size() == (cells + 1) * (cells + 1):
			return got
	var across: int = cells
	var down: int = cells
	var w: int = art.get_width()
	var h: int = art.get_height()
	var filled: PackedByteArray = PackedByteArray()
	filled.resize(across * down)

	# --- one pass over the raw bytes, not a call per pixel ---
	#
	# This is what made dropping a skeleton onto a figure feel slow.
	#
	# It used to ask `Image.get_pixel` for every sample: a bound method call
	# that goes out to the engine, builds a `Color` of four floats, hands it
	# back into script, and is then thrown away for one comparison on one of
	# the four. At sixteen samples a cell over a thirty-two square grid that
	# is sixteen thousand of them before a single bone can be seen, and on a
	# phone it is most of a second of nothing happening.
	#
	# The pixels are already a flat byte array. Read once, indexed directly,
	# and compared as a byte — no Color is ever built and nothing crosses the
	# script boundary but the one `get_data` call. The answer is identical:
	# alpha above sixteen of two hundred and fifty-five is the same test as
	# alpha above 0.06.
	#
	# It also now **walks every pixel of a cell** rather than a four-by-four
	# sample of it, which is the accuracy half of the same change. A sampled
	# cell can miss a thin stroke that crosses it between the samples, and a
	# cell wrongly called empty is a cell with no mesh under it — which is a
	# piece of the drawing that a bone cannot reach and that the pose leaves
	# standing still. Reading them all is affordable now, and it is affordable
	# precisely because it stopped being sixteen thousand engine calls.
	var raw: PackedByteArray = art.get_data()
	var stride: int = 0
	var fmt: int = art.get_format()
	if fmt == Image.FORMAT_RGBA8:
		stride = 4
	elif fmt == Image.FORMAT_RGB8:
		stride = 3
	elif fmt == Image.FORMAT_LA8:
		stride = 2
	if stride == 4 and raw.size() >= w * h * 4:
		for cy in down:
			var y0: int = int(float(cy) * float(h) / float(down))
			var y1: int = mini(maxi(int(float(cy + 1) * float(h)
				/ float(down)), y0 + 1), h)
			for cx in across:
				var x0: int = int(float(cx) * float(w) / float(across))
				var x1: int = mini(maxi(int(float(cx + 1) * float(w)
					/ float(across)), x0 + 1), w)
				var here: bool = false
				for y in range(y0, y1):
					var row: int = y * w * 4
					for x in range(x0, x1):
						if raw[row + x * 4 + 3] > 16:
							here = true
							break
					if here:
						break
				filled[cy * across + cx] = 1 if here else 0
	else:
		# Anything that is not eight-bit RGBA — which a layer should never be,
		# but a reference or an import might — falls back to the slow reliable
		# way rather than guessing at a layout.
		for cy in down:
			for cx in across:
				var x0b: int = int(float(cx) * float(w) / float(across))
				var x1b: int = maxi(int(float(cx + 1) * float(w)
					/ float(across)), x0b + 1)
				var y0b: int = int(float(cy) * float(h) / float(down))
				var y1b: int = maxi(int(float(cy + 1) * float(h)
					/ float(down)), y0b + 1)
				var step_x: int = maxi(int(float(x1b - x0b) / 4.0), 1)
				var step_y: int = maxi(int(float(y1b - y0b) / 4.0), 1)
				var found: bool = false
				for y in range(y0b, mini(y1b, h), step_y):
					for x in range(x0b, mini(x1b, w), step_x):
						if art.get_pixel(x, y).a > 0.06:
							found = true
							break
					if found:
						break
				filled[cy * across + cx] = 1 if found else 0

	var label: PackedInt32Array = PackedInt32Array()
	label.resize(across * down)
	var next: int = 0
	var queue: PackedInt32Array = PackedInt32Array()
	for start in across * down:
		if filled[start] == 0 or label[start] != 0:
			continue
		next += 1
		label[start] = next
		queue.clear()
		queue.append(start)
		var head: int = 0
		while head < queue.size():
			var at: int = queue[head]
			head += 1
			var ax: int = at % across
			var ay: int = int(float(at) / float(across))
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx: int = ax + dx
					var ny: int = ay + dy
					if nx < 0 or ny < 0 or nx >= across or ny >= down:
						continue
					var nat: int = ny * across + nx
					if filled[nat] == 0 or label[nat] != 0:
						continue
					label[nat] = next
					queue.append(nat)

	# The mesh has one more point than it has cells in each direction, and a
	# point sits at a corner where up to four cells meet. It takes the island
	# of whichever of them has ink, so the edge of a drawing belongs to the
	# drawing rather than to the paper beside it.
	var out: PackedInt32Array = PackedInt32Array()
	out.resize((cells + 1) * (cells + 1))
	for gy in cells + 1:
		for gx in cells + 1:
			var found: int = 0
			for dy in range(-1, 1):
				for dx in range(-1, 1):
					var cx2: int = gx + dx
					var cy2: int = gy + dy
					if cx2 < 0 or cy2 < 0 or cx2 >= across or cy2 >= down:
						continue
					var lab: int = label[cy2 * across + cx2]
					if lab != 0:
						found = lab
			out[gy * (cells + 1) + gx] = found
	return out

## Which island each bone lies on, from its rest line.
##
## Sampled along the bone rather than taken from one end: a bone drawn from
## just outside a figure into the middle of it belongs to the figure, and
## reading only its first point would say it belongs to nothing.
##
## A bone that touches no ink at all comes back as nought and is allowed to
## move everything, which is the right answer for a bone somebody has drawn
## in empty space — it has no drawing of its own to be confined to.
func bone_islands(rest_a: PackedVector2Array,
		rest_b: PackedVector2Array) -> PackedInt32Array:
	var n: int = mini(rest_a.size(), rest_b.size())
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(n)
	if _island.is_empty():
		return out
	var side: int = cells + 1
	for i in n:
		var tally: Dictionary = {}
		for s in 17:
			var p: Vector2 = rest_a[i].lerp(rest_b[i], float(s) / 16.0)
			var gx: int = clampi(int(round((p.x - float(rect.position.x))
				/ maxf(float(rect.size.x), 1.0) * float(cells))), 0, cells)
			var gy: int = clampi(int(round((p.y - float(rect.position.y))
				/ maxf(float(rect.size.y), 1.0) * float(cells))), 0, cells)
			var lab: int = _island[gy * side + gx]
			if lab == 0:
				continue
			tally[lab] = int(tally.get(lab, 0)) + 1
		var best: int = 0
		var best_n: int = 0
		for key in tally.keys():
			if int(tally[key]) > best_n:
				best_n = int(tally[key])
				best = int(key)
		out[i] = best
	return out

func islands() -> PackedInt32Array:
	return _island

## The rest positions, so a caller can work out where each point should go
## without this class knowing what is doing the moving. A bone rig, a mouth
## ring and a puppet warp all have completely different ideas about that, and
## none of them belongs in here.
func rest_points() -> PackedVector2Array:
	return _rest

## Moves every point through a rule and redraws.
##
## The rule is given a rest position and returns where it should be. Passing a
## Callable rather than a table of offsets is what lets one skin serve the
## mouth ring, the bone rig and anything added later — this class holds the
## picture and the triangles, and has no opinion about the bending.
func reshape(rule: Callable) -> void:
	if _rest.is_empty() or not rule.is_valid():
		return
	if _live.size() != _rest.size():
		_live = _rest.duplicate()
	for i in _rest.size():
		_live[i] = rule.call(_rest[i])
	_rebuild()

## The same, for a rule that also wants to know which drawing a point is on.
##
## Kept separate rather than folded into `reshape` so the mouth ring — which
## has no use for islands and is called on every frame of every talking layer
## — goes on paying nothing for them.
func reshape_by_island(rule: Callable) -> void:
	if _rest.is_empty() or not rule.is_valid():
		return
	if _live.size() != _rest.size():
		_live = _rest.duplicate()
	var have: bool = _island.size() == _rest.size()
	for i in _rest.size():
		_live[i] = rule.call(_rest[i], _island[i] if have else 0)
	_rebuild()

## Bends the whole skin to one set of bones.
##
## ## Why this exists beside `reshape_by_island`
##
## `reshape_by_island` takes a `Callable` and asks it once per point, which is
## what lets one skin serve the mouth ring, the skeleton and anything added
## later without this class holding an opinion about the bending. It is the
## right shape for the problem and it is also a call into GDScript per point
## per frame.
##
## The skeleton is the one caller that does this a thousand points at a time on
## every frame of a pose, so it gets a route that hands the whole job across at
## once. The arithmetic on the other side is the arithmetic in `bone_rule` and
## nothing else — see `native/ivory/src/ivory_skin.cpp`, which quotes the
## reasoning back.
##
## Falls through to the `Callable` when there is no native half, so a pose is
## the same pose either way.
## ## The seam a single-bone fix cannot reach
##
## `bone_rule`/`deform` make one bone's influence exact — an offset turned by
## one rotation cannot change length, full stop. What that does not cover is
## the *blend between two bones*: where two influence regions overlap, the
## anchor a point is measured from is a weighted average of two moving
## anchors, and a weighted average of two things converging can close faster
## than either one alone moved — the same reason the midpoint between two
## people walking toward each other closes faster than either person's own
## stride. The flesh keeps its exact offset from that anchor, so it is
## carried in with it: a local thinning right at the seam between two bones,
## worst exactly where a joint is bent hardest. Smaller than the fault fixed
## above, and still a real, visible squeeze on a sharply bent elbow or knee.
##
## `preserve_volume` closes that second gap. It measures how much each
## point's own little patch of mesh has gained or lost area against its rest
## shape, then nudges the point relative to its mesh neighbours to push that
## back toward one — see `ivory_skin.cpp` for the derivation. It runs after
## the bone deform, on its output, and only when the native skin is present:
## a Jacobi correction pass over a thousand points, several times a pose, is
## exactly the per-point GDScript cost the native half exists to avoid, so
## there is no GDScript fallback for this particular repair. Its absence
## leaves the pose `deform` already produces — correct for one bone, merely
## a little thin at a seam between two — which is what every build had before
## this pass existed.
func pose_bones(rest_a: PackedVector2Array, rest_b: PackedVector2Array,
		now_a: PackedVector2Array, now_b: PackedVector2Array) -> void:
	if _rest.is_empty():
		return
	var bone_island: PackedInt32Array = bone_islands(rest_a, rest_b)
	var fast: Object = Native.skin()
	if fast != null:
		var have: PackedInt32Array = _island if _island.size() == _rest.size() \
			else PackedInt32Array()
		var got: PackedVector2Array = fast.call("deform", _rest, have,
			rest_a, rest_b, now_a, now_b, bone_island)
		if got.size() == _rest.size():
			if VOLUME_REPAIR_STRENGTH > 0.0 and not _tris.is_empty():
				# MassKeeper is deliberately joint-local: single-bone regions stay
				# rigid and only the overlap around a real joint receives area repair.
				var keeper: Object = Native.mass_keeper()
				if keeper != null:
					var fixed: PackedVector2Array = keeper.call("preserve_joint_mass",
						got, _rest, _tris, rest_a, rest_b,
						VOLUME_REPAIR_STRENGTH, VOLUME_REPAIR_PASSES)
					if fixed.size() == got.size():
						got = fixed
			_live = got
			_rebuild()
			return
	reshape_by_island(bone_rule(rest_a, rest_b, now_a, now_b, bone_island))

## Puts every point back where it started.
func rest_pose() -> void:
	if _rest.is_empty():
		return
	_live = _rest.duplicate()
	_rebuild()

func set_character360_onion(rest_a: PackedVector2Array, rest_b: PackedVector2Array,
		back_a: PackedVector2Array, back_b: PackedVector2Array,
		forward_a: PackedVector2Array, forward_b: PackedVector2Array,
		back_tint: Color, forward_tint: Color) -> void:
	# Onion ghosts are meshes, not baked images. They therefore show the actual
	# previous/next rig pose and remain cheap to move with the live character.
	_clear_pose_onion()
	if not _character360_discs and texture == null:
		return
	if not back_a.is_empty():
		_make_pose_ghost(rest_a, rest_b, back_a, back_b, back_tint, 0.28)
	if not forward_a.is_empty():
		_make_pose_ghost(rest_a, rest_b, forward_a, forward_b, forward_tint, 0.28)

func _clear_pose_onion() -> void:
	for n in get_children():
		if n is MeshInstance2D and n.get_meta("ivory_pose_onion", false):
			n.queue_free()

func _make_pose_ghost(rest_a: PackedVector2Array, rest_b: PackedVector2Array,
		now_a: PackedVector2Array, now_b: PackedVector2Array,
		tint: Color, alpha: float) -> void:
	var ghost := MeshInstance2D.new()
	ghost.set_meta("ivory_pose_onion", true)
	ghost.texture_filter = texture_filter
	ghost.texture = texture
	ghost.material = material
	var uv := _uv
	var live := RigSkin.bone_rule(rest_a, rest_b, now_a, now_b, bone_islands(rest_a, rest_b))
	var verts := PackedVector2Array()
	verts.resize(_rest.size())
	for i in _rest.size():
		verts[i] = live.call(_rest[i], _island[i] if _island.size() == _rest.size() else 0)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = _tris
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	ghost.mesh = am
	ghost.modulate = Color(tint.r, tint.g, tint.b, alpha)
	ghost.z_index = -1
	add_child(ghost)

func _rebuild() -> void:
	if _live.size() < 3 or _tris.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _live
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_INDEX] = _tris
	# A fresh ArrayMesh each time rather than a surface updated in place.
	# Godot has no partial surface update for ArrayMesh, and clearing and
	# re-adding one surface of a thousand points is cheaper than it sounds —
	# far cheaper than the viewport round trip this replaces.
	# Not `mesh`: this class is a MeshInstance2D and `mesh` is its own
	# property. The local was hiding it, so the two lines below read as though
	# they were assigning something to itself.
	var built: ArrayMesh = ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh = built
	mesh = built
	if _character360_discs:
		self_modulate.a = 0.0
		_apply_disc_mesh()

# ------------------------------------------------------------ the two rules

## Bends a mouth through its ring, for one mouth shape.
##
## Everything hard about this was settled and tested in `mouth_ring.gd`: the
## bend is exact on the ring, it lets go before it reaches the cheeks, and it
## cannot fold the mesh through itself. This is the two lines that use it.
static func mouth_rule(ring: MouthRing, shape: PackedFloat32Array) -> Callable:
	var factors: Dictionary = ring.factors(shape)
	return func(p: Vector2) -> Vector2:
		return ring.warp(p, factors)

## Moves a point with the bones nearest it.
##
## ## What was wrong, measured
##
## The rule here used to do what nearly every skinning implementation does at
## first: work out where each bone would put the point, and average those
## positions by weight. It is the obvious thing and it has a famous failure,
## and this app had it. Averaging two *positions* is a straight line between
## them, and a straight line between two points on a circle passes inside the
## circle — so the flesh at a joint is dragged toward the joint as it bends,
## and the harder the bend the worse it gets.
##
## Measured on a ring of flesh drawn twenty units out from an elbow:
##
##     bend      old, nearest point      new
##      30°            19.32            18.79
##      90°            14.14            16.48
##     150°             5.18            15.50
##     179°             0.17            19.38
##
## At a hundred and fifty degrees the old rule pulled the flesh in to a
## quarter of where it was drawn. At a hundred and seventy-nine it collapsed
## it onto the joint outright and the mesh folded through itself. That is the
## pinched, melting elbow, and it is not a matter of taste or of tuning — it
## is what averaging positions does.
##
## ## What it does now
##
## The point is not moved by each bone and then averaged. Instead:
##
## 1. Every bone contributes its **anchor** — the point on it nearest the
##    flesh — both where it rests and where it has moved to. Those are averaged
##    by weight, giving one rest anchor and one moved anchor.
## 2. Every bone contributes its **turn**, and those are averaged *as
##    directions*, by summing unit vectors and taking the angle of the sum.
##    That is the correct mean for angles: it never has to choose which way
##    round to go, and it cannot land between two angles at a shorter radius,
##    because a direction has no radius.
## 3. The flesh keeps its offset from the rest anchor, and that offset is
##    turned once by the averaged angle.
##
## The third step is the whole of it. One rotation applied to one offset
## preserves that offset's length **exactly** — a rotation matrix is an
## isometry, and no weighted average of positions is ever taken. The flesh
## cannot be pulled toward the joint by any bend whatsoever, because nothing
## in the arithmetic is capable of shortening it.
##
## ## Reach
##
## Weights fall to nothing at a finite distance instead of trailing off
## forever. Inverse-square never actually reaches zero, so every bone in the
## figure was tugging at every pixel of it — a hand closing dragged the far
## foot by a hair. The kernel here is smooth, reaches zero at about twice the
## bone's own length, and has no singularity where the flesh sits on the bone,
## so two neighbouring pixels can no longer be given wildly different weights
## and shear apart.
##
## Flesh beyond every bone's reach is carried by the nearest bone alone rather
## than left behind, so a drawing can never tear away from its own skeleton.
## `bone_island` may be empty, in which case every bone may move everything —
## which is what happens when nothing knows how the drawing is divided up.
## When it is given, a bone only moves flesh on its own island, so a skeleton
## drawn on one figure cannot take hold of the figure beside it however close
## the two are on the page. A bone that sits on no ink at all is given island
## nought and is left free to move anything, because a bone in empty space has
## no drawing of its own to be confined to.
static func bone_rule(rest_a: PackedVector2Array, rest_b: PackedVector2Array,
		now_a: PackedVector2Array, now_b: PackedVector2Array,
		bone_island: PackedInt32Array = PackedInt32Array()) -> Callable:
	var n: int = mini(mini(rest_a.size(), rest_b.size()),
		mini(now_a.size(), now_b.size()))
	var mine: PackedInt32Array = bone_island
	if mine.size() != n:
		mine = PackedInt32Array()
		mine.resize(n)

	# Worked out once for the whole skin rather than once per point. This runs
	# for eleven hundred points every time a pose changes, and the turn of a
	# bone is the same for all of them.
	var span: PackedVector2Array = PackedVector2Array()
	var moved_span: PackedVector2Array = PackedVector2Array()
	var length_sq: PackedFloat32Array = PackedFloat32Array()
	var reach_sq: PackedFloat32Array = PackedFloat32Array()
	var turn_cos: PackedFloat32Array = PackedFloat32Array()
	var turn_sin: PackedFloat32Array = PackedFloat32Array()
	span.resize(n)
	moved_span.resize(n)
	length_sq.resize(n)
	reach_sq.resize(n)
	turn_cos.resize(n)
	turn_sin.resize(n)
	for i in n:
		var s: Vector2 = rest_b[i] - rest_a[i]
		var m: Vector2 = now_b[i] - now_a[i]
		span[i] = s
		moved_span[i] = m
		length_sq[i] = s.length_squared()
		# Twice the bone's own length and a little, so a short bone still
		# holds the flesh immediately around it.
		var reach: float = sqrt(maxf(length_sq[i], 1.0)) * 0.42 + 8.0
		reach_sq[i] = reach * reach
		var turn: float = 0.0
		if length_sq[i] > 0.000001 and m.length_squared() > 0.000001:
			turn = m.angle() - s.angle()
		turn_cos[i] = cos(turn)
		turn_sin[i] = sin(turn)

	return func(p: Vector2, on_island: int = 0) -> Vector2:
		if n == 0:
			return p
		var anchor_rest: Vector2 = Vector2.ZERO
		var anchor_now: Vector2 = Vector2.ZERO
		var facing: Vector2 = Vector2.ZERO
		var total: float = 0.0
		# The nearest bone, kept in case nothing is in reach and in case every
		# turn cancels out.
		var closest: int = -1
		var closest_d: float = 1e30
		var closest_t: float = 0.0

		for i in n:
			# A bone belonging to another drawing has nothing to say about
			# this point, however near it happens to be.
			if mine[i] != 0 and on_island != 0 and mine[i] != on_island:
				continue
			var s: Vector2 = span[i]
			var t: float = 0.0
			if length_sq[i] > 0.000001:
				t = clampf((p - rest_a[i]).dot(s) / length_sq[i], 0.0, 1.0)
			var near_rest: Vector2 = rest_a[i] + s * t
			var d_sq: float = p.distance_squared_to(near_rest)
			if d_sq < closest_d:
				closest_d = d_sq
				closest = i
				closest_t = t
			if d_sq >= reach_sq[i]:
				continue
			# Smooth to zero at the edge of the reach, and finite on the bone
			# itself — a kernel that goes to infinity where the flesh meets
			# the bone hands neighbouring pixels wildly different weights and
			# shears them apart.
			var fall: float = 1.0 - d_sq / reach_sq[i]
			var w: float = fall * fall / (d_sq + 1.0)
			anchor_rest += near_rest * w
			anchor_now += (now_a[i] + moved_span[i] * t) * w
			facing += Vector2(turn_cos[i], turn_sin[i]) * w
			total += w

		if total <= 0.0:
			# Out of every bone's reach — or on a drawing none of them
			# belongs to, in which case `closest` was never set and the point
			# is left exactly where it is. Flesh with no skeleton of its own
			# must not be moved by somebody else's.
			if closest < 0:
				return p
			# Carried rigidly by the nearest bone, so no part of a drawing is
			# ever left behind by its own skeleton.
			var lone_rest: Vector2 = rest_a[closest] + span[closest] * closest_t
			var lone_now: Vector2 = now_a[closest] \
				+ moved_span[closest] * closest_t
			var off: Vector2 = p - lone_rest
			return lone_now + Vector2(
				off.x * turn_cos[closest] - off.y * turn_sin[closest],
				off.x * turn_sin[closest] + off.y * turn_cos[closest])

		anchor_rest /= total
		anchor_now /= total
		# Two bones turned exactly opposite ways in equal measure sum to
		# nothing, and the angle of nothing is meaningless. The nearest bone
		# decides it, which is the only answer with any claim to being right.
		var cs: float = turn_cos[closest] if closest >= 0 else 1.0
		var sn: float = turn_sin[closest] if closest >= 0 else 0.0
		if facing.length_squared() > 0.000001:
			facing = facing.normalized()
			cs = facing.x
			sn = facing.y
		var offset: Vector2 = p - anchor_rest
		# One rotation, applied once, to one offset. This is the line that
		# makes the flesh keep its distance from the joint: a rotation cannot
		# change a length.
		return anchor_now + Vector2(offset.x * cs - offset.y * sn,
			offset.x * sn + offset.y * cs)
