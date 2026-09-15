#pragma once
#include "godot_cpp/variant/all.hpp"

namespace godot {

// Only what `ivory_skin.cpp` reads off an image. Enough to type-check the
// island pass off-engine; not enough to decode anything, and not meant to be.
struct Image {
	enum Format { FORMAT_L8, FORMAT_RGBA8 };
	int get_width() const { return 0; }
	int get_height() const { return 0; }
	Format get_format() const { return FORMAT_RGBA8; }
	void convert(Format) {}
	Ref<Image> duplicate() const { return Ref<Image>(); }
	PackedByteArray get_data() const { return PackedByteArray(); }
};

} // namespace godot
