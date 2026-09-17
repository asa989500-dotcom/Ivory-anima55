class_name PuppetWarpFoldover
extends RefCounted
## Backs a move off until the mesh is sound again.
##
## Lifted out of `puppet_warp.gd` at stage 153, unchanged. That file reached
## the twelve hundred lines a file written from today is allowed, and the size
## ledger's rule is that growth is paid for out of another file — so the warp
## gaining the forge and the as-rigid-as-possible engine is paid for here.
##
## It lifts along a real seam: it takes a before and an after and returns the
## furthest point along the line between them at which no triangle is inside
## out. Nothing else in the warp needs to know how that search works.

static func prevent_foldover(host: PuppetWarp, before: PackedVector2Array) -> void:
	if host._tris.is_empty() or before.size() != host._now_v.size():
		return
	if host._mesh_is_valid(host._now_v):
		host._last_good_v = host._now_v.duplicate()
		return
	# `before` should already be feasible. If it is not — a pin jumped so far
	# in one step that even the starting point cannot be trusted — restore
	# the last pose actually verified sound, never the rest pose outright:
	# that would throw every pin's work away for a fault in one triangle and
	# make the whole drawing visibly jump back to its undeformed shape.
	if not host._mesh_is_valid(before):
		if host._last_good_v.size() == host._now_v.size():
			host._now_v = host._last_good_v.duplicate()
		return
	var target: PackedVector2Array = host._now_v.duplicate()
	var candidate: PackedVector2Array = PackedVector2Array()
	candidate.resize(host._now_v.size())
	var lo: float = 0.0
	var hi: float = 1.0
	for iteration in 10:
		var mid: float = (lo + hi) * 0.5
		for i in host._now_v.size():
			candidate[i] = before[i].lerp(target[i], mid)
		if host._mesh_is_valid(candidate):
			lo = mid
		else:
			hi = mid
	for i in host._now_v.size():
		host._now_v[i] = before[i].lerp(target[i], lo)
	host._last_good_v = host._now_v.duplicate()
