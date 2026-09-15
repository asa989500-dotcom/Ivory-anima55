class_name PaintSurface
extends Node2D
## One raster layer, unbounded, made of 512px tiles.
##
## Three ideas keep it light no matter how far you draw or how far you zoom:
##
##   1. A tile's real pixels live in an Image on the CPU and are shown through
##      an ordinary texture. A SubViewport is only borrowed while the tile is
##      being painted. Mobile GPUs may discard a render target whenever they
##      like, so nothing valuable is ever left in one.
##   2. Tiles far from the view fall asleep: their pixels are squeezed into a
##      PNG buffer and the textures are handed back. An empty-ish tile shrinks
##      from a megabyte to a few kilobytes, so the canvas can keep growing.
##   3. A sleeping tile still shows something: a small proxy stands in until
##      the real pixels are back. Awake tiles always draw at full resolution
##      with mipmaps, so zooming never trades quality for speed.
##
## Pixels here are PREMULTIPLIED: a colour is already scaled by its own
## alpha. That is not a stylistic choice. A tile is rebuilt on the GPU from
## its stored copy and read back again after every stroke, and ordinary
## alpha blending onto an empty target multiplies colour by alpha on each
## trip — so a colour laid down once would creep towards black as later
## strokes forced more trips. Premultiplied blending makes the trip an exact
## round-trip instead, and a green stays that same green no matter how much
## is drawn beside it afterwards.
##
## The conversion back to ordinary colour happens only where something
## outside this file reads a pixel, and every one of those places is
## marked.

const TILE: int = 512
const PROXY: int = 128
## Mipmaps are what let a full-resolution tile be drawn small without
## sparkling, which is what makes the proxy unnecessary while awake. They
## are rebuilt when a stroke settles, not on every dab — regenerating them
## mid-stroke would cost more than it saves.
const KEEP_MARGIN: float = 1.6    # screens of slack before a tile sleeps
## Only sleeping is rationed. Waking is not: a tile the user can see has to
## be right this frame, and a budget there is exactly what produced the
## blur-then-sharpen the eye keeps catching.
const SLEEP_BUDGET: int = 2
const MEMORY_TILE_HARD_CAP: int = 720
const MEMORY_SCAN_INTERVAL: int = 24
var _memory_scan_clock: int = 0

## Tiles are shared across every layer, so one busy layer cannot starve
## the others.
static var live_tiles: int = 0
static var max_tiles: int = 600

var tile_limit_reached: bool = false

var _tiles: Dictionary = {}
var _dirty: Dictionary = {}
var _erase_material: ShaderMaterial = null
var _premul_material: CanvasItemMaterial = null

## Where the tiles hang while the layer is being blurred.
##
## A layer is not one picture — it is a grid of tiles, each its own sprite. Put
## a blur on each of them and every tile edge becomes a seam, because a blur
## needs to read the pixels next to it and a tile has none: past its edge is
## another node entirely. A CanvasGroup composites its children into a single
## image first, so the blur reads across tile boundaries as if they were never
## there.
##
## It costs a render target, so it only exists while a layer is actually soft.
## A project not using depth of field never makes one.
var _lens: CanvasGroup = null

## Whether this layer adds its light to what is under it.
var glowing: bool = false
var _glow_material: CanvasItemMaterial = null

func _ready() -> void:
	_erase_material = ShaderMaterial.new()
	_erase_material.shader = load("res://shaders/erase.gdshader")
	_premul_material = premultiplied_material()
	_glow_material = additive_material()

## Shared by everything that shows or composites already-premultiplied
## pixels: tile sprites, the plate that rebuilds a tile, layer thumbnails,
## and the selection floating over the canvas.
static func premultiplied_material() -> CanvasItemMaterial:
	var m: CanvasItemMaterial = CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	return m

## A layer that adds its light to whatever is under it instead of covering
## it.
##
## This is the difference between a painting of a glow and a glow. Normally a
## layer replaces what is beneath in proportion to its alpha, so a soft halo
## over a dark background comes out as a pale grey film sitting on top of it —
## the halo hides the drawing rather than lighting it. Added, the halo only
## ever makes what is under it brighter, and never dims anything: a lamp drawn
## over a night scene lifts the roofs it falls on and leaves the sky alone,
## because adding nothing to black leaves black.
##
## It is also why light needs no eraser of its own. The pixels are ordinary
## pixels — taking them away takes the light away with them.
static func additive_material() -> CanvasItemMaterial:
	var m: CanvasItemMaterial = CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m

## Premultiplied colour back to an ordinary one.
static func to_straight(c: Color) -> Color:
	if c.a <= 0.0001:
		return Color(0.0, 0.0, 0.0, 0.0)
	return Color(c.r / c.a, c.g / c.a, c.b / c.a, c.a)

## Not _exit_tree: a layer waiting in the history is out of the scene tree
## but still owns its tiles, and quietly discounting them there would let
## the budget drift until the real cap was several times what it says.
func dispose() -> void:
	live_tiles = maxi(live_tiles - _tiles.size(), 0)
	_tiles.clear()
	_dirty.clear()
	queue_free()

## Squeezes every tile down and hands back all its GPU memory. Used when a
## layer steps off-stage into the history, where it may sit for a long time.
func sleep_all() -> void:
	for c in _tiles.keys():
		var t: Dictionary = _tiles[c]
		if t["vp"] != null:
			if int(t["rendered"]) > 0:
				_fold(t)
			_release_scratch(t)
		(t["pending"] as Array).clear()
		t["rendered"] = 0
		_sleep(t)
	_dirty.clear()

# ------------------------------------------------------------------- tiles

func tile_coord(world: Vector2) -> Vector2i:
	return Vector2i(int(floor(world.x / float(TILE))), int(floor(world.y / float(TILE))))

func tile_origin(c: Vector2i) -> Vector2:
	return Vector2(float(c.x * TILE), float(c.y * TILE))

func has_tile(c: Vector2i) -> bool:
	return _tiles.has(c)

func get_tile_coords() -> Array:
	return _tiles.keys()

func tile_count() -> int:
	return _tiles.size()

func _make_tile(c: Vector2i) -> Dictionary:
	if _tiles.has(c):
		return _tiles[c]
	if live_tiles >= max_tiles:
		tile_limit_reached = true
		return {}

	var root: Node2D = Node2D.new()
	root.name = "Tile_%d_%d" % [c.x, c.y]
	root.position = tile_origin(c)
	if _lens != null:
		_lens.add_child(root)
	else:
		add_child(root)

	var mirror: Image = Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	mirror.fill(Color(0.0, 0.0, 0.0, 0.0))

	var sprite: Sprite2D = Sprite2D.new()
	sprite.centered = false
	# Mipmapped: shrinking a tile has to stay clean, because the whole point
	# of dropping the proxy is that zooming out no longer costs sharpness.
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.material = _glow_material if glowing else _premul_material
	root.add_child(sprite)

	var t: Dictionary = {
		"root": root,
		"sprite": sprite,
		"mirror": mirror,
		"mirror_tex": ImageTexture.create_from_image(mirror),
		"proxy_tex": null,
		"packed": PackedByteArray(),
		"asleep": false,
		"pending": [],      # stamp dictionaries, in draw order
		"rendered": 0,      # how many of them the last finished frame drew
		"vp": null,
		"plate": null,
		"base": null,
		"erase": null,
	}
	_tiles[c] = t
	live_tiles += 1
	_apply_lod(t)
	return t

# ----------------------------------------------------------- sleep and wake

## Timed, because `Perf.wake_budget` is now built out of what this costs
## rather than out of a guess about what it might cost. The clock is two
## integer reads either side of work that is already measured in
## milliseconds; it does not show up in a profile of the profiler.
func _ensure_awake(t: Dictionary) -> void:
	if not bool(t["asleep"]):
		return
	var started: int = Time.get_ticks_usec()
	var mirror: Image = Image.new()
	var packed: PackedByteArray = t["packed"]
	if packed.size() > 0 and mirror.load_png_from_buffer(packed) == OK:
		if mirror.get_format() != Image.FORMAT_RGBA8:
			mirror.convert(Image.FORMAT_RGBA8)
	else:
		mirror = Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
		mirror.fill(Color(0.0, 0.0, 0.0, 0.0))
	t["mirror"] = mirror
	t["mirror_tex"] = ImageTexture.create_from_image(mirror)
	t["packed"] = PackedByteArray()
	t["asleep"] = false
	_apply_lod(t)
	Perf.since("wake", started)

func _sleep(t: Dictionary) -> void:
	if bool(t["asleep"]) or t["vp"] != null:
		return
	var mirror: Image = t["mirror"]
	if mirror == null:
		return
	_build_proxy(t)   # the only moment the proxy is ever looked at
	t["packed"] = mirror.save_png_to_buffer()
	t["mirror"] = null
	t["mirror_tex"] = null
	t["asleep"] = true
	_apply_lod(t)

func _build_proxy(t: Dictionary) -> void:
	var mirror: Image = t["mirror"]
	if mirror == null:
		return
	var small: Image = Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	small.copy_from(mirror)
	var how: int = Image.INTERPOLATE_LANCZOS
	if Perf.tier != Perf.Tier.HIGH:
		how = Image.INTERPOLATE_BILINEAR
	small.resize(PROXY, PROXY, how)
	var tex: ImageTexture = t["proxy_tex"]
	if tex == null:
		t["proxy_tex"] = ImageTexture.create_from_image(small)
	else:
		tex.update(small)

## Which texture the tile shows. Full resolution whenever it is available —
## the proxy is a stand-in for sleep, not a saving to be made while awake.
func _apply_lod(t: Dictionary) -> void:
	var sprite: Sprite2D = t["sprite"]
	if t["vp"] != null:
		sprite.texture = (t["vp"] as SubViewport).get_texture()
		sprite.scale = Vector2.ONE
		return
	var full: ImageTexture = t["mirror_tex"]
	if full != null:
		sprite.texture = full
		sprite.scale = Vector2.ONE
		return
	var proxy: ImageTexture = t["proxy_tex"]
	if proxy != null:
		sprite.texture = proxy
		sprite.scale = Vector2(float(TILE) / float(PROXY), float(TILE) / float(PROXY))
	else:
		sprite.texture = null

## Called every frame with what the user can actually see.
func update_view(view_world: Rect2, _zoom: float) -> void:
	# Visibility is also our memory policy. Tiles outside the working ring are
	# compressed and their GPU texture is released; visible tiles are restored
	# lazily. This keeps long timelines from making every frame resident RGBA.
	var keep: Rect2 = view_world.grow(maxf(view_world.size.x, view_world.size.y) * KEEP_MARGIN)
	var budget: int = SLEEP_BUDGET
	var waking: int = Perf.wake_budget()
	_memory_scan_clock += 1
	for c in _tiles.keys():
		var t: Dictionary = _tiles[c]
		var box: Rect2 = Rect2(tile_origin(c), Vector2(float(TILE), float(TILE)))
		var root: Node2D = t["root"]
		if view_world.intersects(box):
			root.visible = true
			if bool(t["asleep"]) and waking > 0:
				_ensure_awake(t)
				waking -= 1
			continue
		root.visible = false
		if keep.intersects(box):
			continue
		if budget > 0 and not bool(t["asleep"]) and (t["pending"] as Array).is_empty():
			_sleep(t)
			budget -= 1

	# Under unusual tile counts, perform a conservative second pass. Never
	# reclaim visible tiles or tiles involved in an active stroke.
	if _memory_scan_clock >= MEMORY_SCAN_INTERVAL and _tiles.size() > MEMORY_TILE_HARD_CAP:
		_memory_scan_clock = 0
		for c in _tiles.keys():
			if _tiles.size() <= MEMORY_TILE_HARD_CAP:
				break
			var t: Dictionary = _tiles[c]
			var box: Rect2 = Rect2(tile_origin(c), Vector2(float(TILE), float(TILE)))
			if view_world.intersects(box) or bool(t["asleep"]) or not (t["pending"] as Array).is_empty():
				continue
			_sleep(t)

# ------------------------------------------------------- scratch (painting)

func _attach_scratch(t: Dictionary) -> void:
	if t["vp"] != null:
		return
	_ensure_awake(t)
	var root: Node2D = t["root"]

	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(TILE, TILE)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.gui_disable_input = true
	vp.handle_input_locally = false
	# Cleared and rebuilt from the mirror every frame: nothing to lose.
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(vp)

	# The plate lays the tile's stored pixels down again. It blends
	# premultiplied, which is what makes that an exact copy rather than a
	# slightly darker one.
	var plate: StampPainter = StampPainter.new()
	plate.name = "Plate"
	plate.material = _premul_material
	vp.add_child(plate)

	# New marks blend the ordinary way. Over a premultiplied destination
	# that is already the right sum, so nothing special is needed here.
	var base: StampPainter = StampPainter.new()
	base.name = "Base"
	vp.add_child(base)

	var erase: StampPainter = StampPainter.new()
	erase.name = "Erase"
	erase.material = _erase_material
	vp.add_child(erase)          # last, so erasing wins within a frame

	t["vp"] = vp
	t["plate"] = plate
	t["base"] = base
	t["erase"] = erase
	_apply_lod(t)

func _release_scratch(t: Dictionary) -> void:
	if t["vp"] == null:
		return
	var vp: SubViewport = t["vp"]
	t["vp"] = null
	t["plate"] = null
	t["base"] = null
	t["erase"] = null
	_apply_lod(t)
	vp.queue_free()

# ---------------------------------------------------------------- painting

## --- the panel gate ---
##
## When a comic frame is chosen and confinement is on, a dab outside it is
## refused. Set by `CanvasView` at the start of a stroke and cleared at the
## end; null means no confinement, which is every project that is not a comic
## and every comic page with nothing chosen.
##
## ## Why the gate is here and not in the brush
##
## Because `stamp` is the one place in the app where paint is committed.
## Brushes, shapes, the smudge tool, the fill's edges, the spline stroker,
## every one of them ends up on this line. A gate anywhere else is a gate on
## one route into a building with six doors, and the request was explicit
## about wanting this bound firmly — so it is bound at the choke point rather
## than at each caller, where a tool added next year would quietly bypass it.
##
## ## Why it is a callable and not a rectangle
##
## A frame is a polygon. A rectangle would be wrong for every diagonal cut,
## and passing the polygon itself would mean this file knowing what a comic
## page is. It knows how to ask a question instead.
var confine_to: Callable = Callable()

## Places one dab in world space, writing it into every tile it overlaps,
## so marks that straddle a tile border stay seamless.
func stamp(world_pos: Vector2, dab_size: float, angle: float, col: Color,
		tex: Texture2D, erase: bool = false) -> void:
	# Asked per dab rather than per stroke. A stroke that starts inside a
	# frame and is dragged out of it must stop at the border — checking once
	# at the start would let the whole rest of the stroke through, which is
	# the behaviour somebody would report as the feature not working.
	#
	# Erasing is deliberately gated too. An eraser is a brush that paints
	# nothing, and letting it through would mean the one tool that can reach
	# into a neighbouring frame is the one that destroys what is there.
	if confine_to.is_valid() and not bool(confine_to.call(world_pos)):
		return
	var reach: float = dab_size * 0.75 + 2.0
	var c0: Vector2i = tile_coord(world_pos - Vector2(reach, reach))
	var c1: Vector2i = tile_coord(world_pos + Vector2(reach, reach))
	for ty in range(c0.y, c1.y + 1):
		for tx in range(c0.x, c1.x + 1):
			var c: Vector2i = Vector2i(tx, ty)
			var t: Dictionary = _make_tile(c)
			if t.is_empty():
				continue
			_ensure_awake(t)
			(t["pending"] as Array).append({
				"k": "dab",
				"p": world_pos - tile_origin(c),
				"s": dab_size,
				"a": angle,
				"c": col,
				"t": tex,
				"e": erase,
			})
			_dirty[c] = true

## Draws a finished image straight into the mirrors. Used by the fill tool.
## `replace` writes the pixels straight in instead of blending them over
## what is there — which is what reloading a saved layer needs, so a file
## round trip returns exactly what was written.
func blit_image(img: Image, world_origin: Vector2, replace: bool = false) -> void:
	if img == null or img.get_width() <= 0 or img.get_height() <= 0:
		return
	var rect: Rect2i = Rect2i(Vector2i(world_origin),
		Vector2i(img.get_width(), img.get_height()))
	var c0: Vector2i = tile_coord(Vector2(rect.position))
	var c1: Vector2i = tile_coord(Vector2(rect.position + rect.size))
	for ty in range(c0.y, c1.y + 1):
		for tx in range(c0.x, c1.x + 1):
			var c: Vector2i = Vector2i(tx, ty)
			var t: Dictionary = _make_tile(c)
			if t.is_empty():
				continue
			_ensure_awake(t)
			var org: Vector2i = Vector2i(tile_origin(c))
			var overlap: Rect2i = Rect2i(org, Vector2i(TILE, TILE)).intersection(rect)
			if overlap.size.x <= 0 or overlap.size.y <= 0:
				continue
			# `img` carries ordinary alpha on purpose. blend_rect computes
			# src*srcA + dst*(1-srcA), and with an ordinary source that is
			# exactly the premultiplied result this canvas wants.
			var mirror: Image = t["mirror"]
			var src: Rect2i = Rect2i(overlap.position - rect.position, overlap.size)
			var at: Vector2i = overlap.position - org
			if replace:
				mirror.blit_rect(img, src, at)
			else:
				mirror.blend_rect(img, src, at)
			_refresh(t)

## Only the texture the screen is reading. The proxy is built when a tile
## goes to sleep and at no other time — rebuilding it on every dab meant a
## full 512-to-128 resample per stroke per tile, paid for a picture that was
## not being shown.
func _refresh(t: Dictionary) -> void:
	var mirror: Image = t["mirror"]
	var tex: ImageTexture = t["mirror_tex"]
	if mirror == null or tex == null:
		return
	tex.update(mirror)
	_apply_lod(t)

## Pushes pending dabs to the scratch target. Called once per frame.
func flush() -> void:
	if _dirty.is_empty():
		return
	for c in _dirty.keys():
		if _tiles.has(c):
			_render_tile(_tiles[c])
	_dirty.clear()

func _render_tile(t: Dictionary) -> void:
	var pending: Array = t["pending"]
	if pending.is_empty():
		return
	_attach_scratch(t)

	# Very long strokes: fold what is already on screen back into the mirror
	# so the per-frame redraw cannot grow without bound.
	if pending.size() > Perf.fold_after() and int(t["rendered"]) > 0:
		_fold(t)
		pending = t["pending"]
		if pending.is_empty():
			return

	var plate: StampPainter = t["plate"]
	var base: StampPainter = t["base"]
	var erase: StampPainter = t["erase"]
	plate.reset()
	base.reset()
	erase.reset()
	plate.add_blit(Vector2.ZERO, t["mirror_tex"])
	for s in pending:
		if String(s["k"]) == "sprite":
			# Already premultiplied, so it rides on the plate.
			plate.add_sprite(s["x"], s["t"], s["c"])
		elif bool(s["e"]):
			erase.add_stamp(s["p"], s["s"], s["a"], s["c"], s["t"])
		else:
			base.add_stamp(s["p"], s["s"], s["a"], s["c"], s["t"])
	plate.queue_redraw()
	base.queue_redraw()
	erase.queue_redraw()

	var vp: SubViewport = t["vp"]
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	t["rendered"] = pending.size()

## Reads the last finished frame back into the mirror and drops the dabs it
## already contains. Anything added since that frame stays pending.
## Also timed. This is the read back from the graphics card — the stall that
## `Perf.fold_after` exists to ration — and it was the single number in the
## whole performance model that had never been observed on any device.
func _fold(t: Dictionary) -> void:
	var vp: SubViewport = t["vp"]
	if vp == null:
		return
	var tex: Texture2D = vp.get_texture()
	if tex == null:
		return
	var started: int = Time.get_ticks_usec()
	var img: Image = tex.get_image()
	if img == null:
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var mirror: Image = t["mirror"]
	if mirror == null:
		return
	mirror.copy_from(img)
	var mtex: ImageTexture = t["mirror_tex"]
	if mtex != null:
		mtex.update(mirror)

	var pending: Array = t["pending"]
	var done: int = mini(int(t["rendered"]), pending.size())
	for i in range(done):
		pending.pop_front()
	t["rendered"] = 0
	Perf.since("fold", started)

## Called a couple of frames after a stroke ends: every tile hands its
## scratch target back and settles onto a plain texture.
func settle() -> void:
	for c in _tiles.keys():
		var t: Dictionary = _tiles[c]
		if t["vp"] == null:
			continue
		if int(t["rendered"]) > 0:
			_fold(t)
		if (t["pending"] as Array).is_empty():
			_release_scratch(t)
			_sharpen(t)
		else:
			_dirty[c] = true

## Rebuilds the tile's mipmaps now that the stroke is finished. Doing it per
## dab would cost more than the sharpness is worth; doing it here costs
## nothing anyone can feel.
func _sharpen(t: Dictionary) -> void:
	if not Perf.wants_mipmaps():
		return
	var mirror: Image = t["mirror"]
	if mirror == null:
		return
	var copy: Image = Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	copy.copy_from(mirror)
	copy.generate_mipmaps()
	t["mirror_tex"] = ImageTexture.create_from_image(copy)
	_apply_lod(t)

# ------------------------------------------------------------------ pixels

## A copy of the tile as it stands, for the undo stack. No GPU round trip.
func snapshot_tile(c: Vector2i) -> Image:
	if not _tiles.has(c):
		return null
	var t: Dictionary = _tiles[c]
	_ensure_awake(t)
	var mirror: Image = t["mirror"]
	if mirror == null:
		return null
	var out: Image = Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	out.copy_from(mirror)
	return out

func restore_tile(c: Vector2i, img: Image) -> void:
	var t: Dictionary = _make_tile(c)
	if t.is_empty():
		return
	_ensure_awake(t)
	var mirror: Image = t["mirror"]
	if img != null:
		mirror.copy_from(img)
	else:
		mirror.fill(Color(0.0, 0.0, 0.0, 0.0))
	(t["pending"] as Array).clear()
	t["rendered"] = 0
	_release_scratch(t)
	_refresh(t)

## Colour of a single canvas pixel on this layer.
func sample(world_pos: Vector2) -> Color:
	var c: Vector2i = tile_coord(world_pos)
	if not _tiles.has(c):
		return Color(0.0, 0.0, 0.0, 0.0)
	var t: Dictionary = _tiles[c]
	_ensure_awake(t)
	var mirror: Image = t["mirror"]
	if mirror == null:
		return Color(0.0, 0.0, 0.0, 0.0)
	var org: Vector2 = tile_origin(c)
	var x: int = clampi(int(floor(world_pos.x - org.x)), 0, TILE - 1)
	var y: int = clampi(int(floor(world_pos.y - org.y)), 0, TILE - 1)
	return to_straight(mirror.get_pixel(x, y))

## Composites a world-space rectangle onto `into`, or into a fresh image.
func read_region(rect: Rect2i, into: Image = null) -> Image:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return null
	var out: Image = into
	if out == null:
		out = Image.create_empty(rect.size.x, rect.size.y, false, Image.FORMAT_RGBA8)
		out.fill(Color(0.0, 0.0, 0.0, 0.0))
	var c0: Vector2i = tile_coord(Vector2(rect.position))
	var c1: Vector2i = tile_coord(Vector2(rect.position + rect.size))
	for ty in range(c0.y, c1.y + 1):
		for tx in range(c0.x, c1.x + 1):
			var c: Vector2i = Vector2i(tx, ty)
			if not _tiles.has(c):
				continue
			var t: Dictionary = _tiles[c]
			_ensure_awake(t)
			var mirror: Image = t["mirror"]
			if mirror == null:
				continue
			var org: Vector2i = Vector2i(tile_origin(c))
			var overlap: Rect2i = Rect2i(org, Vector2i(TILE, TILE)).intersection(rect)
			if overlap.size.x <= 0 or overlap.size.y <= 0:
				continue
			var src: Rect2i = Rect2i(overlap.position - org, overlap.size)
			var at: Vector2i = overlap.position - rect.position
			if into == null:
				out.blit_rect(mirror, src, at)
			else:
				out.blend_rect(mirror, src, at)
	return out

## Stamps a texture down with a full transform. Used when a moved, scaled or
## rotated selection is dropped back onto its layer.
func blit_transformed(tex: Texture2D, world_xform: Transform2D, tex_size: Vector2,
		tint: Color = Color.WHITE) -> void:
	if tex == null:
		return
	var corners: Array = [
		world_xform * Vector2.ZERO,
		world_xform * Vector2(tex_size.x, 0.0),
		world_xform * tex_size,
		world_xform * Vector2(0.0, tex_size.y),
	]
	var lo: Vector2 = corners[0]
	var hi: Vector2 = corners[0]
	for c in corners:
		lo.x = minf(lo.x, c.x)
		lo.y = minf(lo.y, c.y)
		hi.x = maxf(hi.x, c.x)
		hi.y = maxf(hi.y, c.y)

	var c0: Vector2i = tile_coord(lo - Vector2(2.0, 2.0))
	var c1: Vector2i = tile_coord(hi + Vector2(2.0, 2.0))
	for ty in range(c0.y, c1.y + 1):
		for tx in range(c0.x, c1.x + 1):
			var c: Vector2i = Vector2i(tx, ty)
			var t: Dictionary = _make_tile(c)
			if t.is_empty():
				continue
			_ensure_awake(t)
			var local: Transform2D = world_xform
			local.origin -= tile_origin(c)
			# Queued like any other mark, because the scratch target is
			# rebuilt from scratch every frame — anything handed straight to
			# the painter would be wiped on the next redraw.
			(t["pending"] as Array).append({
				"k": "sprite", "x": local, "t": tex, "c": tint,
			})
			_dirty[c] = true

## Clears every pixel the stencil covers. Runs straight on the mirrors, so
## lifting a selection costs nothing on the GPU.
func erase_masked(rect: Rect2i, mask: PackedByteArray) -> void:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	var c0: Vector2i = tile_coord(Vector2(rect.position))
	var c1: Vector2i = tile_coord(Vector2(rect.position + rect.size))
	for ty in range(c0.y, c1.y + 1):
		for tx in range(c0.x, c1.x + 1):
			var c: Vector2i = Vector2i(tx, ty)
			if not _tiles.has(c):
				continue
			var t: Dictionary = _tiles[c]
			_ensure_awake(t)
			var mirror: Image = t["mirror"]
			if mirror == null:
				continue
			var org: Vector2i = Vector2i(tile_origin(c))
			var overlap: Rect2i = Rect2i(org, Vector2i(TILE, TILE)).intersection(rect)
			if overlap.size.x <= 0 or overlap.size.y <= 0:
				continue
			var touched: bool = false
			for y in range(overlap.size.y):
				var my: int = overlap.position.y + y - rect.position.y
				var ly: int = overlap.position.y + y - org.y
				var mrow: int = my * rect.size.x
				for x in range(overlap.size.x):
					var mx: int = overlap.position.x + x - rect.position.x
					if mask[mrow + mx] == 0:
						continue
					mirror.set_pixel(overlap.position.x + x - org.x, ly,
						Color(0.0, 0.0, 0.0, 0.0))
					touched = true
			if touched:
				_refresh(t)

## Fades every pixel by a coverage stencil instead of cutting on or off.
##
## `erase_masked` above removes whole pixels, which is right for lifting a
## selection and wrong for holding paint inside a drawn shape: a hard cut
## along the edge of an anti-aliased figure leaves a staircase exactly where
## the figure's own edge is smooth, and no amount of care with the brush hides
## it.
##
## Here each pixel is multiplied by its coverage, so paint that lands on the
## soft outer edge of a character comes away as soft as that edge is. All four
## channels are multiplied because the canvas is premultiplied — scaling alpha
## alone would leave the colour too strong for the alpha carrying it, which is
## the bright fringe this whole file exists to avoid.
##
## Coverage runs 0 to 255 and is laid out row by row over `rect`.
func hold_inside(rect: Rect2i, coverage: PackedByteArray) -> void:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	if coverage.size() < rect.size.x * rect.size.y:
		return
	var c0: Vector2i = tile_coord(Vector2(rect.position))
	var c1: Vector2i = tile_coord(Vector2(rect.position + rect.size))
	for ty in range(c0.y, c1.y + 1):
		for tx in range(c0.x, c1.x + 1):
			var c: Vector2i = Vector2i(tx, ty)
			if not _tiles.has(c):
				continue
			var t: Dictionary = _tiles[c]
			_ensure_awake(t)
			var mirror: Image = t["mirror"]
			if mirror == null:
				continue
			var org: Vector2i = Vector2i(tile_origin(c))
			var overlap: Rect2i = Rect2i(org,
				Vector2i(TILE, TILE)).intersection(rect)
			if overlap.size.x <= 0 or overlap.size.y <= 0:
				continue
			var touched: bool = false
			for y in range(overlap.size.y):
				var my: int = overlap.position.y + y - rect.position.y
				var ly: int = overlap.position.y + y - org.y
				var mrow: int = my * rect.size.x
				for x in range(overlap.size.x):
					var lx: int = overlap.position.x + x - org.x
					var was: Color = mirror.get_pixel(lx, ly)
					if was.a <= 0.0 and was.r <= 0.0 and was.g <= 0.0 \
							and was.b <= 0.0:
						continue
					var keep: float = float(coverage[mrow
						+ overlap.position.x + x - rect.position.x]) / 255.0
					if keep >= 0.999:
						continue
					mirror.set_pixel(lx, ly, Color(was.r * keep, was.g * keep,
						was.b * keep, was.a * keep))
					touched = true
			if touched:
				_refresh(t)

## Union of every tile that exists, in world pixels. Empty if nothing drawn.
func content_bounds() -> Rect2i:
	if _tiles.is_empty():
		return Rect2i(0, 0, 0, 0)
	var lo: Vector2i = Vector2i(2147483647, 2147483647)
	var hi: Vector2i = Vector2i(-2147483648, -2147483648)
	for c in _tiles.keys():
		var key: Vector2i = c
		lo.x = mini(lo.x, key.x * TILE)
		lo.y = mini(lo.y, key.y * TILE)
		hi.x = maxi(hi.x, (key.x + 1) * TILE)
		hi.y = maxi(hi.y, (key.y + 1) * TILE)
	return Rect2i(lo, hi - lo)

## The texture a tile is currently showing, so another surface can composite
## it without a trip through the CPU.
func tile_texture(c: Vector2i) -> Texture2D:
	if not _tiles.has(c):
		return null
	var t: Dictionary = _tiles[c]
	_ensure_awake(t)
	return t["mirror_tex"]

## Folds another surface down onto this one.
##
## Done on the GPU rather than pixel by pixel: merging two full layers by
## hand would mean a few hundred thousand steps per tile in script, which is
## a visible freeze for something as ordinary as merging two layers.
## Queuing it as a blit costs nothing and lands on the next frame.
func blend_from(other: PaintSurface, opacity: float = 1.0) -> void:
	if opacity <= 0.001:
		return
	# Premultiplied pixels scale on every channel at once, so a faded merge
	# uses the same number in all four.
	var tint: Color = Color(opacity, opacity, opacity, opacity)
	for c in other.get_tile_coords():
		var key: Vector2i = c
		var tex: Texture2D = other.tile_texture(key)
		if tex == null:
			continue
		var t: Dictionary = _make_tile(key)
		if t.is_empty():
			continue
		_ensure_awake(t)
		(t["pending"] as Array).append({
			"k": "sprite",
			"x": Transform2D(0.0, Vector2.ZERO),
			"t": tex,
			"c": tint,
		})
		_dirty[key] = true

## Clears anything outside `keep`, in this surface's own coordinates.
##
## Whole tiles beyond the edge are emptied outright; only the ring of tiles
## straddling the border is walked pixel by pixel, so the cost follows the
## perimeter of the page rather than its area.
func trim_to(keep: Rect2) -> void:
	var box: Rect2i = Rect2i(Vector2i(keep.position.floor()),
		Vector2i(keep.size.ceil()))
	for c in _tiles.keys():
		var t: Dictionary = _tiles[c]
		var span: Rect2i = Rect2i(Vector2i(tile_origin(c)), Vector2i(TILE, TILE))
		var overlap: Rect2i = span.intersection(box)
		if overlap.size.x == TILE and overlap.size.y == TILE:
			continue                      # wholly inside: nothing to do
		_ensure_awake(t)
		var mirror: Image = t["mirror"]
		if mirror == null:
			continue
		if overlap.size.x <= 0 or overlap.size.y <= 0:
			mirror.fill(Color(0.0, 0.0, 0.0, 0.0))
			_refresh(t)
			continue
		var local: Rect2i = Rect2i(overlap.position - span.position, overlap.size)
		var kept: Image = Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
		kept.fill(Color(0.0, 0.0, 0.0, 0.0))
		kept.blit_rect(mirror, local, local.position)
		mirror.copy_from(kept)
		_refresh(t)

func clear_all() -> void:
	for c in _tiles.keys():
		var t: Dictionary = _tiles[c]
		_release_scratch(t)
		(t["pending"] as Array).clear()
		t["rendered"] = 0
		if bool(t["asleep"]):
			t["packed"] = PackedByteArray()
			t["asleep"] = false
			var blank: Image = Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
			blank.fill(Color(0.0, 0.0, 0.0, 0.0))
			t["mirror"] = blank
			t["mirror_tex"] = ImageTexture.create_from_image(blank)
		else:
			(t["mirror"] as Image).fill(Color(0.0, 0.0, 0.0, 0.0))
		_refresh(t)
	_dirty.clear()


# ------------------------------------------------------------------ focus

## How far out of focus this layer is, 0 sharp to 1 fully soft.
##
## Everything is done on premultiplied colour, which is what these tiles hold
## and the only form in which averaging pixels together is correct. A blur
## computed on straight alpha draws a dark rim around every stroke — the
## familiar sign of a blur done in the wrong colour space.
func set_blur(amount: float, shader: Shader, blades: int = 6) -> void:
	if amount <= 0.004 or shader == null:
		_drop_lens()
		return
	if _lens == null:
		_lens = CanvasGroup.new()
		_lens.name = "Lens"
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = shader
		_lens.material = mat
		add_child(_lens)
		# Everything already drawn moves under it, so the whole layer is
		# composited as one image rather than tile by tile.
		for c in _tiles.keys():
			var root: Node2D = (_tiles[c] as Dictionary)["root"]
			if root != null and root.get_parent() == self:
				remove_child(root)
				_lens.add_child(root)
	var mat2: ShaderMaterial = _lens.material as ShaderMaterial
	if mat2 == null:
		return
	# Squared, so the first touch of softness is gentle and the far end of the
	# slider still reaches a proper wash. Linear here feels like a switch.
	var eased: float = amount * amount
	mat2.set_shader_parameter("radius", eased * 34.0)
	# The sample count follows the radius *and* the device. A wide blur with
	# too few samples is a ring of ghosts rather than a soft image, and a
	# narrow one with fifty samples is fifty reads of very nearly the same
	# pixel. On a machine already struggling to solve a rig, the ceiling comes
	# down rather than the blur being switched off: a slightly grainier wash
	# looks like film, and a dropped frame looks like a fault.
	var ceiling: int = 48 if Perf.rig_solve_stride() == 1 else 26
	mat2.set_shader_parameter("taps",
		clampi(int(12.0 + eased * 44.0), 8, ceiling))
	mat2.set_shader_parameter("bloom", 3.2)
	mat2.set_shader_parameter("bloom_knee", 0.62)
	mat2.set_shader_parameter("blades", blades)
	# Turned off the horizontal, so the flat of a blade faces the eye rather
	# than a corner. A polygon standing on its point reads as a mistake; the
	# same polygon lying flat reads as a lens.
	mat2.set_shader_parameter("blade_turn", 0.35)
	mat2.set_shader_parameter("haze", 0.045)

func _drop_lens() -> void:
	if _lens == null:
		return
	for c in _tiles.keys():
		var root: Node2D = (_tiles[c] as Dictionary)["root"]
		if root != null and root.get_parent() == _lens:
			_lens.remove_child(root)
			add_child(root)
	_lens.queue_free()
	_lens = null


## Turns this layer into a light, or back into paint.
func set_glow(on: bool) -> void:
	if glowing == on:
		return
	glowing = on
	var mat: CanvasItemMaterial = _glow_material if on else _premul_material
	for c in _tiles.keys():
		var sprite: Sprite2D = (_tiles[c] as Dictionary)["sprite"]
		if sprite != null:
			sprite.material = mat
