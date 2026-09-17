class_name ProjectManager
extends Node2D
## Projects live on the infinite grid as sheets of paper.
##
## Each one is a world of its own: its own layers, its own undo history, its
## own paper size and colour. Nothing is shared, so opening a second project
## can never disturb the first.
##
## Only the open project keeps its pixels on the graphics card. A closed one
## folds every tile down into compressed memory and shows a single flat
## picture instead, which is what makes a workspace full of projects cost
## about as much as a workspace with one.

signal projects_changed()
signal active_changed(project: Project)

enum Kind { DRAWING, ANIMATION, COMIC }

## The colour each kind wears on the shelf.
##
## A workspace fills up with sheets that are all the same shape, and the only
## way to find the one you want is to read every title. Colour is read before
## text is — a person spots the green one across the room and reaches for it
## without having decided to look.
##
const FRAME_TINTS: Dictionary = {
	Kind.DRAWING: Color("#1b1c22"),
	Kind.ANIMATION: Color("#1c2430"),
	Kind.COMIC: Color("#241d2c"),
}

static func frame_for(kind: int) -> Color:
	return FRAME_TINTS.get(kind, Color("#1b1c22"))
enum State { FLOATING, CLOSED, OPEN }

const TITLE_LIFT: float = 34.0
const MAX_PROJECTS: int = 1000
const MAX_PAGES: int = 12

## One page: its own sheet, its own layers, its own undo history. A comic
## page is a drawing in its own right, not a region of a longer one, and
## giving each its own stack is what makes "add a page" cost nothing and
## "work on page three" mean only page three.
class Page:
	var sheet: ProjectSheet = null
	var stack: LayerStack = null
	var history: History = null
	## Its own clip, for the same reason it has its own layers: a page is a
	## drawing in its own right, and a timeline that spanned pages would
	## have to explain what page two means at frame ten of page one.
	var clip: Anim.Clip = null

	## A small picture of this page, for the page wall.
	##
	## Kept on the page rather than in a table elsewhere, so it dies with the
	## page it belongs to — a cache that outlives its subject is how a
	## deleted page keeps appearing in a panel. Cleared whenever the page is
	## drawn on, so a thumbnail is either current or absent and never quietly
	## stale: a stale one sends somebody to the wrong page and the mistake is
	## found after they have started drawing.
	var thumb: ImageTexture = null

	## --- the frames this page is cut into ---
	##
	## Only ever set on a comic page, and made on demand rather than at
	## creation — see `ComicBoard.layout`. Null everywhere else, and null on
	## every comic page written before this existed, which is why every reader
	## of it checks.
	##
	## It lives on the page rather than on the project for the same reason the
	## layers and the history do: a page is a drawing in its own right, and a
	## layout that spanned pages would have to say what page two's third frame
	## means while page one is being cut.
	var frames: ComicPage = null

class Project:
	## An inner class cannot see the enclosing script's constants, so the
	## page gap lives here and the outer code reads it back through the
	## class. One definition, no chance of the two drifting apart.
	const PAGE_GAP: float = 60.0

	var id: int = 0
	var title: String = ""
	var kind: int = 0                       # ProjectManager.Kind
	var created: String = ""
	var origin: Vector2 = Vector2.ZERO      # top-left of page one, in world
	var page: Vector2 = Vector2(1600, 1200)
	var pages: int = 1
	var paper: Color = Color("#ffffff")
	var frame: Color = Color("#1b1c22")
	var cut_points: Array = []

	## Whether layers mean anything on this kind of project.
	##
	## Asked wherever a layer would otherwise be made or shown, so the answer
	## lives in one place instead of being a kind test scattered through the
	## interface. Every kind uses layers now that knitting is gone, and the
	## method is kept rather than deleted: it is the one place to say
	## otherwise if a kind is ever added that does not.
	func uses_layers() -> bool:
		return true

	var favourite: bool = false
	var state: int = 0                      # ProjectManager.State
	## Graph paper under the ink. A guide, never part of the artwork, so it
	## is drawn by the sheet and skipped by every exporter.
	var grid_guide: bool = false

	# --- animation only ---
	## What this project was last exported as, and how.
	##
	## Per project, not one setting for the whole app. A comic and an
	## animation want completely different things — pages as a CBZ, frames as
	## a WebP — and a workspace holds both at once. One shared setting means
	## every export after the first is the wrong kind, chosen again from a
	## list every single time.
	##
	## Empty means never exported, and the first export chooses a sensible
	## kind from what the project actually contains rather than asking.
	var export_kind: String = ""
	## Video container/codec pair. MP4/H.264 is the default and Android hardware path.
	var export_format: String = "mp4_h264"
	## How wide the exported file is, or nought for the drawing's own size.
	var export_width: int = 0
	## H.264 quality control. Lower CRF means higher quality/larger files.
	var export_crf: int = 20
	## Friendly quality preset. Advanced users can still override CRF/bitrate.
	var export_quality: String = "Good"
	## Optional average video bitrate in bits/sec. Zero lets CRF control quality.
	var export_bitrate: int = 0
	## Source, 720p, 1080p, 1440p or 4K.
	var export_resolution: String = "Source"
	## Audio from the animation timeline when an audio track exists.
	var export_audio: bool = true
	## H.264 profile: baseline, main or high.
	var export_profile: String = "high"
	## Which stretch of the scene an export covers: Timeline for all of it,
	## Playback for the range the timeline is set to play, Custom for the two
	## numbers below.
	var export_range: String = "Timeline"
	var export_from: int = 0
	## Zero means "to the end", so a scene that grows does not have to have
	## this corrected every time.
	var export_to: int = 0
	## How much thinking the software encoder is allowed. Costs time and
	## nothing else — the same quality in a smaller file.
	var export_preset: String = "fast"
	## How much room the sound gets, in kbps. 128 is the number everything
	## defaults to and it is audible on music; this is not stuck there.
	var export_audio_kbps: int = 192

	var fps: int = 24
	var frames: int = 24
	var onion_skin: bool = true
	var onion_back: int = 2
	var onion_forward: int = 1
	var onion_back_tint: Color = Color(0.90, 0.35, 0.35, 0.34)
	var onion_highlight: Color = Color(1.0, 0.78, 0.22, 0.34)
	var onion_forward_tint: Color = Color(0.35, 0.55, 0.95, 0.30)
	var looping: bool = true
	## Animation editor surface: the simple Ivory workspace or the professional
	## Stretchy Studio workspace. Kept per project so other project kinds never
	## expose or inherit the choice.
	var animation_ui: String = "ivory"
	## Stretchy's private authoring state, persisted with this animation project.
	var stretchy_document: Dictionary = {}

	## Pages laid out downwards instead of across. A comic reads as a strip
	## either way; which one suits depends on the screen in front of you.
	var stacked: bool = false
	var active_page: int = 0

	var root: Node2D = null
	var sheets: Array = []          # of Page

	## The active page's stack and history. Kept as plain references so the
	## rest of the app can go on saying `project.stack` without caring that
	## there are now several.
	var stack: LayerStack = null
	var history: History = null
	var clip: Anim.Clip = null

	func page_at(i: int) -> Page:
		if sheets.is_empty():
			return null
		return sheets[clampi(i, 0, sheets.size() - 1)]

	## Where a page sits inside the project, measured from its corner.
	func page_offset(i: int) -> Vector2:
		if stacked:
			return Vector2(0.0, (page.y + PAGE_GAP) * float(i))
		return Vector2((page.x + PAGE_GAP) * float(i), 0.0)

	## The whole spread, pages and gaps together.
	func bounds() -> Rect2:
		var last: Vector2 = page_offset(maxi(pages - 1, 0))
		return Rect2(origin, last + page)

	func page_rect(i: int) -> Rect2:
		return Rect2(origin + page_offset(i), page)

var projects: Array[Project] = []
var active: Project = null
var selected: Project = null

## Focus hides everything except the project being worked on, which buys
## both a clear field to draw in and less to render. `focus_shows_others`
## lets someone keep the neighbours in sight when they are working from
## them — the point is to remove clutter, not to remove the choice.
## The sheet the user is placing right now, and only that one. Reading the
## state flag instead let a project left FLOATING by a failed load swallow
## every touch in the app — nothing else could be opened, moved or deleted.
var placing: Project = null

var focus_on: Project = null
var focus_shows_others: bool = false

## Set by anything that changes a document. The autosave timer reads it and
## clears it, so a workspace being looked at rather than drawn on never
## writes a byte.
var dirty: Dictionary = {}

## The sheet currently being carried across the workspace, so the frame can
## say so while it is in the air.
var dragging: Project = null

var _next_id: int = 1
var render_rect: Rect2 = Rect2()

func _ready() -> void:
	y_sort_enabled = false

# ------------------------------------------------------------------ create

func create(title: String, kind: int, page_size: Vector2, paper: Color,
		pages: int, at: Vector2) -> Project:
	if projects.size() >= MAX_PROJECTS:
		return null
	var p: Project = Project.new()
	p.id = _next_id
	_next_id += 1
	p.title = title.strip_edges()
	if p.title == "":
		# Numbered by how many are actually here, not by how many have ever
		# existed. Delete your first project and the next one is number one
		# again, which is what anyone counting sheets on a desk would expect.
		p.title = "%s %d" % [_kind_word(kind), _next_number(kind)]
	p.kind = kind
	p.page = Vector2(maxf(page_size.x, 64.0), maxf(page_size.y, 64.0))
	p.pages = maxi(pages, 1)
	if kind == Kind.COMIC:
		p.pages = maxi(p.pages, 2)   # a comic is a spread, never one sheet
	p.frame = frame_for(kind)
	p.paper = paper
	p.created = Time.get_date_string_from_system()
	p.state = State.FLOATING

	p.root = Node2D.new()
	p.root.name = "Project_%d" % p.id
	add_child(p.root)

	for i in p.pages:
		_add_page_node(p)
	_bind_page(p, 0)

	p.origin = _free_spot(at - p.bounds().size * 0.5, p.bounds().size, p)
	_sync(p)
	projects.append(p)
	placing = p
	projects_changed.emit()
	return p

## Slides a new sheet along until it is clear of the ones already there.
## Two projects born at the middle of the same view would otherwise sit
## exactly on top of each other, and stay stacked for good once saved.
func _free_spot(wanted: Vector2, span: Vector2, ignore: Project) -> Vector2:
	var gap: float = Project.PAGE_GAP * 2.0
	var at: Vector2 = wanted
	for _try in 40:
		var clash: bool = false
		for other in projects:
			if other == ignore:
				continue
			if Rect2(at, span).grow(gap * 0.5).intersects(other.bounds()):
				clash = true
				break
		if not clash:
			return at
		at.x += span.x + gap
		# Wrapped onto a new row rather than marching off in a straight
		# line, so a workspace stays something the eye can scan.
		if at.x > wanted.x + (span.x + gap) * 4.0:
			at.x = wanted.x
			at.y += span.y + gap
	return at

## Builds one more page and everything that belongs to it.
func _add_page_node(p: Project) -> Page:
	var page: Page = Page.new()
	page.sheet = ProjectSheet.new()
	page.sheet.name = "Page_%d" % (p.sheets.size() + 1)
	page.sheet.page_size = p.page
	page.sheet.paper = p.paper
	page.sheet.grid_guide = p.grid_guide
	p.root.add_child(page.sheet)

	page.stack = LayerStack.new()
	page.stack.name = "Layers"
	page.stack.allows_layers = p.uses_layers()
	page.sheet.add_child(page.stack)

	page.history = History.new(page.stack)
	page.stack.history = page.history

	page.clip = Anim.Clip.new()
	page.clip.fps = clampi(p.fps, 1, 60)
	page.clip.length = maxi(p.frames, 1)

	p.sheets.append(page)
	page.sheet.position = p.page_offset(p.sheets.size() - 1)
	return page

## Points the project's `stack` and `history` at one page.
func _bind_page(p: Project, index: int) -> void:
	var page: Page = p.page_at(index)
	if page == null:
		return
	p.active_page = clampi(index, 0, p.sheets.size() - 1)
	p.stack = page.stack
	p.history = page.history
	p.clip = page.clip
	_sync_pages(p)

func set_page(p: Project, index: int) -> void:
	if p == null or index == p.active_page:
		return
	_bind_page(p, index)
	if p == active:
		active_changed.emit(p)
	projects_changed.emit()

func add_page(p: Project) -> void:
	if p == null or p.pages >= MAX_PAGES:
		return
	p.pages += 1
	_add_page_node(p)
	_bind_page(p, p.pages - 1)
	_sync(p)
	projects_changed.emit()

## Lays the pages out and decides which one is allowed to clip.
func _sync_pages(p: Project) -> void:
	for i in p.sheets.size():
		var page: Page = p.sheets[i]
		page.sheet.position = p.page_offset(i)
		page.sheet.page_size = p.page
		page.sheet.paper = p.paper
		page.sheet.grid_guide = p.grid_guide
		# Every page clips, always. Reserving it for the page being painted
		# meant a closed project drew whatever had once run past its edge,
		# and a sheet that shows more than its own paper is not a sheet.
		# The cost is bounded elsewhere: pages off screen do not draw at all.
		page.sheet.set_clipping(true)
		page.sheet.queue_redraw()

func set_layout_stacked(p: Project, on: bool) -> void:
	if p == null or p.stacked == on:
		return
	p.stacked = on
	_sync(p)
	projects_changed.emit()

func _kind_word(kind: int) -> String:
	if kind == Kind.ANIMATION:
		return Lang.t("Animation")
	if kind == Kind.COMIC:
		return Lang.t("Comic")
	return Lang.t("Drawing")

func _next_number(kind: int) -> int:
	var taken: Dictionary = {}
	var word: String = _kind_word(kind)
	for other in projects:
		if other.kind != kind:
			continue
		var tail: String = other.title.replace(word, "").strip_edges()
		if tail.is_valid_int():
			taken[int(tail)] = true
	var n: int = 1
	while taken.has(n):
		n += 1
	return n

func duplicate_project(src: Project) -> Project:
	if src == null:
		return null
	var copy: Project = create(src.title + " copy", src.kind, src.page,
		src.paper, src.pages, src.bounds().get_center())
	if copy == null:
		return null
	copy.frame = src.frame
	copy.favourite = src.favourite
	copy.fps = src.fps
	copy.frames = src.frames
	copy.cut_points = []
	for marker in src.cut_points:
		copy.cut_points.append((marker as Dictionary).duplicate(true))
	copy.onion_skin = src.onion_skin
	copy.onion_back = src.onion_back
	copy.onion_forward = src.onion_forward
	copy.onion_back_tint = src.onion_back_tint
	copy.onion_highlight = src.onion_highlight
	copy.onion_forward_tint = src.onion_forward_tint
	copy.looping = src.looping
	copy.animation_ui = src.animation_ui
	copy.stretchy_document = src.stretchy_document.duplicate(true)
	copy.stacked = src.stacked
	copy.active_page = src.active_page
	copy.origin = src.origin + Vector2(src.bounds().size.x + Project.PAGE_GAP * 2.0, 0.0)
	copy.state = State.CLOSED
	# A professional duplicate is a document duplicate, not a screenshot.
	# Preserve every page's cels, camera keys, layer properties and folders.
	for i in mini(src.sheets.size(), copy.sheets.size()):
		var from_page: Page = src.sheets[i]
		var into_page: Page = copy.sheets[i]
		into_page.clip = Anim.from_dict(Anim.to_dict(from_page.clip))
		into_page.history.clear()

		var from_stack: LayerStack = from_page.stack
		var into_stack: LayerStack = into_page.stack
		while into_stack.layers.size() < from_stack.layers.size():
			if into_stack.add_layer() == null:
				break
		while into_stack.layers.size() > from_stack.layers.size() and into_stack.layers.size() > 1:
			into_stack.remove_layer(into_stack.layers.size() - 1)

		for k in mini(from_stack.layers.size(), into_stack.layers.size()):
			var src_layer: LayerStack.Layer = from_stack.layers[k]
			var dst_layer: LayerStack.Layer = into_stack.layers[k]
			dst_layer.title = src_layer.title
			dst_layer.opacity = src_layer.opacity
			dst_layer.visible = src_layer.visible
			dst_layer.locked = src_layer.locked
			dst_layer.is_background = src_layer.is_background
			dst_layer.cels.from_dict(src_layer.cels.to_dict())
			dst_layer.surface.blend_from(src_layer.surface, 1.0)

		# Recreate folders with fresh IDs, then restore their visual state.
		for g in from_stack.groups:
			var first_index: int = -1
			for k in from_stack.layers.size():
				if from_stack.layers[k].group_id == g.id:
					first_index = k
					break
			if first_index < 0 or first_index >= into_stack.layers.size():
				continue
			var new_group: LayerStack.Group = into_stack.group_layer(first_index)
			if new_group == null:
				continue
			new_group.title = g.title
			new_group.opacity = g.opacity
			new_group.visible = g.visible
			new_group.collapsed = g.collapsed
			for k in into_stack.layers.size():
				if k < from_stack.layers.size() and from_stack.layers[k].group_id == g.id:
					into_stack.layers[k].group_id = new_group.id
		into_stack._rebuild()
		into_page.history.clear()

	_bind_page(copy, clampi(src.active_page, 0, maxi(copy.sheets.size() - 1, 0)))
	_sync(copy)
	projects_changed.emit()
	return copy

func select(p: Project) -> void:
	if p == null:
		return
	selected = p
	projects_changed.emit()

func clear_selection() -> void:
	if selected == null:
		return
	selected = null
	projects_changed.emit()

func remove(p: Project) -> void:
	if p == null:
		return
	var was_active: bool = p == active
	if placing == p:
		placing = null
	if dragging == p:
		dragging = null
	if focus_on == p:
		focus_on = null
	if selected == p:
		selected = null
	projects.erase(p)
	p.root.queue_free()
	if was_active:
		active = null
		active_changed.emit(null)
	projects_changed.emit()

# ------------------------------------------------------------------- state

func open(p: Project) -> void:
	if p == null or p == active:
		return
	if p.state == State.FLOATING:
		place(p)
	if active != null and active != p:
		close(active)
	p.state = State.OPEN
	selected = p
	_wake(p)
	active = p
	_sync(p)
	active_changed.emit(p)
	projects_changed.emit()

## Closing is what keeps a crowded workspace cheap: every tile is squeezed
## into compressed memory and every render target handed back.
func close(p: Project) -> void:
	if p == null or p.state == State.FLOATING:
		return
	p.state = State.CLOSED
	# Trimmed once, here, so the sheet can stop clipping for good. Doing it
	# at closing time means the cost is paid on an action the user already
	# expects to take a moment, not on every frame of every project.
	var page_span: Rect2 = Rect2(Vector2.ZERO, p.page)
	for page in p.sheets:
		var sheet: Page = page
		for l in sheet.stack.layers:
			l.surface.settle()
			l.surface.trim_to(page_span)
			l.surface.sleep_all()
		# And the whole sheet stops being *ticked*.
		#
		# Its tiles are already asleep, but every node under it was still
		# being visited by the engine sixty times a second to be told there
		# was nothing to do. One closed project is nothing; a workspace with
		# twenty is twenty stacks of layers being walked every frame for no
		# result at all. `DISABLED` takes the branch out of the tree walk
		# outright, and `open` puts it back.
		sheet.stack.process_mode = Node.PROCESS_MODE_DISABLED

	if p == active:
		active = null
		active_changed.emit(null)
	_sync(p)
	projects_changed.emit()

func place(p: Project) -> void:
	if p == null or p.state != State.FLOATING:
		return
	p.state = State.CLOSED
	if placing == p:
		placing = null
	_sync(p)
	projects_changed.emit()

func _wake(p: Project) -> void:
	for page in p.sheets:
		var sheet: Page = page
		# Ticking again, first: `close` disabled it, and a stack that is not
		# processing cannot fold a stroke down. Every path that opens a
		# project comes through here, so this is the one place it needs
		# undoing — and it is safe to set on a stack that was never disabled.
		sheet.stack.process_mode = Node.PROCESS_MODE_INHERIT
		for l in sheet.stack.layers:
			l.surface.update_view(Rect2(Vector2.ZERO, p.page).grow(p.page.x), 1.0)

## Marked with the moment it *first* became dirty, not the latest change.
##
## Keeping the first time is what makes the wait honest. Stamping every change
## would restart the clock on every dab, so a project being drawn on steadily
## would never reach the age at which it is written — which is precisely the
## project with the most to lose.
func mark_dirty(p: Project) -> void:
	if p != null and not dirty.has(p.id):
		dirty[p.id] = Time.get_ticks_msec()

## Every project waiting to be written, the one that has been waiting longest
## first.
##
## The order matters. The old list came out in workspace order, so with two
## dirty projects the same one was written every time the timer came round and
## the other could sit unsaved for as long as the first kept changing.
##
## Snapshot only: a failed disk write must remain dirty so the next autosave
## can retry it instead of silently declaring unsaved work clean.
func take_dirty() -> Array:
	var out: Array = []
	for p in projects:
		if dirty.has(p.id):
			out.append(p)
	out.sort_custom(_waiting_longer)
	return out

## Which of two projects has been waiting longer to be written.
##
## A named method, not a lambda: a lambda body wrapped onto a second line does
## not continue the way an expression inside brackets does, and the parser
## stops at the operator that begins the second line.
func _waiting_longer(a: Variant, b: Variant) -> bool:
	return int(dirty.get((a as Project).id, 0)) \
		< int(dirty.get((b as Project).id, 0))

## How long the project that has been waiting longest has been waiting, in
## seconds. Nought when nothing is waiting.
func oldest_dirty_wait() -> float:
	var oldest: int = -1
	for key in dirty.keys():
		var when: int = int(dirty[key])
		if oldest < 0 or when < oldest:
			oldest = when
	if oldest < 0:
		return 0.0
	return float(Time.get_ticks_msec() - oldest) / 1000.0

func mark_saved(p: Project) -> void:
	if p != null:
		dirty.erase(p.id)

func _sync(p: Project) -> void:
	p.root.position = p.origin
	_sync_pages(p)
	_apply_focus()

func set_focus(p: Project) -> void:
	focus_on = p
	_apply_focus()
	projects_changed.emit()

func clear_focus() -> void:
	focus_on = null
	_apply_focus()
	projects_changed.emit()

func set_focus_shows_others(on: bool) -> void:
	focus_shows_others = on
	_apply_focus()
	projects_changed.emit()

func is_hidden(p: Project) -> bool:
	if focus_on == null or focus_shows_others:
		return false
	return p != focus_on

func _apply_focus() -> void:
	for p in projects:
		if p.root != null:
			p.root.visible = not is_hidden(p)

## Where a sheet sits is part of the document, so moving it makes the
## project unsaved rather than quietly losing the new place on exit.
func move_to(p: Project, origin: Vector2) -> void:
	if p == null:
		return
	p.origin = origin
	mark_dirty(p)
	_sync(p)

# ------------------------------------------------------------------ lookup

## Whether a project with this id is already here, so a folder read twice
## cannot produce two of the same project.
func holds_id(id: int) -> bool:
	for p in projects:
		if p.id == id:
			return true
	return false

## Gives a restored project the id it was saved under, and keeps the counter
## above it so a new project can never collide with one on disk.
func reclaim_id(p: Project, id: int) -> void:
	if p == null or id <= 0:
		return
	p.id = id
	p.root.name = "Project_%d" % id
	_next_id = maxi(_next_id, id + 1)

## Topmost first, so a project laid over another answers for the tap. A
## project hidden by focus is not on screen, and something the user cannot
## see must not be what their finger lands on.
func at_point(world: Vector2) -> Project:
	for i in range(projects.size() - 1, -1, -1):
		if is_hidden(projects[i]):
			continue
		if projects[i].bounds().has_point(world):
			return projects[i]
	return null

func title_strip_at(world: Vector2, zoom: float) -> Project:
	var lift: float = TITLE_LIFT / maxf(zoom, 0.0001)
	for i in range(projects.size() - 1, -1, -1):
		if is_hidden(projects[i]):
			continue
		var b: Rect2 = projects[i].bounds()
		var strip: Rect2 = Rect2(b.position - Vector2(0.0, lift),
			Vector2(b.size.x, lift))
		if strip.has_point(world):
			return projects[i]
	return null

func bring_to_front(p: Project) -> void:
	if p == null:
		return
	projects.erase(p)
	projects.append(p)
	move_child(p.root, get_child_count() - 1)

## Keeps closed projects out of the way of the drawing hand.
## A project's layers live inside the project's own node, so their tiles are
## measured from the project's corner, not from the world origin. Handing
## them a world rectangle meant every tile on screen was judged to be far
## away — hidden, and put to sleep — which is why drawing appeared to do
## nothing at all.
## Runs for every project, not only the open one: a closed project still
## draws, and its pages still need to know whether anyone can see them.
func update_view(view_world: Rect2, zoom: float) -> void:
	# Keep a generous culling rectangle for chrome/project cards. This lets
	# workspaces hold hundreds of projects without drawing every card every frame.
	render_rect = view_world.grow(maxf(view_world.size.x, view_world.size.y) * 0.85)
	for p in projects:
		if is_hidden(p):
			for hidden_page in p.sheets:
				(hidden_page as Page).sheet.visible = false
			continue
		for i in p.sheets.size():
			var page: Page = p.sheets[i]
			var corner: Vector2 = p.origin + p.page_offset(i)
			var candidate: Rect2 = Rect2(corner, p.page)
			var seen: bool = view_world.intersects(candidate)
			# Clipping costs a framebuffer copy per page that draws, so a
			# page off screen is hidden rather than merely quiet.
			if page.sheet.visible != seen:
				page.sheet.visible = seen
			if not seen:
				continue
			page.stack.update_view(
				Rect2(view_world.position - corner, view_world.size), zoom)
