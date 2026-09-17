class_name BrushPreview
extends Control
## Shows the selected brush as an actual stroke, not a swatch — the same
## S curve every time, so two brushes can be compared at a glance.

var preset_index: int = 0

func _ready() -> void:
	custom_minimum_size = Vector2(UiKit.s(210.0), UiKit.s(58.0))
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func refresh(i: int) -> void:
	preset_index = i
	queue_redraw()

func _draw() -> void:
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = Color("#ffffff")
	bg.set_corner_radius_all(int(UiKit.s(8.0)))
	draw_style_box(bg, Rect2(Vector2.ZERO, size))

	var p: BrushLibrary.Preset = App.library.get_preset(preset_index)
	if p == null or size.x <= 1.0:
		return

	var pts: PackedVector2Array = PackedVector2Array()
	var n: int = 40
	for i in range(n + 1):
		var t: float = float(i) / float(n)
		pts.append(Vector2(
			lerpf(size.x * 0.08, size.x * 0.92, t),
			size.y * 0.5 + sin(t * PI * 1.6) * size.y * 0.24))

	var stamp_size: float = clampf(App.brush_size, 3.0, size.y * 0.8)
	var col: Color = App.ink
	col.a = App.brush_opacity
	var spacing: float = maxf(stamp_size * p.spacing, 1.0)

	var carry: float = 0.0
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg: float = a.distance_to(b)
		if seg <= 0.001:
			continue
		var dir: Vector2 = (b - a) / seg
		var facing: float = dir.angle()
		var sample_t: float = -carry
		var guard: int = 0
		while sample_t + spacing <= seg and guard < 512:
			sample_t += spacing
			var pos: Vector2 = a + dir * sample_t
			var sz: float = stamp_size
			var ang: float = 0.0
			if p.follow_direction:
				ang = facing
			if p.angle_jitter > 0.0:
				ang += randf_range(-p.angle_jitter, p.angle_jitter)
			if p.size_jitter > 0.0:
				sz *= 1.0 + randf_range(-p.size_jitter, p.size_jitter)
			if p.scatter > 0.0:
				var r: float = stamp_size * p.scatter
				pos += Vector2(randf_range(-r, r), randf_range(-r, r))
			draw_set_transform(pos, ang, Vector2.ONE)
			draw_texture_rect(App.library.standard_texture(p),
				Rect2(-sz * 0.5, -sz * 0.5, sz, sz), false, col)
			guard += 1
		carry = seg - sample_t
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
