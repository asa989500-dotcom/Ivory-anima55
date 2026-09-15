extends Node

## Character 360 regression tests. These are deliberately small: every test
## exercises one invariant that can otherwise fail silently on a touch device.
func _ready() -> void:
	if not Native.has_character360_rig():
		print("SKIP Character360Rig: native extension not loaded")
		queue_free()
		return
	var r: Object = Native.character360_rig()
	assert(r.add_disc(-PI / 2.0) == 0)
	assert(r.add_disc(0.0) == 1)
	assert(r.add_disc(PI / 2.0) == 2)
	var w: PackedFloat32Array = r.disc_weights(0.0)
	assert(w.size() == 3 and absf(w[1] - 1.0) < 0.001)

	# Pins preserve their explicit type rather than collapsing into one generic
	# point constraint.
	var pin: int = r.add_pin(Vector2(4, 5), 3, 1, 1.0)
	assert(int(r.pin(pin)["type"]) == 3)

	# Weight painting is normalized after every brush stroke.
	r.resize_weights(4, 2)
	r.paint_weights(1, 1, 1.0, 1.0)
	var vw: PackedFloat32Array = r.vertex_weights(1)
	var sum := 0.0
	for x in vw: sum += x
	assert(absf(sum - 1.0) < 0.001)

	# History is operation based, not per sample.
	var p := PackedVector2Array([Vector2.ZERO, Vector2(10, 0)])
	var ww := PackedFloat32Array([1.0, 0.0])
	var t := PackedFloat32Array([0.0, 0.0])
	r.begin_history(p, ww, t)
	p[1] = Vector2(20, 0)
	r.commit_history(p, ww, t)
	var u: Dictionary = r.undo()
	assert(not u.is_empty())
	assert((u["points"] as PackedVector2Array)[1].x == 10.0)
	var rd: Dictionary = r.redo()
	assert(not rd.is_empty())
	assert((rd["points"] as PackedVector2Array)[1].x == 20.0)
	print("PASS Character360Rig")
	queue_free()
