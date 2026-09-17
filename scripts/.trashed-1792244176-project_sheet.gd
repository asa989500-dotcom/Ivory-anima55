class_name ProjectSheet
extends Node2D
## One page of paper.
##
## `clip_children` uses whatever this node draws as a stencil for everything
## beneath it, so filling the page rectangle here both paints the paper and
## keeps strokes from spilling off its edge. One node, both jobs, and the
## edge stays exact at every zoom because the clip happens per pixel rather
## than per tile.
##
## There is one of these per page, not per project, which is what lets a
## comic page own its own drawing rather than share one long canvas with
## the pages beside it.

var page_size: Vector2 = Vector2(1600.0, 1200.0)
var paper: Color = Color("#ffffff")
var grid_guide: bool = false

func _ready() -> void:
	set_clipping(false)

## Clipping forces the renderer to copy the framebuffer for this node, which
## on a phone is among the most expensive things a 2D scene can ask for.
## Only a page being painted on can gain pixels past its edge, so only that
## one pays; the rest are trimmed once when the project closes.
func set_clipping(on: bool) -> void:
	clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW if on \
		else CanvasItem.CLIP_CHILDREN_DISABLED

func _draw() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, page_size)
	draw_rect(r, paper, true)
	if grid_guide:
		_guide(r)

## Graph paper, drawn before the layers so it sits under the ink and never
## competes with it. Part of the sheet, not of the artwork — no exporter
## ever sees it.
func _guide(r: Rect2) -> void:
	var step: float = maxf(minf(r.size.x, r.size.y) / 16.0, 24.0)
	var ink: Color = Color(0.0, 0.0, 0.0, 0.055)
	if paper.get_luminance() < 0.45:
		ink = Color(1.0, 1.0, 1.0, 0.075)
	var x: float = step
	while x < r.size.x:
		draw_line(Vector2(x, 0.0), Vector2(x, r.size.y), ink, 1.0)
		x += step
	var y: float = step
	while y < r.size.y:
		draw_line(Vector2(0.0, y), Vector2(r.size.x, y), ink, 1.0)
		y += step
