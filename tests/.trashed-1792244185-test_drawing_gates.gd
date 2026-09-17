extends "res://tests/test_case.gd"
## May this layer be drawn on?
##
## The question is asked in two places — `LayerStack.can_draw` and
## `CanvasView._brush_layer_allowed` — and they have to give the same answer.
## When they disagree the app is worse than when both are wrong: one says yes
## and offers the brush, the other says no and swallows the stroke, so the
## tool looks alive and does nothing.
##
## That is exactly what happened. The rule was `not rig.is_empty()` — any layer
## with a skeleton refused every drawing tool for ever — and fixing it in the
## canvas alone left the stack still refusing. Brushes, the fill, everything.
##
## So this case asserts the rule and asserts that both askers hold it.

func title() -> String:
	return "drawing gates"

func run() -> void:
	_a_plain_layer_takes_ink()
	_a_layer_with_bones_on_it_is_still_a_drawing()
	_only_control_surfaces_refuse()
	_both_gates_give_the_same_answer()

## A real project's layer stack.
##
## Built through `ProjectManager` rather than by calling `LayerStack.new()`,
## because a stack is a node: it makes its first layer when it enters the
## tree, and one created loose has no layers at all and answers every question
## with null. A test that builds its subject differently from the app is a
## test of something the app never does.
var _manager: ProjectManager = null

func _stack() -> LayerStack:
	_manager = ProjectManager.new()
	var p: ProjectManager.Project = _manager.create("Gate test",
		ProjectManager.Kind.DRAWING, Vector2(256, 256), Color.WHITE, 1, Vector2.ZERO)
	_manager.active = p
	return p.page_at(0).stack

## A skeleton with one bone in it, in the shape the rig is actually stored in.
func _some_rig() -> Dictionary:
	return {"bones": [{
		"ax": 10.0, "ay": 10.0, "bx": 40.0, "by": 10.0, "parent": -1,
	}]}

func _a_plain_layer_takes_ink() -> void:
	note("an ordinary visible layer accepts a brush")
	var s: LayerStack = _stack()
	ok(s.can_draw(), "a fresh layer refused the brush")

	var l: LayerStack.Layer = s.active()
	not_null(l, "the fresh stack has no active layer")

	l.visible = false
	ok(not s.can_draw(), "a hidden layer accepted the brush")
	l.visible = true
	ok(s.can_draw(), "showing the layer again did not bring the brush back")

	l.locked = true
	ok(not s.can_draw(), "a locked layer accepted the brush")
	l.locked = false
	ok(s.can_draw(), "unlocking did not bring the brush back")

func _a_layer_with_bones_on_it_is_still_a_drawing() -> void:
	note("bones on a layer do not stop it being drawn on")
	# The fault, stated plainly. Quick bones tried on a figure, a layer lifted
	# and put down again with its skeleton, a return from the Character 360
	# room — all of them leave a rig behind, and none of them should stop the
	# brush.
	var s: LayerStack = _stack()
	var l: LayerStack.Layer = s.active()
	l.rig = _some_rig()
	ok(not l.rig.is_empty(), "the test rig did not attach")
	ok(s.can_draw(), "a layer with bones on it refused the brush")

	# Taking the bones off changes nothing, because they were never what
	# mattered.
	l.rig = {}
	ok(s.can_draw(), "removing the bones changed the answer")

func _only_control_surfaces_refuse() -> void:
	note("the three layers that hold no paintable pixels refuse, and only those")
	var s: LayerStack = _stack()
	var l: LayerStack.Layer = s.active()

	l.is_bone_layer = true
	ok(not s.can_draw(), "a bone layer accepted the brush")
	l.is_bone_layer = false

	l.is_character360 = true
	ok(not s.can_draw(), "a Character 360 reference layer accepted the brush")
	l.is_character360 = false

	l.is_character360_motion = true
	ok(not s.can_draw(), "a Character 360 motion layer accepted the brush")
	l.is_character360_motion = false

	ok(s.can_draw(), "the layer did not go back to being drawable")

func _both_gates_give_the_same_answer() -> void:
	note("the stack and the canvas never disagree about a layer")
	# Every combination that matters, through both askers. A disagreement is
	# the worst of the three possible states: the tool is offered and then
	# does nothing, which reads as the app being broken rather than as a rule.
	var view: CanvasView = CanvasView.new()
	var s: LayerStack = _stack()
	view.layers = s
	var l: LayerStack.Layer = s.active()

	var cases: Array = [
		{"name": "plain", "rig": false, "bone": false, "c360": false, "motion": false},
		{"name": "with bones", "rig": true, "bone": false, "c360": false, "motion": false},
		{"name": "bone layer", "rig": false, "bone": true, "c360": false, "motion": false},
		{"name": "bone layer with a rig", "rig": true, "bone": true, "c360": false, "motion": false},
		{"name": "character 360", "rig": true, "bone": false, "c360": true, "motion": false},
		{"name": "character 360 motion", "rig": true, "bone": false, "c360": false, "motion": true},
	]
	for one in cases:
		l.visible = true
		l.locked = false
		l.rig = _some_rig() if bool(one["rig"]) else {}
		l.is_bone_layer = bool(one["bone"])
		l.is_character360 = bool(one["c360"])
		l.is_character360_motion = bool(one["motion"])

		var by_stack: bool = s.can_draw()
		var by_canvas: bool = view._brush_layer_allowed()
		if by_stack != by_canvas:
			ok(false, "on a '%s' layer the stack says %s and the canvas says %s" \
				% [String(one["name"]), str(by_stack), str(by_canvas)])
		else:
			ok(true, "the two gates agree on a '%s' layer" % String(one["name"]))

		# And the answer is the one the rule says it should be.
		var control_surface: bool = bool(one["bone"]) or bool(one["c360"]) \
			or bool(one["motion"])
		eq(by_stack, not control_surface,
			"a '%s' layer got the wrong answer" % String(one["name"]))

	view.free()
