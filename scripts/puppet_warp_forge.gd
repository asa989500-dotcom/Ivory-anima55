class_name PuppetWarpForge
extends RefCounted
## The warp's mesh and its deformation, when the compiled engines are here.
##
## Two separate replacements, and it is worth being clear about which fault
## each of them answers, because they were being blamed on each other.
##
## ## The mesh: `IvoryMeshForge`
##
## The old mesh is an axis-aligned grid over the artwork's bounding box, with
## cells dropped where an ink map says there is nothing. That gives a boundary
## made of horizontal and vertical steps one cell tall — pull an arm and its
## edge moves in blocks — and it loses a stroke a pixel wide, because the ink
## map averages and a single opaque pixel averaged over a cell of a hundred is
## an alpha below any floor.
##
## The forge keeps the same quad topology, so everything downstream of it here
## still works, and changes the two things that mattered: occupancy is decided
## by the **maximum** alpha in a cell rather than the mean, and every vertex on
## the rim is walked on to the drawing's real outline.
##
## ## The deformation: `IvoryArapSolver`
##
## The old solve places every vertex by rigid moving-least-squares from the
## pins and then runs a few rounds of ARAP to repair the result. That is the
## "it drags" report, and the reason is in the first half: MLS is scattered-
## data interpolation. It knows about pins and distances and nothing about the
## drawing being made of material, so a pin pulled sideways translates its
## whole neighbourhood sideways. The ARAP rounds afterwards are then working
## against the field that has just been imposed on them.
##
## Solving the ARAP energy directly, from rest, with the pins as **hard**
## constraints, is a different thing: every edge would like to keep its rest
## length turned by however much its neighbourhood turned, so a pull stretches
## the material along its length instead of sliding it. And because a pinned
## vertex is removed from the system rather than weighted heavily, it is
## exactly where it was put however many other pins are fighting it.
##
## ## Both are optional
##
## Neither is required. `PuppetWarpBuild` and `PuppetWarp.solve` still hold the
## GDScript that runs when the extension is not built, and it goes on
## behaving as it always did.

## Lays the mesh with the forge. Returns false when the engine is not here, in
## which case the caller falls back to its own grid.
static func build_mesh(host: PuppetWarp, density: int) -> bool:
	var forge: Object = Native.meshforge()
	if forge == null or host.source == null:
		return false

	var span: Vector2 = Vector2(float(host.rect.size.x), float(host.rect.size.y))
	if span.x < 2.0 or span.y < 2.0:
		return false
	# The density control says how many cells across the longest side, so the
	# cell size is that side divided by it — the same number the grid used, so
	# the slider goes on meaning what it meant.
	var want: int = clampi(density, host.MIN_CELLS, host.MAX_CELLS)
	var cell: float = maxf(span.x, span.y) / float(maxi(want, 2))

	var rgba: PackedByteArray = host.source.get_data()
	if host.source.get_format() != Image.FORMAT_RGBA8:
		var copy: Image = host.source.duplicate()
		copy.convert(Image.FORMAT_RGBA8)
		rgba = copy.get_data()
	var built: Dictionary = forge.build(rgba, host.source.get_width(),
		host.source.get_height(), cell, host.INK_FLOOR)
	if not bool(built.get("ok", false)):
		return false

	var verts: PackedVector2Array = built["vertices"]
	var tris: PackedInt32Array = built["triangles"]
	if verts.size() < 3 or tris.size() < 3:
		return false

	host.cells = want
	# The forge works in the source image's own pixels; the warp works in page
	# coordinates with the artwork's corner as the origin.
	var origin: Vector2 = Vector2(host.rect.position)
	host._rest_v = PackedVector2Array()
	host._uv = PackedVector2Array()
	for i in verts.size():
		host._rest_v.append(origin + verts[i])
		host._uv.append(Vector2(verts[i].x / span.x, verts[i].y / span.y))
	host._tris = tris
	host._rim = built["boundary"]

	# There is no grid behind this mesh, so the slot bookkeeping that the grid
	# path uses to find neighbours has nothing to say. Marked with a column
	# count of nought, which `PuppetWarpBuild.link` reads as "the neighbours
	# are already worked out, leave them alone".
	host._cols = 0
	host._rows = 0
	host._cell = Vector2(cell, cell)
	host._slot = PackedInt32Array()
	host._home = PackedInt32Array()

	_link_from_edges(host, built["edges"])
	host._now_v = host._rest_v.duplicate()
	host._last_good_v = host._rest_v.duplicate()
	host._build_wire()
	host._measure_rest()
	host._order_dirty = true
	host._reach_dirty = true
	host._fast_pins_dirty = true
	# Keep the C++ IvoryWarp instance synchronized with the newly forged mesh.
	# This is intentionally once per rebuild, never during a drag.
	host._hand_mesh_over()
	return true

## Who each vertex is joined to, taken from the mesh's own edges.
##
## The grid path reads this off the lattice: four orthogonal neighbours, or
## fewer at an edge, and fewer than four is what marks a rim vertex. The forge
## has no lattice, so the edges are read instead and the four nearest kept.
##
## Four is not an approximation of convenience — it is what `_near` is sized
## for, and what the distance walk expects. Keeping the nearest four preserves
## the property the walk depends on: a gap in the drawing is a gap in the
## measurement, because there is no edge across it to walk along.
static func _link_from_edges(host: PuppetWarp, edges: PackedInt32Array) -> void:
	var count: int = host._rest_v.size()
	host._near = PackedInt32Array()
	host._near.resize(count * 4)
	host._near.fill(-1)

	# Gathered per vertex first, because an edge list says nothing about which
	# end is which and every edge has to be seen from both.
	var lists: Array = []
	lists.resize(count)
	for i in count:
		lists[i] = []
	var pairs: int = floori(float(edges.size()) / 2.0)
	for e in pairs:
		var a: int = edges[e * 2]
		var b: int = edges[e * 2 + 1]
		if a < 0 or b < 0 or a >= count or b >= count:
			continue
		(lists[a] as Array).append(b)
		(lists[b] as Array).append(a)

	for i in count:
		var mine: Array = lists[i]
		# Nearest first. On a quad mesh the four orthogonal neighbours are
		# always nearer than the diagonals, so this picks exactly the four the
		# grid path would have picked — without needing the grid.
		var here: Vector2 = host._rest_v[i]
		mine.sort_custom(func(x: int, y: int) -> bool:
			return here.distance_squared_to(host._rest_v[x]) \
				< here.distance_squared_to(host._rest_v[y]))
		var kept: int = mini(mine.size(), 4)
		for k in kept:
			host._near[i * 4 + k] = int(mine[k])

# ---------------------------------------------------------------- solving

## The native solver is owned by the PuppetWarp instance.
##
## Stage 162 kept a second global IvoryArapSolver here. That meant the active
## path could silently use a solver belonging to another warp mesh, and it also
## bypassed IvoryWarp's affine fit, bounds and turn handling. The project already
## has the complete IvoryWarp engine, so use that engine directly and keep one
## instance per PuppetWarp host.
static func solve(host: PuppetWarp, settle: bool) -> bool:
	if host._rest_v.is_empty() or host._tris.is_empty():
		return false

	# MeshForge owns the topology; hand it to IvoryWarp once after every rebuild.
	if host._fast == null or not host._fast_mesh:
		host._hand_mesh_over()
	if host._fast == null or not host._fast_mesh:
		return false

	var count: int = host.pins.size()
	if count == 0:
		host._now_v = host._rest_v.duplicate()
		host._last_good_v = host._rest_v.duplicate()
		host._fast_pins_dirty = true
		return true

	var rest_pins := PackedVector2Array()
	var now_pins := PackedVector2Array()
	var vertex := PackedInt32Array()
	var turn := PackedFloat32Array()
	rest_pins.resize(count)
	now_pins.resize(count)
	vertex.resize(count)
	turn.resize(count)
	for i in count:
		var pin: PuppetWarp.Pin = host.pins[i] as PuppetWarp.Pin
		rest_pins[i] = pin.rest
		now_pins[i] = pin.now
		vertex[i] = pin.vertex
		turn[i] = pin.turn

	if host._fast_pins_dirty:
		host._fast.call("set_pins", rest_pins, now_pins, vertex, turn)
		host._fast_pins_dirty = false
	else:
		host._fast.call("move_pins", now_pins, turn)

	# Keep the native parameters identical to the editor's current controls.
	# Bounds are a hard safety constraint; they are deliberately enforced by the
	# solver rather than by cropping the rendered texture afterwards.
	host._fast.call("set_mode", host.fit_mode)
	host._fast.call("set_params", host.stiffness, host.softness,
		host._rigid_strength(), host.smoothing, 1.62)
	host._fast.call("set_bounds", Vector2(host.rect.position),
		Vector2(host.rect.position + host.rect.size))

	var got: PackedVector2Array = host._fast.call("solve", settle)
	if got.size() != host._rest_v.size():
		return false
	host._now_v = got
	return true

## The solver now belongs to the host, so there is no global state to forget.
static func forget() -> void:
	pass
