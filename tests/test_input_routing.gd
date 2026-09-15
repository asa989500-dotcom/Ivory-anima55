extends "res://tests/test_case.gd"
## Regression test for the global canvas-input failure.
##
## A full-screen dismiss Control previously used MOUSE_FILTER_STOP. When a tool
## panel was open, the shade consumed the first touch on the canvas, closed the
## panel, and dropped the very event that should have started the stroke.
##
## This test checks the ownership contract in the actual project sources:
## the shade is visual-only and dismissal happens before GUI routing in
## MainRoom._input(), so the event remains available to CanvasView.

func title() -> String:
	return "input routing"

func run() -> void:
	_shade_is_visual_only()
	_mainroom_dismisses_before_gui_routing()
	_canvas_still_owns_canvas_events()

func _source(path: String) -> String:
	return FileAccess.get_file_as_string(path)

func _shade_is_visual_only() -> void:
	note("the full-screen dismiss layer cannot swallow drawing input")
	var s: String = _source("res://scripts/main.gd")
	var start: int = s.find("_shade = Control.new()")
	not_null(start if start >= 0 else null, "shade setup exists")
	if start < 0:
		return
	var end: int = s.find("_ai_wait = AiWait.new()", start)
	var block: String = s.substr(start, end - start if end > start else 500)
	ok("MOUSE_FILTER_STOP" not in block, "shade still stops input")
	ok("MOUSE_FILTER_IGNORE" in block, "shade does not ignore input")

func _mainroom_dismisses_before_gui_routing() -> void:
	note("a press outside a panel closes it without consuming the same event")
	var s: String = _source("res://scripts/main.gd")
	var start: int = s.find("func _input(event: InputEvent) -> void:")
	not_null(start if start >= 0 else null, "MainRoom._input exists")
	if start < 0:
		return
	var end: int = s.find("\nfunc _process", start)
	var block: String = s.substr(start, end - start if end > start else 2000)
	ok("outside_panel" in block, "outside-panel routing state is missing")
	ok("get_global_rect().has_point" in block, "panel hit-test is missing")
	ok("_close_panel()" in block, "panel dismissal is missing from _input")

func _canvas_still_owns_canvas_events() -> void:
	note("touch and mouse events still enter CanvasView")
	var s: String = _source("res://scripts/canvas_view.gd")
	ok("func _gui_input(event: InputEvent) -> void:" in s,
		"CanvasView GUI input handler disappeared")
	ok("_handle_touch(event as InputEventScreenTouch)" in s,
		"touch events no longer enter CanvasView")
	ok("_begin_input(mb.position)" in s,
		"mouse press no longer starts canvas input")
	ok("_end_input(mb.position)" in s,
		"mouse release no longer ends canvas input")
