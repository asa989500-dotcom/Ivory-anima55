class_name ShapeGeometry
extends RefCounted
## Live geometry correction for touch-drawn canonical shapes.

static func corrected_endpoint(mode: int, a: Vector2, b: Vector2) -> Vector2:
	var d: Vector2 = b - a
	if d.length() < 0.5:
		return b
	match mode:
		App.Shape.SQUARE:
			var square_side: float = maxf(absf(d.x), absf(d.y))
			return a + Vector2(signf(d.x) * square_side, signf(d.y) * square_side)
		App.Shape.RECT:
			var rect_ax: float = absf(d.x)
			var rect_ay: float = absf(d.y)
			var rect_long_side: float = maxf(rect_ax, rect_ay)
			var rect_short_side: float = minf(rect_ax, rect_ay)
			if rect_long_side > 0.0 and rect_short_side / rect_long_side >= 0.82:
				return a + Vector2(signf(d.x) * rect_long_side, signf(d.y) * rect_long_side)
			return b
		App.Shape.ELLIPSE:
			var ellipse_ax: float = absf(d.x)
			var ellipse_ay: float = absf(d.y)
			var ellipse_long_side: float = maxf(ellipse_ax, ellipse_ay)
			var ellipse_short_side: float = minf(ellipse_ax, ellipse_ay)
			if ellipse_long_side > 0.0 and ellipse_short_side / ellipse_long_side >= 0.88:
				return a + Vector2(signf(d.x) * ellipse_long_side, signf(d.y) * ellipse_long_side)
			return b
		App.Shape.DIAMOND:
			var diamond_side: float = maxf(absf(d.x), absf(d.y))
			return a + Vector2(signf(d.x) * diamond_side, signf(d.y) * diamond_side)
		App.Shape.LINE:
			var angle: float = d.angle()
			# Fifteen-degree increments keep straight lines clean without forcing
			# every free line to horizontal, vertical, or forty-five degrees.
			var step: float = PI / 12.0
			angle = round(angle / step) * step
			return a + Vector2.from_angle(angle) * d.length()
	return b
