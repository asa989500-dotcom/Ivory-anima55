class_name DrawTransfer
extends RefCounted
## Carries a drawing out of a drawing project and into another project.
##
## This is the one road between two projects. Everywhere else in IVORY a
## project is a sealed world — its own layers, its own history, its own paper —
## and that is deliberate: it is what makes opening a second project unable to
## disturb the first. So the road is built narrow and one-way on purpose.
##
## Three rules hold it together, and every decision below follows from one of
## them:
##
## **It only leaves a drawing.** The button is offered inside a drawing project
## and nowhere else. An animation is a scene and a comic is a book; neither is
## a thing you reach into for a picture. A drawing is.
##
## **It copies, it never cuts.** The source project is opened read-only and is
## not written to by a single line in this file. A transfer that emptied the
## drawing it came from would be one gesture away from losing hours of work,
## across a boundary where undo cannot reach — because undo belongs to a
## project, and the two projects have two histories. Copying makes the worst
## case "a layer I did not want", which is one undo away in the project that
## received it.
##
## **What lands is undoable.** Everything this file adds to the target arrives
## as a *single* history entry in the target's own stack. Not one per layer:
## the user made one decision and pressing undo once should take it back
## whole. The last section of `run` is entirely about arranging that.

## Nothing may be resampled past this on a side. A drawing dragged onto a
## page many times its size would otherwise ask for an allocation no phone
## has, and the honest answer is to stop at a size that can be held.
const MAX_SIDE: int = 8192

## The rule the whole flow is gated on.
static func offered_by(p: ProjectManager.Project) -> bool:
	return p != null and p.kind == ProjectManager.Kind.DRAWING

# ------------------------------------------------------------------- plan

## What the three questions add up to.
##
## Held rather than passed as seven arguments, because the answers arrive one
## screen at a time and the flow has to survive being backed out of and begun
## again. The panel writes into this; `run` reads it once and does the work.
class Plan:
	var source: ProjectManager.Project = null
	var page: int = 0
	## Layer ids, not indices. An index is a position in a list that another
	## part of the app may reorder between one screen and the next; an id is
	## the layer itself.
	var chosen: Dictionary = {}
	var target: ProjectManager.Project = null
	var target_page: int = 0
	var merge: bool = false

	func count() -> int:
		return chosen.size()

	func holds(id: int) -> bool:
		return chosen.has(id)

	func toggle(id: int) -> void:
		if chosen.has(id):
			chosen.erase(id)
		else:
			chosen[id] = true

	func clear() -> void:
		chosen.clear()

# ------------------------------------------------------------------ lists

## The layers of the source page, top of the picture first — the order the
## layers panel shows, so the two lists cannot disagree.
##
## Empty layers are listed rather than hidden. A layer the user believes has
## something on it and which turns out not to is worth seeing greyed out with
## the word *empty* beside it; silently dropping it from the list reads as a
## bug in the list.
static func rows(p: ProjectManager.Project, page_index: int) -> Array:
	var out: Array = []
	if p == null:
		return out
	var page: ProjectManager.Page = p.page_at(page_index)
	if page == null or page.stack == null:
		return out
	var stack: LayerStack = page.stack
	var i: int = stack.layers.size() - 1
	while i >= 0:
		var l: LayerStack.Layer = stack.layers[i]
		var box: Rect2i = l.surface.content_bounds()
		out.append({
			"id": l.id,
			"index": i,
			"title": l.title,
			"thumb": l.thumb,
			"empty": box.size.x <= 0 or box.size.y <= 0,
			"background": l.is_background,
			"hidden": not l.visible,
		})
		i -= 1
	return out

## Everywhere the drawing could go.
##
## Every other project in the workspace, animations and comics first, because
## those are what this feature exists to feed. Other drawings stay on the list
## underneath them: a drawing is a perfectly reasonable place to send a
## drawing — a character sheet gathering figures drawn on separate pages is
## exactly that — and refusing it would be a rule with no one behind it.
static func targets(manager: ProjectManager,
		source: ProjectManager.Project) -> Array:
	var out: Array = []
	if manager == null:
		return out
	var wanted: Array = [ProjectManager.Kind.ANIMATION,
		ProjectManager.Kind.COMIC, ProjectManager.Kind.DRAWING]
	for kind in wanted:
		for p in manager.projects:
			if p == source or p.kind != kind:
				continue
			out.append(p)
	return out

# --------------------------------------------------------------- geometry

## The single number that carries a drawing from one page onto another.
##
## One factor for both axes, never two. Two would fit the drawing to the page
## exactly and stretch the figure doing it — a face is a face at one ratio and
## nobody's face at another. So the smaller of the two ratios wins, the whole
## source page fits inside the target with its proportions untouched, and what
## is left over becomes an even margin on the two sides that had room to spare.
##
## When the pages are the same size this comes out as exactly one and no
## offset, and `run` then skips resampling altogether — a same-size transfer
## is pixel for pixel what was drawn, not a copy that has been through a
## filter for no reason.
static func fit(from_page: Vector2, to_page: Vector2) -> Dictionary:
	var sw: float = maxf(from_page.x, 1.0)
	var sh: float = maxf(from_page.y, 1.0)
	var k: float = minf(to_page.x / sw, to_page.y / sh)
	if absf(k - 1.0) < 0.0005:
		k = 1.0
	var offset: Vector2 = (to_page - Vector2(sw, sh) * k) * 0.5
	return {"k": k, "offset": offset}

# ------------------------------------------------------------ compositing

## One premultiplied image laid over another, exactly.
##
## `over` and `under` are both premultiplied, which is the form these canvases
## hold and the only form in which this sum is a single line:
##
##     out = over + under · (1 − over.a)
##
## Godot's own `blend_rect` cannot be used here. It reads both sides as
## straight alpha, so over a destination that already has something on it the
## source is weighted by its alpha twice — exact where the top pixel is solid
## or empty, and wrong along every anti-aliased edge, which on a drawing means
## wrong along every line in it. That error is invisible once and visible after
## six layers have been merged through it.
##
## The loop is written around the two cases that are nearly all of a drawing:
## a transparent pixel costs one comparison and is skipped, a solid one costs a
## four-byte copy. Only genuinely part-transparent pixels — the thin rim of the
## strokes — reach the arithmetic. That is what makes an exact composite
## affordable in GDScript on a page of eight million pixels.
## `round(v / 255)` for `v` in 0…65025, without dividing.
##
## Two reasons, and the second is the one that matters.
##
## Godot warns on every integer division in the file — "decimal part will be
## discarded" — because most of the time that discarding is a bug someone did
## not mean. Here it was deliberate, but a warning you have decided to ignore is
## a warning you will go on ignoring when it is finally telling you something,
## so it is better to write code that has nothing to warn about.
##
## And it is exact. `(t + (t >> 8)) >> 8` with `t = v + 128` equals
## `round(v / 255)` for every one of the 65,026 values this can be handed —
## checked exhaustively, not sampled. The largest product that reaches it is
## 255 × 255 = 65,025, comfortably inside the range where the identity holds.
static func _by255(v: int) -> int:
	var t: int = v + 128
	return (t + (t >> 8)) >> 8

static func _over(under: Image, over: Image, at: Vector2i) -> void:
	if under == null or over == null:
		return
	var dw: int = under.get_width()
	var dh: int = under.get_height()
	var sw: int = over.get_width()
	var sh: int = over.get_height()

	# The part of the top image that actually lands on the bottom one.
	var x0: int = maxi(0, -at.x)
	var y0: int = maxi(0, -at.y)
	var x1: int = mini(sw, dw - at.x)
	var y1: int = mini(sh, dh - at.y)
	if x1 <= x0 or y1 <= y0:
		return

	var dst: PackedByteArray = under.get_data()
	var src: PackedByteArray = over.get_data()
	for y in range(y0, y1):
		var srow: int = y * sw * 4
		var drow: int = ((y + at.y) * dw + at.x) * 4
		for x in range(x0, x1):
			var so: int = srow + x * 4
			var sa: int = src[so + 3]
			if sa == 0:
				continue
			var dofs: int = drow + x * 4
			if sa == 255:
				dst[dofs] = src[so]
				dst[dofs + 1] = src[so + 1]
				dst[dofs + 2] = src[so + 2]
				dst[dofs + 3] = 255
				continue
			# 255 − a, carried with rounding, so a long stack of merges cannot
			# drift a channel downward one unit at a time. `_by255` does the
			# rounding divide without a divide — see the note on it.
			var inv: int = 255 - sa
			dst[dofs] = mini(int(src[so]) + _by255(int(dst[dofs]) * inv), 255)
			dst[dofs + 1] = mini(int(src[so + 1]) + _by255(int(dst[dofs + 1]) * inv), 255)
			dst[dofs + 2] = mini(int(src[so + 2]) + _by255(int(dst[dofs + 2]) * inv), 255)
			dst[dofs + 3] = mini(sa + _by255(int(dst[dofs + 3]) * inv), 255)
	under.set_data(dw, dh, false, Image.FORMAT_RGBA8, dst)

## Every channel scaled by the same number.
##
## Premultiplied colour fades on all four channels at once — that is the whole
## convenience of it — so a layer carried across at seventy per cent is one
## multiply per byte and needs no division and no special case for alpha.
static func _fade(img: Image, amount: float) -> void:
	if img == null or amount >= 0.999:
		return
	var f: int = clampi(int(round(clampf(amount, 0.0, 1.0) * 255.0)), 0, 255)
	var d: PackedByteArray = img.get_data()
	var n: int = img.get_width() * img.get_height() * 4
	for i in range(n):
		var v: int = d[i]
		if v != 0:
			d[i] = _by255(v * f)
	img.set_data(img.get_width(), img.get_height(), false,
		Image.FORMAT_RGBA8, d)

# ------------------------------------------------------------------- work

## What one chosen layer amounts to: its pixels, and where on the target page
## they belong.
class Piece:
	var img: Image = null
	var at: Vector2i = Vector2i.ZERO
	var title: String = ""
	var opacity: float = 1.0
	var visible: bool = true
	var glow: bool = false

## Reads the chosen layers out of the source, in stack order, bottom first.
##
## Bottom first for two reasons at once: it is the order a merge has to be
## summed in, and it is the order the layers have to be added to the target in
## if the picture is to come out the way it went in. One order serves both, so
## there is no second place where the order could be got wrong.
static func _gather(plan: Plan) -> Array:
	var out: Array = []
	var page: ProjectManager.Page = plan.source.page_at(plan.page)
	if page == null or page.stack == null:
		return out
	var stack: LayerStack = page.stack

	# A stroke lives on the graphics card until it is folded down. Reading the
	# layer without this returns the drawing as it was a moment ago, missing
	# whatever the hand did last — which is exactly the part the user is most
	# sure they drew.
	stack.flush_all()
	stack.settle_all()

	var span: Rect2i = Rect2i(Vector2i.ZERO,
		Vector2i(int(plan.source.page.x), int(plan.source.page.y)))

	for l in stack.layers:
		if not plan.holds(l.id):
			continue
		# Clipped to the page, always. Ink that ran off the edge is not part
		# of the drawing — the sheet does not show it and no export carries
		# it — so it must not be what decides how large the transfer is.
		var box: Rect2i = l.surface.content_bounds().intersection(span)
		if box.size.x <= 0 or box.size.y <= 0:
			continue
		var img: Image = l.surface.read_region(box)
		if img == null:
			continue
		var piece: Piece = Piece.new()
		piece.img = img
		piece.at = box.position
		piece.title = l.title
		piece.opacity = l.opacity
		piece.visible = l.visible
		piece.glow = l.glow
		out.append(piece)
	return out

## Folds several pieces into one, at source resolution.
##
## At source resolution and not at target resolution, deliberately: resampling
## once at the end costs one filter pass over the finished picture, where
## resampling each piece first would put every layer through a filter and then
## add the results together — six roundings instead of one, and the softness
## of all six landing on the same line where two layers share an edge.
static func _flatten(pieces: Array) -> Piece:
	var lo: Vector2i = (pieces[0] as Piece).at
	var hi: Vector2i = lo
	for one in pieces:
		var p: Piece = one
		lo.x = mini(lo.x, p.at.x)
		lo.y = mini(lo.y, p.at.y)
		hi.x = maxi(hi.x, p.at.x + p.img.get_width())
		hi.y = maxi(hi.y, p.at.y + p.img.get_height())
	var w: int = clampi(hi.x - lo.x, 1, MAX_SIDE)
	var h: int = clampi(hi.y - lo.y, 1, MAX_SIDE)

	# Asked for through the budget rather than taken. The union of six
	# full-page layers on a Full HD comic is the largest single allocation this
	# feature ever wants, and `Image.create_empty` does not fail politely when
	# it is beyond reach — the process is killed, which reaches the user as the
	# app vanishing with their drawing in it.
	var sheet: Image = Perf.make_image(Vector2i(w, h))
	if sheet == null:
		var out_small: Piece = Piece.new()
		out_small.img = null
		out_small.at = lo
		return out_small
	var drawn: int = 0
	for one in pieces:
		var p: Piece = one
		# A layer hidden in the source is hidden in the drawing, and a merge
		# is the drawing. It keeps its own line in the several-layers route,
		# where hidden still means something; here there is nowhere to put it.
		if not p.visible or p.opacity <= 0.004:
			continue
		_fade(p.img, p.opacity)
		_over(sheet, p.img, p.at - lo)
		drawn += 1
		# Released as we go. Holding six full-page layers and the sheet at
		# once is the one moment this feature could ask for more memory than
		# a phone has, and nothing needs a piece again once it is folded in.
		p.img = null

	var out: Piece = Piece.new()
	# Every chosen layer turned out to be hidden, so the merge of them is a
	# blank sheet. Handing that over would put an empty layer in the target
	# and call it a success; saying nothing landed is the truth.
	out.img = sheet if drawn > 0 else null
	out.at = lo
	out.title = ""
	return out

# ---------------------------------------------------------------- the landing

## Everything worked out and waiting, but not yet on the page.
##
## The transfer used to finish the moment the last question was answered, which
## meant the drawing landed wherever the arithmetic put it — centred on the
## target page, which is the only sensible guess and is a guess. A figure meant
## for the left of a comic panel arrived in the middle of it and had to be
## selected, cut and moved.
##
## So the arithmetic still runs to the end, and then stops. What it produces is
## this: the pieces at their final resolution, and one flattened picture of what
## they will look like. `CanvasView` floats that picture in the target project
## inside the ordinary transform box, and `land` is called once the user has put
## it where they want it.
class Landing:
	var target: ProjectManager.Project = null
	var target_page: int = 0
	var merge: bool = false
	## `Piece`s at target resolution; `at` is already in target page pixels.
	var pieces: Array = []
	var origin: Vector2i = Vector2i.ZERO
	var size: Vector2i = Vector2i.ONE
	## The flattened picture the user drags about. Never written to the page —
	## on the several-layers route the pieces are laid down one at a time and
	## this was only ever what they looked like stacked.
	var preview: Image = null
	var dropped: int = 0

	## Where the box should first appear: exactly where the fitting put it.
	func home() -> Vector2:
		return Vector2(origin) + Vector2(size) * 0.5

## A flattened picture of the pieces, without consuming them.
##
## `_flatten` fades and releases as it goes, because on the merge route nothing
## needs the pieces afterwards. Here everything does — each one still has to be
## laid down on a layer of its own once the box is placed — so the fading is
## done on a duplicate and the duplicate is what gets folded in.
static func _preview(pieces: Array, origin: Vector2i, size: Vector2i) -> Image:
	var sheet: Image = Perf.make_image(Vector2i(maxi(size.x, 1), maxi(size.y, 1)))
	if sheet == null:
		return null
	for one in pieces:
		var p: Piece = one
		if p.img == null or not p.visible or p.opacity <= 0.004:
			continue
		var shown: Image = p.img
		if p.opacity < 0.999:
			shown = Image.create_empty(p.img.get_width(), p.img.get_height(),
				false, Image.FORMAT_RGBA8)
			shown.copy_from(p.img)
			_fade(shown, p.opacity)
		_over(sheet, shown, p.at - origin)
	return sheet

## Runs every question's answer through the arithmetic and stops at the page.
##
## Returns `{"ok": bool, "landing": Landing, "message": String}`. The message is
## a finished sentence in the current language: this is called from a button,
## and what a button owes the user is a sentence.
static func prepare(manager: ProjectManager, plan: Plan) -> Dictionary:
	var refuse: Dictionary = {"ok": false, "landing": null, "message": ""}
	if manager == null or plan == null or plan.source == null \
			or plan.target == null or plan.count() == 0:
		refuse["message"] = UiKit.label_for("Nothing to transfer", "لا شيء لنقله")
		return refuse

	var into_page: ProjectManager.Page = plan.target.page_at(plan.target_page)
	if into_page == null or into_page.stack == null:
		refuse["message"] = UiKit.label_for("Nothing to transfer", "لا شيء لنقله")
		return refuse

	var pieces: Array = _gather(plan)
	if pieces.is_empty():
		refuse["message"] = UiKit.label_for("Those layers are empty",
			"تلك الطبقات فارغة")
		return refuse

	# Merging is the only route that has to bake anything. On the other one a
	# layer's opacity travels as what it is — a property of the layer — so a
	# figure carried across at forty per cent can be turned back up to full in
	# the project it lands in. Baking it would make that number the pixels, and
	# the pixels do not come back.
	if plan.merge and pieces.size() > 1:
		var one_piece: Piece = _flatten(pieces)
		if one_piece.img == null:
			refuse["message"] = UiKit.label_for("Those layers are empty",
				"تلك الطبقات فارغة")
			return refuse
		pieces = [one_piece]

	# How many the target can take, worked out before any of the expensive
	# work, so nothing is begun and then abandoned halfway with a partial
	# picture on the page.
	var free: int = maxi(LayerStack.MAX_LAYERS - into_page.stack.layers.size(), 0)
	if free <= 0:
		refuse["message"] = UiKit.label_for("That project is full of layers",
			"ذلك المشروع بلغ حدّ الطبقات")
		return refuse
	var dropped: int = maxi(pieces.size() - free, 0)
	if dropped > 0:
		pieces = pieces.slice(0, free)

	# Resampled once, here, to the size the target page asks for. Doing it now
	# rather than at landing time means the picture under the finger is the
	# picture that will be laid down — the box shows the real thing, not an
	# approximation of it that sharpens when released.
	var shape: Dictionary = fit(plan.source.page, plan.target.page)
	var k: float = float(shape["k"])
	var offset: Vector2 = shape["offset"]
	var kept: Array = []
	for one in pieces:
		var p: Piece = one
		if p.img == null:
			continue
		if k != 1.0:
			var want: Vector2i = Vector2i(
				clampi(int(round(float(p.img.get_width()) * k)), 1, MAX_SIDE),
				clampi(int(round(float(p.img.get_height()) * k)), 1, MAX_SIDE))
			p.img = Distort.rescale(p.img, want)
			if p.img == null:
				continue
		p.at = Vector2i((Vector2(p.at) * k + offset).round())
		kept.append(p)
	if kept.is_empty():
		refuse["message"] = UiKit.label_for("Those layers are empty",
			"تلك الطبقات فارغة")
		return refuse

	var lo: Vector2i = (kept[0] as Piece).at
	var hi: Vector2i = lo
	for one in kept:
		var p: Piece = one
		lo.x = mini(lo.x, p.at.x)
		lo.y = mini(lo.y, p.at.y)
		hi.x = maxi(hi.x, p.at.x + p.img.get_width())
		hi.y = maxi(hi.y, p.at.y + p.img.get_height())

	var out: Landing = Landing.new()
	out.target = plan.target
	out.target_page = plan.target_page
	out.merge = plan.merge
	out.pieces = kept
	out.origin = lo
	out.size = Vector2i(clampi(hi.x - lo.x, 1, MAX_SIDE),
		clampi(hi.y - lo.y, 1, MAX_SIDE))
	out.dropped = dropped
	out.preview = _preview(kept, out.origin, out.size)
	if out.preview == null:
		# The drawing is larger than this device can hold in one piece. Said
		# plainly and early, with nothing written anywhere, rather than
		# discovered by the operating system halfway through.
		refuse["message"] = UiKit.label_for(
			"That drawing is too large for this device to carry",
			"تلك الرسمة أكبر من أن يحملها هذا الجهاز")
		return refuse
	return {"ok": true, "landing": out, "message": ""}

## Puts it down, where the box was left.
##
## `place` maps the preview's own box — nothing to `size` — onto the target
## page, and is the transform the user built by dragging. It carries a move and
## a uniform scale and nothing else: rotation is kept off the placement box on
## purpose, because turning a picture means resampling every piece through an
## angle, and a rotation applied to six layers separately does not compose back
## into what the preview showed. Turning it afterwards, with the selection tool
## on the layer it landed on, does exactly what it looks like.
static func land(manager: ProjectManager, landing: Landing,
		place: Transform2D) -> Dictionary:
	var refuse: Dictionary = {"ok": false, "layers": 0, "message": ""}
	if manager == null or landing == null or landing.pieces.is_empty():
		refuse["message"] = UiKit.label_for("Nothing to transfer", "لا شيء لنقله")
		return refuse
	var into_page: ProjectManager.Page = landing.target.page_at(landing.target_page)
	if into_page == null or into_page.stack == null:
		refuse["message"] = UiKit.label_for("Nothing to transfer", "لا شيء لنقله")
		return refuse
	var into: LayerStack = into_page.stack

	var grow: float = maxf(place.x.length(), 0.01)

	# --- the single undo entry ------------------------------------------
	#
	# Captured before anything is added, and the target's history is unhooked
	# while the layers go in. `add_layer` records a step of its own otherwise,
	# so six transferred layers would be six presses of undo to be rid of —
	# and the user made one decision, not six.
	var before: Array = [{"t": "arrangement", "state": into.capture_arrangement()}]
	var keeper: History = into.history
	into.history = null

	var landed: int = 0
	var page_span: Rect2 = Rect2(Vector2.ZERO, landing.target.page)
	var word: String = UiKit.label_for("Transferred", "منقول")

	for one in landing.pieces:
		var p: Piece = one
		if p.img == null:
			continue
		var img: Image = p.img
		# Each piece keeps its place *within* the picture: its offset from the
		# preview's corner goes through the same transform the preview did, so
		# six layers that lined up on the source page still line up here.
		var at: Vector2 = place * Vector2(p.at - landing.origin)

		if absf(grow - 1.0) > 0.004:
			var want: Vector2i = Vector2i(
				clampi(int(round(float(img.get_width()) * grow)), 1, MAX_SIDE),
				clampi(int(round(float(img.get_height()) * grow)), 1, MAX_SIDE))
			img = Distort.rescale(img, want)
			if img == null:
				continue

		var fresh: LayerStack.Layer = into.add_layer(into.layers.size(), 0)
		if fresh == null:
			break
		fresh.title = p.title if p.title != "" else word
		fresh.visible = p.visible
		fresh.opacity = clampf(p.opacity, 0.0, 1.0)
		fresh.glow = p.glow
		# Present from the first frame of the scene, not from wherever the
		# playhead of a project nobody was looking at happens to be standing. A
		# drawing brought in from outside has no opinion about time; the only
		# honest answer is that it has always been there.
		fresh.born_at = 0
		fresh.gone_at = -1

		# `replace`, on a layer created empty a line ago. It writes the
		# premultiplied bytes down verbatim rather than blending them into the
		# nothing beneath, so what lands is what was read — no filter, no
		# rounding, no alpha arithmetic at all.
		fresh.surface.blit_image(img, at.round(), true)
		fresh.surface.trim_to(page_span)
		landed += 1
		p.img = null

	into.history = keeper
	if landed > 0 and keeper != null:
		keeper.push(UiKit.label_for("Transfer of the decree", "نقل المرسوم"),
			before)

	landing.pieces.clear()
	landing.preview = null
	if landed == 0:
		refuse["message"] = UiKit.label_for("Nothing to transfer", "لا شيء لنقله")
		return refuse

	# Not redundant, despite `add_layer` having rebuilt after each one. The
	# opacity, visibility and glow of every transferred layer were written
	# straight onto the layer *after* it was made, and it is `_apply_looks` —
	# reached from here — that turns those three numbers into what the layer
	# actually looks like. Without this a layer carried across at forty per
	# cent would arrive at forty per cent on paper and full strength on screen.
	into._rebuild()
	into.refresh_all_thumbs()
	# A project nobody has open goes straight back to sleep: its tiles are
	# compressed and hand back every byte of graphics memory they were given
	# for the length of this operation. Without it, transferring into six
	# projects would leave six projects awake.
	if landing.target != manager.active:
		for l in into.layers:
			l.surface.settle()
			l.surface.sleep_all()
	manager.mark_dirty(landing.target)
	manager.projects_changed.emit()

	var told: String = ""
	if landed == 1:
		told = Lang.fill("Moved into {0}", [landing.target.title], "نُقلت إلى {0}")
	else:
		told = Lang.fill("{0} layers moved into {1}",
			[landed, landing.target.title], "نُقلت {0} طبقات إلى {1}")
	if landing.dropped > 0:
		told += "  ·  " + Lang.fill("{0} would not fit", [landing.dropped],
			"{0} لم تتّسع")
	return {"ok": true, "layers": landed, "message": told}
