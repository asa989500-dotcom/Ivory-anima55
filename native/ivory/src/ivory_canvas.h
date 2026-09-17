#ifndef IVORY_CANVAS_H
#define IVORY_CANVAS_H

// Canvas sizes: the list of them, and the arithmetic around choosing one.
//
// ## Why this is in C++ at all, when it is a table of numbers
//
// The table is the least of it. What matters when somebody picks a canvas size
// on a phone is the question nobody asks out loud: **will this project open
// again?** A 4K animation canvas with twenty layers is four hundred megabytes
// of surface before a single stroke is drawn, and on a mid-range Android
// device that is the difference between an app and a crash on the third
// launch. The size chooser is exactly the moment to know that, and the only
// moment when it can still be changed painlessly.
//
// So this holds three things that belong together:
//
//   * **The presets** — every standard the app offers, in one place, so the
//     drawing chooser and the animation chooser cannot drift apart.
//   * **The cost** — how much memory one page at a given size actually takes,
//     which is a multiply and is not guesswork.
//   * **The fit** — the rectangle a preview thumbnail should occupy inside a
//     given box, preserving the aspect ratio. Trivially small and got wrong
//     in every codebase that writes it four times.
//
// None of it is hot. It is here because it is *shared*, and because a number
// that decides whether a project is openable should live somewhere it can be
// tested rather than being re-derived in a panel.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace godot {

class IvoryCanvas : public RefCounted {
	GDCLASS(IvoryCanvas, RefCounted)

protected:
	static void _bind_methods();

public:
	IvoryCanvas() = default;
	~IvoryCanvas() = default;

	// Every offered size, as an array of dictionaries carrying `key`, `w`,
	// `h` and `group`. The group is one of "screen", "print", "square",
	// "social" — used only to lay the chooser out in bands.
	Array presets() const;

	// The presets one kind of project should be shown, in the order they
	// should appear. Animation leads with the video standards; a drawing
	// leads with the print sizes it is most likely to want.
	Array presets_for(const String &kind) const;

	// How much memory one page of this size costs, in bytes, at four bytes a
	// pixel — which is what an RGBA8 surface is.
	double bytes_for(const Vector2i &size, int layers) const;

	// A size held inside what is sensible. Never below the floor, never above
	// the ceiling, and never so lopsided that one side is a hairline: an
	// aspect beyond about thirty to one is almost always a typo and produces
	// a canvas nobody can work on.
	Vector2i sane(const Vector2i &size) const;

	// Where a page of `size` sits inside `box`, centred, at the largest scale
	// that fits with `margin` pixels to spare. This is the preview.
	Rect2 fit(const Vector2i &size, const Vector2 &box, double margin) const;

	// A short human reading of a size: "3840 x 2160 - 16:9". The ratio is
	// reduced properly rather than approximated, so 1600 x 1200 reads 4:3 and
	// not 1.33.
	String describe(const Vector2i &size) const;

	// The reduced aspect ratio, as `Vector2i(w, h)`.
	Vector2i ratio_of(const Vector2i &size) const;

	// A device-aware technical profile used by the project-creation sheet.
	// It keeps the arithmetic for memory, tile size and undo capacity in C++
	// so the UI never invents a different budget from the renderer.
	Dictionary profile(const String &kind, const Vector2i &size,
			int layers, int undo_levels) const;

	static const int FLOOR_SIDE = 64;
	static const int CEIL_SIDE = 8192;
};

} // namespace godot

#endif // IVORY_CANVAS_H
