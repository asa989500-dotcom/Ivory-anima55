class_name AudioImport
extends RefCounted
## Getting sound off the device and into a scene.
##
## Lifted out of `main.gd`, which is the longest file in the project and was
## carrying this whole subject — the picker, the format list, the flash
## messages and the playback wiring — inside a class that is otherwise about
## laying out a room.
##
## The seam is a good one: everything here is about *files on a phone* and
## none of it is about IVORY's own state beyond "which layer asked". The main
## room keeps two four-line wrappers so `timeline.audio_wanted` still lands
## somewhere that knows what a layer is.

## The picker, kept between openings.
##
## A `FileDialog` is a node, and building a new one for every import would
## lose whatever folder the last one was left in — which on a phone, where
## music is three taps deep, is the difference between adding eleven sounds
## and giving up after four.
static var _picker: FileDialog = null
static var _last_dir: String = ""
static var _preview: AudioPreview = null

## Picks sounds for a layer, through the platform's own file picker.
##
## Several at once, because that is how sound arrives: a scene is a score and
## eleven effects, not one file eleven times.
static func pick(host: Node) -> void:
	if _picker == null:
		_picker = FileDialog.new()
		_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILES
		_picker.access = FileDialog.ACCESS_FILESYSTEM
		_picker.use_native_dialog = DisplayServer.has_feature(
			DisplayServer.FEATURE_NATIVE_DIALOG_FILE)
		_picker.title = UiKit.label_for("Import audio", "استيراد صوت")
		_picker.filters = AudioBank.filters()
		_picker.files_selected.connect(func(paths: PackedStringArray) -> void:
			host.call("_take_audio", paths))
		# The native picker on some platforms only ever reports one file, and
		# it reports it through the other signal. Both are listened to so a
		# single choice is never silently dropped.
		_picker.file_selected.connect(func(one: String) -> void:
			host.call("_take_audio", PackedStringArray([one])))
		host.add_child(_picker)
	var start: String = _last_dir
	for guess in [OS.get_system_dir(OS.SYSTEM_DIR_MUSIC),
			OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS),
			OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)]:
		if start != "" and DirAccess.dir_exists_absolute(start):
			break
		start = String(guess)
	if start != "" and DirAccess.dir_exists_absolute(start):
		_picker.current_dir = start
	_picker.popup_centered_ratio(0.9)

## Adds every chosen file to the layer, starting at the playhead.
##
## Nothing is decoded here and nothing is copied. Adding twelve tracks takes
## as long as adding one, which is the whole point: the expensive part is the
## first export, it happens once, and its result is cached.
static func take(host: Node, paths: PackedStringArray, layer_index: int) -> void:
	var p: ProjectManager.Project = host.call("current_project")
	var view: Object = host.get("view")
	if p == null or p.clip == null or view == null or view.layers == null:
		return
	if layer_index < 0 or layer_index >= view.layers.layers.size():
		return
	var l: LayerStack.Layer = view.layers.layers[layer_index]
	var at: int = maxi(view.layers.shown_frame, 0)
	var taken: int = 0
	var refused: String = ""
	for one in paths:
		var path: String = String(one)
		if path == "":
			continue
		_last_dir = path.get_base_dir()
		if not AudioBank.supported(path):
			refused = AudioBank.trouble_words("unsupported")
			continue
		if p.clip.audio.add(path, l.id, at) != null:
			taken += 1
	if taken > 0:
		view.projects.mark_dirty(p)
		var timeline: Object = host.get("timeline")
		if timeline != null:
			timeline.call("refresh")
	if taken == 0:
		host.call("_flash", refused if refused != "" else UiKit.label_for(
			"No sound was added", "لم يُضف أي صوت"))
	elif taken == 1:
		host.call("_flash", "%s  ·  %s" % [
			UiKit.label_for("Added", "أُضيف"), String(paths[0]).get_file()])
	else:
		host.call("_flash", Lang.fill("{0} sounds added", [taken],
			"أُضيف {0} صوتاً"))

## Sound while the timeline plays.
##
## Wired here rather than inside the player because the player's job is timing
## and this one's is noise, and a scene with no sound in it should not pay for
## a mixer it never uses — the preview is built the first time a timeline is
## opened and then follows whichever project is in front.
static func hook_preview(host: Node, p: ProjectManager.Project) -> void:
	var view: Object = host.get("view")
	if view == null or view.player == null or p == null:
		return
	if _preview == null or not is_instance_valid(_preview):
		_preview = AudioPreview.new()
		host.add_child(_preview)
		view.player.playing_changed.connect(func(on: bool) -> void:
			if _preview == null or not is_instance_valid(_preview):
				return
			if on:
				_preview.begin(int(view.player.frame))
			else:
				_preview.silence())
		view.player.frame_index_changed.connect(func(f: int) -> void:
			if _preview != null and is_instance_valid(_preview) \
					and view.player.playing:
				_preview.step(f))
	_preview.clip = p.clip
	_preview.track = p.clip.audio if p.clip != null else null
