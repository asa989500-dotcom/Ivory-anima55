class_name ComicConfine
extends RefCounted
## The panel is the edge of the paper.
##
## ## What was asked for
##
## On a comic page, a mark stays inside the panel it began in. Cut the page in
## two and there are two places to draw and no way out of either. Cut again and
## there are four. The brush, the eraser, the fill, the smudge — everything
## that lays ink — stops at the panel's edge exactly as it would stop at the
## edge of the sheet.
##
## Two things may cross, and only two: **an imported image** and **text**. Both
## are placed objects rather than strokes; an artist positions them and can see
## where they are, and a speech balloon that has to stay inside its panel is a
## speech balloon that cannot overlap the gutter, which is half of comic
## lettering.
##
## ## What was there before
##
## Confinement existed but needed a panel to have been *chosen* first — tapped,
## deliberately, in the cutter. Until then `confined()` was false and the whole
## page was one surface, which is the opposite of what cutting a page means.
## And the point being tested had the page origin subtracted from it twice, so
## on any page but the first the allowed region was a panel-shaped hole
## somewhere off the paper: every stroke inside a visible frame was refused and
## the tools appeared dead.
##
## ## What decides which panel
##
## Where the stroke *began*. Not where the finger is now — that would let a
## stroke change panels halfway and be clipped into two pieces — and not the
## chosen panel alone, because a page that has been cut should confine whether
## or not anybody has tapped a frame. A chosen panel still wins when there is
## one, because choosing it is a deliberate statement.

## The panel a mark starting here belongs to, or -1 for none.
##
## The chosen panel wins when there is one: tapping a frame in the cutter is
## the artist saying "this one", and it should hold even for a stroke that
## starts in the gutter and reaches in.
static func panel_for(sheet: ComicPage, start: Vector2) -> int:
	if sheet == null or sheet.panels.is_empty():
		return -1
	if not sheet.confine:
		return -1
	if sheet.chosen >= 0 and sheet.chosen < sheet.panels.size():
		return sheet.chosen
	return sheet.panel_at(start)

## Whether a point may be inked, given the panel the mark belongs to.
static func allows(sheet: ComicPage, panel: int, at: Vector2) -> bool:
	if sheet == null or panel < 0 or panel >= sheet.panels.size():
		return true
	if not sheet.confine:
		return true
	return sheet.point_in_panel(panel, at)

## Erases everything in `img` that falls outside the panel.
##
## The fill needs this and the brush does not. A brush asks about one dab at a
## time and a dab that is refused simply does not happen. A flood is decided in
## one go: it starts inside the panel, runs along whatever the drawing lets it
## reach, and a gap in a line lets it out into the next panel — where it lands
## as a solid block of colour nobody asked for. So the flood is allowed to run
## and its result is cut to the panel afterwards, which also means the fill
## stops on the panel edge itself rather than needing a line drawn there.
##
## `origin` is where `img` sits in page coordinates. Returns how many pixels
## were removed, so a caller can tell the difference between a fill that was
## trimmed and one that was entirely outside.
static func clip_to_panel(sheet: ComicPage, panel: int, img: Image,
		origin: Vector2) -> int:
	if sheet == null or img == null:
		return 0
	if panel < 0 or panel >= sheet.panels.size() or not sheet.confine:
		return 0

	# The panel's own box first. Most of a filled region is usually well
	# inside or well outside it, and a rectangle test is far cheaper than a
	# polygon one.
	var poly: PackedVector2Array = sheet.panels[panel]
	if poly.size() < 3:
		return 0
	var lo: Vector2 = poly[0]
	var hi: Vector2 = poly[0]
	for v in poly:
		lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
		hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))

	var removed: int = 0
	var w: int = img.get_width()
	var h: int = img.get_height()
	for y in h:
		var py: float = origin.y + float(y) + 0.5
		var row_outside: bool = py < lo.y or py > hi.y
		for x in w:
			if img.get_pixel(x, y).a <= 0.0:
				continue
			var px: float = origin.x + float(x) + 0.5
			var out: bool = row_outside or px < lo.x or px > hi.x
			if not out:
				out = not sheet.point_in_panel(panel, Vector2(px, py))
			if out:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				removed += 1
	return removed

## Whether this tool is one the panel edge stops.
##
## Everything that lays ink by hand is stopped: the brush, the eraser, the
## fill, the shapes, the blend. What is not stopped is not listed here because
## it never reaches this code at all — text is placed by its own room and an
## imported image by the import path, and neither goes through the dab or the
## flood. That is the exemption you asked for, and it is structural rather
## than a rule that could be got wrong: there is no line to forget to write.
##
## The three that do pass through here and must not be confined are the ones
## that lay no ink: picking a colour, selecting, and moving what is already
## drawn. A selection dragged out of a panel is a decision the artist can see
## and undo; a stroke that silently stops halfway is not.
static func tool_is_confined(tool_id: int) -> bool:
	if tool_id == App.Tool.PICK:
		return false
	if tool_id == App.Tool.SELECT:
		return false
	if tool_id == App.Tool.MOVE:
		return false
	return true
