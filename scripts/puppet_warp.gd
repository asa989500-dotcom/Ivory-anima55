class_name PuppetWarp
extends Node2D
## Bending a drawing by pinning it and pulling.

## You put pins on the artwork. The pins you hold still hold the drawing
## still; the one you drag takes the drawing with it, and everything between
## bends the way paper bends rather than sliding apart.
##
## ## The deformation
##
## Rigid Moving Least Squares (Schaefer, McPhail and Warren, 2006). For every
## point on the mesh it asks: *what single rotation and translation best
## explains where all the pins moved, as seen from here?* Near a pin that pin
## dominates and the drawing follows it exactly; between two the answer
## blends, and because it is a rotation rather than a slide, the drawing turns
## instead of smearing.
##
## Three properties follow, and they are the whole difference from a falloff
## scheme that adds up weighted movements:
##
##   * **Absolute, not incremental.** Every solve is computed from the rest
##     pose, so dragging a pin back returns the drawing exactly.
##   * **It interpolates.** A point under a pin lands on that pin.
##   * **Rigid.** Only rotation and position are fitted, never scale, so ink
##     keeps its thickness and a face does not smear while an arm is moved.
##
## ## The mesh follows the ink, and distance runs through it
##
## A plain rectangle over the bounding box measuring distance in a straight
## line, is wrong for any shape that is not roughly a blob. A **U** shows why:
## its two arms are a few pixels apart across the gap and a long way apart
## through the drawing, so a pin on one arm was treated as being beside the
## other and pulling it dragged ink that nothing connects it to.
##
## So the mesh is built only where there is ink, and distance is measured by
## walking the mesh rather than crossing the gap. Building on the ink also
## costs less — the empty half of a U's box carried as many triangles as the
## drawing and they were solved every frame to move nothing — and that saving
## is spent on a finer mesh, which is what makes the bend smooth.

signal changed()

const MIN_CELLS: int = 16
const MAX_CELLS: int = 112
const MAX_BAKE: int = 4096
## Below this many pins there is no rotation to find, so the drawing is
## simply carried.
const RIGID_FROM: int = 2
## Alpha under this is not ink. Low, because an antialiased edge fades a long
## way down and the mesh should reach past the last visible pixel.
const INK_FLOOR: float = 0.004
## Unreachable — a piece of drawing no path connects to this pin.
const FAR: float = 1.0e20
## How much more the outward smoothing pass gives back than the inward one
## took. See `_relax_smooth`.
const INFLATE: float = 1.03
## What a piece of drawing no path reaches is treated as costing, on top of
## the straight-line distance to it. See `_rebuild_reach`.
const BRIDGE: float = 240.0

## --- what a pin is allowed to do to the drawing ---
##
## ## Why the old answer was wrong for a two-dimensional drawing
##
## The fit was rigid: rotation and translation, nothing else, so every
## distance in the drawing was preserved exactly. That is the right choice
## when a puppet warp is standing in for a jointed figure, and it is the wrong
## one for almost everything a person actually reaches for this tool to do.
##
## Draw a straight line. Put a pin at each end and pull one towards the other.
## A rigid fit is not *allowed* to shorten the line — the two ends are closer
## together and every distance along it must stay what it was — so the
## material has to go somewhere, and where it goes is sideways: the line bows
## out into an arc. The drawing was dragged rather than shortened, and it was
## dragged because it was forbidden to shrink.
##
## The three modes are Schaefer, McPhail and Warren (2006), section by
## section. Everything else — the weights, the distances walked through the
## mesh, the pins — is identical between them.
enum Fit {
	## Rotation and translation. Proportions exact, and material slides out of
	## the way rather than compressing. For posing something jointed.
	RIGID,
	## One uniform scale as well. Pins spread apart and the drawing grows with
	## them; brought together and it shrinks, keeping its shape.
	SIMILARITY,
	## The full linear fit: a scale on each axis independently, and shear.
	## Pull a pin towards another and the material *between them compresses*
	## while what is square to that line is left alone. This is what
	## stretching and squashing a flat drawing means, and it is the default.
	AFFINE,
}

class Pin extends RefCounted:
	## Where the pin was placed and where it is now, in page coordinates. The
	## rest never changes while the pin exists — every solve measures from it.
	var rest: Vector2 = Vector2.ZERO
	var now: Vector2 = Vector2.ZERO
	## Pinned down: it holds the drawing but cannot be dragged, so a hand can
	## never move an anchor by accident while reaching past it.
	var anchored: bool = false
	## How far this pin has been turned, in radians.
	##
	## Position alone cannot say everything a hand means. Dragging a pin on a
	## forearm lets the fit decide which way the hand ends up pointing, and it
	## decides that from where the *other* pins are. A wrist turned over, a
	## head tilted, a foot pointed: each is a rotation about one place with no
	## movement at all, and there was no way to ask for one.
	var turn: float = 0.0
	## Which side of a fold this pin's part of the drawing is on. Higher is
	## nearer the viewer.
	var depth: int = 0
	## The mesh vertex this pin sits on; distances are measured outwards from
	## here. Named `vertex` rather than `seed` because `seed` is a built-in.
	var vertex: int = -1

# --- what is being bent ---
var rect: Rect2i = Rect2i()
var source: Image = null
var pins: Array = []

# --- how it is bent ---
## How sharply a pin's neighbourhood belongs to it. Higher makes each pin's
## grip more local; lower lets the whole drawing answer to every pin.
var stiffness: float = 1.0
## The radius, in page units, over which a pin's pull is spread rather than
## concentrated on one point.
##
## Straight inverse-square weighting divides by the distance to the pin, which
## at the pin itself is nothing — the weight runs away to infinity, leaving a
## tiny rigid disc at each pin with the drawing bending around it, and on a
## stroke that reads as a kink exactly where the finger is. A radius under the
## distance keeps the weight finite and turns the kink into a curve:
##
##     w = 1 / (d² + softness²) ^ stiffness
##
## Well past `softness` this is the inverse-square falloff it always was.
var softness: float = 7.0
## How hard the mesh is relaxed towards a smooth surface after solving.
##
## A polish, and nothing structural depends on it any more. Left at zero the
## drawing keeps every corner it was drawn with, which is usually what is
## wanted; turned up it softens the whole surface.
var smoothing: float = 0.4
## How strongly the drawing insists on keeping its own shape.
##
## This is the weight on the as-rigid-as-possible solve — see `_arap_fit`. At
## nought the pose is plain MLS and the ground between two pins pulling apart
## collapses; at one the drawing holds its local shape everywhere it is not
## being held by a pin, which is what stops an arm thinning as it bends.
var area_keep: float = 0.55

## Which fit the pins are allowed. See `Fit`, which explains at length why
## this defaults to the one that squashes.
var fit_mode: int = Fit.AFFINE

## --- how hard the mesh resists being deformed ---
##
## As-rigid-as-possible is, by construction, a force *against* scaling: it
## fits a rotation to every neighbourhood and pulls the mesh towards it, and a
## neighbourhood that has been compressed is a neighbourhood no rotation
## explains. So at full strength it undoes exactly the thing the affine fit is
## for, and the drawing springs back out of every squash.
##
## It cannot simply be turned off — it is what keeps the mesh from folding
## through itself — so in the stretching modes it is run gently instead. Firm
## enough to stop a tangle, weak enough not to fight the squash.
func _rigid_strength() -> float:
	if fit_mode == Fit.RIGID:
		return area_keep
	return area_keep * 0.35

var show_mesh: bool = true
var zoom: float = 1.0
## The pin the hand last touched — what the panel's controls act on.
var selected: int = -1

## How fine the mesh currently is, in cells across its longest side.
##
## Public because the panel's Grid slider used to open at a hardcoded 34
## whatever the mesh was, so the first touch of it jumped the drawing to a
## density nobody asked for.
var cells: int = 34

var _tex: ImageTexture = null
var _mesh_node: MeshInstance2D = null

# --- the mesh ---
@warning_ignore("unused_private_class_variable")
var _cols: int = 0
@warning_ignore("unused_private_class_variable")
var _rows: int = 0
var _cell: Vector2 = Vector2.ONE
## Grid slot -> vertex index, or -1 where the drawing has no ink.
@warning_ignore("unused_private_class_variable")
var _slot: PackedInt32Array = PackedInt32Array()
## Vertex index -> grid slot, for neighbour lookups.
@warning_ignore("unused_private_class_variable")
var _home: PackedInt32Array = PackedInt32Array()
var _rest_v: PackedVector2Array = PackedVector2Array()
var _now_v: PackedVector2Array = PackedVector2Array()
## The last pose `_prevent_foldover` verified sound. Restored, not the rest
## pose, when even a step's starting point cannot be trusted — see
## `PuppetWarpFoldover`. Falling all the way back to rest throws away every
## pin's work for a fault that touched one triangle.
var _last_good_v: PackedVector2Array = PackedVector2Array()
var _uv: PackedVector2Array = PackedVector2Array()
## The triangles as the grid built them, before depth has any say. `_index`
## is this same list put in drawing order.
var _tris: PackedInt32Array = PackedInt32Array()
## Every edge of the mesh, once, as pairs of vertex indices.
##
## ## Why it is built rather than derived while drawing
##
## Every interior edge belongs to two triangles, so walking the triangle list
## and drawing all three sides draws half the mesh twice — visibly heavier
## lines in a pattern that has nothing to do with the mesh. Deduplicating
## while drawing needs a set of several thousand keys built every frame, for
## an answer that cannot change: the mesh does not move while it is being
## dragged, only its vertices do.
##
## So it is built once, when the mesh is, and read straight through.
@warning_ignore("unused_private_class_variable")
var _wire: PackedInt32Array = PackedInt32Array()
var _index: PackedInt32Array = PackedInt32Array()
## Four neighbours per vertex, -1 where the mesh ends. Flat, four per vertex.
var _near: PackedInt32Array = PackedInt32Array()
## True where a vertex sits on the outline of the mesh.
@warning_ignore("unused_private_class_variable")
var _rim: PackedByteArray = PackedByteArray()

# --- the native solver, when there is one ---
#
# ## Both halves stay, and this is why
#
# Everything below in this file is the solve, in GDScript, and it is correct.
# `native/ivory` is the same solve in C++, and it is the one that runs when the
# library has been built for the platform in hand. Neither is a draft of the
# other: the GDScript is what a checkout runs before anybody has run `scons`,
# and what every platform nobody has got round to yet runs, and it has to go on
# working for that to be true.
#
# What C++ buys is not a different answer. It is the inner loops — one MLS fit
# per vertex over every pin, then several ARAP sweeps over every vertex — being
# arithmetic instead of Variants, which is the difference between a mesh of
# eighty-eight cells following a finger and one that has to be dropped to
# thirty-four to keep up. It also gets three things the GDScript cannot
# affordably have: exact walked distances by Dijkstra rather than converged
# sweeps, over-relaxed ARAP sweeps, and the MLS sums accumulated in double.
#
# The bridge is `scripts/native.gd`, and it is the only place that asks whether
# the extension exists.
var _fast: Object = null
## True once the mesh has been handed across. Cleared whenever the mesh is
## rebuilt, because the native side holds its own copy of it.
var _fast_mesh: bool = false

# --- solving ---
var _weights: PackedFloat32Array = PackedFloat32Array()
## Distance from each pin to every vertex, measured through the mesh. One
## array per pin. Costly to work out and completely unaffected by dragging,
## so it is built when the pins change and then simply read.
var _reach: Array = []
@warning_ignore("unused_private_class_variable")
var _rest_area: PackedFloat32Array = PackedFloat32Array()
## Per vertex, how completely it belongs to a pin. Near 1 the vertex is doing
## what a pin told it to and must be left alone by the relaxation passes.
var _hold: PackedFloat32Array = PackedFloat32Array()
@warning_ignore("unused_private_class_variable")
var _fix: PackedVector2Array = PackedVector2Array()
var _order_dirty: bool = true
var _reach_dirty: bool = true

# --- as-rigid-as-possible ---
#
# See `_arap_fit` and `_arap_sweep`. Two floats per vertex holding the best
# local rotation as a cosine and a sine rather than an angle, because every
# use of it is a rotation of a vector and not one of them wants the angle
# back — and `atan2` followed by `cos` and `sin` is three transcendentals per
# vertex per round for a number that was already in hand.
@warning_ignore("unused_private_class_variable")
var _rot_c: PackedFloat32Array = PackedFloat32Array()
@warning_ignore("unused_private_class_variable")
var _rot_s: PackedFloat32Array = PackedFloat32Array()
## True where a pin is holding this vertex outright, so the sweeps skip it.
var _pinned: PackedByteArray = PackedByteArray()
## Whether any pin has been turned at all.
##
## Kept because `_warp` runs once per vertex per solve — tens of thousands of
## times for every frame of a drag — and the turn arithmetic is pure waste on
## the overwhelmingly common pose where nobody has touched a ring.
var _any_turn: bool = false

func _note_turns() -> void:
	_any_turn = false
	for one in pins:
		if absf((one as Pin).turn) > 0.0001:
			_any_turn = true
			return

func _ready() -> void:
	z_index = 40

# ------------------------------------------------------------------ set up

func begin(image: Image, region: Rect2i, density: int = 34) -> bool:
	return PuppetWarpBuild.begin(self, image, region, density)

func _build_grid(density: int) -> void:
	PuppetWarpBuild.build_grid(self, density)

func _build_wire() -> void:
	PuppetWarpBuild.build_wire(self)

## Which cells the drawing actually reaches — see `WarpMesh.ink_map`, which
## is where the tearing was: the old map was made with one bilinear shrink
## from a thousand pixels to thirty-four, at which ratio bilinear never looks
## at most of the image and thin strokes fell between its samples. A cell
## wrongly called empty gets no triangles, and a piece of drawing with no
## triangles under it is not drawn at all.
func _ink_map(cells_x: int, cells_y: int) -> PackedByteArray:
	return WarpMesh.ink_map(source, cells_x, cells_y, INK_FLOOR)

func _link() -> void:
	PuppetWarpBuild.link(self)

func _measure_rest() -> void:
	PuppetWarpBuild.measure_rest(self)

func _hand_mesh_over() -> void:
	PuppetWarpBuild.hand_mesh_over(self)

## Whether the pins have changed in a way the native side has not been told
## about. Moving a pin is cheap to send; adding or removing one throws away
## the walked distances, so the two are kept apart.
var _fast_pins_dirty: bool = true

## Signed, so a triangle that has been turned inside out reports a negative
## area and the constraint pushes it back the right way instead of settling
## happily into a fold.
static func _area(a: Vector2, b: Vector2, c: Vector2) -> float:
	return 0.5 * ((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y))

func set_density(density: int) -> void:
	PuppetWarpBuild.set_density(self, density)

func restyle() -> void:
	PuppetWarpBuild.restyle(self)

# -------------------------------------------------------------------- pins

func _vertex_near(at: Vector2) -> int:
	return PuppetWarpPins.vertex_near(self, at)

func can_pin(at: Vector2) -> bool:
	return PuppetWarpPins.can_pin(self, at)

func add_pin(at: Vector2) -> int:
	return PuppetWarpPins.add_pin(self, at)

func pin_at(at: Vector2, reach: float) -> int:
	return PuppetWarpPins.pin_at(self, at, reach)

func move_pin(index: int, to: Vector2) -> void:
	PuppetWarpPins.move_pin(self, index, to)

## The finger has lifted, so the shape is solved again properly — see `solve`.
func settle_pose() -> void:
	if _rest_v.is_empty() or pins.is_empty():
		return
	solve(true)
	changed.emit()

func ring_radius() -> float:
	return PuppetWarpPins.ring_radius(self)

func on_ring(at: Vector2) -> bool:
	return PuppetWarpPins.on_ring(self, at)

func turn_pin_towards(index: int, to: Vector2, grabbed_at: float) -> void:
	PuppetWarpPins.turn_pin_towards(self, index, to, grabbed_at)

## The angle from a pin to a place, for the caller to hold on to while a turn
## is in progress. Taking the difference from this is what stops the drawing
## jumping the moment the ring is touched.
func angle_from(index: int, to: Vector2) -> float:
	if index < 0 or index >= pins.size():
		return 0.0
	return (to - (pins[index] as Pin).now).angle()

func turn_of(index: int) -> float:
	if index < 0 or index >= pins.size():
		return 0.0
	return (pins[index] as Pin).turn

func set_turn(index: int, radians: float) -> void:
	if index < 0 or index >= pins.size():
		return
	(pins[index] as Pin).turn = radians
	_note_turns()
	solve()
	changed.emit()

func toggle_anchor(index: int) -> void:
	if index < 0 or index >= pins.size():
		return
	var p: Pin = pins[index] as Pin
	p.anchored = not p.anchored
	queue_redraw()
	changed.emit()

func is_anchored(index: int) -> bool:
	if index < 0 or index >= pins.size():
		return false
	return (pins[index] as Pin).anchored

## Moves a pin's part of the drawing in front of or behind the rest.
func set_depth(index: int, depth: int) -> void:
	if index < 0 or index >= pins.size():
		return
	(pins[index] as Pin).depth = clampi(depth, -9, 9)
	_order_dirty = true
	solve()
	changed.emit()

func depth_of(index: int) -> int:
	if index < 0 or index >= pins.size():
		return 0
	return (pins[index] as Pin).depth

func remove_pin(index: int) -> void:
	PuppetWarpPins.remove_pin(self, index)

## Puts every pin back where it was placed. The pins stay — what goes is the
## pose, which is the thing a hand wants to take back.
## One step back, and only one — a pose is explored by pulling and pulling
## back, and a hand mid-pose wants the last pull undone far more often than it
## wants a list of every pull it has made.
var _last_pose: Array = []

## A pose is where the pins are *and* which way they face.
##
## Remembering only the positions was right while a pin could only be moved.
## Now that one can be turned, a step back that put every pin where it was and
## left them all facing wherever the last turn had left them would undo half a
## gesture — which is worse than undoing none of it.
func remember_pose() -> void:
	_last_pose = []
	for p in pins:
		_last_pose.append([(p as Pin).now, (p as Pin).turn])

func has_step_back() -> bool:
	return _last_pose.size() == pins.size() and not _last_pose.is_empty()

func step_back() -> void:
	if not has_step_back():
		return
	var swap: Array = []
	for i in pins.size():
		var p: Pin = pins[i] as Pin
		swap.append([p.now, p.turn])
		var was: Array = _last_pose[i]
		p.now = was[0]
		p.turn = float(was[1])
	_last_pose = swap
	_note_turns()
	solve()
	changed.emit()

func reset_pose() -> void:
	remember_pose()
	for p in pins:
		(p as Pin).now = (p as Pin).rest
		(p as Pin).turn = 0.0
	_any_turn = false
	solve()
	changed.emit()

func clear_pins() -> void:
	pins.clear()
	selected = -1
	_any_turn = false
	_order_dirty = true
	_reach_dirty = true
	_fast_pins_dirty = true
	solve()
	changed.emit()

# ------------------------------------------------------------ measuring out

## How far every part of the drawing is from every pin, walking the mesh.
##
## Straight-line distance is what made a pull arrive from the wrong place:
## across the mouth of a U it is a few pixels from one arm to the other, so
## each arm was weighted as though it were sitting on top of the other. Walked
## through the mesh the same two points are the whole length of the bend
## apart, and the drawing behaves as the shape it is.
##
## Worked out by repeated relaxation: every vertex offers each neighbour a
## route through itself, and the passes repeat until no route improves. Sweeps
## alternate direction so a distance travelling against the raster order does
## not need one pass per step. It costs a great deal more than subtracting two
## points — and it is done when the pins change, never while one is being
## dragged, because where a pin was *placed* is what it measures from.
func _rebuild_reach() -> void:
	_reach_dirty = false
	_reach = []
	var count: int = _rest_v.size()
	for p in pins:
		var pin: Pin = p as Pin
		if pin.vertex < 0 or pin.vertex >= count:
			pin.vertex = _vertex_near(pin.rest)
		var far: PackedFloat32Array = PackedFloat32Array()
		far.resize(count)
		far.fill(FAR)
		if pin.vertex >= 0:
			far[pin.vertex] = 0.0
		_spread(far)
		# A piece of drawing no path reaches is carried rather than left
		# standing. See `WarpMesh.bridge_islands` — this was the other half
		# of the drawing coming apart.
		WarpMesh.bridge_islands(far, pin.rest, _rest_v, BRIDGE)
		_reach.append(far)

func _spread(far: PackedFloat32Array) -> void:
	WarpMesh.spread(far, _near, _rest_v)

## How much of each vertex belongs to a pin rather than to the mesh.
##
## The relaxation passes are the price of a smooth surface: they move vertices
## for reasons that have nothing to do with where the pins are. Near a pin
## that is exactly wrong — a pin has to mean the place it sits on — so near a
## pin they are turned off, and they fade back in with distance.
func _measure_hold() -> void:
	var span: float = maxf(_cell.length() * 1.6, softness)
	var span2: float = span * span
	for i in _hold.size():
		# Union the pin influences instead of letting the single strongest pin
		# erase all the others. This matters at joints where two pins overlap: the
		# ARAP relaxation should be protected by both controls, not whichever one
		# happens to be a fraction closer.
		var free: float = 1.0
		for r in _reach:
			var d: float = (r as PackedFloat32Array)[i]
			if d >= FAR:
				continue
			var got: float = clampf(exp(-(d * d) / span2), 0.0, 1.0)
			free *= 1.0 - got
		_hold[i] = clampf(1.0 - free, 0.0, 1.0)

## ---------------------------------------------------------------- fold-over guard
##
## A rectangle clamp cannot prevent a triangle from turning inside-out: the
## inversion happens while all three vertices are still inside the rectangle.
## Preserve each source triangle's winding and a small positive area. When a
## solver step crosses that boundary, binary-search that exact step and keep
## the largest feasible fraction. The same rule is implemented by IvoryWarp in
## C++, so the fallback and native paths have identical safety semantics.
func _mesh_is_valid(points: PackedVector2Array) -> bool:
	if _tris.is_empty() or points.size() != _rest_v.size():
		return true
	var span2: float = maxf(_cell.x * _cell.x, 1.0)
	var count: int = floori(float(_tris.size()) / 3.0)
	for t in count:
		var a: int = _tris[t * 3]
		var b: int = _tris[t * 3 + 1]
		var c: int = _tris[t * 3 + 2]
		var rab: Vector2 = _rest_v[b] - _rest_v[a]
		var rac: Vector2 = _rest_v[c] - _rest_v[a]
		var rest_area: float = rab.cross(rac)
		var pab: Vector2 = points[b] - points[a]
		var pac: Vector2 = points[c] - points[a]
		var area: float = pab.cross(pac)
		var floor_area: float = maxf(absf(rest_area) * 0.015, span2 * 0.000001)
		if rest_area > 0.0:
			if area < floor_area:
				return false
		else:
			if area > -floor_area:
				return false
	return true

func _prevent_foldover(before: PackedVector2Array) -> void:
	PuppetWarpFoldover.prevent_foldover(self, before)

# --------------------------------------------------------------- the solve

## Works out where every vertex of the drawing has ended up.
##
## The relaxation passes are the difference between a warp and a smear, and a
## fixed two was wrong twice over: too many for a cheap tablet following a
## finger at sixty frames a second, far too few for the moment when quality is
## all that matters and nobody is waiting. Mid-drag the answer must arrive
## before the next frame and is about to be replaced anyway — one pass with
## nothing spare, two otherwise. On `settle`, six, past the point where
## another changes anything the eye can find. Same arithmetic either way: it
## buys accuracy with time that was going spare.
func solve(settle: bool = false) -> void:
	if _rest_v.is_empty():
		return
	var count: int = pins.size()

	# --- the native solver, when it is there ---
	#
	# Same solve, same result, in C++. Everything below this branch is the
	# GDScript that runs when it is not, and it is not dead code: it is what a
	# checkout with no `bin/` runs, which is every checkout before somebody
	# builds the extension.
	# --- the as-rigid-as-possible engine, when it is there ---
	#
	# Ahead of the older native path because it is a different solve, not a
	# faster one. That path is the moving-least-squares placement with ARAP
	# rounds on top of it; this one minimises the ARAP energy directly from
	# rest with the pins as hard constraints. The difference is the whole of
	# the "it drags instead of stretching" report. See `PuppetWarpForge`.
	if PuppetWarpForge.solve(self, settle):
		_clamp_to_rect()
		if _order_dirty:
			_order_triangles()
		_push_mesh()
		queue_redraw()
		return

	if _fast != null and _fast_mesh and _solve_fast(settle):
		if _order_dirty:
			_order_triangles()
		_push_mesh()
		queue_redraw()
		return

	if count == 0:
		_now_v = _rest_v.duplicate()
		_last_good_v = _rest_v.duplicate()
	else:
		if _reach_dirty:
			_rebuild_reach()
			_measure_hold()
		if count < RIGID_FROM:
			# One pin cannot describe a rotation, so it carries the drawing.
			# All of it: a loose piece with no path to the pin used to be
			# left standing while everything else moved, which took the
			# picture apart. `_bridge_islands` has already given those pieces
			# a finite distance, so there is nothing here to exclude.
			var only: Pin = pins[0] as Pin
			var shift: Vector2 = only.now - only.rest
			for i in _rest_v.size():
				_now_v[i] = _rest_v[i] + shift
			_clamp_to_rect()
		else:
			if _weights.size() != count:
				_weights.resize(count)
			for i in _rest_v.size():
				_now_v[i] = _warp(i)
			# MLS has placed every vertex. What follows makes the placement
			# hold its shape — see `_arap_fit`. It is given the MLS answer as
			# its starting point rather than the rest pose, which is the whole
			# reason a couple of rounds is enough where a cold start would
			# need dozens.
			_mark_pinned()
			var rigid: float = clampf(_rigid_strength(), 0.0, 1.0)
			if rigid > 0.001:
				var rounds: int = 6 if settle \
					else (3 if Perf.headroom > 0.35 else 2)
				var both: bool = settle or _rest_v.size() < 4200
				for round_i in rounds:
					_arap_fit()
					var before_forward: PackedVector2Array = _now_v.duplicate()
					_arap_sweep(false, rigid)
					_prevent_foldover(before_forward)
					if both:
						var before_backward: PackedVector2Array = _now_v.duplicate()
						_arap_sweep(true, rigid)
						_prevent_foldover(before_backward)
					var before_pins: PackedVector2Array = _now_v.duplicate()
					_enforce_pins()
					_prevent_foldover(before_pins)
			# A light polish on top, for anyone who wants the surface softer
			# than the drawing itself is. ARAP is not a smoothing pass and
			# deliberately leaves a sharp corner sharp.
			if smoothing > 0.001:
				var before_smooth: PackedVector2Array = _now_v.duplicate()
				_relax_smooth()
				_prevent_foldover(before_smooth)
			# One final projection makes pins true positional constraints, not
			# merely heavy weights.
			var before_final_pins: PackedVector2Array = _now_v.duplicate()
			_enforce_pins()
			_prevent_foldover(before_final_pins)
		_clamp_to_rect()

	if _order_dirty:
		_order_triangles()
	_push_mesh()
	queue_redraw()


# ------------------------------------------------- as-rigid-as-possible
#
# ## What this is and where it comes from
#
# **As-Rigid-As-Possible shape manipulation** — Igarashi, Moscovich and Hughes
# (2005) for the 2D case, and Sorkine and Alexa (2007) for the local/global
# formulation used here. It is the deformation behind Photoshop's Puppet Warp,
# Krita's cage transform and every Live2D-style deformer, and it is not a
# heuristic: it is the minimiser of a stated energy.
#
# The energy says the drawing should be locally *rigid*. For every edge of the
# mesh, the vector between its two ends after the pull should be the vector it
# was before, turned by some rotation — and each vertex gets one rotation for
# all the edges around it:
#
#     E = Σ_i Σ_j∈N(i)  w_ij ‖ (p_i − p_j) − R_i (p⁰_i − p⁰_j) ‖²
#
# Nothing in that expression permits a stretch or a shear. A region that is
# merely carried and turned costs nothing at all; a region that is squashed
# costs, and the solve spends its freedom elsewhere to avoid paying.
#
# ## Why it is here on top of MLS rather than instead of it
#
# Rigid MLS is exact where it matters and cheap: it interpolates every pin
# outright, it is computed from the rest pose so a pin dragged back returns
# the drawing precisely, and it never stretches ink. What it cannot do is the
# **ground between two pins pulling different ways**. Each pin's neighbourhood
# is rigid and the blend in between takes up the whole of the difference by
# collapsing — pull two pins together and the drawing between them thins out.
#
# That collapse is what `_relax_area` was written to patch, by measuring how
# much area each triangle had lost and shoving its corners outwards. It is a
# fair patch and it is still a patch: it restores *area* without any opinion
# about shape, so a square that has become a thin diamond is given its area
# back as a fatter diamond. ARAP has an opinion about shape, because shape is
# the thing its energy is written about.
#
# ## How it is solved without a sparse factorisation
#
# The standard solve alternates two steps and each has a closed form:
#
#   * **Local.** With the vertices held still, the best rotation for each one
#     is read straight off its own edge fan. In two dimensions no SVD is
#     needed at all — minimising over a rotation gives
#     `θ = atan2( Σ w (e⁰ × e), Σ w (e⁰ · e) )`, and since every use of θ is a
#     rotation, the normalised sums *are* the cosine and sine and the angle is
#     never formed.
#
#   * **Global.** With the rotations held still, the energy is a quadratic in
#     the positions whose minimum is a Laplace system, `L p = b`. Factorising
#     it is what a desktop tool does; on a phone, with a mesh that is a
#     regular grid and an initial guess already close, **Gauss–Seidel** on the
#     same system converges in a couple of sweeps. Each vertex is simply moved
#     to the average its neighbours ask for:
#
#         p_i ← ( Σ_j p_j + ½(R_i + R_j)(p⁰_i − p⁰_j) ) / |N(i)|
#
#     Sweeps alternate direction so information does not have to travel one
#     vertex per pass against the raster order.
#
# Weights are uniform because the mesh is a regular grid — the cotangent
# weights of the general formulation all come out equal on one, so computing
# them would be arithmetic to arrive at 1.

## Which vertices a pin is holding outright, so the sweeps leave them alone.
##
## A sweep that moved a pinned vertex would be undone by `_enforce_pins` on
## the next line, but not before its wrong answer had been read by every
## neighbour it touched on the way past — Gauss–Seidel uses values as it
## writes them, which is exactly why it converges quickly and exactly why a
## wrong value in it spreads.
func _mark_pinned() -> void:
	var n: int = _rest_v.size()
	if _pinned.size() != n:
		_pinned.resize(n)
	for i in n:
		_pinned[i] = 0
	for one in pins:
		var p: Pin = one as Pin
		if p.vertex >= 0 and p.vertex < n:
			_pinned[p.vertex] = 1

func _arap_fit() -> void:
	PuppetWarpArap.arap_fit(self)

func _arap_sweep(backwards: bool, pull: float) -> void:
	PuppetWarpArap.arap_sweep(self, backwards, pull)

## Hands the pose to the native solver and takes the answer back.
##
## Returns false when it could not, so the caller falls through to the
## GDScript — which is what happens on a platform the library has not been
## built for, and what has to go on happening.
##
## ## What crosses the boundary, and how often
##
## The mesh goes over once per rebuild. The pins go over in two ways: the whole
## set when one is added, removed or anchored, which is what makes the walked
## distances stale; and just their positions and turns on every frame of a
## drag, which does not. That split is the difference between sending a few
## dozen floats per frame and rebuilding a distance field per frame.
func _solve_fast(settle: bool) -> bool:
	var rest_pins: PackedVector2Array = PackedVector2Array()
	var now_pins: PackedVector2Array = PackedVector2Array()
	var vertex: PackedInt32Array = PackedInt32Array()
	var turn: PackedFloat32Array = PackedFloat32Array()
	rest_pins.resize(pins.size())
	now_pins.resize(pins.size())
	vertex.resize(pins.size())
	turn.resize(pins.size())
	for i in pins.size():
		var p: Pin = pins[i] as Pin
		rest_pins[i] = p.rest
		now_pins[i] = p.now
		vertex[i] = p.vertex
		turn[i] = p.turn
	if _fast_pins_dirty or _reach_dirty:
		_fast.call("set_pins", rest_pins, now_pins, vertex, turn)
		_fast_pins_dirty = false
		# The GDScript side's own distance field is now the stale one. Left
		# stale on purpose: rebuilding it would be paying for an answer the
		# native side has already given, and it is rebuilt the moment anything
		# falls back to GDScript anyway.
		_reach_dirty = false
	else:
		_fast.call("move_pins", now_pins, turn)
	_fast.call("set_mode", fit_mode)
	_fast.call("set_params", stiffness, softness, _rigid_strength(),
		smoothing, 1.62)
	var got: PackedVector2Array = _fast.call("solve", settle)
	if got.size() != _rest_v.size():
		return false
	_now_v = got
	return true

## Pins are hard constraints. MLS interpolates them analytically, but the
## optional smoothing/area passes happen afterwards; projecting their mesh
## vertices back to the controls removes the tiny visible drift those passes
## can otherwise introduce and makes the artwork feel nailed to the handles.
func _clamp_to_rect() -> void:
	# A deformer is allowed to bend the drawing, never to manufacture mesh
	# outside the source image. The projection is a final feasibility step,
	# not a crop of the rendered pixels, so the topology stays unchanged.
	var lo: Vector2 = Vector2(rect.position)
	var hi: Vector2 = lo + Vector2(rect.size)
	for i in _now_v.size():
		var p: Vector2 = _now_v[i]
		p.x = clampf(p.x, lo.x, hi.x)
		p.y = clampf(p.y, lo.y, hi.y)
		_now_v[i] = p

func _enforce_pins() -> void:
	for one in pins:
		var pin: Pin = one as Pin
		if pin.vertex >= 0 and pin.vertex < _now_v.size():
			_now_v[pin.vertex] = pin.now
			if rect.size.x > 0 and rect.size.y > 0:
				var lo: Vector2 = Vector2(rect.position)
				var hi: Vector2 = lo + Vector2(rect.size)
				_now_v[pin.vertex].x = clampf(_now_v[pin.vertex].x, lo.x, hi.x)
				_now_v[pin.vertex].y = clampf(_now_v[pin.vertex].y, lo.y, hi.y)

## Where one vertex of the rest drawing ends up.
##
## Weigh every pin by how far it is through the mesh; find the weighted centre
## of the pins as they were and as they are now; then find the single rotation
## that best carries the first arrangement onto the second, as weighted from
## this vertex. Turn the vertex by that rotation about the rest centre and put
## it down at the new centre. Because only a rotation is fitted — never a
## stretch — the drawing keeps its proportions.
func _warp(at: int) -> Vector2:
	var v: Vector2 = _rest_v[at]
	var count: int = pins.size()
	var total: float = 0.0
	var p_star: Vector2 = Vector2.ZERO
	var q_star: Vector2 = Vector2.ZERO
	var soft2: float = softness * softness
	var plain: bool = absf(stiffness - 1.0) < 0.0001

	for i in count:
		var pin: Pin = pins[i] as Pin
		var d: float = (_reach[i] as PackedFloat32Array)[at]
		if d >= FAR:
			# No path from this pin to here. Nothing this pin does should
			# reach a piece of drawing it is not joined to.
			_weights[i] = 0.0
			continue
		var d2: float = d * d
		if d2 < 0.000001:
			return pin.now
		# `pow` is called once per vertex per pin — tens of thousands of times
		# for every frame of a drag — so the default exponent skips it.
		var den: float = d2 + soft2
		var w: float = 1.0 / den if plain else 1.0 / pow(den, stiffness)
		_weights[i] = w
		total += w
		p_star += pin.rest * w
		q_star += pin.now * w

	if total <= 0.0:
		return v
	p_star /= total
	q_star /= total

	var u: Vector2 = v - p_star
	var fr: Vector2 = Vector2.ZERO
	for i in count:
		if _weights[i] <= 0.0:
			continue
		var other: Pin = pins[i] as Pin
		var ph: Vector2 = other.rest - p_star
		var qh: Vector2 = other.now - q_star
		# The two halves of a rotation, read off the rest offset against this
		# vertex: how much it lies along it, and how much across it.
		var along: float = ph.dot(u)
		var across: float = ph.x * u.y - ph.y * u.x
		fr += _weights[i] * Vector2(
			qh.x * along - qh.y * across,
			qh.x * across + qh.y * along)

	var placed: Vector2 = q_star

	if fit_mode == Fit.AFFINE:
		# --- the affine fit ---
		#
		# The exact weighted least-squares linear map from the rest offsets to
		# the moved ones:
		#
		#     M = (sum w p^T p)^-1 (sum w p^T q),   f(v) = (v - p*) M + q*
		#
		# A two-by-two inverse written out, because at this size a general
		# solver is both slower and less accurate than the closed form.
		#
		# This is the mode that squashes: two pins pulled together compress
		# the material along the line joining them and leave what is square to
		# it alone. See `Fit`.
		var sxx: float = 0.0
		var sxy: float = 0.0
		var syy: float = 0.0
		var txx: float = 0.0
		var txy: float = 0.0
		var tyx: float = 0.0
		var tyy: float = 0.0
		for i in count:
			var wa: float = _weights[i]
			if wa <= 0.0:
				continue
			var one: Pin = pins[i] as Pin
			var ph2: Vector2 = one.rest - p_star
			var qh2: Vector2 = one.now - q_star
			sxx += wa * ph2.x * ph2.x
			sxy += wa * ph2.x * ph2.y
			syy += wa * ph2.y * ph2.y
			txx += wa * ph2.x * qh2.x
			txy += wa * ph2.x * qh2.y
			tyx += wa * ph2.y * qh2.x
			tyy += wa * ph2.y * qh2.y
		var det: float = sxx * syy - sxy * sxy
		# Degenerate: one pin, or every pin on a single line through the
		# centre. There is no affine map to find — the system is rank
		# deficient and inverting it amplifies noise without limit — so the
		# rigid answer below is used instead. One pin dragged should carry the
		# drawing, not tear it.
		if absf(det) > 0.000000001:
			var ixx: float = syy / det
			var ixy: float = -sxy / det
			var iyy: float = sxx / det
			var m00: float = ixx * txx + ixy * tyx
			var m01: float = ixx * txy + ixy * tyy
			var m10: float = ixy * txx + iyy * tyx
			var m11: float = ixy * txy + iyy * tyy
			placed = q_star + Vector2(u.x * m00 + u.y * m10,
				u.x * m01 + u.y * m11)
			if not _any_turn:
				return placed
			return _spun(placed, count)

	var span: float = fr.length()
	if span >= 0.000000001:
		if fit_mode == Fit.SIMILARITY:
			# The same fit, divided by the weighted sum of the squared rest
			# offsets rather than renormalised to the vertex's old distance.
			# That single division is where the scale comes from.
			var mu: float = 0.0
			for i in count:
				var wb: float = _weights[i]
				if wb <= 0.0:
					continue
				mu += wb * ((pins[i] as Pin).rest - p_star).length_squared()
			if mu > 0.000000001:
				placed = q_star + fr / mu
			else:
				placed = q_star + fr * (u.length() / span)
		else:
			# Only the direction of the fit is kept; the distance from the
			# centre is the one the vertex already had. That is the whole of
			# "rigid": the fit may turn the drawing, never stretch it.
			placed = q_star + fr * (u.length() / span)

	if not _any_turn:
		return placed
	return _spun(placed, count)

## The turns the pins carry, laid on top of whichever fit produced `placed`.
##
## Lifted out of `_warp` when the affine fit arrived, so all three modes share
## one implementation of spin rather than the two later ones quietly losing it.
func _spun(placed: Vector2, count: int) -> Vector2:
	# The turns the pins were given, laid on top of the fit above.
	#
	# Composed rather than folded into the fit, and that is deliberate: with
	# every turn at nought this reduces to exactly the line above, so a pose
	# built before pins could be turned bends today precisely as it did.
	#
	# Averaged **as directions** — unit vectors summed, and the angle of the
	# sum taken — which is the only correct mean for angles. Averaging the
	# numbers would have to choose which way round to go between a pin at
	# three degrees and one at three hundred and fifty-seven, and would land
	# halfway round the wrong side.
	#
	# **The turn happens about the pin that was turned**, and this is the
	# whole of why the ring used to do so little.
	#
	# It used to happen about `q_star` — the weighted centre of every pin
	# reaching this vertex. The reasoning was that near a turned pin its own
	# weight dominates, so `q_star` is nearly that pin. Which is true, and is
	# exactly the problem: a rotation about a point does not move that point,
	# and `q_star` collapsing onto the pin is `q_star` collapsing onto the
	# place the drawing is being asked to turn around. The offset being
	# rotated shrank to nothing precisely where the effect should have been
	# strongest, and further out the untouched pins pulled the average angle
	# back towards nought. Weak close in, weak far out, and no distance at
	# which it did what a ring promises.
	#
	# Measured on a four-pin figure, turning one pin a quarter circle:
	#
	#     20 px from the pin   moved 18 where it should move 28
	#     40 px from the pin   moved 11 where it should move 57
	#     60 px from the pin   moved  2 where it should move 85
	#
	# Two units of travel for a quarter-turn is a control that does nothing.
	#
	# So the centre is the turned pins themselves, weighted by how much each
	# is turned and by how much it reaches here. With one pin turned — the
	# ordinary case — that is exactly that pin, and the drawing swings
	# around it the way the ring says it will. The *angle* is still shared
	# out by weight, so the turn still fades with distance and still gives
	# way to pins that are holding: strength where the ring is, and nothing
	# where the drawing is being held still.
	var spin: Vector2 = Vector2.ZERO
	var pivot: Vector2 = Vector2.ZERO
	var pivot_w: float = 0.0
	for i in count:
		var w2: float = _weights[i]
		if w2 <= 0.0:
			continue
		var turned: Pin = pins[i] as Pin
		var a: float = turned.turn
		spin += Vector2(cos(a), sin(a)) * w2
		if absf(a) > 0.0001:
			var share: float = w2 * absf(a)
			pivot += turned.now * share
			pivot_w += share
	if spin.length_squared() < 0.000000001 or pivot_w <= 0.0:
		return placed
	spin = spin.normalized()
	pivot /= pivot_w
	var off: Vector2 = placed - pivot
	return pivot + Vector2(off.x * spin.x - off.y * spin.y,
		off.x * spin.y + off.y * spin.x)

func _relax_smooth() -> void:
	PuppetWarpArap.relax_smooth(self)

func _smooth_by(amount: float) -> void:
	PuppetWarpArap.smooth_by(self, amount)

func _relax_area() -> void:
	PuppetWarpArap.relax_area(self)

func _order_triangles() -> void:
	PuppetWarpArap.order_triangles(self)

# ------------------------------------------------------------------ drawing

func _push_mesh() -> void:
	if _mesh_node == null or _now_v.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _now_v
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_INDEX] = _index
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_node.mesh = mesh

func _draw() -> void:
	PuppetWarpDraw.draw(self)

## The mesh's own colour: ivory, the same one the app's frames and joints wear.
const IVORY_WIRE: Color = Color(0.99, 0.96, 0.88, 0.62)

func _draw_wire(col: Color, width: float) -> void:
	PuppetWarpDraw.draw_wire(self, col, width)

func _draw_pin(p: Pin, thin: float, chosen: bool = false) -> void:
	PuppetWarpDraw.draw_pin(self, p, thin, chosen)

func _draw_ring(p: Pin, thin: float) -> void:
	PuppetWarpDraw.draw_ring(self, p, thin)

# ------------------------------------------------------------------ baking

## The box the bent drawing now needs, which is rarely the box it started in —
## pulling a limb out puts ink where there was none.
func deformed_bounds() -> Rect2i:
	if _now_v.is_empty():
		return rect
	var lo: Vector2 = _now_v[0]
	var hi: Vector2 = _now_v[0]
	for v in _now_v:
		lo.x = minf(lo.x, v.x)
		lo.y = minf(lo.y, v.y)
		hi.x = maxf(hi.x, v.x)
		hi.y = maxf(hi.y, v.y)
	# A pixel of air on each side, so a linear sample at the very edge has
	# something to read and the outline does not come back clipped.
	var pad: Vector2 = Vector2(2.0, 2.0)
	var box: Rect2i = Rect2i(Vector2i((lo - pad).floor()),
		Vector2i((hi - lo + pad * 2.0).ceil()))
	box.size.x = clampi(box.size.x, 1, MAX_BAKE)
	box.size.y = clampi(box.size.y, 1, MAX_BAKE)
	return box

## Renders the bent drawing once and hands back the pixels.
##
## The graphics card does the rasterising. Walking a few thousand triangles by
## hand in script would take long enough to be felt, and it would have to
## reinvent the sampling the card already does properly.
func bake() -> Dictionary:
	if _now_v.is_empty() or _tex == null:
		return {}
	# Solved properly one last time before it becomes pixels: this is the
	# answer that gets written into the drawing and kept.
	if not pins.is_empty():
		solve(true)
	var box: Rect2i = deformed_bounds()

	var shifted: PackedVector2Array = PackedVector2Array()
	shifted.resize(_now_v.size())
	var origin: Vector2 = Vector2(box.position)
	for i in _now_v.size():
		shifted[i] = _now_v[i] - origin

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = shifted
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_INDEX] = _index
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var port: SubViewport = SubViewport.new()
	port.size = box.size
	port.transparent_bg = true
	port.disable_3d = true
	port.render_target_update_mode = SubViewport.UPDATE_ONCE
	port.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	# The bake is the pixels the drawing keeps, so it is sampled as well as
	# the card can rather than as fast as it can.
	port.msaa_2d = Viewport.MSAA_4X

	var flat: MeshInstance2D = MeshInstance2D.new()
	flat.mesh = mesh
	flat.texture = _tex
	flat.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	flat.material = PaintSurface.premultiplied_material()
	port.add_child(flat)
	add_child(port)

	# Two frames: one for the viewport to be told to draw, one for the draw to
	# have happened. Reading after a single frame returns the frame before
	# this one, which on the first bake is nothing at all.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var out: Image = port.get_texture().get_image()
	port.queue_free()
	if out == null:
		return {}
	if out.get_format() != Image.FORMAT_RGBA8:
		out.convert(Image.FORMAT_RGBA8)
	return {"image": out, "at": box.position, "rect": box}

func finish() -> void:
	if _mesh_node != null:
		_mesh_node.visible = false
		_mesh_node.mesh = null
	source = null
	_tex = null
	pins.clear()
	selected = -1
	_rest_v = PackedVector2Array()
	_now_v = PackedVector2Array()
	_reach = []
	queue_redraw()
