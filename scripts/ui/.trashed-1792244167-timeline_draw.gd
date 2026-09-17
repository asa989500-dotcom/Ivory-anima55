class_name TimelineDraw
extends RefCounted
## Everything the timeline puts on the screen, and nothing else.
##
## Lifted out of `timeline_panel.gd` whole. Not one line of the drawing was
## rewritten in the move: the functions arrived exactly as they were, with
## every reference to the panel's own state made explicit through `p`. That
## was the point — a split that also rewrites is a split whose bugs nobody can
## tell apart from the rewrite's bugs, and this file exists because of a build
## that did exactly that.
##
## The panel keeps a one-line delegate for each of these, so no caller of
## `_draw_rows` or `_unit_rect` anywhere had to change, and the drawing is
## still reached the same way `_body.draw.connect(_draw_body)` always reached
## it.
##
## The move was done by `tools/lift_module.py` and checked by
## `tools/check_references.py`, which now resolves every `Class.member` in the
## project against what that class actually has. That pair is the real answer
## to "I deleted something and missed a reader of it": the reader is now found
## by a machine on every build rather than by a user on a tablet.
##
## Why the drawing and not something else: it was the largest part of the file
## with the fewest ties to the rest of it. Every function here had exactly one
## caller, and all of them were each other.
##
## `p.` everywhere reads as noise at first. It is worth it — it is the only
## reason the compiler can tell you when a field this file leans on stops
## existing.

## The whole band, and the four parts of it, timed separately.
##
## "The timeline is slow" has been on the list for four builds without a
## single measurement behind it, so there was no way to tell a slow ruler from
## slow rows from slow units — and they are entirely different problems. Each
## now reports under its own name, and `Perf.report()` prints the four side by
## side with their peaks. Five clock reads a frame against work measured in
## milliseconds: the measurement cannot be what makes it slow.
static func draw_body(p: TimelinePanel) -> void:
	if p.clip == null or p._body == null or p.stack == null:
		return
	var whole: int = Time.get_ticks_usec()
	var grid: Rect2 = p.grid_rect()
	p._body.draw_rect(Rect2(Vector2.ZERO, p._body.size), Color("#181a20"), true)
	p._body.draw_rect(Rect2(0.0, 0.0, UiKit.s(p.TREE_W), p._body.size.y),
		Color("#1e2129"), true)

	var part: int = Time.get_ticks_usec()
	p._draw_ruler(grid)
	Perf.since("timeline_ruler", part)

	part = Time.get_ticks_usec()
	p._draw_rows(grid)
	Perf.since("timeline_rows", part)

	part = Time.get_ticks_usec()
	p._draw_units(grid)
	Perf.since("timeline_units", part)

	p._draw_playhead(grid)
	Perf.since("timeline_draw", whole)

## Seconds along the top, counted the way the scene actually runs.
##
## It used to mark every frame divisible by the scene's rate, which was right
## while every frame lasted the same length of time. A frame-rate unit breaks
## that: six frames held at two a second are three seconds on their own, and a
## ruler still counting in twenty-fours would put the four-second mark
## somewhere no clock agrees with.
##
## So a mark is made where a new whole second *begins* — asked of the clip,
## which knows what every stretch of the band costs. Inside a slowed unit the
## marks spread out and inside a quickened one they crowd together, which is
## the plainest possible statement of what a unit does.
static func draw_ruler(p: TimelinePanel, grid: Rect2) -> void:
	var f: Font = ThemeDB.fallback_font
	var h: float = UiKit.s(p.RULER_H)
	p._body.draw_rect(Rect2(grid.position.x, 0.0, grid.size.x, h),
		Color("#20242c"), true)

	var span: Vector2i = p._visible_frames()
	var right: float = grid.position.x + grid.size.x
	# The second the frame before the first visible one falls in, so the very
	# first mark on screen is judged against its true neighbour rather than
	# against nothing.
	var before: int = int(floor(p.clip.time_of(maxi(span.x - 1, 0)) + 0.000001))
	for i in range(span.x, span.y + 1):
		var x: float = p.x_of(float(i))
		if x < grid.position.x - 2.0 or x > right:
			continue
		var mark: int = int(floor(p.clip.time_of(i) + 0.000001))
		var second: bool = mark > before or (i == 0 and mark == 0)
		before = maxi(before, mark)
		var col: Color = Color("#6c7385") if second else Color("#333846")
		p._body.draw_line(Vector2(x, h * (0.35 if second else 0.6)),
			Vector2(x, h), col, 1.0)
		if second and f != null and p.frame_w >= 5.0:
			p._body.draw_string(f, Vector2(x + UiKit.s(3.0), UiKit.s(12.0)),
				Lang.digits("%ds" % mark), HORIZONTAL_ALIGNMENT_LEFT, -1,
				int(UiKit.s(9.0)), Color("#7c8394"))

	# A unit is marked on the ruler as well as on the band, because the ruler
	# is where the consequence of it shows: this is the stretch whose seconds
	# are not the scene's seconds.
	for u in p.clip.units:
		var one: Anim.Unit = u
		var x0: float = maxf(p.x_of(float(one.from_frame)), grid.position.x)
		var x1: float = minf(p.x_of(float(one.to_frame + 1)), right)
		if x1 <= x0:
			continue
		p._body.draw_line(Vector2(x0, h - UiKit.s(1.5)),
			Vector2(x1, h - UiKit.s(1.5)), p.UNIT_EDGE, UiKit.s(2.4))

static func draw_rows(p: TimelinePanel, grid: Rect2) -> void:
	var f: Font = ThemeDB.fallback_font
	var top: float = UiKit.s(p.RULER_H)
	for entry in p._rows:
		var y: float = top + float(entry["y"]) - p.scroll_y
		var tall: float = p._row_height(entry)
		if y > p._body.size.y or y + tall < top:
			continue

		if String(entry["kind"]) == "group":
			p._draw_group_row(entry, grid, y, f)
			continue

		var camera: bool = entry["kind"] == "camera"
		var title: String = Lang.t("Camera") if camera \
			else (entry["layer"] as LayerStack.Layer).title
		var selected: bool = not camera \
			and int(entry["index"]) == p.stack.active_index

		# A row that is currently out of focus is dimmed here too, so the
		# band and the canvas agree about what is being looked at without
		# having to check one against the other.
		var sharp: float = 1.0
		if not camera:
			var lid: int = (entry["layer"] as LayerStack.Layer).id
			if p.stack.focus_sharpness.has(lid):
				sharp = float(p.stack.focus_sharpness[lid])
		if sharp < 0.995:
			p._body.draw_rect(Rect2(0.0, y, p._body.size.x, UiKit.s(p.ROW_H)),
				Color(0.03, 0.04, 0.06, (1.0 - sharp) * 0.42), true)

		if selected:
			p._body.draw_rect(Rect2(0.0, y, p._body.size.x, UiKit.s(p.ROW_H)),
				Color(1.0, 1.0, 1.0, 0.05), true)
		if f != null:
			p._body.draw_string(f, Vector2(UiKit.s(12.0), y + UiKit.s(19.0)),
				title, HORIZONTAL_ALIGNMENT_LEFT,
				UiKit.s(p.TREE_W) - UiKit.s(18.0), int(UiKit.s(11.0)),
				Color("#dfe2ea") if selected else Color("#a8adba"))

		if camera:
			p._draw_camera_row(grid, y)
		else:
			p._draw_cel_row(entry["layer"], grid, y)
			p._draw_focus_row(entry["layer"], grid, y)
		p._body.draw_line(Vector2(0.0, y + UiKit.s(p.ROW_H)),
			Vector2(p._body.size.x, y + UiKit.s(p.ROW_H)), Color("#242833"), 1.0)

	p._body.draw_line(Vector2(grid.position.x, 0.0),
		Vector2(grid.position.x, p._body.size.y), Color("#333846"), 1.5)

## A folder, in the band. It holds no drawings of its own, so it carries no
## track — it is here to say where in the stack the rows below it sit.
static func draw_group_row(p: TimelinePanel, entry: Dictionary, grid: Rect2, y: float, f: Font) -> void:
	var g: LayerStack.Group = p.stack.group_by_id(int(entry["gid"]))
	if g == null:
		return
	var tall: float = UiKit.s(p.GROUP_H)
	p._body.draw_rect(Rect2(0.0, y, p._body.size.x, tall), Color("#2e333d"), true)
	var animation: bool = g.is_animation
	if f != null:
		var mark: String = "▾ " if not g.collapsed else "▸ "
		# Not `name`: every Node already has one, and a local of that name
		# quietly shadows it. Harmless here, but the kind of shadow that
		# eventually has somebody debugging why setting a title renamed a
		# node.
		var caption: String = mark + g.title
		if animation:
			# An animation folder is a different kind of thing from a plain
			# one, and the band says so rather than leaving it to be found out
			# by pressing something and watching nothing happen.
			caption += "  ·  " + Lang.t("Animation layer")
		p._body.draw_string(f, Vector2(UiKit.s(10.0), y + tall * 0.68), caption,
			HORIZONTAL_ALIGNMENT_LEFT, UiKit.s(p.TREE_W) - UiKit.s(14.0),
			int(UiKit.s(11.0)),
			Color("#e8d5a3") if animation else Color("#c3c8d4"))
	if animation:
		p._body.draw_line(Vector2(grid.position.x, y + tall * 0.5),
			Vector2(minf(p.x_of(float(p._reach + 1)),
				grid.position.x + grid.size.x), y + tall * 0.5),
			Color(0.85, 0.75, 0.55, 0.35), UiKit.s(2.0))
	p._body.draw_line(Vector2(0.0, y + tall), Vector2(p._body.size.x, y + tall),
		Color("#242833"), 1.0)

static func draw_cel_row(p: TimelinePanel, l: LayerStack.Layer, grid: Rect2, y: float) -> void:
	var mid: float = y + UiKit.s(p.ROW_H) * 0.5
	var ink: Color = Color("#d24b4b")
	# The line stops where the scene stops. The band itself is endless, but
	# drawing a layer's line off into an endless empty grid would say the
	# layer goes on forever, which is the one thing it does not do.
	var end: float = minf(p.x_of(float(p._reach + 1)),
		grid.position.x + grid.size.x)
	p._body.draw_line(Vector2(grid.position.x, mid), Vector2(end, mid),
		Color(ink.r, ink.g, ink.b, 0.55), UiKit.s(1.6))

	var showing: int = l.cels.frame_showing(int(round(p.player.frame)))
	var frames: Array = l.cels.frames()
	var right: float = grid.position.x + grid.size.x + 8.0
	# Start at the first drawing the eye can actually reach rather than at
	# frame zero. Scrolling out to frame four hundred used to mean stepping
	# over four hundred invisible drawings on every redraw of every layer;
	# the list is sorted, so where to begin is a binary search. One back from
	# there, because the drawing before the window may still be holding into
	# it and its bar has to be drawn.
	var start: int = maxi(l.cels.index_at_or_after(p._view_lo()) - 1, 0)
	for i in range(start, frames.size()):
		var one: int = int(frames[i])
		# The hold runs to the next drawing, and the next drawing is the next
		# item — no search needed while walking the list in order.
		var next: int = int(frames[i + 1]) if i + 1 < frames.size() \
			else p._reach + 1
		var held: int = maxi(next - one, 1)
		var x0: float = p.x_of(float(one))
		var x1: float = p.x_of(float(one + held))
		if x0 > right:
			# The list is in frame order, so once one drawing starts past
			# the right edge every drawing after it does too.
			break
		if x1 < grid.position.x - 8.0:
			continue

		# A drawing is not an instant: it holds until the next one. Drawn as
		# a bar reaching that far, its duration can be read without counting
		# squares, and a long hold is obvious at a glance.
		var filled: bool = not (l.cels.cels[one]["png"] as PackedByteArray).is_empty()
		var bar: Rect2 = Rect2(x0 + UiKit.s(1.5), mid - UiKit.s(6.0),
			maxf(x1 - x0 - UiKit.s(3.0), UiKit.s(4.0)), UiKit.s(12.0))
		var body_ink: Color = Color(ink.r, ink.g, ink.b, 0.30 if filled else 0.12)
		p._body.draw_rect(bar, body_ink, true)

		var r: float = UiKit.s(5.5)
		if one == showing:
			# The drawing on screen right now gets a ring, so the eye finds
			# it without counting along the row.
			p._body.draw_circle(Vector2(x0, mid), r + UiKit.s(2.5),
				Color(1.0, 1.0, 1.0, 0.9))
		p._body.draw_circle(Vector2(x0, mid), r, ink if filled else Color("#5a3030"))

		# The grip that lengthens the hold, shown only when it is reachable.
		if bar.size.x > UiKit.s(20.0):
			p._body.draw_line(Vector2(x1 - UiKit.s(2.5), mid - UiKit.s(5.0)),
				Vector2(x1 - UiKit.s(2.5), mid + UiKit.s(5.0)),
				Color(ink.r, ink.g, ink.b, 0.75), UiKit.s(2.0))

## The camera's line is blue, and that is the only thing that tells it apart
## — it is a row like any other, which is what makes it easy to reach.
##
## Between two keys the line thickens into a bar, because that stretch is
## not empty: it is the move, filled in frame by frame from the poses at
## either end. A cut carries no bar, since nothing travels across it.
static func draw_camera_row(p: TimelinePanel, grid: Rect2, y: float) -> void:
	var mid: float = y + UiKit.s(p.ROW_H) * 0.5
	var ink: Color = Color("#4f8ede")
	var right: float = grid.position.x + grid.size.x
	var end: float = minf(p.x_of(float(p._reach + 1)), right)
	p._body.draw_line(Vector2(grid.position.x, mid), Vector2(end, mid),
		Color(ink.r, ink.g, ink.b, 0.55), UiKit.s(1.6))

	# --- the moves ---
	for i in range(p.clip.shots.size() - 1):
		var a: Anim.Shot = p.clip.shots[i]
		var b: Anim.Shot = p.clip.shots[i + 1]
		if a.ease_mode == Anim.Ease.HOLD:
			continue
		var x0: float = p.x_of(float(a.frame))
		var x1: float = p.x_of(float(b.frame))
		if x1 < grid.position.x - 8.0:
			continue
		if x0 > right + 8.0:
			break
		var travel: Rect2 = Rect2(x0, mid - UiKit.s(3.5),
			maxf(x1 - x0, UiKit.s(2.0)), UiKit.s(7.0))
		p._body.draw_rect(travel, Color(ink.r, ink.g, ink.b, 0.34), true)
		# Whether the move is holding still, building or settling is read
		# off the shape of the bar rather than by opening the key.
		var lead: float = p._ease_lead(a.ease_mode)
		if lead > 0.0 and travel.size.x > UiKit.s(14.0):
			p._body.draw_rect(Rect2(travel.position.x, mid - UiKit.s(1.5),
				travel.size.x * lead, UiKit.s(3.0)),
				Color(ink.r, ink.g, ink.b, 0.62), true)

	# --- the keys ---
	for sh in p.clip.shots:
		var shot: Anim.Shot = sh
		var x: float = p.x_of(float(shot.frame))
		if x < grid.position.x - 8.0 or x > right + 8.0:
			continue
		if shot.frame == p._last_key_frame:
			p._body.draw_circle(Vector2(x, mid), UiKit.s(8.0),
				Color(1.0, 1.0, 1.0, 0.85))
		if shot.ease_mode == Anim.Ease.HOLD:
			# A held shot is square, so a cut reads differently from a move
			# without having to be tapped to find out.
			p._body.draw_rect(Rect2(x - UiKit.s(4.5), mid - UiKit.s(4.5),
				UiKit.s(9.0), UiKit.s(9.0)), ink, true)
		else:
			p._body.draw_circle(Vector2(x, mid), UiKit.s(5.5), ink)

## Where the speed of a move sits: nothing for an even one, weighted to the
## far end for a build, to the near end for a settle.
## Takes no panel: the answer depends only on which kind of ease it is asked
## about. The lift handed it one, which Godot then reported as a parameter
## that is never used.
static func ease_lead(mode: int) -> float:
	if mode == Anim.Ease.IN:
		return 0.34
	if mode == Anim.Ease.OUT:
		return 0.72
	if mode == Anim.Ease.SMOOTH:
		return 0.5
	return 0.0

static func draw_playhead(p: TimelinePanel, grid: Rect2) -> void:
	if p.player == null:
		return
	var x: float = p.x_of(p.player.frame)
	if x < grid.position.x or x > grid.position.x + grid.size.x:
		return
	var glow: Color = UiKit.ACCENT
	p._body.draw_line(Vector2(x, 0.0), Vector2(x, p._body.size.y),
		Color(glow.r, glow.g, glow.b, 0.35), UiKit.s(4.0))
	p._body.draw_line(Vector2(x, 0.0), Vector2(x, p._body.size.y), glow, UiKit.s(1.4))
	var r: float = UiKit.s(7.0)
	p._body.draw_colored_polygon(PackedVector2Array([
		Vector2(x, r * 2.0), Vector2(x + r, r), Vector2(x, 0.0),
		Vector2(x - r, r)]), glow)

## The plate a unit is drawn on. Made once and kept, because `_draw` runs on
## every frame of playback and a new StyleBox each time would be rubbish for
## the collector to clear up sixty times a second.
static func unit_style(p: TimelinePanel) -> StyleBoxFlat:
	if p._unit_plate != null:
		return p._unit_plate
	p._unit_plate = StyleBoxFlat.new()
	p._unit_plate.bg_color = p.UNIT_FILL
	p._unit_plate.border_color = p.UNIT_EDGE
	p._unit_plate.set_border_width_all(int(maxf(UiKit.s(1.6), 1.0)))
	p._unit_plate.set_corner_radius_all(int(UiKit.s(8.0)))
	return p._unit_plate

## Where a unit sits on screen: from its first frame to just past its last,
## and the full height of the band under the ruler.
##
## The full height on purpose. A unit is not a property of one layer — it is a
## stretch of *time*, and everything in the scene passes through it at the same
## rate. Drawn on one row it would read as belonging to that row, and the first
## thing anybody would try is putting a different rate on the layer below.
static func unit_rect(p: TimelinePanel, one: Anim.Unit) -> Rect2:
	var top: float = UiKit.s(p.RULER_H)
	var tall: float = maxf(p._body.size.y - top, 1.0)
	var x0: float = p.x_of(float(one.from_frame))
	var x1: float = p.x_of(float(one.to_frame + 1))
	return Rect2(x0, top, maxf(x1 - x0, UiKit.s(2.0)), tall)

static func draw_units(p: TimelinePanel, grid: Rect2) -> void:
	if p.clip.units.is_empty():
		return
	var f: Font = ThemeDB.fallback_font
	var right: float = grid.position.x + grid.size.x
	var lowest: int = p._view_lo()
	for u in p.clip.units:
		var one: Anim.Unit = u
		var box: Rect2 = p._unit_rect(one)
		if box.position.x > right + 30.0 \
				or box.position.x + box.size.x < grid.position.x - 30.0:
			continue

		# Cut to the grid so a unit scrolled half off the left never paints
		# over the column of layer names.
		var lo: float = maxf(box.position.x, grid.position.x)
		var hi: float = minf(box.position.x + box.size.x, right)
		if hi > lo:
			p._body.draw_style_box(p._unit_style(),
				Rect2(lo, box.position.y, hi - lo, box.size.y))

		var mid: float = box.position.y + box.size.y * 0.5
		# What the unit is, written on it: the rate, how many frames, and what
		# that comes to in seconds. The last of the three is the answer to the
		# question a unit is made to ask, so it is never the one left out.
		if f != null and hi - lo > UiKit.s(58.0):
			var caption: String = Lang.digits("%d fps · %d f · %.2fs"
				% [one.fps, one.count(), one.seconds()])
			p._body.draw_string(f, Vector2(lo + UiKit.s(7.0),
				box.position.y + UiKit.s(13.0)), caption,
				HORIZONTAL_ALIGNMENT_LEFT, hi - lo - UiKit.s(10.0),
				int(UiKit.s(9.5)), p.UNIT_INK)

		var held: bool = one == p._drag_unit or one == p._press_unit
		# The right grip always. The left one only when there is something on
		# its left to give ground — at the first frame of the band there is
		# nothing before it, and an arrow pointing at nothing is a promise the
		# app cannot keep.
		var far: float = box.position.x + box.size.x
		if far >= grid.position.x and far <= right:
			p._draw_unit_grip(Vector2(far, mid), 1, held and p._drag_unit_side > 0)
		if one.from_frame > lowest and box.position.x >= grid.position.x \
				and box.position.x <= right:
			p._draw_unit_grip(Vector2(box.position.x, mid), -1,
				held and p._drag_unit_side < 0)

## One arrow, on the edge it belongs to.
##
## A disc with a chevron in it and two short trailing strokes: round so it
## reads as something to take hold of rather than as part of the drawing, and
## trailing so which way it wants to be pulled is obvious before it is touched.
static func draw_unit_grip(p: TimelinePanel, at: Vector2, way: int, lit: bool) -> void:
	var r: float = UiKit.s(p.GRIP_R)
	var back: Color = Color(0.086, 0.094, 0.118, 0.90)
	p._body.draw_circle(at, r, back)
	p._body.draw_arc(at, r, 0.0, TAU, 22,
		p.UNIT_INK if lit else p.UNIT_EDGE, UiKit.s(1.6))

	var side: float = float(way)
	var w: float = UiKit.s(4.0)
	var h: float = UiKit.s(5.2)
	p._body.draw_colored_polygon(PackedVector2Array([
		at + Vector2(side * w * 1.05, 0.0),
		at + Vector2(-side * w * 0.55, -h),
		at + Vector2(-side * w * 0.55, h)]), p.UNIT_INK)
	# The two strokes behind it, fading away from the point, so the arrow
	# looks like it is already moving in the direction it can be moved.
	for i in 2:
		var away: float = w * 1.5 + float(i) * UiKit.s(3.0)
		var fade: float = 0.55 - float(i) * 0.22
		p._body.draw_line(at + Vector2(-side * away, -h * 0.55),
			at + Vector2(-side * away, h * 0.55),
			Color(p.UNIT_INK.r, p.UNIT_INK.g, p.UNIT_INK.b, fade), UiKit.s(1.3))

## The focus line for a layer, drawn just above its own line so the two read
## as belonging together without ever being mistaken for each other.
static func draw_focus_row(p: TimelinePanel, l: LayerStack.Layer, grid: Rect2, y: float) -> void:
	var spans: Array = p.clip.focus_for(l.id)
	if spans.is_empty():
		return
	var lift: float = y + UiKit.s(p.ROW_H) * 0.5 - UiKit.s(7.0)
	var right: float = grid.position.x + grid.size.x
	var gold: Color = Color("#E8C46A")
	for f in spans:
		var one: Anim.Focus = f as Anim.Focus
		var x0: float = p.x_of(float(one.from_frame))
		var x1: float = p.x_of(float(one.to_frame))
		if x1 < grid.position.x - 10.0 or x0 > right + 10.0:
			continue
		p._body.draw_line(Vector2(x0, lift), Vector2(x1, lift),
			Color(gold.r, gold.g, gold.b, 0.75), UiKit.s(3.0))
		if one.mode == Anim.Blur.CINEMATIC:
			# The quarter over which the pull arrives, drawn as the part of
			# the line that is still thickening.
			var quarter: float = x0 + (x1 - x0) * 0.25
			p._body.draw_line(Vector2(x0, lift), Vector2(quarter, lift),
				Color(gold.r, gold.g, gold.b, 0.35), UiKit.s(6.0))
		p._body.draw_circle(Vector2(x0, lift), UiKit.s(4.5), gold)
		if one.mode == Anim.Blur.HARD:
			p._body.draw_rect(Rect2(x1 - UiKit.s(4.5), lift - UiKit.s(4.5),
				UiKit.s(9.0), UiKit.s(9.0)), gold, true)
		else:
			p._body.draw_circle(Vector2(x1, lift), UiKit.s(5.5), gold)
			p._body.draw_arc(Vector2(x1, lift), UiKit.s(5.5), 0.0, TAU, 16,
				Color("#FFF8E7"), UiKit.s(1.4))
