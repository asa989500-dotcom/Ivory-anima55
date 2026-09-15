extends "res://tests/test_case.gd"

func title() -> String:
	return "brush regression"

func run() -> void:
	var canvas: String = FileAccess.get_file_as_string("res://scripts/canvas_view.gd")
	var panel: String = FileAccess.get_file_as_string("res://scripts/ui/tool_panels.gd")
	note("the brush remains reachable on rigged layers")
	ok("if BoneHandle.grab(self, screen):" in canvas, "joint hit test remains first")
	ok("if App.current_tool == App.Tool.MOVE:" in canvas, "move tool remains isolated")
	ok("w = _brush_safe_point(w)" in canvas, "brush boundary guard exists")
	ok("not motion_layer.rig.is_empty():" in canvas, "rigged-layer branch exists")
	var rig_block_start: int = canvas.find("if motion_layer != null and not motion_layer.rig.is_empty():")
	var brush_start: int = canvas.find("if not _brush_layer_allowed():", rig_block_start)
	ok(rig_block_start >= 0 and brush_start > rig_block_start,
		"rigged layers continue to the brush gate")
	note("the removed colour distortion option is absent from the tool panel")
	ok("UiKit.label_for(\"Smudge\", \"تلطيخ\")" not in panel,
		"smudge button is removed")
	ok("[2, UiKit.label_for(\"Smudge\"" not in panel,
		"smudge mode row is removed")
