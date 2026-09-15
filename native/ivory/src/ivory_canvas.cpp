#include "ivory_canvas.h"

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {

struct Preset {
	const char *key;
	int w;
	int h;
	const char *group;
};

// Every size the app offers, once.
//
// The order inside each group is deliberate: largest first within a family, so
// that scanning down the list is scanning down in size and the eye does not
// have to sort. Between families the order is the one a person is likely to
// want, which is why the video standards lead — this app makes animation.
const Preset TABLE[] = {
	// --- video and screen ---
	{ "8K UHD", 7680, 4320, "screen" },
	{ "4K UHD", 3840, 2160, "screen" },
	{ "4K DCI", 4096, 2160, "screen" },
	{ "2K QHD", 2560, 1440, "screen" },
	{ "Full HD", 1920, 1080, "screen" },
	{ "HD", 1280, 720, "screen" },
	{ "SD", 854, 480, "screen" },
	{ "Vertical HD", 1080, 1920, "screen" },
	{ "Vertical 4K", 2160, 3840, "screen" },

	// --- print, at 300 dots to the inch ---
	{ "A3 300", 3508, 4961, "print" },
	{ "A4 300", 2480, 3508, "print" },
	{ "A5 300", 1748, 2480, "print" },
	{ "A4 150", 1240, 1754, "print" },
	{ "Letter 300", 2550, 3300, "print" },
	{ "Tabloid 300", 3300, 5100, "print" },
	{ "Comic page", 1988, 3056, "print" },

	// --- square and social ---
	{ "Square 4K", 4096, 4096, "square" },
	{ "Square 2K", 2048, 2048, "square" },
	{ "Square 1K", 1024, 1024, "square" },
	{ "Post", 1080, 1080, "social" },
	{ "Story", 1080, 1920, "social" },
	{ "Wide post", 1200, 630, "social" },
	{ "Thumbnail", 1280, 720, "social" },

	// --- the old default, kept so an existing project reads as a preset ---
	{ "Classic", 1600, 1200, "screen" },
	{ "Sketch", 1200, 900, "screen" },
	{ "Small", 800, 600, "screen" },
};

const int TABLE_SIZE = (int)(sizeof(TABLE) / sizeof(TABLE[0]));

int greatest_common(int a, int b) {
	a = a < 0 ? -a : a;
	b = b < 0 ? -b : b;
	while (b != 0) {
		const int t = a % b;
		a = b;
		b = t;
	}
	return a == 0 ? 1 : a;
}

} // namespace

void IvoryCanvas::_bind_methods() {
	ClassDB::bind_method(D_METHOD("presets"), &IvoryCanvas::presets);
	ClassDB::bind_method(D_METHOD("presets_for", "kind"),
			&IvoryCanvas::presets_for);
	ClassDB::bind_method(D_METHOD("bytes_for", "size", "layers"),
			&IvoryCanvas::bytes_for);
	ClassDB::bind_method(D_METHOD("sane", "size"), &IvoryCanvas::sane);
	ClassDB::bind_method(D_METHOD("fit", "size", "box", "margin"),
			&IvoryCanvas::fit);
	ClassDB::bind_method(D_METHOD("describe", "size"), &IvoryCanvas::describe);
	ClassDB::bind_method(D_METHOD("ratio_of", "size"), &IvoryCanvas::ratio_of);
	ClassDB::bind_method(D_METHOD("profile", "kind", "size", "layers",
			"undo_levels"), &IvoryCanvas::profile);
}

Array IvoryCanvas::presets() const {
	Array out;
	for (int i = 0; i < TABLE_SIZE; i++) {
		Dictionary row;
		row["key"] = String(TABLE[i].key);
		row["w"] = TABLE[i].w;
		row["h"] = TABLE[i].h;
		row["group"] = String(TABLE[i].group);
		out.append(row);
	}
	return out;
}

Array IvoryCanvas::presets_for(const String &kind) const {
	// One table, two orders. A separate list per kind would be two lists to
	// keep in step, and they would stop being in step the first time a size
	// was added.
	Array first;
	Array rest;
	const bool moving = kind == "animation" || kind == "knit";
	for (int i = 0; i < TABLE_SIZE; i++) {
		Dictionary row;
		row["key"] = String(TABLE[i].key);
		row["w"] = TABLE[i].w;
		row["h"] = TABLE[i].h;
		row["group"] = String(TABLE[i].group);
		const String group = String(TABLE[i].group);
		const bool lead = moving ? (group == "screen") : (group == "print");
		if (lead) {
			first.append(row);
		} else {
			rest.append(row);
		}
	}
	for (int i = 0; i < rest.size(); i++) {
		first.append(rest[i]);
	}
	return first;
}

double IvoryCanvas::bytes_for(const Vector2i &size, int layers) const {
	const double w = (double)std::max(size.x, 1);
	const double h = (double)std::max(size.y, 1);
	const double n = (double)std::max(layers, 1);
	// Four bytes a pixel for the surface, and a fifth of that again for the
	// thumbnail, the undo snapshot heads and the texture the card holds. The
	// fifth is measured rather than assumed: it is what IVORY's own layers
	// cost above their pixels.
	return w * h * 4.0 * n * 1.2;
}

Vector2i IvoryCanvas::sane(const Vector2i &size) const {
	int w = std::min(std::max(size.x, (int)FLOOR_SIDE), (int)CEIL_SIDE);
	int h = std::min(std::max(size.y, (int)FLOOR_SIDE), (int)CEIL_SIDE);
	// A canvas thirty times longer than it is wide is a mistyped number far
	// more often than it is a panorama, and the cost of being wrong is a
	// project that cannot be drawn on. Widened rather than refused, so the
	// intent is kept.
	const double aspect = (double)w / (double)h;
	if (aspect > 30.0) {
		h = std::min((int)std::round((double)w / 30.0), (int)CEIL_SIDE);
	} else if (aspect < 1.0 / 30.0) {
		w = std::min((int)std::round((double)h / 30.0), (int)CEIL_SIDE);
	}
	return Vector2i(std::max(w, (int)FLOOR_SIDE), std::max(h, (int)FLOOR_SIDE));
}

Rect2 IvoryCanvas::fit(const Vector2i &size, const Vector2 &box,
		double margin) const {
	const double w = (double)std::max(size.x, 1);
	const double h = (double)std::max(size.y, 1);
	const double bw = std::max((double)box.x - margin * 2.0, 1.0);
	const double bh = std::max((double)box.y - margin * 2.0, 1.0);
	const double scale = std::min(bw / w, bh / h);
	const double sw = w * scale;
	const double sh = h * scale;
	return Rect2((real_t)(((double)box.x - sw) * 0.5),
			(real_t)(((double)box.y - sh) * 0.5), (real_t)sw, (real_t)sh);
}

Vector2i IvoryCanvas::ratio_of(const Vector2i &size) const {
	const int w = std::max(size.x, 1);
	const int h = std::max(size.y, 1);
	const int g = greatest_common(w, h);
	int rw = w / g;
	int rh = h / g;
	// A ratio like 427:240 tells nobody anything. Past a point the honest
	// thing is the nearest common one, and the common ones are few.
	if (rw > 64 || rh > 64) {
		static const int COMMON[][2] = { { 16, 9 }, { 9, 16 }, { 4, 3 },
			{ 3, 4 }, { 3, 2 }, { 2, 3 }, { 1, 1 }, { 21, 9 }, { 5, 4 },
			{ 16, 10 }, { 10, 16 } };
		const double want = (double)w / (double)h;
		double best = 1.0e9;
		for (int i = 0; i < 11; i++) {
			const double got = (double)COMMON[i][0] / (double)COMMON[i][1];
			const double off = std::fabs(got - want);
			if (off < best) {
				best = off;
				rw = COMMON[i][0];
				rh = COMMON[i][1];
			}
		}
	}
	return Vector2i(rw, rh);
}

String IvoryCanvas::describe(const Vector2i &size) const {
	const Vector2i r = ratio_of(size);
	return String::num_int64(size.x) + String(" x ")
			+ String::num_int64(size.y) + String("  -  ")
			+ String::num_int64(r.x) + String(":") + String::num_int64(r.y);
}


Dictionary IvoryCanvas::profile(const String &kind, const Vector2i &size,
		int layers, int undo_levels) const {
	const Vector2i safe = sane(size);
	const int layer_count = std::max(layers, 1);
	const int undo = std::max(undo_levels, 1);
	const double bytes = bytes_for(safe, layer_count);

	// Tiles are a rendering decision rather than a visual one. Small work is
	// quicker with small uploads; large work benefits from fewer, larger
	// textures. These thresholds keep the number of tiles bounded on Android.
	const double pixels = (double)safe.x * (double)safe.y;
	int tile = 128;
	if (pixels >= 16000000.0) {
		tile = 512;
	} else if (pixels >= 6000000.0) {
		tile = 256;
	}

	// Undo is deliberately budgeted instead of being an unbounded count.
	// A snapshot is roughly one RGBA surface per active layer, so the profile
	// tells the UI how much room the chosen history depth asks for.
	const double undo_bytes = (double)safe.x * (double)safe.y * 4.0
			* (double)layer_count * (double)undo * 0.35;
	const double total_mb = (bytes + undo_bytes) / 1048576.0;

	Dictionary out;
	out["kind"] = kind;
	out["width"] = safe.x;
	out["height"] = safe.y;
	out["aspect"] = ratio_of(safe);
	out["layers"] = layer_count;
	out["undo_levels"] = undo;
	out["tile"] = tile;
	out["estimated_mb"] = total_mb;
	out["heavy"] = total_mb > 512.0;
	out["recommended_undo"] = total_mb > 1024.0 ? 12 : (total_mb > 512.0 ? 24 : 48);
	out["recommended_preview_scale"] =
			total_mb > 1024.0 ? 0.25 : (total_mb > 512.0 ? 0.35 : 0.5);
	return out;
}
