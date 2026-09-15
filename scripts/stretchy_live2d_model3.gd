extends RefCounted
class_name StretchyModel3

## Builds a `.model3.json` manifest: the root file a Live2D runtime opens
## first to find everything else (moc3, textures, motions, physics...).
##
## A faithful port of Stretchy Studio's `src/io/live2d/model3json.js` —
## small and purely structural, so unlike the binary writers there is
## nothing lossy about doing it directly in GDScript's own `Dictionary`/
## `JSON` types.

## opts: {
##   "model_name": String,
##   "texture_files": Array[String],
##   "motion_files": Array[String] (optional),
##   "physics_file": String (optional),
##   "pose_file": String (optional),
##   "display_info_file": String (optional),
##   "groups": Dictionary (optional, e.g. {"LipSync": [...], "EyeBlink": [...]}),
##   "hit_areas": Array[Dictionary] (optional, e.g. [{"Id": "Head", "Name": "Head"}]),
## }
## Returns the JSON-serializable Dictionary; use `to_json` to get the text.
static func build(opts: Dictionary) -> Dictionary:
	var model_name: String = opts.get("model_name", "character")
	var texture_files: Array = opts.get("texture_files", [])
	var motion_files: Array = opts.get("motion_files", [])
	var physics_file: String = opts.get("physics_file", "")
	var pose_file: String = opts.get("pose_file", "")
	var display_info_file: String = opts.get("display_info_file", "")
	var groups: Dictionary = opts.get("groups", {})
	var hit_areas: Array = opts.get("hit_areas", [])

	var file_references := {
		"Moc": "%s.moc3" % model_name,
		"Textures": texture_files,
	}
	if physics_file != "":
		file_references["Physics"] = physics_file
	if pose_file != "":
		file_references["Pose"] = pose_file
	if display_info_file != "":
		file_references["DisplayInfo"] = display_info_file
	if not motion_files.is_empty():
		file_references["Motions"] = _build_motion_groups(motion_files)

	var model := {
		"Version": 3,
		"FileReferences": file_references,
	}

	var groups_array := []
	for group_name in groups.keys():
		var ids: Array = groups[group_name]
		if not ids.is_empty():
			groups_array.append({
				"Target": "Parameter",
				"Name": group_name,
				"Ids": ids,
			})
	if not groups_array.is_empty():
		model["Groups"] = groups_array

	if not hit_areas.is_empty():
		model["HitAreas"] = hit_areas

	return model

## All motion files under one "Idle" group, same simplification the
## reference makes: a name-prefix grouping scheme was never implemented
## there either, just this default.
static func _build_motion_groups(motion_files: Array) -> Dictionary:
	var out := {"Idle": []}
	for file in motion_files:
		out["Idle"].append({"File": file})
	return out

## `JSON.stringify(model, null, 2)`'s Godot equivalent: two-space indent, so
## a person opening the file by hand can actually read it.
static func to_json(opts: Dictionary) -> String:
	return JSON.stringify(build(opts), "  ")
