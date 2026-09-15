class_name StampPainter
extends Node2D
## Draws whatever is in `queue` once, then empties it.
## Lives inside a SubViewport whose clear mode is NEVER, so each draw
## accumulates on top of what is already there.

var queue: Array = []
var blits: Array = []
var sprites: Array = []


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

func add_stamp(local_pos: Vector2, dab_size: float, angle: float,
		col: Color, tex: Texture2D) -> void:
	queue.append({"p": local_pos, "s": dab_size, "a": angle, "c": col, "t": tex})

func add_blit(local_pos: Vector2, tex: Texture2D, col: Color = Color.WHITE) -> void:
	blits.append({"p": local_pos, "t": tex, "c": col})

## A texture placed with a full transform — used when a moved, scaled or
## rotated selection is stamped back down onto its layer.
func add_sprite(xform: Transform2D, tex: Texture2D, col: Color = Color.WHITE) -> void:
	sprites.append({"x": xform, "t": tex, "c": col})

func reset() -> void:
	queue.clear()
	blits.clear()
	sprites.clear()

func has_work() -> bool:
	return not queue.is_empty() or not blits.is_empty() or not sprites.is_empty()

func _draw() -> void:
	for b in blits:
		var bt: Texture2D = b["t"]
		if bt != null:
			draw_texture(bt, b["p"], b["c"])
	for sp in sprites:
		var stex: Texture2D = sp["t"]
		if stex != null:
			draw_set_transform_matrix(sp["x"])
			draw_texture(stex, Vector2.ZERO, sp["c"])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for st in queue:
		var tex: Texture2D = st["t"]
		if tex == null:
			continue
		var dab_size: float = st["s"]
		var half: float = dab_size * 0.5
		draw_set_transform(st["p"], st["a"], Vector2.ONE)
		draw_texture_rect(tex, Rect2(-half, -half, dab_size, dab_size), false, st["c"])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	queue.clear()
	blits.clear()
	sprites.clear()
