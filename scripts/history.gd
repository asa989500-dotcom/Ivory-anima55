class_name History
extends RefCounted
## One undo stack for everything the user can change.
##
## An entry is a list of steps, and a step is one of two things:
##
##   pixels       — tiles of one layer, as they were before
##   arrangement  — the whole layer order, folders and settings, as numbers
##
## Keeping both in one stack is what makes "delete a layer" and "draw a
## line" cost the same gesture to take back. Grouping steps into a single
## entry is what makes one user action take one tap to undo, even when it
## touched pixels and structure at once — merging two layers does both.
##
## Only the *before* state is stored. The *after* state is read from the
## live document at the moment of undoing, which halves what has to be kept
## and can never fall out of step with reality.

signal changed()
## Fires only for undo and redo, never for a fresh action, so the interface
## can say what was taken back without narrating ordinary drawing.
signal acted(label: String, undone: bool)

## Bytes of pixel data the stack may hold. Counted rather than counting
## entries, because deleting a layer is thousands of times heavier than a
## brush stroke and one number cannot fairly limit both.
## Per page, and every comic page keeps its own. Sixty-four megabytes of
## tiles is still dozens of brush strokes, and a project of twelve pages no
## longer reserves nearly two gigabytes it will never use.
const BUDGET: int = 64 * 1024 * 1024
const MIN_ENTRIES: int = 3

var stack: LayerStack = null

var _undo: Array = []
var _redo: Array = []
var _bytes: int = 0

func _init(layer_stack: LayerStack) -> void:
	stack = layer_stack

# ------------------------------------------------------------------ public

func can_undo() -> bool:
	return not _undo.is_empty()

func can_redo() -> bool:
	return not _redo.is_empty()

func label_of_undo() -> String:
	if _undo.is_empty():
		return ""
	return String(_undo[_undo.size() - 1]["label"])

## `steps` describe the state *before* the change that just happened.
func push(label: String, steps: Array) -> void:
	if steps.is_empty():
		return
	var entry: Dictionary = {
		"label": label,
		"steps": steps,
		"bytes": _weigh(steps),
	}
	_undo.append(entry)
	_bytes += int(entry["bytes"])
	_drop_redo()
	_trim()
	_release_unused()
	changed.emit()

## Convenience for the common case: one layer's tiles.
func push_pixels(label: String, layer_id: int, tiles: Dictionary) -> void:
	if tiles.is_empty():
		return
	push(label, [{"t": "pixels", "layer": layer_id, "tiles": tiles}])

func undo() -> void:
	if _undo.is_empty():
		return
	var entry: Dictionary = _undo.pop_back()
	_bytes -= int(entry["bytes"])
	var counter: Dictionary = _capture(entry)
	_apply(entry["steps"])
	_redo.append(counter)
	_release_unused()
	changed.emit()
	acted.emit(String(entry["label"]), true)

func redo() -> void:
	if _redo.is_empty():
		return
	var entry: Dictionary = _redo.pop_back()
	var counter: Dictionary = _capture(entry)
	_apply(entry["steps"])
	_undo.append(counter)
	_bytes += int(counter["bytes"])
	_trim()
	_release_unused()
	changed.emit()
	acted.emit(String(entry["label"]), false)

func clear() -> void:
	_undo.clear()
	_redo.clear()
	_bytes = 0
	_release_unused()
	changed.emit()

# ---------------------------------------------------------------- internals

## Structure first, always. Restoring pixels into a layer that undo has not
## brought back yet would quietly write them nowhere.
func _apply(steps: Array) -> void:
	for s in steps:
		if String(s["t"]) == "arrangement":
			stack.apply_arrangement(s["state"])
	# --- the comic page's frames ---
	#
	# Carried as an ordinary step rather than through a mechanism of its own,
	# so one press of undo takes back a cut exactly as it takes back a stroke.
	# Cutting a page and drawing on it are the same kind of act to the person
	# doing them, and two undo stacks — one that remembers strokes and another
	# that remembers cuts — is a promise that the wrong one will be emptied.
	#
	# The layout is stored as its dictionary rather than as the object,
	# because the object keeps being cut after this entry is pushed and a
	# reference would restore the panels as they are now.
	for s in steps:
		if String(s["t"]) == "frames":
			var owner: ProjectManager.Page = s["owner"]
			if owner != null:
				owner.frames = ComicPage.from_dict(s["state"])
	for s in steps:
		if String(s["t"]) != "pixels":
			continue
		var surface: PaintSurface = stack.surface_by_id(int(s["layer"]))
		if surface == null:
			continue
		var tiles: Dictionary = s["tiles"]
		for c in tiles.keys():
			surface.restore_tile(c, tiles[c])

## Reads today's state for exactly the things this entry will overwrite.
func _capture(entry: Dictionary) -> Dictionary:
	var out: Array = []
	for s in entry["steps"]:
		if String(s["t"]) == "arrangement":
			out.append({"t": "arrangement", "state": stack.capture_arrangement()})
			continue
		if String(s["t"]) == "frames":
			var owner: ProjectManager.Page = s["owner"]
			out.append({"t": "frames", "owner": owner,
				"state": {} if owner == null or owner.frames == null
					else owner.frames.to_dict()})
			continue
		var layer_id: int = int(s["layer"])
		var surface: PaintSurface = stack.surface_by_id(layer_id)
		var tiles: Dictionary = {}
		var source: Dictionary = s["tiles"]
		for c in source.keys():
			tiles[c] = null if surface == null else surface.snapshot_tile(c)
		out.append({"t": "pixels", "layer": layer_id, "tiles": tiles})
	return {"label": entry["label"], "steps": out, "bytes": _weigh(out)}

func _weigh(steps: Array) -> int:
	var total: int = 0
	for s in steps:
		if String(s["t"]) != "pixels":
			continue
		var tiles: Dictionary = s["tiles"]
		for c in tiles.keys():
			if tiles[c] != null:
				total += PaintSurface.TILE * PaintSurface.TILE * 4
	return total

func _trim() -> void:
	while _bytes > BUDGET and _undo.size() > MIN_ENTRIES:
		var gone: Dictionary = _undo.pop_front()
		_bytes -= int(gone["bytes"])

func _drop_redo() -> void:
	_redo.clear()

## Layers that only the history still remembers are kept alive off-stage.
## Once no entry mentions one any more, it can finally go.
func _release_unused() -> void:
	var keep: Dictionary = {}
	for entry in _undo:
		_collect_ids(entry, keep)
	for entry in _redo:
		_collect_ids(entry, keep)
	stack.purge_detached(keep)

func _collect_ids(entry: Dictionary, into: Dictionary) -> void:
	for s in entry["steps"]:
		if String(s["t"]) == "pixels":
			into[int(s["layer"])] = true
			continue
		var state: Dictionary = s["state"]
		for row in state["layers"]:
			into[int(row["id"])] = true
