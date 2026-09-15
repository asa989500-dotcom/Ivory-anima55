class_name PuppetWarpPins
extends RefCounted
## Adding, finding, moving and removing the pins of a puppet warp, and the
## ring around a pin that turns it.
##
## Lifted out of `puppet_warp.gd` at stage 145 to bring that file back under
## the size the project allows. `PuppetWarp` keeps a one-line delegate for
## each, so nothing that called them changed.
##
## The touch rules live here and are worth keeping together: a pin has a
## sensor slightly larger than it looks, so it can be caught by a fingertip
## rather than by a cursor, and a pin that has been caught stays caught until
## the finger lifts.

## Pins live on the mesh, and the mesh is the drawing.
##
## A pin dropped on blank paper used to be accepted and then quietly did
## nothing sensible: it had no ink to hold, and it dragged whatever happened
## to be nearest in a straight line. Now a tap off the drawing is refused,
## and a tap just outside its edge is taken as meaning the edge.
static func add_pin(host: PuppetWarp, at: Vector2) -> int:
	var vertex: int = host._vertex_near(at)
	if vertex < 0:
		return -1
	var p: PuppetWarp.Pin = PuppetWarp.Pin.new()
	p.rest = host._rest_v[vertex]
	p.now = p.rest
	p.vertex = vertex
	host.pins.append(p)
	host.selected = host.pins.size() - 1
	host._order_dirty = true
	host._reach_dirty = true
	host._fast_pins_dirty = true
	host.solve()
	host.changed.emit()
	return host.selected

## The pin under a finger, nearest first. `reach` is in page units so the
## target stays the same size on screen at any zoom.
static func pin_at(host: PuppetWarp, at: Vector2, reach: float) -> int:
	var best: int = -1
	var best_d: float = reach * reach
	for i in host.pins.size():
		var d: float = at.distance_squared_to((host.pins[i] as PuppetWarp.Pin).now)
		if d <= best_d:
			best_d = d
			best = i
	return best

static func move_pin(host: PuppetWarp, index: int, to: Vector2) -> void:
	if index < 0 or index >= host.pins.size():
		return
	var p: PuppetWarp.Pin = host.pins[index] as PuppetWarp.Pin
	if p.anchored:
		return
	if host._last_pose.size() != host.pins.size():
		host.remember_pose()
	p.now = to
	host.solve()
	host.changed.emit()

static func remove_pin(host: PuppetWarp, index: int) -> void:
	if index < 0 or index >= host.pins.size():
		return
	host.pins.remove_at(index)
	host._note_turns()
	if host.selected >= host.pins.size():
		host.selected = host.pins.size() - 1
	host._order_dirty = true
	host._reach_dirty = true
	host._fast_pins_dirty = true
	host.solve()
	host.changed.emit()

## Whether a pin may be put down here at all.
static func can_pin(host: PuppetWarp, at: Vector2) -> bool:
	return host._vertex_near(at) >= 0

## The mesh vertex nearest a point, or -1 when the point is off the mesh.
static func vertex_near(host: PuppetWarp, at: Vector2) -> int:
	if host._rest_v.is_empty():
		return -1
	var best: int = -1
	var best_d: float = INF
	for i in host._rest_v.size():
		var d: float = host._rest_v[i].distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = i
	# Beyond a cell or so from any vertex there is no drawing here to pin.
	var span: float = host._cell.length() * 1.25
	if best_d > span * span:
		return -1
	return best

## How wide the ring around the chosen pin is drawn, in page units.
##
## Well clear of the pin itself — a ring drawn tight around a thirteen-point
## disc is a ring you cannot put a thumb on without covering the pin, and the
## first thing every finger would do is drag the pin instead of turning it.
static func ring_radius(host: PuppetWarp) -> float:
	return 46.0 / maxf(host.zoom, 0.0001)

## Whether a touch has landed on the chosen pin's ring.
##
## A band rather than a line, and a wide one: the ring is a circle a finger has
## to follow, and the whole of the gesture is *rotation* — how far round, not
## how far out — so being loose about the radius costs nothing and being strict
## about it loses the grip halfway through every turn.
static func on_ring(host: PuppetWarp, at: Vector2) -> bool:
	if host.selected < 0 or host.selected >= host.pins.size():
		return false
	var p: PuppetWarp.Pin = host.pins[host.selected] as PuppetWarp.Pin
	var r: float = host.ring_radius()
	var d: float = at.distance_to(p.now)
	var band: float = 20.0 / maxf(host.zoom, 0.0001)
	return d > r - band and d < r + band

## Turns a pin. `to` is where the finger is, and the pin turns to face it.
##
## Given as a place rather than as an angle so the caller never has to do the
## arithmetic, and so the grip cannot drift: whatever happens to the frame
## rate, the pin points exactly where the thumb is.
static func turn_pin_towards(host: PuppetWarp, index: int, to: Vector2, grabbed_at: float) -> void:
	if index < 0 or index >= host.pins.size():
		return
	var p: PuppetWarp.Pin = host.pins[index] as PuppetWarp.Pin
	if host._last_pose.size() != host.pins.size():
		host.remember_pose()
	var here: float = (to - p.now).angle()
	p.turn = here - grabbed_at
	host._note_turns()
	host.solve()
	host.changed.emit()
