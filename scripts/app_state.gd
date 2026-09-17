extends Node
## Single source of truth for tool selection, colour and brush settings.
## Autoloaded as `App`.

signal tool_changed(tool_id: int)
signal color_changed(color: Color)
signal fill_color_changed(color: Color)
## Raised by the fill panel so the shell can swap in the colour page.
signal open_fill_colour()

## Only ever emitted from here, so the emitter lives here too.
func request_fill_colour() -> void:
	open_fill_colour.emit()
signal brush_changed(index: int)
signal settings_changed()

enum Tool { BRUSH, FILL, SHAPE, ERASER, PICK, SELECT, MOVE, BLEND }

## How hard the line is pulled straight while drawing, nought to one.
## See `StrokeSmoother.strength` for what this actually does and what it costs.
var stabilizer: float = 0.0
enum Shape { FREE, LINE, RECT, SQUARE, ELLIPSE, DIAMOND, POLYLINE, CHAIN }
enum EraserShape { SOFT, HARD, SQUARE }
enum SelectShape { RECT, ELLIPSE, LASSO, POLY }

## What the bucket does: find an enclosed area, or lay down a solid shape.
enum FillShape { FLOOD, RECT, ELLIPSE, TRIANGLE, DIAMOND, STAR }

var library: BrushLibrary

var current_tool: int = Tool.BRUSH

## The brush and the fill bucket keep their own colours. They are different
## jobs — outlines in one hand, flats in the other — and sharing one swatch
## meant every fill quietly repainted the brush.
var ink: Color = Color("#101014")
var fill_ink: Color = Color("#c8443c")
var recent_colors: Array[Color] = []

## Which colour the eyedropper hands its result to.
var pick_into_fill: bool = false

var brush_index: int = 0
var brush_size: float = 8.0
var brush_opacity: float = 1.0

var eraser_size: float = 40.0
var eraser_opacity: float = 1.0
var eraser_shape: int = EraserShape.SOFT

var shape_mode: int = Shape.FREE
var select_shape: int = SelectShape.RECT
var fill_shape: int = FillShape.FLOOD
## How different a pixel may be from the one tapped and still be filled.
##
## It was a fixed number, and a fixed number is wrong for both ends of the
## work: a clean vector-ish drawing wants it low so the fill stops at the
## line, and a textured or heavily antialiased one wants it high or the
## colour dams up against its own soft edges. Now it is a dial.
# --- the colour blend tool ---
#
# Its own settings rather than the brush's, because they mean different
# things. A brush's opacity is how much ink lands; the blend tool lays no ink
# at all, and its strength is how far towards the answer one pass carries the
# colour that is already there. Sharing one number would make turning the
# brush up quietly change what the blend tool does.

## Which of the five ways of bringing two colours together. Matches
## `IvoryBlend.Mode`: mix, gradient, smudge, average, snap.
var blend_mode: int = 0
## How far one pass carries a pixel towards the answer, nought to one.
##
## Just under a half by default. At one a single dab replaces the colour under
## the middle of the stamp outright, which is a paint tool wearing a blend
## tool's name; at a tenth it takes ten passes to arrive, which is how a
## person actually blends but is slow to discover. A little under half arrives
## in two or three passes — enough to see it working on the first, and not so
## much that the first is the last word.
var blend_strength: float = 0.45
## The dab's diameter, in canvas pixels.
var blend_size: float = 40.0
## How much of what it passes over the brush carries with it, for the modes
## that carry anything. At one it forgets instantly and smudges nothing; at
## nought it carries the first colour the whole way, which is painting.
var blend_pickup: float = 0.55
## Whether a dab may change how opaque a pixel is. Off, and deliberately: a
## blend tool that quietly erases is a blend tool nobody trusts.
var blend_touch_alpha: bool = false
## Which brush shape the mixing takes. `-1` means the brush currently chosen,
## so picking up a chalk and switching to blend mixes through chalk's tooth
## without having to say so twice.
var blend_shape: int = -1

var fill_tolerance: int = 56
## How far the fill pushes under the edge of the linework it stops at.
##
## Anti-aliased strokes fade out over two or three pixels. A fill that stops
## exactly where it first meets one leaves a pale rim all the way round —
## the classic halo. Pushing under the edge removes it.
var fill_creep: int = 2

## Copied pixels, kept as a plain image so they can land on any layer.
var clipboard: Image = null
## The name of the layer they were taken from, so a paste that makes its own
## layer can call it something that means anything. Emptied with the picture.
var clip_from: String = ""

var tool_before_pick: int = Tool.BRUSH
## Set the first time a real finger is seen. Android also sends emulated
## mouse events for the same finger, and every widget must ignore those or
## each press is handled twice.
var touch_mode: bool = false
var symmetry_enabled: bool = false
var symmetry_count: int = 2
var symmetry_angle: float = 0.0
var pressure_enabled: bool = true
var ui_scale: float = 1.0

func _ready() -> void:
	# Before anything else: whatever the last run left on the device.
	#
	# The cel spill writes drawings that are far from the playhead out to
	# `user://cels`. A run that ends properly clears its own; a run that is
	# killed — the app swiped away, the battery gone, a crash — clears
	# nothing, and until now those files stayed there for ever. This is the
	# one place that is guaranteed to run once, before any track exists.
	var swept: int = CelTrack.sweep_orphans()
	if swept > 0:
		print("IVORY: cleared %d cel file(s) left by an earlier run" % swept)
	library = BrushLibrary.new()
	_sync_brush_defaults()
	recent_colors = [Color("#101014"), Color("#ffffff"), Color("#c8443c"),
		Color("#3f6fb5"), Color("#4e8f52"), Color("#d8b26a")]

## A clean exit takes this run's spilled cels with it.
##
## Belt as well as braces: the sweep in `_ready` is what actually guarantees
## the folder cannot grow, because Android kills applications without warning
## and nothing here runs when it does. This just means the ordinary case
## leaves the device tidy the moment the app closes rather than the next time
## it opens.
func _exit_tree() -> void:
	CelTrack.close_session()

func set_tool(t: int) -> void:
	if t == current_tool:
		return
	if t == Tool.PICK and current_tool != Tool.PICK:
		tool_before_pick = current_tool
	current_tool = t
	tool_changed.emit(t)

## Leaves the eyedropper and hands the canvas back to whatever was active.
func end_pick() -> void:
	if current_tool == Tool.PICK:
		set_tool(tool_before_pick)

func set_ink(c: Color) -> void:
	ink = c
	_push_recent(c)
	color_changed.emit(c)

func set_fill_ink(c: Color) -> void:
	fill_ink = c
	_push_recent(c)
	fill_color_changed.emit(c)

## The same, but without entering the colour in the recent row.
##
## For a finger still dragging the wheel. A single sweep across the ring
## passes through dozens of colours, and every one of them used to be filed
## as a choice — so twelve slots meant to hold the colours of the drawing
## filled up with the path a thumb took to reach one of them. Only the
## colour the finger settles on is a choice, and only that one is recorded.
func set_ink_live(c: Color) -> void:
	ink = c
	color_changed.emit(c)

func set_fill_ink_live(c: Color) -> void:
	fill_ink = c
	fill_color_changed.emit(c)

## Used by the eyedropper, which does not care which panel opened it.
func apply_picked(c: Color) -> void:
	if pick_into_fill:
		set_fill_ink(c)
	else:
		set_ink(c)

func set_brush(i: int) -> void:
	# Clamped, because the brush list grew from eight to forty and an index
	# kept from an older run would otherwise point at nothing.
	var want: int = clampi(i, 0, maxi(library.presets.size() - 1, 0))
	if want == brush_index:
		return
	brush_index = want
	_sync_brush_defaults()
	brush_changed.emit(want)
	settings_changed.emit()

func current_preset() -> BrushLibrary.Preset:
	return library.get_preset(brush_index)

func _sync_brush_defaults() -> void:
	var p: BrushLibrary.Preset = current_preset()
	if p != null:
		brush_size = p.default_size
		brush_opacity = p.default_opacity

func _push_recent(c: Color) -> void:
	for i in range(recent_colors.size() - 1, -1, -1):
		if recent_colors[i].is_equal_approx(c):
			recent_colors.remove_at(i)
	recent_colors.push_front(c)
	while recent_colors.size() > 12:
		recent_colors.pop_back()
