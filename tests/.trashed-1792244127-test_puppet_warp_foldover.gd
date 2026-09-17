extends "res://tests/test_case.gd"
## The puppet warp's fold-over guard, and the fault it used to have.
##
## `_prevent_foldover` backs a step off until no triangle is inside out — but
## when even the step's *starting* point was already invalid, it used to
## reset the whole mesh to its undeformed rest pose, discarding every pin's
## work for a fault that touched one triangle. On screen that read as the
## drawing snapping back to its original shape mid-drag: exactly what makes
## a puppet warp feel like it "doesn't hold still when something goes wrong".
##
## This exercises the pure-GDScript solver (the path every checkout runs
## before the native extension is built) with a drag hard enough to force
## the guard to engage more than once in a row, and checks the pose ends up
## bent — not snapped back to `rest`.

func title() -> String:
	return "puppet warp fold-over guard"

func run() -> void:
	_a_hard_drag_holds_the_last_good_pose()

func _a_hard_drag_holds_the_last_good_pose() -> void:
	note("an extreme drag does not reset the mesh to its rest pose")
	var art: Image = Image.create_empty(200, 200, false, Image.FORMAT_RGBA8)
	art.fill(Color(0.05, 0.04, 0.03, 1.0))

	var puppet: PuppetWarp = PuppetWarp.new()
	var began: bool = puppet.begin(art, Rect2i(0, 0, 200, 200), 20)
	ok(began, "the warp accepted a fully-inked square")
	if not began:
		return

	var a: int = puppet.add_pin(Vector2(10.0, 10.0))
	var b: int = puppet.add_pin(Vector2(190.0, 190.0))
	ok(a >= 0 and b >= 0, "both pins were placed")

	# Corners dragged most of the way past each other — the same shape of
	# stress the native test uses, and about as unreasonable as a finger on
	# a screen gets.
	puppet.move_pin(a, Vector2(210.0, 10.0))
	puppet.move_pin(b, Vector2(-10.0, 190.0))
	puppet.settle_pose()

	var drift_from_rest: float = 0.0
	for i in puppet._rest_v.size():
		drift_from_rest += puppet._now_v[i].distance_to(puppet._rest_v[i])
	# A guard that falls back to rest on every hard case leaves the mesh
	# sitting exactly at `_rest_v` — this is the check that would have
	# failed before the fix.
	ok(drift_from_rest > 1.0, "a hard drag left the mesh sitting at its rest pose")
	ok(puppet._mesh_is_valid(puppet._now_v),
		"the pose the guard settled on is itself a sound mesh")

	puppet.finish()
