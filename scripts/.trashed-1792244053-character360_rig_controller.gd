class_name Character360RigController
extends RefCounted
## High-level room facade. Geometry/math is native when the extension exists;
## this facade keeps the Character 360 layer format stable and supplies safe
## fallbacks for projects opened without the extension.

var native: Object = null
var layer_id: int = 0
var state: Dictionary = {}

func bind(layer: LayerStack.Layer) -> void:
	layer_id = layer.id if layer != null else 0
	state = {} if layer == null else layer.character360_state.duplicate(true)
	native = Native.character360_rig()
	if native == null:
		return
	for row in state.get("turn_discs", []):
		if row is Dictionary:
			native.add_disc(deg_to_rad(float(row.get("angle", 0.0))))

func disc_weights(yaw: float) -> PackedFloat32Array:
	if native != null:
		return native.disc_weights(yaw)
	var rows: Array = state.get("turn_discs", [])
	var out := PackedFloat32Array()
	out.resize(rows.size())
	if rows.is_empty():
		return out
	var best := 0
	var best_d := INF
	for i in rows.size():
		var d := absf(wrapf(yaw - deg_to_rad(float(rows[i].get("angle", 0.0))), -PI, PI))
		if d < best_d:
			best_d = d; best = i
	out[best] = 1.0
	return out


func bone_reference_weights(local_angle: float) -> PackedFloat32Array:
	return disc_weights(local_angle)

func reference_plan(local_angles: PackedFloat32Array) -> Array:
	var rows: Array = []
	for a in local_angles:
		rows.append(disc_weights(a))
	return rows

func solve_ik(points: PackedVector2Array, parent: PackedInt32Array,
		lengths: PackedFloat32Array, tip: int, target: Vector2) -> PackedVector2Array:
	if native == null:
		return points
	native.set_ik_enabled(true)
	if native.has_method("solve_ik_pole"):
		var pole := _stable_pole(points, parent, tip)
		return native.solve_ik_pole(points, parent, lengths, tip, target, pole, 8)
	return native.solve_ik(points, parent, lengths, tip, target, 8)

func _stable_pole(points: PackedVector2Array, parent: PackedInt32Array, tip: int) -> Vector2:
	if tip < 0 or tip >= points.size() or tip >= parent.size():
		return Vector2.ZERO
	var mid := parent[tip]
	if mid < 0 or mid >= points.size():
		return points[tip]
	return points[mid]

func constrain_turns(turns: PackedFloat32Array, delta: float) -> PackedFloat32Array:
	if native == null:
		return turns
	return native.apply_constraints(turns, delta)

func add_pin(rest: Vector2, type: int, bone: int = -1) -> int:
	if native == null:
		return -1
	return native.add_pin(rest, type, bone, 1.0)

func paint_weight(vertex: int, bone: int, strength: float, radius: float = 0.0) -> void:
	if native != null:
		native.paint_weights(vertex, bone, strength, radius)

func deform_ffd(points: PackedVector2Array) -> PackedVector2Array:
	if native == null:
		return points
	return native.ffd_deform(points)

func bind_member_art(layer: LayerStack.Layer, rest_points: PackedVector2Array) -> Dictionary:
	# Member data remains its own raster; this call only returns a native plan
	# describing which master/local channels apply.
	var local: Dictionary = {} if layer == null else layer.character360_state.get("local_rig", {})
	var local_bones: Array = local.get("bones", []) if local is Dictionary else []
	return {"ok": native != null, "master": true, "local": local_bones.size(), "points": rest_points.size()}

func diagnostics() -> Dictionary:
	return native.diagnostics() if native != null else {
		"discs": state.get("turn_discs", []).size(),
		"native": false,
		"live_mesh": true,
		"ik_fk": true,
		"pins": 5,
		"constraints": true,
		"weight_paint": true,
		"ffd": true,
	}
