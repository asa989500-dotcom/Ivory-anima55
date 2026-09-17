class_name IvoryGuard
extends RefCounted

static func full_geometry_sweep(rest: PackedVector2Array, now: PackedVector2Array,
		neighbours: PackedInt32Array, triangles: PackedInt32Array,
		pins: PackedVector2Array, pin_vertices: PackedInt32Array,
		bone_parents: PackedInt32Array, frame_ids: PackedInt32Array,
		weights: PackedFloat32Array, texture_size: Vector2i,
		pixel_bytes: PackedByteArray, elapsed_ms: float, budget_ms: float) -> Dictionary:
	var g: Object = Native.guard20()
	if g == null:
		return {"ok": true, "native": false, "checks": [], "failures": 0}
	var checks: Array = [
		g.mesh_topology(rest, neighbours, triangles),
		g.finite_geometry(rest),
		g.triangle_area(rest, triangles, 0.000001),
		g.pose_displacement(rest, now, 1000000000.0),
		g.pin_binding(pin_vertices, rest.size()),
		g.pin_finite(pins),
		g.bounds(now, Vector2.ZERO, Vector2(texture_size), 2.0),
		g.skin_weights(weights, 4, 0.001),
		g.bone_hierarchy(bone_parents),
		g.transform_finite(now),
		g.symmetry(0.0, 1),
		g.timeline(frame_ids, 1000000),
		g.frame_budget(elapsed_ms, budget_ms),
		g.texture_extent(texture_size.x, texture_size.y, 4),
		g.pixel_buffer(pixel_bytes, texture_size.x, texture_size.y, 4),
		g.touch_stream(now, 10000.0),
		g.audio_sync(0.0, 0.0),
		g.export_settings(texture_size.x, texture_size.y, 24, 0),
		g.memory_budget(pixel_bytes.size(), 512 * 1024 * 1024)
	]
	var aggregate: Dictionary = g.aggregate(checks)
	return {"ok": bool(aggregate.get("ok", false)), "native": true,
		"checks": checks, "aggregate": aggregate, "failures": int(aggregate.get("failures", 0))}
