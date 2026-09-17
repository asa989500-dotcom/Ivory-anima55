class_name Exporters
extends RefCounted
## Every format the app can write, and nothing it cannot.
##
## Three of these are written by hand rather than handed to a library,
## because they are the formats that make the difference between "I made a
## picture" and "I can carry this into my working life":
##
##   PSD  — layers survive. Opening the file in Photoshop or Krita gives
##          back the layers as they were left, not a flattened print.
##   CBZ  — what comic readers actually open. It is a zip of pages in order,
##          which the engine can write directly.
##   PDF  — pages anyone can open, with the images embedded as JPEG.
##
## MP4 is provided by the native GDE GoZen/FFmpeg encoder bundled as source
## under `native/gde_gozen`. The app streams frames into the encoder one at a
## time so a long animation does not require every frame to remain in RAM.

## Exports go somewhere the rest of the phone can see. An app-private
## folder is invisible to the gallery and to every other app, which makes a
## finished picture unreachable from the very tools it was made for.
static var _cached_dir: String = ""

static func out_dir() -> String:
	if _cached_dir != "":
		return _cached_dir
	var base: String = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if base == "":
		base = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if base == "" or not DirAccess.dir_exists_absolute(base):
		base = "user://"          # desktop sandboxes and odd devices
	_cached_dir = base.rstrip("/") + "/IVORY"
	return _cached_dir

## Kept so older call sites still read correctly.
static func ensure_dir() -> String:
	var dir: String = out_dir()
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		# Refused — most likely storage permission. Fall back rather than
		# lose the export entirely.
		_cached_dir = "user://exports"
		DirAccess.make_dir_recursive_absolute(_cached_dir)
	return _cached_dir

static func stamp() -> String:
	return Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")

static func base_name(p: ProjectManager.Project) -> String:
	var n: String = p.title.validate_filename()
	if n == "":
		n = "project"
	return "%s_%s" % [n, stamp()]

# --------------------------------------------------------------- rendering

## Flattens a page — paper first, then every visible layer in order.
## Canvas pixels are premultiplied and blend_rect expects exactly that in
## its source, so the two meet without conversion.
static func render_page(p: ProjectManager.Project, page: int) -> Image:
	# A page below zero means the whole spread: every page composited side
	# by side exactly as it sits on the grid.
	if page < 0 and p.pages > 1:
		return _render_spread(p)
	var index: int = maxi(page, 0)
	var target: ProjectManager.Page = p.page_at(index)
	if target == null:
		return null
	var w: int = int(p.page.x)
	var h: int = int(p.page.y)
	if w <= 0 or h <= 0:
		return null
	# The page size comes from a box the user typed in, so it can be anything.
	# Asked for through the budget: an export that returns null is an export
	# that can say "too large for this device", where one that is simply
	# attempted is an export that closes the app.
	var sheet: Image = Perf.make_image(Vector2i(w, h))
	if sheet == null:
		return null
	var art: Image = target.stack.read_region(Rect2i(Vector2i.ZERO, Vector2i(w, h)))
	sheet.fill(p.paper)
	if art != null:
		sheet.blend_rect(art, Rect2i(Vector2i.ZERO, Vector2i(w, h)), Vector2i.ZERO)
	return sheet

static func _render_spread(p: ProjectManager.Project) -> Image:
	var span: Vector2 = p.bounds().size
	# A spread is every page side by side, so a forty-page comic asks for forty
	# times one page. This is the single largest thing the exporter ever builds,
	# and the one that has no upper bound at all — the user can keep adding
	# pages.
	#
	# Shrunk rather than refused. "Here is your comic, smaller than the pages
	# are" is a real answer; "this comic cannot be exported" is not one, and
	# the pages themselves are untouched on disk either way. The factor is on
	# both sides equally, so nothing is stretched.
	var want: Vector2i = Perf.fit_within(Vector2i(int(span.x), int(span.y)))
	var shrink: float = 1.0
	if span.x > 0.0:
		shrink = float(want.x) / span.x
	var out: Image = Perf.make_image(want)
	if out == null:
		return null
	for i in p.pages:
		var one: Image = render_page(p, i)
		if one == null:
			continue
		if shrink < 0.999:
			var small: Vector2i = Vector2i(
				maxi(int(round(float(one.get_width()) * shrink)), 1),
				maxi(int(round(float(one.get_height()) * shrink)), 1))
			one = Distort.rescale(one, small)
			if one == null:
				continue
		out.blit_rect(one, Rect2i(Vector2i.ZERO, Vector2i(one.get_width(),
			one.get_height())), Vector2i(p.page_offset(i) * shrink))
	return out

## One layer on its own, in ordinary (not premultiplied) colour, which is
## what every other program expects to receive.
static func render_layer(p: ProjectManager.Project, layer: LayerStack.Layer,
		_page: int) -> Image:
	var img: Image = layer.surface.read_region(
		Rect2i(Vector2i.ZERO, Vector2i(int(p.page.x), int(p.page.y))))
	if img == null:
		return null
	_to_straight(img)
	return img

static func _to_straight(img: Image) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var d: PackedByteArray = img.get_data()
	for i in range(w * h):
		var o: int = i * 4
		var a: int = d[o + 3]
		if a == 0 or a == 255:
			continue
		d[o] = mini(int(float(d[o]) * 255.0 / float(a)), 255)
		d[o + 1] = mini(int(float(d[o + 1]) * 255.0 / float(a)), 255)
		d[o + 2] = mini(int(float(d[o + 2]) * 255.0 / float(a)), 255)
	img.set_data(w, h, false, Image.FORMAT_RGBA8, d)

# ------------------------------------------------------------ flat images

static func save_flat(p: ProjectManager.Project, fmt: String,
		per_page: bool) -> String:
	var dir: String = ensure_dir()
	var base: String = base_name(p)
	var count: int = p.pages if per_page else 1
	var last: String = ""
	for i in count:
		var img: Image = render_page(p, i if per_page else -1)
		if img == null:
			continue
		var suffix: String = ("_%03d" % (i + 1)) if per_page else ""
		var path: String = "%s/%s%s.%s" % [dir, base, suffix, fmt]
		if _write_image(img, path, fmt) == OK:
			last = path
	return last

static func _write_image(img: Image, path: String, fmt: String) -> int:
	if fmt == "jpg":
		var flat: Image = Image.create_empty(img.get_width(), img.get_height(),
			false, Image.FORMAT_RGBA8)
		flat.copy_from(img)
		flat.convert(Image.FORMAT_RGB8)
		return flat.save_jpg(path, 0.94)
	if fmt == "webp":
		return img.save_webp(path, false, 0.95)
	return img.save_png(path)

# ------------------------------------------------------- numbered sequence

## What editing software wants: one file per frame, zero padded so they sort
## correctly, plus a plain text note of the frame rate they belong to.
static func save_sequence(p: ProjectManager.Project) -> String:
	var folder: String = "%s/%s_frames" % [ensure_dir(), base_name(p)]
	DirAccess.make_dir_recursive_absolute(folder)
	var frames: Array = render_frames(p)
	if frames.is_empty():
		return ""
	# Four digits, so a scene of any length an animator would draw by hand
	# sorts correctly in every file browser and every editing program. Three
	# would break at frame one thousand, and breaking there means the last
	# tenth of a long scene silently plays first.
	var written: int = 0
	for i in frames.size():
		var img: Image = frames[i]
		if img.save_png("%s/frame_%04d.png" % [folder, i + 1]) == OK:
			written += 1
	if written == 0:
		return ""
	var first: Image = frames[0]
	var note: FileAccess = FileAccess.open("%s/frames.txt" % folder,
		FileAccess.WRITE)
	if note != null:
		note.store_line("fps=%d" % p.fps)
		note.store_line("frames=%d" % written)
		note.store_line("size=%dx%d" % [first.get_width(), first.get_height()])
		note.close()
	return folder

## All frames side by side on one image, with a text file describing the
## grid — the pair every game engine and web animation tool accepts.
static func save_sprite_sheet(p: ProjectManager.Project) -> String:
	var frames: Array = render_frames(p, 256)
	if frames.is_empty():
		return ""
	var cell: Image = frames[0]
	var cw: int = cell.get_width()
	var ch: int = cell.get_height()
	# As square a grid as the frame count allows.
	#
	# A single row is what a first attempt gives and it is unusable: sixty
	# frames of a thousand pixels is a sixty-thousand-pixel image, wider than
	# any graphics card will accept as a texture and wider than most programs
	# will open at all. Squaring it keeps both sides reasonable.
	var cols: int = maxi(int(ceil(sqrt(float(frames.size())))), 1)
	var rows: int = int(ceil(float(frames.size()) / float(cols)))
	var sheet: Image = Perf.make_image(Vector2i(cw * cols, ch * rows))
	if sheet == null:
		# The empty string, not null: this function hands back a *path*, and
		# every caller reads its answer as "somewhere, or nowhere". Failing
		# with the wrong kind of nothing is how the guard I added here stopped
		# the whole project compiling — the memory check was right, the way it
		# gave up was not.
		return ""
	for i in frames.size():
		var img: Image = frames[i]
		sheet.blit_rect(img, Rect2i(0, 0, cw, ch),
			Vector2i((i % cols) * cw, int(float(i) / float(cols)) * ch))
	var base: String = base_name(p)
	var path: String = "%s/%s_sheet.png" % [ensure_dir(), base]
	if sheet.save_png(path) != OK:
		return ""
	var note: FileAccess = FileAccess.open(
		"%s/%s_sheet.txt" % [ensure_dir(), base], FileAccess.WRITE)
	if note != null:
		note.store_line("columns=%d" % cols)
		note.store_line("rows=%d" % rows)
		note.store_line("frames=%d" % frames.size())
		note.store_line("frame=%dx%d" % [cw, ch])
		note.store_line("fps=%d" % p.fps)
		note.close()
	return path

# -------------------------------------------------------------- animation

## The largest a single exported frame may be, in pixels each way.
##
## A hundred frames of a four-thousand-pixel page is four gigabytes of raw
## image before a single one is compressed, and a phone will be killed by the
## system long before it finishes. Frames are brought down to this and the
## user is told, which is a slower export; the alternative is no export.
const FRAME_CEILING: int = 2048

## Every frame of the scene, rendered.
##
## This is the piece that was missing, and its absence quietly hollowed out
## four exports at once. `save_sequence`, `save_sprite_sheet`, `save_gif` and
## `save_webp_anim` all rendered the page **as it stood** and wrote a single
## frame — a sprite sheet of one cell, a GIF that does not move, a folder
## called `_frames` with `frames=1` in the note beside it. Each carried a
## comment saying it was waiting for the timeline. The timeline arrived some
## time ago.
##
## Three things have to be right, and each of them is a way the naive version
## would be wrong:
##
## **Holds.** A drawing on twos occupies two frames and is drawn once. Walking
## the cels would give half the frames and an animation running at double
## speed; walking the *frames* and asking each layer what it is showing gives
## what the scene actually looks like.
##
## **Rate units.** A stretch slowed to two a second lasts as long as the
## timeline says it does. A file format with one frame rate cannot slow down,
## so the frame is written as many times as it is held for — which is exactly
## what "the same picture stays on screen for half a second" means when the
## file plays at twenty-four.
##
## **Putting the scene back.** The stack is walked through the whole clip to
## do this, and it is the same stack the user is looking at. Whatever frame
## they were on is restored at the end, or exporting would silently scrub
## their work to the last frame of the scene every time.
## How many frames the last render had to leave out for want of memory.
##
## Read straight after `render_frames`. A returned value above zero is not an
## error — the clip that came back is real and complete as far as it goes — but
## the user is owed the sentence, because a scene that silently exports two
## thirds of itself is the worst kind of bug: the file opens, it plays, and it
## is wrong.
static var last_short_by: int = 0

static func render_frames(p: ProjectManager.Project,
		limit: int = 600) -> Array:
	var out: Array = []
	if p == null or p.stack == null:
		var one: Image = render_page(p, -1)
		if one != null:
			out.append(one)
		return out
	if p.clip == null:
		var still: Image = render_page(p, -1)
		if still != null:
			out.append(still)
		return out

	var span: Vector2i = p.clip.play_span(p.stack)
	var from_frame: int = maxi(span.x, 0)
	var to_frame: int = maxi(span.y, from_frame)
	var rate: int = clampi(p.clip.fps, 1, 60)
	# Where the user actually is, so they are put back there afterwards.
	var was: int = p.stack.shown_frame

	# How many *distinct* drawings this device can hold at once.
	#
	# The array below keeps every rendered frame alive until the encoder has
	# finished with all of them — that is what a single-palette GIF and a sprite
	# sheet both need. So a three-hundred-frame scene at Full HD asks for two
	# and a half gigabytes in one go, and the operating system answers by
	# closing the app in the middle of an export the user has been waiting on.
	#
	# Repeats are free: a held drawing is appended by reference, so a frame
	# shown for two seconds costs one image and forty-eight slots. Only new
	# renders are counted against the budget.
	var held_pixels: int = 0
	var budget: int = Perf.frame_pixel_budget()
	var short_by: int = 0

	var written: int = 0
	for f in range(from_frame, to_frame + 1):
		if written >= limit:
			break
		p.stack.show_frame(f, false)
		var img: Image = render_page(p, -1)
		if img == null:
			continue
		_fit_ceiling(img)
		var cost: int = img.get_width() * img.get_height()
		if held_pixels + cost > budget and not out.is_empty():
			# Stop cleanly with what is in hand rather than push on and be
			# killed. A shorter clip that exists beats a full one that does
			# not, and the caller says how much was left out.
			short_by = to_frame - f + 1
			break
		held_pixels += cost
		# How many frames of a fixed-rate file this one drawing occupies.
		# One outside a rate unit; more inside a slowed one; and a quickened
		# unit still gets one, because a file at twenty-four a second cannot
		# show a frame for less time than that and dropping it would lose the
		# drawing altogether.
		var held: int = 1
		var here: float = p.clip.span_seconds(f, f)
		if here > 0.0:
			held = clampi(int(round(here * float(rate))), 1, 120)
		for _k in held:
			if written >= limit:
				break
			out.append(img)
			written += 1

	# Back where they were, and drawn again, or the canvas is left showing
	# the last frame of the scene with no idea why.
	p.stack.show_frame(was, false)
	last_short_by = short_by
	return out

static func _fit_ceiling(img: Image) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var big: int = maxi(w, h)
	if big <= FRAME_CEILING:
		return
	var scale: float = float(FRAME_CEILING) / float(big)
	# Area averaging going down. Lanczos rings every line it reduces, and a
	# frame with a pale halo along every edge is worse than a slightly softer
	# one.
	img.resize(maxi(int(float(w) * scale), 1), maxi(int(float(h) * scale), 1),
		Image.INTERPOLATE_TRILINEAR)

## How many frames an export of this project will contain, without rendering
## any of them — so a sheet or a GIF can say how big it will be before it
## spends a minute finding out.
static func frame_count(p: ProjectManager.Project) -> int:
	if p == null or p.clip == null or p.stack == null:
		return 1
	var span: Vector2i = p.clip.play_span(p.stack)
	var rate: int = clampi(p.clip.fps, 1, 60)
	var total: int = 0
	for f in range(maxi(span.x, 0), maxi(span.y, 0) + 1):
		var here: float = p.clip.span_seconds(f, f)
		total += clampi(int(round(here * float(rate))), 1, 120) \
			if here > 0.0 else 1
	return maxi(total, 1)

# --------------------------------------------------------------------- CBZ

## A comic archive is a zip of pages named so they sort in reading order.
## A webtoon episode: every page joined into one tall image.
##
## ## Why this is not "export the pages"
##
## A webtoon is not read as pages. It is one continuous scroll, and it is
## uploaded as one file — so exporting six separate images and asking the
## artist to join them is exporting the wrong thing and calling it done.
##
## Joined with **no gap and no seam**. A webtoon's panel breaks are drawn into
## the artwork as white space; a gap added by the exporter would be a second
## kind of break the artist did not put there and cannot control.
##
## ## The height limit
##
## Long strips are usually split for upload, and the limit is real: browsers
## and phone decoders start failing somewhere past sixteen thousand pixels,
## and a strip that will not open is worse than one in two parts. So the run
## is broken into files of at most `WEBTOON_TALL`, cut between pages rather
## than through one — a cut through a drawing would be visible in the reader
## as a hairline where two images meet.
static func save_webtoon(p: ProjectManager.Project) -> String:
	if p == null or p.sheets.is_empty():
		return ""
	var made: Array = []
	var run: Array = []
	var tall: int = 0
	var wide: int = 0
	for i in p.sheets.size():
		var page: Image = render_page(p, i)
		if page == null:
			continue
		if tall + page.get_height() > WEBTOON_TALL and not run.is_empty():
			made.append(_join_down(run, wide, tall))
			run = []
			tall = 0
		run.append(page)
		wide = maxi(wide, page.get_width())
		tall += page.get_height()
	if not run.is_empty():
		made.append(_join_down(run, wide, tall))
	if made.is_empty():
		return ""

	var base: String = base_name(p)
	var last: String = ""
	for i in made.size():
		var name: String = "%s_%s.png" % [base, stamp()] if made.size() == 1 \
			else "%s_%s_%02d.png" % [base, stamp(), i + 1]
		var path: String = out_dir().path_join(name)
		if _write_image(made[i], path, "png") == OK:
			last = path
	return last

## The tallest a single exported strip may be, in pixels.
const WEBTOON_TALL: int = 16000

## Several pages stacked into one image, top to bottom.
static func _join_down(pages: Array, wide: int, tall: int) -> Image:
	var out: Image = Image.create_empty(maxi(wide, 1), maxi(tall, 1), false,
		Image.FORMAT_RGBA8)
	out.fill(Color(1.0, 1.0, 1.0, 1.0))
	var y: int = 0
	for one in pages:
		var page: Image = one
		# Centred if a page is narrower than the widest — which should not
		# happen in a webtoon and is not worth failing over if it does.
		var x: int = int((wide - page.get_width()) * 0.5)
		out.blend_rect(page,
			Rect2i(Vector2i.ZERO, page.get_size()), Vector2i(x, y))
		y += page.get_height()
	return out

static func save_cbz(p: ProjectManager.Project) -> String:
	var path: String = "%s/%s.cbz" % [ensure_dir(), base_name(p)]
	var zip: ZIPPacker = ZIPPacker.new()
	if zip.open(path) != OK:
		return ""
	# The pages of a comic, or the frames of a scene.
	#
	# An animation has one page and any number of frames, so paging through
	# `p.pages` gave a one-page archive of whatever happened to be on screen.
	# A flipbook of the frames is what a comic reader can actually show of an
	# animation, and it is what somebody asking for a CBZ of one wants.
	var sheets: Array = []
	if p.clip != null and frame_count(p) > 1:
		sheets = render_frames(p, 400)
	else:
		for i in p.pages:
			var one: Image = render_page(p, i)
			if one != null:
				sheets.append(one)
	if sheets.is_empty():
		zip.close()
		return ""
	for i in sheets.size():
		var img: Image = sheets[i]
		zip.start_file("%03d.png" % (i + 1))
		zip.write_file(img.save_png_to_buffer())
		zip.close_file()
	zip.close()
	return path

# --------------------------------------------------------------------- PDF

## A minimal but valid PDF: one page per drawing, each holding a JPEG that
## the reader decodes directly. Small files, and nothing exotic that an old
## reader might choke on.
static func save_pdf(p: ProjectManager.Project) -> String:
	var path: String = "%s/%s.pdf" % [ensure_dir(), base_name(p)]
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""

	# The pages of a comic, or the frames of a scene — the same reasoning as
	# in `save_cbz`.
	var sheets: Array = []
	if p.clip != null and frame_count(p) > 1:
		sheets = render_frames(p, 400)
	else:
		for i in p.pages:
			var one: Image = render_page(p, i)
			if one != null:
				sheets.append(one)

	var jpegs: Array = []
	var sizes: Array = []
	for sheet in sheets:
		# Duplicated before converting: a held drawing is the same object in
		# several places in the list, and converting it in place would turn
		# the second visit into a conversion of something already converted.
		var img: Image = (sheet as Image).duplicate()
		img.convert(Image.FORMAT_RGB8)
		jpegs.append(img.save_jpg_to_buffer(0.92))
		sizes.append(Vector2i(img.get_width(), img.get_height()))
	if jpegs.is_empty():
		f.close()
		return ""

	var n: int = jpegs.size()
	# Object numbering: 1 catalog, 2 page tree, then three objects per page.
	var offsets: Array = []
	var out: PackedByteArray = PackedByteArray()

	var put: Callable = func(text: String) -> void:
		out.append_array(text.to_utf8_buffer())
	var mark: Callable = func() -> void:
		offsets.append(out.size())

	put.call("%PDF-1.4\n")

	mark.call()
	put.call("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")

	var kids: String = ""
	for i in n:
		kids += "%d 0 R " % (3 + i * 3)
	mark.call()
	put.call("2 0 obj\n<< /Type /Pages /Count %d /Kids [%s] >>\nendobj\n" % [n, kids])

	for i in n:
		var page_id: int = 3 + i * 3
		var content_id: int = page_id + 1
		var image_id: int = page_id + 2
		var w: int = sizes[i].x
		var h: int = sizes[i].y

		mark.call()
		put.call(("%d 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] "
			+ "/Resources << /XObject << /Im0 %d 0 R >> >> /Contents %d 0 R >>\nendobj\n")
			% [page_id, w, h, image_id, content_id])

		var stream: String = "q %d 0 0 %d 0 0 cm /Im0 Do Q\n" % [w, h]
		mark.call()
		put.call("%d 0 obj\n<< /Length %d >>\nstream\n%s endstream\nendobj\n"
			% [content_id, stream.length(), stream])

		var data: PackedByteArray = jpegs[i]
		mark.call()
		put.call(("%d 0 obj\n<< /Type /XObject /Subtype /Image /Width %d /Height %d "
			+ "/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode "
			+ "/Length %d >>\nstream\n") % [image_id, w, h, data.size()])
		out.append_array(data)
		put.call("\nendstream\nendobj\n")

	var xref: int = out.size()
	put.call("xref\n0 %d\n0000000000 65535 f \n" % (offsets.size() + 1))
	for off in offsets:
		put.call("%010d 00000 n \n" % int(off))
	put.call("trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n"
		% [offsets.size() + 1, xref])

	f.store_buffer(out)
	f.close()
	return path

# --------------------------------------------------------------------- PSD

## Photoshop's format, written by hand so layers survive the trip.
##
## Channels are stored uncompressed. Photoshop's RLE would make the file
## smaller, but uncompressed is the variant every reader agrees on, and a
## file that opens everywhere beats one that opens smaller.
static func save_psd(p: ProjectManager.Project) -> String:
	var w: int = int(p.page.x)
	var h: int = int(p.page.y)
	if w <= 0 or h <= 0 or w > 30000 or h > 30000:
		return ""

	var path: String = "%s/%s.psd" % [ensure_dir(), base_name(p)]
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""

	var visible: Array = []
	for l in p.stack.layers:
		var img: Image = render_layer(p, l, -1)
		if img == null:
			continue
		visible.append({"layer": l, "image": img})
	if visible.is_empty():
		f.close()
		return ""

	# May be null when the page is past what this device can hold in one
	# piece. That is survivable *here* and nowhere else in the exporter: a PSD
	# is a file of layers, and `_raw_plane` writes a transparent composite for
	# a missing one. Every reader that can open a PSD at all reads the layers;
	# only a preview thumbnail would come up empty. Losing the thumbnail beats
	# losing the export.
	var flat: Image = render_page(p, -1)

	# --- header ---
	f.store_buffer("8BPS".to_ascii_buffer())
	_u16(f, 1)                       # version
	for i in 6:
		f.store_8(0)                 # reserved
	_u16(f, 4)                       # channels: RGBA
	_u32(f, h)
	_u32(f, w)
	_u16(f, 8)                       # bits per channel
	_u16(f, 3)                       # RGB
	_u32(f, 0)                       # no colour mode data
	_u32(f, 0)                       # no image resources

	# --- layer section, built in memory so its length can be written first ---
	var layers_blob: PackedByteArray = _psd_layers(visible, w, h)
	_u32(f, layers_blob.size() + 4)
	_u32(f, layers_blob.size())
	f.store_buffer(layers_blob)

	# --- the flattened composite every reader falls back to ---
	_u16(f, 0)                       # raw
	f.store_buffer(_plane(flat, 0, w, h))
	f.store_buffer(_plane(flat, 1, w, h))
	f.store_buffer(_plane(flat, 2, w, h))
	f.store_buffer(_plane(flat, 3, w, h))
	f.close()
	return path

static func _psd_layers(entries: Array, w: int, h: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	_bu16(out, entries.size())

	var plane_size: int = w * h + 2   # two bytes of compression flag each
	for e in entries:
		var l: LayerStack.Layer = e["layer"]
		_bu32(out, 0)
		_bu32(out, 0)
		_bu32(out, h)
		_bu32(out, w)
		_bu16(out, 4)                                  # four channels
		for ch in [-1, 0, 1, 2]:                       # A, R, G, B
			_bu16(out, ch & 0xFFFF)
			_bu32(out, plane_size)
		out.append_array("8BIM".to_ascii_buffer())
		out.append_array("norm".to_ascii_buffer())
		out.append(int(clampf(l.opacity, 0.0, 1.0) * 255.0))
		out.append(0)                                  # clipping
		out.append(0 if l.visible else 2)              # bit 1 = hidden
		out.append(0)                                  # filler

		var name_bytes: PackedByteArray = _pascal(l.title)
		_bu32(out, 4 + 4 + name_bytes.size())
		_bu32(out, 0)                                  # no mask
		_bu32(out, 0)                                  # no blending ranges
		out.append_array(name_bytes)

	for e in entries:
		var img: Image = e["image"]
		for ch in [3, 0, 1, 2]:                        # A, R, G, B
			_bu16(out, 0)                              # raw
			out.append_array(_raw_plane(img, ch, w, h))
	if out.size() % 2 == 1:
		out.append(0)
	return out

## One channel of an image as a flat byte plane, padded if the layer is
## smaller than the canvas.
static func _plane(img: Image, ch: int, w: int, h: int) -> PackedByteArray:
	return _raw_plane(img, ch, w, h)

static func _raw_plane(img: Image, ch: int, w: int, h: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(w * h)
	if img == null:
		out.fill(0)
		return out
	var iw: int = img.get_width()
	var ih: int = img.get_height()
	var d: PackedByteArray = img.get_data()
	for y in range(h):
		var row: int = y * w
		if y >= ih:
			continue
		for x in range(w):
			if x >= iw:
				continue
			out[row + x] = d[((y * iw) + x) * 4 + ch]
	return out

static func _pascal(text: String) -> PackedByteArray:
	var raw: PackedByteArray = text.substr(0, 250).to_utf8_buffer()
	var out: PackedByteArray = PackedByteArray()
	out.append(raw.size())
	out.append_array(raw)
	while out.size() % 4 != 0:
		out.append(0)
	return out

# PSD is big endian throughout; Godot writes little endian, hence these.
static func _u16(f: FileAccess, v: int) -> void:
	f.store_8((v >> 8) & 0xFF)
	f.store_8(v & 0xFF)

static func _u32(f: FileAccess, v: int) -> void:
	f.store_8((v >> 24) & 0xFF)
	f.store_8((v >> 16) & 0xFF)
	f.store_8((v >> 8) & 0xFF)
	f.store_8(v & 0xFF)

static func _bu16(b: PackedByteArray, v: int) -> void:
	b.append((v >> 8) & 0xFF)
	b.append(v & 0xFF)

static func _bu32(b: PackedByteArray, v: int) -> void:
	b.append((v >> 24) & 0xFF)
	b.append((v >> 16) & 0xFF)
	b.append((v >> 8) & 0xFF)
	b.append(v & 0xFF)

# --------------------------------------------------------------------- GIF

## Frame rates that divide 100 evenly. GIF measures delays in hundredths of
## a second, so 24 fps would become 25 and the whole clip would run four per
## cent fast — a mistake that is invisible until it is played beside sound.
const GIF_RATES: Array = [10, 12, 20, 25, 50]

static func gif_rate_for(fps: int) -> int:
	var best: int = 12
	var gap: int = 1 << 30
	for r in GIF_RATES:
		var d: int = absi(int(r) - fps)
		if d < gap:
			gap = d
			best = int(r)
	return best

## `width` of 0 keeps the full size. Anything smaller is the single biggest
## lever on file size, so the exporter offers it plainly.
static func save_gif(p: ProjectManager.Project, width: int) -> String:
	var dir: String = ensure_dir()
	var frames: Array = _sized_frames(p, width, 400)
	if frames.is_empty():
		return ""
	var rate: int = gif_rate_for(p.fps)
	var data: PackedByteArray = GifEncoder.encode(frames,
		int(100.0 / float(rate)))
	if data.is_empty():
		return ""
	var path: String = "%s/%s.gif" % [dir, base_name(p)]
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_buffer(data)
	f.close()
	return path

## Animated WebP: full colour, real transparency, and a fraction of the
## size of the same clip as GIF, because the compression underneath is a
## video codec rather than one from 1987.
static func save_webp_anim(p: ProjectManager.Project, width: int) -> String:
	var dir: String = ensure_dir()
	var frames: Array = _sized_frames(p, width, 900)
	if frames.is_empty():
		return ""
	var delay: int = int(1000.0 / float(clampi(p.fps, 1, 60)))
	var data: PackedByteArray = WebpAnim.encode(frames, delay)
	if data.is_empty():
		return ""
	var path: String = "%s/%s.webp" % [dir, base_name(p)]
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_buffer(data)
	f.close()
	return path

## Every frame, brought down to a chosen width.
##
## The scaling happens here rather than inside `render_frames`, because a PNG
## sequence wants full size and a GIF very much does not — and because doing
## it once per frame as they come off the renderer costs a great deal less
## memory than rendering them all at full size and reducing afterwards.
##
## Frames are compared as they are made: a drawing held over several frames is
## the same object each time, so it is resized once and shared. On a scene
## animated on twos that halves the work, and on a held pose it does far
## better than that.
static func _sized_frames(p: ProjectManager.Project, width: int,
		limit: int) -> Array:
	var raw: Array = render_frames(p, limit)
	var out: Array = []
	var done: Dictionary = {}
	for one in raw:
		var img: Image = one
		var key: int = img.get_instance_id()
		if done.has(key):
			out.append(done[key])
			continue
		var made: Image = img
		if width > 0 and made.get_width() > width:
			var scale: float = float(width) / float(made.get_width())
			made = made.duplicate()
			made.resize(width,
				maxi(int(float(made.get_height()) * scale), 1),
				Image.INTERPOLATE_TRILINEAR)
		if made.get_format() != Image.FORMAT_RGBA8:
			if made == img:
				made = made.duplicate()
			made.convert(Image.FORMAT_RGBA8)
		done[key] = made
		out.append(made)
	return out

## Rough size of a GIF before spending a minute making one.
static func gif_estimate_mb(p: ProjectManager.Project, width: int,
		seconds: float) -> float:
	var w: float = float(width) if width > 0 else p.page.x
	var h: float = w * (p.page.y / maxf(p.page.x, 1.0))
	var per_frame: float = w * h * 0.25 / 1048576.0   # LZW on flat art
	# The scene's own length when it has one, rather than a figure passed in
	# from a slider that was guessing. `seconds` is still honoured when there
	# is no clip to ask.
	var count: float = float(frame_count(p))
	if count > 1.0:
		return per_frame * count
	return per_frame * float(gif_rate_for(p.fps)) * seconds
