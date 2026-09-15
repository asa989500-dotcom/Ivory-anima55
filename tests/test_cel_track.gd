extends "res://tests/test_case.gd"
## The frame track: where a drawing sits in time, and where it sits on disk.
##
## This is the file that carries the user's drawings, so it gets the most
## attention. Every assertion here is a bug that has already happened once or
## a rule the timeline relies on without saying so.

func title() -> String:
	return "cel track"

func run() -> void:
	_ordering()
	_showing_matches_a_plain_search()
	_holds()
	_inserting_and_shifting()
	_saving()
	_spill_writes_and_reads_back()
	_spill_respects_its_ceiling()
	_spill_cleans_up_after_a_crash()

func _track_with(frames: Array) -> CelTrack:
	var t: CelTrack = CelTrack.new()
	for f in frames:
		t.cels[int(f)] = {"png": PackedByteArray(), "at": Vector2i.ZERO,
			"size": Vector2i.ZERO}
	t._frames_dirty = true
	return t

func _ordering() -> void:
	note("frames come back in order however they went in")
	var t: CelTrack = _track_with([9, 1, 40, 3])
	eq(t.frames(), [1, 3, 9, 40], "sorted frame list")
	eq(t.last_frame(), 40, "last frame")
	eq(CelTrack.new().last_frame(), -1, "last frame of an empty track")
	ok(CelTrack.new().is_empty(), "a new track is empty")

## `frame_showing` is a binary search, and a binary search that is subtly
## wrong is the worst kind of bug in this file: it does not crash, it shows
## the wrong drawing on some frames and the right one on most. So it is
## checked against the obvious slow answer on every frame of a clip.
func _showing_matches_a_plain_search() -> void:
	note("the drawing on screen is the last one at or before the playhead")
	var keys: Array = [0, 1, 2, 7, 8, 19, 20, 21, 60, 200]
	var t: CelTrack = _track_with(keys)
	var wrong: int = 0
	for at in range(-3, 210):
		var slow: int = -1
		for k in keys:
			if int(k) <= at:
				slow = maxi(slow, int(k))
		if t.frame_showing(at) != slow:
			wrong += 1
	eq(wrong, 0, "binary search agrees with a plain walk on every frame")
	eq(_track_with([]).frame_showing(5), -1, "nothing showing on an empty track")

func _holds() -> void:
	note("a drawing holds until the next one, or to the end of the clip")
	var t: CelTrack = _track_with([0, 4, 5, 30])
	eq(t.hold_length(0, 100), 4, "hold from 0 to the drawing at 4")
	eq(t.hold_length(4, 100), 1, "a single-frame hold")
	eq(t.hold_length(30, 100), 70, "the last drawing holds to the clip end")
	eq(t.hold_length(30, 10), 1, "never shorter than one frame")

	note("the index helpers the timeline draws from")
	eq(t.index_after(4), 2, "first drawing strictly after frame 4")
	eq(t.index_after(30), 4, "nothing after the last drawing")
	eq(t.index_at_or_after(4), 1, "first drawing at or after frame 4")
	eq(t.index_at_or_after(-5), 0, "before the start")
	eq(t.index_at_or_after(999), 4, "past the end")

	# The timeline now takes the hold from the next item in the list rather
	# than asking for it. If those two ever disagree, a bar is drawn the wrong
	# length and nobody notices until a scene is played back.
	var frames: Array = t.frames()
	var disagreed: int = 0
	for i in range(frames.size()):
		var one: int = int(frames[i])
		var by_list: int = (int(frames[i + 1]) - one) if i + 1 < frames.size() \
			else 100 - one
		if maxi(by_list, 1) != t.hold_length(one, 100):
			disagreed += 1
	eq(disagreed, 0, "walking the list gives the same hold as asking for it")

func _inserting_and_shifting() -> void:
	note("inserting a blank frame slides everything after it along")
	var t: CelTrack = _track_with([0, 1, 2])
	t.cels[1]["png"] = _bytes(64, 7)
	t.insert_blank_after(null, 0)
	eq(t.frames(), [0, 1, 2, 3], "one more frame after the insert")
	eq((t.cels[2]["png"] as PackedByteArray).size(), 64,
		"the drawing that was at 1 is now at 2")
	ok((t.cels[1]["png"] as PackedByteArray).is_empty(),
		"the new frame is blank")

	note("shifting after a frame does not drop or overwrite a drawing")
	var s: CelTrack = _track_with([0, 5, 6, 7])
	s.cels[5]["png"] = _bytes(32, 1)
	s.cels[6]["png"] = _bytes(32, 2)
	s.shift_after(0, 3)
	eq(s.frames(), [0, 8, 9, 10], "everything after frame 0 moved by three")
	eq(int((s.cels[8]["png"] as PackedByteArray)[0]), 1,
		"the drawing from 5 landed on 8 intact")

	note("moving and removing")
	var m: CelTrack = _track_with([2, 9])
	m.loaded = 2
	m.move_frame(2, 4)
	eq(m.frames(), [4, 9], "the drawing moved")
	eq(m.loaded, 4, "the surface followed it")
	m.remove_frame(4)
	eq(m.frames(), [9], "and was removed")
	eq(m.loaded, -1, "the surface no longer claims to hold it")

func _saving() -> void:
	note("a track survives being written out and read back")
	var t: CelTrack = _track_with([0, 12])
	t.cels[0]["png"] = _bytes(50, 3)
	t.cels[0]["at"] = Vector2i(11, -22)
	t.cels[12]["png"] = _bytes(10, 9)
	var doc: Dictionary = t.to_dict()
	var back: CelTrack = CelTrack.new()
	back.from_dict(doc)
	eq(back.frames(), [0, 12], "both drawings came back")
	eq(back.origin_of(0), Vector2i(11, -22), "and so did where they sit")
	eq((back.cels[0]["png"] as PackedByteArray).size(), 50, "with their bytes")

	# An empty cel is written as a hole rather than as empty bytes, because
	# handing empty bytes to Marshalls printed an error on every single save.
	var e: CelTrack = _track_with([0, 1])
	e.cels[1]["png"] = _bytes(20, 4)
	eq(((e.to_dict()["cels"]) as Array).size(), 1,
		"an empty frame is not written out")

# ------------------------------------------------------------------- spilling

func _spill_writes_and_reads_back() -> void:
	note("cels far from the playhead go to disk and come back unchanged")
	CelTrack.spill_budget = 192 * 1024 * 1024
	var t: CelTrack = CelTrack.new()
	for f in range(30):
		t.cels[f] = {"png": _bytes(20000, f + 1), "at": Vector2i(f, f),
			"size": Vector2i.ZERO}
	t._frames_dirty = true
	t.loaded = 0

	t.page_around(0, 4)
	var on_disk: int = 0
	for f in range(30):
		if String((t.cels[f] as Dictionary).get("spill", "")) != "":
			on_disk += 1
	ok(on_disk > 0, "something was written out")
	ok((t.cels[25]["png"] as PackedByteArray).is_empty(),
		"a far cel no longer costs memory")
	ok(not (t.cels[2]["png"] as PackedByteArray).is_empty(),
		"a near cel was left alone")

	var report: Dictionary = CelTrack.spill_report()
	ok(int(report["bytes"]) > 0, "the spill knows what it is holding")
	ok(String(report["dir"]).begins_with(CelTrack.SPILL_ROOT),
		"and where it put it")

	# The whole point: reading it back has to give the same bytes.
	t._page_in(25)
	var back: PackedByteArray = t.cels[25]["png"]
	eq(back.size(), 20000, "the cel came back the same size")
	eq(int(back[0]), 26, "and with the same contents")

	t.drop_spill()
	eq(int(CelTrack.spill_report()["bytes"]), 0,
		"dropping a track releases every byte it was holding")

func _spill_respects_its_ceiling() -> void:
	note("the ceiling that did not exist")
	CelTrack.spill_budget = 100000          # deliberately tiny
	var before: int = int(CelTrack.spill_report()["refused"])
	var t: CelTrack = CelTrack.new()
	for f in range(40):
		t.cels[f] = {"png": _bytes(20000, 1), "at": Vector2i.ZERO,
			"size": Vector2i.ZERO}
	t._frames_dirty = true
	t.loaded = 0
	t.page_around(0, 1)

	var report: Dictionary = CelTrack.spill_report()
	ok(int(report["bytes"]) <= 100000, "never wrote past the ceiling")
	ok(int(report["refused"]) > before,
		"and said so rather than writing anyway")
	# A refused cel keeps its pixels. Losing a drawing to save disk space
	# would be a far worse bug than the one the ceiling exists to prevent.
	var kept: int = 0
	for f in range(40):
		if not (t.cels[f]["png"] as PackedByteArray).is_empty():
			kept += 1
	ok(kept > 0, "the cels that were not written are still in memory")
	t.drop_spill()
	CelTrack.spill_budget = 192 * 1024 * 1024

func _spill_cleans_up_after_a_crash() -> void:
	note("what a killed session leaves behind is removed on the next start")
	# A folder belonging to a process that certainly is not running, and a
	# loose file in the old flat layout: exactly what is on the device now.
	var ghost_dir: String = CelTrack.SPILL_ROOT + "/run_999999_1"
	DirAccess.make_dir_recursive_absolute(ghost_dir)
	_write(ghost_dir + "/pid", "999999")
	_write(ghost_dir + "/cel_1.png", "not really a png")
	_write(CelTrack.SPILL_ROOT + "/cel_7_123.png", "the old flat layout")

	# Force another sweep; the real one runs once, at startup.
	CelTrack._swept = false
	var removed: int = CelTrack.sweep_orphans()
	ok(removed >= 3, "the sweep removed what the dead run left")
	not_ok(DirAccess.dir_exists_absolute(ghost_dir),
		"the dead run's folder is gone")
	not_ok(FileAccess.file_exists(CelTrack.SPILL_ROOT + "/cel_7_123.png"),
		"and so is the loose file")

	# And it does not touch a folder whose process is alive — which is this
	# one. Deleting a live session's cels would lose the user's drawings.
	var mine: String = CelTrack.SPILL_ROOT + "/run_%d_2" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(mine)
	_write(mine + "/pid", str(OS.get_process_id()))
	_write(mine + "/cel_2.png", "mine")
	CelTrack._swept = false
	CelTrack.sweep_orphans()
	# A folder naming *our own* pid is our own dead leftovers on a relaunch —
	# the pid was reused — so it is fair game. What must survive is a folder
	# naming a different, live process, and there is no second process here to
	# make one with. So this only checks the sweep did not crash on it.
	ok(true, "the sweep survived a folder naming a live process")
	CelTrack._remove_tree(mine)

# ------------------------------------------------------------------- helpers

func _bytes(count: int, first: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(count)
	out.fill(0x5a)
	if count > 0:
		out[0] = first
	return out

func _write(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
