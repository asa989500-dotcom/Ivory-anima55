#include "ivory_stretchy_export.h"

#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>

using namespace godot;

static String key_string(const String &a, const String &b) {
	return a + String(".") + b;
}

String IvoryStretchyExport::sanitize_name(const String &name) {
	String out;
	for (int i = 0; i < name.length(); ++i) {
		const char32_t c = name[i];
		const bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
				(c >= '0' && c <= '9') || c == '_' || c == '-';
		out += ok ? String::chr(c) : String("_");
	}
	return out.is_empty() ? String("motion") : out;
}

Dictionary IvoryStretchyExport::build_model3(const Dictionary &opts) {
	const String model_name = String(opts.get("model_name", "character"));
	const Array textures = opts.get("texture_files", Array());
	const Array motions = opts.get("motion_files", Array());
	Dictionary refs;
	refs["Moc"] = model_name + String(".moc3");
	refs["Textures"] = textures;
	const String physics = String(opts.get("physics_file", ""));
	const String pose = String(opts.get("pose_file", ""));
	const String display = String(opts.get("display_info_file", ""));
	if (!physics.is_empty()) refs["Physics"] = physics;
	if (!pose.is_empty()) refs["Pose"] = pose;
	if (!display.is_empty()) refs["DisplayInfo"] = display;
	if (!motions.is_empty()) {
		Dictionary idle;
		Array files;
		for (int i = 0; i < motions.size(); ++i) {
			Dictionary file_entry;
			file_entry["File"] = motions[i];
			files.push_back(file_entry);
		}
		idle["Idle"] = files;
		refs["Motions"] = idle;
	}
	Dictionary model;
	model["Version"] = 3;
	model["FileReferences"] = refs;
	Dictionary groups = opts.get("groups", Dictionary());
	Array groups_array;
	Array group_keys = groups.keys();
	for (int i = 0; i < group_keys.size(); ++i) {
		const String k = String(group_keys[i]);
		const Array ids = groups[k];
		if (!ids.is_empty()) {
			Dictionary group_entry;
			group_entry["Target"] = "Parameter";
			group_entry["Name"] = k;
			group_entry["Ids"] = ids;
			groups_array.push_back(group_entry);
		}
	}
	if (!groups_array.is_empty()) model["Groups"] = groups_array;
	const Array hit_areas = opts.get("hit_areas", Array());
	if (!hit_areas.is_empty()) model["HitAreas"] = hit_areas;
	return model;
}

Dictionary IvoryStretchyExport::build_cdi3(const Dictionary &opts) {
	Dictionary result;
	result["Version"] = 3;
	const Array parameters = opts.get("parameters", Array());
	if (!parameters.is_empty()) {
		Array out;
		for (int i = 0; i < parameters.size(); ++i) {
			Dictionary p = parameters[i];
			Dictionary e;
			const String id = String(p.get("id", ""));
			e["Id"] = id;
			e["Name"] = String(p.get("name", id));
			const String group_id = String(p.get("group_id", ""));
			if (!group_id.is_empty()) e["GroupId"] = group_id;
			out.push_back(e);
		}
		result["Parameters"] = out;
	}
	const Array parts = opts.get("parts", Array());
	if (!parts.is_empty()) {
		Array out;
		for (int i = 0; i < parts.size(); ++i) {
			Dictionary p = parts[i];
			const String id = String(p.get("id", ""));
			Dictionary part_entry;
			part_entry["Id"] = id;
			part_entry["Name"] = String(p.get("name", id));
			out.push_back(part_entry);
		}
		result["Parts"] = out;
	}
	return result;
}

static int easing_type(const String &e) {
	if (e == "ease-in" || e == "ease-out" || e == "ease-in-out" || e == "bezier") return 1;
	if (e == "stepped" || e == "step") return 2;
	if (e == "inverse-stepped") return 3;
	return 0;
}

Array IvoryStretchyExport::encode_segments(const Array &keyframes) {
	Array sorted = keyframes.duplicate(true);
	// Godot's Array has no portable inline comparator callback across all
	// supported bindings, so use a small stable insertion sort.
	for (int i = 1; i < sorted.size(); ++i) {
		Dictionary cur = sorted[i];
		const double ct = double(cur.get("time", 0.0));
		int j = i - 1;
		while (j >= 0 && double(Dictionary(sorted[j]).get("time", 0.0)) > ct) {
			sorted[j + 1] = sorted[j];
			--j;
		}
		sorted[j + 1] = cur;
	}
	Array segments;
	if (sorted.is_empty()) return segments;
	Dictionary first = sorted[0];
	segments.push_back(double(first.get("time", 0.0)) / 1000.0);
	segments.push_back(double(first.get("value", 0.0)));
	for (int i = 1; i < sorted.size(); ++i) {
		Dictionary cur = sorted[i];
		Dictionary prev = sorted[i - 1];
		const double t = double(cur.get("time", 0.0)) / 1000.0;
		const double pt = double(prev.get("time", 0.0)) / 1000.0;
		const double pv = double(prev.get("value", 0.0));
		const double v = double(cur.get("value", 0.0));
		const int type = easing_type(String(cur.get("easing", "linear")));
		segments.push_back(type);
		if (type == 1) {
			const double dt = t - pt;
			segments.push_back(pt + dt / 3.0);
			segments.push_back(pv);
			segments.push_back(pt + 2.0 * dt / 3.0);
			segments.push_back(v);
			segments.push_back(t);
			segments.push_back(v);
		} else {
			segments.push_back(t);
			segments.push_back(v);
		}
	}
	return segments;
}

Dictionary IvoryStretchyExport::build_motion3(const Dictionary &animation, const Dictionary &parameter_map) {
	const double duration = double(animation.get("duration", 2000.0)) / 1000.0;
	const double fps = double(animation.get("fps", 24.0));
	Array curves;
	int segment_count = 0;
	int point_count = 0;
	const Array tracks = animation.get("tracks", Array());
	for (int i = 0; i < tracks.size(); ++i) {
		Dictionary track = tracks[i];
		const String node_id = String(track.get("nodeId", ""));
		const String property = String(track.get("property", ""));
		const String key = key_string(node_id, property);
		String id;
		String target;
		if (parameter_map.has(key)) {
			id = String(parameter_map[key]);
			target = "Parameter";
		} else if (property == "opacity") {
			id = node_id;
			target = "PartOpacity";
		} else {
			continue;
		}
		Array kfs = track.get("keyframes", Array());
		if (property == "mesh_verts") {
			if (!parameter_map.has(key) || kfs.size() < 2) continue;
			Array idx_kfs;
			for (int k = 0; k < kfs.size(); ++k) {
				Dictionary q = kfs[k];
				Dictionary idx_entry;
				idx_entry["time"] = q.get("time", 0.0);
				idx_entry["value"] = k;
				idx_entry["easing"] = q.get("easing", "linear");
				idx_kfs.push_back(idx_entry);
			}
			kfs = idx_kfs;
			target = "Parameter";
		}
		Array seg = encode_segments(kfs);
		if (seg.size() == 0) continue;
		int sc = 0;
		int pc = 1;
		int j = 2;
		while (j < seg.size()) {
			const int typ = int(seg[j]);
			++sc; ++j;
			if (typ == 1) { pc += 3; j += 6; }
			else { pc += 1; j += 2; }
		}
		segment_count += sc;
		point_count += pc;
		Dictionary curve_entry;
		curve_entry["Target"] = target;
		curve_entry["Id"] = id;
		curve_entry["Segments"] = seg;
		curves.push_back(curve_entry);
	}
	Dictionary meta;
	meta["Duration"] = duration;
	meta["Fps"] = fps;
	meta["Loop"] = true;
	meta["AreBeziersRestricted"] = false;
	meta["CurveCount"] = curves.size();
	meta["TotalSegmentCount"] = segment_count;
	meta["TotalPointCount"] = point_count;
	meta["UserDataCount"] = 0;
	meta["TotalUserDataSize"] = 0;
	Dictionary final_out;
	final_out["Version"] = 3;
	final_out["Meta"] = meta;
	final_out["Curves"] = curves;
	return final_out;
}

String IvoryStretchyExport::model3_json(const Dictionary &opts) const {
	return JSON::stringify(build_model3(opts), "  ");
}

String IvoryStretchyExport::cdi3_json(const Dictionary &opts) const {
	return JSON::stringify(build_cdi3(opts), "  ");
}

String IvoryStretchyExport::motion3_json(const Dictionary &animation, const Dictionary &parameter_map) const {
	return JSON::stringify(build_motion3(animation, parameter_map), "  ");
}

Dictionary IvoryStretchyExport::build_stretchy_tracks(const Dictionary &project) {
	Dictionary doc;
	doc["version"] = 1;
	doc["schema"] = "ivory.stretchy.tracks.v1";

	Array audio_out;
	const Array audio = project.get("audio_tracks", project.get("audio", Array()));
	for (int i = 0; i < audio.size(); ++i) {
		Dictionary a = audio[i];
		Dictionary out;
		out["id"] = String(a.get("id", String("audio_%02d") % (int64_t)i));
		out["source"] = String(a.get("source", a.get("path", "")));
		out["start_us"] = int64_t(a.get("start_us", int64_t(double(a.get("start", 0.0)) * 1000000.0)));
		out["end_us"] = int64_t(a.get("end_us", int64_t(double(a.get("end", 0.0)) * 1000000.0)));
		out["gain"] = double(a.get("gain", 1.0));
		out["enabled"] = bool(a.get("enabled", true));
		audio_out.push_back(out);
	}
	doc["audio_track"] = audio_out;

	Dictionary perf;
	perf["enabled"] = bool(project.get("performance_track_enabled", true));
	perf["sample_every_frames"] = std::max(int(project.get("performance_sample_every_frames", 1)), 1);
	perf["frame_budget_ms"] = double(project.get("performance_frame_budget_ms", 1000.0 / std::max(int(project.get("fps", 24)), 1)));
	perf["metrics"] = Array({"render_ms", "audio_ms", "submit_ms", "total_ms", "dropped_frames"});
	doc["performance_track"] = perf;

	Dictionary mp4;
	mp4["container"] = "mp4";
	mp4["audio_track_source"] = "audio_track";
	mp4["audio_codec"] = "aac";
	mp4["audio_sample_rate"] = 48000;
	mp4["audio_channels"] = 2;
	mp4["performance_source"] = "performance_track";
	mp4["verification_required"] = true;
	doc["mp4_export"] = mp4;
	return doc;
}

Dictionary IvoryStretchyExport::build_track_document(const Dictionary &project) const {
	return build_stretchy_tracks(project);
}

Dictionary IvoryStretchyExport::target_plan() const {
	const String os_name = OS::get_singleton()->get_name();
	Dictionary result;
	result["os"] = os_name;
	if (os_name == "Android" || os_name == "iOS") {
		result["needs_dialog"] = false;
		result["default_dir"] = OS::get_singleton()->get_system_dir(OS::SYSTEM_DIR_DOCUMENTS);
		return result;
	}
	if (os_name == "Windows" || os_name == "macOS" || os_name == "Linux" ||
			os_name == "FreeBSD" || os_name == "NetBSD" || os_name == "OpenBSD" ||
			os_name == "BSD") {
		String documents = OS::get_singleton()->get_system_dir(OS::SYSTEM_DIR_DOCUMENTS);
		if (documents.is_empty()) documents = OS::get_singleton()->get_user_data_dir();
		result["needs_dialog"] = true;
		result["default_dir"] = documents;
		return result;
	}
	result["needs_dialog"] = false;
	result["default_dir"] = String("user://");
	return result;
}

Dictionary IvoryStretchyExport::write_text(const String &directory, const String &filename,
		const String &text) const {
	return write_bytes(directory, filename, text.to_utf8_buffer());
}

Dictionary IvoryStretchyExport::write_bytes(const String &directory, const String &filename,
		const PackedByteArray &bytes) const {
	const String path = directory.path_join(filename);
	Dictionary result;
	result["path"] = path;
	Ref<FileAccess> file = FileAccess::open(path, FileAccess::WRITE);
	if (file.is_null()) {
		result["ok"] = false;
		result["error"] = String("Could not open export path for writing.");
		return result;
	}
	file->store_buffer(bytes);
	file->close();
	result["ok"] = true;
	result["error"] = String();
	return result;
}

Dictionary IvoryStretchyExport::smart_save_text(const String &filename, const String &text) const {
	const Dictionary plan = target_plan();
	if (bool(plan.get("needs_dialog", false))) {
		Dictionary result;
		result["ok"] = false;
		result["path"] = String();
		result["error"] = String("This platform requires a folder choice.");
		result["needs_dialog"] = true;
		result["default_dir"] = plan.get("default_dir", String());
		return result;
	}
	Dictionary result = write_text(plan.get("default_dir", String("user://")), filename, text);
	result["needs_dialog"] = false;
	return result;
}


Dictionary IvoryStretchyExport::export_json_bundle(const Dictionary &project, const String &directory) const {
	Dictionary result;
	if (!DirAccess::make_dir_recursive_absolute(directory)) {
		result["ok"] = false;
		result["error"] = "Could not create export directory.";
		return result;
	}
	const String model_name = String(project.get("model_name", "character"));
	Array textures;
	const Array layers = project.get("layers", Array());
	for (int i = 0; i < layers.size(); ++i) {
		Dictionary l = layers[i];
		textures.push_back(String(l.get("name", String("texture_%02d.png") % (int64_t)i)).get_basename() + ".png");
	}
	Dictionary model_opts;
	model_opts["model_name"] = model_name;
	model_opts["texture_files"] = textures;
	const Array params = project.get("parameters", Array());
	Array cdi_params;
	for (int i = 0; i < params.size(); ++i) {
		Dictionary p = params[i];
		Dictionary cdi_entry;
		cdi_entry["id"] = p.get("id", "");
		cdi_entry["name"] = p.get("name", p.get("id", ""));
		cdi_entry["group_id"] = p.get("groupId", "");
		cdi_params.push_back(cdi_entry);
	}
	Dictionary cdi_opts;
	cdi_opts["parameters"] = cdi_params;
	Dictionary cdi_parts;
	Array anim_files;
	const Array animations = project.get("animations", Array());
	for (int i = 0; i < animations.size(); ++i) {
		Dictionary a = animations[i];
		const String filename = sanitize_name(String(a.get("name", String("motion_%02d") % (int64_t)i))) + ".motion3.json";
		const String path = directory.path_join(filename);
		Ref<FileAccess> f = FileAccess::open(path, FileAccess::WRITE);
		if (f.is_null()) {
			result["ok"] = false; result["error"] = String("Could not write ") + path; return result;
		}
		Dictionary empty_map;
		f->store_string(motion3_json(a, empty_map));
		f->close();
		anim_files.push_back(filename);
	}
	const String cdi_path = directory.path_join(model_name + String(".cdi3.json"));
	Ref<FileAccess> cdi_f = FileAccess::open(cdi_path, FileAccess::WRITE);
	if (cdi_f.is_null()) { result["ok"] = false; result["error"] = "Could not write cdi3."; return result; }
	cdi_f->store_string(cdi3_json(cdi_opts)); cdi_f->close();
	model_opts["display_info_file"] = model_name + String(".cdi3.json");
	model_opts["motion_files"] = anim_files;
	const String model_path = directory.path_join(model_name + String(".model3.json"));
	Ref<FileAccess> model_f = FileAccess::open(model_path, FileAccess::WRITE);
	if (model_f.is_null()) { result["ok"] = false; result["error"] = "Could not write model3."; return result; }
	model_f->store_string(model3_json(model_opts)); model_f->close();
	const String tracks_path = directory.path_join("stretchy_tracks.json");
	Ref<FileAccess> tracks_f = FileAccess::open(tracks_path, FileAccess::WRITE);
	if (tracks_f.is_null()) { result["ok"] = false; result["error"] = "Could not write stretchy tracks."; return result; }
	tracks_f->store_string(JSON::stringify(build_stretchy_tracks(project), "  "));
	tracks_f->close();
	result["tracks_file"] = tracks_path;
	result["audio_track"] = true;
	result["performance_track"] = true;
	result["mp4_audio_codec"] = "aac";
	result["mp4_performance_verification"] = true;
	result["ok"] = true;
	result["directory"] = directory;
	result["binary_writers"] = "not ported: moc3/cmo3/can3";
	return result;
}

void IvoryStretchyExport::_bind_methods() {
	ClassDB::bind_method(D_METHOD("model3_json", "opts"), &IvoryStretchyExport::model3_json);
	ClassDB::bind_method(D_METHOD("cdi3_json", "opts"), &IvoryStretchyExport::cdi3_json);
	ClassDB::bind_method(D_METHOD("motion3_json", "animation", "parameter_map"), &IvoryStretchyExport::motion3_json, Dictionary());
	ClassDB::bind_method(D_METHOD("export_json_bundle", "project", "directory"), &IvoryStretchyExport::export_json_bundle);
	ClassDB::bind_method(D_METHOD("build_track_document", "project"), &IvoryStretchyExport::build_track_document);
	ClassDB::bind_method(D_METHOD("target_plan"), &IvoryStretchyExport::target_plan);
	ClassDB::bind_method(D_METHOD("write_bytes", "directory", "filename", "bytes"), &IvoryStretchyExport::write_bytes);
	ClassDB::bind_method(D_METHOD("write_text", "directory", "filename", "text"), &IvoryStretchyExport::write_text);
	ClassDB::bind_method(D_METHOD("smart_save_text", "filename", "text"), &IvoryStretchyExport::smart_save_text);
}
