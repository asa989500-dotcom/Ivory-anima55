class_name PuppetWarpBuild
extends RefCounted
## Putting a puppet-warp mesh together: the grid, the wire, the links between
## a vertex and its neighbours, and the rest measurements everything else is
## judged against.
##
## Lifted out of `puppet_warp.gd` at stage 145 to bring that file back under
## the size the project allows. This is all cold code — it runs once when a
## warp is opened and never again while a pin is being dragged — which is why
## it is the part that moved rather than the solve.
##
## `PuppetWarp` keeps a one-line delegate for each, so nothing that called
## them changed.

## Takes a picture of a layer and builds a mesh over its ink. Returns false
## when there is nothing on the layer worth bending.
static func begin(host: PuppetWarp, image: Image, region: Rect2i, density: int = 34) -> bool:
	if image == null or region.size.x < 4 or region.size.y < 4:
		return false
	host.source = image
	host.rect = region
	host._tex = ImageTexture.create_from_image(image)
	host.pins.clear()
	host.selected = -1
	host._build_grid(density)
	if host._rest_v.is_empty():
		return false

	if host._mesh_node == null:
		host._mesh_node = MeshInstance2D.new()
		host._mesh_node.name = "WarpPreview"
		# The canvas keeps premultiplied pixels, and the preview is those
		# same pixels — so it has to blend the way every layer blends or the
		# drawing would darken the moment warping started.
		host._mesh_node.material = PaintSurface.premultiplied_material()
		host._mesh_node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		# Underneath this node's own drawing. A child paints after its
		# parent, so the artwork was going down on top of the grid and the
		# pins and hiding both — the grid was being drawn all along, just
		# never seen.
		host._mesh_node.z_index = -1
		host.add_child(host._mesh_node)
	host._mesh_node.texture = host._tex
	host._mesh_node.visible = true
	host.solve()
	return true

## The mesh is laid over the ink and nowhere else.
##
## Cells are kept when the drawing puts something in them, plus one ring
## outwards so a stroke always has mesh on both sides of its edge. Empty
## cells are dropped: they cost the same to solve as drawn ones and move
## nothing, and — worse — they bridge gaps that the drawing does not, which
## is what let a pull cross from one arm of a U to the other.
static func build_grid(host: PuppetWarp, density: int) -> void:
	# The forge first, when the compiled engine is here. Same quad topology,
	# so everything below and after this still works — but occupancy decided
	# by the strongest pixel in a cell rather than the average, and every rim
	# vertex walked on to the drawing's real outline. See `PuppetWarpForge`.
	PuppetWarpForge.forget()
	if PuppetWarpForge.build_mesh(host, density):
		return
	var want: int = clampi(density, host.MIN_CELLS, host.MAX_CELLS)
	host.cells = want
	var span: Vector2 = Vector2(float(host.rect.size.x), float(host.rect.size.y))
	var longest: float = maxf(span.x, span.y)
	host._cols = clampi(int(round(want * span.x / longest)), 2, host.MAX_CELLS) + 1
	host._rows = clampi(int(round(want * span.y / longest)), 2, host.MAX_CELLS) + 1
	host._cell = Vector2(span.x / float(host._cols - 1), span.y / float(host._rows - 1))

	var cells_x: int = host._cols - 1
	var cells_y: int = host._rows - 1
	var inked: PackedByteArray = host._ink_map(cells_x, cells_y)

	# --- vertices, for kept cells only ---
	host._slot = PackedInt32Array()
	host._slot.resize(host._cols * host._rows)
	host._slot.fill(-1)
	host._rest_v = PackedVector2Array()
	host._uv = PackedVector2Array()
	host._home = PackedInt32Array()

	var origin: Vector2 = Vector2(host.rect.position)
	var claim: Callable = func(x: int, y: int) -> int:
		var at: int = y * host._cols + x
		if host._slot[at] >= 0:
			return host._slot[at]
		var fx: float = float(x) / float(host._cols - 1)
		var fy: float = float(y) / float(host._rows - 1)
		host._rest_v.append(origin + Vector2(fx * span.x, fy * span.y))
		host._uv.append(Vector2(fx, fy))
		host._home.append(at)
		host._slot[at] = host._rest_v.size() - 1
		return host._slot[at]

	host._tris = PackedInt32Array()
	for cy in cells_y:
		for cx in cells_x:
			if inked[cy * cells_x + cx] == 0:
				continue
			var a: int = claim.call(cx, cy)
			var b: int = claim.call(cx + 1, cy)
			var c: int = claim.call(cx, cy + 1)
			var d: int = claim.call(cx + 1, cy + 1)
			# The diagonal alternates. A grid whose triangles all lean the
			# same way bends more easily along that diagonal than across it,
			# and a drawing pulled at forty-five degrees shows the bias as a
			# staircase. Alternating cancels it out.
			if (cx + cy) % 2 == 0:
				host._tris.append_array([a, b, c])
				host._tris.append_array([b, d, c])
			else:
				host._tris.append_array([a, b, d])
				host._tris.append_array([a, d, c])

	host._now_v = host._rest_v.duplicate()
	host._last_good_v = host._rest_v.duplicate()
	host._build_wire()
	host._link()
	host._measure_rest()
	host._order_dirty = true
	host._reach_dirty = true
	host._fast_pins_dirty = true

## The unique edges of the triangle list.
##
## A dictionary keyed on the pair, built once. The key packs the two indices
## into one integer with the lower first, so an edge listed as (7, 12) by one
## triangle and (12, 7) by its neighbour lands on the same key and is kept
## once. Boundary edges belong to one triangle only and are kept the same way,
## which is what a parity rule on the winding would have quietly dropped.
static func build_wire(host: PuppetWarp) -> void:
	host._wire = PackedInt32Array()
	if host._tris.is_empty():
		return
	var seen: Dictionary = {}
	var stride: int = maxi(host._rest_v.size(), 1)
	var count: int = floori(float(host._tris.size()) / 3.0)
	for t in count:
		var corner: Array = [host._tris[t * 3], host._tris[t * 3 + 1], host._tris[t * 3 + 2]]
		for k in 3:
			var u: int = int(corner[k])
			var v: int = int(corner[(k + 1) % 3])
			var lo: int = mini(u, v)
			var hi: int = maxi(u, v)
			var key: int = lo * stride + hi
			if seen.has(key):
				continue
			seen[key] = true
			host._wire.append(lo)
			host._wire.append(hi)

## Who each vertex is joined to. This is the map every distance is walked
## along, and the reason a gap in the drawing is a gap in the measurement.
static func link(host: PuppetWarp) -> void:
	# A column count of nought means the mesh did not come from a lattice, so
	# there are no slots to read neighbours out of — `PuppetWarpForge` has
	# already worked them out from the mesh's own edges. See its
	# `_link_from_edges`.
	if host._cols <= 0:
		return
	var count: int = host._rest_v.size()
	host._near = PackedInt32Array()
	host._near.resize(count * 4)
	host._near.fill(-1)
	host._rim = PackedByteArray()
	host._rim.resize(count)

	var steps: Array = [Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 1), Vector2i(0, -1)]
	for i in count:
		var slot: int = host._home[i]
		var gx: int = slot % host._cols
		# Deliberately whole: a slot number is a row times the width plus a
		# column, so the row *is* the discarded-remainder division. Marked so
		# Godot stops warning about a decimal part that must not exist here.
		@warning_ignore("integer_division")
		var gy: int = slot / host._cols
		var found: int = 0
		for k in 4:
			var step: Vector2i = steps[k]
			var nx: int = gx + step.x
			var ny: int = gy + step.y
			if nx < 0 or ny < 0 or nx >= host._cols or ny >= host._rows:
				continue
			var other: int = host._slot[ny * host._cols + nx]
			if other < 0:
				continue
			host._near[i * 4 + k] = other
			found += 1
		host._rim[i] = 1 if found < 4 else 0

## The area of every triangle before anything was pulled.
static func measure_rest(host: PuppetWarp) -> void:
	var count: int = floori(float(host._tris.size()) / 3.0)
	host._rest_area = PackedFloat32Array()
	host._rest_area.resize(count)
	for t in count:
		host._rest_area[t] = PuppetWarp._area(host._rest_v[host._tris[t * 3]], host._rest_v[host._tris[t * 3 + 1]],
			host._rest_v[host._tris[t * 3 + 2]])
	host._fix = PackedVector2Array()
	host._fix.resize(host._rest_v.size())
	host._hold = PackedFloat32Array()
	host._hold.resize(host._rest_v.size())
	host._hand_mesh_over()

## Gives the native solver the mesh, if there is one to give it to.
##
## Once per rebuild and never per frame. The mesh is the large thing here —
## several thousand vertices and four neighbours each — and copying it across
## on every solve would spend more than the solve saves.
static func hand_mesh_over(host: PuppetWarp) -> void:
	if host._fast == null:
		host._fast = Native.warp()
	if host._fast == null:
		return
	# Validate the native boundary once, immediately after the expensive mesh
	# build and before the solver is allowed to consume it. A malformed mesh is
	# rejected here instead of becoming a renderer crash or a NaN cascade.
	var diag: Object = Native.diagnostics()
	if diag != null:
		var report: Dictionary = diag.call("check_mesh", host._rest_v, host._near, host._rim, host._tris, 0.000001)
		if not bool(report.get("ok", false)):
			host._fast_mesh = false
			host._fast = null
			return
	host._fast.call("set_mesh", host._rest_v, host._near, host._rim, host._cell.length(), host._tris)
	host._fast.call("set_bounds", Vector2(host.rect.position), Vector2(host.rect.position + host.rect.size))
	host._fast_mesh = true
	host._fast_pins_dirty = true

static func set_density(host: PuppetWarp, density: int) -> void:
	if host.source == null:
		return
	var pose: Array = []
	for p in host.pins:
		pose.append([(p as PuppetWarp.Pin).rest, (p as PuppetWarp.Pin).now, (p as PuppetWarp.Pin).anchored,
			(p as PuppetWarp.Pin).depth])
	host._build_grid(density)
	# The pins are put back on the new mesh rather than thrown away: changing
	# how finely something is measured should not undo the pose.
	host.pins.clear()
	for row in pose:
		var p: PuppetWarp.Pin = PuppetWarp.Pin.new()
		p.rest = row[0]
		p.now = row[1]
		p.anchored = row[2]
		p.depth = row[3]
		p.vertex = host._vertex_near(p.rest)
		if p.vertex >= 0:
			host.pins.append(p)
	host.selected = mini(host.selected, host.pins.size() - 1)
	host.solve()
	host.changed.emit()

## Re-solving after a setting changes. The pose is untouched — only the way
## it is worked out.
static func restyle(host: PuppetWarp) -> void:
	host._order_dirty = true
	host._reach_dirty = true
	host._fast_pins_dirty = true
	host.solve()
