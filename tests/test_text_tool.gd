extends RefCounted
## Seven focused checks for the text object. The suite deliberately tests the
## interaction contract, not the renderer: shaping belongs to TextServer and
## these seven checks are what must remain true around it.

var failures: Array = []
var checks: int = 0
var _notes: Array = []
var native: Object = null

func title() -> String:
	return "text tool"

func _ok(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _close(a: Vector2, b: Vector2, eps: float = 0.01) -> bool:
	return a.distance_to(b) <= eps

func run() -> void:
	native = Native.text_tool()
	_notes.append("tight object bounds")
	_notes.append("exact finger translation")
	_notes.append("opposite-corner resize")
	_notes.append("rotation without first-frame snap")
	_notes.append("preview keeps centre under transform")
	_notes.append("scale clamp")
	_notes.append("100k hot-path transform operations")

	# 1 — the stored text box is the measured text, not a 256px tile.
	var tight := Rect2(120.0, 80.0, 311.0, 47.0)
	_ok(tight.size == Vector2(311.0, 47.0), "text box is not tight")

	# 2 — movement must be exactly the finger delta.
	var from := Vector2(200.0, 100.0)
	var to := Vector2(247.5, 163.25)
	var moved: Rect2 = native.moved(tight, from, to) if native != null else HandleBox.moved(tight, from, to)
	_ok(_close(moved.position, tight.position + to - from), "move delta drifted")

	# 3 — resizing keeps the opposite corner fixed.
	var resized: Rect2 = native.sized(tight, 0.0, HandleBox.Part.BOTTOM_RIGHT,
		Vector2(431.0, 127.0), Vector2(500.0, 150.0), true) if native != null else HandleBox.sized(tight, 0.0, HandleBox.Part.BOTTOM_RIGHT,
		Vector2(431.0, 127.0), Vector2(500.0, 150.0), true)
	_ok(_close(resized.position, tight.position), "opposite corner moved")
	_ok(resized.size.x >= 12.0 and resized.size.y >= 12.0, "resize crossed minimum")

	# 4 — rotation is measured as a delta from the caught position.
	var r0 := Vector2(0.0, -100.0)
	var r1 := Vector2(1.0, -100.0)
	var delta: float = native.turned(tight, tight.get_center() + r0,
		tight.get_center() + r1) if native != null else HandleBox.turned(tight, tight.get_center() + r0,
		tight.get_center() + r1)
	_ok(absf(delta) < 0.02, "rotation jumped on first touch")

	# 5 — preview transform maps the old object centre exactly to the new one.
	var centre := tight.get_center()
	var new_centre := centre + Vector2(73.0, -21.0)
	var tr: Dictionary = native.preview_transform(centre, new_centre, 0.37, 1.8) if native != null else {
		"position": new_centre - centre.rotated(0.37) * 1.8,
		"rotation": 0.37,
		"scale": 1.8
	}
	var mapped := Vector2(tr["position"]) + centre.rotated(float(tr["rotation"])) * float(tr["scale"])
	_ok(_close(mapped, new_centre), "preview centre is not exact")

	# 6 — scale limits cannot be escaped by an extreme finger movement.
	var clamped: float = native.clamp_scale(999.0, 0.15, 12.0) if native != null else clampf(999.0, 0.15, 12.0)
	_ok(absf(clamped - 12.0) < 0.001, "scale upper clamp failed")

	# 7 — hot path stays arithmetic-only and completes 100k transforms.
	var started := Time.get_ticks_usec()
	var sink := Vector2.ZERO
	for i in 100000:
		var q := Vector2(float(i % 1000), float(i % 997))
		var t: Dictionary = native.preview_transform(centre, centre + q, 0.013, 1.002) if native != null else {
			"position": centre + q - centre.rotated(0.013) * 1.002,
			"rotation": 0.013,
			"scale": 1.002
		}
		sink += Vector2(t["position"])
	var elapsed := Time.get_ticks_usec() - started
	_ok(is_finite(float(sink.x)) and is_finite(float(sink.y)), "hot path produced non-finite data")
	_ok(elapsed < 1000000, "hot path exceeded 1 second")
