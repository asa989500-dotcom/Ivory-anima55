class_name Anim
extends RefCounted
## The animation, as data only.
##
## Two things move: the drawings, and the camera. The drawings are held by
## each layer as frames — see CelTrack — and the camera is here, because it
## belongs to the clip rather than to any layer.
##
## Deliberately small. Everything that used to live here to serve bones and
## warps is gone, and what is left is what an animator on a tablet actually
## reaches for: how fast it plays, how long it runs, and where the camera is
## looking at each moment.

## How a camera key hands over to the next one.
##
## The numbers are written into saved files, so new modes are appended
## rather than inserted — an old scene keeps meaning what it meant.
##   SMOOTH  eased at both ends: starts, travels, arrives
##   LINEAR  one speed the whole way
##   HOLD    no travel at all — the shot cuts to the next key
##   IN      starts slowly and builds
##   OUT     starts at speed and settles
enum Ease { SMOOTH, LINEAR, HOLD, IN, OUT }

class Shot:
	var frame: int = 0
	## Where the camera looks, measured from the middle of the page.
	var offset: Vector2 = Vector2.ZERO
	## How much of the page it keeps. Above one is closer in.
	var zoom: float = 1.0
	var rotation: float = 0.0
	var ease_mode: int = Ease.SMOOTH

## How much room a brand-new scene opens with. Not a limit — the scene grows
## past it the moment a drawing is put beyond it.
const OPENING_FRAMES: int = 48
## The furthest the band will ever run. Not a creative limit — five hours at
## twenty-four frames a second — but arithmetic has to stop somewhere, and a
## number that cannot be reached by hand is a better place to stop than the
## first overflow.
const CEILING_FRAMES: int = 432000

## A stretch of time in which one layer is the one in focus.
##
## Depth of field, as a camera does it: choosing what is sharp is the same act
## as choosing what is not. So a focus line is put on the layer that should be
## sharp, and everything without one goes soft for as long as that line runs.
class Focus:
	var layer_id: int = 0
	var from_frame: int = 0
	var to_frame: int = 2
	## How the softness arrives.
	##   HARD      full blur for the whole stretch, no build-up
	##   CINEMATIC blur comes on over the first quarter of the stretch, the
	##             way a focus pull settles
	var mode: int = Blur.CINEMATIC
	## How far out of focus the rest of the scene goes.
	var strength: float = 1.0
	## How many blades the iris has while this line is running.
	##
	## Nought is a perfect disc — a wide-open lens, or a computer-generated
	## one. Six is what most photographic lenses give, and it is what makes an
	## out-of-focus highlight a small hexagon rather than a circle. It lives on
	## the focus line rather than on the layer because one camera is looking at
	## the whole scene: two layers softened through two different irises in the
	## same frame would be two cameras.
	var blades: int = 6

enum Blur { HARD, CINEMATIC }

## A stretch of frames that runs at its own rate.
##
## "Dividing the frame rate into units": the scene has one rate, and inside a
## unit a chosen run of frames plays at another. Six frames at two a second
## take three seconds; the same six at sixty take a tenth of one. The frames
## themselves do not move and nothing is added or removed — only how long each
## of them is held.
##
## That is the whole point, and it is what makes this different from adding
## copies of a drawing to slow it down: the band does not get longer, the
## drawings keep their numbers, and everything after the unit simply happens
## later or sooner in time.
##
## Units never overlap. Two rates over one frame is not a thing that can be
## drawn or played, so the arithmetic that places and resizes them refuses it
## rather than picking a winner.
class Unit:
	## Both ends are inclusive: a unit from 4 to 9 holds six frames.
	var from_frame: int = 0
	var to_frame: int = 0
	var fps: int = 12

	func count() -> int:
		return maxi(to_frame - from_frame + 1, 1)

	## How long this unit lasts, in seconds.
	func seconds() -> float:
		return float(count()) / float(clampi(fps, MIN_UNIT_FPS, MAX_UNIT_FPS))

	func holds(frame: int) -> bool:
		return frame >= from_frame and frame <= to_frame

## The slowest and fastest a unit may run.
##
## Two a second is the slowest anything reads as movement rather than as a
## slideshow; sixty is the fastest any screen this app runs on can show. Both
## ends are asked for, and neither is a number the arithmetic needs — they are
## there so a mistyped rate cannot make a scene that never ends.
const MIN_UNIT_FPS: int = 2
const MAX_UNIT_FPS: int = 60

## How many frames a newly made unit covers before it is dragged out.
const UNIT_OPENING: int = 4

## A moment at which a switch folder changes which member it shows.
##
## It lives in the clip rather than on the folder for the same reason the
## camera does: it is a fact about *timing*, and timing belongs to the scene.
## Copy a mouth chart into another scene and it arrives without the dialogue
## it was mouthing, which is right.
##
## There is no ease mode here, and that is deliberate rather than unfinished.
## A mouth is open or closed; there is no frame on which it is thirty per cent
## of the way to an F. Every other key in this file blends and this one steps,
## because the thing it describes steps.
class Swap:
	var group_id: int = 0
	var frame: int = 0
	var index: int = 0

class Clip:
	var fps: int = 24
	## How far the scene runs *so far*. It is never a wall: it grows to fit
	## whatever is drawn, and playback and export read the work rather than
	## this number.
	var length: int = OPENING_FRAMES
	## Where playback starts and stops. Both -1 means the whole scene, which
	## is what a new project wants; set them and only that stretch plays, so
	## a run of six frames in the middle of a long scene can be watched
	## without sitting through everything in front of it.
	var play_from: int = -1
	var play_to: int = -1
	## Which stretch of the band is *shown*. Separate from `play_from` and
	## `play_to` on purpose: one decides what you are looking at, the other
	## decides what plays, and an animator wants to narrow the first far more
	## often than the second.
	##
	## `view_to` of -1 means no end at all — the band runs forward for as long
	## as there is anywhere to go, which is what an endless timeline is.
	var view_from: int = 0
	var view_to: int = -1
	## How far the last drawing has deliberately been held.
	##
	## A hold dragged out past the last drawing is real work with nothing in
	## it: no cel sits at its far end, so nothing else in the file remembers
	## it happened. Without this, working out where a scene ends from its
	## contents would cut every trailing hold off at the drawing it started
	## from.
	var tail_hold: int = 0
	## Frame-rate units, always kept in frame order and never overlapping.
	var units: Array = []
	## The focus lines, one or more per layer.
	var focus: Array = []
	## Camera keys, always kept in frame order.
	var shots: Array[Shot] = []
	## Switch-folder changes, likewise in frame order.
	var swaps: Array = []
	## Whether this scene has a camera at all.
	##
	## A camera is something you add to a scene, not something every scene
	## is born with. Until it is added there is no camera row on the
	## timeline, no keys to reach by accident, and playback simply shows
	## the page — which is what a scene without a camera means.
	var camera_on: bool = false
	## The scene's sounds: music, effects, anything that plays. Held on the
	## clip rather than on a layer because a scene is what gets exported, and
	## an export mixes every sound in it at once. See AudioTrack.
	var audio: AudioTrack = AudioTrack.new()

	# ------------------------------------------------------------ switching

	## Which member a chart shows at a moment: the last change at or before
	## this frame. Before the first change it shows whatever the folder was
	## left showing, which is what `fallback` carries.
	##
	## A step, walked backwards from the end, so the common case — playback
	## asking about a frame near the last change — answers on its first
	## comparison.
	func swap_at(group_id: int, frame: int, fallback: int) -> int:
		var best: int = -1
		var found: int = fallback
		for s in swaps:
			var one: Swap = s
			if one.group_id != group_id or one.frame > frame:
				continue
			if one.frame > best:
				best = one.frame
				found = one.index
		return found

	func set_swap(group_id: int, frame: int, index: int) -> Swap:
		for s in swaps:
			var one: Swap = s
			if one.group_id == group_id and one.frame == frame:
				one.index = index
				return one
		var made: Swap = Swap.new()
		made.group_id = group_id
		made.frame = maxi(frame, 0)
		made.index = index
		swaps.append(made)
		swaps.sort_custom(func(a, b): return (a as Swap).frame < (b as Swap).frame)
		return made

	func clear_swap(group_id: int, frame: int) -> void:
		for i in swaps.size():
			var one: Swap = swaps[i]
			if one.group_id == group_id and one.frame == frame:
				swaps.remove_at(i)
				return

	func swaps_for(group_id: int) -> Array:
		var out: Array = []
		for s in swaps:
			if (s as Swap).group_id == group_id:
				out.append(s)
		return out

	## Forgets every change belonging to a folder that no longer exists.
	## Called after a folder is dissolved, so its keys do not sit in the file
	## for the rest of the project's life waiting for an id that will never
	## come back.
	func drop_swaps_for(group_id: int) -> void:
		var kept: Array = []
		for s in swaps:
			if (s as Swap).group_id != group_id:
				kept.append(s)
		swaps = kept

	# ---------------------------------------------------------- rate units

	## Named rather than written inline as a lambda.
	##
	## The inline version was two lines long, and a statement inside a lambda
	## body does not continue onto a second line the way an expression inside
	## brackets does — so the parser stopped at the `<`, the whole class
	## failed to build, and sixty-one errors were reported in eleven files
	## that had nothing wrong with them. A named method has no body to wrap.
	func sort_units() -> void:
		units.sort_custom(_unit_earlier)

	func _unit_earlier(a: Variant, b: Variant) -> bool:
		return (a as Unit).from_frame < (b as Unit).from_frame

	## The unit covering a frame, or null where the scene's own rate rules.
	func unit_at(frame: int) -> Unit:
		for u in units:
			var one: Unit = u
			if one.holds(frame):
				return one
		return null

	## How many frames a second are shown at this moment.
	func rate_at(frame: int) -> int:
		var one: Unit = unit_at(frame)
		if one != null:
			return clampi(one.fps, MIN_UNIT_FPS, MAX_UNIT_FPS)
		return clampi(fps, 1, MAX_UNIT_FPS)

	## The first frame at which the rate stops being the rate at `frame`.
	##
	## Playback walks the clock segment by segment rather than frame by frame,
	## so a long unit costs the same as a short one and a boundary crossed in
	## the middle of a rendered frame is crossed exactly rather than rounded.
	func segment_end(frame: int) -> int:
		var here: Unit = unit_at(frame)
		if here != null:
			return here.to_frame + 1
		var soonest: int = CEILING_FRAMES
		for u in units:
			var one: Unit = u
			if one.from_frame > frame:
				soonest = mini(soonest, one.from_frame)
		return soonest

	## Where a unit is free to reach: up to the neighbour on either side.
	##
	## Returned rather than enforced from inside the drag, so the timeline can
	## also *show* the room a unit has before a finger is put on it.
	func unit_room(one: Unit) -> Vector2i:
		var lo: int = 0
		var hi: int = CEILING_FRAMES - 1
		for u in units:
			var other: Unit = u
			if other == one:
				continue
			if other.to_frame < one.from_frame:
				lo = maxi(lo, other.to_frame + 1)
			elif other.from_frame > one.to_frame:
				hi = mini(hi, other.from_frame - 1)
		return Vector2i(lo, maxi(hi, lo))

	## Somewhere a new unit can go, at or after `frame`.
	##
	## A unit asked for on top of an existing one is placed immediately after
	## it instead — never over it, and never somewhere else on the band that
	## happened to be free. That is what "the new one starts where the old one
	## ends" means, and it is why this walks forward rather than searching.
	func free_slot(frame: int, want: int = UNIT_OPENING) -> Vector2i:
		var start: int = maxi(frame, 0)
		var need: int = maxi(want, 1)
		var guard: int = 0
		while guard < 64:
			guard += 1
			var here: Unit = unit_at(start)
			if here != null:
				start = here.to_frame + 1
				continue
			var cap: int = CEILING_FRAMES - 1
			for u in units:
				var one: Unit = u
				if one.from_frame > start:
					cap = mini(cap, one.from_frame - 1)
			if cap >= start:
				return Vector2i(start, mini(start + need - 1, cap))
			start += 1
		return Vector2i(start, start)

	func add_unit(from_frame: int, to_frame: int, rate: int) -> Unit:
		var one: Unit = Unit.new()
		one.from_frame = maxi(mini(from_frame, to_frame), 0)
		one.to_frame = maxi(from_frame, to_frame)
		one.fps = clampi(rate, MIN_UNIT_FPS, MAX_UNIT_FPS)
		units.append(one)
		sort_units()
		return one

	func drop_unit(one: Unit) -> void:
		units.erase(one)

	## Seconds from the start of the scene to the start of `frame`.
	##
	## Every frame outside a unit costs one over the scene's rate, and every
	## frame inside one costs one over that unit's rate. Summed per unit
	## rather than per frame, so asking about frame nine hundred costs the
	## same as asking about frame nine.
	func time_of(frame: int) -> float:
		var end: int = maxi(frame, 0)
		var base: float = float(clampi(fps, 1, MAX_UNIT_FPS))
		var whole: float = float(end) / base
		for u in units:
			var one: Unit = u
			var lo: int = maxi(one.from_frame, 0)
			var hi: int = mini(one.to_frame + 1, end)
			if hi <= lo:
				continue
			var run: float = float(hi - lo)
			whole += run / float(clampi(one.fps, MIN_UNIT_FPS, MAX_UNIT_FPS)) \
				- run / base
		return whole

	## How long a stretch of the band lasts, in seconds, units and all.
	func span_seconds(from_frame: int, to_frame: int) -> float:
		return maxf(time_of(to_frame + 1) - time_of(from_frame), 0.0)

	func shot_at(frame: int) -> Shot:
		for s in shots:
			if (s as Shot).frame == frame:
				return s
		return null

	func set_shot(frame: int, offset: Vector2, zoom: float,
			ease_mode: int = Ease.SMOOTH, rotation: float = 0.0) -> Shot:
		var s: Shot = shot_at(frame)
		if s == null:
			s = Shot.new()
			s.frame = frame
			shots.append(s)
			shots.sort_custom(func(a, b): return (a as Shot).frame < (b as Shot).frame)
		s.offset = offset
		s.zoom = maxf(zoom, 0.05)
		s.rotation = rotation
		s.ease_mode = ease_mode
		return s

	## Inserts one timing frame after `frame`, shifting camera keys at or
	## beyond the insertion point so drawing and camera timing remain aligned.
	func insert_frame_after(frame: int) -> void:
		var at: int = maxi(frame + 1, 0)
		for s in shots:
			var shot: Shot = s
			if shot.frame >= at:
				shot.frame += 1
		# Switch changes shift with everything else, or a syllable inserted
		# at the top of a scene silently slides every mouth shape one frame
		# out of step with the sound for the rest of the take.
		for w in swaps:
			var swap: Swap = w
			if swap.frame >= at:
				swap.frame += 1
		# A rate unit is a stretch of *these* frames, so it travels with them.
		# A unit that stays put while the drawings underneath it move is a
		# unit describing frames it was never put on.
		for u in units:
			var unit: Unit = u
			if unit.from_frame >= at:
				unit.from_frame += 1
				unit.to_frame += 1
			elif unit.to_frame >= at:
				# The frame lands inside the unit: the unit gets one frame
				# longer rather than being split in two.
				unit.to_frame += 1
		for f in focus:
			var one_f: Focus = f as Focus
			if one_f.from_frame >= at:
				one_f.from_frame += 1
			if one_f.to_frame >= at:
				one_f.to_frame += 1
		if tail_hold >= at:
			tail_hold += 1
		shots.sort_custom(func(a, b): return (a as Shot).frame < (b as Shot).frame)
		sort_units()
		length = clampi(length + 1, 1, CEILING_FRAMES)

	## The curve a key travels on, as a plain reshaping of 0..1.
	##
	## The whole in-betweening of a camera move is this one line and the
	## division that feeds it: everything between two keys is filled by
	## measuring how far along you are and bending that number.
	static func shape_ease(t: float, mode: int) -> float:
		var x: float = clampf(t, 0.0, 1.0)
		if mode == Ease.LINEAR:
			return x
		if mode == Ease.IN:
			# Slow to leave. The move builds instead of jumping into speed.
			return x * x
		if mode == Ease.OUT:
			# Quick to leave, slow to arrive — a shot settling into place.
			return 1.0 - (1.0 - x) * (1.0 - x)
		# SMOOTH, and anything a newer file might carry that this build
		# does not know: eased at both ends.
		return x * x * (3.0 - 2.0 * x)

	## The key that governs a moment, and the one after it. Used by the
	## timeline to draw the travel between keys as travel rather than as
	## two unrelated dots.
	func span_at(frame: int) -> Array:
		for i in range(shots.size() - 1):
			var a: Shot = shots[i]
			var b: Shot = shots[i + 1]
			if frame >= a.frame and frame < b.frame:
				return [a, b]
		return []

	## Whether anything at all is in focus at this moment. When nothing is,
	## nothing is blurred either — depth of field only means something once
	## something has been chosen to be sharp.
	func focus_live(frame: int) -> bool:
		for f in focus:
			var one: Focus = f as Focus
			if frame >= one.from_frame and frame <= one.to_frame:
				return true
		return false

	## How sharp a layer is at a moment: 0 is fully soft, 1 is fully sharp.
	##
	## A layer carrying a line that covers this frame is sharp. Everything
	## else softens, and how quickly depends on the line doing the softening —
	## which is the line the *sharp* layer holds, since that is the one that
	## says what kind of focus pull this is.
	func focus_at(layer_id: int, frame: int) -> float:
		var soft: float = 1.0
		var found: bool = false
		for f in focus:
			var one: Focus = f as Focus
			if frame < one.from_frame or frame > one.to_frame:
				continue
			found = true
			if one.layer_id == layer_id:
				# This layer is the subject. Nothing softens it.
				return 1.0
			var run: float = float(maxi(one.to_frame - one.from_frame, 1))
			var along: float = float(frame - one.from_frame) / run
			var amount: float = one.strength
			if one.mode == Blur.CINEMATIC:
				# The pull takes the first quarter of the stretch to arrive,
				# eased at both ends so it starts and settles rather than
				# ramping mechanically.
				var t: float = clampf(along / 0.25, 0.0, 1.0)
				amount *= t * t * (3.0 - 2.0 * t)
			soft = minf(soft, 1.0 - clampf(amount, 0.0, 1.0))
		if not found:
			return 1.0
		return soft

	## The iris in use at a moment: the one belonging to whichever focus line
	## is running. With none running there is nothing being softened, so the
	## answer only has to be harmless.
	func aperture_at(frame: int) -> int:
		for f in focus:
			var one: Focus = f as Focus
			if frame >= one.from_frame and frame <= one.to_frame:
				return clampi(one.blades, 0, 9)
		return 6

	func add_focus(layer_id: int, from_frame: int, to_frame: int) -> Focus:
		var one: Focus = Focus.new()
		one.layer_id = layer_id
		one.from_frame = mini(from_frame, to_frame)
		one.to_frame = maxi(from_frame, to_frame)
		focus.append(one)
		return one

	func focus_for(layer_id: int) -> Array:
		var out: Array = []
		for f in focus:
			if (f as Focus).layer_id == layer_id:
				out.append(f)
		return out

	func drop_focus(one: Focus) -> void:
		focus.erase(one)

	## How far the scene really goes: the last drawing, the last camera key,
	## or the far end of a hold dragged past both.
	##
	## `length` is not that number any more and cannot be. The band is endless
	## now, so scrubbing out to frame nine hundred to see whether there is
	## room grows `length` to nine hundred — and a scene that then played nine
	## hundred frames of nothing would have punished you for looking.
	func reach(stack: Variant) -> int:
		var ls: LayerStack = stack as LayerStack
		return maxi(maxi(last_event(ls), tail_hold), 0)

	## The stretch that actually plays, after the range has had its say.
	func play_span(stack: Variant) -> Vector2i:
		var last: int = maxi(reach(stack), 0)
		var from: int = 0 if play_from < 0 else clampi(play_from, 0, last)
		var to: int = last if play_to < 0 else clampi(play_to, 0, last)
		if to < from:
			var swap: int = from
			from = to
			to = swap
		return Vector2i(from, to)

	## The scene is as long as the work in it. Called whenever a drawing or a
	## camera key lands, so the band always has somewhere to put the next one
	## and never has to be stretched by hand.
	func grow_to_fit(stack: Variant, at_least: int = 0) -> void:
		# Not `reach`: this class already has a method by that name three
		# functions up, and a parameter that hides a method is a trap for
		# whoever next writes `reach(stack)` inside this body and gets an
		# integer back instead.
		var want: int = maxi(last_event(stack) + 1, at_least + 1)
		length = clampi(maxi(length, want), 1, CEILING_FRAMES)

	func drop_shot(frame: int) -> void:
		for i in range(shots.size() - 1, -1, -1):
			if (shots[i] as Shot).frame == frame:
				shots.remove_at(i)

	func has_camera() -> bool:
		return camera_on and not shots.is_empty()

	## Where the camera is at a moment, blended from the keys either side.
	##
	## Before the first key and after the last, the nearest one holds: a
	## camera should stay where it was put rather than drift back to some
	## default nobody chose.
	func camera_at(frame: float) -> Dictionary:
		# No camera in the scene means no camera to answer for. A scene whose
		# camera has been taken away must show the page, not the last shot
		# its keys happened to be left on.
		if not camera_on or shots.is_empty():
			return {}
		var first: Shot = shots[0]
		if frame <= float(first.frame) or shots.size() == 1:
			return {"offset": first.offset, "zoom": first.zoom, "rotation": first.rotation}
		var last: Shot = shots[shots.size() - 1]
		if frame >= float(last.frame):
			return {"offset": last.offset, "zoom": last.zoom, "rotation": last.rotation}

		for i in range(shots.size() - 1):
			var a: Shot = shots[i]
			var b: Shot = shots[i + 1]
			if frame < float(a.frame) or frame > float(b.frame):
				continue
			if a.ease_mode == Ease.HOLD:
				return {"offset": a.offset, "zoom": a.zoom, "rotation": a.rotation}
			var span: float = float(b.frame - a.frame)
			if span <= 0.0:
				return {"offset": b.offset, "zoom": b.zoom, "rotation": b.rotation}
			var t: float = (frame - float(a.frame)) / span
			t = shape_ease(t, a.ease_mode)
			return {
				"offset": a.offset.lerp(b.offset, t),
				"zoom": lerpf(a.zoom, b.zoom, t),
				"rotation": lerp_angle(a.rotation, b.rotation, t),
			}
		return {"offset": last.offset, "zoom": last.zoom, "rotation": last.rotation}

	## The last frame anything happens on, so playback and export know where
	## the clip really ends rather than trusting a number nobody updated.
	func last_event(stack: LayerStack) -> int:
		var last: int = 0
		for s in shots:
			last = maxi(last, (s as Shot).frame)
		for u in units:
			last = maxi(last, (u as Unit).to_frame)
		if stack != null:
			for l in stack.layers:
				# One question per layer rather than one per drawing: this is
				# asked while the scene is playing.
				last = maxi(last, l.cels.last_frame())
		return last

## The ease curve, reachable without knowing which inner class holds it.
## `RigTrack` blends its keys with exactly this, so a rig key eased SMOOTH and
## a camera key eased SMOOTH travel on the same curve — which is the whole
## point of the rig reusing `Ease` rather than inventing its own modes.
static func ease_shape(t: float, mode: int) -> float:
	return Clip.shape_ease(t, mode)

# ------------------------------------------------------------------ saving

static func to_dict(clip: Clip) -> Dictionary:
	var rows: Array = []
	for s in clip.shots:
		var one: Shot = s
		rows.append({"f": one.frame, "x": one.offset.x, "y": one.offset.y,
			"z": one.zoom, "r": one.rotation, "e": one.ease_mode})
	var focus_rows: Array = []
	for f in clip.focus:
		var one: Focus = f as Focus
		focus_rows.append({"layer": one.layer_id, "from": one.from_frame,
			"to": one.to_frame, "mode": one.mode, "strength": one.strength,
			"blades": one.blades})
	var swap_rows: Array = []
	for w in clip.swaps:
		var one_w: Swap = w as Swap
		swap_rows.append({"g": one_w.group_id, "f": one_w.frame,
			"i": one_w.index})
	var unit_rows: Array = []
	for u in clip.units:
		var one_u: Unit = u as Unit
		unit_rows.append({"from": one_u.from_frame, "to": one_u.to_frame,
			"fps": one_u.fps})
	return {"fps": clip.fps, "length": clip.length, "shots": rows,
		"camera_on": clip.camera_on, "focus": focus_rows, "swaps": swap_rows,
		"play_from": clip.play_from, "play_to": clip.play_to,
		"units": unit_rows, "view_from": clip.view_from,
		"view_to": clip.view_to, "tail_hold": clip.tail_hold,
		"audio": AudioTrack.to_dict(clip.audio)}

static func from_dict(doc: Dictionary) -> Clip:
	var clip: Clip = Clip.new()
	clip.fps = clampi(int(doc.get("fps", 24)), 1, 60)
	clip.length = clampi(int(doc.get("length", OPENING_FRAMES)), 1,
		CEILING_FRAMES)
	clip.play_from = int(doc.get("play_from", -1))
	clip.play_to = int(doc.get("play_to", -1))
	# Absent in every file written before units existed, which is why each of
	# these carries the value that means "as it was": no units, no view
	# window, no trailing hold.
	clip.view_from = maxi(int(doc.get("view_from", 0)), 0)
	clip.view_to = int(doc.get("view_to", -1))
	clip.tail_hold = maxi(int(doc.get("tail_hold", 0)), 0)
	# Absent in every file written before the scene could carry sound, which
	# reads as an empty track rather than as a fault.
	clip.audio = AudioTrack.from_dict(doc.get("audio", {}))
	for row in doc.get("units", []):
		var from_frame: int = maxi(int(row.get("from", 0)), 0)
		var to_frame: int = maxi(int(row.get("to", from_frame)), from_frame)
		# A file written by hand, or one that survived a crash mid-write, can
		# carry units that sit on top of each other. Two rates over one frame
		# has no meaning, so the later one is trimmed to start after the
		# earlier rather than being dropped or allowed to win.
		if clip.unit_at(from_frame) != null:
			continue
		var room: Vector2i = clip.free_slot(from_frame,
			to_frame - from_frame + 1)
		if room.y < room.x:
			continue
		clip.add_unit(room.x, room.y, int(row.get("fps", clip.fps)))
	for row in doc.get("focus", []):
		var one: Focus = clip.add_focus(int(row.get("layer", 0)),
			int(row.get("from", 0)), int(row.get("to", 2)))
		one.mode = int(row.get("mode", Blur.CINEMATIC))
		one.strength = float(row.get("strength", 1.0))
		one.blades = clampi(int(row.get("blades", 6)), 0, 9)
	# Scenes saved before the camera became something you add are read as
	# having one whenever they already carry keys.
	clip.camera_on = bool(doc.get("camera_on",
		not (doc.get("shots", []) as Array).is_empty()))
	for row in doc.get("swaps", []):
		clip.set_swap(int(row.get("g", 0)), int(row.get("f", 0)),
			maxi(int(row.get("i", 0)), 0))
	for row in doc.get("shots", []):
		clip.set_shot(int(row.get("f", 0)),
			Vector2(float(row.get("x", 0.0)), float(row.get("y", 0.0))),
			float(row.get("z", 1.0)), int(row.get("e", Ease.SMOOTH)),
			float(row.get("r", 0.0)))
	return clip
