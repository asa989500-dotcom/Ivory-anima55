extends "res://tests/test_case.gd"
## Are the comic frames on the page?
##
## They were not. The frames were drawn one page origin away from the drawing,
## and the paint confinement asked about a point one page origin away from the
## finger — so on any page but the first, or on any project that had been moved
## in the workspace, the cutter's frames sat beside the canvas and a stroke
## inside a visible panel was refused.
##
## The reason it survived so long is that the offset is exactly zero for page
## one of a project at the workspace origin, which is what anyone testing it by
## hand looks at first. So this case deliberately works on a project that has
## been moved and on a page that is not the first.

func title() -> String:
	return "comic frames"

func run() -> void:
	_the_two_coordinate_spaces_are_the_same()
	_frames_land_inside_the_page()
	_a_cut_keeps_every_piece_on_the_page()
	_paint_is_confined_to_the_frame_the_artist_can_see()

## A comic project whose origin is deliberately not zero, on a page that is
## deliberately not the first.
func _moved_comic() -> ProjectManager:
	var manager: ProjectManager = ProjectManager.new()
	var p: ProjectManager.Project = manager.create("Cut test", ProjectManager.Kind.COMIC,
		Vector2(1600, 1200), Color.WHITE, 3, Vector2.ZERO)
	# Deliberately not at the workspace origin, and deliberately not page one.
	# Both offsets are zero in the case anyone checks by hand, which is exactly
	# why the fault went unnoticed.
	p.origin = Vector2(4321.0, -987.5)
	p.active_page = 2
	manager.active = p
	return manager

func _the_two_coordinate_spaces_are_the_same() -> void:
	note("canvas coordinates and page coordinates are the same coordinates")
	# This is the fact the whole fault turned on, so it is asserted rather than
	# remembered. `canvas_origin()` and `page_rect().position` are the same
	# expression written in two files; if they ever stop being, the conversion
	# in ComicBoard has to come back and this test is where that gets noticed.
	var manager: ProjectManager = _moved_comic()
	var p: ProjectManager.Project = manager.active
	for i in range(p.pages):
		var by_rect: Vector2 = p.page_rect(i).position
		var by_offset: Vector2 = p.origin + p.page_offset(i)
		near(by_rect.x, by_offset.x, 0.0001, "page_rect and page_offset disagree on x")
		near(by_rect.y, by_offset.y, 0.0001, "page_rect and page_offset disagree on y")

	# And the conversion the board applies on top of that is nothing, because
	# the overlay's own transform has already done it.
	var nowhere: Vector2 = ComicBoard.page_origin(null)
	near(nowhere.x, 0.0, 0.0001, "the board is applying a page offset a second time")
	near(nowhere.y, 0.0, 0.0001, "the board is applying a page offset a second time")

func _frames_land_inside_the_page() -> void:
	note("every frame corner is inside the page, on a moved project's third page")
	var manager: ProjectManager = _moved_comic()
	var p: ProjectManager.Project = manager.active
	var sheet: ComicPage = ComicPage.fresh(p.page)
	not_null(sheet, "a fresh comic page produced no frames")
	ok(sheet.panels.size() >= 1, "a fresh comic page has no panels")

	# The frames are stored page-local, so they must lie inside a rectangle
	# starting at the origin — not inside the page's position in the workspace.
	var page_box: Rect2 = Rect2(Vector2.ZERO, p.page)
	for poly in sheet.panels:
		for v in poly:
			ok(page_box.has_point(v),
				"a frame corner at %s is outside the page 0,0..%s" % [str(v), str(p.page)])

	# And the margin is real: the frame does not run to the very edge.
	var first: PackedVector2Array = sheet.panels[0]
	var lo: Vector2 = first[0]
	var hi: Vector2 = first[0]
	for v in first:
		lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
		hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
	ok(lo.x > 0.5 and lo.y > 0.5, "the frame runs to the very edge of the page")
	ok(hi.x < p.page.x - 0.5 and hi.y < p.page.y - 0.5, "the frame runs to the very edge of the page")

func _a_cut_keeps_every_piece_on_the_page() -> void:
	note("cutting the page leaves every piece on the page")
	var manager: ProjectManager = _moved_comic()
	var p: ProjectManager.Project = manager.active
	var sheet: ComicPage = ComicPage.fresh(p.page)
	var before: int = sheet.panels.size()

	# A vertical cut down the middle, in page coordinates.
	var cut: bool = sheet.cut_line(Vector2(p.page.x * 0.5, -50.0),
		Vector2(p.page.x * 0.5, p.page.y + 50.0))
	ok(cut, "a cut straight down the middle of the page did nothing")
	ok(sheet.panels.size() > before, "the cut did not make more panels")

	var page_box: Rect2 = Rect2(Vector2(-1, -1), p.page + Vector2(2, 2))
	for poly in sheet.panels:
		ok(poly.size() >= 3, "a cut produced a panel with fewer than three corners")
		for v in poly:
			ok(page_box.has_point(v), "a cut put a corner at %s, off the page" % str(v))

func _paint_is_confined_to_the_frame_the_artist_can_see() -> void:
	note("a point inside a visible frame is allowed; one outside it is not")
	# The half of the fault nobody could see: the frames were drawn in the
	# wrong place AND the confinement asked about the wrong point, so a stroke
	# inside a panel was refused.
	var manager: ProjectManager = _moved_comic()
	var p: ProjectManager.Project = manager.active
	var sheet: ComicPage = ComicPage.fresh(p.page)
	sheet.cut_line(Vector2(p.page.x * 0.5, -50.0),
		Vector2(p.page.x * 0.5, p.page.y + 50.0))
	ok(sheet.panels.size() >= 2, "the page did not divide in two")

	# Choose the left panel and check the middle of it is paintable.
	var left: int = sheet.panel_at(Vector2(p.page.x * 0.25, p.page.y * 0.5))
	ok(left >= 0, "no panel contains the middle of the left half")
	sheet.chosen = left
	ok(sheet.confined(), "choosing a panel did not confine painting to it")

	# Page-local coordinates, which is what `_panel_allows` now receives.
	ok(sheet.allows(Vector2(p.page.x * 0.25, p.page.y * 0.5)),
		"the middle of the chosen panel is not paintable")
	ok(not sheet.allows(Vector2(p.page.x * 0.75, p.page.y * 0.5)),
		"the other panel is paintable while this one is chosen")

	# And the point that used to be asked about — the same finger position with
	# the page origin subtracted a second time — is nowhere near the panel.
	# This is the exact arithmetic that made a visible frame refuse a stroke.
	var doubled: Vector2 = Vector2(p.page.x * 0.25, p.page.y * 0.5) - p.page_rect(p.active_page).position
	ok(not sheet.allows(doubled),
		"subtracting the page origin twice still lands inside the panel — the test proves nothing")
