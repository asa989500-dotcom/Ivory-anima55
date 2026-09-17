extends RefCounted
class_name StretchyExportTarget

## Compatibility bridge only. Export-target policy and file writing live in
## IvoryStretchyExport (C++); this class keeps the existing GDScript call shape
## for builds where the native extension is optional.

static func _native() -> Object:
	return Native.stretchy_export()

static func plan() -> Dictionary:
	var native := _native()
	if native == null:
		return {
			"os": OS.get_name(),
			"needs_dialog": false,
			"default_dir": "user://",
			"native_unavailable": true,
		}
	return native.target_plan()

static func write_to(dir: String, filename: String, bytes: PackedByteArray) -> Dictionary:
	var native := _native()
	if native == null:
		return {"ok": false, "path": dir.path_join(filename), "error": "Native C++ exporter unavailable."}
	return native.write_bytes(dir, filename, bytes)

static func write_text(dir: String, filename: String, text: String) -> Dictionary:
	var native := _native()
	if native == null:
		return {"ok": false, "path": dir.path_join(filename), "error": "Native C++ exporter unavailable."}
	return native.write_text(dir, filename, text)

static func smart_save_text(filename: String, text: String) -> Dictionary:
	var native := _native()
	if native == null:
		return {"ok": false, "path": "", "error": "Native C++ exporter unavailable."}
	return native.smart_save_text(filename, text)
