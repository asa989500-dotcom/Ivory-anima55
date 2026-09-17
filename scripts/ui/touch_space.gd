class_name TouchSpace
extends RefCounted
## Where a finger may start a stroke, and where it may not.
##
## ## The problem this exists for
##
## The canvas fills the screen. Everything else — the tool rail, the layers
## panel, the timeline — floats on top of it. Godot already routes a press to
## the topmost control that accepts one, so a tap on a button is the button's
## and a tap on bare canvas is the canvas's, and that part has always worked.
##
## Two things it does not cover, and both of them reach the user as the drawing
## going wrong rather than as a mis-tap:
##
## **The system gesture strips.** Android reserves a band along the bottom of
## the screen for the navigation bar, and on gesture navigation it reserves a
## strip down each side for the back swipe. A stroke that *begins* inside one of
## those is not a stroke: a few events arrive, then the operating system decides
## the gesture was meant for it and takes the rest. What the app sees is a
## pointer that stops reporting. What the user sees is a line that cuts itself
## off partway. Nothing inside the app can win that argument once it has begun,
## so the only real answer is not to begin.
##
## **Buttons smaller than a fingertip.** A control whose touch box is smaller
## than about nine millimetres is a control that gets missed, and a miss on a
## floating panel goes straight through to the canvas underneath as a stroke.
## The mark that appears is not the user's mistake — it is the panel's.
##
## ## What it does not do
##
## It never interrupts a stroke already under way. A finger that starts on good
## canvas and wanders into the bottom strip keeps drawing: the operating system
## only claims a gesture it saw the *start* of, so once a stroke is running the
## strip is ordinary screen. Refusing mid-stroke would break long diagonals for
## no reason at all.

## How wide the side strips are, in device-independent pixels.
##
## Android's own back-gesture inset is 20 dp a side on most builds and can be
## set larger by the user. Twenty-four is that with a little margin: enough to
## cover the setting most people have, small enough that on a 400 dp wide phone
## it costs twelve per cent of the width and only for *starting* a stroke.
const SIDE_DP: float = 24.0

## How tall the bottom strip is when the system does not tell us.
##
## Only a fallback. The real number comes from the safe area below, which knows
## about the navigation bar this device actually has; this is what gets used on
## a platform that reports nothing, where the gesture bar is the common case.
const BOTTOM_DP: float = 28.0

## The smallest a control may be and still be reliably hit.
##
## Forty-eight density-independent pixels is the number every platform's own
## guidance settles on, and it is roughly nine millimetres — the width of the
## contact patch of an adult fingertip, which is why they all agree.
const TARGET_DP: float = 48.0

## Rects, in screen pixels, that some floating panel is occupying right now.
##
## Registered by the panels themselves. Godot's own routing handles a press that
## lands *on* a control, but a panel is a rounded card with shadow and padding,
## and the corners and the gaps between its buttons are not controls — a press
## there falls through to the canvas and draws a mark inside what the user sees
## as a solid panel. This is the panel's whole footprint, not its buttons.
static var _claimed: Dictionary = {}

## Panels register under a name so re-registering replaces rather than piles up.
static func claim(who: String, area: Rect2) -> void:
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		release(who)
		return
	_claimed[who] = area

static func release(who: String) -> void:
	_claimed.erase(who)

static func release_all() -> void:
	_claimed.clear()

## The screen, minus whatever the system has kept for itself.
##
## `get_display_safe_area` is in real pixels and is the honest source: it knows
## about the notch, the navigation bar and the rounded corners of this exact
## device. When it comes back as the whole window — desktop, or a platform that
## does not implement it — the bottom fallback stands in, because a phone that
## reports no safe area still usually has a gesture bar.
static func safe_area() -> Rect2:
	var window: Vector2 = Vector2(DisplayServer.window_get_size())
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var box: Rect2 = Rect2(Vector2(safe.position), Vector2(safe.size))
	if box.size.x <= 0.0 or box.size.y <= 0.0:
		box = Rect2(Vector2.ZERO, window)
	# When the system reports no inset at the bottom, a phone still usually has
	# a gesture bar there. The fallback stands in for it — and only ever on a
	# phone, since `may_begin` is the sole caller that acts on this.
	if box.size.y >= window.y - 1.0:
		box.size.y = maxf(window.y - BOTTOM_DP * App.ui_scale, 1.0)
	return box

## Whether a stroke may begin here.
##
## Asked once, at touch-down, and never again for that stroke.
static func may_begin(screen: Vector2) -> bool:
	# A panel's footprint is refused everywhere, because a mouse falls through
	# the gap between two rows exactly as a finger does.
	for area in _claimed.values():
		if (area as Rect2).has_point(screen):
			return false
	# The strips are a phone problem and only a phone problem. A desktop window
	# has no back-gesture inset and no navigation bar, and reserving its edges
	# would take the left and right of the canvas away from a mouse that was
	# never going to lose the argument with the window manager.
	if not _on_a_phone():
		return true
	var window: Vector2 = Vector2(DisplayServer.window_get_size())
	var side: float = SIDE_DP * App.ui_scale
	if screen.x < side or screen.x > window.x - side:
		return false
	var box: Rect2 = safe_area()
	if screen.y < box.position.y or screen.y > box.position.y + box.size.y:
		return false
	return true

## Whether the edges of this screen belong to somebody else.
static func _on_a_phone() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") \
		or OS.has_feature("ios")

## Gives a control a touch box no smaller than a fingertip.
##
## The visible size is left alone — a small icon should look small. What grows
## is `custom_minimum_size`, which is what the press is measured against, so the
## button reads as the size it was drawn and catches the taps that were aimed at
## it and landed a few pixels out.
static func reachable(c: Control) -> Control:
	if c == null:
		return c
	var least: float = TARGET_DP * App.ui_scale
	var want: Vector2 = c.custom_minimum_size
	c.custom_minimum_size = Vector2(maxf(want.x, least), maxf(want.y, least))
	return c
