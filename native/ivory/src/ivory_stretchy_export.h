#ifndef IVORY_STRETCHY_EXPORT_H
#define IVORY_STRETCHY_EXPORT_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include "ivory_stretchy_tracks.h"

namespace godot {

class IvoryStretchyExport : public RefCounted {
	GDCLASS(IvoryStretchyExport, RefCounted)

protected:
	static void _bind_methods();

private:
	static String sanitize_name(const String &name);
	static Dictionary build_model3(const Dictionary &opts);
	static Dictionary build_cdi3(const Dictionary &opts);
	static Array encode_segments(const Array &keyframes);
	static Dictionary build_motion3(const Dictionary &animation, const Dictionary &parameter_map);
	static Dictionary build_stretchy_tracks(const Dictionary &project);

public:
	IvoryStretchyExport() = default;
	~IvoryStretchyExport() = default;

	String model3_json(const Dictionary &opts) const;
	String cdi3_json(const Dictionary &opts) const;
	String motion3_json(const Dictionary &animation, const Dictionary &parameter_map = Dictionary()) const;

	// Writes the three exact JSON artifacts represented by Stretchy Studio's
	// model3json.js, cdi3json.js and motion3json.js into one directory.
	// Binary Cubism writers are intentionally not fabricated here.
	Dictionary export_json_bundle(const Dictionary &project, const String &directory) const;
	Dictionary build_track_document(const Dictionary &project) const;
	Dictionary target_plan() const;
	Dictionary write_bytes(const String &directory, const String &filename,
			const PackedByteArray &bytes) const;
	Dictionary write_text(const String &directory, const String &filename, const String &text) const;
	Dictionary smart_save_text(const String &filename, const String &text) const;
};

} // namespace godot

#endif // IVORY_STRETCHY_EXPORT_H
