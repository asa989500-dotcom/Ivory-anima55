extends SceneTree
## Runs every test case, inside a real Godot.
##
## This is the thing the project did not have. The four checkers in `tools/`
## read the text of the files: they catch a name left behind after a deletion,
## a return of the wrong kind of nothing, a wrapped line that became two
## statements. Not one of them can catch a line that parses perfectly and says
## the wrong thing — and the first run of this suite found exactly that in the
## fill bucket, where one line sat outside its `else` and the tool had not
## filled anything for several builds.
##
## Run it:
##
##     godot --headless --path . --script tests/run_tests.gd
##
## Exit code 0 if everything passed, 1 if anything did not, so it can be put
## in front of a build and mean something. `tools/build.sh` does that.
##
## No graphics are touched. Everything here is `Image`, `RefCounted` and
## files — which is deliberate: a suite that needs a screen is a suite that
## stops being run.

const CASES: Array = [
	"res://tests/test_cel_track.gd",
	"res://tests/test_perf.gd",
	"res://tests/test_image_import.gd",
	"res://tests/test_anim.gd",
	"res://tests/test_flood_fill.gd",
	"res://tests/test_ai.gd",
	"res://tests/test_lang.gd",
	"res://tests/test_bone_rig.gd",
	"res://tests/test_warp_mesh.gd",
	"res://tests/test_bone_solver.gd",
	"res://tests/test_spline_anchor.gd",
	"res://tests/test_comic_frame.gd",
	"res://tests/test_text_tool.gd",
	# Stage 153. The comic frames were drawn one page origin away from the page
	# and the paint confinement asked about a point one page origin away from
	# the finger. Both offsets are zero on page one of a project at the
	# workspace origin, so this case works on neither.
	"res://tests/test_comic_frames.gd",
	# The gate that decides whether a layer may be drawn on is asked in two
	# places, and a build shipped in which they disagreed — the brush was
	# offered and then swallowed every stroke.
	"res://tests/test_drawing_gates.gd",
	"res://tests/test_input_routing.gd",
	# The puppet warp's fold-over guard used to reset the whole mesh to its
	# rest pose the moment a hard drag made even the guard's own starting
	# point invalid — visible as the drawing snapping back mid-drag instead
	# of holding still at the deformation limit.
	"res://tests/test_puppet_warp_foldover.gd",
]

func _initialize() -> void:
	var started: int = Time.get_ticks_msec()
	var failed: int = 0
	var checks: int = 0
	var broken: Array = []

	print("")
	print("IVORY — running the tests")
	print("")

	for path in CASES:
		var script: GDScript = load(path)
		if script == null:
			print("  !! could not load %s" % path)
			failed += 1
			continue
		var case: Object = script.new()
		var label: String = case.call("title")
		var spent: int = Time.get_ticks_msec()
		case.call("run")
		spent = Time.get_ticks_msec() - spent

		var failures: Array = case.get("failures")
		var ran: int = int(case.get("checks"))
		checks += ran
		if failures.is_empty():
			print("  ok    %-22s %4d checks   %5d ms" % [label, ran, spent])
		else:
			failed += failures.size()
			print("  FAIL  %-22s %4d checks   %5d ms" % [label, ran, spent])
			for one in failures:
				print("          %s" % String(one))
				broken.append("%s: %s" % [label, String(one)])
		# What the case was checking, printed under it so a passing run still
		# says what it proved rather than only that it passed.
		for line in (case.get("_notes") as Array):
			print("          · %s" % String(line))

	print("")
	print("%d checks in %d ms" % [checks, Time.get_ticks_msec() - started])
	if failed == 0:
		print("everything passed.")
	else:
		print("%d FAILED:" % failed)
		for one in broken:
			print("  %s" % String(one))
	print("")
	quit(0 if failed == 0 else 1)
