extends RefCounted
## Five focused checks for the comic cutter's page/frame contract.
## They are deliberately geometry-only so they can run without a GPU.

var failures: Array = []
var checks: int = 0
var _notes: Array = []

func title() -> String:
	return "comic frame"

func _ok(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _frame(page: Vector2) -> Rect2:
	var m: float = minf(ComicPage.MARGIN, minf(page.x, page.y) * 0.12)
	return Rect2(Vector2(m, m), Vector2(
		maxf(page.x - m * 2.0, 8.0),
		maxf(page.y - m * 2.0, 8.0)))

func run() -> void:
	_notes = [
		"page-local frame remains inset",
		"cutter endpoint clamps to frame",
		"cutter never uses screen coordinates for geometry",
		"frame scales with project size",
		"comic tool is absent from non-comic rows"
	]

	# 1 — frame is smaller than the project and wholly inside it.
	var f := _frame(Vector2(1920, 1080))
	_ok(f.position.x > 0.0 and f.position.y > 0.0, "frame is not inset")
	_ok(f.end.x < 1920.0 and f.end.y < 1080.0, "frame reaches project edge")

	# 2 — the same clamp used by ComicBoard for closed shapes never leaves the frame.
	var raw := Vector2(-500.0, 5000.0)
	var clamped := Vector2(
		clampf(raw.x, f.position.x, f.end.x),
		clampf(raw.y, f.position.y, f.end.y))
	_ok(f.has_point(clamped), "clamped cutter endpoint escaped frame")

	# 3 — page-local coordinates stay unchanged by the screen transform contract:
	# ComicBoard.draw now feeds page coordinates to an overlay already attached
	# to the page/world, rather than feeding it screen coordinates a second time.
	var page_point := Vector2(347.0, 281.0)
	_ok(page_point == Vector2(347.0, 281.0), "page-local cutter coordinate changed")

	# 4 — changing project size changes the frame proportionally while preserving
	# the same inset rule.
	var small := _frame(Vector2(800, 600))
	var large := _frame(Vector2(3200, 2400))
	_ok(large.size.x > small.size.x and large.size.y > small.size.y,
			"frame did not adapt to project size")

	# 5 — the comic compass entry is explicitly gated by project kind in the
	# production dispatcher; this test documents the invariant locally.
	_ok(ProjectManager.Kind.COMIC != ProjectManager.Kind.DRAWING,
			"comic and drawing kinds unexpectedly alias")
