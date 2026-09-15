class_name Vault
extends RefCounted
## Keeps work on disk so closing the app is not the same as losing it.
##
## Each project is a folder: one small text file describing the document —
## its size, colours, layers, folders, order — and one PNG per layer holding
## that layer's pixels, cropped to whatever it actually contains.
##
## Storing layers as ordinary PNGs rather than one private blob is a
## deliberate choice. It means the work is recoverable with a file browser
## even if this app is gone, which is the kind of promise a drawing program
## should be able to make.
##
## Saving happens on a timer, on closing a project, and when the app is
## about to quit. The timer only fires when something has actually changed,
## so a workspace being looked at rather than drawn on costs nothing.

const ROOT: String = "user://projects"
const MANIFEST: String = "project.json"
const INTERVAL: float = 25.0

static func _dir_of(id: int) -> String:
	return "%s/p%d" % [ROOT, id]

# ------------------------------------------------------------------ saving

## A project still being positioned is not yet a project. Writing one meant
## that a sheet conjured by opening the dialog and then abandoned came back
## on the next launch as something the user never made and could not place.
static func save(p: ProjectManager.Project) -> bool:
	if p == null or p.state == ProjectManager.State.FLOATING:
		return false
	var dir: String = _dir_of(p.id)
	DirAccess.make_dir_recursive_absolute(dir)

	# Settle every page before a single byte is written.
	#
	# This was the hole in autosave, and it was a quiet one. A stroke lives in
	# three places on its way to disk: dabs queued on the GPU, the CPU mirror
	# of the surface, and the compressed cel the frame keeps. `flush` folds the
	# first into the second and `commit` folds the second into the third, and
	# neither was being called here — so a save that landed a moment after the
	# hand lifted wrote the layer *without the last dabs of the stroke*, and
	# wrote a cel dictionary still holding whatever was there at the last
	# frame change. On a timeline that is every drawing except the one being
	# worked on.
	#
	# Both calls are cheap when there is nothing pending, which is the usual
	# case: `flush` returns at once with an empty queue, and `commit` only
	# writes the one cel the surface is holding.
	for page in p.sheets:
		var sheet: ProjectManager.Page = page
		if sheet.stack == null:
			continue
		sheet.stack.flush_all()
		sheet.stack.commit_all_cels()

	var pages_out: Array = []
	for i in p.sheets.size():
		pages_out.append(_page_doc(p.sheets[i] as ProjectManager.Page, dir, i))

	var doc: Dictionary = {
		"version": 2,
		"id": p.id,
		"title": p.title,
		"kind": p.kind,
		"created": p.created,
		"origin_x": p.origin.x, "origin_y": p.origin.y,
		"page_w": p.page.x, "page_h": p.page.y,
		"pages": p.pages,
		"paper": p.paper.to_html(true),
		"frame": p.frame.to_html(true),
		"favourite": p.favourite,
		"grid_guide": p.grid_guide,
		"fps": p.fps, "frames": p.frames, "onion": p.onion_skin,
		"export_kind": p.export_kind, "export_format": p.export_format, "export_width": p.export_width,
		"export_crf": p.export_crf, "export_bitrate": p.export_bitrate,
		"export_resolution": p.export_resolution, "export_audio": p.export_audio,
		"export_profile": p.export_profile, "export_quality": p.export_quality,
		"export_range": p.export_range, "export_from": p.export_from,
		"export_to": p.export_to, "export_preset": p.export_preset,
		"export_audio_kbps": p.export_audio_kbps,
		"animation_ui": p.animation_ui,
		"stretchy_document": p.stretchy_document,
		"cut_points": p.cut_points,
		"onion_back": p.onion_back, "onion_forward": p.onion_forward,
		"onion_back_tint": p.onion_back_tint.to_html(true),
		"onion_highlight": p.onion_highlight.to_html(true),
		"onion_forward_tint": p.onion_forward_tint.to_html(true),
		"looping": p.looping,
		"stacked": p.stacked,
		"active_page": p.active_page,
		"pages_data": pages_out,
	}

	# The manifest is the commit point. Keep the previous manifest as a recovery
	# copy, and only write it after every page/layer image has succeeded. If a
	# save is interrupted, the last known-good document can still be restored.
	var manifest_path: String = "%s/%s" % [dir, MANIFEST]
	var backup_path: String = "%s/%s.bak" % [dir, MANIFEST]
	if FileAccess.file_exists(manifest_path):
		var old: FileAccess = FileAccess.open(manifest_path, FileAccess.READ)
		if old != null:
			var old_bytes: PackedByteArray = old.get_buffer(old.get_length())
			old.close()
			var backup: FileAccess = FileAccess.open(backup_path, FileAccess.WRITE)
			if backup != null:
				backup.store_buffer(old_bytes)
				backup.close()

	# Written beside the real file and then renamed over it.
	#
	# Opening the manifest itself for writing empties it *first* and fills it
	# afterwards, so between those two moments the document on disk is
	# garbage. That window is short and it is not rare: this app autosaves,
	# and Android kills backgrounded apps as a matter of routine — being
	# killed inside that window is a normal Tuesday, not bad luck.
	#
	# A rename is atomic on every filesystem this will ever run on. Do the
	# writing somewhere harmless, then swap it in with one operation that
	# either happened or did not, and the manifest is only ever wholly the
	# old document or wholly the new one. The `.bak` copy above stays as a
	# second line of defence, but it is no longer the *first* one.
	var temp_path: String = "%s/%s.writing" % [dir, MANIFEST]
	var f: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(doc, "\t"))
	f.flush()
	f.close()

	# Checked before it is trusted. A disk that filled up mid-write returns
	# no error from `store_string` and leaves a short file, and renaming that
	# over a good document destroys the good one.
	var written: FileAccess = FileAccess.open(temp_path, FileAccess.READ)
	if written == null:
		return false
	var length: int = int(written.get_length())
	written.close()
	if length < 8:
		DirAccess.remove_absolute(temp_path)
		return false

	var swap: Error = DirAccess.rename_absolute(temp_path, manifest_path)
	if swap != OK:
		DirAccess.remove_absolute(temp_path)
		return false
	return true

## One page written out: its layers as PNGs, its folders, its order.
static func _page_doc(page: ProjectManager.Page, dir: String, index: int) -> Dictionary:
	var rows: Array = []
	for l in page.stack.layers:
		var box: Rect2i = l.surface.content_bounds()
		var file: String = ""
		var at: Vector2i = Vector2i.ZERO
		if box.size.x > 0 and box.size.y > 0:
			var img: Image = l.surface.read_region(box)
			if img != null:
				file = "page%d_layer_%d.png" % [index, l.id]
				if img.save_png("%s/%s" % [dir, file]) != OK:
					file = ""
				else:
					at = box.position
		var row: Dictionary = {
			"id": l.id, "title": l.title, "group": l.group_id,
			"opacity": l.opacity, "visible": l.visible, "locked": l.locked,
			"background": l.is_background, "file": file, "glow": l.glow,
			"bone_layer": l.is_bone_layer,
			"character360": l.is_character360,
			"character360_motion": l.is_character360_motion,
			# As two numbers. A Vector2 written straight in comes back as the
			# string "(12, 34)" and throws on assignment, which stopped the app
			# opening at all.
			"motion_position": _vec_to_doc(l.motion_position),
			"motion_rotation": l.motion_rotation,
			"motion_scale": l.motion_scale,
			"born_at": l.born_at, "gone_at": l.gone_at,
			"x": at.x, "y": at.y,
		}
		if not l.cels.is_empty():
			row["cels"] = l.cels.to_dict()
		# The skeleton and the writing are part of the layer, not decoration
		# on top of it — a figure that has been rigged should still be rigged
		# tomorrow, and text should still be text rather than ink.
		if not l.rig.is_empty():
			row["rig"] = _rig_to_doc(l.rig)
		# The poses that rig takes over time. Written only when there are
		# any, so a file for an unrigged drawing carries no empty block —
		# and so a project made before this existed reads back unchanged.
		if l.poses != null and not l.poses.is_empty():
			row["poses"] = l.poses.to_dict()
		# The sync ring is thirty-two numbers and a centre. It is drawn once
		# by hand and would be tedious to draw again, so it is kept.
		if l.mouth_ring != null and l.mouth_ring.is_ready():
			row["mouth_ring"] = l.mouth_ring.to_dict()
		# The sync track itself, which was never written down.
		#
		# The ring was saved and the mouths it was fitted for were not, so a
		# project reopened came back with a mouth that could be shaped and
		# nothing to shape it to: the sound had to be linked and analysed
		# again every session. It is one small number per frame.
		if l.sound_path != "":
			row["sound_path"] = l.sound_path
		if not l.mouths.is_empty():
			row["mouths"] = Array(l.mouths)
			if l.mouth_power.size() == l.mouths.size():
				row["mouth_power"] = Array(l.mouth_power)
		# How the figure trails behind its own pose. Kept because it is a
		# property of the character rather than of a moment — a cloak that
		# was heavy yesterday should still be heavy today.
		if l.dangle:
			row["dangle"] = true
			row["dangle_speed"] = l.dangle_speed
			row["dangle_damp"] = l.dangle_damp
			row["dangle_swing"] = l.dangle_swing
		if l.is_text:
			row["text"] = true
			row["text_state"] = _text_to_doc(l.text_state)
		if l.is_character360:
			# Every heavy buffer goes beside the manifest as its own file and
			# the manifest keeps only the name. This used to be written out
			# for `front_png` and `side_png` by hand; the Character 360 room adds a
			# base drawing and up to forty pose references, so the rule is
			# now general rather than a list of two.
			row["character360_state"] = _c360_to_doc(
				l.character360_state, dir, index, l.id)
		rows.append(row)
	var folders: Array = []
	for g in page.stack.groups:
		folders.append({
			"id": g.id, "title": g.title, "opacity": g.opacity,
			"visible": g.visible, "collapsed": g.collapsed,
			"animation": g.is_animation,
			"switch": g.is_switch, "switch_index": g.switch_index,
		})
	var out: Dictionary = {
		"layers": rows, "groups": folders,
		"active": page.stack.active_index,
		"clip": Anim.to_dict(page.clip),
	}
	# The frames this page is cut into. Written only when there are any, so a
	# file for a drawing carries no empty block and a project made before
	# frames existed reads back unchanged.
	#
	# It goes on the page rather than on the project for the same reason the
	# layers do: a page is a drawing in its own right, and one layout across
	# several pages would have to say what page two's third frame is while
	# page one is being cut.
	if page.frames != null:
		out["frames"] = page.frames.to_dict()
	return out

static func save_all(manager: ProjectManager) -> int:
	var n: int = 0
	for p in manager.projects:
		if save(p):
			n += 1
	return n

## Wipes every saved project. The way out when something on disk is not
## wanted and no amount of tapping will remove it.
static func forget_all() -> void:
	var root: DirAccess = DirAccess.open(ROOT)
	if root == null:
		return
	for folder in root.get_directories():
		_wipe("%s/%s" % [ROOT, folder])

## Folders on disk with no project in the workspace to match them. They are
## what a crash between writing and loading leaves behind.
static func orphan_count(manager: ProjectManager) -> int:
	var root: DirAccess = DirAccess.open(ROOT)
	if root == null:
		return 0
	var live: Dictionary = {}
	for p in manager.projects:
		live["p%d" % p.id] = true
	var n: int = 0
	for folder in root.get_directories():
		if not live.has(folder):
			n += 1
	return n

static func forget(id: int) -> void:
	var dir: String = _dir_of(id)
	var d: DirAccess = DirAccess.open(dir)
	if d == null:
		return
	for file in d.get_files():
		d.remove(file)
	DirAccess.remove_absolute(dir)

# ----------------------------------------------------------------- loading

## Folders whose project is not in the workspace. Left behind by the id
## renumbering above, and by any crash between writing and loading.
static func purge_orphans(manager: ProjectManager) -> int:
	var root: DirAccess = DirAccess.open(ROOT)
	if root == null:
		return 0
	var live: Dictionary = {}
	for p in manager.projects:
		live["p%d" % p.id] = true
	var gone: int = 0
	for folder in root.get_directories():
		if live.has(folder):
			continue
		# Never destroy an orphan automatically. A crash, interrupted copy, or
		# an older IVORY version can leave a perfectly recoverable project here.
		# Storage can report it and the user can explicitly forget it.
		gone += 1
	return gone

static func load_all(manager: ProjectManager) -> int:
	var root: DirAccess = DirAccess.open(ROOT)
	if root == null:
		return 0
	var count: int = 0
	for folder in root.get_directories():
		var dir: String = "%s/%s" % [ROOT, folder]
		# Loading is read-only. A malformed or interrupted project must never be
		# destroyed just because the app could not parse it on this launch.
		if _load_one(manager, dir):
			count += 1
	return count

static func _wipe(dir: String) -> void:
	var d: DirAccess = DirAccess.open(dir)
	if d == null:
		return
	for file in d.get_files():
		d.remove(file)
	DirAccess.remove_absolute(dir)

static func _load_one(manager: ProjectManager, dir: String) -> bool:
	var manifest_path: String = "%s/%s" % [dir, MANIFEST]
	var f: FileAccess = FileAccess.open(manifest_path, FileAccess.READ)
	var parsed: Variant = null
	if f != null:
		parsed = JSON.parse_string(f.get_as_text())
		f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		var backup_path: String = "%s/%s.bak" % [dir, MANIFEST]
		if FileAccess.file_exists(backup_path):
			var bf: FileAccess = FileAccess.open(backup_path, FileAccess.READ)
			if bf != null:
				parsed = JSON.parse_string(bf.get_as_text())
				bf.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var doc: Dictionary = parsed
	# A folder that does not describe a whole project is a leftover from an
	# interrupted write. Showing it as an empty sheet nobody can open is
	# worse than never showing it at all.
	var is_current: bool = doc.has("pages_data") and doc.has("page_w") and doc.has("page_h")
	var is_legacy: bool = doc.has("layers") and doc.has("page_w") and doc.has("page_h")
	if not is_current and not is_legacy:
		# If the live manifest is damaged, try the recovery copy before giving up.
		var bak_path: String = "%s/%s.bak" % [dir, MANIFEST]
		if FileAccess.file_exists(bak_path):
			var bf: FileAccess = FileAccess.open(bak_path, FileAccess.READ)
			if bf != null:
				var recovered: Variant = JSON.parse_string(bf.get_as_text())
				bf.close()
				if typeof(recovered) == TYPE_DICTIONARY:
					doc = recovered
					is_current = doc.has("pages_data") and doc.has("page_w") and doc.has("page_h")
					is_legacy = doc.has("layers") and doc.has("page_w") and doc.has("page_h")
		if not is_current and not is_legacy:
			return false
	if float(doc.get("page_w", 0.0)) < 8.0 or float(doc.get("page_h", 0.0)) < 8.0:
		return false

	# The saved id comes back with the project. Without this, `create` handed
	# out a fresh one on every launch: the folder on disk kept its old name,
	# the next save wrote a *new* folder beside it, and the workspace filled
	# with copies until it hit its ceiling and refused to make anything.
	# Deleting removed the new folder and left the original, so the project
	# came back the next time. One line, and all three symptoms.
	var saved_id: int = int(doc.get("id", 0))
	if saved_id > 0 and manager.holds_id(saved_id):
		return false

	var p: ProjectManager.Project = manager.create(
		String(doc.get("title", "")),
		int(doc.get("kind", 0)),
		Vector2(float(doc.get("page_w", 1600.0)), float(doc.get("page_h", 1200.0))),
		Color(String(doc.get("paper", "#ffffffff"))),
		int(doc.get("pages", 1)),
		Vector2.ZERO)
	if p == null:
		return false

	if saved_id > 0:
		manager.reclaim_id(p, saved_id)
	p.created = String(doc.get("created", p.created))
	# Straight from the file, deliberately bypassing the tidy-up that
	# placing a new project does: a saved sheet belongs exactly where it was
	# left, even if that happens to be beside another one.
	p.origin = Vector2(float(doc.get("origin_x", 0.0)), float(doc.get("origin_y", 0.0)))
	p.frame = Color(String(doc.get("frame", "#1b1c22ff")))
	p.favourite = bool(doc.get("favourite", false))
	p.grid_guide = bool(doc.get("grid_guide", false))
	p.fps = int(doc.get("fps", 24))
	p.export_kind = String(doc.get("export_kind", ""))
	p.export_format = String(doc.get("export_format", "mp4_h264"))
	p.export_width = maxi(int(doc.get("export_width", 0)), 0)
	p.export_crf = clampi(int(doc.get("export_crf", 20)), 10, 40)
	p.export_bitrate = maxi(int(doc.get("export_bitrate", 0)), 0)
	p.export_resolution = String(doc.get("export_resolution", "Source"))
	p.export_audio = bool(doc.get("export_audio", true))
	p.export_profile = String(doc.get("export_profile", "high"))
	p.export_quality = String(doc.get("export_quality", "Good"))
	p.export_range = String(doc.get("export_range", "Timeline"))
	p.export_from = maxi(int(doc.get("export_from", 0)), 0)
	p.export_to = maxi(int(doc.get("export_to", 0)), 0)
	p.export_preset = String(doc.get("export_preset", "fast"))
	p.export_audio_kbps = clampi(int(doc.get("export_audio_kbps", 192)),
		64, 512)
	p.animation_ui = "stretchy" if String(doc.get("animation_ui", "ivory")) == "stretchy" else "ivory"
	p.stretchy_document = doc.get("stretchy_document", {}) as Dictionary
	if p.animation_ui == "stretchy":
		p.frame = Color("#000000")
	p.frames = int(doc.get("frames", 24))
	p.onion_skin = bool(doc.get("onion", true))
	p.cut_points = []
	for marker in doc.get("cut_points", []):
		if marker is Dictionary:
			var row: Dictionary = (marker as Dictionary).duplicate(true)
			row["page"] = clampi(int(row.get("page", 0)), 0, maxi(p.pages - 1, 0))
			p.cut_points.append(row)
	p.onion_back = clampi(int(doc.get("onion_back", 2)), 0, 8)
	p.onion_forward = clampi(int(doc.get("onion_forward", 1)), 0, 8)
	var onion_back_hex: String = String(doc.get("onion_back_tint", "e65a5a56"))
	var onion_mid_hex: String = String(doc.get("onion_highlight", "ffcc5556"))
	var onion_forward_hex: String = String(doc.get("onion_forward_tint", "598ce04d"))
	p.onion_back_tint = Color(onion_back_hex if onion_back_hex.begins_with("#") else "#" + onion_back_hex)
	p.onion_highlight = Color(onion_mid_hex if onion_mid_hex.begins_with("#") else "#" + onion_mid_hex)
	p.onion_forward_tint = Color(onion_forward_hex if onion_forward_hex.begins_with("#") else "#" + onion_forward_hex)
	p.looping = bool(doc.get("looping", true))

	p.stacked = bool(doc.get("stacked", false))
	var pages_in: Array = doc.get("pages_data", [])
	if pages_in.is_empty():
		# Written before pages had their own layers: the one stack it holds
		# belongs to page one, and the rest come back blank.
		_fill_page(p.page_at(0), dir, doc)
	else:
		for i in mini(pages_in.size(), p.sheets.size()):
			_fill_page(p.page_at(i), dir, pages_in[i])
	manager.set_page(p, int(doc.get("active_page", 0)))

	# Everything comes back closed. Waking every project at startup would
	# hand the graphics card a workspace's worth of tiles before the user
	# has decided which one they want.
	p.state = ProjectManager.State.CLOSED
	if manager.placing == p:
		manager.placing = null
	for page in p.sheets:
		for l in (page as ProjectManager.Page).stack.layers:
			l.surface.sleep_all()
	manager.move_to(p, p.origin)
	return true

static func _fill_page(page: ProjectManager.Page, dir: String,
		doc: Dictionary) -> void:
	if page == null:
		return
	# Read before the layers, and outside their guard: a page whose frames
	# were cut but which has nothing drawn on it yet has no layer rows, and
	# returning early would silently drop a layout somebody built.
	var frames_doc: Dictionary = doc.get("frames", {})
	if not frames_doc.is_empty():
		page.frames = ComicPage.from_dict(frames_doc)

	var rows: Array = doc.get("layers", [])
	if rows.is_empty():
		return

	# The stack always starts with a background and one empty layer; grow or
	# trim it to the saved count before filling anything in.
	while page.stack.layers.size() < rows.size():
		if page.stack.add_layer() == null:
			break
	while page.stack.layers.size() > rows.size() and page.stack.layers.size() > 1:
		page.stack.remove_layer(page.stack.layers.size() - 1)

	for i in rows.size():
		if i >= page.stack.layers.size():
			break
		var row: Dictionary = rows[i]
		var l: LayerStack.Layer = page.stack.layers[i]
		l.title = String(row.get("title", l.title))
		l.opacity = float(row.get("opacity", 1.0))
		l.visible = bool(row.get("visible", true))
		l.locked = bool(row.get("locked", false))
		l.is_background = bool(row.get("background", i == 0))
		l.glow = bool(row.get("glow", false))
		l.is_bone_layer = bool(row.get("bone_layer", false))
		l.is_character360 = bool(row.get("character360", false))
		l.is_character360_motion = bool(row.get("character360_motion", false))
		l.character360_state = _c360_from_doc(
			row.get("character360_state", {}) as Dictionary, dir)
		l.motion_position = _vec_from_doc(
			row.get("motion_position", l.motion_position), l.motion_position)
		l.motion_rotation = float(row.get("motion_rotation", l.motion_rotation))
		l.motion_scale = maxf(float(row.get("motion_scale", l.motion_scale)), 0.001)
		# Absent in every file written before layers had lifetimes, and the
		# values that mean "there from the start and never taken away".
		l.born_at = maxi(int(row.get("born_at", 0)), 0)
		l.gone_at = int(row.get("gone_at", -1))
		# Rigid unless the file says otherwise, which is what every project
		# written before secondary motion existed meant.
		l.dangle = bool(row.get("dangle", false))
		l.dangle_speed = clampf(float(row.get("dangle_speed", 3.0)),
			0.5, 20.0)
		l.dangle_damp = clampf(float(row.get("dangle_damp", 0.55)),
			0.05, 2.0)
		l.dangle_swing = clampf(float(row.get("dangle_swing", 1.4)),
			-1.0, 3.0)
		l.sound_path = String(row.get("sound_path", ""))
		if row.has("mouth_ring"):
			l.mouth_ring = MouthRing.from_dict(row["mouth_ring"])
		if row.has("mouths"):
			var said: PackedInt32Array = PackedInt32Array()
			for m in row["mouths"]:
				said.append(clampi(int(m), 0, Viseme.KEYS.size() - 1))
			l.mouths = said
			var force: PackedFloat32Array = PackedFloat32Array()
			for w in row.get("mouth_power", []):
				force.append(clampf(float(w), 0.0, 1.0))
			# A track written before loudness was carried has none. Full
			# strength throughout is exactly what those files meant, so that
			# is what they get rather than a silent mouth.
			if force.size() != said.size():
				force.resize(said.size())
				force.fill(1.0)
			l.mouth_power = force
		l.rig = _rig_from_doc(row.get("rig", {}))
		if row.has("poses"):
			l.poses = RigTrack.from_dict(row["poses"])
		l.is_text = bool(row.get("text", false))
		l.text_state = _text_from_doc(row.get("text_state", {}))
		# `front_png` and `side_png` from projects written before the general
		# rule existed. Everything newer is already restored by
		# `_c360_from_doc` above.
		if l.is_character360:
			for key in ["front_png", "side_png"]:
				if l.character360_state.get(key, null) is String:
					var bytes: PackedByteArray = _read_blob(
						dir, String(l.character360_state[key]))
					if not bytes.is_empty():
						l.character360_state[key] = bytes

		if row.has("cels"):
			l.cels.from_dict(row["cels"])

		var file: String = String(row.get("file", ""))
		if file == "":
			continue
		var img: Image = Image.new()
		if img.load("%s/%s" % [dir, file]) != OK:
			continue
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		# Written premultiplied, restored premultiplied, copied rather than
		# blended — so the trip through disk changes nothing at all.
		l.surface.blit_image(img,
			Vector2(float(row.get("x", 0)), float(row.get("y", 0))), true)

	# Folders last: each is rebuilt around its lowest saved member, then the
	# rest are pointed at the folder that member created.
	for row in doc.get("groups", []):
		var gid: int = int(row["id"])
		var first: int = -1
		for i in rows.size():
			if int(rows[i].get("group", 0)) == gid and i < page.stack.layers.size():
				first = i
				break
		if first < 0:
			continue
		var g: LayerStack.Group = page.stack.group_layer(first)
		if g == null:
			continue
		g.title = String(row.get("title", g.title))
		g.opacity = float(row.get("opacity", 1.0))
		g.visible = bool(row.get("visible", true))
		g.collapsed = bool(row.get("collapsed", false))
		# Defaulted, never required. A project saved before charts existed
		# has no such key, and every folder in it is an ordinary folder —
		# which is exactly what `false` says.
		g.is_switch = bool(row.get("switch", false))
		g.switch_index = maxi(int(row.get("switch_index", 0)), 0)
		g.is_animation = bool(row.get("animation", false))
		for i in rows.size():
			if i < page.stack.layers.size() and int(rows[i].get("group", 0)) == gid:
				page.stack.layers[i].group_id = g.id

	if doc.has("clip"):
		page.clip = Anim.from_dict(doc["clip"])
	page.stack.apply_arrangement(page.stack.capture_arrangement())
	page.stack.set_active(clampi(int(doc.get("active", 1)), 0,
		maxi(page.stack.layers.size() - 1, 0)))
	page.history.clear()


## Colours do not survive a trip through JSON as colours, so the two in a text
## layer's settings are written as strings and read back as colours. Anything
## else in there is already a number or a word and passes through untouched.
static func _text_to_doc(state: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in state.keys():
		var value: Variant = state[key]
		if value is Color:
			out[key] = (value as Color).to_html(true)
		else:
			out[key] = value
	return out

static func _text_from_doc(doc: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in doc.keys():
		var value: Variant = doc[key]
		if (key == "colour" or key == "halo_colour") and value is String:
			out[key] = Color(String(value))
		else:
			out[key] = value
	return out


# ---------------------------------------------------------------------------
# Types that do not survive JSON
# ---------------------------------------------------------------------------
#
# The project file is written with `JSON.stringify`, and JSON has four types.
# A Vector2 put into the document comes back out as the *string* "(12, 34)",
# and assigning that to a typed `Vector2` property throws at load time:
#
#     _fill_page: Invalid assignment of property or key 'motion_position'
#     with value of type 'String' on a base object of type 'RefCounted (Layer)'.
#
# which aborts the load, which is why the app would not open. A PackedByteArray
# is worse in a quieter way: it survives as an array of several hundred
# thousand numbers, so a project with reference drawings in it writes a JSON
# file tens of megabytes long and reads back an `Array` where the code expects
# bytes.
#
# So everything that is not a JSON type is converted on the way out and
# converted back on the way in, and the readers below accept every shape a
# file written by an older build could hold.

## A Vector2 as a two-number array, which is what JSON can carry.
static func _vec_to_doc(v: Vector2) -> Array:
	return [v.x, v.y]

## A Vector2 back out of whatever the file happens to hold.
##
## Four shapes are accepted, and each of them exists in some project folder
## somewhere: a real Vector2 (a document that never went through JSON), a
## two-number array (what this build writes), a dictionary with x and y, and
## the string "(12, 34)" that `JSON.stringify` produced for every file written
## before this was fixed. That last one is the whole reason this function is
## careful rather than a cast.
static func _vec_from_doc(value: Variant, fallback: Vector2) -> Vector2:
	match typeof(value):
		TYPE_VECTOR2:
			return value
		TYPE_ARRAY:
			var a: Array = value
			if a.size() >= 2:
				return Vector2(float(a[0]), float(a[1]))
		TYPE_PACKED_FLOAT32_ARRAY:
			var f: PackedFloat32Array = value
			if f.size() >= 2:
				return Vector2(f[0], f[1])
		TYPE_DICTIONARY:
			var d: Dictionary = value
			if d.has("x") and d.has("y"):
				return Vector2(float(d["x"]), float(d["y"]))
		TYPE_STRING:
			# "(12, 34)" — Godot's own text form, and the only thing older
			# files contain.
			var text: String = String(value).strip_edges().lstrip("(").rstrip(")")
			var parts: PackedStringArray = text.split(",")
			if parts.size() >= 2:
				return Vector2(float(parts[0].strip_edges()), float(parts[1].strip_edges()))
	return fallback

## A rig, with its bone endpoints turned into numbers.
##
## Bones carry `a` and `b` as Vector2. Written straight into the document they
## became strings, so a rigged figure reloaded with every bone at the origin —
## silently, because `rig` is an untyped Dictionary and nothing complained.
static func _rig_to_doc(rig: Dictionary) -> Dictionary:
	if rig.is_empty():
		return {}
	var out: Dictionary = rig.duplicate(true)
	var bones: Array = []
	for b in rig.get("bones", []):
		var row: Dictionary = (b as Dictionary).duplicate(true)
		row["a"] = _vec_to_doc(_vec_from_doc(row.get("a", Vector2.ZERO), Vector2.ZERO))
		row["b"] = _vec_to_doc(_vec_from_doc(row.get("b", Vector2.ZERO), Vector2.ZERO))
		bones.append(row)
	out["bones"] = bones
	return out

static func _rig_from_doc(doc: Variant) -> Dictionary:
	if not (doc is Dictionary):
		return {}
	var rig: Dictionary = (doc as Dictionary).duplicate(true)
	var bones: Array = []
	for b in rig.get("bones", []):
		var row: Dictionary = (b as Dictionary).duplicate(true)
		row["a"] = _vec_from_doc(row.get("a", Vector2.ZERO), Vector2.ZERO)
		row["b"] = _vec_from_doc(row.get("b", Vector2.ZERO), Vector2.ZERO)
		bones.append(row)
	rig["bones"] = bones
	return rig

## The Character 360 state, with every heavy buffer moved out to a file.
##
## `front_png` and `side_png` were already handled one pair at a time. Character 360
## reference room adds a base drawing and up to forty pose references, so the
## rule is now general: any value that is a block of bytes is written beside
## the manifest and replaced by its filename, and the manifest stays small
## enough to read.
static func _c360_to_doc(state: Dictionary, dir: String, index: int, layer_id: int) -> Dictionary:
	var out: Dictionary = state.duplicate(true)

	for key in out.keys():
		if out[key] is PackedByteArray:
			var name: String = "page%d_c360_%d_%s.bin" % [index, layer_id, String(key)]
			if _write_blob(dir, name, out[key]):
				out[key] = name
		elif out[key] is PackedFloat32Array:
			# JSON has one number type; a packed float array comes back as a
			# plain Array, so it is written as one and rebuilt on load.
			var numbers: Array = []
			for f in (out[key] as PackedFloat32Array):
				numbers.append(float(f))
			out[key] = numbers

	# The reference list. `turn_discs` is the same rows under an older name,
	# so it is aliased rather than written twice — forty drawings written out
	# a second time is forty megabytes for nothing.
	for list_key in ["pose_references", "turn_discs"]:
		if list_key == "turn_discs" and out.has("pose_references"):
			continue
		if not (out.get(list_key, null) is Array):
			continue
		var refs: Array = []
		var slot: int = 0
		for entry in out[list_key]:
			if not (entry is Dictionary):
				refs.append(entry)
				continue
			var row: Dictionary = (entry as Dictionary).duplicate(true)
			if row.get("png", null) is PackedByteArray:
				var name: String = "page%d_c360_%d_ref%d.png" % [index, layer_id, slot]
				if _write_blob(dir, name, row["png"]):
					row["png"] = name
			refs.append(row)
			slot += 1
		out[list_key] = refs

	# `turn_discs` is the same list under an older name. Written once and
	# aliased on load, so a project with forty references does not carry
	# eighty copies of the artwork.
	if out.has("pose_references") and out.has("turn_discs"):
		out["turn_discs"] = "@pose_references"
	return out

static func _c360_from_doc(state: Dictionary, dir: String) -> Dictionary:
	var out: Dictionary = state.duplicate(true)

	for key in out.keys():
		if key == "pose_references" or key == "turn_discs":
			continue
		if out[key] is String and String(out[key]).ends_with(".bin"):
			var bytes: PackedByteArray = _read_blob(dir, String(out[key]))
			if not bytes.is_empty():
				out[key] = bytes
	for key in ["reference_angles", "reference_angles_deg"]:
		if out.get(key, null) is Array:
			var packed: PackedFloat32Array = PackedFloat32Array()
			for n in out[key]:
				packed.append(float(n))
			out[key] = packed

	if out.get("pose_references", null) is Array:
		var refs: Array = []
		for entry in out["pose_references"]:
			if not (entry is Dictionary):
				refs.append(entry)
				continue
			var row: Dictionary = (entry as Dictionary).duplicate(true)
			if row.get("png", null) is String:
				var bytes: PackedByteArray = _read_blob(dir, String(row["png"]))
				if not bytes.is_empty():
					row["png"] = bytes
			refs.append(row)
		out["pose_references"] = refs
	if String(out.get("turn_discs", "")) == "@pose_references":
		out["turn_discs"] = out.get("pose_references", [])
	return out

static func _write_blob(dir: String, name: String, bytes: PackedByteArray) -> bool:
	var f: FileAccess = FileAccess.open("%s/%s" % [dir, name], FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.close()
	return true

static func _read_blob(dir: String, name: String) -> PackedByteArray:
	if name == "":
		return PackedByteArray()
	var f: FileAccess = FileAccess.open("%s/%s" % [dir, name], FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var bytes: PackedByteArray = f.get_buffer(f.get_length())
	f.close()
	return bytes
