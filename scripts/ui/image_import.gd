class_name ImageImport
extends RefCounted
## Bringing a picture in from the device.
##
## The platform's own file picker, the last folder it was left in, the formats
## Godot can actually read, and the conversion every incoming picture needs:
## sized to sit inside the page, turned premultiplied like everything the
## canvas holds, and left floating so it can be moved before it is committed.
##
## Two callers now — the layer's *Import image*, and the design room's
## *Import a picture* — which is why it stopped being a private corner of
## `main.gd` and became something with a name. The room does not know a file
## dialog exists; it asks, and a picture arrives.

## Godot's own browser rather than the system picker: the system picker
## hands back a content URI that this engine cannot open, while the browser
## returns a real path Image.load understands. It starts in the folder the
## camera and the download manager write to, which is where a picture the
## user means to place almost always is.
static func ask_for_image(host: MainRoom, layer_index: int) -> void:
	if not host.view.has_project() and not host._import_for_ai:
		host._flash(UiKit.label_for("Open a project first", "افتح مشروعاً أولاً"))
		return
	host._import_into = layer_index

	# Android uses the native Storage Access Framework so scoped storage,
	# Downloads, Photos and provider-backed files work exactly like a normal
	# Android app. The desktop FileDialog remains the fallback.
	if AndroidPlatform.file_picker_available():
		var native_picker: Object = AndroidPlatform.picker()
		if native_picker != null:
			if not native_picker.file_picked.is_connected(host._place_image):
				native_picker.file_picked.connect(host._place_image)
			native_picker.openFilePicker("image/*")
			return
	if host._picker == null:
		host._picker = FileDialog.new()
		host._picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		host._picker.access = FileDialog.ACCESS_FILESYSTEM
		host._picker.use_native_dialog = DisplayServer.has_feature(
			DisplayServer.FEATURE_NATIVE_DIALOG_FILE)
		host._picker.size = Vector2i(int(UiKit.s(560.0)), int(UiKit.s(520.0)))
		host._picker.show_hidden_files = false
		host._picker.title = UiKit.label_for("Import image", "استيراد صورة")
		host._picker.filters = PackedStringArray([
			"*.png, *.jpg, *.jpeg, *.webp, *.bmp, *.tga, *.svg, *.tif, *.tiff, *.hdr, *.exr, *.dds, *.ktx, *.qoi ; Images",
			"*.png ; PNG", "*.jpg, *.jpeg ; JPEG", "*.webp ; WebP",
			"*.bmp ; BMP", "*.tga ; TGA", "*.svg ; SVG",
			"*.tif, *.tiff ; TIFF", "*.hdr ; HDR", "*.exr ; OpenEXR",
			"*.dds ; DDS", "*.ktx ; KTX", "*.qoi ; QOI",
		])
		host._picker.file_selected.connect(host._place_image)
		host._ui.add_child(host._picker)
	# Where it was left last time, else the camera roll, else downloads.
	# Hunting for the same folder on every import is the whole friction.
	var start: String = host._last_import_dir
	if start == "" or not DirAccess.dir_exists_absolute(start):
		start = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if start == "" or not DirAccess.dir_exists_absolute(start):
		start = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if start != "" and DirAccess.dir_exists_absolute(start):
		host._picker.current_dir = start
	host._picker.popup_centered_ratio(0.9)

static func load_path(path: String, max_side: int = 4096) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var img: Image = null

	# General image import is deliberately independent of the retired reference intake
	# service. Godot decodes the image, then we apply the same bounded RGBA8
	# policy used by the rest of IVORY.
	img = Image.new()
	if img.load(path) != OK or img.get_width() < 1 or img.get_height() < 1:
		return {"ok": false, "error": "Image could not be decoded", "native": false, "micros": Time.get_ticks_usec() - started}
	if img.get_width() > max_side or img.get_height() > max_side:
		var scale: float = minf(float(max_side) / float(img.get_width()), float(max_side) / float(img.get_height()))
		img.resize(maxi(1, int(img.get_width() * scale)), maxi(1, int(img.get_height() * scale)), Image.INTERPOLATE_BILINEAR)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	Perf.note("image_import", Time.get_ticks_usec() - started)
	return {"ok": true, "image": img, "native": false, "micros": Time.get_ticks_usec() - started,
		"source_width": img.get_width(), "source_height": img.get_height()}

static func place_image(host: MainRoom, path: String) -> void:
	host._last_import_dir = path.get_base_dir()
	var project: ProjectManager.Project = host.current_project()
	if project == null and not host._import_for_ai:
		return
	var decode_side: int = 4096
	if project != null:
		decode_side = clampi(int(ceil(maxf(project.page.x, project.page.y) * 0.92)), 512, 4096)
	var result: Dictionary = load_path(path, decode_side)
	if not bool(result.get("ok", false)):
		host._flash(UiKit.label_for("That image is too large or could not be read",
			"الصورة كبيرة جداً أو تعذّرت قراءتها"))
		return
	var img: Image = result["image"]

	# A picture asked for by the design room goes to the room, not onto a
	# layer. Same picker, same formats, same last-folder memory — the only
	# difference is where it lands, and routing it here means the room never
	# has to know a file dialog exists.
	if host._import_for_ai:
		host._import_for_ai = false
		premultiply(img)
		if host._ai_room != null:
			host._ai_room.take_import(img)
		return

	var p: ProjectManager.Project = project
	if p == null:
		return
	# Sized to sit inside the page rather than dwarf it, keeping its shape.
	var room: Vector2 = p.page * 0.92
	var factor: float = minf(room.x / maxf(float(img.get_width()), 1.0),
		room.y / maxf(float(img.get_height()), 1.0))
	if factor < 0.999:
		img.resize(maxi(int(float(img.get_width()) * factor), 1),
			maxi(int(float(img.get_height()) * factor), 1),
			Image.INTERPOLATE_LANCZOS)

	# The canvas stores premultiplied pixels; an imported file does not.
	premultiply(img)

	var stack: LayerStack = p.stack
	var index: int = clampi(host._import_into, 0, maxi(stack.layers.size() - 1, 0))
	stack.set_active(index)

	# Centred on the page being looked at, and floating: a picture almost
	# never lands where it is finally wanted, so it arrives as something
	# still movable rather than as a decision already made.
	# Page-local: the floating piece lands in the middle of the page being
	# worked on, whichever page that is.
	host.view.float_image(img, stack.layers[index].id, p.page * 0.5)
	host.view.projects.mark_dirty(p)
	host._close_panel()
	host._flash(UiKit.label_for("Drag it, then Place", "حرّكها ثم ثبّت"))

## Ordinary pixels turned into the premultiplied ones the canvas keeps.
##
## Takes no host, because it never needed one: it is arithmetic on an image
## and nothing else. The lift gave every moved function a host parameter
## without asking whether it used one, which is a thing the lift should
## notice — see the note in `tools/lift_module.py`.
static func premultiply(img: Image) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var d: PackedByteArray = img.get_data()
	for i in range(w * h):
		var o: int = i * 4
		var a: int = d[o + 3]
		if a == 255:
			continue
		if a == 0:
			d[o] = 0
			d[o + 1] = 0
			d[o + 2] = 0
			continue
		d[o] = int(float(d[o]) * float(a) / 255.0)
		d[o + 1] = int(float(d[o + 1]) * float(a) / 255.0)
		d[o + 2] = int(float(d[o + 2]) * float(a) / 255.0)
	img.set_data(w, h, false, Image.FORMAT_RGBA8, d)
